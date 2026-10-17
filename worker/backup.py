"""Efoc backup for stitched vlogs.

Downloads every stitched vlog that hasn't been backed up yet into
<dest>/<Log name>/<yyyy-mm-dd>.mp4 and marks it in Supabase
(vlogs.backed_up_at), which allows the nightly cleanup to delete it.

The nightly GitHub job (.github/workflows/stitch.yml) uses it in two steps
around an rclone upload to Google Drive, so a vlog only counts as backed
up once it's actually on Drive:

    python worker/backup.py --dest out --no-mark --manifest out.json
    rclone copy out gdrive:efoc
    python worker/backup.py --mark-from out.json

Run on its own (no flags) it downloads into BACKUP_DIR and marks right
away, which is fine for a local folder.

Standard library only: no pip install needed.

Needs SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in the environment.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import shutil
import sys
import urllib.parse
import urllib.request
from pathlib import Path

SUPABASE_URL = os.environ.get("SUPABASE_URL", "").rstrip("/")
SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
BACKUP_DIR = os.environ.get("BACKUP_DIR", str(Path.home() / "efoc-backups"))


def request(method: str, path: str, params: dict | None = None,
            body: dict | None = None, timeout: int = 30):
    url = f"{SUPABASE_URL}{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    headers = {"apikey": SERVICE_KEY, "Authorization": f"Bearer {SERVICE_KEY}"}
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
        headers["Prefer"] = "return=minimal"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    return urllib.request.urlopen(req, timeout=timeout)


def get_json(path: str, params: dict) -> list[dict]:
    with request("GET", path, params) as r:
        return json.load(r)


def mark_backed_up(ids: list[str]) -> None:
    if not ids:
        return
    request(
        "PATCH", "/rest/v1/vlogs",
        params={"id": f"in.({','.join(ids)})"},
        body={"backed_up_at": dt.datetime.now(dt.timezone.utc).isoformat()},
    ).close()


def safe_name(name: str) -> str:
    cleaned = re.sub(r'[<>:"/\\|?*\x00-\x1f]', "_", name).strip(" .")
    return cleaned or "Log"


def download_pending(dest_root: Path) -> tuple[list[str], int]:
    """Returns (ids downloaded, failures)."""
    pending = get_json("/rest/v1/vlogs", {
        "select": "id,group_id,vlog_date,storage_path",
        "backed_up_at": "is.null",
        "order": "vlog_date.asc",
    })
    if not pending:
        print("Nothing new to back up.")
        return [], 0

    group_ids = sorted({v["group_id"] for v in pending})
    names = {
        row["id"]: row["name"]
        for row in get_json("/rest/v1/groups", {
            "select": "id,name",
            "id": f"in.({','.join(group_ids)})",
        })
    }

    done: list[str] = []
    failed = 0
    for v in pending:
        folder = dest_root / safe_name(names.get(v["group_id"], v["group_id"]))
        folder.mkdir(parents=True, exist_ok=True)
        dest = folder / f"{v['vlog_date']}.mp4"
        tmp = dest.with_suffix(".part")
        try:
            path = urllib.parse.quote(v["storage_path"])
            with request("GET", f"/storage/v1/object/vlogs/{path}", timeout=120) as r, \
                    open(tmp, "wb") as f:
                shutil.copyfileobj(r, f)
            if tmp.stat().st_size == 0:
                raise RuntimeError("empty download")
            tmp.replace(dest)
            done.append(v["id"])
            print(f"Downloaded {dest}")
        except Exception as e:
            failed += 1
            tmp.unlink(missing_ok=True)
            print(f"FAILED {v['vlog_date']} {v['group_id']}: {e}", file=sys.stderr)
    return done, failed


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dest", help=f"download folder (default BACKUP_DIR={BACKUP_DIR})")
    ap.add_argument("--no-mark", action="store_true",
                    help="download only; don't mark as backed up yet")
    ap.add_argument("--manifest", help="write the downloaded vlog ids here (JSON)")
    ap.add_argument("--mark-from", help="only mark the ids in this manifest")
    args = ap.parse_args()

    if not SUPABASE_URL or not SERVICE_KEY:
        print("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required", file=sys.stderr)
        return 2

    if args.mark_from:
        ids = json.loads(Path(args.mark_from).read_text(encoding="utf-8"))
        mark_backed_up(ids)
        print(f"Marked {len(ids)} vlog(s) as backed up.")
        return 0

    done, failed = download_pending(Path(args.dest or BACKUP_DIR))
    if args.manifest:
        Path(args.manifest).write_text(json.dumps(done), encoding="utf-8")
    if not args.no_mark:
        mark_backed_up(done)
    print(f"Downloaded {len(done)}, failed {failed}.")
    # In the two-step Drive flow, a vlog that failed to download mustn't
    # stop the others from being uploaded; it's retried the next night.
    return 1 if failed and not args.manifest else 0


if __name__ == "__main__":
    sys.exit(main())
