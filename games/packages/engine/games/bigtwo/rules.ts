// Big Two rules: combo detection and comparison, legal plays, and the round
// state machine for Standard and Fight Till The End. Pure and deterministic.
// See docs/spec.md (Big Two) and docs/decisions.md.

import { isCard, rankOf, suitOf, type Card, type Order, type Rank, type Suit } from '../../core/cards';
import { combinations, compareKeys, groupBy, product } from '../../core/combos';
import { dealEven } from '../../core/deal';
import type { Rng } from '../../core/rng';
import type { GameEvent, RoundResult, SeatId, ValidateResult } from '../../core/types';
import type { BigTwoConfig } from './config';

// ---------------------------------------------------------------- ordering

export const RANK_ORDER: Order<Rank> = {
  '3': 0, '4': 1, '5': 2, '6': 3, '7': 4, '8': 5, '9': 6, T: 7, J: 8, Q: 9, K: 10, A: 11, '2': 12,
};
export const SUIT_ORDER: Order<Suit> = { d: 0, c: 1, h: 2, s: 3 };

export const rankIndex = (c: Card): number => RANK_ORDER[rankOf(c)];
export const suitIndex = (c: Card): number => SUIT_ORDER[suitOf(c)];
/** Single-card strength: rank first, then suit. 0 (3♦) to 51 (2♠). */
export const cardValue = (c: Card): number => rankIndex(c) * 4 + suitIndex(c);

export function sortCards(cards: readonly Card[]): Card[] {
  return [...cards].sort((a, b) => cardValue(a) - cardValue(b));
}

// ------------------------------------------------------------------ combos

export type ComboKind =
  | 'single' | 'pair' | 'triple' | 'quad'
  | 'straight' | 'flush' | 'fullhouse' | 'fourkind' | 'straightflush';

export interface Combo {
  kind: ComboKind;
  size: number;
  /** Compared lexicographically against a combo of the same size. */
  key: number[];
}

const FIVE_CARD_ORDER: Partial<Record<ComboKind, number>> = {
  straight: 0, flush: 1, fullhouse: 2, fourkind: 3, straightflush: 4,
};

export const isBomb = (kind: ComboKind): boolean =>
  kind === 'fourkind' || kind === 'straightflush' || kind === 'quad';

/** Straight strength and the rank index of its top card, or null. */
function straightInfo(rankIdxs: number[], config: BigTwoConfig): { strength: number; top: number } | null {
  const r = [...rankIdxs].sort((a, b) => a - b);
  if (new Set(r).size !== 5) return null;
  // 3…2 in a row, no wrap: 3-4-5-6-7 (top 7, strength 4) up to J-Q-K-A-2 (top 2, strength 12).
  if (r[4]! - r[0]! === 4) return { strength: r[4]!, top: r[4]! };
  const key = r.join(',');
  if (config.allowA2345 && key === '0,1,2,11,12') return { strength: 1, top: 2 }; // A-2-3-4-5, top is the 5
  if (config.allow23456 && key === '0,1,2,3,12') return { strength: 2, top: 3 }; // 2-3-4-5-6, top is the 6
  return null;
}

/** Classifies a set of cards as a Big Two combo, or null if it isn't one. */
export function classify(cards: readonly Card[], config: BigTwoConfig): Combo | null {
  const n = cards.length;
  const ranks = cards.map(rankIndex);
  const sameRank = ranks.every((r) => r === ranks[0]);
  if (n === 1) return { kind: 'single', size: 1, key: [cardValue(cards[0]!)] };
  if (n === 2) return sameRank ? { kind: 'pair', size: 2, key: [Math.max(...cards.map(cardValue))] } : null;
  if (n === 3) return sameRank && config.allowTriples ? { kind: 'triple', size: 3, key: [ranks[0]!] } : null;
  if (n === 4) return sameRank && !config.fourOfAKindKicker ? { kind: 'quad', size: 4, key: [ranks[0]!] } : null;
  if (n !== 5) return null;

  const suits = cards.map(suitIndex);
  const flush = suits.every((s) => s === suits[0]);
  const straight = straightInfo(ranks, config);
  if (straight) {
    const topCard = cards.find((c) => rankIndex(c) === straight.top)!;
    const kind: ComboKind = flush ? 'straightflush' : 'straight';
    return { kind, size: 5, key: [FIVE_CARD_ORDER[kind]!, straight.strength, suitIndex(topCard)] };
  }
  if (flush) {
    const desc = [...ranks].sort((a, b) => b - a);
    const key = config.flushCompare === 'suitFirst' ? [suits[0]!, ...desc] : [...desc, suits[0]!];
    return { kind: 'flush', size: 5, key: [FIVE_CARD_ORDER.flush!, ...key] };
  }
  const counts = [...groupBy(ranks, (r) => r).entries()].sort((a, b) => b[1].length - a[1].length);
  const [big, small] = counts;
  if (counts.length === 2 && big![1].length === 3 && small![1].length === 2) {
    return { kind: 'fullhouse', size: 5, key: [FIVE_CARD_ORDER.fullhouse!, big![0]] };
  }
  if (counts.length === 2 && big![1].length === 4 && config.fourOfAKindKicker) {
    return { kind: 'fourkind', size: 5, key: [FIVE_CARD_ORDER.fourkind!, big![0]] };
  }
  return null;
}

/** True when `a` can be played on `b`: same card count and stronger. */
export function beats(a: Combo, b: Combo): boolean {
  return a.size === b.size && compareKeys(a.key, b.key) > 0;
}

export interface Play {
  cards: Card[];
  combo: Combo;
}

/** Every combo the hand can make, without duplicates. */
export function allCombos(hand: readonly Card[], config: BigTwoConfig): Play[] {
  const out: Play[] = [];
  const add = (cards: Card[]): void => {
    const combo = classify(cards, config);
    if (combo) out.push({ cards: sortCards(cards), combo });
  };
  const sorted = sortCards(hand);
  for (const c of sorted) add([c]);

  const byRank = groupBy(sorted, rankIndex);
  for (const group of byRank.values()) {
    for (const p of combinations(group, 2)) add(p);
    if (config.allowTriples) for (const t of combinations(group, 3)) add(t);
    if (!config.fourOfAKindKicker && group.length === 4) add(group);
  }
  if (sorted.length < 5) return out;

  // Straights and straight flushes, one window of ranks at a time.
  const windows: number[][] = [];
  for (let start = 0; start + 4 <= 12; start++) windows.push([0, 1, 2, 3, 4].map((i) => start + i));
  if (config.allowA2345) windows.push([11, 12, 0, 1, 2]);
  if (config.allow23456) windows.push([12, 0, 1, 2, 3]);
  for (const w of windows) {
    const groups = w.map((r) => byRank.get(r) ?? []);
    if (groups.some((g) => g.length === 0)) continue;
    for (const cards of product(groups)) add(cards);
  }
  // Flushes that aren't straights (those were added above).
  for (const group of groupBy(sorted, suitIndex).values()) {
    if (group.length < 5) continue;
    for (const cards of combinations(group, 5)) {
      const combo = classify(cards, config);
      if (combo?.kind === 'flush') out.push({ cards, combo });
    }
  }
  // Full houses and four of a kind + kicker.
  for (const [r3, g3] of byRank) {
    if (g3.length >= 3) {
      for (const [r2, g2] of byRank) {
        if (r2 === r3 || g2.length < 2) continue;
        for (const t of combinations(g3, 3)) for (const p of combinations(g2, 2)) add([...t, ...p]);
      }
    }
    if (g3.length === 4 && config.fourOfAKindKicker) {
      for (const k of sorted) if (rankIndex(k) !== r3) add([...g3, k]);
    }
  }
  return out;
}

/** Plays from `hand` that may be made now. */
export function legalPlays(
  hand: readonly Card[],
  lead: Combo | null,
  mustInclude: Card | null,
  config: BigTwoConfig,
): Play[] {
  return allCombos(hand, config).filter(
    (p) => (!mustInclude || p.cards.includes(mustInclude)) && (!lead || beats(p.combo, lead)),
  );
}

// ------------------------------------------------------------------- state

export type BigTwoMove = { type: 'play'; cards: Card[] } | { type: 'pass' };

export interface BigTwoState {
  config: BigTwoConfig;
  players: number;
  hands: Card[][];
  /** Burned and past-the-cap cards, face down, never shown. */
  out: Card[];
  /** Every card played this round, in order. Public. */
  pile: Card[];
  turn: SeatId;
  /** The play to beat, or null when the turn player leads. */
  lead: { seat: SeatId; cards: Card[]; combo: Combo } | null;
  /** Who made the last play in the current trick. */
  lastPlayer: SeatId | null;
  passed: boolean[];
  /** The opening play must include this card (3♦, or the lowest dealt card if 3♦ was burned). */
  mustInclude: Card | null;
  /** Seats that went out, in order. */
  finished: SeatId[];
  phase: 'play' | 'roundOver' | 'matchOver';
  round: number;
  /** Cumulative penalty points for the match. */
  scores: number[];
  roundPoints: number[] | null;
  placings: SeatId[] | null;
}

function clone(s: BigTwoState): BigTwoState {
  return {
    ...s,
    hands: s.hands.map((h) => h.slice()),
    out: s.out.slice(),
    pile: s.pile.slice(),
    lead: s.lead && { ...s.lead, cards: s.lead.cards.slice(), combo: { ...s.lead.combo, key: s.lead.combo.key.slice() } },
    passed: s.passed.slice(),
    finished: s.finished.slice(),
    scores: s.scores.slice(),
    roundPoints: s.roundPoints && s.roundPoints.slice(),
    placings: s.placings && s.placings.slice(),
  };
}

function dealRound(players: number, config: BigTwoConfig, rng: Rng, round: number, scores: number[]): BigTwoState {
  const { hands, out } = dealEven(players, rng, 13);
  const opening = hands.some((h) => h.includes('3d'))
    ? '3d'
    : sortCards(hands.flat())[0]!;
  const opener = hands.findIndex((h) => h.includes(opening));
  return {
    config,
    players,
    hands: hands.map(sortCards),
    out,
    pile: [],
    turn: opener,
    lead: null,
    lastPlayer: null,
    passed: new Array<boolean>(players).fill(false),
    mustInclude: opening,
    finished: [],
    phase: 'play',
    round,
    scores,
    roundPoints: null,
    placings: null,
  };
}

export function setup(seats: SeatId[], config: BigTwoConfig, rng: Rng): BigTwoState {
  if (seats.length < 2 || seats.length > 8) throw new Error(`Big Two needs 2 to 8 players, got ${seats.length}`);
  return dealRound(seats.length, config, rng, 1, new Array<number>(seats.length).fill(0));
}

/** Deals the next round of a multi-round match, keeping the scores. */
export function nextRound(state: BigTwoState, rng: Rng): BigTwoState {
  if (state.phase !== 'roundOver') throw new Error('The round is not over');
  return dealRound(state.players, state.config, rng, state.round + 1, state.scores.slice());
}

const isActive = (s: BigTwoState, seat: SeatId): boolean => s.hands[seat]!.length > 0;

export function legalMoves(state: BigTwoState, seat: SeatId): BigTwoMove[] {
  if (state.phase !== 'play' || seat !== state.turn) return [];
  const plays = legalPlays(state.hands[seat]!, state.lead?.combo ?? null, state.mustInclude, state.config);
  const moves: BigTwoMove[] = plays.map((p) => ({ type: 'play', cards: p.cards }));
  if (state.lead) moves.push({ type: 'pass' });
  return moves;
}

export function validate(state: BigTwoState, seat: SeatId, move: unknown): ValidateResult {
  if (state.phase !== 'play') return { ok: false, reason: 'The round is over' };
  if (seat !== state.turn) return { ok: false, reason: 'Not your turn' };
  if (typeof move !== 'object' || move === null) return { ok: false, reason: 'Bad move' };
  const m = move as { type?: unknown; cards?: unknown };
  if (m.type === 'pass') {
    return state.lead ? { ok: true } : { ok: false, reason: 'You have the lead, so you must play' };
  }
  if (m.type !== 'play' || !Array.isArray(m.cards)) return { ok: false, reason: 'Bad move' };
  const cards = m.cards as unknown[];
  if (cards.length === 0 || !cards.every(isCard)) return { ok: false, reason: 'Bad cards' };
  if (new Set(cards).size !== cards.length) return { ok: false, reason: 'Same card twice' };
  const hand = state.hands[seat]!;
  if (!cards.every((c) => hand.includes(c))) return { ok: false, reason: "That card isn't in your hand" };
  const combo = classify(cards, state.config);
  if (!combo) return { ok: false, reason: 'Not a valid combination' };
  if (state.mustInclude && !cards.includes(state.mustInclude)) {
    return { ok: false, reason: `The first play must include ${state.mustInclude}` };
  }
  if (state.lead) {
    if (combo.size !== state.lead.combo.size) return { ok: false, reason: `Play ${state.lead.combo.size} card(s)` };
    if (!beats(combo, state.lead.combo)) return { ok: false, reason: "That doesn't beat the last play" };
  }
  return { ok: true };
}

function penaltyFor(cardsLeft: number): number {
  if (cardsLeft >= 13) return cardsLeft * 3;
  if (cardsLeft >= 10) return cardsLeft * 2;
  return cardsLeft;
}

function endRound(s: BigTwoState, events: GameEvent[]): void {
  const n = s.players;
  const points = new Array<number>(n).fill(0);
  let placings: SeatId[];
  if (s.config.mode === 'standard') {
    const winner = s.finished[0]!;
    const rest: SeatId[] = [];
    for (let i = 1; i < n; i++) rest.push((winner + i) % n);
    rest.sort((a, b) => s.hands[a]!.length - s.hands[b]!.length); // stable: ties keep seat order from the winner
    placings = [winner, ...rest];
    for (const seat of rest) points[seat] = penaltyFor(s.hands[seat]!.length);
  } else {
    placings = s.finished.slice();
    placings.forEach((seat, place) => (points[seat] = place));
    const last = placings[n - 1]!;
    points[last] = points[last]! + s.hands[last]!.length;
  }
  const doubled = s.config.roundsToPlay > 1 && s.round === s.config.roundsToPlay;
  if (doubled) for (let i = 0; i < n; i++) points[i] = points[i]! * 2;
  for (let i = 0; i < n; i++) s.scores[i] = s.scores[i]! + points[i]!;
  s.roundPoints = points;
  s.placings = placings;
  s.phase = s.round >= s.config.roundsToPlay ? 'matchOver' : 'roundOver';
  s.lead = null;
  events.push({ type: 'round_ended', points, placings, doubled, scores: s.scores.slice() });
}

/** Moves the turn on, resetting the trick when everyone else has passed. */
function advance(s: BigTwoState, events: GameEvent[]): void {
  const n = s.players;
  for (let i = 1; i <= n; i++) {
    const c = (s.turn + i) % n;
    if (c === s.lastPlayer && isActive(s, c)) return resetTrick(s, c, events);
    if (c !== s.turn && isActive(s, c) && !s.passed[c]) {
      s.turn = c;
      return;
    }
  }
  // Everyone still in has passed and the last player went out: the lead
  // goes to the next player still holding cards.
  let c = s.lastPlayer!;
  do c = (c + 1) % n;
  while (!isActive(s, c));
  resetTrick(s, c, events);
}

function resetTrick(s: BigTwoState, leader: SeatId, events: GameEvent[]): void {
  events.push({ type: 'all_passed', seat: s.lastPlayer!, leader });
  s.lead = null;
  s.passed.fill(false);
  s.turn = leader;
}

export function apply(
  state: BigTwoState,
  seat: SeatId,
  move: BigTwoMove,
  _rng?: Rng,
): { state: BigTwoState; events: GameEvent[] } {
  const check = validate(state, seat, move);
  if (!check.ok) throw new Error(`Illegal move by seat ${seat}: ${check.reason}`);
  const s = clone(state);
  const events: GameEvent[] = [];

  if (move.type === 'pass') {
    s.passed[seat] = true;
    events.push({ type: 'passed', seat });
    advance(s, events);
    return { state: s, events };
  }

  const cards = sortCards(move.cards);
  const combo = classify(cards, s.config)!;
  s.hands[seat] = s.hands[seat]!.filter((c) => !cards.includes(c));
  s.pile.push(...cards);
  s.lead = { seat, cards, combo };
  s.lastPlayer = seat;
  s.mustInclude = null;
  if (!s.config.passLocksOut) s.passed.fill(false);
  events.push({ type: 'card_played', seat, cards, kind: combo.kind, left: s.hands[seat]!.length });
  if (isBomb(combo.kind)) events.push({ type: 'bomb', seat, kind: combo.kind });

  if (s.hands[seat]!.length === 0) {
    s.finished.push(seat);
    events.push({ type: 'player_out', seat, place: s.finished.length });
    const stillIn = s.hands.map((_, i) => i).filter((i) => isActive(s, i));
    if (s.config.mode === 'standard') {
      endRound(s, events);
      return { state: s, events };
    }
    if (stillIn.length === 1) {
      s.finished.push(stillIn[0]!);
      endRound(s, events);
      return { state: s, events };
    }
  }
  advance(s, events);
  return { state: s, events };
}

export function result(state: BigTwoState): RoundResult | null {
  if (state.phase === 'play') return null;
  return { points: state.roundPoints!.slice(), placings: state.placings!.slice() };
}

// -------------------------------------------------------------------- view

export type BigTwoView = {
  seat: SeatId | 'public';
  config: BigTwoConfig;
  players: number;
  /** Your own hand; empty in the public view. */
  hand: Card[];
  handCounts: number[];
  turn: SeatId;
  lead: { seat: SeatId; cards: Card[]; kind: ComboKind } | null;
  lastPlayer: SeatId | null;
  passed: boolean[];
  /** Set only for the seat that holds the card the opening play must include. */
  mustInclude: Card | null;
  openingPlay: boolean;
  pile: Card[];
  outCount: number;
  finished: SeatId[];
  phase: BigTwoState['phase'];
  round: number;
  scores: number[];
  roundPoints: number[] | null;
};

export function view(state: BigTwoState, seat: SeatId | 'public'): BigTwoView {
  const hand = seat === 'public' ? [] : state.hands[seat]!.slice();
  return {
    seat,
    config: state.config,
    players: state.players,
    hand,
    handCounts: state.hands.map((h) => h.length),
    turn: state.turn,
    lead: state.lead && { seat: state.lead.seat, cards: state.lead.cards.slice(), kind: state.lead.combo.kind },
    lastPlayer: state.lastPlayer,
    passed: state.passed.slice(),
    mustInclude: state.mustInclude && hand.includes(state.mustInclude) ? state.mustInclude : null,
    openingPlay: state.mustInclude !== null,
    pile: state.pile.slice(),
    outCount: state.out.length,
    finished: state.finished.slice(),
    phase: state.phase,
    round: state.round,
    scores: state.scores.slice(),
    roundPoints: state.roundPoints && state.roundPoints.slice(),
  };
}
