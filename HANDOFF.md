# Handoff — efoc

Written 2026-10-25, after the sticker/clip/chat work landed.

**State:** `main` at the README commit, deployed as **1.9.0 (build 35)**, remote in
sync. `NOTES.md` has the deploy ritual, migration order, sticker model and the
traps that have already cost a release cycle. Read that first; this file is
about what's next.

---

## Next task: tell the group when someone opens a table

Right now a table is announced only in the group's Games tab and as a chat card
posted by the host. Nobody gets a push unless they happen to be looking.

### What already exists

| Piece | Where |
|---|---|
| Host lists the table | `lib/games/table_screen.dart:150` — `OpenTables.instance.list(...)`, called once the page's first write creates the room (guarded by `_announced`) |
| The listing itself | `tables/{groupId}/{roomId}` in Firebase Realtime Database, `lib/games/open_tables.dart` — `{gameId, hostUid, hostName, createdAt}`, auto-ignored after 6 h |
| Unlisting | `table_screen.dart:110` (results arrive) and `:140` (host closes the room) |
| Join link | `TableLink.toUri()` → `https://efoc.party/join?table=…&group=…&game=…`. **Reuses `/join` on purpose** — Android's intent filter already covers that path, and the web build's catch-all route handles it. |
| Device tokens | `public.push_tokens` (`token`, `user_id`, `platform`), registered by `lib/services/reminder_service.dart` |
| Sending | `worker/remind.py` — FCM HTTP v1, auth from the `FIREBASE_SERVICE_ACCOUNT` env var via `google.oauth2.service_account` |
| Same secret in Deno | `supabase/functions/firebase-token/` already reads `FIREBASE_SERVICE_ACCOUNT` and mints a JWT with Web Crypto — copy that signing code |

So the only missing piece is the sender and the call site.

### Proposed shape

**1. Edge Function `supabase/functions/notify-table/index.ts`**

```
POST { roomId, groupId, gameId }
Authorization: <user JWT>

- anon client with the caller's JWT → confirms the caller is signed in
- verify caller ∈ group_members(groupId)
- service-role client → select token from push_tokens
    join group_members on user_id
    where group_id = <groupId> and user_id <> <caller>
- POST https://fcm.googleapis.com/v1/projects/efoc-fcf44/messages:send once per token
    notification: { title: "<hostName> opened <Game>", body: "Tap to join" }
    data:         { url: "https://efoc.party/join?table=…&group=…&game=…", type: "table" }
```

Read the game's display name from `kGames` on the client and pass it in, or keep a
small map in the function — the first is simpler.

**2. Client call** — right after the `OpenTables.instance.list(...)` at
`table_screen.dart:150`, fire and forget:

```dart
_notifyTable(groupId, roomId, widget.gameId); // swallow errors, never block the host
```

**3. Dedupe** — one push per room, not per re-list. Either a `table_pushes`
table keyed by `roomId`, or a `notified_at` column on a small table; the room id
is unique per table so it's a cheap guard. FCM also honours a `collapse_key` if
you'd rather let it coalesce.

### Decisions to make before writing code

- **Who gets it.** Everyone in the Log with a registered device is the easy
  answer, but a group of five gets five pushes per table. Alternatives: only
  people who played a game in the last day, or cap to one push per group per
  N minutes.
- **Mute.** There is no per-feature mute. `profiles.reminders_enabled` is for
  hourly reminders only — don't reuse it. If you add a switch, it belongs in the
  Games tab, not in profile.
- **Quiet hours.** A 3am "Aina opened Lucky 7" is worse than nothing.
- **Android channel + web click handler.** `web/firebase-messaging-sw.js` must
  handle `notificationclick` and open `data.url`, otherwise a tapped web push
  just focuses the app on whatever screen it was on.

### What to test

Two accounts, two devices: A opens Big Two → B's phone gets the push → tapping
it opens the table directly (not the games list). Then: A closes the room → B
gets nothing. Then: the same table is re-listed → B gets nothing twice.

---

## Not done, deliberately (Play Store)

Blocking a release, in order:

1. `android/app/src/main/AndroidManifest.xml` has **no `INTERNET` permission** — it
   lives only in the debug/profile manifests. A release build cannot reach the
   network at all.
2. `applicationId = "com.example.efoc"` — Play rejects `com.example.*`.
3. Release signs with the **debug key** (`android/app/build.gradle.kts`).
4. Deep links cover `/join` only; the sticker share link (`?pack=`) doesn't open
   the app.
5. UGC reporting/blocking doesn't exist — "Report this Log" is still a placeholder,
   and Play requires it before review.
6. No privacy-policy URL, feature graphic, screenshots or store copy.
7. Invite-only means a reviewer can't get in — supply a working account **and** a
   live invite code in Play Console → App access, or it's an instant rejection.
8. New individual accounts need **12 testers × 14 days** of closed testing first.

---

## Housekeeping

- Branch per task in a worktree, `deepseek/<task>`, merge to `main` only after
  `flutter analyze` is clean and `flutter build web` succeeds. Deploy with
  `build_web.bat`, then commit `chore(release)`.
- Migrations go in `supabase/migrations/YYYYMMDD_name.sql`, are run **by hand** in
  the SQL editor, and must land **before** the build that selects new columns.
- `flutter test` covers the sticker parser and the game/table-link logic.
- **Never open or print** the two `efoc-fcf44-firebase-adminsdk-*.json` files in
  the parent folder — they are live service-account credentials.
