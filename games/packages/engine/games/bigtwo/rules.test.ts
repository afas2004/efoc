import { describe, expect, it } from 'vitest';
import { fullDeck, type Card } from '../../core/cards';
import { createRng } from '../../core/rng';
import { bot } from './bot';
import { defaultConfig, type BigTwoConfig } from './config';
import {
  allCombos,
  apply,
  applyTrusted,
  checksum,
  mask,
  beats,
  classify,
  legalMoves,
  nextRound,
  result,
  setup,
  validate,
  view,
  type BigTwoMove,
  type BigTwoState,
  type Combo,
} from './rules';

const cfg = (over: Partial<BigTwoConfig> = {}): BigTwoConfig => ({ ...defaultConfig, ...over });
const c = (s: string): Card[] => s.split(' ');
const combo = (s: string, over: Partial<BigTwoConfig> = {}): Combo => {
  const k = classify(c(s), cfg(over));
  if (!k) throw new Error(`not a combo: ${s}`);
  return k;
};
const kind = (s: string, over: Partial<BigTwoConfig> = {}) => classify(c(s), cfg(over))?.kind ?? null;
const play = (s: string): BigTwoMove => ({ type: 'play', cards: c(s) });
const PASS: BigTwoMove = { type: 'pass' };

/** A mid-round state with chosen hands; the rest of the deck is "out". */
function state(hands: string[], over: Partial<BigTwoState> = {}, config = cfg()): BigTwoState {
  const hs = hands.map((h) => (h ? c(h) : []));
  const used = new Set(hs.flat());
  const n = hs.length;
  return {
    config,
    players: n,
    hands: hs,
    out: fullDeck().filter((x) => !used.has(x)),
    onTwo: [],
    pile: [],
    turn: 0,
    lead: null,
    lastPlayer: null,
    passed: new Array<boolean>(n).fill(false),
    mustInclude: null,
    finished: [],
    phase: 'play',
    round: 1,
    scores: new Array<number>(n).fill(0),
    roundPoints: null,
    placings: null,
    ...over,
  };
}

const run = (s: BigTwoState, moves: [number, BigTwoMove][]) => {
  const events = [];
  for (const [seat, m] of moves) {
    const r = apply(s, seat, m);
    s = r.state;
    events.push(...r.events);
  }
  return { s, events };
};

describe('combo detection', () => {
  it('recognises every kind', () => {
    expect(kind('7h')).toBe('single');
    expect(kind('7h 7s')).toBe('pair');
    expect(kind('7h 7s 7d')).toBe('triple');
    expect(kind('3d 4c 5h 6s 7d')).toBe('straight');
    expect(kind('3h 8h Th Qh 2h')).toBe('flush');
    expect(kind('9d 9c 9h 4s 4d')).toBe('fullhouse');
    expect(kind('9d 9c 9h 9s 4d')).toBe('fourkind');
    expect(kind('5s 6s 7s 8s 9s')).toBe('straightflush');
  });

  it('rejects non-combos', () => {
    expect(kind('7h 8h')).toBeNull();
    expect(kind('7h 7s 8d')).toBeNull();
    expect(kind('7h 7s 7d 7c')).toBeNull(); // four alone needs fourOfAKindKicker off
    expect(kind('3d 4c 5h 6s 8d')).toBeNull();
    expect(kind('9d 9c 4h 4s 5d', { pokerHands: false })).toBeNull();
    expect(kind('9d 9c 9h 4s 5d', { pokerHands: false })).toBeNull();
    expect(kind('9d 9c 4h 4s 4d 5d')).toBeNull();
    expect(kind('3d 3c 4h 4s 5d 5c')).toBeNull();
  });

  it('runs straights 3 to 2 with no wrap', () => {
    expect(kind('Jd Qc Kh As 2d')).toBe('straight');
    expect(kind('Td Jc Qh Ks Ad')).toBe('straight');
    expect(kind('Qd Kc Ah 2s 3d')).toBeNull();
    expect(kind('Kd Ac 2h 3s 4d')).toBeNull();
    expect(kind('Ad 2c 3h 4s 5d')).toBeNull();
    expect(kind('2d 3c 4h 5s 6d')).toBeNull();
  });

  it('allows A2345 and 23456 behind flags, as the lowest straights', () => {
    const flags = { allowA2345: true, allow23456: true };
    expect(kind('Ad 2c 3h 4s 5d', flags)).toBe('straight');
    expect(kind('2d 3c 4h 5s 6d', flags)).toBe('straight');
    const a2345 = combo('Ad 2c 3h 4s 5s', flags);
    const s23456 = combo('2d 3c 4h 5s 6d', flags);
    const s34567 = combo('3d 4c 5h 6s 7d', flags);
    expect(beats(s23456, a2345)).toBe(true);
    expect(beats(s34567, s23456)).toBe(true);
  });

  it('respects allowTriples and fourOfAKindKicker', () => {
    expect(kind('7h 7s 7d', { allowTriples: false })).toBeNull();
    expect(kind('7h 7s 7d 7c', { fourOfAKindKicker: false })).toBe('quad');
    expect(kind('9d 9c 9h 9s 4d', { fourOfAKindKicker: false })).toBeNull();
  });
});

describe('opening play', () => {
  it("3♦ can't be the throw card in two pair, three or four of a kind", () => {
    const s0 = state(['3d 5c 5h 8s 8d 9c 9h 9s 4c 4d 4h 4s', '6d', '7d'], { mustInclude: '3d' });
    expect(validate(s0, 0, play('5c 5h 8s 8d 3d')).ok).toBe(false); // two pair + 3♦ kicker
    expect(validate(s0, 0, play('9c 9h 9s 3d 5c')).ok).toBe(false); // trips + 3♦ kicker
    expect(validate(s0, 0, play('4c 4d 4h 4s 3d')).ok).toBe(false); // quads + 3♦ kicker
    expect(validate(s0, 0, play('3d')).ok).toBe(true);
    const plays = legalMoves(s0, 0).filter((m) => m.type === 'play') as { cards: string[] }[];
    for (const p of plays) {
      const k = classify(p.cards, cfg())!;
      expect(['twopair', 'trips', 'fourkind'].includes(k.kind) && p.cards.includes('3d')).toBe(false);
    }
  });
});

describe('unbeatable plays', () => {
  it('a single 2♠ makes everyone pass at once and gives the lead back', () => {
    const s0 = state(['2s 4d', '5d 6d', '7d 8d'], { turn: 0 });
    const { s, events } = run(s0, [[0, play('2s')]]);
    expect(events.map((e) => e.type)).toEqual(['card_played', 'unbeatable', 'all_passed']);
    expect(s.turn).toBe(0);
    expect(s.lead).toBeNull();
  });
  it('also for a pair with 2♠, and the top straight flush; not for a lone 2♥', () => {
    const t = (hand: string, p: string) => run(state([hand, '5d', '6d'], { turn: 0 }), [[0, play(p)]]).events.some((e) => e.type === 'unbeatable');
    expect(t('2s 2h 4d', '2s 2h')).toBe(true);
    expect(t('Js Qs Ks As 2s 4d', 'Js Qs Ks As 2s')).toBe(true);
    expect(t('2h 4d', '2h')).toBe(false);
  });
  it('can be switched off', () => {
    const s0 = state(['2s 4d', '5d 6d', '7d 8d'], { turn: 0 }, cfg({ autoPassUnbeatable: false }));
    const { s } = run(s0, [[0, play('2s')]]);
    expect(s.turn).toBe(1);
  });
  it('finishing with it in Fight Till The End passes the lead on', () => {
    const s0 = state(['2s', '5d 6d', '7d 8d'], { turn: 0 }, cfg({ mode: 'fightTillTheEnd' }));
    const { s } = run(s0, [[0, play('2s')]]);
    expect(s.turn).toBe(1);
    expect(s.lead).toBeNull();
  });
});

describe('poker hands', () => {
  const b = (a: string, x: string) => beats(combo(a), combo(x));
  it('are on by default: two pair and three of a kind as 5-card hands', () => {
    expect(kind('9d 9c 4h 4s 5d')).toBe('twopair');
    expect(kind('9d 9c 9h 4s 5d')).toBe('trips');
    expect(kind('9d 9c 9h 4s 4d')).toBe('fullhouse');
    expect(kind('9d 9c 4h 4s')).toBeNull(); // two pair needs its kicker
  });
  it('rank two pair < trips < straight', () => {
    expect(b('3d 3c 3h 4s 5d', 'Ad Ac 2h 2s 5d')).toBe(true);
    expect(b('3d 4c 5h 6s 7d', '2d 2c 2h 4s 5d')).toBe(true);
    expect(b('Ad Ac 2h 2s 5d', '3d 4c 5h 6s 7d')).toBe(false);
  });
  it('two pair: higher pair, then lower pair, then the best suit in the higher pair', () => {
    expect(b('9d 9c 4h 4s 5d', '8d 8c 7h 7s Ad')).toBe(true);
    expect(b('9d 9c 5h 5s 3d', '9h 9s 4d 4c Ad')).toBe(true);
    expect(b('9h 9s 4d 4c 3d', '9d 9c 4h 4s Ad')).toBe(true);
  });
  it('trips by the triple rank', () => {
    expect(b('Td Tc Th 3s 4d', '9d 9c 9h As 2d')).toBe(true);
  });
  it('enumeration agrees with brute force with poker hands off', () => {
    for (let seed = 0; seed < 10; seed++) {
      const hand = createRng(seed).shuffle(fullDeck()).slice(0, 13);
      const off = cfg({ pokerHands: false });
      const fast = new Set(allCombos(hand, off).map((p) => p.cards.join(' ')));
      let brute = 0;
      for (let mask = 1; mask < 1 << 13; mask++) {
        const pick = hand.filter((_, i) => mask & (1 << i));
        if (pick.length <= 5 && classify(pick, off)) brute++;
      }
      expect(fast.size).toBe(brute);
    }
  });
});

describe('combo comparison', () => {
  const b = (a: string, x: string, over: Partial<BigTwoConfig> = {}) => beats(combo(a, over), combo(x, over));

  it('singles: rank first, 2 high, then suit ♦ < ♣ < ♥ < ♠', () => {
    expect(b('2d', 'As')).toBe(true);
    expect(b('4d', '3s')).toBe(true);
    expect(b('3c', '3d')).toBe(true);
    expect(b('3h', '3c')).toBe(true);
    expect(b('3s', '3h')).toBe(true);
    expect(b('3d', '3s')).toBe(false);
    expect(b('3d', '3d')).toBe(false);
  });

  it('pairs: rank, then highest suit', () => {
    expect(b('8d 8c', '7h 7s')).toBe(true);
    expect(b('7d 7s', '7c 7h')).toBe(true);
    expect(b('7c 7h', '7d 7s')).toBe(false);
  });

  it('triples by rank', () => {
    expect(b('9d 9c 9h', '8c 8h 8s')).toBe(true);
    expect(b('2d 2c 2h', 'Ac Ah As')).toBe(true);
  });

  it('five-card order: straight < flush < full house < four of a kind < straight flush', () => {
    const order = ['Ad Ac 2h 2s 5d', '2d 2c 2h 4s 5d', '3d 4c 5h 6s 7d', '3h 8h Th Qh Kh', '4d 4c 4h 3s 3d', '5d 5c 5h 5s 3c', '3s 4s 5s 6s 7s'];
    for (let i = 1; i < order.length; i++) {
      expect(b(order[i]!, order[i - 1]!)).toBe(true);
      expect(b(order[i - 1]!, order[i]!)).toBe(false);
    }
    expect(b('3s 4s 5s 6s 7s', '2d 2c 2h 2s Ac')).toBe(true);
  });

  it('straights by top card, then its suit', () => {
    expect(b('4d 5c 6h 7s 8d', '3d 4c 5h 6s 7s')).toBe(true);
    expect(b('3d 4c 5h 6s 7s', '3c 4d 5d 6d 7h')).toBe(true);
    expect(b('Jd Qc Kh Ad 2d', 'Ts Js Qs Ks Ah')).toBe(true);
  });

  it('flushes: suit first by default', () => {
    expect(b('3s 4s 6s 7s 9s', 'Th Jh Qh Kh 2h')).toBe(true);
    expect(b('3h 4h 6h 7h Kh', '3h 4h 6h 7h Qh')).toBe(true);
    expect(b('3h 5h 6h 7h Kh', '3h 4h 6h 7h Kh')).toBe(true);
  });

  it('flushes: high card first when flushCompare is highCardFirst', () => {
    const hc = { flushCompare: 'highCardFirst' } as const;
    expect(b('Th Jh Qh Kh 2h', '3s 4s 6s 7s 9s', hc)).toBe(true);
    expect(b('3s 4s 6s 7s 9s', '3h 4h 6h 7h 9h', hc)).toBe(true);
  });

  it('full house and four of a kind by the big rank', () => {
    expect(b('5d 5c 5h 3s 3d', '4d 4c 4h As Ad')).toBe(true);
    expect(b('6d 6c 6h 6s 3d', '5d 5c 5h 5s 2d')).toBe(true);
  });

  it('straight flush by top card then suit', () => {
    expect(b('4d 5d 6d 7d 8d', '3s 4s 5s 6s 7s')).toBe(true);
    expect(b('3s 4s 5s 6s 7s', '3h 4h 5h 6h 7h')).toBe(true);
  });

  it('never beats a different card count, so bombs only meet 5-card hands', () => {
    expect(b('5d 5c 5h 5s 3c', '2s')).toBe(false);
    expect(b('3s 4s 5s 6s 7s', '2h 2s')).toBe(false);
    expect(b('2s', '3d 4c 5h 6s 7d')).toBe(false);
  });
});

describe('combo enumeration', () => {
  it('finds every combo in a hand once', () => {
    const hand = c('3d 3c 3h 4s 5d 6c 7h 7s');
    const plays = allCombos(hand, cfg());
    const keys = plays.map((p) => p.cards.join(' '));
    expect(new Set(keys).size).toBe(keys.length);
    expect(plays.filter((p) => p.combo.kind === 'single')).toHaveLength(8);
    expect(plays.filter((p) => p.combo.kind === 'pair')).toHaveLength(4);
    expect(plays.filter((p) => p.combo.kind === 'triple')).toHaveLength(1);
    expect(plays.filter((p) => p.combo.kind === 'straight')).toHaveLength(6); // 3 threes × 2 sevens
    expect(plays.filter((p) => p.combo.kind === 'fullhouse')).toHaveLength(1);
  });

  it('agrees with brute force over a random 13-card hand', () => {
    for (let seed = 0; seed < 20; seed++) {
      const hand = createRng(seed).shuffle(fullDeck()).slice(0, 13);
      const plays = allCombos(hand, cfg());
      const fast = new Set(plays.map((p) => p.cards.join(' ')));
      expect(fast.size, 'no duplicates').toBe(plays.length);
      let brute = 0;
      for (let mask = 1; mask < 1 << 13; mask++) {
        const pick = hand.filter((_, i) => mask & (1 << i));
        if (pick.length <= 5 && classify(pick, cfg())) brute++;
      }
      expect(fast.size).toBe(brute);
    }
  });
});

describe('deal and burn', () => {
  const expected: Record<number, [number, number]> = {
    2: [13, 26], 3: [13, 13], 4: [13, 0], 5: [10, 2], 6: [8, 4], 7: [7, 3], 8: [6, 4],
  };
  it.each(Object.entries(expected))('%s players get the shared deal', (n, [each, out]) => {
    const s = setup([...Array(Number(n)).keys()], cfg(), createRng(7));
    expect(s.hands.every((h) => h.length === each)).toBe(true);
    expect(s.out).toHaveLength(out);
    expect(new Set([...s.hands.flat(), ...s.out]).size).toBe(52);
  });

  it('the 3♦ holder leads and must include it', () => {
    for (let seed = 0; seed < 50; seed++) {
      const s = setup([0, 1, 2, 3], cfg(), createRng(seed));
      expect(s.hands[s.turn]).toContain('3d');
      expect(s.mustInclude).toBe('3d');
      expect(validate(s, s.turn, { type: 'play', cards: [s.hands[s.turn]!.find((x) => x !== '3d')!] }).ok).toBe(false);
      expect(validate(s, s.turn, play('3d')).ok).toBe(true);
    }
  });

  it('if 3♦ is burned, the lowest card leads', () => {
    let seen = 0;
    for (let seed = 0; seen < 5 && seed < 500; seed++) {
      const s = setup([...Array(8).keys()], cfg(), createRng(seed));
      if (!s.out.includes('3d')) continue;
      seen++;
      const all = s.hands.flat();
      const lowest = all.reduce((a, b) => (classify([a], cfg())!.key[0]! < classify([b], cfg())!.key[0]! ? a : b));
      expect(s.mustInclude).toBe(lowest);
      expect(s.hands[s.turn]).toContain(lowest);
    }
    expect(seen).toBe(5);
  });
});

describe('turns and passing', () => {
  it("the leader can't pass", () => {
    const s = state(['3d 4d', '5d 6d', '7d 8d']);
    expect(validate(s, 0, PASS).ok).toBe(false);
    expect(legalMoves(s, 0).some((m) => m.type === 'pass')).toBe(false);
  });

  it('rejects wrong turn, missing cards, duplicates, wrong count and weaker plays', () => {
    const s = state(['3d 4d 5c 5h', '6d 7d', '8d 9d'], { turn: 1, lead: { seat: 0, cards: ['5c'], combo: combo('5c') }, lastPlayer: 0 });
    expect(validate(s, 0, play('3d')).ok).toBe(false);
    expect(validate(s, 1, play('8d')).ok).toBe(false);
    expect(validate(s, 1, play('6d 6d')).ok).toBe(false);
    expect(validate(s, 1, play('6d 7d')).ok).toBe(false);
    expect(validate(s, 1, { type: 'play', cards: ['xx'] } as never).ok).toBe(false);
    expect(validate(s, 1, { type: 'nope' } as never).ok).toBe(false);
    expect(validate(s, 1, null as never).ok).toBe(false);
    expect(validate(s, 1, play('6d')).ok).toBe(true);
    const low = state(['3d', '4d 4c', '8d'], { turn: 1, lead: { seat: 0, cards: ['5s'], combo: combo('5s') }, lastPlayer: 0 });
    expect(validate(low, 1, play('4d')).ok).toBe(false);
  });

  it('everyone passing gives the lead back to the last player', () => {
    const s0 = state(['3d 9d', '4d Td', '5d Jd']);
    const { s, events } = run(s0, [[0, play('3d')], [1, PASS], [2, PASS]]);
    expect(s.turn).toBe(0);
    expect(s.lead).toBeNull();
    expect(events.some((e) => e.type === 'all_passed' && e.seat === 0)).toBe(true);
  });

  it('by default a pass only skips that turn', () => {
    const s0 = state(['3d 9d Kd', '4d Td Kc', '5d Jd Ks']);
    const { s } = run(s0, [[0, play('3d')], [1, PASS], [2, play('5d')], [0, play('9d')]]);
    expect(s.turn).toBe(1);
    expect(validate(s, 1, play('Td')).ok).toBe(true);
  });

  it('with passLocksOut, a passer sits out until the trick resets', () => {
    const s0 = state(['3d 9d Kd', '4d Td Kc', '5d Jd Ks'], {}, cfg({ passLocksOut: true }));
    const { s } = run(s0, [[0, play('3d')], [1, PASS], [2, play('5d')], [0, play('9d')]]);
    expect(s.turn).toBe(2);
    const r = run(s, [[2, PASS]]);
    expect(r.s.turn).toBe(0);
    expect(r.s.lead).toBeNull();
  });
});

describe('Standard scoring', () => {
  it('ends when one player goes out; cards left are penalties, 10–12 double, 13 triple', () => {
    const hands = [
      '3d',
      '4d 4c 4h 4s 5d 5c 5h 5s 6d', // 9
      '7d 7c 7h 7s 8d 8c 8h 8s 9d 9c', // 10
      'Td Tc Th Ts Jd Jc Jh Js Qd Qc Qh Qs Kd', // 13
    ];
    const { s, events } = run(state(hands), [[0, play('3d')]]);
    expect(s.phase).toBe('matchOver');
    expect(result(s)!.points).toEqual([0, 9, 20, 39]);
    expect(result(s)!.placings).toEqual([0, 1, 2, 3]);
    expect(events.map((e) => e.type)).toContain('player_out');
  });
});

describe('Fight Till The End', () => {
  const ftte = cfg({ mode: 'fightTillTheEnd' });

  it('skips finished players and passes their lead to the next player still in', () => {
    const s0 = state(['3d', '4d 9d', '5d Td'], {}, ftte);
    let { s } = run(s0, [[0, play('3d')]]);
    expect(s.phase).toBe('play');
    expect(s.turn).toBe(1);
    ({ s } = run(s, [[1, PASS], [2, PASS]]));
    expect(s.lead).toBeNull();
    expect(s.turn).toBe(1); // next still in after seat 0
    ({ s } = run(s, [[1, play('4d')], [2, play('5d')], [1, play('9d')]]));
    expect(s.phase).toBe('matchOver');
    // places: 0 first (0), 1 second (1), 2 last (2 + 1 card left)
    expect(result(s)!.placings).toEqual([0, 1, 2]);
    expect(result(s)!.points).toEqual([0, 1, 3]);
  });
});

describe('finishing on a 2 puts you last', () => {
  it('Standard: the round goes on, the next to go out wins, the 2-finisher scores as 13 cards', () => {
    const s0 = state(['2h', '4d 9d', '5d Td'], { turn: 0 });
    let { s, events } = run(s0, [[0, play('2h')]]);
    expect(s.phase).toBe('play');
    expect(events.find((e) => e.type === 'player_out')).toMatchObject({ seat: 0, onTwo: true, place: 3 });
    ({ s } = run(s, [[1, PASS], [2, PASS], [1, play('4d')], [2, play('5d')], [1, play('9d')]]));
    expect(s.phase).toBe('matchOver');
    expect(result(s)!.placings).toEqual([1, 2, 0]);
    expect(result(s)!.points).toEqual([39, 0, 1]);
  });
  it('Standard, 2 players: the other player wins', () => {
    const { s } = run(state(['2h', '4d 9d'], { turn: 0 }), [[0, play('2h')]]);
    expect(s.phase).toBe('matchOver');
    expect(result(s)!.placings).toEqual([1, 0]);
    expect(result(s)!.points).toEqual([39, 0]);
  });
  it('counts a 2 anywhere in the last play (a pair, a straight)', () => {
    const { s } = run(state(['2h 2s', '4d 9d', '5d Td'], { turn: 0 }), [[0, play('2h 2s')]]);
    expect(s.onTwo).toEqual([0]);
  });
  it('Fight Till The End: 2-finishers fill the bottom places, the first one very last', () => {
    const ftte = cfg({ mode: 'fightTillTheEnd' });
    const s0 = state(['2s', '2h', '5d Td', '3c'], { turn: 0 }, ftte);
    let { s } = run(s0, [[0, play('2s')]]); // 0 out on a 2 (unbeatable): lead passes on
    expect(s.turn).toBe(1);
    ({ s } = run(s, [[1, play('2h')], [2, PASS], [3, PASS]])); // 1 out on a 2 too
    ({ s } = run(s, [[2, play('5d')], [3, PASS], [2, play('Td')]])); // 2 goes out properly; 3 holds
    expect(s.phase).toBe('matchOver');
    expect(result(s)!.placings).toEqual([2, 3, 1, 0]);
    // places 0..3; seat 3 (left holding 1 card) also pays 1
    expect(result(s)!.points).toEqual([3, 2, 0, 1 + 1]);
  });
  it('can be switched off', () => {
    const { s } = run(state(['2h', '4d 9d'], { turn: 0 }, cfg({ twoFinishLoses: false })), [[0, play('2h')]]);
    expect(result(s)!.placings).toEqual([0, 1]);
  });
  it('bots avoid it when they can', () => {
    // Leading with 2h and 5d left: a bot must not play the 2 last.
    const s0 = state(['5d 2h', '4d 9d 9c'], { turn: 0 });
    const move = bot(view(s0, 0), 'normal', createRng(1));
    expect(move).toEqual(play('5d'));
  });
});

describe('multi-round matches', () => {
  it('keeps scores, re-deals with 3♦ leading, and doubles the last round', () => {
    const config = cfg({ roundsToPlay: 2 });
    let s = state(['3d', '4d 5d'], {}, config);
    s = apply(s, 0, play('3d')).state;
    expect(s.phase).toBe('roundOver');
    expect(s.scores).toEqual([0, 2]);
    s = nextRound(s, createRng(1));
    expect(s.round).toBe(2);
    // 3♦ leads if dealt; with 2 players it may be among the 26 cards left out.
    if (s.hands.flat().includes('3d')) expect(s.mustInclude).toBe('3d');
    expect(s.hands[s.turn]).toContain(s.mustInclude);
    expect(s.scores).toEqual([0, 2]);
    // finish round 2 with bots and check the doubling
    const rng = createRng(2);
    while (s.phase === 'play') s = apply(s, s.turn, bot(view(s, s.turn), 'normal', rng)).state;
    expect(s.phase).toBe('matchOver');
    const pts = result(s)!.points;
    expect(pts.every((p) => p % 2 === 0)).toBe(true);
    expect(s.scores).toEqual([0 + pts[0]!, 2 + pts[1]!]);
  });
});

describe('masked copies (what each phone holds)', () => {
  it('follow the public log and match the host after every move', () => {
    for (let seed = 0; seed < 20; seed++) {
      const rng = createRng(seed);
      let host = setup([0, 1, 2, 3, 4], cfg({ mode: seed % 2 ? 'fightTillTheEnd' : 'standard' }), rng);
      let copies = [0, 1, 2, 3, 4].map((i) => mask(host, i));
      while (host.phase === 'play') {
        const seat = host.turn;
        const m = bot(view(host, seat), 'normal', rng);
        host = apply(host, seat, m).state;
        copies = copies.map((c) => applyTrusted(c, seat, m).state);
        copies.forEach((c, i) => {
          expect(checksum(c)).toBe(checksum(host));
          expect(view(c, i)).toEqual(view(host, i));
        });
      }
    }
  });
  it("never hold another seat's cards or the burned cards", () => {
    const s = setup([0, 1, 2, 3, 4, 5, 6, 7], cfg(), createRng(3));
    const m = mask(s, 2);
    expect(m.hands[2]).toEqual(s.hands[2]);
    for (const [i, h] of m.hands.entries()) if (i !== 2) expect(h.every((c) => c === '??')).toBe(true);
    expect(m.out.every((c) => c === '??')).toBe(true);
    expect(mask(s, 'public').hands.flat().every((c) => c === '??')).toBe(true);
  });
});

describe('views', () => {
  it('show only your own hand; the public view shows none', () => {
    const s = setup([0, 1, 2, 3], cfg(), createRng(3));
    const pub = JSON.stringify(view(s, 'public'));
    for (const card of s.hands.flat()) expect(pub).not.toContain(`"${card}"`);
    for (let seat = 0; seat < 4; seat++) {
      const v = JSON.stringify(view(s, seat));
      for (let other = 0; other < 4; other++) {
        if (other === seat) continue;
        for (const card of s.hands[other]!) expect(v).not.toContain(`"${card}"`);
      }
    }
  });
});

describe('bots', () => {
  it('always return a legal move', () => {
    for (let seed = 0; seed < 30; seed++) {
      const rng = createRng(seed);
      let s = setup([0, 1, 2, 3, 4], cfg(), rng);
      while (s.phase === 'play') {
        const m = bot(view(s, s.turn), seed % 2 ? 'easy' : 'normal', rng);
        expect(validate(s, s.turn, m)).toEqual({ ok: true });
        s = apply(s, s.turn, m).state;
      }
    }
  });
});
