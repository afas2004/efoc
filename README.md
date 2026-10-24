# efoc

Three seconds every hour, stitched into a daily vlog for a group of friends.
Runs in the browser at [efoc.party](https://efoc.party) as a PWA, plus an
Android build. Invite-only.

Flutter (web + Android) · Supabase (Postgres, Storage, Edge Functions) ·
Firebase (Hosting, Messaging) · Python workers on GitHub Actions.

## Working on it

Read **[NOTES.md](NOTES.md)** first — deploy process, migration order, the
sticker model, and the traps that have already bitten once.

```powershell
flutter pub get
flutter analyze
flutter test
build_web.bat -Version X.Y.Z -Notes "What changed"   # bump, build, deploy
```

The design specs live one folder up (`# Chat Page…`, `# Vlog Grid…`, and
friends). They describe the original intent and several decisions have since
changed — where they disagree with the code, the code wins.
