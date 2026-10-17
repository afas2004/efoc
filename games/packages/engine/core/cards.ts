// Card model. A card is a 2-character id: rank `3456789TJQKA2` + suit `dchs`,
// e.g. `3d`, `As`, `Th`. The Joker is `JK`. Rank and suit order are per game,
// passed in as lookup tables, never hard-coded in comparisons.

export type Card = string;

export const RANKS = ['3', '4', '5', '6', '7', '8', '9', 'T', 'J', 'Q', 'K', 'A', '2'] as const;
export const SUITS = ['d', 'c', 'h', 's'] as const;
export const JOKER: Card = 'JK';

export type Rank = (typeof RANKS)[number];
export type Suit = (typeof SUITS)[number];

/** Lookup table from rank or suit to its strength in a game. */
export type Order<K extends string> = Readonly<Record<K, number>>;

export function rankOf(card: Card): Rank {
  return card[0] as Rank;
}

export function suitOf(card: Card): Suit {
  return card[1] as Suit;
}

/** The 52-card deck in a fixed order, plus the Joker when asked. */
export function fullDeck(withJoker = false): Card[] {
  const deck: Card[] = [];
  for (const r of RANKS) for (const s of SUITS) deck.push(r + s);
  if (withJoker) deck.push(JOKER);
  return deck;
}

export function isCard(value: unknown): value is Card {
  return (
    typeof value === 'string' &&
    (value === JOKER ||
      (value.length === 2 &&
        (RANKS as readonly string[]).includes(value[0]!) &&
        (SUITS as readonly string[]).includes(value[1]!)))
  );
}
