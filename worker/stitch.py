"""Efoc daily vlog stitcher.

Concatenates each group's clips for one day into a single portrait MP4,
uploads it to the `vlogs` bucket and upserts a row in `public.vlogs`.

Runs at local midnight from .github/workflows/stitch.yml, but works the same
from a laptop:

    export SUPABASE_URL=https://<project>.supabase.co
    export SUPABASE_SERVICE_ROLE_KEY=...
    python worker/stitch.py                       # yesterday, all groups
    python worker/stitch.py --date 2026-10-16     # a specific day
    python worker/stitch.py --group <uuid> --force
    python worker/stitch.py --cleanup-only --dry-run   # what would be deleted

After stitching it applies the free-tier retention policy (see cleanup()):
only today's raw clips and yesterday's stitched vlog stay in Supabase.

Requires ffmpeg/ffprobe on PATH and a TTF font (see FONT_FILE).
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from collections import defaultdict
from pathlib import Path
from zoneinfo import ZoneInfo

import requests

SUPABASE_URL = os.environ.get("SUPABASE_URL", "").rstrip("/")
SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")

# Clips are dated by the phone's local calendar day (clips.recorded_on), so
# "yesterday" must be computed in the same timezone the app's users live in.
APP_TZ = ZoneInfo(os.environ.get("APP_TZ", "Asia/Kuala_Lumpur"))

FONT_FILE = os.environ.get(
    "FONT_FILE", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
)

# Caption fonts, the same Google Fonts the app uses (lib/widgets/caption.dart).
# The workflow downloads them into CAPTION_FONT_DIR; anything missing falls
# back to DejaVu so a stitch never fails over a font.
FONT_DIR = os.environ.get("CAPTION_FONT_DIR", "/tmp/efoc-fonts")
_DEJAVU = "/usr/share/fonts/truetype/dejavu/"
CAPTION_FONTS = {
    #  key        file                                 size  fallback
    "classic": ("Poppins-Bold.ttf", 60, "DejaVuSans-Bold.ttf"),
    "bold": ("Anton-Regular.ttf", 70, "DejaVuSansCondensed-Bold.ttf"),
    "elegant": ("PlayfairDisplay-Italic.ttf", 64, "DejaVuSerif-Italic.ttf"),
    "mono": ("JetBrainsMono.ttf", 54, "DejaVuSansMono-Bold.ttf"),
    "hand": ("Caveat.ttf", 84, "DejaVuSans-Bold.ttf"),
    "script": ("Pacifico-Regular.ttf", 58, "DejaVuSans-Bold.ttf"),
}


def caption_font_file(key: str) -> tuple[str, int]:
    name, size, fallback = CAPTION_FONTS.get(key, CAPTION_FONTS["classic"])
    path = Path(FONT_DIR) / name
    if path.is_file():
        return str(path), size
    alt = Path(_DEJAVU) / fallback
    return (str(alt) if alt.is_file() else FONT_FILE), size


def _is_light(hex_color: str) -> bool:
    """hex_color like 0xRRGGBB. Same idea as the app's contrast check."""
    v = int(hex_color[2:], 16)
    r, g, b = (v >> 16) & 255, (v >> 8) & 255, v & 255
    return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255 > 0.6


def caption_box(highlight: str, color: str) -> tuple[str, str]:
    """(drawtext box/border options, font colour) for a highlight style."""
    if highlight == "none":
        edge = "black" if _is_light(color) else "white"
        return f"borderw=4:bordercolor={edge}@0.85", color
    if highlight == "light":
        return "box=1:boxcolor=white@0.88:boxborderw=18", color
    if highlight == "color":
        text = "black" if _is_light(color) else "white"
        return f"box=1:boxcolor={color}:boxborderw=18", text
    return "box=1:boxcolor=black@0.55:boxborderw=18", color


# Where the app puts a caption with no saved position (Alignment(0, -0.3)).
DEFAULT_CAPTION_ALIGN = (0.0, -0.3)

# Landscape: clips are recorded with the phone sideways and come out 3:2.
# Older upright clips are fitted over a blurred copy of themselves.
WIDTH, HEIGHT, FPS = 1080, 720, 30
MAX_CLIP_SECONDS = 4  # clips are 3s; cap guards against odd uploads

HEX_COLOR = re.compile(r"^#?([0-9a-fA-F]{6})$")

# Retention. Raw clips go once their day is stitched; if stitching keeps
# failing they still go after RAW_GRACE_DAYS so storage can't pile up.
# Stitched vlogs older than yesterday go once backed up to the laptop
# (worker/backup.py), or after VLOG_MAX_DAYS even without a backup.
RAW_GRACE_DAYS = int(os.environ.get("RAW_GRACE_DAYS", "3"))
VLOG_MAX_DAYS = int(os.environ.get("VLOG_MAX_DAYS", "7"))

# Nothing dated before this is ever deleted, so data from before the
# retention policy existed stays until you decide what to do with it
# (it's copied to Drive by worker/archive.py). Clear it to apply the
# policy to everything.
RETENTION_START = os.environ.get("RETENTION_START", "").strip()

VIDEO_EXT = re.compile(r"\.(mp4|webm|mov)$")


# ============================================================
# Supabase REST helpers
# ============================================================

def _headers(extra: dict | None = None) -> dict:
    h = {"apikey": SERVICE_KEY, "Authorization": f"Bearer {SERVICE_KEY}"}
    if extra:
        h.update(extra)
    return h


def rest_get(table: str, params: dict) -> list[dict]:
    r = requests.get(
        f"{SUPABASE_URL}/rest/v1/{table}", headers=_headers(), params=params, timeout=30
    )
    r.raise_for_status()
    return r.json()


def rest_upsert(table: str, row: dict, on_conflict: str) -> None:
    r = requests.post(
        f"{SUPABASE_URL}/rest/v1/{table}",
        headers=_headers({
            "Content-Type": "application/json",
            "Prefer": "resolution=merge-duplicates,return=minimal",
        }),
        params={"on_conflict": on_conflict},
        data=json.dumps(row),
        timeout=30,
    )
    r.raise_for_status()


def rest_delete_ids(table: str, ids: list[str]) -> None:
    for i in range(0, len(ids), 100):
        r = requests.delete(
            f"{SUPABASE_URL}/rest/v1/{table}",
            headers=_headers({"Prefer": "return=minimal"}),
            params={"id": f"in.({','.join(ids[i:i + 100])})"},
            timeout=30,
        )
        r.raise_for_status()


def storage_delete(bucket: str, paths: list[str]) -> None:
    """Bulk delete. Paths that don't exist are ignored by Storage."""
    for i in range(0, len(paths), 100):
        r = requests.delete(
            f"{SUPABASE_URL}/storage/v1/object/{bucket}",
            headers=_headers({"Content-Type": "application/json"}),
            data=json.dumps({"prefixes": paths[i:i + 100]}),
            timeout=60,
        )
        r.raise_for_status()


def thumb_path_for(storage_path: str) -> str:
    """Same rule as ClipService.publicThumbnailUrl in the app."""
    if VIDEO_EXT.search(storage_path):
        return VIDEO_EXT.sub(".jpg", storage_path)
    return storage_path  # old extensionless web uploads


def storage_download(bucket: str, path: str, dest: Path) -> None:
    with requests.get(
        f"{SUPABASE_URL}/storage/v1/object/{bucket}/{path}",
        headers=_headers(),
        stream=True,
        timeout=60,
    ) as r:
        r.raise_for_status()
        with open(dest, "wb") as f:
            shutil.copyfileobj(r.raw, f)


def storage_upload(bucket: str, path: str, src: Path, content_type: str) -> None:
    with open(src, "rb") as f:
        r = requests.post(
            f"{SUPABASE_URL}/storage/v1/object/{bucket}/{path}",
            headers=_headers({"Content-Type": content_type, "x-upsert": "true"}),
            data=f,
            timeout=300,
        )
    r.raise_for_status()


# ============================================================
# ffmpeg
# ============================================================

def run(cmd: list[str]) -> str:
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError(f"{cmd[0]} failed:\n{p.stderr[-2000:]}")
    return p.stdout


def has_audio(path: Path) -> bool:
    out = run([
        "ffprobe", "-v", "error", "-select_streams", "a",
        "-show_entries", "stream=index", "-of", "csv=p=0", str(path),
    ])
    return bool(out.strip())


def duration_of(path: Path) -> float | None:
    out = run([
        "ffprobe", "-v", "error", "-show_entries", "format=duration",
        "-of", "default=nw=1:nk=1", str(path),
    ]).strip()
    try:
        return round(float(out), 2)
    except ValueError:
        return None


def _filter_path(p: Path) -> str:
    # drawtext options are ':'-separated, so escape anything that would break.
    return str(p).replace("\\", "/").replace(":", r"\:").replace("'", r"\'")


def _hour_label(hour: int) -> str:
    h12 = hour % 12 or 12
    return f"{h12} {'AM' if hour < 12 else 'PM'}"


def normalize_clip(src: Path, dest: Path, label: str, caption: str | None,
                   caption_color: str, work: Path, caption_font: str = "classic",
                   caption_align: tuple[float, float] = DEFAULT_CAPTION_ALIGN,
                   rotation: int = 0, caption_bg: str = "dark") -> None:
    """Re-encodes one clip to the shared format with label + caption burned in.

    Clips arrive as WebM (web) or MP4 (Android). rotation=90 clips were
    filmed with the phone sideways and are turned upright first. Each is
    fitted onto the WIDTHxHEIGHT canvas over a blurred copy of itself so
    the stitched vlog never shows black bars.
    """
    label_file = work / f"{dest.stem}.label.txt"
    label_file.write_text(label, encoding="utf-8")

    font = _filter_path(Path(FONT_FILE))
    # 90: back camera, turn counter-clockwise; 270: front camera, clockwise.
    upright = {90: "transpose=2,", 270: "transpose=1,"}.get(rotation, "")
    vf = (
        f"[0:v]{upright}split=2[a][b];"
        f"[a]scale={WIDTH}:{HEIGHT}:force_original_aspect_ratio=increase,"
        f"crop={WIDTH}:{HEIGHT},boxblur=20:2[bg];"
        f"[b]scale={WIDTH}:{HEIGHT}:force_original_aspect_ratio=decrease[fg];"
        f"[bg][fg]overlay=(W-w)/2:(H-h)/2,fps={FPS},format=yuv420p,setsar=1,"
        f"drawtext=fontfile='{font}':textfile='{_filter_path(label_file)}':"
        f"fontsize=30:fontcolor=white:x=36:y=64:"
        f"box=1:boxcolor=black@0.35:boxborderw=12"
    )
    if caption:
        caption_file = work / f"{dest.stem}.caption.txt"
        caption_file.write_text(caption, encoding="utf-8")
        font_path, size = caption_font_file(caption_font)
        box, text_color = caption_box(caption_bg, caption_color)
        ax, ay = caption_align
        # Same maths as Flutter's Align: -1 = flush left/top, 1 = right/bottom,
        # inside a margin so the box never touches the edge.
        margin = 48
        vf += (
            f",drawtext=fontfile='{_filter_path(Path(font_path))}':"
            f"textfile='{_filter_path(caption_file)}':"
            f"fontsize={size}:fontcolor={text_color}:{box}:"
            f"x=(w-text_w)/2+({ax:.3f})*((w-text_w)/2-{margin}):"
            f"y=(h-text_h)/2+({ay:.3f})*((h-text_h)/2-{margin})"
        )
    vf += "[v]"

    cmd = ["ffmpeg", "-y", "-v", "error", "-i", str(src)]
    if has_audio(src):
        audio_map = "0:a:0"
    else:
        # Silent track keeps every segment's stream layout identical, which
        # the copy-concat below depends on.
        cmd += ["-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo"]
        audio_map = "1:a:0"

    cmd += [
        "-filter_complex", vf,
        "-map", "[v]", "-map", audio_map,
        "-t", str(MAX_CLIP_SECONDS), "-shortest",
        "-c:v", "libx264", "-preset", "veryfast", "-crf", "23", "-r", str(FPS),
        "-c:a", "aac", "-ar", "48000", "-ac", "2", "-b:a", "128k",
        str(dest),
    ]
    run(cmd)


def concat(segments: list[Path], dest: Path, work: Path) -> None:
    listing = work / "concat.txt"
    listing.write_text(
        "".join(f"file '{s.as_posix()}'\n" for s in segments), encoding="utf-8"
    )
    run([
        "ffmpeg", "-y", "-v", "error", "-f", "concat", "-safe", "0",
        "-i", str(listing), "-c", "copy", "-movflags", "+faststart", str(dest),
    ])


def thumbnail(video: Path, dest: Path) -> None:
    run([
        "ffmpeg", "-y", "-v", "error", "-ss", "0.5", "-i", str(video),
        "-frames:v", "1", "-vf", "scale=360:-2", "-q:v", "3", str(dest),
    ])


# ============================================================
# Stitching
# ============================================================

def stitch_group(group_id: str, date: str, clips: list[dict],
                 names: dict[str, str], dry_run: bool) -> None:
    print(f"[{group_id}] {len(clips)} clip(s)")
    if dry_run:
        return

    with tempfile.TemporaryDirectory(prefix="efoc-") as tmp:
        work = Path(tmp)
        segments: list[Path] = []

        for i, clip in enumerate(clips):
            path = clip["storage_path"]
            src = work / f"src{i}{Path(path).suffix or '.mp4'}"
            seg = work / f"seg{i:03d}.mp4"
            try:
                storage_download("clips", path, src)
                m = HEX_COLOR.match(clip.get("text_color") or "")
                normalize_clip(
                    src, seg,
                    label=f"{names.get(clip['user_id'], 'Someone')} · "
                          f"{_hour_label(clip['hour_of_day'])}",
                    caption=(clip.get("text_overlay") or "").strip() or None,
                    caption_color=f"0x{m.group(1)}" if m else "0xFFFFFF",
                    work=work,
                    caption_font=clip.get("text_font") or "classic",
                    caption_align=(
                        (float(clip["text_x"]), float(clip["text_y"]))
                        if clip.get("text_x") is not None and clip.get("text_y") is not None
                        else DEFAULT_CAPTION_ALIGN
                    ),
                    rotation=int(clip.get("rotation") or 0),
                    caption_bg=clip.get("text_bg") or "dark",
                )
                segments.append(seg)
            except Exception as e:  # one bad clip shouldn't sink the vlog
                print(f"  skip {path}: {e}", file=sys.stderr)

        if not segments:
            raise RuntimeError("no clip could be processed")

        out = work / "vlog.mp4"
        thumb = work / "vlog.jpg"
        concat(segments, out, work)
        thumbnail(out, thumb)

        video_path = f"{group_id}/{date}.mp4"
        thumb_path = f"{group_id}/{date}.jpg"
        storage_upload("vlogs", video_path, out, "video/mp4")
        storage_upload("vlogs", thumb_path, thumb, "image/jpeg")

        rest_upsert("vlogs", {
            "group_id": group_id,
            "vlog_date": date,
            "storage_path": video_path,
            "thumbnail_path": thumb_path,
            "clip_count": len(segments),
            "duration_seconds": duration_of(out),
            "stitched_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        }, on_conflict="group_id,vlog_date")

        print(f"  -> {video_path} ({len(segments)} clips)")


# ============================================================
# Retention
# ============================================================

def cleanup(today: dt.date, dry_run: bool) -> None:
    yesterday = today - dt.timedelta(days=1)
    verb = "would delete" if dry_run else "deleting"

    # ---- raw clips from before today ----
    clip_filter = {"recorded_on": f"lt.{today.isoformat()}"}
    vlog_filter = {"vlog_date": f"lt.{yesterday.isoformat()}"}
    if RETENTION_START:
        print(f"Leaving anything before {RETENTION_START} alone (RETENTION_START)")
        clip_filter = {"and": f"(recorded_on.lt.{today.isoformat()},"
                              f"recorded_on.gte.{RETENTION_START})"}
        vlog_filter = {"and": f"(vlog_date.lt.{yesterday.isoformat()},"
                              f"vlog_date.gte.{RETENTION_START})"}

    old_clips = rest_get("clips", {
        "select": "id,group_id,recorded_on,storage_path",
        **clip_filter,
    })
    stitched = {
        (v["group_id"], v["vlog_date"])
        for v in rest_get("vlogs", {
            "select": "group_id,vlog_date",
            "vlog_date": f"lt.{today.isoformat()}",
        })
    }
    grace_cutoff = (today - dt.timedelta(days=RAW_GRACE_DAYS)).isoformat()

    doomed: list[dict] = []
    for c in old_clips:
        if (c["group_id"], c["recorded_on"]) in stitched:
            doomed.append(c)
        elif c["recorded_on"] < grace_cutoff:
            print(f"  [{c['group_id']}] {c['recorded_on']} never stitched, "
                  f"dropping raw clips anyway", file=sys.stderr)
            doomed.append(c)

    kept = len(old_clips) - len(doomed)
    print(f"Raw clips before {today}: {verb} {len(doomed)}, keeping {kept} "
          f"(not stitched yet)")
    if doomed and not dry_run:
        # Rows first: if that fails the files are still there; a leftover
        # file with no row is only wasted space.
        rest_delete_ids("clips", [c["id"] for c in doomed])
        paths = [c["storage_path"] for c in doomed]
        storage_delete("clips", paths)
        storage_delete("thumbnails", [thumb_path_for(p) for p in paths])

    # ---- stitched vlogs older than yesterday ----
    old_vlogs = rest_get("vlogs", {
        "select": "id,group_id,vlog_date,storage_path,thumbnail_path,backed_up_at",
        **vlog_filter,
    })
    hard_cutoff = (today - dt.timedelta(days=VLOG_MAX_DAYS)).isoformat()
    gone = [
        v for v in old_vlogs
        if v.get("backed_up_at") or v["vlog_date"] < hard_cutoff
    ]
    for v in gone:
        if not v.get("backed_up_at"):
            print(f"  [{v['group_id']}] {v['vlog_date']} was never backed up, "
                  f"deleting after {VLOG_MAX_DAYS} days", file=sys.stderr)
    waiting = len(old_vlogs) - len(gone)
    print(f"Stitched vlogs before {yesterday}: {verb} {len(gone)}, keeping "
          f"{waiting} (waiting for laptop backup)")
    if gone and not dry_run:
        files = [v["storage_path"] for v in gone]
        files += [v["thumbnail_path"] for v in gone if v.get("thumbnail_path")]
        rest_delete_ids("vlogs", [v["id"] for v in gone])
        storage_delete("vlogs", files)

    # ---- on-demand exports ("Make a vlog"): kept for a day ----
    cutoff = (dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=1)).isoformat()
    try:
        old_exports = rest_get("exports", {
            "select": "id,storage_path", "created_at": f"lt.{cutoff}",
        })
    except Exception as e:  # table not there yet
        print(f"Exports cleanup skipped: {e}", file=sys.stderr)
        old_exports = []
    print(f"On-demand exports older than a day: {verb} {len(old_exports)}")
    if old_exports and not dry_run:
        rest_delete_ids("exports", [x["id"] for x in old_exports])
        files = [x["storage_path"] for x in old_exports if x.get("storage_path")]
        if files:
            storage_delete("exports", files)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--date", help="YYYY-MM-DD (default: yesterday in APP_TZ)")
    ap.add_argument("--group", help="only this group id")
    ap.add_argument("--force", action="store_true",
                    help="re-stitch even if a vlog already exists")
    ap.add_argument("--dry-run", action="store_true",
                    help="list what would be stitched/deleted, change nothing")
    ap.add_argument("--no-cleanup", action="store_true",
                    help="skip the retention cleanup")
    ap.add_argument("--cleanup-only", action="store_true",
                    help="only run the retention cleanup")
    args = ap.parse_args()

    if not SUPABASE_URL or not SERVICE_KEY:
        print("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set", file=sys.stderr)
        return 2

    today = dt.datetime.now(APP_TZ).date()

    failed = 0 if args.cleanup_only else stitch_day(args)

    if not args.no_cleanup and not args.date:
        # Only for the normal nightly run: a manual --date re-stitch of an
        # old day shouldn't trigger deletes.
        try:
            cleanup(today, args.dry_run)
        except Exception as e:
            failed += 1
            print(f"Cleanup FAILED: {e}", file=sys.stderr)

    return 1 if failed else 0


def stitch_day(args: argparse.Namespace) -> int:
    """Stitches one day. Returns the number of groups that failed."""
    date = args.date or (dt.datetime.now(APP_TZ).date() - dt.timedelta(days=1)).isoformat()
    print(f"Stitching {date} ({APP_TZ.key})")

    params = {
        "select": "user_id,group_id,storage_path,hour_of_day,text_overlay,"
                  "text_color,text_font,text_x,text_y,rotation,text_bg",
        "recorded_on": f"eq.{date}",
        "order": "hour_of_day.asc,created_at.asc",
    }
    if args.group:
        params["group_id"] = f"eq.{args.group}"
    clips = rest_get("clips", params)

    by_group: dict[str, list[dict]] = defaultdict(list)
    for c in clips:
        if c.get("group_id"):
            by_group[c["group_id"]].append(c)

    if not args.force and by_group:
        done = rest_get("vlogs", {"select": "group_id", "vlog_date": f"eq.{date}"})
        for row in done:
            if by_group.pop(row["group_id"], None) is not None:
                print(f"[{row['group_id']}] already stitched, skipping")

    if not by_group:
        print("Nothing to stitch.")
        return 0

    user_ids = sorted({c["user_id"] for cs in by_group.values() for c in cs})
    profiles = rest_get("profiles", {
        "select": "id,display_name,username",
        "id": f"in.({','.join(user_ids)})",
    })
    names = {
        p["id"]: (p.get("display_name") or "").strip() or p.get("username") or "Someone"
        for p in profiles
    }

    failed = 0
    for group_id, group_clips in by_group.items():
        try:
            stitch_group(group_id, date, group_clips, names, args.dry_run)
        except Exception as e:
            failed += 1
            print(f"[{group_id}] FAILED: {e}", file=sys.stderr)

    return failed


if __name__ == "__main__":
    sys.exit(main())
