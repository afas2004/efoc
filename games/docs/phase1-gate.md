# Phase 1 exit gate — Big Two engine

Run on 17 Oct 2026 with `npm run sim` (seed 1): 10,000 bot games per row,
with a random mix of Easy and Normal bots per seat. **Result: PASS, 0
failures in 140,000 games.**

| Mode | 2 | 3 | 4 | 5 | 6 | 7 | 8 players |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Standard | 0 | 0 | 0 | 0 | 0 | 0 | 0 failures |
| Fight Till The End | 0 | 0 | 0 | 0 | 0 | 0 | 0 failures |

There were 10.1 million moves in total. Separately, `npm run sim -- --games
2000 --variants --seed 5` ran 14,000 games with every house-rule flag
randomised and 1–3 rounds per match: 0 failures.

Checked after every move: the player to move has a legal move and nobody
else does, every bot move passes `validate()`, all 52 cards are in exactly
one place, and no view (public or any seat's) contains a card from another
player's hand. Checked per game: it ends within 2,000 moves per round, the
result is sane (one placing per seat, winner on 0, no negative points), and
replaying the move log from the seed reproduces the exact final state.

Sanity check: three bugs were planted on purpose (a hand leaked to the
public view, a played card left in the hand, a trick that never resets).
The simulator caught each one within 3 games.

## Rerun with poker hands on (17 Oct)

After poker hands became the default, `npm run sim` ran again: 140,000 games
at 2–8 players in both modes, **0 failures**. The random-flags sweep (now
including `pokerHands`) ran 14,000 games, **0 failures**.
