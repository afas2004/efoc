# efoc — working notes

Three seconds every hour, stitched into a daily vlog for a group of friends.
Web PWA at **efoc.party** plus an Android build; invite-only.

Written because the specs in the parent folder (`# Chat Page…`, `# Vlog Grid…`,
`# Group Settings…`, `# Profile Popup…`, `EFOC Card Games…`) describe the
original design and several of those decisions were later dropped — the day
dots, for instance. **The code is the source of truth; the specs are context.**

---

## Stack

| Piece | What it does |
|---|---|
| Flutter | one codebase, web + Android |
| Supabase | Postgres, Storage, Edge Functions (`supabase/functions/`) |
| Firebase | Hosting, Messaging (push), Auth (only for push tokens) |
| Python workers | `worker/*.py`, run by GitHub Actions on a schedule |

`worker/stitch.py` builds yesterday's vlog, `export.py` renders user exports,
`remind.py` sends hourly nudges, `archive.py` / `backup.py` housekeeping.
Workflows live in `.github/workflows/`.

---

## Deploying

Always:

```powershell
build_web.bat -Version 1.9.1 -Notes "What changed, for the update banner."
```

That runs `release.ps1` (bumps `pubspec.yaml`, `web/update.json`,
`lib/version.dart`), builds with `--pwa-strategy=none`, then `firebase deploy`.
Commit the bump afterwards as `chore(release): X.Y.Z (build N)`.

Never `flutter build web` + `firebase deploy` by hand: the version bump is what
makes the in-app update banner fire, and the default service worker pins people
to stale builds.

**Migrations are run by hand** in the Supabase SQL editor, in filename order.
Apply them *before* deploying code that selects new columns — the app is
deployed straight to production and a missing column breaks the screen that
queries it.

---

## Data model, short version

- `groups`, `group_members` (`role` is only `owner` / `member` — no admin tier),
  `profiles`.
- `clips` — one row per person per hour. **`rotation` is 90 or 270 for every
  real clip**: the phone is held sideways while the app stays portrait, so the
  file is a portrait frame holding a landscape scene. `aspect_ratio` is a label
  forced by a check constraint (`9:16`, `1:1`, `16:9`) and is not the true
  shape — playback uses the video's own size.
- `vlogs` — stitched per group per day.
- `messages` — `kind` in `text | clip | vlog | sticker`. Cards carry their own
  copies (`card_path`, `card_hour`, `card_caption`, `card_date`,
  `card_rotation`) because retention deletes the clip row after the day and
  nulls `clip_id`; the card must still render.
- `sticker_packs` / `stickers` / `sticker_pack_installs` — see below.
- `exports`, `clip_views`, `message_reactions`, `reminder_*`.

Storage buckets: `clips` (private, signed URLs), `thumbnails` (public),
`vlogs` (private), `avatars` (public), `exports` (private),
`stickers` (public, path `{owner_id}/{pack_id}/{file}`).

RLS is group-membership based throughout — copy the pattern in
`20261017_rls_hardening.sql`.

---

## Stickers

Packs belong to a **person**, not to a Log. The tray is what each user
installed. Sharing is a link, not a file. Sending never depends on install —
every message carries its own `sticker_url`.

| Piece | Where |
|---|---|
| Pack + stickers | `sticker_packs`, `stickers` (owner-only writes) |
| The tray | `sticker_pack_installs` (`archived`, `last_used_at`) |
| Install, with the cap | `install_sticker_pack()` — archives the least recently used past **8** |
| Recency | `touch_sticker_pack()`, called after a sticker is sent |
| "Saved" pack | `ensure_saved_pack()` / `save_sticker()` |
| Share link | `efoc.party/?pack=<slug>` → `StickerPackScreen` |
| Import | `StickerService.parseWastickers()` |
| Share target | `web/share-target-sw.js` + `?shared=1` |

The importer is deliberately forgiving: `contents.json` at any depth, the
`sticker_packs` wrapper, alternate key names, a nested zip, or no metadata at
all (every image becomes a sticker). Tests:
`flutter test test/sticker_parse_test.dart`.

---

## Gotchas learned the hard way

- **`web/index.html` unregisters service workers.** Its kill switch whitelists
  `firebase-messaging-sw.js` and `share-target-sw.js`. Remove either exception
  and the feature silently dies on the next page load.
- **`storage.objects` cannot be deleted from SQL** — Supabase blocks it
  (`storage.protect_delete`). Empty buckets from the dashboard.
- **`file_picker` does nothing on web** when reached from a tap that already
  closed a bottom sheet. `lib/services/file_pick_web.dart` builds its own
  `<input type="file">` for that reason; native still uses the plugin.
- **Chrome on Android renames downloads** served as `application/zip` to
  `<name>.wastickers.zip`. The export uses `application/octet-stream`.
- **Clip cards need `card_rotation`**, not `clips.rotation` — retention removes
  the clip row.
- **A sticker export's `identifier` is the pack slug**, and Sticker Maker only
  imports files ending `.wastickers`.

---

## Checks before shipping

```powershell
flutter analyze          # no errors or warnings; the ~35 infos are style lints
flutter test             # sticker parser + game session + table links
flutter build web --release --pwa-strategy=none
```

---

## Known gaps, deliberately skipped

Typing indicator, chat header + `⋯` settings sheet (mute / background / report),
admin roles and permission pickers, capture ratio picker (capture is locked to
landscape), "vlog ready" and "new clip" push notifications. The tray shows
"By someone else" rather than the pack owner's name, because the profile join
was never added.
