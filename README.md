# efoc

**Three seconds every hour. One vlog a day.**

efoc nudges your group every hour to record a tiny 3-second clip. At midnight
everyone's clips are stitched into yesterday's vlog, hour by hour, all of you
side by side.

Friends only. Invite only. Runs in the browser at
[efoc.party](https://efoc.party) — add it to your home screen and it behaves
like an app, hourly nudges included.

---

## How it works

1. **A nudge every hour.** Everyone in the Log gets the same reminder, so the
   clips line up hour by hour.
2. **Record 3 seconds.** Point, tap, done. Drop a caption on it if you like.
3. **Watch yesterday's vlog.** At midnight the day is stitched together: one
   screen per hour, everyone playing at once.

The grid *is* the app. One column per person, one row per hour, and empty cells
that quietly say `z z z` until someone fills them. Tap a cell to watch that
moment; tap a day to watch the whole thing.

## More than a grid

- **Group chat** built around the vlog — clips and finished vlogs land in it as
  first-class messages, with replies, reactions and stickers.
- **Stickers** you bring from anywhere: import a `.wastickers` pack, make one
  from photos, or keep any sticker you receive. Packs are yours and follow you
  into every Log; share one by sending its link.
- **Make a vlog** from any hours you like — not just yesterday.
- **Download** a day's vlog to keep.
- **Card games** at the table: *Big Two* and *Lucky 7*, 2–8 players, opened from
  the Games tab and joined with a link. Guests can play a hand without an
  account. More games at [games.efoc.party](https://games.efoc.party).
- **Hourly reminders** that repair themselves when a phone silently drops them.

## Joining

Someone already in a Log sends you an invite — their QR code, or a
six-character code.

Then pick how to sign in:

- **With email** — we email you a sign-in code. Nothing to remember.
- **Just a username** — no email at all. You get a recovery code **once**.
  Screenshot it. It's the only way onto a new phone and there's no reset.

## What it deliberately doesn't do

No read receipts, no "last seen", no follower counts, no public discovery, no
editing messages, no likes that count. The constraint is the product: three
seconds, once an hour, with people you actually know.

---

## For developers

Flutter (web + Android) · Supabase (Postgres, Storage, Edge Functions) ·
Firebase (Hosting, Messaging) · Python workers on GitHub Actions.

```powershell
flutter pub get
flutter analyze
flutter test
build_web.bat -Version X.Y.Z -Notes "What changed"   # bump, build, deploy
```

**Read [NOTES.md](NOTES.md) before changing anything** — deploy ritual,
migration order, the sticker model, and the traps that have already bitten
once (they are not obvious, and two of them cost a release cycle).

The design specs sit one folder up (`# Chat Page…`, `# Vlog Grid…`,
`# Group Settings…`, `# Profile Popup…`). They describe the original intent and
several decisions have since been reversed — the day dots, for one. Where the
specs and the code disagree, **the code wins**.

---

Made by [Fahmi](https://games.efoc.party) · more games at
[games.efoc.party](https://games.efoc.party)
