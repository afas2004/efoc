import { describe, expect, it } from 'vitest';
import { fullDeck, type Card } from '../../core/cards';
import { createRng } from '../../core/rng';
import type { GameEvent } from '../../core/types';
import { bot } from './bot';
import { defaultConfig } from './config';
import {
  apply,
  applyPrivate,
  applyPublic,
  cardPoints,
  checksum,
  HIDDEN,
  legalMoves,
  mask,
  result,
  setup,
  validate,
  view,
  winners,
  type LuckyMove,
  type LuckyState,
} from './rules';

const rng = createRng(1);

/** A table with chosen slots; the deck and Discard as given, the rest Used. */
function table(slots: string[], deck = '5d 6d 8d', over: Partial<LuckyState> = {}): LuckyState {
  const sl = slots.map((s) => s.split(' '));
  const dk = deck ? deck.split(' ') : [];
  const used = new Set([...sl.flat(), ...dk, ...((over.discard as Card[]) ?? [])]);
  return {
    config: defaultConfig,
    players: sl.length,
    slots: sl,
    locks: sl.map(() => [null, null, null]),
    deck: dk,
    discard: [],
    discardBy: null,
    used: fullDeck().filter((c) => !used.has(c)),
    turn: 0,
    step: 'draw',
    drawn: null,
    drawnFrom: null,
    turns: 0,
    maxTurns: 1000,
    phase: 'play',
    totals: null,
    placings: null,
    ...over,
  };
}

function run(s: LuckyState, moves: [number, LuckyMove][]): { s: LuckyState; events: GameEvent[] } {
  const events: GameEvent[] = [];
  for (const [seat, m] of moves) {
    const r = apply(s, seat, m, rng);
    s = r.state;
    events.push(...r.events);
  }
  return { s, events };
}

/** Every card id mentioned anywhere in a value. */
const cardsOf = (x: unknown): Card[] => [...JSON.stringify(x).matchAll(/"([2-9TJQKA][dchs])"/g)].map((m) => m[1]!);

const cardsIn = (s: LuckyState): Card[] => [...s.slots.flat(), ...s.locks.flat().filter((k): k is Card => !!k), ...s.deck, ...s.discard, ...s.used, ...(s.drawn ? [s.drawn] : [])];

describe('Lucky 7 values', () => {
  it('7 = 0, A = 1, 2 to 10 face value, J Q K = 10', () => {
    expect(['7h', 'Ah', '2h', '9h', 'Th', 'Jh', 'Qh', 'Kh'].map(cardPoints)).toEqual([0, 1, 2, 9, 10, 10, 10, 10]);
  });
});

describe('deal', () => {
  it('3 hidden cards each, the rest is the centre deck; the host (seat 0) starts', () => {
    for (let n = 2; n <= 8; n++) {
      const s = setup(Array.from({ length: n }, (_, i) => i), defaultConfig, createRng(n));
      expect(s.slots.every((x) => x.length === 3)).toBe(true);
      expect(s.deck.length).toBe(52 - 3 * n);
      expect(new Set(cardsIn(s)).size).toBe(52);
      expect(s.turn).toBe(0);
      expect(s.maxTurns).toBe(s.deck.length * 2);
    }
  });
  it("nobody's view shows any slot, their own included", () => {
    const s = setup([0, 1, 2], defaultConfig, createRng(3));
    for (const seat of [0, 1, 2, 'public'] as const) {
      const v = view(s, seat);
      expect(JSON.stringify(v)).not.toMatch(new RegExp(s.slots.flat().join('|')));
      expect(v.revealed).toBeNull();
    }
  });
});

describe('a turn', () => {
  it('draw from the deck (only you see it), then swap: the old card goes face up to Discard', () => {
    const s0 = table(['Kd Kc Kh', '2d 3d 4d']);
    let { s, events } = run(s0, [[0, { type: 'draw', from: 'deck' }]]);
    expect(s.drawn).toBe('8d');
    expect(view(s, 0).drawn).toBe('8d');
    expect(view(s, 1).drawn).toBeNull();
    expect(events.find((e) => e.type === 'drawn_card')).toEqual({ type: 'drawn_card', to: 0, card: '8d' });
    ({ s, events } = run(s, [[0, { type: 'swap', slot: 1 }]]));
    expect(s.slots[0]).toEqual(['Kd', '8d', 'Kh']);
    expect(s.discard).toEqual(['Kc']);
    expect(events[0]).toEqual({ type: 'swapped', seat: 0, slot: 1, out: 'Kc' });
    expect(s.turn).toBe(1);
  });
  it('or throw it on Discard; the next player may take it (everyone sees it) and throw it back', () => {
    const s0 = table(['Kd Kc Kh', '2d 3d 4d']);
    let { s, events } = run(s0, [[0, { type: 'draw', from: 'deck' }], [0, { type: 'discard' }], [1, { type: 'draw', from: 'discard' }]]);
    expect(events.find((e) => e.type === 'drew' && e.from === 'discard')).toMatchObject({ card: '8d' });
    expect(view(s, 0).drawn).toBe('8d');
    ({ s } = run(s, [[1, { type: 'discard' }]]));
    expect(s.discard).toEqual(['8d']);
  });
  it('taking a 7, an A or an unused power someone threw away is a gift', () => {
    const s0 = table(['Kd Kc Kh', '2d 3d 4d'], '5d 6d 7d');
    const { events } = run(s0, [[0, { type: 'draw', from: 'deck' }], [0, { type: 'discard' }], [1, { type: 'draw', from: 'discard' }]]);
    expect(events).toContainEqual({ type: 'gift_grabbed', seat: 1, from: 0, card: '7d' });
  });
  it("must draw first; can't swap into a locked slot; can't take from an empty Discard", () => {
    const s0 = table(['Kd Kc Kh', '2d 3d 4d']);
    expect(validate(s0, 0, { type: 'swap', slot: 0 }).ok).toBe(false);
    expect(validate(s0, 0, { type: 'draw', from: 'discard' }).ok).toBe(false);
    expect(validate(s0, 1, { type: 'draw', from: 'deck' }).ok).toBe(false);
    const locked = table(['Kd Kc Kh', '2d 3d 4d'], '5d 6d 8d', { locks: [['Ks', null, null], [null, null, null]] });
    const { s } = run(locked, [[0, { type: 'draw', from: 'deck' }]]);
    expect(validate(s, 0, { type: 'swap', slot: 0 }).ok).toBe(false);
    expect(validate(s, 0, { type: 'swap', slot: 1 }).ok).toBe(true);
  });
  it('only power cards can be used', () => {
    const { s } = run(table(['Kd Kc Kh', '2d 3d 4d']), [[0, { type: 'draw', from: 'deck' }]]);
    expect(validate(s, 0, { type: 'use' }).ok).toBe(false);
  });
});

describe('powers', () => {
  const drawPower = (card: string, over: Partial<LuckyState> = {}) =>
    run(table(['Kd 2c Kh', '2d 3d 4d', '5h 6h 8h'], `5d 6d ${card}`, over), [[0, { type: 'draw', from: 'deck' }]]).s;

  it('J: see your own unlocked cards (privately), then peek at one opponent card', () => {
    const s0 = drawPower('Jc', { locks: [[null, 'Ks', null], [null, null, null], [null, null, null]] });
    let { s, events } = run(s0, [[0, { type: 'use' }]]);
    expect(s.step).toBe('peek');
    expect(events).toContainEqual({ type: 'peek_own', to: 0, cards: ['Kd', null, 'Kh'], seconds: 10 });
    expect(validate(s, 0, { type: 'peek', target: { seat: 0, slot: 0 } }).ok).toBe(false); // not your own
    ({ s, events } = run(s, [[0, { type: 'peek', target: { seat: 2, slot: 1 } }]]));
    expect(events).toContainEqual({ type: 'peek_card', to: 0, target: { seat: 2, slot: 1 }, card: '6h' });
    expect(events).toContainEqual({ type: 'peeked', seat: 0, target: { seat: 2, slot: 1 } });
    expect(s.used).toContain('Jc');
    expect(s.turn).toBe(1);
  });
  it("J: a locked card can't be peeked", () => {
    const s0 = drawPower('Jc', { locks: [[null, null, null], ['Ks', null, null], [null, null, null]] });
    const { s } = run(s0, [[0, { type: 'use' }]]);
    expect(validate(s, 0, { type: 'peek', target: { seat: 1, slot: 0 } }).ok).toBe(false);
    expect(validate(s, 0, { type: 'peek', target: null }).ok).toBe(false); // there are open cards
  });
  it('Q: swaps one of yours with one of theirs, unseen; not locked ones', () => {
    const s0 = drawPower('Qc', { locks: [[null, null, null], ['Ks', null, null], [null, null, null]] });
    expect(validate(s0, 0, { type: 'use', mine: 0, target: { seat: 1, slot: 0 } }).ok).toBe(false);
    const { s, events } = run(s0, [[0, { type: 'use', mine: 0, target: { seat: 1, slot: 1 } }]]);
    expect(s.slots[0]![0]).toBe('3d');
    expect(s.slots[1]![1]).toBe('Kd');
    expect(JSON.stringify(events)).not.toMatch(/Kd|3d/); // nobody learns the cards
    expect(s.used).toContain('Qc');
  });
  it('K: locks any card (yours or theirs); the K sits on it and adds nothing to the score', () => {
    const s0 = drawPower('Kc');
    const { s, events } = run(s0, [[0, { type: 'use', target: { seat: 2, slot: 2 } }]]);
    expect(s.locks[2]![2]).toBe('Kc');
    expect(view(s, 1).locked[2]).toEqual([false, false, true]);
    expect(events).toContainEqual({ type: 'card_locked', seat: 0, target: { seat: 2, slot: 2 } });
    expect(s.used).not.toContain('Kc');
    expect(validate(drawPower('Ks', { locks: s.locks }), 0, { type: 'use', target: { seat: 2, slot: 2 } }).ok).toBe(false);
  });
  it('9: removes one lock (the K goes to Used), or skip', () => {
    const s0 = drawPower('9c', { locks: [[null, null, null], [null, 'Ks', null], [null, null, null]] });
    expect(validate(s0, 0, { type: 'use', target: { seat: 1, slot: 0 } }).ok).toBe(false); // not locked
    const { s, events } = run(s0, [[0, { type: 'use', target: { seat: 1, slot: 1 } }]]);
    expect(s.locks[1]![1]).toBeNull();
    expect(s.used).toEqual(expect.arrayContaining(['9c', 'Ks']));
    expect(events).toContainEqual({ type: 'lock_broken', seat: 0, target: { seat: 1, slot: 1 } });
    expect(run(drawPower('9c'), [[0, { type: 'use', target: null }]]).s.turn).toBe(1);
  });
  it('10: shuffles one seat; locked cards stay put', () => {
    const s0 = drawPower('Tc', { locks: [[null, null, null], [null, null, null], [null, 'Ks', null]] });
    for (let seed = 0; seed < 20; seed++) {
      const s = apply(s0, 0, { type: 'use', seat: 2 }, createRng(seed)).state;
      expect(s.slots[2]![1]).toBe('6h');
      expect(new Set(s.slots[2])).toEqual(new Set(['5h', '6h', '8h']));
    }
  });
  it('only a power card offers Use, with one move per legal target', () => {
    const k = drawPower('Kc');
    expect(legalMoves(k, 0).filter((m) => m.type === 'use')).toHaveLength(9);
    const q = drawPower('Qc');
    expect(legalMoves(q, 0).filter((m) => m.type === 'use')).toHaveLength(3 * 6);
  });
});

describe('the end', () => {
  it('when a turn ends with the centre deck empty: reveal, lowest total wins, ties share', () => {
    const s0 = table(['7d Ad 2c', '7c Ac 2h', 'Kd Kc Kh'], '5d');
    const { s, events } = run(s0, [[0, { type: 'draw', from: 'deck' }], [0, { type: 'discard' }]]);
    expect(s.phase).toBe('over');
    expect(result(s)).toEqual({ points: [3, 3, 30], placings: [0, 1, 2] });
    expect(winners(s)).toEqual([0, 1]);
    expect(events.find((e) => e.type === 'revealed')).toBeTruthy();
    expect(view(s, 'public').revealed![2]).toEqual(['Kd', 'Kc', 'Kh']);
  });
  it('a K lock adds nothing; the locked card counts', () => {
    const s0 = table(['7d Ad 2c', '9c 9d 9h'], '5d', { locks: [['Ks', null, null], [null, null, null]] });
    const { s } = run(s0, [[0, { type: 'draw', from: 'deck' }], [0, { type: 'discard' }]]);
    expect(result(s)!.points).toEqual([3, 27]);
  });
  it('the turn cap stops a table that never draws from the centre deck', () => {
    const s0 = table(['Kd Kc Kh', '2d 3d 4d'], '5d 6d 8d', { discard: ['9s'], maxTurns: 4 });
    const moves: [number, LuckyMove][] = [];
    for (let t = 0; t < 4; t++) moves.push([t % 2, { type: 'draw', from: 'discard' }], [t % 2, { type: 'discard' }]);
    expect(run(s0, moves).s.phase).toBe('over');
  });
  it('final lap: one card per player left', () => {
    const s0 = table(['Kd Kc Kh', '2d 3d 4d'], '5d 6d 8d');
    const { events } = run(s0, [[0, { type: 'draw', from: 'deck' }], [0, { type: 'discard' }]]);
    expect(events).toContainEqual({ type: 'final_lap' });
  });
});

describe('hidden cards never leak (every power)', () => {
  /** Plays random bot games; checks every view, mask and public event. */
  it('views, masks and public events show no slot before the reveal; masked copies stay in sync', () => {
    for (let game = 0; game < 120; game++) {
      const players = 2 + (game % 7);
      const r = createRng(1000 + game);
      let host = setup(Array.from({ length: players }, (_, i) => i), defaultConfig, r);
      const phones = Array.from({ length: players }, (_, i) => mask(host, i));
      // Cards each phone has legitimately seen: its own draws, and anything taken off Discard.
      const seen = Array.from({ length: players }, () => new Set<Card>());
      let pub = mask(host, 'public');
      let guard = 0;
      while (host.phase === 'play' && guard++ < 500) {
        const seat = host.turn;
        const move = bot(view(host, seat), game % 2 ? 'normal' : 'easy', r);
        const { state, events } = apply(host, seat, move, r);
        const secret = new Set<Card>([...host.slots.flat(), ...host.deck, ...state.slots.flat(), ...state.deck]);
        // What became public on the table is fine to mention.
        for (const c of [...state.discard, ...state.used, ...state.locks.flat()]) if (c) secret.delete(c);
        if (state.drawnFrom === 'discard' && state.drawn) secret.delete(state.drawn);
        const pubEvents = events.filter((e) => e.to === undefined);
        const finished = state.phase === 'over';
        if (!finished) {
          const leaked = (x: unknown, ok?: Card | null): Card[] => cardsOf(x).filter((c) => secret.has(c) && c !== ok);
          for (const e of pubEvents) expect(leaked(e)).toEqual([]);
          for (let s = 0; s < players; s++) expect(leaked(view(state, s), s === state.turn ? state.drawn : null)).toEqual([]);
        }
        // Private events go only to their seat and only say what that seat may know.
        for (const e of events.filter((x) => x.to !== undefined)) expect(e.to).toBe(seat);
        // Every phone advances its masked copy from the public entry plus its own private events.
        for (const e of events) {
          if (e.type === 'drawn_card') seen[e.to as number]!.add(e.card as Card);
          if (e.type === 'drew' && e.from === 'discard') for (const x of seen) x.add(e.card as Card);
        }
        for (let s = 0; s < players; s++) {
          let p = applyPublic(phones[s]!, seat, move, pubEvents);
          for (const e of events.filter((x) => x.to === s)) p = applyPrivate(p, s, e);
          phones[s] = p;
          expect(checksum(p)).toBe(checksum(state));
          const known = p.slots.flat().filter((c) => c !== HIDDEN);
          if (finished) expect(known.sort()).toEqual(state.slots.flat().sort());
          else for (const c of known) expect(seen[s]!.has(c)).toBe(true);
        }
        pub = applyPublic(pub, seat, move, pubEvents);
        expect(checksum(pub)).toBe(checksum(state));
        expect(new Set(cardsIn(state)).size).toBe(52);
        expect(cardsIn(state)).toHaveLength(52);
        host = state;
      }
      expect(host.phase).toBe('over');
      expect(result(pub)).toEqual(result(host));
    }
  }, 30_000);
});

describe('bots', () => {
  it('always make legal moves and finish games, 2 to 8 players, both levels', () => {
    for (let game = 0; game < 400; game++) {
      const players = 2 + (game % 7);
      const r = createRng(game);
      let s = setup(Array.from({ length: players }, (_, i) => i), defaultConfig, r);
      let guard = 0;
      while (s.phase === 'play') {
        expect(guard++).toBeLessThan(1000);
        const move = bot(view(s, s.turn), game % 2 ? 'normal' : 'easy', r);
        expect(validate(s, s.turn, move)).toEqual({ ok: true });
        s = apply(s, s.turn, move, r).state;
      }
      expect(result(s)!.placings.slice().sort()).toEqual(Array.from({ length: players }, (_, i) => i));
    }
  }, 30_000);
  it('normal beats easy most of the time', () => {
    let normalWins = 0;
    const games = 600;
    for (let game = 0; game < games; game++) {
      const r = createRng(5000 + game);
      let s = setup([0, 1], defaultConfig, r);
      while (s.phase === 'play') s = apply(s, s.turn, bot(view(s, s.turn), s.turn === game % 2 ? 'normal' : 'easy', r), r).state;
      if (result(s)!.points[game % 2]! < result(s)!.points[1 - (game % 2)]!) normalWins++;
    }
    expect(normalWins / games).toBeGreaterThan(0.5);
  });
});
