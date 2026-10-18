# Table feel: rules for every game

How cards move, how players act, and how the table shows who is there.
Every game's table follows these; a game only adds its own moments.
Written 18 Oct 2026 after Lucky 7 playtest feedback from Fahmi.

## 1. Cards live on the table

- Each player's cards sit **on the felt in front of their seat**, big
  enough to follow by eye, not tucked inside a seat badge. The seat badge
  (avatar, name, status) sits just behind them.
- Card size scales with the number of players; your own cards are the
  biggest. Below about 40 px wide, tapping an opponent's cards opens a
  focus sheet with large copies (spec "Targeting small seats").
- The card a player is holding this turn sits between their cards and the
  middle of the table: face up for whoever may see it, face down for
  everyone else.

## 2. Act by tapping where the card goes

- No "Swap" or "Throw" buttons to read: holding a card, **your own slots
  and the Discard pile light up**. Tap a slot to swap into it, tap Discard
  to throw it away. Draw the same way: tap the deck or the Discard card.
- Buttons stay only for things with no place on the table (use a power,
  skip, menu).
- Whatever can be tapped right now glows and gently pulses; nothing else
  does.

## 3. Every move is shown, step by step

Players must be able to track cards (in Lucky 7 that is the game), so:

- **Animate each step, not just the end state.** A swap is two flights at
  once: the new card from the hand into the slot, and the old card from
  the slot to Discard. (Board Game Arena developers hit the same problem:
  animating only a card's final destination loses players who aren't
  moving.)
- **Real paths.** Cards fly from the exact place they left to the exact
  place they land, on a gentle arc with a little rotation, ease-out then
  settle. Never teleport; never fade in at the destination.
- **The destination waits.** A slot or pile shows its old content until
  the flying card lands; state and picture never disagree on screen.
- **Flips show information changing hands.** A card turns face up only
  when it becomes public (thrown to Discard, revealed); face down when it
  is hidden again (into a slot). Private faces (your drawn card, a peek)
  appear only on the owner's screen.
- **Hidden shuffles can't be followed.** When a power shuffles hidden
  cards (Lucky 7's 10), they gather, spin and deal back; the animation
  never shows the real new order.
- **Peeks are visible as peeks.** Everyone sees *which* card someone is
  looking at (it lifts and tilts toward them with an eye), never its face.

## 4. Pacing

- A single flight takes 380–520 ms; steps of one move follow each other
  with about 100 ms between them; parallel flights (a swap) run together.
- After a move the table pauses just long enough for its animation, then
  the next player (or bot) goes: about 0.7 s for a draw, 0.9 s for a swap
  or throw, 1.4–1.8 s for a power with several steps. The host's bot
  pause (`dwellMs`) is set from these numbers so bots never act during an
  animation, and the turn clock starts after it.
- The final reveal flips cards seat by seat (about 0.45 s each), the
  lowest total last, then results.
- Reduced motion keeps the order and the pauses but shortens flights to
  fades.

## 5. The Jester speaks about what the table shows

- A line plays **after** the move's cards have landed, never before.
- When the next move starts, the previous line goes, so the Jester never
  talks over a different move.
- Lines describe what everyone can see: a card thrown or swapped out (its
  face is on Discard), a power and its target, who peeked at which cards.
  Never a hidden face, and never a claim the animation contradicts.
- No line repeats soon after itself; small moments wait 15 s between
  lines, big ones always speak.

## 6. Who is there (online tables)

- **Online:** normal seat.
- **Reconnecting:** seat greyed, blinking amber dot, "Reconnecting…".
  Their turn clock keeps running; at zero the Easy bot picks for them.
- **Left** (tapped Leave): seat greyed, "Left"; a bot plays their turns at
  once so nobody waits.
- **Results:** everyone taps "I'm in!"; the host sees who is in, still
  deciding, or gone before Play again.
- The waiting room redraws only when something shown changes, keeping its
  scroll and buttons steady through presence heartbeats.
