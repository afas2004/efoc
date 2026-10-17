# Phase 3c — the games inside EFOC

Written and tested locally on 17 Oct 2026. Nothing is deployed.

## How it fits together

```
EFOC app (Flutter)                          game page (games.efoc.party/bigtwo/)
  Games tab ── Open a table / Join ──┐
  TableScreen                        │        OnlineGame (same code as Phase 3a)
    GameSession ◄── {t:'db', op, path, ...} ── BridgeStore (RoomStore)
       │        ──► {t:'dbResult' | 'dbValue' | 'dbChild' | 'dbClock'}
       ▼
  firebase_database (signed in with a custom token from
  supabase/functions/firebase-token, uid = Supabase user id)
```

- **Page:** `src/net/bridgeStore.ts`. Inside the app the page waits for
  `init`; `init.online` = `{room, uid, name, avatar, clockOffset, create?}`
  starts the online table on the bridge store. `create` (the host only)
  carries the group id and its member uids for `rooms/{id}/allowed`.
  `init.practice` opens Practice vs bots. The page never holds a token.
- **Transports:** Android WebView (`flutter_inappwebview`, JS handler
  `efoc`, other origins blocked) or, on the web build, an `<iframe>` with
  postMessage (origin and source checked both ways). Picked with
  `table_view_native.dart` / `table_view_web.dart`.
- **GameSession** (`lib/games/game_session.dart`) runs only paths under
  `rooms/{id}`, `presence/{id}`, `chat/{id}`; anything else is refused
  before it reaches Firebase. The rules still decide every read and write.
- **Connection:** `GamesDatabase.acquire()/release()` — online only while
  the Games tab or a table is open (Spark: 100 connections). Going offline
  runs the onDisconnect presence write, which now uses the server's time.
- **Open tables:** `tables/{groupId}/{roomId}` = `{gameId, hostUid,
  hostName, createdAt}`. The host lists the table once its room exists and
  takes it off when the match has results; the Games tab hides entries
  older than 6 h. Rules: any signed-in player can read a group's list (the
  group id is a uuid only members see); only the room's host can add,
  only players in the room can remove.
- **Seat avatars** are emoji picked from the uid (the rules cap avatars at
  16 characters), not profile photos.

## Tests

- `games/apps/games-web`: `tests/bridge.spec.ts` — a fake app page hosts two
  phones as iframes and answers their bridge calls from an in-memory
  database (with the same path limits); they play a full match with a bot.
- `test/games/game_session_test.dart` — path limits and every op.
- `games/firebase`: 4 new rules tests for `tables/`.
- `supabase/functions/firebase-token/token.test.mjs` — the custom token
  verifies against the key and has Firebase's claims (`node` it).

## Not done yet

- The "download once, serve locally" cache on Android (`InAppLocalhostServer`):
  the WebView loads games.efoc.party directly for now.
- Deep links to a table, rooms cleaned up after the match, the host's 60 s
  "host is away" countdown in Flutter (the page already migrates the host).

## Fahmi's steps to go live

1. Firebase console (efoc-fcf44): create the **Realtime Database** in
   **asia-southeast1** (locked mode). Its URL should be
   `https://efoc-fcf44-default-rtdb.asia-southeast1.firebasedatabase.app`
   (the app's default; tell me if it differs).
2. Firebase console → Project settings → Service accounts → **Generate new
   private key**. Keep the JSON file out of the repo.
3. Supabase: set the secret and deploy the function
   (`supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat key.json)"`,
   `supabase functions deploy firebase-token`). Then delete the local key file.
4. Deploy the rules: `firebase deploy --only database,firestore:rules`
   with `games/firebase/database.rules.json` and `firestore.rules`.
5. Firebase console → Authentication: make sure it's enabled (custom tokens
   need no provider switched on).
6. DNS: `CNAME games → afas2004.github.io`; in the repo's Pages settings set
   the custom domain `games.efoc.party` and enforce HTTPS.
7. Run the manual **Publish card games** workflow.
8. Build and release the app as usual (new packages: `firebase_auth`,
   `firebase_database`, `flutter_inappwebview`).
9. Phase 3 exit gate: 8 real phones finish a Fight Till The End match with
   the host's phone switched off mid-match.
