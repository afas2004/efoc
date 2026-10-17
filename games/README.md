# EFOC card games

Big Two, Hearts, Zombie, 21 and Lucky 7 for 2–8 friends inside EFOC. Start
with [docs/spec.md](docs/spec.md), then [docs/decisions.md](docs/decisions.md),
which overrides the spec where they differ.

```
packages/engine/   @efoc/engine: pure, seeded rules, bots, simulator (Vitest)
apps/games-web/    Vite table client, one page per game -> games.efoc.party/<game>/
assets/            sounds, Lottie, icons, card art; every licence in LICENSES.md
firebase/          Realtime Database and Firestore rules (not deployed yet)
docs/              spec, decisions, rule sheets, Jester lines
```

The Flutter side lives in `../lib/games/` (see [docs/phase3c.md](docs/phase3c.md)).

```bash
npm install        # from games/
npm test           # engine tests
npm run typecheck
npm run sim        # bot-vs-bot simulation (Phase 1)
npm run build:web  # builds apps/games-web/dist
```

Publishing to GitHub Pages is the manual "Publish card games" workflow.
