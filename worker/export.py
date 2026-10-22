"""Efoc on-demand vlog ("Make a vlog" in the app's ⬇ menu).

Stitches one exports row: the chosen day, Logs and hours, in the same
look as the nightly vlog (it reuses stitch.py), uploads the MP4 to the
private exports bucket and marks the row done. The app is watching the
row and downloads the file straight to the phone; a push notification
covers the case where the app was closed.

Started by .github/workflows/export.yml (via the start-export Edge
Function). Locally:

    python worker/export.py --id <export uuid>
"""

from __future__ import annotations

import argparse
import datetime as dt
import sys
import tempfile
from pathlib import Path

import requests

import stitch as s


def patch_export(export_id: str, fields: dict) -> None:
    r = requests.patch(
        f"{s.SUPABASE_URL}/rest/v1/exports",
        headers=s._headers({"Content-Type": "application/json", "Prefer": "return=minimal"}),
        params={"id": f"eq.{export_id}"},
        json=fields,
        timeout=30,
    )
    r.raise_for_status()


def notify(user_id: str, clip_count: int) -> None:
    """Best effort: a push to the requester's devices."""
    try:
        import remind
        if not remind.SERVICE_ACCOUNT:
            return
        tokens = s.rest_get("push_tokens", {"select": "token", "user_id": f"eq.{user_id}"})
        if not tokens:
            return
        session, project = remind.fcm_session()
        for t in tokens:
            session.post(
                f"https://fcm.googleapis.com/v1/projects/{project}/messages:send",
                json={"message": {
                    "token": t["token"],
                    "notification": {
                        "title": "Your vlog is ready 🎞️",
                        "body": f"{clip_count} clip{'s' if clip_count != 1 else ''}. "
                                "Open efoc to save it.",
                    },
                    "webpush": {
                        "notification": {
                            "icon": "/icons/Icon-192.png",
                            "badge": "/icons/badge-96.png",
                            "tag": "efoc-export",
                        },
                        "fcm_options": {"link": remind.APP_URL},
                    },
                }},
                timeout=30,
            )
    except Exception as e:
        print(f"push failed (not fatal): {e}", file=sys.stderr)


def run(export_id: str) -> None:
    rows = s.rest_get("exports", {"select": "*", "id": f"eq.{export_id}"})
    if not rows:
        raise RuntimeError(f"export {export_id} not found")
    ex = rows[0]
    if ex["status"] not in ("queued", "failed"):
        print(f"export is {ex['status']}, nothing to do")
        return
    patch_export(export_id, {"status": "running", "error": None})

    params = {
        "select": "user_id,group_id,storage_path,hour_of_day,text_overlay,"
                  "text_color,text_font,text_x,text_y,rotation,text_bg,created_at",
        "recorded_on": f"eq.{ex['day']}",
        "group_id": f"in.({','.join(ex['group_ids'])})",
        "order": "hour_of_day.asc,created_at.asc",
    }
    if ex.get("hours"):
        params["hour_of_day"] = f"in.({','.join(str(h) for h in ex['hours'])})"
    clips = s.rest_get("clips", params)

    # One recording sent to several Logs is several rows: keep it once.
    seen: set[tuple[str, int]] = set()
    unique = []
    for c in clips:
        key = (c["user_id"], c["hour_of_day"])
        if key not in seen:
            seen.add(key)
            unique.append(c)
    if not unique:
        raise RuntimeError("No clips for that day, Log and hours (raw clips "
                           "from before today may already be cleaned up).")

    user_ids = sorted({c["user_id"] for c in unique})
    names = {
        p["id"]: (p.get("display_name") or "").strip() or p.get("username") or "Someone"
        for p in s.rest_get("profiles", {
            "select": "id,display_name,username",
            "id": f"in.({','.join(user_ids)})",
        })
    }

    with tempfile.TemporaryDirectory(prefix="efoc-export-") as tmp:
        work = Path(tmp)
        segments, used = s.build_hour_frames(
            unique, names, work,
            fetch=lambda path, dest: s.storage_download("clips", path, dest),
        )
        if not segments:
            raise RuntimeError("None of the clips could be processed.")

        out = work / "vlog.mp4"
        s.concat(segments, out, work)
        dest = f"{ex['user_id']}/{export_id}.mp4"
        s.storage_upload("exports", dest, out, "video/mp4")

    patch_export(export_id, {
        "status": "done",
        "storage_path": dest,
        "clip_count": used,
        "finished_at": dt.datetime.now(dt.timezone.utc).isoformat(),
    })
    print(f"done: {dest} ({used} clips in {len(segments)} frames)")
    notify(ex["user_id"], used)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--id", required=True)
    args = ap.parse_args()
    if not s.SUPABASE_URL or not s.SERVICE_KEY:
        print("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set", file=sys.stderr)
        return 2
    try:
        run(args.id)
        return 0
    except Exception as e:
        print(f"FAILED: {e}", file=sys.stderr)
        try:
            patch_export(args.id, {
                "status": "failed",
                "error": str(e)[:300],
                "finished_at": dt.datetime.now(dt.timezone.utc).isoformat(),
            })
        except Exception:
            pass
        return 1


if __name__ == "__main__":
    sys.exit(main())
