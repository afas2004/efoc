"""Efoc one-off archive: everything in Supabase, downloaded for Drive.

Copies every raw clip and every stitched vlog into a local folder that
.github/workflows/archive.yml then uploads to My Drive/efoc/archive:

    raw clips/<Log name>/<yyyy-mm-dd>/<HH>-<person>.<ext>
    stitched/<Log name>/<yyyy-mm-dd>.mp4

Read-only: nothing is marked or deleted. Safe to run again; rclone skips
files that are already on Drive.

    python worker/archive.py --dest archive

Standard library only. Needs SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY.
"""

from __future__ import annotations

import argparse
import re
import shutil
import sys
import urllib.parse
from pathlib import Path

from backup import SERVICE_KEY, SUPABASE_URL, get_json, request, safe_name

VIDEO_EXT = re.compile(r"\.(mp4|webm|mov)$", re.IGNORECASE)


def download(bucket: str, storage_path: str, dest: Path) -> bool:
    if dest.exists() and dest.stat().st_size > 0:
        return True
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".part")
    try:
        path = urllib.parse.quote(storage_path)
        with request("GET", f"/storage/v1/object/{bucket}/{path}", timeout=120) as r, \
                open(tmp, "wb") as f:
            shutil.copyfileobj(r, f)
        tmp.replace(dest)
        return True
    except Exception as e:
        tmp.unlink(missing_ok=True)
        print(f"  FAILED {bucket}/{storage_path}: {e}", file=sys.stderr)
        return False


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dest", default="archive")
    args = ap.parse_args()
    root = Path(args.dest)

    if not SUPABASE_URL or not SERVICE_KEY:
        print("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required", file=sys.stderr)
        return 2

    groups = {g["id"]: g["name"] for g in get_json("/rest/v1/groups", {"select": "id,name"})}
    people = {
        p["id"]: (p.get("display_name") or "").strip() or p.get("username") or "someone"
        for p in get_json("/rest/v1/profiles", {"select": "id,display_name,username"})
    }

    def log_name(group_id: str) -> str:
        return safe_name(groups.get(group_id, group_id or "unknown"))

    # ---- raw clips ----
    clips = get_json("/rest/v1/clips", {
        "select": "group_id,user_id,recorded_on,hour_of_day,storage_path",
        "order": "recorded_on.asc,hour_of_day.asc",
    })
    ok = 0
    for c in clips:
        m = VIDEO_EXT.search(c["storage_path"])
        # Old web uploads had no real extension; they're WebM.
        ext = m.group(0).lower() if m else ".webm"
        name = f"{c['hour_of_day']:02d}-{safe_name(people.get(c['user_id'], 'someone'))}{ext}"
        dest = root / "raw clips" / log_name(c["group_id"]) / c["recorded_on"] / name
        ok += download("clips", c["storage_path"], dest)
    print(f"Raw clips: {ok}/{len(clips)} downloaded")
    clip_failures = len(clips) - ok

    # ---- stitched vlogs ----
    vlogs = get_json("/rest/v1/vlogs", {
        "select": "group_id,vlog_date,storage_path",
        "order": "vlog_date.asc",
    })
    ok = 0
    for v in vlogs:
        dest = root / "stitched" / log_name(v["group_id"]) / f"{v['vlog_date']}.mp4"
        ok += download("vlogs", v["storage_path"], dest)
    print(f"Stitched vlogs: {ok}/{len(vlogs)} downloaded")

    failures = clip_failures + len(vlogs) - ok
    if failures:
        print(f"{failures} file(s) failed; everything else still gets uploaded.",
              file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
