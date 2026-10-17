"""Efoc laptop backup for stitched vlogs.

Downloads every stitched vlog that hasn't been backed up yet into
BACKUP_DIR/<Log name>/<yyyy-mm-dd>.mp4, then marks it in Supabase
(vlogs.backed_up_at) so the nightly cleanup is allowed to delete it.

Supabase keeps a vlog for at most 7 days without a backup, so run this at
least every few days. backup.bat runs it; schedule that daily.

Standard library only: no pip install needed.

Settings come from environment variables or a file next to the efoc
folder, named efoc-backup.env (see worker/backup.env.example):

    SUPABASE_URL=https://<project>.supabase.co
    SUPABASE_SERVICE_ROLE_KEY=...
    BACKUP_DIR=D:/efoc-backups
"""

from __future__ import annotations

import datetime as dt
import json
import os
import re
import shutil
import sys
import urllib.parse
import urllib.request
from pathlib import Path


def load_env_file(path: Path) -> None:
    if not path.is_file():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"'))


# Kept outside the repo on purpose (the service role key is a secret):
# <folder containing efoc>/efoc-backup.env
REPO = Path(__file__).resolve().parents[1]
load_env_file(REPO.parent / "efoc-backup.env")

SUPABASE_URL = os.environ.get("SUPABASE_URL", "").rstrip("/")
SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
BACKUP_DIR = Path(os.environ.get("BACKUP_DIR", str(Path.home() / "efoc-backups")))


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


def safe_name(name: str) -> str:
    cleaned = re.sub(r'[<>:"/\\|?*\x00-\x1f]', "_", name).strip(" .")
    return cleaned or "Log"


def main() -> int:
    print(f"--- {dt.datetime.now():%Y-%m-%d %H:%M}")
    if not SUPABASE_URL or not SERVICE_KEY:
        print("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required "
              "(put them in efoc-backup.env)", file=sys.stderr)
        return 2

    pending = get_json("/rest/v1/vlogs", {
        "select": "id,group_id,vlog_date,storage_path",
        "backed_up_at": "is.null",
        "order": "vlog_date.asc",
    })
    if not pending:
        print("Nothing new to back up.")
        return 0

    group_ids = sorted({v["group_id"] for v in pending})
    names = {
        row["id"]: row["name"]
        for row in get_json("/rest/v1/groups", {
            "select": "id,name",
            "id": f"in.({','.join(group_ids)})",
        })
    }

    failed = 0
    for v in pending:
        folder = BACKUP_DIR / safe_name(names.get(v["group_id"], v["group_id"]))
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

            # Only after the file is safely on disk.
            request(
                "PATCH", "/rest/v1/vlogs",
                params={"id": f"eq.{v['id']}"},
                body={"backed_up_at": dt.datetime.now(dt.timezone.utc).isoformat()},
            ).close()
            print(f"Saved {dest}")
        except Exception as e:
            failed += 1
            tmp.unlink(missing_ok=True)
            print(f"FAILED {v['vlog_date']} {v['group_id']}: {e}", file=sys.stderr)

    print(f"Backed up {len(pending) - failed}, failed {failed}.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
