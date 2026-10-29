// Zombie rules (docs/spec.md "Zombie", docs/decisions.md).
//
// Old Maid with one Joker, the Zombie. All 53 cards are dealt (uneven hands,
// never burned). Then everyone throws their pairs of the same rank face up,
// all at once (step 'deal'). On your turn the next player still holding
// cards has their hand shuffled for them, you aim at one face-down card
// (everyone sees which slot you're pointing at, the holder too), and
// confirm to draw it. If it makes a pair you throw that pair (step
// 'throw'). Empty hands are safe. The last player left holding the Zombie
// loses.
//
// Hidden positions: the drawer picks a slot index, never a card; the host
// maps it through the holder's private order. The holder's hand is
// shuffled by the host at the start of every turn it's drawn from, so
// nobody can track where the Zombie went.
//
// Hidden information: the host holds the real state. Every phone holds
// mask(state, seat) (its own hand real, the rest placeholders) and advances
// it with applyPublic(entry); its drawn card and its shuffled order arrive
// as private events (`to` its seat). Who held the Zombie when stays secret
// until the round ends.

import { fullDeck, JOKER, rankOf, type Card } from '../../core/cards';
import type { Rng } from '../../core/rng';
import type { GameEvent, RoundResult, SeatId, ValidateResult } from '../../core/types';
import type { ZombieConfig } from './config';

/** A card a phone isn't allowed to see. */
export const HIDDEN = '??';
export const ZOMBIE = JOKER;

export const isZombie = (c: Card | null | undefined): boolean => c === ZOMBIE;

export type ZombieMove =
  /** Point at the card at `slot` of the next player's hand (anyone can see which). Doesn't end the turn. */
  | { type: 'aim'; slot: number }
  /** Draw the card at `slot` of the next player's hand. */
  | { type: 'draw'; slot: number }
  /** Throw a pair face up: of `rank`, or every pair I hold when no rank is given. */
  | { type: 'throw'; rank?: string };

/** Secret until the end: how the Zombie moved. */
export interface ZombieStats {
  /** Times the Zombie was drawn. */
  moves: number;
  /** Per seat: times the Zombie was drawn from them (Hot Potato). */
  drawnFrom: number[];
  /** Per seat: draws that ended with them holding the Zombie. */
  held: number[];
  /** Who held it at the deal. */
  dealtTo: SeatId;
}

export interface ZombieState {
  config: ZombieConfig;
  players: number;
  /** hands[seat], in the holder's order. Private. */
  hands: Card[][];
  /** Every pair thrown, face up, in order. */
  pile: Card[];
  /** Pairs thrown per seat. */
  pairs: number[];
  /** 'deal': everyone throws their dealt pairs at once; 'draw': `turn` aims and draws; 'throw': `turn` throws the pair it drew. */
  step: 'deal' | 'draw' | 'throw';
  turn: SeatId;
  /** The slot the drawer is pointing at, or null. */
  aim: number | null;
  /** Seats whose hands emptied, in that order. */
  safe: SeatId[];
  draws: number;
  maxDraws: number;
  phase: 'play' | 'over';
  loser: SeatId | null;
  /** Host only until the end (masked to null). */
  stats: ZombieStats | null;
}

function clone(s: ZombieState): ZombieState {
  return {
    ...s,
    hands: s.hands.map((h) => h.slice()),
    pile: s.pile.slice(),
    pairs: s.pairs.slice(),
    safe: s.safe.slice(),
    stats: s.stats && { ...s.stats, drawnFrom: s.stats.drawnFrom.slice(), held: s.stats.held.slice() },
  };
}

/** Pairs in a hand: [[a, b], ...] in hand order, two cards of a rank each (the Zombie never pairs, not even with a J). */
export function pairsIn(hand: readonly Card[]): Card[][] {
  const seen = new Map<string, Card>();
  const out: Card[][] = [];
  for (const c of hand) {
    if (isZombie(c) || c === HIDDEN) continue;
    const r = rankOf(c);
    const mate = seen.get(r);
    if (mate === undefined) seen.set(r, c);
    else {
      out.push([mate, c]);
      seen.delete(r);
    }
  }
  return out;
}

// ---------------------------------------------------------------- setup

export function setup(seats: SeatId[], config: ZombieConfig, rng: Rng): ZombieState {
  const n = seats.length;
  if (n < 2 || n > 8) throw new Error(`Zombie needs 2 to 8 players, got ${n}`);
  for (;;) {
    const deck = rng.shuffle(fullDeck(true));
    const hands: Card[][] = Array.from({ length: n }, () => []);
    deck.forEach((c, i) => hands[i % n]!.push(c));
    // Vanishingly rare: everyone but one would pair out at the deal. Deal again.
    const left = hands.filter((h) => h.length > pairsIn(h).length * 2).length;
    if (left < 2) continue;
    const s: ZombieState = {
      config,
      players: n,
      hands,
      pile: [],
      pairs: new Array<number>(n).fill(0),
      step: 'deal',
      turn: 0,
      aim: null,
      safe: [],
      draws: 0,
      maxDraws: config.maxDraws > 0 ? config.maxDraws : 2000,
      phase: 'play',
      loser: null,
      stats: { moves: 0, drawnFrom: new Array<number>(n).fill(0), held: new Array<number>(n).fill(0), dealtTo: hands.findIndex((h) => h.includes(ZOMBIE)) },
    };
    // Nobody dealt a pair (rare, big tables): straight to the first draw.
    if (hands.every((h) => pairsIn(h).length === 0)) startTurn(s, 0, rng, []);
    return s;
  }
}

// ---------------------------------------------------------------- moves

/** The next seat clockwise after `seat` still holding cards. */
export function nextIn(s: ZombieState, seat: SeatId): SeatId {
  for (let k = 1; k <= s.players; k++) {
    const i = (seat + k) % s.players;
    if (s.hands[i]!.length > 0) return i;
  }
  return seat;
}

/** The nearest seat before `seat` still holding cards. */
export function prevIn(s: ZombieState, seat: SeatId): SeatId {
  for (let k = 1; k <= s.players; k++) {
    const i = (seat - k + s.players) % s.players;
    if (s.hands[i]!.length > 0) return i;
  }
  return seat;
}

/**
 * Whose hand `seat` draws from on its turn: the player before it. The turn
 * then moves on, so whoever just picked is the next one picked from.
 */
export const targetOf = (s: ZombieState, seat: SeatId): SeatId => prevIn(s, seat);

export function legalMoves(state: ZombieState, seat: SeatId): ZombieMove[] {
  if (state.phase !== 'play') return [];
  if (state.step === 'deal') return pairsIn(state.hands[seat]!).length > 0 ? [{ type: 'throw' }] : [];
  if (seat !== state.turn) return [];
  if (state.step === 'throw') return [{ type: 'throw' }];
  const n = state.hands[targetOf(state, seat)]!.length;
  return Array.from({ length: n }, (_, slot) => ({ type: 'draw', slot }));
}

export function validate(state: ZombieState, seat: SeatId, move: unknown): ValidateResult {
  const no = (reason: string): ValidateResult => ({ ok: false, reason });
  if (state.phase !== 'play') return no('The round is over');
  const m = move as ZombieMove | null;
  if (!m || typeof m !== 'object') return no('Bad move');
  if (!Number.isInteger(seat) || seat < 0 || seat >= state.players) return no('Bad seat');
  if (m.type === 'throw') {
    if (state.step === 'draw' || (state.step === 'throw' && seat !== state.turn)) return no('Nothing to throw now');
    const pairs = pairsIn(state.hands[seat]!);
    if (pairs.length === 0) return no('No pairs to throw');
    if (m.rank !== undefined && !pairs.some((p) => rankOf(p[0]!) === m.rank)) return no('No pair of that rank');
    return { ok: true };
  }
  if (m.type !== 'draw' && m.type !== 'aim') return no('Bad move');
  if (state.step === 'deal') return no('Throw your pairs first');
  if (seat !== state.turn) return no('Not your turn');
  if (state.step !== 'draw') return no('Throw your pair first');
  const n = state.hands[targetOf(state, seat)]!.length;
  if (!Number.isInteger(m.slot) || m.slot < 0 || m.slot >= n) return no('Pick one of their cards');
  return { ok: true };
}

export function apply(state: ZombieState, seat: SeatId, move: ZombieMove, rng: Rng): { state: ZombieState; events: GameEvent[] } {
  const check = validate(state, seat, move);
  if (!check.ok) throw new Error(`Illegal move by seat ${seat}: ${check.reason}`);
  return applyTrusted(state, seat, move, rng);
}

/**
 * Starts `seat`'s turn: the hand it draws from is shuffled first, so nobody
 * knows where any card sits in it. Only its holder learns the new order.
 */
function startTurn(s: ZombieState, seat: SeatId, rng: Rng, events: GameEvent[]): void {
  s.turn = seat;
  s.step = 'draw';
  s.aim = null;
  const from = targetOf(s, seat);
  s.hands[from] = rng.shuffle(s.hands[from]!);
  events.push({ type: 'turn', seat, from });
  events.push({ type: 'shuffled', seat: from, auto: true });
  events.push({ type: 'hand', to: from, cards: s.hands[from]!.slice() });
}

function markSafe(s: ZombieState, events: GameEvent[], who: SeatId[]): void {
  for (const w of who) {
    if (s.hands[w]!.length === 0 && !s.safe.includes(w)) {
      s.safe.push(w);
      events.push({ type: 'safe', seat: w, place: s.safe.length });
    }
  }
}

/** After a turn's draw (and its pair): the round ends, or the next player draws. */
function endTurn(s: ZombieState, seat: SeatId, rng: Rng, events: GameEvent[]): void {
  const holder = s.hands.findIndex((h) => h.includes(ZOMBIE));
  if (holder >= 0) s.stats!.held[holder]!++;
  const left = s.hands.filter((h) => h.length > 0).length;
  if (left <= 1 || s.draws >= s.maxDraws) return finish(s, events);
  startTurn(s, nextIn(s, seat), rng, events);
}

/** Applies a checked move on the host's real state. Phones run applyPublic instead. */
function applyTrusted(state: ZombieState, seat: SeatId, move: ZombieMove, rng: Rng): { state: ZombieState; events: GameEvent[] } {
  const s = clone(state);
  const events: GameEvent[] = [];
  if (move.type === 'aim') {
    s.aim = move.slot;
    events.push({ type: 'aim', seat, from: targetOf(s, seat), slot: move.slot });
    return { state: s, events };
  }
  if (move.type === 'throw') {
    const hand = s.hands[seat]!;
    const pairs = pairsIn(hand).filter((p) => move.rank === undefined || rankOf(p[0]!) === move.rank);
    for (const pair of move.rank === undefined ? pairs : pairs.slice(0, 1)) {
      for (const c of pair) hand.splice(hand.indexOf(c), 1);
      s.pile.push(...pair);
      s.pairs[seat]!++;
      events.push({ type: 'pair', seat, cards: pair.slice() });
    }
    if (s.step === 'throw') {
      s.step = 'draw';
      markSafe(s, events, [seat]);
      endTurn(s, seat, rng, events);
    } else {
      markSafe(s, events, [seat]);
      // Everyone's dealt pairs are down: the host (or the next player in) draws first.
      if (s.hands.every((h) => pairsIn(h).length === 0)) startTurn(s, s.hands[0]!.length > 0 ? 0 : nextIn(s, 0), rng, events);
    }
    return { state: s, events };
  }

  const from = targetOf(s, seat);
  const card = s.hands[from]!.splice(move.slot, 1)[0]!;
  const hand = s.hands[seat]!;
  hand.push(card);
  s.aim = null;
  s.draws++;
  const pair = !isZombie(card) && hand.some((c, i) => i < hand.length - 1 && !isZombie(c) && rankOf(c) === rankOf(card));
  events.push({ type: 'drew', seat, from, slot: move.slot, pair });
  events.push({ type: 'drawn_card', to: seat, card, from });
  if (isZombie(card)) {
    s.stats!.moves++;
    s.stats!.drawnFrom[from]!++;
  }
  markSafe(s, events, [from]);
  if (pair) {
    s.step = 'throw';
    return { state: s, events };
  }
  endTurn(s, seat, rng, events);
  return { state: s, events };
}

/** The Zombie's holder loses; everyone else ranks by when they got safe. */
function finish(s: ZombieState, events: GameEvent[]): void {
  s.phase = 'over';
  s.aim = null;
  const loser = s.hands.findIndex((h) => h.includes(ZOMBIE));
  s.loser = loser;
  const order = placings(s);
  const points = new Array<number>(s.players).fill(0);
  points[loser] = 1;
  events.push({ type: 'zombie_loser', seat: loser, hand: s.hands[loser]!.slice() });
  events.push({ type: 'round_ended', points, placings: order, stats: s.stats as unknown as Record<string, unknown> });
}

export function result(state: ZombieState): RoundResult | null {
  if (state.phase !== 'over' || state.loser === null) return null;
  const points = new Array<number>(state.players).fill(0);
  points[state.loser] = 1;
  return { points, placings: placings(state) };
}

/** Safe in the order they got out; after a draw cap, fewest cards next; the loser last. */
function placings(s: ZombieState): SeatId[] {
  const loser = s.loser!;
  const rest = s.hands
    .map((_, i) => i)
    .filter((i) => i !== loser && !s.safe.includes(i))
    .sort((a, b) => s.hands[a]!.length - s.hands[b]!.length || a - b);
  return [...s.safe, ...rest, loser];
}

// -------------------------------------------------------------- masking

/**
 * The table as `seat`'s phone may hold it: its own hand real, every other
 * hand placeholders of the right length, and the Zombie's story secret. A
 * spectator ('public') sees no hand at all. After the end the loser's hand
 * is public (it's in the zombie_loser event).
 */
export function mask(state: ZombieState, seat: SeatId | 'public'): ZombieState {
  const s = clone(state);
  s.hands = s.hands.map((h, i) => (i === seat ? h : h.map(() => HIDDEN)));
  if (s.phase !== 'over') s.stats = null;
  else if (s.loser !== null) s.hands[s.loser] = state.hands[s.loser]!.slice();
  return s;
}

/** Advances a masked copy by one public log entry, from the entry's events. */
export function applyPublic(state: ZombieState, seat: SeatId, move: { type: string; slot?: number }, events: readonly GameEvent[]): ZombieState {
  const s = clone(state);
  for (const e of events) {
    switch (e.type) {
      case 'aim':
        s.aim = e.slot as number;
        break;
      case 'drew': {
        const from = e.from as SeatId;
        s.hands[from]!.splice(e.slot as number, 1);
        // Someone else's hand, or mine until my private event says what I drew.
        s.hands[seat]!.push(HIDDEN);
        s.aim = null;
        s.draws++;
        if (e.pair) s.step = 'throw';
        break;
      }
      case 'pair': {
        const who = e.seat as SeatId;
        const hand = s.hands[who]!;
        for (const c of e.cards as Card[]) {
          const i = hand.lastIndexOf(c);
          hand.splice(i >= 0 ? i : hand.lastIndexOf(HIDDEN), 1);
        }
        s.pile.push(...(e.cards as Card[]));
        s.pairs[who]!++;
        break;
      }
      case 'safe':
        s.safe.push(e.seat as SeatId);
        break;
      case 'turn':
        s.turn = e.seat as SeatId;
        s.step = 'draw';
        s.aim = null;
        break;
      case 'zombie_loser':
        s.phase = 'over';
        s.step = 'draw';
        s.aim = null;
        s.loser = e.seat as SeatId;
        s.hands[s.loser] = (e.hand as Card[]).slice();
        break;
      case 'round_ended': {
        const st = e.stats as unknown as ZombieStats;
        s.stats = { ...st, drawnFrom: st.drawnFrom.slice(), held: st.held.slice() };
        break;
      }
      default:
    }
  }
  void move;
  return s;
}

/** A private event for `seat` (its drawn card, its shuffled order) folded into its copy. */
export function applyPrivate(state: ZombieState, seat: SeatId, e: GameEvent): ZombieState {
  if (e.type === 'drawn_card') {
    const i = state.hands[seat]!.lastIndexOf(HIDDEN);
    if (i < 0) return state;
    const s = clone(state);
    s.hands[seat]![i] = e.card as Card;
    return s;
  }
  if (e.type === 'hand') {
    const s = clone(state);
    s.hands[seat] = (e.cards as Card[]).slice();
    return s;
  }
  return state;
}

/** FNV-1a over the public view: equal on every phone that applied the same log. */
export function checksum(state: ZombieState): string {
  const text = JSON.stringify(view(state, 'public'));
  let h = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) {
    h ^= text.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return (h >>> 0).toString(16).padStart(8, '0');
}

// ----------------------------------------------------------------- view

export type ZombieView = {
  seat: SeatId | 'public';
  config: ZombieConfig;
  players: number;
  step: ZombieState['step'];
  turn: SeatId;
  /** Whose hand the player to move draws from. */
  from: SeatId;
  aim: number | null;
  /** My own hand in its order (empty for a spectator). */
  hand: Card[];
  counts: number[];
  pile: Card[];
  pairs: number[];
  safe: SeatId[];
  draws: number;
  phase: ZombieState['phase'];
  loser: SeatId | null;
  /** The loser's last hand, after the end. */
  loserHand: Card[] | null;
  stats: ZombieStats | null;
  placings: SeatId[] | null;
};

export function view(state: ZombieState, seat: SeatId | 'public'): ZombieView {
  const over = state.phase === 'over';
  return {
    seat,
    config: state.config,
    players: state.players,
    step: state.step,
    turn: state.turn,
    from: targetOf(state, state.turn),
    aim: state.aim,
    hand: seat === 'public' ? [] : state.hands[seat]!.slice(),
    counts: state.hands.map((h) => h.length),
    pile: state.pile.slice(),
    pairs: state.pairs.slice(),
    safe: state.safe.slice(),
    draws: state.draws,
    phase: state.phase,
    loser: state.loser,
    loserHand: over && state.loser !== null ? state.hands[state.loser]!.slice() : null,
    stats: over && state.stats ? { ...state.stats, drawnFrom: state.stats.drawnFrom.slice(), held: state.stats.held.slice() } : null,
    placings: over && state.loser !== null ? placings(state) : null,
  };
}
