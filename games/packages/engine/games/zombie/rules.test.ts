import { describe, expect, it } from 'vitest';
import { createRng } from '../../core/rng';
import { simulateZombie } from '../../sim/zombie';
import { bot } from './bot';
import { defaultConfig } from './config';
import { apply, applyPrivate, applyPublic, checksum, HIDDEN, legalMoves, mask, pairsIn, result, setup, validate, view, ZOMBIE, type ZombieState } from './rules';

const rng = createRng(1);

/** A table mid-game with chosen hands: seat 0 to draw from seat 1. */
function table(hands: string[], over: Partial<ZombieState> = {}): ZombieState {
  const h = hands.map((x) => (x ? x.split(' ') : []));
  return {
    config: defaultConfig,
    players: h.length,
    hands: h,
    pile: [],
    pairs: h.map(() => 0),
    step: 'draw',
    turn: 0,
    aim: null,
    safe: h.map((x, i) => (x.length ? -1 : i)).filter((i) => i >= 0),
    draws: 0,
    maxDraws: 2000,
    phase: 'play',
    loser: null,
    stats: { moves: 0, drawnFrom: h.map(() => 0), held: h.map(() => 0), dealtTo: 0 },
    ...over,
  };
}

describe('deal', () => {
  it('all 53 cards, uneven hands; everyone throws their pairs at once before the first draw', () => {
    const s = setup([0, 1, 2, 3], defaultConfig, createRng(3));
    expect(s.hands.flat()).toHaveLength(53);
    expect(s.step).toBe('deal');
    const waiting = [0, 1, 2, 3].filter((i) => legalMoves(s, i).length > 0);
    expect(waiting.length).toBeGreaterThan(1);
    for (const i of waiting) expect(pairsIn(s.hands[i]!).length).toBeGreaterThan(0);
  });

  it('pairs are by rank (any suits); three of a kind is one pair; the Zombie never pairs, not even with a J', () => {
    expect(pairsIn(['5d', '5s', '5h', 'JK', 'Jc', '9d'])).toEqual([['5d', '5s']]);
  });

  it('throw one pair by rank, or all at once; when nobody holds a pair the host draws first, from a freshly shuffled hand', () => {
    let s = table(['5d 5s 9c 9d 3h', '4c 6c 7c', 'JK 8d 8s'], { step: 'deal' });
    let r = apply(s, 0, { type: 'throw', rank: '9' }, rng);
    expect(r.state.hands[0]).toEqual(['5d', '5s', '3h']);
    expect(r.events).toEqual([{ type: 'pair', seat: 0, cards: ['9c', '9d'] }]);
    s = apply(r.state, 2, { type: 'throw' }, rng).state;
    expect(s.step).toBe('deal');
    r = apply(s, 0, { type: 'throw' }, rng);
    expect(r.state.step).toBe('draw');
    expect(r.state.turn).toBe(0);
    expect(r.events.map((e) => e.type)).toEqual(['pair', 'turn', 'shuffled', 'hand']);
    expect(r.events.find((e) => e.type === 'hand')).toMatchObject({ to: 1 });
    expect(validate(s, 1, { type: 'throw' }).ok).toBe(false); // no pairs
  });
});

describe('a turn', () => {
  it('point at a card (everyone sees which), then draw it: it goes to the end of my hand', () => {
    const s = table(['3d 4d', '5s 6s 7s', '8h 9h']);
    const aimed = apply(s, 0, { type: 'aim', slot: 2 }, rng);
    expect(aimed.state.aim).toBe(2);
    expect(aimed.events).toEqual([{ type: 'aim', seat: 0, from: 1, slot: 2 }]);
    expect(aimed.state.turn).toBe(0);
    const { state, events } = apply(aimed.state, 0, { type: 'draw', slot: 1 }, rng);
    expect(state.hands[0]).toEqual(['3d', '4d', '6s']);
    expect(events.find((e) => e.type === 'drew')).toEqual({ type: 'drew', seat: 0, from: 1, slot: 1, pair: false });
    expect(events.find((e) => e.type === 'drawn_card')).toMatchObject({ to: 0, card: '6s' });
    // Seat 1 draws next, from seat 2's hand, shuffled for it.
    expect(state.turn).toBe(1);
    expect(state.aim).toBeNull();
    expect(events.find((e) => e.type === 'shuffled')).toEqual({ type: 'shuffled', seat: 2, auto: true });
  });

  it('a draw that makes a pair waits for me to throw it; then the next player draws', () => {
    const s = table(['3d 4d', '4s 6s', '8h']);
    const r = apply(s, 0, { type: 'draw', slot: 0 }, rng);
    expect(r.state.step).toBe('throw');
    expect(r.state.turn).toBe(0);
    expect(r.events.find((e) => e.type === 'drew')).toMatchObject({ pair: true });
    expect(legalMoves(r.state, 0)).toEqual([{ type: 'throw' }]);
    expect(validate(r.state, 0, { type: 'draw', slot: 0 }).ok).toBe(false);
    const t = apply(r.state, 0, { type: 'throw' }, rng);
    expect(t.state.hands[0]).toEqual(['3d']);
    expect(t.state.pile).toEqual(['4d', '4s']);
    expect(t.state.turn).toBe(1);
  });

  it('empty hands are safe and skipped; the last one holding the Zombie loses', () => {
    let s = table(['3d', '3s JK', '9c']);
    s = apply(s, 0, { type: 'draw', slot: 0 }, rng).state;
    s = apply(s, 0, { type: 'throw' }, rng).state; // seat 0 pairs out: safe
    expect(s.safe).toEqual([0]);
    expect(s.turn).toBe(1);
    const r = apply(s, 1, { type: 'draw', slot: 0 }, rng); // seat 1 takes seat 2's last card
    expect(r.state.phase).toBe('over');
    expect(r.state.loser).toBe(1);
    expect(result(r.state)).toEqual({ points: [0, 1, 0], placings: [0, 2, 1] });
    expect(r.events.find((e) => e.type === 'zombie_loser')).toEqual({ type: 'zombie_loser', seat: 1, hand: ['JK', '9c'] });
  });

  it('only the player to move aims or draws, only a slot that exists', () => {
    const s = table(['3d', '5s 6s', '8h']);
    expect(validate(s, 1, { type: 'draw', slot: 0 })).toEqual({ ok: false, reason: 'Not your turn' });
    expect(validate(s, 0, { type: 'aim', slot: 2 }).ok).toBe(false);
    expect(validate(s, 0, { type: 'draw', slot: 1 }).ok).toBe(true);
  });
});

describe('hidden cards', () => {
  it('a masked copy keeps its own hand and only placeholders for others; the Zombie story stays secret', () => {
    const s = setup([0, 1, 2, 3], defaultConfig, createRng(5));
    const m = mask(s, 2);
    expect(m.hands[2]).toEqual(s.hands[2]);
    for (const i of [0, 1, 3]) expect(m.hands[i]!.every((c) => c === HIDDEN)).toBe(true);
    expect(m.stats).toBeNull();
    expect(view(s, 1).stats).toBeNull();
    expect(checksum(m)).toBe(checksum(s));
  });

  it("a phone follows the log: the drawer learns its card privately, the giver's copy just loses it, the next target gets its new order", () => {
    const s = table(['3d 4d', '5s JK', '8h 9h']);
    const { state, events } = apply(s, 0, { type: 'draw', slot: 1 }, rng);
    const pub = events.filter((e) => e.to === undefined);
    let me = applyPublic(mask(s, 0), 0, { type: 'draw', slot: 1 }, pub);
    expect(me.hands[0]).toEqual(['3d', '4d', HIDDEN]);
    for (const e of events.filter((x) => x.to === 0)) me = applyPrivate(me, 0, e);
    expect(me.hands[0]).toEqual(['3d', '4d', 'JK']);
    const giver = applyPublic(mask(s, 1), 0, { type: 'draw', slot: 1 }, pub);
    expect(giver.hands[1]).toEqual(['5s']);
    let next = applyPublic(mask(s, 2), 0, { type: 'draw', slot: 1 }, pub);
    for (const e of events.filter((x) => x.to === 2)) next = applyPrivate(next, 2, e);
    expect(next.hands[2]).toEqual(state.hands[2]);
    for (const c of [me, giver, next]) expect(checksum(c)).toBe(checksum(state));
  });
});

describe('bots', () => {
  it('throw their pairs, draw a real slot (the aimed one if any) and finish, 2 to 8 players', () => {
    for (let game = 0; game < 200; game++) {
      const players = 2 + (game % 7);
      const r = createRng(game);
      let s = setup(Array.from({ length: players }, (_, i) => i), defaultConfig, r);
      let guard = 0;
      while (s.phase === 'play') {
        expect(guard++).toBeLessThan(3000);
        const seat = Array.from({ length: players }, (_, i) => i).find((i) => legalMoves(s, i).length > 0)!;
        const move = bot(view(s, seat), 'normal', r);
        expect(validate(s, seat, move)).toEqual({ ok: true });
        s = apply(s, seat, move, r).state;
      }
      expect(result(s)!.placings.slice().sort()).toEqual(Array.from({ length: players }, (_, i) => i));
      expect(s.hands[s.loser!]).toEqual([ZOMBIE]);
    }
    const aimed = apply(table(['3d', '5s 6s 7s', '8h']), 0, { type: 'aim', slot: 2 }, rng).state;
    expect(bot(view(aimed, 0), 'easy', rng)).toEqual({ type: 'draw', slot: 2 });
  });
});

// A slice of the full gate (npm run sim:zombie) so every test run covers it.
describe('Zombie simulation', () => {
  it.each([2, 3, 4, 5, 6, 7, 8])('%i players: no failures, no leaks, copies stay in sync', (players) => {
    const r = simulateZombie({ games: 80, players, seed: 42 });
    expect(r.failures).toEqual([]);
  });
});
