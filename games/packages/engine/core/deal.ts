// Shared deal rule for games that deal the whole deck evenly (Big Two,
// Hearts): each player gets 52 ÷ players cards, rounded down, capped at
// `cap`. The rest are removed face down and never shown. Because the deck is
// shuffled first, the leftover cards are a random burn.

import { fullDeck, type Card } from './cards';
import type { Rng } from './rng';

export interface EvenDeal {
  hands: Card[][];
  /** Burned cards plus any past the cap. Never revealed. */
  out: Card[];
}

export function dealEven(players: number, rng: Rng, cap = Infinity): EvenDeal {
  const deck = rng.shuffle(fullDeck());
  const each = Math.min(Math.floor(deck.length / players), cap);
  const hands: Card[][] = [];
  for (let i = 0; i < players; i++) hands.push(deck.slice(i * each, (i + 1) * each));
  return { hands, out: deck.slice(players * each) };
}
