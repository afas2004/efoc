// Big Two house rules. Defaults follow docs/decisions.md.

export interface BigTwoConfig {
  /** standard: the round ends when the first player goes out. fightTillTheEnd: until one player still holds cards. */
  mode: 'standard' | 'fightTillTheEnd';
  /** A-2-3-4-5 counts as a straight (the lowest one). Off: straights only run 3…2 without wrapping. */
  allowA2345: boolean;
  /** 2-3-4-5-6 counts as a straight (just above A-2-3-4-5). */
  allow23456: boolean;
  allowTriples: boolean;
  /** On: four of a kind is a 5-card hand (4 + 1). Off: it is played as 4 cards alone. */
  fourOfAKindKicker: boolean;
  /** suitFirst: a better-suited flush always wins. highCardFirst: compare ranks first, suit breaks ties. */
  flushCompare: 'suitFirst' | 'highCardFirst';
  /** On: a pass sits you out until the trick resets. Off: a pass only skips that turn. */
  passLocksOut: boolean;
  /**
   * Poker hands: two pair (2 + 2 + 1) and three of a kind (3 + 1 + 1) also
   * count as 5-card hands, below a straight, as in poker.
   */
  pokerHands: boolean;
  /**
   * A play nothing can beat (single 2♠, a pair with 2♠, three or four 2s,
   * the top straight flush) ends the trick at once: everyone auto-passes.
   */
  autoPassUnbeatable: boolean;
  /** Rounds in a match. When over 1, the last round counts double. */
  roundsToPlay: number;
}

export const defaultConfig: BigTwoConfig = {
  mode: 'standard',
  allowA2345: false,
  allow23456: false,
  allowTriples: true,
  fourOfAKindKicker: true,
  flushCompare: 'suitFirst',
  pokerHands: true,
  autoPassUnbeatable: true,
  passLocksOut: false,
  roundsToPlay: 1,
};
