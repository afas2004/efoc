# Firebase rules (Spark plan, project efoc-fcf44)

- `database.rules.json`: Realtime Database rules for rooms, presence and
  chat, following the "Security rules (outline)" in docs/spec.md. This is a
  draft until Phase 3, when it gets emulator tests with
  `@firebase/rules-unit-testing`.
  - Chat's limit of 1 message per second: each message write must also set
    `chatRate/{room}/{uid}` to `now` in the same multi-path update, and
    that value can only move forward by 1000 ms or more.
  - Spectators are capped at 8 per room.
  - Host migration: a seated member may take `meta/hostUid` once the old
    host's presence is offline with `lastSeen` more than 60 s ago.
- `firestore.rules`: stats, achievements and reports.

Nothing here is deployed yet. Deploying needs the Realtime Database created
in the Firebase console and Fahmi's OK.
