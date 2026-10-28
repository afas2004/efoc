// Zombie rules (docs/spec.md "Zombie", docs/decisions.md).
//
// Old Maid with one Joker, the Zombie. All 53 cards are dealt (uneven hands,
// never burned) and every pair of the same rank is thrown face up. On your
// turn you draw one face-down card from the next player still holding cards;
// a new pair is thrown at once. Empty hands are safe. The last player left
// holding the Zombie loses.
//
// Hidden positions: the drawer picks a slot index, never a card; the host
// maps it through the holder's private order. A drawn card goes to the end
// of the drawer's hand, so the player it came from knows where it is until
// the drawer reorders (drag) or shuffles. Reordering is allowed any time,
// on anyone's turn, and everyone sees *that* a hand was shuffled (a real
// table's tell), never the new order.
//
// Hidden information: the host holds the real state. Every phone holds
// mask(state, seat) (its own hand real, the rest placeholders) and advances
// it with applyPublic(entry); its drawn card and its new order arrive as
// private events (`to` its seat). Who held the Zombie when stays secret
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
  /** Draw the card at `slot` of the next player's hand; `shuffle` mixes my hand after. */
  | { type: 'draw'; slot: number; shuffle?: boolean }
  /** My whole hand in a new order (drag or Shuffle). Any time, anyone's turn. */
  | { type: 'order'; cards: Card[] };

/** Secret until the end: how the Zombie moved. */
export interface ZombieStats {
  /** Times the Zombie was drawn. */
  moves: number;
  /** Per seat: times the Zombie was drawn from them (Hot Potato). */
  drawnFrom: number[];
  /** Per seat: turns they held the Zombie at the end of a draw. */
  held: number[];
  /** Who held it at the deal. */
  dealtTo: SeatId;
}

export interface ZombieState {
  config: ZombieConfig;
  players: number;
  /** hands[seat], in the holder's own order. Private. */
  hands: Card[][];
  /** Pairs thrown at the deal, per seat (public, face up). */
  dealPairs: Card[][];
  /** Every pair thrown, face up, in order. */
  pile: Card[];
  /** Pairs thrown per seat, deal included. */
  pairs: number[];
  turn: SeatId;
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
    dealPairs: s.dealPairs.map((h) => h.slice()),
    pile: s.pile.slice(),
    pairs: s.pairs.slice(),
    safe: s.safe.slice(),
    stats: s.stats && { ...s.stats, drawnFrom: s.stats.drawnFrom.slice(), held: s.stats.held.slice() },
  };
}

/** Removes every pair of the same rank; returns what's left (order kept) and the pairs. */
export function throwPairs(hand: Card[]): { left: Card[]; pairs: Card[] } {
  const seen = new Map<string, number>();
  const drop = new Set<number>();
  hand.forEach((c, i) => {
    if (isZombie(c) || c === HIDDEN) return;
    const r = rankOf(c);
    const j = seen.get(r);
    if (j === undefined) seen.set(r, i);
    else {
      drop.add(j);
      drop.add(i);
      seen.delete(r);
    }
  });
  const pairs: Card[] = [];
  const left: Card[] = [];
  hand.forEach((c, i) => (drop.has(i) ? pairs : left).push(c));
  return { left, pairs };
}

// ---------------------------------------------------------------- setup

export function setup(seats: SeatId[], config: ZombieConfig, rng: Rng): ZombieState {
  const n = seats.length;
  if (n < 2 || n > 8) throw new Error(`Zombie needs 2 to 8 players, got ${n}`);
  for (;;) {
    const deck = rng.shuffle(fullDeck(true));
    const dealt: Card[][] = Array.from({ length: n }, () => []);
    deck.forEach((c, i) => dealt[i % n]!.push(c));
    const hands: Card[][] = [];
    const dealPairs: Card[][] = [];
    for (const h of dealt) {
      const { left, pairs } = throwPairs(h);
      hands.push(left);
      dealPairs.push(pairs);
    }
    // Vanishingly rare: everyone but one paired out at the deal. Deal again.
    if (hands.filter((h) => h.length > 0).length < 2) continue;
    const holder = hands.findIndex((h) => h.includes(ZOMBIE));
    const s: ZombieState = {
      config,
      players: n,
      hands,
      dealPairs,
      pile: dealPairs.flat(),
      pairs: dealPairs.map((p) => p.length / 2),
      turn: 0,
      safe: [],
      draws: 0,
      maxDraws: config.maxDraws > 0 ? config.maxDraws : 2000,
      phase: 'play',
      loser: null,
      stats: { moves: 0, drawnFrom: new Array<number>(n).fill(0), held: new Array<number>(n).fill(0), dealtTo: holder },
    };
    // Empty at the deal: safe already, in seat order.
    hands.forEach((h, i) => h.length === 0 && s.safe.push(i));
    // The host (seat 0) draws first, or the next player still in.
    s.turn = hands[0]!.length > 0 ? 0 : nextIn(s, 0);
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

/** Whose hand `seat` draws from on its turn. */
export const targetOf = (s: ZombieState, seat: SeatId): SeatId => nextIn(s, seat);

export function legalMoves(state: ZombieState, seat: SeatId): ZombieMove[] {
  if (state.phase !== 'play' || seat !== state.turn) return [];
  const n = state.hands[targetOf(state, seat)]!.length;
  return Array.from({ length: n }, (_, slot) => ({ type: 'draw', slot }));
}

/** Same cards, maybe in another order. */
function samePile(a: readonly Card[], b: readonly Card[]): boolean {
  if (a.length !== b.length) return false;
  const x = a.slice().sort();
  const y = b.slice().sort();
  return x.every((c, i) => c === y[i]);
}

export function validate(state: ZombieState, seat: SeatId, move: unknown): ValidateResult {
  const no = (reason: string): ValidateResult => ({ ok: false, reason });
  if (state.phase !== 'play') return no('The round is over');
  const m = move as ZombieMove | null;
  if (!m || typeof m !== 'object') return no('Bad move');
  if (!Number.isInteger(seat) || seat < 0 || seat >= state.players) return no('Bad seat');
  if (m.type === 'order') {
    const hand = state.hands[seat]!;
    if (hand.length === 0) return no("You're safe");
    if (!Array.isArray(m.cards) || !samePile(m.cards, hand)) return no('Your hand changed');
    return { ok: true };
  }
  if (m.type !== 'draw') return no('Bad move');
  if (seat !== state.turn) return no('Not your turn');
  if (m.shuffle !== undefined && typeof m.shuffle !== 'boolean') return no('Bad move');
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
 * Applies a checked move on the host's real state. Phones never run it:
 * applyPublic follows the log on a masked copy instead.
 */
function applyTrusted(state: ZombieState, seat: SeatId, move: ZombieMove, rng: Rng): { state: ZombieState; events: GameEvent[] } {
  const s = clone(state);
  const events: GameEvent[] = [];
  if (move.type === 'order') {
    s.hands[seat] = move.cards.slice();
    events.push({ type: 'shuffled', seat });
    events.push({ type: 'hand', to: seat, cards: s.hands[seat]!.slice() });
    return { state: s, events };
  }

  const from = targetOf(s, seat);
  const card = s.hands[from]!.splice(move.slot, 1)[0]!;
  const hand = s.hands[seat]!;
  hand.push(card);
  events.push({ type: 'drew', seat, from, slot: move.slot });
  events.push({ type: 'drawn_card', to: seat, card, from });
  if (isZombie(card)) {
    s.stats!.moves++;
    s.stats!.drawnFrom[from]!++;
  }
  // A new pair goes face up at once.
  const partner = isZombie(card) ? -1 : hand.findIndex((c, i) => i < hand.length - 1 && !isZombie(c) && rankOf(c) === rankOf(card));
  if (partner >= 0) {
    const mate = hand[partner]!;
    hand.splice(hand.length - 1, 1);
    hand.splice(partner, 1);
    s.pile.push(mate, card);
    s.pairs[seat]!++;
    events.push({ type: 'pair', seat, cards: [mate, card] });
  }
  if (move.shuffle && hand.length > 1) {
    s.hands[seat] = rng.shuffle(hand);
    events.push({ type: 'shuffled', seat });
    events.push({ type: 'hand', to: seat, cards: s.hands[seat]!.slice() });
  }
  s.draws++;
  for (const who of [from, seat]) {
    if (s.hands[who]!.length === 0 && !s.safe.includes(who)) {
      s.safe.push(who);
      events.push({ type: 'safe', seat: who, place: s.safe.length });
    }
  }
  const holder = s.hands.findIndex((h) => h.includes(ZOMBIE));
  if (holder >= 0) s.stats!.held[holder]!++;
  const left = s.hands.map((h, i) => (h.length > 0 ? i : -1)).filter((i) => i >= 0);
  if (left.length <= 1 || s.draws >= s.maxDraws) {
    finish(s, events);
    return { state: s, events };
  }
  s.turn = nextIn(s, seat);
  events.push({ type: 'turn', seat: s.turn, from: targetOf(s, s.turn) });
  return { state: s, events };
}

/** The Zombie's holder loses; everyone else ranks by when they got safe. */
function finish(s: ZombieState, events: GameEvent[]): void {
  s.phase = 'over';
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
 * spectator ('public') sees no hand at all. After the end, only the loser's
 * hand (the Zombie) is shown; it's in the zombie_loser event.
 */
export function mask(state: ZombieState, seat: SeatId | 'public'): ZombieState {
  const s = clone(state);
  s.hands = s.hands.map((h, i) => (i === seat ? h : h.map(() => HIDDEN)));
  if (s.phase !== 'over') s.stats = null;
  else if (s.loser !== null) s.hands[s.loser] = state.hands[s.loser]!.slice();
  return s;
}

/**
 * Advances a masked copy by one public log entry. The move may arrive with
 * its private part stripped (an order's cards never enter the log).
 */
export function applyPublic(state: ZombieState, seat: SeatId, move: { type: string; slot?: number }, events: readonly GameEvent[]): ZombieState {
  const s = clone(state);
  if (move.type !== 'draw') return s; // a reorder: nothing public changes
  const from = targetOf(s, seat);
  s.hands[from]!.splice(move.slot!, 1);
  // Someone else's hand, or mine before my private event says what I drew.
  s.hands[seat]!.push(HIDDEN);
  s.draws++;
  for (const e of events) {
    if (e.type === 'pair') {
      const hand = s.hands[seat]!;
      for (const c of e.cards as Card[]) {
        const i = hand.lastIndexOf(c);
        hand.splice(i >= 0 ? i : hand.lastIndexOf(HIDDEN), 1);
      }
      s.pile.push(...(e.cards as Card[]));
      s.pairs[seat]!++;
    } else if (e.type === 'safe') {
      s.safe.push(e.seat as SeatId);
    } else if (e.type === 'turn') {
      s.turn = e.seat as SeatId;
    } else if (e.type === 'zombie_loser') {
      s.phase = 'over';
      s.loser = e.seat as SeatId;
      s.hands[s.loser] = (e.hand as Card[]).slice();
    } else if (e.type === 'round_ended') {
      const st = e.stats as unknown as ZombieStats;
      s.stats = { ...st, drawnFrom: st.drawnFrom.slice(), held: st.held.slice() };
    }
  }
  return s;
}

/** A private event for `seat` (its drawn card, its new order) folded into its copy. */
export function applyPrivate(state: ZombieState, seat: SeatId, e: GameEvent): ZombieState {
  if (e.type === 'drawn_card') {
    const hand = state.hands[seat]!;
    const i = hand.lastIndexOf(HIDDEN);
    if (i < 0) return state; // it paired straight away
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
  turn: SeatId;
  /** Whose hand the player to move draws from. */
  from: SeatId;
  /** My own hand in my order (empty for a spectator). */
  hand: Card[];
  counts: number[];
  dealPairs: Card[][];
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
  const own = seat === 'public' ? [] : state.hands[seat]!.slice();
  return {
    seat,
    config: state.config,
    players: state.players,
    turn: state.turn,
    from: targetOf(state, state.turn),
    hand: own,
    counts: state.hands.map((h) => h.length),
    dealPairs: state.dealPairs.map((p) => p.slice()),
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
