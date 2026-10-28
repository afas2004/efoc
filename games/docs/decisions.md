# EFOC Card Games — Phase 0 decisions

Answers to everything [spec.md](spec.md) left open or that clashed with how
the EFOC app actually works. Settled with Fahmi on 17 Oct 2026. Where this
file and the spec disagree, this file wins.

## Platform and backend

| # | Question | Answer |
| --- | --- | --- |
| P1 | Where do the games run? | **Web and Android.** EFOC is mostly used as the Flutter web build at efoc.party, where `flutter_inappwebview` and `InAppLocalhostServer` don't work. On web the table is an `<iframe>` to `games.efoc.party/efoc/<game>/` talking over `postMessage`; on Android it's a WebView with the `efoc` JS handler. Both carry the same bridge messages (spec, Bridge protocol). The two transports are picked with conditional imports (`*_native.dart` / `*_web.dart`, `dart.library.js_interop`), like the rest of the app. On web the "download once, serve locally" cache is the browser's HTTP cache. |
| P2 | How does a player get a Firebase `auth.uid` for the Realtime Database rules? | **A Supabase Edge Function mints a Firebase custom token** whose uid is the player's Supabase user id. The app signs in to Firebase Auth with it. So `allowed/{uid}`, `hands/{uid}` and every other rule really is tied to the Supabase account and its group membership. Free: Supabase Edge Functions plus the Firebase Admin service-account key kept as a function secret, never in the repo. Built in Phase 3. |
| P3 | Where do stats, achievements and chat reports live? | **Firestore, as in the spec** (`users/{uid}/stats/{gameId}`, `users/{uid}/achievements/{id}`, `reports/{id}`), using the Firebase identity from P2. Live play is on the Realtime Database either way. The "Open table" card in the group still uses EFOC's Supabase group data. |
| P4 | Repository layout | **One repo: `games/` inside afas2004/efoc**, with the spec's layout under it (below). The repo is public, so GitHub Pages can publish `games/apps/games-web` from a manual-trigger Actions workflow. The Flutter side lives in `lib/games/`. |
| 8 | Game file hosting | **Changed (17 Oct):** games.efoc.party already serves Fahmi's other games from the `afas2004.github.io` repo, so the card games are this repo's GitHub Pages *project* site, which GitHub serves under the user site's domain: **`games.efoc.party/efoc/<game>/`**. No DNS change and no CNAME file. Fahmi sets Pages → Source → GitHub Actions once; updates are the manual "Publish card games" workflow. |
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

| Finishing on a 2 (online playtest, 18 Oct) | **Always on: going out with a 2 anywhere in your last play puts you last.** Standard: the round carries on until someone goes out properly (they win); the 2-finisher scores as if holding all 13 cards (39). If everyone else went out on a 2, the player left wins. Fight Till The End: 2-finishers fill the bottom places, the first of them very last. Bots avoid it; the Play button warns before you do it. | `twoFinishLoses: true` (no switch in the app) |

## Playtest changes (17 Oct)

- **The Jester is host-driven.** The host picks every line and sends it in the log as a `jester` event, so every player and spectator sees the same line at the same time. Lines describe what happened ("Mei played a pair of Ks…"). Big moments (bomb, last card, going out, win, round start) always speak; smaller ones keep the 15 s gap. He is a large animated original mascot with Noto animated emoji reactions.
- **Slower pacing.** Bots wait 0.9 to 4.2 s, plus a pause after big moments, so people can follow the table.
- **Seats show small card backs** with the count, and every action stamps the seat (PASS, PAIR, …).
- **Stats on every results screen**, plus a setup screen (players, mode, poker hands, humour) and "Change rules".
- **Playtest 2:** a turn chip above the hand ("YOUR TURN · beat it or pass" / "Speedy's turn…") with a glowing hand and a YOUR TURN pop; a "Before" strip with the two previous plays; humour defaults to **Spicy**; menu settings are switches; 2♠-style plays get an UNBEATABLE / UNSTOPPABLE moment with synced PASS stamps; results add the Jester's verdict and top-3 highlights.

- **Playtest 3:** a single 2♠ or any straight/royal flush gets a *legendary* moment (thrown up spinning with a rainbow edge, slammed down with a shockwave, then a big announcement with rays, sparkles, confetti and Noto emoji). It runs 3.8 s, longer than the spec's 1.5 s T3 cap, at Fahmi's request; it never blocks input and a tap skips it, and the auto-passed play stays on the table until it is done. 2s spent inside a combo in the first half of a hand get a "BIG SPENDER!" moment. Every deal is followed by a 5 s look-at-your-cards countdown (no moves until it ends). Results show a pedestal for the top three.

- **Playtest 4:** a big moment (legendary play, bomb, auto-pass, "Double it!") holds the next turn: the clock, the timer bar and moves wait until its animation has played, and the host refuses moves until then. The look-at-your-cards pause is **15 s**, with an "I'm ready" button that starts the game as soon as every human is ready.

## Lucky 7 (18 Oct)

The spec's rules stand. Clarified with Fahmi:

- A card taken from Discard can be swapped in, used (if a power card), or thrown straight back onto Discard.
- Fully blind: nobody sees their own cards at the start; only a J shows them.
- Full deck: play until the centre deck is empty, however many players.
- A locked card stays hidden even from its owner's J peek.
- **Playtest 18 Oct (corrected):** a J is **either/or**: see **all your own cards**, OR peek at **one card of another player**. Not both, and not just one of your own. Whatever you look at stays face up for you for `peekSeconds` (8 s). Locked cards stay hidden, yours included. Everyone else sees which cards are being looked at (they lift), never their faces.
- Power cards are single use: a used power goes to Used for good. One thrown away unused can still be taken off Discard and used (17 Oct decision).
- **Crowded tables (5+ players, 18 Oct):** other seats rest as mini cards (22 px) under their name badge. The seat whose turn it is grows to the 4-player size (about 45 px; a top-row seat fits between its neighbours) and is drawn over the felt; nothing else moves. In the final reveal the seat being flipped grows. A card I J-peek at shows at the grown size for its 8 s. Targeting small seats still goes through the focus sheet. My own cards are unchanged.
- The Jester reacts to public stories: a 7 or A thrown away, a 9 thrown when the next player is locked, a power left on Discard, a good card swapped out by mistake, revenge, grudges, halfway and the last card, close wins. It never repeats a line soon after itself.

## Zombie (28 Oct)

The spec's rules stand. Settled with Fahmi (first build, then his playtest the same day):

- **The table is a real table:** every player's hand sits at their edge of the screen, the same size as mine (smaller from 5 players), turned the way they hold it, half off the screen. The two players in an exchange expand (hands slide in, badges grow) and everyone else dims. Nothing is arranged in the middle except the pile.
- **Slow on purpose:** every step animates and waits for the last: shrink, expand, shuffle, point, wobble, fly, turn over, throw. Nothing is allowed to feel snappy; every action must be easy to follow.
- **Auto-shuffle:** the hand about to be drawn from shuffles itself (animated) at the start of every turn, so nobody can track the Zombie. No Shuffle button and no dragging.
- **Pick with a confirm:** tap a card to point at it (everyone sees it lift, its holder too), then tap it again or **Take it**. 15 s; at zero the card pointed at is taken, or a random one.
- **Throwing is manual:** pairs glow; tap one to throw it. At the deal everyone throws at once on one 20 s clock, with a **Throw all** button. A pair made by a draw has 10 s. At zero the game throws for you. **Auto-throw** in the menu throws for you every time. A pair flies to its exact place on the pile and stays there.
- **Results:** the loser's seat is eaten by the Zombie (T4); the results list who got safe 1st, 2nd…, the loser last, plus the Zombie's story: times it changed hands, who was dealt it, who held it longest, hot potato (taken from most), most pairs, draws.
- The host (seat 0) draws first; you draw from the next player clockwise still holding cards; a drawn card goes to the end of your hand. Pairs are by rank, any suits; the Zombie never pairs, not even with a J. The Zombie's path stays secret until the end (even the Jester doesn't know).

## Left for later (as the spec says)

- Pressure-rule numbers get tuned in beta.
- Optional "Double it!" gets decided in beta (Phase 7).
