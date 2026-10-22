"""Efoc hourly reminders.

At the top of each hour, sends a push notification to everyone with
"Hourly reminders" on who hasn't recorded a clip for the current hour yet.
Quiet hours are skipped.

Runs from .github/workflows/remind.yml, but works the same from a laptop:

    export SUPABASE_URL=https://<project>.supabase.co
    export SUPABASE_SERVICE_ROLE_KEY=...
    export FIREBASE_SERVICE_ACCOUNT="$(cat service-account.json)"
    python worker/remind.py              # current hour
    python worker/remind.py --dry-run    # print who would be reminded
    python worker/remind.py --hour 14    # pretend it's 2 PM
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys
from zoneinfo import ZoneInfo

import requests
from google.auth.transport.requests import Request
from google.oauth2 import service_account

SUPABASE_URL = os.environ.get("SUPABASE_URL", "").rstrip("/")
SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
SERVICE_ACCOUNT = os.environ.get("FIREBASE_SERVICE_ACCOUNT", "")

# Same zone the stitcher uses: clips are dated by the phone's local day.
APP_TZ = ZoneInfo(os.environ.get("APP_TZ", "Asia/Kuala_Lumpur"))

# Reminders go out from FIRST_HOUR:00 up to and including LAST_HOUR:00.
FIRST_HOUR = int(os.environ.get("REMIND_FIRST_HOUR", "8"))
LAST_HOUR = int(os.environ.get("REMIND_LAST_HOUR", "22"))

APP_URL = os.environ.get("APP_URL", "https://efoc.party/")
FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"

FCM_ERROR_TYPE = "type.googleapis.com/google.firebase.fcm.v1.FcmError"


def is_dead_token(status: str, code: str | None, message: str) -> bool:
    """True only when FCM says the device itself is gone.

    INVALID_ARGUMENT also covers a malformed message, which must not cost
    a working phone its registration, so it only counts when FCM blames
    the token.
    """
    if code == "UNREGISTERED" or status == "NOT_FOUND":
        return True
    return status == "INVALID_ARGUMENT" and "registration token" in message.lower()


def _headers() -> dict:
    return {"apikey": SERVICE_KEY, "Authorization": f"Bearer {SERVICE_KEY}"}


def rest_get(table: str, params: dict) -> list[dict]:
    r = requests.get(
        f"{SUPABASE_URL}/rest/v1/{table}",
        headers=_headers(),
        params=params,
        timeout=30,
    )
    r.raise_for_status()
    return r.json()


def rest_delete(table: str, params: dict) -> None:
    r = requests.delete(
        f"{SUPABASE_URL}/rest/v1/{table}",
        headers=_headers(),
        params=params,
        timeout=30,
    )
    r.raise_for_status()


def claim_hour(hour_key: str) -> bool:
    """True if this run is the first for the hour. Both GitHub's schedule
    and cron-job.org can start a run; only the first one sends."""
    try:
        r = requests.post(
            f"{SUPABASE_URL}/rest/v1/reminder_sends",
            headers={
                **_headers(),
                "Content-Type": "application/json",
                "Prefer": "resolution=ignore-duplicates,return=representation",
            },
            params={"on_conflict": "hour_key"},
            json={"hour_key": hour_key},
            timeout=30,
        )
        r.raise_for_status()
        return bool(r.json())
    except Exception as e:
        # Table missing or unreachable: better a rare double than no reminder.
        print(f"Couldn't check for an earlier run this hour ({e}); sending anyway.",
              file=sys.stderr)
        return True


def in_list(values: list[str]) -> str:
    return "in.(" + ",".join(values) + ")"


def label_for(hour: int) -> str:
    if hour == 0:
        return "12 AM"
    if hour < 12:
        return f"{hour} AM"
    if hour == 12:
        return "12 PM"
    return f"{hour - 12} PM"


def fcm_session() -> tuple[requests.Session, str]:
    info = json.loads(SERVICE_ACCOUNT)
    creds = service_account.Credentials.from_service_account_info(
        info, scopes=[FCM_SCOPE]
    )
    creds.refresh(Request())
    s = requests.Session()
    s.headers["Authorization"] = f"Bearer {creds.token}"
    return s, info["project_id"]


def send(session: requests.Session, project: str, token: str,
         hour: int) -> tuple[str, str | None, str] | None:
    """Returns None on success, or FCM's (status, error code, message)."""
    title = f"It's {label_for(hour)} 🎬"
    body = "Record your 3 seconds for this hour."
    msg = {
        "message": {
            "token": token,
            "notification": {"title": title, "body": body},
            "webpush": {
                "notification": {
                    "icon": "/icons/Icon-192.png",
                    # White mug silhouette for Android's status bar.
                    "badge": "/icons/badge-96.png",
                    # One reminder on screen at a time; a new hour replaces
                    # an ignored one instead of stacking.
                    "tag": "efoc-hourly",
                    "renotify": True,
                },
                "fcm_options": {"link": APP_URL},
            },
            "android": {
                "priority": "high",
                "notification": {"tag": "efoc-hourly"},
            },
        }
    }
    r = session.post(
        f"https://fcm.googleapis.com/v1/projects/{project}/messages:send",
        json=msg,
        timeout=30,
    )
    if r.ok:
        return None
    try:
        err = r.json()["error"]
        code = next(
            (d.get("errorCode") for d in err.get("details", [])
             if d.get("@type") == FCM_ERROR_TYPE),
            None,
        )
        return err.get("status", f"HTTP {r.status_code}"), code, err.get("message", "")
    except Exception:
        return f"HTTP {r.status_code}", None, r.text[:200]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--hour", type=int, help="Override the current hour (0-23)")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--force", action="store_true",
                    help="send even if this hour's reminders already went out")
    args = ap.parse_args()

    if not SUPABASE_URL or not SERVICE_KEY:
        print("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required", file=sys.stderr)
        return 1

    now = dt.datetime.now(APP_TZ)
    hour = now.hour if args.hour is None else args.hour
    today = now.date().isoformat()

    if not FIRST_HOUR <= hour <= LAST_HOUR:
        print(f"{label_for(hour)} is in quiet hours, nothing to send.")
        return 0

    opted_in = [
        p["id"]
        for p in rest_get("profiles", {"select": "id", "reminders_enabled": "eq.true"})
    ]
    if not opted_in:
        print("Nobody has reminders on.")
        return 0

    # Anyone who already recorded this hour (in any Log) doesn't need a nudge.
    done = {
        c["user_id"]
        for c in rest_get(
            "clips",
            {
                "select": "user_id",
                "recorded_on": f"eq.{today}",
                "hour_of_day": f"eq.{hour}",
                "user_id": in_list(opted_in),
            },
        )
    }
    targets = [u for u in opted_in if u not in done]
    if not targets:
        print(f"Everyone with reminders on has recorded {label_for(hour)}.")
        return 0

    tokens = rest_get(
        "push_tokens",
        {"select": "token,user_id", "user_id": in_list(targets)},
    )
    print(
        f"{label_for(hour)}: {len(opted_in)} opted in, {len(done)} already "
        f"recorded, {len(tokens)} device(s) to remind."
    )
    if args.dry_run or not tokens:
        return 0

    if not SERVICE_ACCOUNT:
        print("FIREBASE_SERVICE_ACCOUNT is required to send", file=sys.stderr)
        return 1

    if not args.force and not claim_hour(f"{today}T{hour:02d}"):
        print(f"{label_for(hour)} reminders already went out this hour.")
        return 0

    session, project = fcm_session()
    sent = failed = removed = 0
    for t in tokens:
        err = send(session, project, t["token"], hour)
        if err is None:
            sent += 1
            continue
        status, code, message = err
        reason = f"{status}{f'/{code}' if code else ''}: {message}"
        if is_dead_token(status, code, message):
            rest_delete("push_tokens", {"token": f"eq.{t['token']}"})
            removed += 1
            print(f"  removed dead device for {t['user_id']} ({reason})",
                  file=sys.stderr)
        else:
            failed += 1
            print(f"  send failed for {t['user_id']} ({reason})", file=sys.stderr)

    print(f"Sent {sent}, removed {removed} dead token(s), {failed} failed.")
    return 1 if failed and not sent else 0


if __name__ == "__main__":
    sys.exit(main())
