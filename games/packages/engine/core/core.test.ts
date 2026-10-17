import { describe, expect, it } from 'vitest';
import { fullDeck, isCard } from './cards';
import { createRng } from './rng';

describe('cards', () => {
  it('has 52 unique valid cards, 53 with the Joker', () => {
    const deck = fullDeck();
    expect(new Set(deck).size).toBe(52);
    expect(deck.every(isCard)).toBe(true);
    expect(fullDeck(true)).toHaveLength(53);
  });
});

describe('rng', () => {
  it('is deterministic for a seed', () => {
    const a = createRng(42).shuffle(fullDeck());
    const b = createRng(42).shuffle(fullDeck());
    expect(a).toEqual(b);
    expect(createRng(43).shuffle(fullDeck())).not.toEqual(a);
  });
});
