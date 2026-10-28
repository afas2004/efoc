import { describe, expect, it } from 'vitest';
import { createRng } from '../../core/rng';
import { simulateZombie } from '../../sim/zombie';
import { bot } from './bot';
import { defaultConfig } from './config';
import { apply, applyPrivate, applyPublic, checksum, HIDDEN, legalMoves, mask, result, setup, throwPairs, validate, view, ZOMBIE, type ZombieState } from './rules';

const rng = createRng(1);

/** A table with chosen hands; everything else already thrown on the pile. */
function table(hands: string[], over: Partial<ZombieState> = {}): ZombieState {
  const h = hands.map((x) => (x ? x.split(' ') : []));
  return {
    config: defaultConfig,
    players: h.length,
    hands: h,
    dealPairs: h.map(() => []),
    pile: [],
    pairs: h.map(() => 0),
    turn: 0,
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
  it('all 53 cards, uneven hands, every pair thrown face up; the host draws first', () => {
    const s = setup([0, 1, 2, 3, 4, 5, 6, 7], defaultConfig, createRng(3));
    expect(s.hands.flat().length + s.pile.length).toBe(53);
    for (const h of s.hands) expect(throwPairs(h).pairs).toEqual([]);
    expect(s.hands.flat().filter((c) => c === ZOMBIE)).toHaveLength(1);
    expect(s.pile).toEqual(s.dealPairs.flat());
    expect(s.turn).toBe(0);
  });

  it('pairs are by rank (any suits); three of a kind throws one pair; the Zombie never pairs, not even with a J', () => {
    expect(throwPairs(['5d', '5s', '5h', 'JK', 'Jc', '9d'])).toEqual({ left: ['5h', 'JK', 'Jc', '9d'], pairs: ['5d', '5s'] });
  });
});

describe('a turn', () => {
  it('draw a face-down card from the next player: it goes to the end of my hand; others see only that a card moved', () => {
    const s = table(['3d 4d', '5s 6s 7s', '8h 9h']);
    const { state, events } = apply(s, 0, { type: 'draw', slot: 1 }, rng);
    expect(state.hands[0]).toEqual(['3d', '4d', '6s']);
    expect(state.hands[1]).toEqual(['5s', '7s']);
    expect(events.find((e) => e.type === 'drew')).toEqual({ type: 'drew', seat: 0, from: 1, slot: 1 });
    expect(events.find((e) => e.type === 'drawn_card')).toMatchObject({ to: 0, card: '6s' });
    expect(state.turn).toBe(1);
    expect(legalMoves(state, 1)).toHaveLength(2); // seat 2's two cards
  });

  it('a new pair is thrown at once', () => {
    const s = table(['3d 4d', '4s 6s', '8h']);
    const { state, events } = apply(s, 0, { type: 'draw', slot: 0 }, rng);
    expect(state.hands[0]).toEqual(['3d']);
    expect(state.pile).toEqual(['4d', '4s']);
    expect(events).toContainEqual({ type: 'pair', seat: 0, cards: ['4d', '4s'] });
  });

  it('empty hands are safe and skipped; the last one holding the Zombie loses', () => {
    let s = table(['3d', '3s JK', '9c']);
    let r = apply(s, 0, { type: 'draw', slot: 0 }, rng); // pairs out: seat 0 safe
    s = r.state;
    expect(s.safe).toEqual([0]);
    expect(r.events).toContainEqual({ type: 'safe', seat: 0, place: 1 });
    expect(s.turn).toBe(1);
    r = apply(s, 1, { type: 'draw', slot: 0 }, rng); // seat 1 takes seat 2's last card
    s = r.state;
    expect(s.safe).toEqual([0, 2]);
    expect(s.phase).toBe('over');
    expect(s.loser).toBe(1);
    expect(result(s)).toEqual({ points: [0, 1, 0], placings: [0, 2, 1] });
    expect(r.events.find((e) => e.type === 'zombie_loser')).toEqual({ type: 'zombie_loser', seat: 1, hand: ['JK', '9c'] });
  });

  it('only the player to move draws, and only a slot that exists', () => {
    const s = table(['3d', '5s 6s', '8h']);
    expect(validate(s, 1, { type: 'draw', slot: 0 })).toEqual({ ok: false, reason: 'Not your turn' });
    expect(validate(s, 0, { type: 'draw', slot: 2 }).ok).toBe(false);
    expect(validate(s, 0, { type: 'draw', slot: 1 }).ok).toBe(true);
  });
});

describe('hiding the Zombie', () => {
  it('anyone may reorder their own hand any time; everyone sees that, only they see the order', () => {
    const s = table(['3d', '5s JK 6s', '8h']);
    expect(validate(s, 1, { type: 'order', cards: ['JK', '6s', '5s'] }).ok).toBe(true);
    expect(validate(s, 1, { type: 'order', cards: ['JK', '6s', '7s'] })).toEqual({ ok: false, reason: 'Your hand changed' });
    const { state, events } = apply(s, 1, { type: 'order', cards: ['JK', '6s', '5s'] }, rng);
    expect(state.hands[1]).toEqual(['JK', '6s', '5s']);
    expect(state.turn).toBe(0);
    expect(events).toEqual([{ type: 'shuffled', seat: 1 }, { type: 'hand', to: 1, cards: ['JK', '6s', '5s'] }]);
    // Seat 0 now takes slot 0: the Zombie.
    const r = apply(state, 0, { type: 'draw', slot: 0 }, rng);
    expect(r.state.hands[0]).toEqual(['3d', 'JK']);
    expect(r.events.find((e) => e.type === 'drawn_card')).toMatchObject({ to: 0, card: 'JK' });
  });

  it('draw with shuffle mixes my hand after; my new order comes privately', () => {
    const s = table(['3d 4d 9d', '5s JK', '8h']);
    const { state, events } = apply(s, 0, { type: 'draw', slot: 1, shuffle: true }, createRng(9));
    expect(state.hands[0]!.slice().sort()).toEqual(['3d', '4d', '9d', 'JK'].sort());
    expect(events).toContainEqual({ type: 'shuffled', seat: 0 });
    expect(events.find((e) => e.type === 'hand')).toEqual({ type: 'hand', to: 0, cards: state.hands[0] });
  });

  it('a masked copy keeps its own hand and only placeholders for others; the Zombie story stays secret until the end', () => {
    const s = setup([0, 1, 2, 3], defaultConfig, createRng(5));
    const m = mask(s, 2);
    expect(m.hands[2]).toEqual(s.hands[2]);
    for (const i of [0, 1, 3]) expect(m.hands[i]!.every((c) => c === HIDDEN)).toBe(true);
    expect(m.stats).toBeNull();
    expect(view(s, 1).stats).toBeNull();
    expect(checksum(m)).toBe(checksum(s));
  });

  it("a phone follows the log: the drawer learns its card privately, the giver's copy just loses it", () => {
    const s = table(['3d 4d', '4s JK', '8h']);
    const { state, events } = apply(s, 0, { type: 'draw', slot: 1 }, rng);
    const pub = events.filter((e) => e.to === undefined);
    let me = applyPublic(mask(s, 0), 0, { type: 'draw', slot: 1 }, pub);
    expect(me.hands[0]).toEqual(['3d', '4d', HIDDEN]);
    for (const e of events.filter((x) => x.to === 0)) me = applyPrivate(me, 0, e);
    expect(me.hands[0]).toEqual(['3d', '4d', 'JK']);
    const giver = applyPublic(mask(s, 1), 0, { type: 'draw', slot: 1 }, pub);
    expect(giver.hands[1]).toEqual(['4s']);
    expect(giver.hands[0]).toEqual([HIDDEN, HIDDEN, HIDDEN]);
    expect(checksum(me)).toBe(checksum(state));
    expect(checksum(giver)).toBe(checksum(state));
  });
});

describe('bots', () => {
  it('always draw a real slot and finish, 2 to 8 players, both levels', () => {
    for (let game = 0; game < 200; game++) {
      const players = 2 + (game % 7);
      const r = createRng(game);
      let s = setup(Array.from({ length: players }, (_, i) => i), defaultConfig, r);
      let guard = 0;
      while (s.phase === 'play') {
        expect(guard++).toBeLessThan(2000);
        const move = bot(view(s, s.turn), game % 2 ? 'normal' : 'easy', r);
        expect(validate(s, s.turn, move)).toEqual({ ok: true });
        s = apply(s, s.turn, move, r).state;
      }
      expect(result(s)!.placings.slice().sort()).toEqual(Array.from({ length: players }, (_, i) => i));
      expect(s.hands[s.loser!]).toEqual([ZOMBIE]);
    }
  });
});

// A slice of the full gate (npm run sim:zombie) so every test run covers it.
describe('Zombie simulation', () => {
  it.each([2, 3, 4, 5, 6, 7, 8])('%i players: no failures, no leaks, copies stay in sync', (players) => {
    const r = simulateZombie({ games: 80, players, seed: 42 });
    expect(r.failures).toEqual([]);
  });
});
