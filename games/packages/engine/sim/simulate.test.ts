import { describe, expect, it } from 'vitest';
import { defaultConfig } from '../games/bigtwo/config';
import { simulate } from './simulate';

// A small slice of the full gate (npm run sim) so every test run covers it.
describe('Big Two simulation', () => {
  it.each([2, 3, 4, 5, 6, 7, 8])('%i players: default rules, both modes', (players) => {
    for (const mode of ['standard', 'fightTillTheEnd'] as const) {
      const r = simulate({ games: 40, players, config: { ...defaultConfig, mode }, seed: 99 });
      expect(r.failures).toEqual([]);
    }
  });

  it.each([2, 4, 8])('%i players: random house rules', (players) => {
    const r = simulate({ games: 60, players, config: defaultConfig, seed: 7, variants: true });
    expect(r.failures).toEqual([]);
  });
});
