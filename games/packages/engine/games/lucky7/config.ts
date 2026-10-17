// Lucky 7 house rules. Defaults follow docs/spec.md and docs/decisions.md.

export interface LuckySevenConfig {
  /** Seconds a J's peeked card stays face up for you (spec `peekSeconds`). */
  peekSeconds: number;
  /**
   * Safety stop: the round also ends after this many turns. A card taken
   * from Discard may go straight back onto it, so a table that never draws
   * from the centre deck would otherwise never finish. 0 = twice the
   * centre deck at the deal.
   */
  maxTurns: number;
}

export const defaultConfig: LuckySevenConfig = {
  peekSeconds: 5,
  maxTurns: 0,
};
