# EFOC Card Games — Phase 0 decisions

Answers to everything [spec.md](spec.md) left open or that clashed with how
the EFOC app actually works. Settled with Fahmi on 17 Oct 2026. Where this
file and the spec disagree, this file wins.

## Platform and backend

| # | Question | Answer |
| --- | --- | --- |
| P1 | Where do the games run? | **Web and Android.** EFOC is mostly used as the Flutter web build at efoc.party, where `flutter_inappwebview` and `InAppLocalhostServer` don't work. On web the table is an `<iframe>` to `games.efoc.party/<game>/` talking over `postMessage`; on Android it's a WebView with the `efoc` JS handler. Both carry the same bridge messages (spec, Bridge protocol). The two transports are picked with conditional imports (`*_native.dart` / `*_web.dart`, `dart.library.js_interop`), like the rest of the app. On web the "download once, serve locally" cache is the browser's HTTP cache. |
| P2 | How does a player get a Firebase `auth.uid` for the Realtime Database rules? | **A Supabase Edge Function mints a Firebase custom token** whose uid is the player's Supabase user id. The app signs in to Firebase Auth with it. So `allowed/{uid}`, `hands/{uid}` and every other rule really is tied to the Supabase account and its group membership. Free: Supabase Edge Functions plus the Firebase Admin service-account key kept as a function secret, never in the repo. Built in Phase 3. |
| P3 | Where do stats, achievements and chat reports live? | **Firestore, as in the spec** (`users/{uid}/stats/{gameId}`, `users/{uid}/achievements/{id}`, `reports/{id}`), using the Firebase identity from P2. Live play is on the Realtime Database either way. The "Open table" card in the group still uses EFOC's Supabase group data. |
| P4 | Repository layout | **One repo: `games/` inside afas2004/efoc**, with the spec's layout under it (below). The repo is public, so GitHub Pages can publish `games/apps/games-web` from a manual-trigger Actions workflow. The Flutter side lives in `lib/games/`. |
| 8 | Game file hosting | **Confirmed:** GitHub Pages on `games.efoc.party`. Needs a DNS `CNAME games → afas2004.github.io` and the custom domain set in the repo's Pages settings, both done by Fahmi when we first publish. |
| 9 | Chat moderation | **Changed:** no word filter. Report and mute stay, since store policy expects them for user chat. |

```
efoc/                         (this repo)
  games/
    packages/engine/          @efoc/engine: rules for all five games, deal/burn rule, bots, simulator
    apps/games-web/           HTML table client (Vite): player and host mode, tiers, Jester
    assets/                   sounds, Lottie files, icons, card art, LICENSES.md
    firebase/                 database.rules.json, firestore.rules
    docs/                     spec, these decisions, per-game rule sheets, Jester line bank
  lib/games/                  hub, lobby, GameHost, GameSession, relay, chat, achievements (Phase 3+)
  supabase/functions/firebase-token/   custom-token mint (Phase 3)
```

## Big Two rules

| Question | Answer | Config flag |
| --- | --- | --- |
| Can a bomb (four of a kind, straight flush) beat a single or pair? | **No.** Every play must match the card count. "BOMB!" is only the reaction. | — |
| After passing, can you play again in the same trick? | **Yes.** A pass only skips that turn. The trick resets when play comes back to the last player who played and everyone in between passed. | `passLocksOut: false` |
| Which straights count? | **Any 5 cards in a row in Big Two order:** 3 4 5 6 7 8 9 10 J Q K A 2. Lowest 3-4-5-6-7, highest J-Q-K-A-2. No wrapping, so A-2-3-4-5 and 2-3-4-5-6 aren't straights. Compared by top card (rank, then suit). | `allowA2345: false`, `allow23456: false` (the spec's flags stay for other house rules, default off) |
| Flush vs flush | **Better suit wins** (♠ > ♥ > ♣ > ♦). Same suit: compare the highest card, then the next, and so on. | `flushCompare: 'suitFirst'` |
| Straight flush vs straight flush | Top card, rank then suit (as for straights). | — |
| Who leads round 2 onward? | **Whoever has 3♦**, every round (or the lowest card if 3♦ is burned). | — |
| Rounds per match | **1 by default.** The host gets a "Play again" button on the results screen. "Final round doubles" only applies when `roundsToPlay` > 1. | `roundsToPlay: 1` |
| Default mode | Standard. The host picks Fight Till The End on the setup screen. | `mode: 'standard'` |
| Poker hands (playtest, 17 Oct) | **On by default.** Two pair (2+2+1) and three of a kind (3+1+1) are also 5-card hands. Order: two pair < three of a kind < straight < flush < full house < four of a kind < straight flush. Two pair compares the higher pair, then the lower pair, then the best suit in the higher pair; three of a kind compares the triple. | `pokerHands: true` |
| Triples, four of a kind | Spec defaults: triples allowed, four of a kind is played as 4 + 1 kicker. | `allowTriples: true`, `fourOfAKindKicker: true` |

| Opening play (playtest 2) | **3♦ can't be the throw card.** In two pair, three of a kind or four of a kind + 1, the 3♦ (or the burned-3♦ fallback card) must be in the main group, not the kicker. | — |
| Unbeatable plays (playtest 2) | **Auto-pass.** A play nothing can beat (single 2♠, a pair with 2♠, three or four 2s, J-Q-K-A-2 of spades) makes everyone else pass at once, and the player leads again. In Fight Till The End, if they went out with it, the lead goes to the next player still in. | `autoPassUnbeatable: true` |

## Playtest changes (17 Oct)

- **The Jester is host-driven.** The host picks every line and sends it in the log as a `jester` event, so every player and spectator sees the same line at the same time. Lines describe what happened ("Mei played a pair of Ks…"). Big moments (bomb, last card, going out, win, round start) always speak; smaller ones keep the 15 s gap. He is a large animated original mascot with Noto animated emoji reactions.
- **Slower pacing.** Bots wait 0.9 to 4.2 s, plus a pause after big moments, so people can follow the table.
- **Seats show small card backs** with the count, and every action stamps the seat (PASS, PAIR, …).
- **Stats on every results screen**, plus a setup screen (players, mode, poker hands, humour) and "Change rules".
- **Playtest 2:** a turn chip above the hand ("YOUR TURN · beat it or pass" / "Speedy's turn…") with a glowing hand and a YOUR TURN pop; a "Before" strip with the two previous plays; humour defaults to **Spicy**; menu settings are switches; 2♠-style plays get an UNBEATABLE / UNSTOPPABLE moment with synced PASS stamps; results add the Jester's verdict and top-3 highlights.

- **Playtest 3:** a single 2♠ or any straight/royal flush gets a *legendary* moment (thrown up spinning with a rainbow edge, slammed down with a shockwave, then a big announcement with rays, sparkles, confetti and Noto emoji). It runs 3.8 s, longer than the spec's 1.5 s T3 cap, at Fahmi's request; it never blocks input and a tap skips it, and the auto-passed play stays on the table until it is done. 2s spent inside a combo in the first half of a hand get a "BIG SPENDER!" moment. Every deal is followed by a 5 s look-at-your-cards countdown (no moves until it ends). Results show a pedestal for the top three.

- **Playtest 4:** a big moment (legendary play, bomb, auto-pass, "Double it!") holds the next turn: the clock, the timer bar and moves wait until its animation has played, and the host refuses moves until then. The look-at-your-cards pause is **15 s**, with an "I'm ready" button that starts the game as soon as every human is ready.

## Left for later (as the spec says)

- Pressure-rule numbers get tuned in beta.
- Optional "Double it!" gets decided in beta (Phase 7).
