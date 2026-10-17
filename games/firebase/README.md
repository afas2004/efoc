# Firebase rules (Spark plan, project efoc-fcf44)

- `database.rules.json`: Realtime Database rules for rooms, presence and
  chat, matching the protocol in `apps/games-web/src/net/protocol.ts`.
  - Group members (the room's `allowed` list, copied by the host when the
    table opens) can read a room so they can join it; only seated members
    send intents; each player reads only their own `hands/{uid}`; only the
    host reads/writes `hostState`, appends to the log (never rewrites it)
    and deals hands.
  - Host migration: a seated member may set `meta/hostUid` to themself, and
    nothing else in meta, once the old host's presence is offline and
    `lastSeen` is more than 60 s old.
  - Spectators: at most 8, via `spectatorSlots/0..7` (the rules language
    can't count children, so a slot is claimed in the same write as the
    spectator record).
  - Chat (Phase 4): 1 message per second via `chatRate/{room}/{uid}`, text
    1–200 characters, as yourself.
- `firestore.rules`: stats, achievements and reports.

## Tests

`npm test` here starts the Database and Firestore emulators (project
`demo-efoc-games`, nothing real) and runs `rules.test.ts` with
`@firebase/rules-unit-testing`. Needs Java 11+ and the Firebase CLI.

On Windows the emulators' Java can fail with "Unable to establish loopback
connection"; point its socket folder at a short path with no spaces:

    set JAVA_TOOL_OPTIONS=-Djdk.net.unixdomain.tmpdir=C:\src\tmp

Nothing here is deployed yet. Deploying needs the Realtime Database created
in the Firebase console and Fahmi's OK.
