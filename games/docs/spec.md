# EFOC Card Games — Ground-Up Spec

Oct 17, 2026 · @Fahmi

## Overview

Five multiplayer card games (Big Two, Hearts, Zombie, 21, Lucky 7) run as HTML games inside the EFOC Flutter app for 2 to 8 friends. The host's phone referees each match, and free Firebase plus GitHub Pages carry everything else, so running costs are zero. Every important moment gets a loud, funny reaction sized to how much it matters.

### Goals

- 2 to 8 friends play any of the five games together, in real time, inside the app.
- Zero running cost: the Firebase free (Spark) plan and GitHub Pages only.
- No player sees another player's hidden cards. The host's app referees, so it is the one exception.
- Every key decision, swing, win and loss lands with motion, sound and a joke, scaled to its size.
- One table UI, one feedback system, one chat and one achievement system shared by every game.
- Game updates ship without an app store release.
- Bots fill empty seats and take over disconnected or AFK players.

### Non-goals for v1

- Public matchmaking with strangers. Play happens inside a vlog app group, and only its members can join or watch.
- Real money, betting, or chips. Scores are points only.
- Playing outside the app in a normal browser.
- Cheat-proofing against the host. Fine among friends; the backend section explains the trade-off.
- Ranked ladders and tournaments.

### Decisions

| # | Decision | Answer | Status |
| --- | --- | --- | --- |
| 1 | Zombie rules | Old Maid style, one Joker is the Zombie | Confirmed |
| 2 | Lucky 7 rules | 3 hidden cards each, draw then swap, discard or use; power cards J, Q, K, 9, 10; lowest total wins | Confirmed |
| 3 | Big Two rules | ♦ < ♣ < ♥ < ♠, 3♦ leads, Standard and Fight Till The End modes | Confirmed |
| 4 | 21 format | Rotating banker, points only | Confirmed |
| 5 | Hearts | Standard passing, game ends at 100 | Confirmed |
| 6 | Crowd size | Up to 8 players; leftover cards burned at random | Confirmed |
| 7 | Backend | Host phone referees on free Firebase; no paid services | Confirmed |
| 8 | Game file hosting | GitHub Pages on `games.efoc.party` | Proposed |
| 9 | Chat moderation | On-device word filter, report, mute | Proposed |

### Decided on 17 Oct

- Lucky 7: a power card thrown to Discard without being used can be taken and used by the next player. A used power card goes to Used and can never be taken or used again.
- Lucky 7: a K lock adds nothing to the score.
- Lucky 7: one round, played until the centre deck is empty. The host goes first.
- All games: waiting room, live spectator view, vote to end with no host end button, and a summary even when a match stops early. See Match flow.
- Big Two Fight Till The End: placement penalty, 1st 0, each later place +1.
- Hearts with 6 or more players: 2 cards, left or right, picked against a visible countdown with auto-select at zero.
- "Double it!" is no longer a player bet. The game itself raises the stakes to punish stalling. See Match flow.
- Host: only the work that needs hidden cards or one shared clock. Every phone runs the public rules and their effects on the spot.

* Pressure rule numbers get tuned in beta.
* Vote to end: anyone can start one, once per round or once per cycle of turns, and a simple majority of human players ends the match.
* Spectators: capped at 8 per room.

## System architecture

Every phone runs the same Flutter app and game page. The host's phone also runs the engine as referee, and free Firebase plus GitHub Pages carry the rest.

&#91;embedded content: system architecture · phone and Firebase\]

Moves travel as intents through Realtime Database to the host, which appends them to a public log that every phone plays on the spot; hidden cards go only to their owner. Firestore, not drawn, only stores stats and achievements at match end.

### Repository layout

```
efoc-games/                 one monorepo, so every phone runs the same engine version
  packages/engine/          rules for all five games, burn rule, bots, simulator
  apps/games-web/           HTML table client: player and host mode, tiers, Jester
  assets/                   sounds, Lottie files, icons, card art, LICENSES.md
  firebase/                 database.rules.json, firestore.rules
  docs/                     this spec, per-game rule sheets, Jester line bank
efoc-app/                   existing Flutter vlog app
  lib/games/                hub, lobby, GameHost, GameSession, host relay, chat, achievements
```

## Game rules

All five games use one 52-card deck (Zombie adds a Joker) and seat up to 8 players. Every house rule is a config flag, so a room can switch variants without new code.

### Shared deal rule for big crowds

- Games that deal the whole deck evenly (Big Two, Hearts) give each player 52 ÷ players cards, rounded down.
- The leftover cards (52 mod players) are burned: picked at random, removed face down, never shown.
- Burning can remove an opening card, so each game names its fallback below.
- 21, Lucky 7 and Zombie never burn.

| Game | Players | Cards each at 4 / 8 players | Burned at 8 | Logic difficulty | Build order |
| --- | --- | --- | --- | --- | --- |
| Big Two | 2-8 | 13 / 6 | 4 | High: combo detection | 1st |
| 21 | 2-8 | 2-5, drawn | 0 | Low | 2nd |
| Hearts | 3-8 | 13 / 6 | 4 | Medium: tricks, passing | 3rd |
| Zombie | 2-8 | 13-14 / 6-7 | 0 | Low rules, tricky UI | 4th |
| Lucky 7 | 2-8 | 3 hidden | 0 | Medium rules, many UI states | 5th |

### Big Two

- **Rank:** 3 low, then 4 to K, A, 2 high. **Suits:** ♦ < ♣ < ♥ < ♠.
- **Deal:** the shared rule, capped at 13 cards each. With 2 or 3 players, the cards past 13 each stay out face down.
- **Lead:** the 3♦ holder leads and the play must include 3♦. If 3♦ is burned, the holder of the lowest card leads with it.
- **Legal plays:** single, pair, triple, or a 5-card hand. Each play must match the current card count and beat it.
- **5-card order:** straight < flush < full house < four of a kind + 1 < straight flush.
- **Comparison:** singles and pairs by rank then highest suit. Straights by top card. Full house and four of a kind by the triple or quad rank.
- **Passing:** when everyone else passes, the last player to play leads anything.
- **Mode, Standard:** the round ends when the first player empties their hand. Everyone else takes penalty points equal to cards left. 10 to 12 cards count double, 13 triple.
- **Mode, Fight Till The End:** play continues until one player still holds cards. Finished players are skipped. If a finished player had just won the lead, it passes to the next player still in. Placement penalty: 1st 0, each later place +1, and the last player also adds cards left.
- **Flags:** `mode`, `allowA2345`, `allow23456`, `allowTriples`, `fourOfAKindKicker`, `roundsToPlay`.

### Hearts

- **Players:** 3 to 8. Four is the classic table.
- **Deal:** the shared rule.
- **Pass:** 3 cards left, right, across, then no pass, repeating. With 6 or more players, 2 cards, left or right only. Everyone picks at once against a visible 15 s countdown, and anyone still choosing at zero gets cards auto-selected.
- **Lead:** 2♣ leads the first trick. If 2♣ is burned, the lowest club held leads.
- **Tricks:** follow suit if able. Highest card of the led suit wins and leads next.
- **First trick:** no hearts and no Q♠ unless the player has nothing else.
- **Hearts broken:** hearts can't be led until one has been played, unless the leader holds only hearts.
- **Scoring:** each heart is 1 point, Q♠ is 13. Shooting the moon means taking every point card that was dealt (burned ones don't count). It gives everyone else 26.
- **End:** at 100 points. Lowest score wins.
- **Flags:** `passPattern`, `passCount`, `endScore`, `jackOfDiamondsMinus10`, `moonOption`.

### 21

- **Roles:** one banker, everyone else plays against the banker. The banker seat rotates each round.
- **Deck:** one deck reshuffled every round. 8 players × 5 cards is 40, so one deck always fits.
- **Deal:** 2 cards each, hidden from other players. The banker shows one card.
- **Values:** A is 1 or 11, J Q K are 10, others face value.
- **Turn:** hit or stand, up to 5 cards. Over 21 busts.
- **Banker:** hits below 16, stands on 16 or more (`bankerStandsOn`).
- **Results:** natural 21 (A + 10-value) scores 2, five cards at 21 or under scores 2, a normal win 1, a tie 0.
- **Points only:** no betting, chips or stakes.

### Lucky 7

Lowest hidden total wins, and nobody sees their own cards without a power card. It is a game of memory, bluffing and sabotage.

- **Players and deck:** 2 to 8 players, 52 cards.
- **Deal:** 3 face-down cards per player in slots 1 to 3. Nobody sees them, not even the owner. The rest form the centre deck.
- **Order:** the host takes the first turn, then play goes clockwise.
- **Piles beside the centre deck:** a face-up Discard pile and a Used pile. Unused cards go to Discard, where the next player may take the top one. Power cards that were used go to Used and can never be taken or used again.
- **Values:** 7 = 0, A = 1, 2 to 10 face value, J Q K = 10.
- **Turn:** draw the top of the centre deck (only you see it), or take the top card of Discard (everyone sees it). Then choose one:
  - **Swap:** place it face down into one of your slots. The card it replaces goes face up onto Discard.
  - **Discard:** place it face up on Discard.
  - **Use:** if it is a power card, from the centre deck or from Discard, do its effect. It then goes to Used.
- **End:** one round, played until the centre deck is empty. The last turn finishes, then everyone reveals. Lowest total wins; ties share the win. A K lock adds nothing to the score.
- **Flags:** `peekSeconds` (default 10).

| Card | Power | Effect |
| --- | --- | --- |
| J | Peek | See all your own cards for 10 s with a countdown ring, then peek at one opponent card. Only you see them. |
| Q | Swap | Exchange one of your cards with one opponent card, both unseen. |
| K | Lock | Put the K on any one card, yours or an opponent's. A locked card can't be peeked, swapped or shuffled, and stays in its slot. |
| 9 | Unlock | Remove any one lock on any player (the K goes to Used), or skip. The only counter to K. |
| 10 | Shuffle | Randomly rearrange the slots of yourself or one opponent. Locked cards stay in place. |

Peek results go only to the peeker as private events. The engine never tracks what players remember.

### Zombie

- **Players and deck:** 2 to 8 players, 52 cards + 1 Joker, the Zombie.
- **Deal:** all cards, uneven hands allowed. No burning, because removing a card would leave an unmatched rank.
- **Pairs:** each player discards every pair of the same rank.
- **Turn:** draw one face-down card from the next player's hand, discard any new pair, then the next player draws from you.
- **Shuffle:** before being drawn from, a player may reorder their hand. This bluffing is the core of the game.
- **End:** empty hands are safe. The last player holding the Zombie loses.
- **Hidden positions:** the drawer picks a slot index, never a card. The host maps the slot to the card through the holder's private order.

## Match flow (all games)

Every game shares one flow: waiting room, play against visible timers, an optional vote to end, and a summary however the match ends. Starting the match is the host's only special power.

### Waiting room

- **No separate lobby screen.** The table is the waiting room: the play area is greyed out with "Waiting for players" while seats fill.
- Tables open inside a vlog app group. Only that group's members can take a seat or watch.
- Each seat shows a Ready toggle and connection quality. The host taps Start once the game's minimum is ready, and empty seats can take bots.
- Anyone who joins after the start becomes a spectator.

### Spectators

- Spectators see the table live, with public information only: played cards, piles, card counts, scores. Never anyone's hidden cards.
- Players who are out (finished in Fight Till The End, safe in Zombie) switch to spectator view for the rest of the match.
- Spectators can chat and send quick phrases and throwables, but can't vote.
- At most 8 spectators per room, to protect the 100-connection limit.

### Timers and auto-select

- Every decision shows a ticking ring and a bar that turns red in the last 5 s, with a tick sound each second at the end.
- At zero the game auto-selects for that player with the Easy bot and stamps it "Too slow!".
- Two auto-selects in a row mark the player AFK until they tap "I'm back".
- A Fast room setting halves every timer.

| Decision | Time |
| --- | --- |
| Big Two turn | 20 s |
| Hearts pass, everyone at once | 15 s |
| Hearts trick play | 15 s |
| 21 hit or stand | 10 s |
| Lucky 7 turn | 20 s, plus 10 s for a J peek |
| Zombie draw | 10 s |

### Pressure rules ("Double it!" redesigned)

The game raises the stakes, not a player, and stalling is what gets punished. Points only. The idea of stakes rising automatically late in a game comes from [Marvel Snap](https://en.wikipedia.org/wiki/Marvel_Snap).

- **Slowpoke tax:** each auto-select earns a slowpoke stamp. A player's third stamp in one match triggers "Double it!" on them, so their penalty for that round doubles. T3 banner, laughing Jester.
- **Final round doubles:** in multi-round matches (Big Two `roundsToPlay`), the last round counts double, announced with a T3 banner.
- **Lucky 7 final lap:** when the centre deck has one card per player left, every timer halves and the felt pulses red.
- The numbers get tuned in beta.

### Vote to end

- Any player can start a vote from the table menu. There is no host-only end button.
- The match ends if more than half of the human players vote yes within 20 s. Bots and spectators don't vote.
- **Vote window:** one vote per round, shared by everyone. In games with one long round (Lucky 7), one vote per cycle of turns instead.
- **Minimum gap:** if a cycle is short, the window spans as many cycles as it takes to reach at least 2 minutes of play since the last vote.

### Match summary

- Shown after every match, including one stopped by a vote or abandoned.
- **Standings:** final scores, or the scores at the stop marked "Unfinished". Lucky 7 reveals every hand when stopped.
- **Highlights:** the 3 biggest moments from the event log, T3 moments first, replayed as short clips.
- **Per player:** cards played, timeouts, Jester roasts received, achievements unlocked.
- Unfinished matches keep their highlights but record no wins or losses.

## Game feel, humour and hype

Feedback is designed with the rules, not added afterwards. Every action gets an instant reaction, and the size of the reaction matches the size of the moment.

### What the research says

| Lesson | Source | What we do with it |
| --- | --- | --- |
| Strip the animation and sound from Balatro and it is a calculator; the feedback is the product | [Balatro breakdown](https://blakecrosley.com/guides/design/balatro) | Feedback is specified per event in this doc, before code |
| Stack channels in one beat: card motion, particles, rolling numbers, sound | [Balatro breakdown](https://blakecrosley.com/guides/design/balatro) | Every tier fires motion, sound, haptic and text together |
| Shake strength carries information: a bigger score shakes harder | [Balatro breakdown](https://blakecrosley.com/guides/design/balatro) | Shake and volume scale by tier, never random |
| Each scored card plays a rising note; a big threshold gets a bass hit and flash | [Balatro breakdown](https://blakecrosley.com/guides/design/balatro) | Multi-card plays step up in pitch per card |
| Juice changes no rules: tweening, particles and sound make a dull game alive | [Juice It or Lose It, via Kenney's list](https://kenney.nl/learn/must-see-videos-for-indie-developers) | Same engine, a juicy renderer on top |
| Screen shake is added per action and decays quickly | [Nijman on Nuclear Throne](https://infovore.org/tag/feel/) | Shake is short and fades within the tier's time |
| One colour means one thing everywhere | [Balatro breakdown](https://blakecrosley.com/guides/design/balatro) | Fixed colour roles, below |
| Everyone waits for the drawer's reaction; that tension carries the game | [Exploding Kittens playtest notes](https://www.tuni.fi/playlab/?p=11880) | Suspense beat before hidden reveals |
| Doubling the stakes mid-game, borrowed from backgammon's cube, adds hype | [Marvel Snap](https://en.wikipedia.org/wiki/Marvel_Snap) | Optional "Double it!" call |
| Limited emotes still get misused; some were cut as "used for evil" | [Hearthstone emotes](https://hearthstone.wiki.gg/wiki/Emote) | Curated reactions, cooldowns, per-player mute |
| Things to fiddle with between turns make a digital table feel physical | [Hearthstone's board](https://popmatters.com/180652-playing-with-the-pieces-hearthstone-and-the-physical-aspects-of-play-2495669954.html) | Idle toys on the table |
| Tables laugh hardest when chance wrecks someone's plan | [Humour in board games](https://lestmyopinions.com/2019/03/10/the-secret-ingredient-of-a-great-game/) | Jokes trigger on reversals, not on a timer |

### Moment tiers

Each engine event maps to one tier. The tier sets duration, shake, sound, haptic and text, so a moment of the same weight feels the same in all five games.

| Tier | When | Motion | Sound and haptic | Max length |
| --- | --- | --- | --- | --- |
| T0 Touch | Select, sort, drag | Lift 18 px, slight tilt | Soft click, light tick | 150 ms |
| T1 Play | Normal play, draw, pass | Card flies and lands with a squash | Card thud, pitch steps up per card | 300 ms |
| T2 Swing | Beat a strong play, take points, peek, lock, a good card grabbed | Pop-up word, small shake, particles | Whoosh and chime, medium haptic | 700 ms |
| T3 Big | Bomb, straight flush, shoot the moon, natural 21, comeback | Table dims, banner, animated burst, big shake | Bass hit, strong haptic | 1.5 s, tap to skip |
| T4 Ending | Round and match results | Podium, confetti for the winner, roast card for last | Fanfare or sad trombone | 4 s, tap to skip |

- One T3 plays at a time and others queue. T0 and T1 never queue.
- Input is never blocked longer than 1.5 s, except the T4 results screen.
- Reduced motion keeps sound, haptics and text, and swaps motion for a fade.
- The engine emits events and the renderer picks the tier. No game hand-codes its own effects.
- **Feedback never leaks hidden information.** Private moments play only on the owner's screen, and everyone else sees a neutral T1.

### Key moments per game

| Game | Moment | Tier | Reaction |
| --- | --- | --- | --- |
| Big Two | Four of a kind or straight flush played | T3 | "BOMB!" banner, table shake, explosion |
| Big Two | Everyone passes on your play | T2 | Jester shrug: "Nobody? Nobody." |
| Big Two | A player goes out in Fight Till The End | T2 | Seat turns gold, place number pops |
| Big Two | Last player still holding cards | T4 | Roast card on their seat |
| Hearts | Q♠ taken | T2 | The queen slides to the taker: "She's yours now." |
| Hearts | Shoot the moon | T3 | Moon rises, everyone else's score ticks up 26 |
| 21 | Bust | T2 | Cards crumble: "So close. Not really." |
| 21 | Natural 21 | T3 | Gold flash and star burst |
| 21 | Banker beats every player | T3 | "Banker's Day" banner |
| Lucky 7 | A 7, an A, or an unused power card thrown away, then grabbed by the next player | T2 | Laughing Jester over the Discard pile: "Thanks for the gift!" |
| Lucky 7 | Card locked with K | T2 | Padlock slams onto the slot |
| Lucky 7 | Lock broken with 9 | T2 | Padlock shatters |
| Lucky 7 | Your slots shuffled with 10 | T2 | Your cards spin: "Good luck remembering." |
| Lucky 7 | Final reveal | T4 | Seats flip one by one, lowest total last |
| Zombie | You draw the Zombie | T3, your screen only | Zombie grin on your card, others see a normal draw |
| Zombie | Hand empties, player safe | T2 | "SAFE" stamp on the seat |
| Zombie | Last holder | T4 | Zombie eats the seat avatar |
| All | Win after being last at halfway | T3 | "Comeback!" banner |

### Suspense beats

- Before a hidden card is revealed (Zombie draw, Lucky 7 reveal, the banker's hidden card), it wobbles for 400 ms with a heartbeat, then flips.
- The drawing player's seat zooms slightly on every screen, so everyone "watches the reaction" like at a real table.

### Humour system

- **The Jester:** one original mascot who comments on play. Its lines live in locale files, keyed by event, so new jokes need no code.
- **Example lines:** "Spending your 2 already? Bold." · "Pass, pass, pass. Riveting." · "That card was worth zero. You threw it away." · "Comeback arc loading…" · "Alamak, spend your 2 so early ah?" · "Walao, pass again?"
- **Rules:** at most one Jester line per 15 s. Never the same target twice in a row. Losers get as many cheering lines as teasing ones. No jokes about looks, race, religion or money.
- **Humour level per room:** Off, Mild, or Spicy, set by the host.
- **Bot personalities, by behaviour:** Speedy (plays instantly, emotes a lot), Slowpoke (uses the whole timer, sighs), Bluffer (loves "Double it!"), Grandmaster (quiet, plays well).
- **Throwables:** tap a seat to throw a tomato, rose or slipper. It flies across the table and splats on their avatar. Three per player per round.
- **Quick phrases:** "Nice!", "Hurry up", "Alamak", "GG". "GG" unlocks only after the round ends, so it can't be used as an early taunt.
- **Idle toys:** flick a card in your hand, tap the felt to drum, nudge the discard pile.

### Optional: "Double it!"

Off by default. Once per round, any player may tap "Double it!" and the round's points double. Others can fold right away for half the usual penalty. It is borrowed from Marvel Snap and backgammon, uses points only, and gets tried in beta before it is enabled.

### Consistency rules

- **Motion:** spring ease-out for arrivals, quick ease-in for departures, durations from the tier table.
- **Colour roles** in all five games: gold is good for you, red is penalty or danger, blue is information (peeks, hints), purple is a power card, green is your turn. Colour is never decoration.
- **Sound:** one card-sound pack and one UI pack, mixed to the same loudness.
- **Type and cards:** one type scale and one card design everywhere. Only the felt colour changes per game.
- **Same weight, same reaction:** every event goes through the tier table.

## Assets and layout

Every sound, animation and icon comes from free, licence-clear sources rather than being drawn in code. CC BY assets are credited on an in-app credits screen.

### Asset sources

| Use | Source | Licence | Credit required |
| --- | --- | --- | --- |
| Deal, shuffle, card slap, chip sounds | [Kenney Casino Audio](https://opengameart.org/content/54-casino-sound-effects-cards-dice-chips) | CC0 | No |
| Button clicks, blips, UI sounds | [Kenney audio packs](https://defold.com/assets/kenney) | CC0 | No |
| Card faces and backs, the style reference | [Kenney Boardgame Pack](https://opengameart.org/content/boardgame-pack) | CC0 | No |
| Animated reactions and Jester expressions (laugh, skull, explode, fire) | [Noto Animated Emoji](https://pub.dev/packages/animated_emoji), as Lottie, WebP or GIF | CC BY 4.0 | Yes |
| Confetti, explosions, padlock, moon | [LottieFiles free animations](https://help.lottiefiles.com/animation-licensing-basics-) | Lottie Simple License | No, but encouraged |
| Power-card and achievement icons (padlock, crown, zombie) | [game-icons.net](https://game-icons.net/about.html) | CC BY 3.0 | Yes |

- The Lottie Simple License allows commercial use, but you can't redistribute the files on their own. Check each animation's page, because some creators add restrictions.
- **One style:** flat, rounded cartoon on coloured felt, matching Kenney's cards and Noto's emoji. Lottie effects are picked to match that look and recoloured to the colour roles. Microsoft's 3D Fluent emoji are dropped because they clash.
- **Players:** `lottie-web` or `dotlottie-web` in the HTML, the `lottie` package on Flutter screens.
- **Budget:** under 60 KB per Lottie effect, under 2 MB per game including sounds. T3 and T4 assets preload when the table opens.
- **Final card art:** Kenney's cards set the style. Anything missing (Joker, power-card marks, padlock overlay) is added in the same look rather than drawing a new deck.

### Mobile layout for 2 to 8 players

Portrait phone at 360 × 780 is the primary layout. Your hand and action bar sit at the bottom; when space runs short the play area shrinks, never the hand.

| Players | Opponent seats in portrait | Seat size |
| --- | --- | --- |
| 2 | One, top centre | Full seat card |
| 3-4 | Left, top, right | Full seat card |
| 5-6 | Left-middle, top-left, top, top-right, right-middle | Compact |
| 7-8 | Two down each side, three across the top | Compact, 44 px avatar |

- **Seat chip:** avatar, name (first 8 characters), card count, turn ring, connection dot. Lucky 7 adds three mini card slots with lock icons.
- **Targeting small seats:** tapping a seat for a Lucky 7 power or a throwable opens a focus sheet with large card slots. Eight players stay tappable without 20 px targets.
- **Big hands:** past 13 cards (Zombie with 2 players can reach 27), the hand switches to two overlapping rows.
- **Landscape and tablet:** seats sit on an oval around a larger play area.
- **Safe areas:** respect notches and the home bar. The chat button sits bottom-right, above the action bar.
- **Same layout code for all five games.** Each game only defines its centre area (trick, piles, banker) and its seat extras.

## Rules engine

One TypeScript package, `@efoc/engine`, holds every game's rules as pure functions. Every phone runs it on each public log entry to update the table and play its effects on the spot. The host's copy also deals and draws hidden cards, orders moves and runs timers. Bots and tests use the same code.

### Card model

- A card is a 2-character id: rank `3456789TJQKA2` + suit `dchs`, e.g. `3d`, `As`, `Th`. The Joker is `JK`.
- Rank and suit order are per game, defined as lookup tables, never hard-coded in comparisons.
- Invariant: every card is in exactly one place (a hand, the deck, a pile, a trick). Tests check this after every move.

### Module interface

```ts
interface GameModule<Config, State, Move> {
  id: 'bigtwo' | 'hearts' | 'twentyone' | 'lucky7' | 'zombie';
  minPlayers: number; maxPlayers: number;
  defaultConfig: Config;
  setup(seats: SeatId[], config: Config, rng: Rng): State;
  legalMoves(state: State, seat: SeatId): Move[];
  validate(state: State, seat: SeatId, move: Move): { ok: true } | { ok: false; reason: string };
  apply(state: State, seat: SeatId, move: Move, rng: Rng): { state: State; events: GameEvent[] };
  view(state: State, seat: SeatId | 'public'): PlayerView;
  result(state: State): RoundResult | null;
  bot(view: PlayerView, level: 'easy' | 'normal', rng: Rng): Move;
}
```

### Engine rules

- **Pure and deterministic:** no `Date`, no `Math.random`, no I/O. Same state + move + seed gives the same result.
- **Seeded RNG:** the host draws a fresh seed per round from `crypto.getRandomValues` and keeps it in host-only state.
- **Shared deal:** `core/deal.ts` implements the burn rule and the 13-card cap once for every game.
- **Split apply:** the host's `apply()` returns one public log entry plus private updates per seat. Every phone's `applyPublic(entry)` advances the public state from the log alone, so all phones show the same table.
- **Log positions:** each entry has a number `n`. A move names the position it was made against, and a stale move is rejected.
- **Checksums:** every 20 entries the host adds a hash of the public state, and phones compare it with their own to catch any drift.
- **Events:** entries carry typed events (`card_played`, `bomb`, `hearts_broken`, `shot_the_moon`, `card_locked`, `good_card_grabbed`, `player_out`, `round_ended`). Events drive the moment tiers and achievements.
- **Private events:** peeks, Zombie draws and drawn-card reveals carry a `to` seat and go only to that player.
- **Moves are data:** e.g. `{ type: 'play', cards: ['3d','4d','5d','6d','7d'] }`, `{ type: 'use', power: 'Q', mine: 1, target: { seat: 3, slot: 2 } }`, `{ type: 'draw', from: 'discard' }`.

### Bots

- **Easy:** a random legal move, weighted toward low cards.
- **Normal:** per-game heuristics. Big Two holds 2s and bombs and plays the lowest beating combo. Hearts voids a suit early, dumps Q♠ safely, and avoids tricks with points. Lucky 7 blocks rows where it holds the gating card.
- Bots only see `view()`, the same as a human, so they cannot cheat.
- The same bot code fills empty seats and replaces a player after the AFK timeout.

### Package layout

```
packages/engine/
  core/      cards.ts  rng.ts  types.ts  combos.ts
  games/     bigtwo/  hearts/  twentyone/  lucky7/  zombie/
             each: rules.ts  bot.ts  config.ts  rules.test.ts
  sim/       simulate.ts   (bot-vs-bot runner for tests)
```

## HTML game client

Each game page draws the table, plays the moment tiers and sends the player's move. On the host's phone, the same page also runs the engine as referee.

### Build and delivery

- Shared source (table shell, card renderer, tier and feedback system, Jester, bridge) plus one module per game.
- Vite builds one HTML file per game, with its Lottie and sound files beside it.
- Hosted on GitHub Pages at `games.efoc.party/<game>/`, with a `version.json` per game.
- Flutter downloads each new version once and serves it from the phone, so each phone costs bandwidth once per update.

### Two modes in one page

| Mode | Runs on | Does |
| --- | --- | --- |
| Player | Every phone, spectators too | Applies each log entry and plays its effects at once, shows its own hidden cards, sends moves, shows legal-move hints |
| Host | The host's phone, on top of player mode | Deals and draws hidden cards, checks moves against hidden cards, puts moves in one order, runs timers, auto-select and bots |

The host only does what needs hidden cards or one shared clock. Your own legal move animates the moment you tap, before the host confirms it; a rare rejection snaps the cards back with the reason.

### Table layout

- Seat positions follow the 2 to 8 player table in Assets and layout.
- **Card size** comes from the viewport: `cardW = min(viewportW / 8.5, viewportH / 6)`, height = width × 1.4. No fixed pixel positions.
- **Hand:** a fan along a shallow arc when it fits, a flat overlap when it doesn't, two rows past 13 cards.
- **Sorting:** auto-sort by the game's rank order, with a rank or suit toggle.

### Input

- **Tap** a card to raise it 18 px. Big Two allows several. **Long press and drag** reorders, which Zombie bluffing needs.
- **Play** is enabled only when the selection is legal, using the engine locally. Swipe up on a selected card also plays.
- **Lucky 7:** two draw buttons (centre deck, Discard), then an action sheet (Swap, Discard, Use). Targets are chosen in the seat focus sheet. J shows a 10 s countdown ring while your cards are face up. Locked slots show a padlock and can't be tapped.
- **Zombie draw:** tap one of the opponent's face-down cards. It wobbles, then flips once the host confirms.
- Targets at least 44 px. Every action also works with a screen reader through labelled buttons.

### Animation and feedback

- **Event queue:** state arrives with events. Each event plays its tier, then the final state shows. Rules never wait on animation.
- **FLIP technique:** record the card's old box, render the new layout, animate `transform` from old to new. Only `transform` and `opacity` animate.
- **Z-order:** a moving or dragged card goes to the top layer until it settles.
- **Rejected move:** short shake plus the reason, as a T1.
- **Reduced motion:** from the OS or Flutter setting, as defined under moment tiers.

### Bridge protocol

JSON messages with a type field `t`. Flutter to game uses `window.efoc.receive(msg)`. Game to Flutter uses `flutter_inappwebview.callHandler('efoc', msg)`.

| Direction | `t` | Payload |
| --- | --- | --- |
| Flutter → game | `init` | gameId, mySeat, isHost, isSpectator, players, locale, settings, humour level, safe-area insets |
| Flutter → game | `log` | new log entries, each a move with its public events |
| Flutter → game | `private` | my hidden cards and private events |
| Flutter → game | `snapshot` | public state at an entry, for joining or reconnecting |
| Flutter → game | `rejected` | log position, reason |
| Flutter → game | `pause` / `resume` | app backgrounded, reconnecting |
| Flutter → game (host) | `intent` | sender seat, log position, move |
| Flutter → game (host) | `restore` | saved host state after the host app restarts |
| Game → Flutter | `ready` | renderer version |
| Game → Flutter | `move` | log position it was made against, move |
| Game → Flutter (host) | `output` | next log entry, private updates per seat, a snapshot every 20 entries |
| Game → Flutter | `vote` | start or answer a vote to end |
| Game → Flutter | `haptic` | light, medium, strong, error |
| Game → Flutter | `exit` | player tapped leave |

### In-game screens

- The table, a round-results overlay, a rules panel per game, and a first-time tutorial round against bots.
- Lobby, invites, chat, profile and achievements are Flutter screens.

## Free backend (host-refereed)

The Firebase free (Spark) plan has no Cloud Functions, so the host's phone handles only the jobs that need hidden cards or one shared clock, and Firebase relays. Every phone runs the public rules itself, so the host sends small log entries instead of whole tables.

### Free-tier budget

| Service | Free limit | Our use |
| --- | --- | --- |
| Realtime Database connections | 100 at once on Spark ([limits](https://firebase.google.com/docs/database/usage/limits)) | Phones connect only while on a game screen. 100 is about 12 full 8-player tables at once. |
| Realtime Database download | 10 GB a month ([pricing](https://firebase.google.com/pricing)) | Game state, chat, presence |
| Realtime Database storage | 1 GB ([pricing](https://firebase.google.com/pricing)) | Rooms deleted after the match, chat after 7 days |
| Firestore | 50,000 reads and 20,000 writes a day ([pricing](https://firebase.google.com/pricing)) | Profiles, stats, achievements, written only at match end |
| Firebase Hosting | 360 MB a day ([pricing](https://firebase.google.com/pricing)) | Not used for game files |
| GitHub Pages | 100 GB a month soft limit, 1 GB site ([limits](https://docs.github.com/en/pages/getting-started-with-github-pages/github-pages-limits)) | Game files, downloaded once per phone per update |

- **Rough estimate, to measure in beta:** a log entry is about 300 bytes, so one move at 8 players is about 2.4 KB of downloads plus small private updates. A 40-move round is about 100 KB, so 10 GB covers on the order of 100,000 rounds a month.
- **Connections:** players and spectators all count toward the same 100, and so does the vlog app if it uses Realtime Database.

### Who does what

| Job | Done by |
| --- | --- |
| Deal, draw and peek hidden cards; Zombie slot mapping | Host |
| Put moves in one order and check them against hidden cards | Host |
| Turn timers, auto-select, bots, pressure rules | Host |
| Public rules, animations, sounds, Jester | Every phone, on the spot |
| Count votes to end | Every phone (same result); the host writes the end |
| Relay between phones | Realtime Database |
| Who may read and write each path | Realtime Database security rules |
| Stats and achievements | Each player's own app, from the results |

The host can't go away completely: someone has to hold the shuffled deck, and whoever holds it could look. Cryptographic card-dealing schemes exist, but they are far too heavy for a friends' game.

### Realtime Database data model

| Path | Contents | Read | Write |
| --- | --- | --- | --- |
| `rooms/{id}/allowed/{uid}` | the group's members, copied when the table opens | Host | Host, at creation |
| `rooms/{id}/meta` | gameId, groupId, hostUid, status, config | Members, spectators | Host |
| `rooms/{id}/members/{uid}` | seat, name, avatar, ready | Members, spectators | That uid if allowed; host removes |
| `rooms/{id}/spectators/{uid}` | name, avatar | Members, spectators | That uid if allowed |
| `rooms/{id}/intents/{pushId}` | uid, log position, move | Host | Members, own uid, new entries only |
| `rooms/{id}/log/{n}` | move, public events, next deadline, checksum every 20 | Members, spectators | Host, append only |
| `rooms/{id}/snapshot` | public state at entry n, refreshed every 20 entries | Members, spectators | Host |
| `rooms/{id}/hands/{uid}` | own hidden cards, private events, last rejection | That uid | Host |
| `rooms/{id}/hostState` | full state, seed | Host | Host |
| `rooms/{id}/votes/{uid}` | yes or no, start time | Members | That uid |
| `rooms/{id}/results` | final or stopped scores, highlights, events for achievements | Members, spectators | Host |
| `presence/{id}/{uid}` | online, lastSeen | Members, spectators | That uid |
| `chat/{id}/{msgId}` | uid, text, ts | Members, spectators | Members and spectators, own uid |

### Move flow

1. A player taps Play. Their page checks the move locally and animates it right away.
2. Their app writes the move to `intents`.
3. The host checks it against hidden cards and the log position. It then appends `log/{n}` and writes any private cards to `hands/{uid}` in one multi-path update, and deletes the intent.
4. Every phone, spectators included, applies entry n with its own engine and plays the effects.
5. If the host rejects a move, the mover's cards snap back with the reason. Nobody else ever saw it.
6. Timers, auto-selects and bot moves come from the host the same way.

### Security rules (outline)

```
isAllowed   = root/rooms/$room/allowed/auth.uid exists
isMember    = root/rooms/$room/members/auth.uid exists
isSpectator = root/rooms/$room/spectators/auth.uid exists
isHost      = root/rooms/$room/meta/hostUid == auth.uid

rooms/$room/allowed         read: isHost                    write: isHost && !data.exists()
rooms/$room/members/$uid    read: isMember || isSpectator   write: (auth.uid == $uid && isAllowed) || isHost
rooms/$room/spectators/$uid read: isMember || isSpectator   write: auth.uid == $uid && isAllowed
rooms/$room/meta            read: isMember || isSpectator   write: isHost (or migration, below)
rooms/$room/intents/$i      read: isHost                    write: isMember && newData.uid == auth.uid && !data.exists()
rooms/$room/log/$n          read: isMember || isSpectator   write: isHost && !data.exists()
rooms/$room/snapshot        read: isMember || isSpectator   write: isHost
rooms/$room/hands/$uid      read: auth.uid == $uid          write: isHost
rooms/$room/hostState       read: isHost                    write: isHost
rooms/$room/votes/$uid      read: isMember                  write: isMember && auth.uid == $uid
chat/$room/$msg             read: isMember || isSpectator   write: (isMember || isSpectator) && newData.uid == auth.uid
                                                            && text length 1-200 && 1 message per second
```

Realtime Database rules can't read Firestore, so the host copies the group's member list into `allowed` when opening the table. Someone who joins the group mid-match can join the next table.

### Host migration

- If the host has been offline for 60 s, the next seated player's app may set `meta/hostUid` to itself. The rules allow this only when the old host's presence shows offline and `lastSeen` is more than 60 s old.
- The new host reads `hostState` and continues from the last version, so nothing is lost.
- A returning old host rejoins as a normal player.

### Trade-offs

- The host's app holds every hand. A host with debugging tools could peek; normal players can't. Fine among friends, and the host role can rotate each match.
- Each player's app writes its own stats and achievements from `results`, so a modified app could fake them. Points only, so low stakes.
- A slow host phone slows everyone. The lobby shows each player's connection and suggests the best host.
- The engine is the same code either way. Moving to a paid server later means moving it, not rewriting it.

### Firestore (light use)

- `users/{uid}/stats/{gameId}` and `users/{uid}/achievements/{id}`: the owner writes, friends read.
- `reports/{id}`: any signed-in user can write, nobody reads from the app.
- Opening a table posts an "Open table" card to the group, using the vlog app's existing group data and permissions. Tapping it joins the table.

### Reconnection and AFK

- A disconnected player's seat is held for 60 s (`seatHoldSeconds`) while their turn timer keeps running and auto-selects at zero.
- Two auto-selects in a row mark the player AFK, and the bot keeps playing until they tap "I'm back".
- A returning player or a new spectator loads the latest `snapshot`, then applies the log entries after it.

## Flutter host

Flutter owns sign-in, every Firebase connection, and all screens except the table. The game page never holds a Firebase token; it only receives state and sends moves.

### Packages

`flutter_inappwebview`, `firebase_database`, `cloud_firestore`, `app_links` (open an "Open table" link straight into that table), `lottie` (Flutter-side animations). State management: whatever the vlog app already uses, wrapped in one `GameSession` per table.

### Screens

| Screen | Contents |
| --- | --- |
| Group games tab | Inside each vlog app group: the five games, open tables, recent matches, "Practice vs bots" |
| Game detail | Short rules, variants (e.g. Big Two mode), Open a table in this group |
| Table | `GameHost` WebView. Before the start it is the waiting room: greyed play area, seats with Ready toggles, Add bot, house rules and humour level (host), Start. Then the live game, with chat and seat presence |
| Results | Scores, placements, highlights, achievements unlocked this match, Play again |
| Achievements | All achievements per game, progress bars, hints for locked ones |
| Credits | Licences and attributions for CC BY assets |

### GameHost and GameSession

- Loads the game from the locally cached copy (served with `InAppLocalhostServer`), falling back to `games.efoc.party`. Navigation to any other origin is blocked.
- One JS handler, `efoc`, accepting messages only from the allowed origin.
- **Every phone:** loads the latest `snapshot`, then listens to `log` and its own `hands/{uid}`. It forwards them as `log` and `private` messages, and writes `intents` and `votes`.
- **Spectators:** the same, without `hands`.
- **Host phone, in addition:** listens to `intents`, forwards each as `intent`, and writes the page's `output` as one multi-path update. On app restart it sends `hostState` back as `restore`.
- Connects to Realtime Database only on lobby and table screens (`goOnline` / `goOffline`) to stay under 100 connections.
- Lifecycle: `pause` when backgrounded, `resume` plus catch-up from the log on return. If the host backgrounds, a 60 s countdown shows for everyone before migration starts.
- Back gesture asks "Leave the table? A bot will take your seat."
- WebView: zoom off, text selection off, transparent background, audio allowed after the first tap.

### Updates and offline

- The games hub checks each game's `version.json` and downloads changed files into app storage once.
- "Practice vs bots" runs the whole game inside the page in host mode, alone, with no network.

## Chat, presence and achievements

All three are built once in Flutter and shared by every game, with no server code. The game pages only see a seat's online dot and the throwables.

### Chat

- A chat button opens a bottom-sheet overlay above the table. The game keeps running underneath.
- **Quick phrases and throwables** (see Humour system) are the main chat. They pop above the sender's seat for 2 s and need no moderation.
- **Text chat:** up to 200 characters, 1 message per second, enforced by the database rules.
- **Safety:** an on-device word filter masks flagged words before sending and on display. Players can mute someone or report a message to `reports/{id}`.
- **Cleanup:** chat is deleted with the room when the host closes it. On app start, the app removes rooms it hosted that are older than 7 days.
- **Unread badge** on the chat button, plus a small toast near the sender's seat.

### Presence

- Each app writes `presence/{roomId}/{uid}` with `online: true`, and `onDisconnect()` sets `online: false` and `lastSeen`.
- Seats show green (online), amber (reconnecting, under 60 s), or a bot icon (seat taken over).
- The host's app watches presence to start seat-hold timers and host migration.

### Achievements

Achievements are data: id, game, title, description, type (`event`, `counter` or `streak`) and a condition. At match end the host writes `results`, and each player's app checks the conditions against the results and its own stats, then saves unlocks to Firestore.

| Game | Achievement | Condition |
| --- | --- | --- |
| All | First Deal | Finish your first match of any game |
| All | Full House Party | Finish a match with 8 human players |
| All | Regular | Finish a match in all five games |
| All | Comeback | Win after being last at the halfway point |
| Big Two | Straight Flush Strike | Win a trick with a straight flush |
| Big Two | No Twos Needed | Win a round without playing a 2 |
| Big Two | Bomb Disposal | Beat a four of a kind |
| Big Two | Last One Standing | Finish last in Fight Till The End (yes, it's a badge) |
| Hearts | Shoot the Moon | Take every point card in one round |
| Hearts | Clean Hands | Finish a round with 0 points |
| 21 | Natural | 21 with your first two cards |
| 21 | Five Card Charlie | Five cards at 21 or under |
| 21 | Banker's Day | As banker, beat every player in one round |
| Lucky 7 | Thanks for the Gift | Take a 7 from the Discard pile that another player threw away |
| Lucky 7 | Perfect Zero | Win with a total of 0 |
| Lucky 7 | Lockdown | Have K locks on all three of an opponent's cards |
| Zombie | Survivor | Escape the Zombie 10 times |
| Zombie | Hot Potato | Have the Zombie drawn from you 3 times in one game |

- Every achievement uses only events the engine emits. A new one that needs a new event means an engine change first.
- Unlocks play a T2 on the results screen and show a toast in the vlog app.

## Non-functional requirements

The hard targets are a smooth table on a cheap Android phone, a move that lands within a second through the host, and zero running cost.

### Performance

| Metric | Target |
| --- | --- |
| Frame rate during T3 effects | 60 fps mid-range, at least 30 fps on a 2 to 3 GB RAM Android |
| Move round trip (tap Play to new state, via the host) | p95 under 1 s on 4G in Malaysia |
| Engine work per move on the host | Under 20 ms on a low-end phone |
| Game download | Under 2 MB per game including sounds |
| Table ready after opening | Under 2 s from the local copy |
| Effects at once | At most 2 Lottie animations playing |
| WebView memory | Under 150 MB on the table screen |

### Accessibility

- Every card has a spoken label ("Queen of spades, selected"). Every action is a labelled button.
- Optional four-colour deck. Suits and colour roles never rely on colour alone; each has an icon too.
- Jester lines and banners are always text, so sound-off and deaf players miss nothing.
- Reduced motion and text size follow the OS. Humour level can be Off.
- Touch targets at least 44 px; small seats use the focus sheet. The turn timer announces "10 seconds left".

### Security

- Realtime Database rules decide every read and write (see the backend section). Each player can only read their own hand.
- The host page shape-checks every intent before the engine sees it.
- The WebView only loads the local copy or `games.efoc.party`, and the bridge ignores other origins.
- The host can peek and players' apps write their own achievements. Both are accepted trade-offs for a free, friends-only game.

### Store policy and age rating

- No real money, betting language, chips or casino styling, especially in 21. Scores are points.
- User chat counts as user-generated content, so report and mute ship in v1.
- Throwables and Jester lines are reviewed for tone before release.
- Re-read both stores' rules for HTML games inside apps before submitting.

### Language

- All strings, Jester lines included, live in locale files. The Jester speaks a Manglish mix from day one. Plain English and Malay line banks can be added later without code.

### Cost

- Zero: Firebase Spark, GitHub Pages, free assets. No card is attached to the Firebase project.
- Watch the Firebase usage dashboard weekly in beta for connections and RTDB download.

## Testing and build phases

Big Two goes all the way to multiplayer with full game feel before any other game starts. The other four then reuse the engine, table, feedback system, host mode and backend.

### Testing layers

| Layer | Tool | What must pass |
| --- | --- | --- |
| Rules | Vitest | Every rule and flag has a test, including each Big Two combo comparison, the burn rule and every Lucky 7 power |
| Simulation | `sim/simulate.ts` | 10,000 bot games per game at 2, 4 and 8 players: card count conserved, a legal move always exists, every game ends |
| Determinism | Replay test | Replaying a move log with its seed reproduces the exact final state, and every phone's public state matches the host's checksum |
| No leaks | View test | For every event, no other seat's view contains a private card or private event |
| Security rules | Firebase emulator + `@firebase/rules-unit-testing` | Player A can't read B's hand or `hostState`, can't write `public`, can't forge another uid's intent |
| Host mode | Emulator, 8 simulated players | Stale and wrong-turn intents rejected, timeouts play bots, host migration resumes at the same version |
| Feel | Playwright, local bot mode | Each tier's timing within budget, one T3 at a time, reduced-motion path, input never blocked over 1.5 s |
| Layout | Playwright | Full match at five screen sizes and 2, 4 and 8 seats, no overlap, targets at least 44 px |
| App | Flutter integration test | Lobby to results on one low-end Android and one iPhone |
| Multiplayer soak | Real phones | Airplane mode mid-turn, host leaves mid-round, background and rejoin, finish the match |

### Build phases

1. **Phase 0, decisions and setup.** Settle the open items in the Overview. Monorepo (`engine`, `games-web`, Flutter app), GitHub Pages site on `games.efoc.party`, Spark project rules. Exit: every decision answered.
2. **Phase 1, Big Two engine.** Rules, both modes, burn rule, combo detection, bots, simulation. Exit: 10,000 bot games at 2 to 8 players with no failure.
3. **Phase 2, Big Two table and feel.** Layout for 2 to 8 seats, input, the tier system, Jester, sounds, first assets, tutorial, offline practice. Exit: Playwright passes, and three friends laugh at least once in a 15-minute test.
4. **Phase 3, multiplayer.** Rooms, host mode, intents, rules, timers, reconnection, host migration. Exit: 8 phones finish a Fight Till The End match with one forced host disconnect.
5. **Phase 4, social layer.** Chat, quick phrases, throwables, presence, achievements, results, report and mute. Exit: chat rate limit holds, unlocks appear correctly.
6. **Phase 5, 21 and Hearts.** New engine modules, centre areas and key moments. Exit: same gates as Big Two.
7. **Phase 6, Zombie and Lucky 7.** Zombie hand reordering and private draws; Lucky 7 power cards, focus sheet, locks, peek countdown. Exit: same gates, plus the no-leak test for every power.
8. **Phase 7, beta and release.** Closed test with your group, decide "Double it!", fix list, store submission.

### Kickoff checklist (per game)

This follows your Game Development Principles, one spec before code.

- [ ] Rules and house-rule flags confirmed with the people who play it
- [ ] Core loop, onboarding, help, and the tutorial round specified
- [ ] Every event mapped to a tier, with its key-moment reactions and Jester lines
- [ ] Achievements listed with the events they need
- [ ] Layout checked at five screen sizes and 2, 4 and 8 seats on paper
- [ ] Assets chosen in the one shared style, licences recorded
- [ ] Strings and Jester lines in the locale file
- [ ] Accessibility labels planned

### Pre-release checklist

- [ ] Simulation, determinism, no-leak and security-rule tests green
- [ ] Playwright feel and layout walkthroughs green
- [ ] Low-end Android holds 30 fps during T3 effects
- [ ] p95 move round trip under 1 s measured on 4G through a real host
- [ ] Host migration tested on real phones
- [ ] Report and mute reachable within two taps
- [ ] Credits screen lists every CC BY asset
- [ ] Firebase usage checked against Spark limits after a full beta week
- [ ] Store rules for HTML games and user content re-read
