// Zombie house rules. Defaults follow docs/spec.md and docs/decisions.md.

export interface ZombieConfig {
  /**
   * Safety stop: the round also ends after this many draws, the Zombie's
   * holder losing as usual. Random draws always finish long before; this
   * only guards against a table that somehow never does. 0 = 2000.
   */
  maxDraws: number;
}

export const defaultConfig: ZombieConfig = {
  maxDraws: 0,
};
