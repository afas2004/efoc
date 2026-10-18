// Lucky 7 rules (docs/spec.md "Lucky 7", docs/decisions.md).
//
// Everyone holds 3 face-down cards in slots 0-2 that nobody sees, not even
// the owner. A turn is: draw (the centre deck, seen only by you, or the top
// of Discard, seen by all), then swap it into a slot (the old card goes face
// up onto Discard), throw it onto Discard, or use it if it's a power card.
// The round ends when a turn finishes with the centre deck empty; lowest
// total wins.
//
// Powers: J peek: EITHER see all your own (unlocked) cards, OR one card of
// another player (playtest 18 Oct), Q swap one of yours with one of theirs, K lock a card (no peek,
// swap or shuffle; the K sits on it), 9 unlock (the K goes to Used) or skip,
// 10 shuffle one seat's unlocked slots. Used powers go to Used for good.
//
// Hidden information: the host holds the real state. Every phone holds
// mask(state) and advances it with applyPublic(entry), which takes any card
// that becomes public from the entry's events. Private events (your drawn
// card, your peeks) carry `to` and only ever reach that seat.

import { fullDeck, rankOf, type Card } from '../../core/cards';
import { createRng, type Rng } from '../../core/rng';
import type { GameEvent, RoundResult, SeatId, ValidateResult } from '../../core/types';
import type { LuckySevenConfig } from './config';

export const SLOTS = 3;

/** A card a phone isn't allowed to see. */
export const HIDDEN = '??';

export type Power = 'J' | 'Q' | 'K' | '9' | 'T';
const POWERS = new Set<string>(['J', 'Q', 'K', '9', 'T']);

export const powerOf = (c: Card | null): Power | null => (c && c !== HIDDEN && POWERS.has(rankOf(c)) ? (rankOf(c) as Power) : null);

/** 7 = 0, A = 1, 2 to 10 face value, J Q K = 10. */
export function cardPoints(c: Card): number {
  const r = rankOf(c);
  if (r === '7') return 0;
  if (r === 'A') return 1;
  if (r === 'T' || r === 'J' || r === 'Q' || r === 'K') return 10;
  return Number(r);
}

export interface Target {
  seat: SeatId;
  slot: number;
}

export type LuckyMove =
  | { type: 'draw'; from: 'deck' | 'discard' }
  | { type: 'swap'; slot: number }
  | { type: 'discard' }
  /**
   * Use the drawn power card. J: no fields (then a peek move). Q: `mine` and
   * `target`. K: `target`. 9: `target` (a locked slot) or null to skip.
   * 10: `seat`.
   */
  | { type: 'use'; mine?: number; target?: Target | null; seat?: SeatId }
  /**
   * After a J, one of: `own: true` to see all your own unlocked cards, or
   * `target` for one unlocked card of another player (null only when there
   * is nothing at all to look at).
   */
  | { type: 'peek'; own?: boolean; target?: Target | null };

export interface LuckyState {
  config: LuckySevenConfig;
  players: number;
  /** slots[seat][0..2]. Nobody sees these until the end. */
  slots: Card[][];
  /** The K locking each slot, or null. */
  locks: (Card | null)[][];
  /** Centre deck; the top is the last card. */
  deck: Card[];
  /** Face-up Discard pile; the top is the last card. */
  discard: Card[];
  /** Who threw the top Discard card away (for "Thanks for the gift!"). */
  discardBy: SeatId | null;
  /** Used powers. Never taken or used again. */
  used: Card[];
  turn: SeatId;
  step: 'draw' | 'act' | 'peek';
  drawn: Card | null;
  drawnFrom: 'deck' | 'discard' | null;
  turns: number;
  maxTurns: number;
  phase: 'play' | 'over';
  totals: number[] | null;
  placings: SeatId[] | null;
}

function clone(s: LuckyState): LuckyState {
  return {
    ...s,
    slots: s.slots.map((x) => x.slice()),
    locks: s.locks.map((x) => x.slice()),
    deck: s.deck.slice(),
    discard: s.discard.slice(),
    used: s.used.slice(),
    totals: s.totals && s.totals.slice(),
    placings: s.placings && s.placings.slice(),
  };
}

// ---------------------------------------------------------------- setup

export function setup(seats: SeatId[], config: LuckySevenConfig, rng: Rng): LuckyState {
  const n = seats.length;
  if (n < 2 || n > 8) throw new Error(`Lucky 7 needs 2 to 8 players, got ${n}`);
  const deck = rng.shuffle(fullDeck());
  const slots: Card[][] = [];
  for (let i = 0; i < n; i++) slots.push(deck.splice(0, SLOTS));
  return {
    config,
    players: n,
    slots,
    locks: slots.map(() => new Array<Card | null>(SLOTS).fill(null)),
    deck,
    discard: [],
    discardBy: null,
    used: [],
    turn: 0, // the host is seat 0 and goes first
    step: 'draw',
    drawn: null,
    drawnFrom: null,
    turns: 0,
    maxTurns: config.maxTurns > 0 ? config.maxTurns : deck.length * 2,
    phase: 'play',
    totals: null,
    placings: null,
  };
}

// ---------------------------------------------------------------- moves

const isTarget = (t: unknown): t is Target =>
  !!t && typeof t === 'object' && Number.isInteger((t as Target).seat) && Number.isInteger((t as Target).slot);

const validSlot = (s: LuckyState, t: Target): boolean =>
  t.seat >= 0 && t.seat < s.players && t.slot >= 0 && t.slot < SLOTS;

const unlocked = (s: LuckyState, t: Target): boolean => validSlot(s, t) && s.locks[t.seat]![t.slot] === null;

function allSlots(s: LuckyState, filter: (t: Target) => boolean): Target[] {
  const out: Target[] = [];
  for (let seat = 0; seat < s.players; seat++) for (let slot = 0; slot < SLOTS; slot++) if (filter({ seat, slot })) out.push({ seat, slot });
  return out;
}

/** Opponent slots a Q may swap with. */
const openOpponentSlots = (s: LuckyState, me: SeatId): Target[] => allSlots(s, (t) => t.seat !== me && unlocked(s, t));

/** Do I have any unlocked card to look at? */
const ownOpen = (s: LuckyState, me: SeatId): boolean => s.locks[me]!.some((k) => k === null);

export function legalMoves(state: LuckyState, seat: SeatId): LuckyMove[] {
  if (state.phase !== 'play' || seat !== state.turn) return [];
  const out: LuckyMove[] = [];
  if (state.step === 'draw') {
    if (state.deck.length > 0) out.push({ type: 'draw', from: 'deck' });
    if (state.discard.length > 0) out.push({ type: 'draw', from: 'discard' });
    return out;
  }
  if (state.step === 'peek') {
    const peeks: LuckyMove[] = openOpponentSlots(state, seat).map((target) => ({ type: 'peek', target }));
    if (ownOpen(state, seat)) peeks.unshift({ type: 'peek', own: true });
    return peeks.length ? peeks : [{ type: 'peek', target: null }];
  }
  for (let slot = 0; slot < SLOTS; slot++) if (state.locks[seat]![slot] === null) out.push({ type: 'swap', slot });
  out.push({ type: 'discard' });
  const power = powerOf(state.drawn);
  if (power === 'J') out.push({ type: 'use' });
  if (power === 'Q') {
    const theirs = openOpponentSlots(state, seat);
    for (let mine = 0; mine < SLOTS; mine++) {
      if (state.locks[seat]![mine] !== null) continue;
      for (const target of theirs) out.push({ type: 'use', mine, target });
    }
  }
  if (power === 'K') for (const target of allSlots(state, (t) => unlocked(state, t))) out.push({ type: 'use', target });
  if (power === '9') {
    out.push({ type: 'use', target: null });
    for (const target of allSlots(state, (t) => validSlot(state, t) && state.locks[t.seat]![t.slot] !== null)) out.push({ type: 'use', target });
  }
  if (power === 'T') for (let s = 0; s < state.players; s++) out.push({ type: 'use', seat: s });
  return out;
}

export function validate(state: LuckyState, seat: SeatId, move: unknown): ValidateResult {
  const no = (reason: string): ValidateResult => ({ ok: false, reason });
  if (state.phase !== 'play') return no('The round is over');
  if (seat !== state.turn) return no('Not your turn');
  const m = move as LuckyMove | null;
  if (!m || typeof m !== 'object') return no('Bad move');
  if (state.step === 'draw') {
    if (m.type !== 'draw') return no('Draw a card first');
    if (m.from === 'deck') return state.deck.length > 0 ? { ok: true } : no('The centre deck is empty');
    if (m.from === 'discard') return state.discard.length > 0 ? { ok: true } : no('Discard is empty');
    return no('Bad move');
  }
  if (state.step === 'peek') {
    if (m.type !== 'peek') return no('Look at your cards, or one of theirs');
    if (m.own === true) return ownOpen(state, seat) ? { ok: true } : no('All your cards are locked');
    const nothing = !ownOpen(state, seat) && openOpponentSlots(state, seat).length === 0;
    if (m.target === null || m.target === undefined) return nothing ? { ok: true } : no('Look at your cards, or one of theirs');
    if (!isTarget(m.target) || m.target.seat === seat || !unlocked(state, m.target)) return no("You can't peek at that card");
    return { ok: true };
  }
  // step 'act'
  switch (m.type) {
    case 'swap':
      if (!Number.isInteger(m.slot) || m.slot < 0 || m.slot >= SLOTS) return no('Bad slot');
      return state.locks[seat]![m.slot] === null ? { ok: true } : no('That card is locked');
    case 'discard':
      return { ok: true };
    case 'use': {
      const power = powerOf(state.drawn);
      if (!power) return no('Only J, Q, K, 9 and 10 have powers');
      if (power === 'J') return { ok: true };
      if (power === 'Q') {
        if (!Number.isInteger(m.mine) || m.mine! < 0 || m.mine! >= SLOTS || state.locks[seat]![m.mine!] !== null) return no('Pick one of your unlocked cards');
        if (!isTarget(m.target) || m.target.seat === seat || !unlocked(state, m.target)) return no("Pick another player's unlocked card");
        return { ok: true };
      }
      if (power === 'K') return isTarget(m.target) && unlocked(state, m.target) ? { ok: true } : no('Pick an unlocked card to lock');
      if (power === '9') {
        if (m.target === null || m.target === undefined) return { ok: true };
        return isTarget(m.target) && validSlot(state, m.target) && state.locks[m.target.seat]![m.target.slot] !== null ? { ok: true } : no('Pick a locked card');
      }
      // 10
      return Number.isInteger(m.seat) && m.seat! >= 0 && m.seat! < state.players ? { ok: true } : no('Pick a player to shuffle');
    }
    default:
      return no('Swap, discard or use the card');
  }
}

export function apply(state: LuckyState, seat: SeatId, move: LuckyMove, rng: Rng): { state: LuckyState; events: GameEvent[] } {
  const check = validate(state, seat, move);
  if (!check.ok) throw new Error(`Illegal move by seat ${seat}: ${check.reason}`);
  return applyTrusted(state, seat, move, rng);
}

/**
 * Applies a checked move. The host runs it on the real state; phones run it
 * (through applyPublic) on their masked copy, where every slot and the deck
 * are placeholders, so it never needs to see a hidden card.
 */
function applyTrusted(state: LuckyState, seat: SeatId, move: LuckyMove, rng: Rng): { state: LuckyState; events: GameEvent[] } {
  const s = clone(state);
  const events: GameEvent[] = [];
  const endTurn = (): void => {
    // Did this turn take a card from the centre deck? (Discard draws leave the count as it was.)
    const fromDeck = s.drawnFrom === 'deck';
    s.drawn = null;
    s.drawnFrom = null;
    s.turns++;
    if (s.deck.length === 0 || s.turns >= s.maxTurns) {
      finish(s, events);
      return;
    }
    s.turn = (s.turn + 1) % s.players;
    s.step = 'draw';
    events.push({ type: 'turn', seat: s.turn, deck: s.deck.length, fromDeck });
    // Final lap: one card per player left in the centre deck (said once, when it gets there).
    if (fromDeck && s.deck.length === s.players) events.push({ type: 'final_lap' });
  };

  switch (move.type) {
    case 'draw': {
      if (move.from === 'deck') {
        const card = s.deck.pop()!;
        s.drawn = card;
        s.drawnFrom = 'deck';
        events.push({ type: 'drew', seat, from: 'deck', deck: s.deck.length });
        if (card !== HIDDEN) events.push({ type: 'drawn_card', to: seat, card });
      } else {
        const card = s.discard.pop()!;
        const from = s.discardBy;
        s.drawn = card;
        s.drawnFrom = 'discard';
        s.discardBy = null;
        events.push({ type: 'drew', seat, from: 'discard', card });
        // A 7, an A or an unused power thrown away, grabbed by the next player.
        if (from !== null && from !== seat && (cardPoints(card) <= 1 || powerOf(card))) {
          events.push({ type: 'gift_grabbed', seat, from, card });
        }
      }
      s.step = 'act';
      return { state: s, events };
    }
    case 'swap': {
      const out = s.slots[seat]![move.slot]!;
      s.slots[seat]![move.slot] = s.drawn!;
      s.discard.push(out);
      s.discardBy = seat;
      events.push({ type: 'swapped', seat, slot: move.slot, out });
      endTurn();
      return { state: s, events };
    }
    case 'discard': {
      const card = s.drawn!;
      s.discard.push(card);
      s.discardBy = seat;
      events.push({ type: 'discarded', seat, card });
      endTurn();
      return { state: s, events };
    }
    case 'use': {
      const card = s.drawn!;
      const power = powerOf(card)!;
      if (power === 'J') {
        s.used.push(card);
        s.drawn = null;
        s.step = 'peek';
        events.push({ type: 'power', seat, power, card });
        return { state: s, events };
      }
      if (power === 'Q') {
        const t = move.target!;
        const mine = move.mine!;
        const a = s.slots[seat]![mine]!;
        s.slots[seat]![mine] = s.slots[t.seat]![t.slot]!;
        s.slots[t.seat]![t.slot] = a;
        s.used.push(card);
        events.push({ type: 'power', seat, power, card, mine, target: t });
      } else if (power === 'K') {
        const t = move.target!;
        s.locks[t.seat]![t.slot] = card;
        events.push({ type: 'power', seat, power, card, target: t });
        events.push({ type: 'card_locked', seat, target: t });
      } else if (power === '9') {
        const t = move.target ?? null;
        s.used.push(card);
        if (t) {
          s.used.push(s.locks[t.seat]![t.slot]!);
          s.locks[t.seat]![t.slot] = null;
        }
        events.push({ type: 'power', seat, power, card, target: t });
        if (t) events.push({ type: 'lock_broken', seat, target: t });
      } else {
        const target = move.seat!;
        const open = [0, 1, 2].filter((i) => s.locks[target]![i] === null);
        const order = rng.shuffle(open);
        const before = s.slots[target]!.slice();
        open.forEach((slot, i) => (s.slots[target]![slot] = before[order[i]!]!));
        s.used.push(card);
        events.push({ type: 'power', seat, power, card, target: { seat: target, slot: -1 } });
        events.push({ type: 'shuffled', seat, target });
      }
      endTurn();
      return { state: s, events };
    }
    case 'peek': {
      if (move.own) {
        // All my own cards; locked ones stay hidden even from me.
        events.push({ type: 'peeked', seat, own: true });
        if (s.slots[seat]![0] !== HIDDEN) {
          const own = s.slots[seat]!.map((c, i) => (s.locks[seat]![i] === null ? c : null));
          events.push({ type: 'peek_own', to: seat, cards: own, seconds: s.config.peekSeconds });
        }
      } else if (move.target) {
        const card = s.slots[move.target.seat]![move.target.slot]!;
        events.push({ type: 'peeked', seat, target: move.target });
        if (card !== HIDDEN) events.push({ type: 'peek_card', to: seat, target: move.target, card, seconds: s.config.peekSeconds });
      }
      endTurn();
      return { state: s, events };
    }
  }
}

/** Everyone reveals; lowest total wins, ties share the win. Locks add nothing. */
function finish(s: LuckyState, events: GameEvent[]): void {
  s.phase = 'over';
  s.step = 'draw';
  score(s);
  events.push({ type: 'revealed', slots: s.slots.map((x) => x.slice()) });
  events.push({ type: 'round_ended', points: s.totals!.slice(), placings: s.placings!.slice() });
}

function score(s: LuckyState): void {
  s.totals = s.slots.map((cards) => cards.reduce((sum, c) => sum + (c === HIDDEN ? 0 : cardPoints(c)), 0));
  // Lowest first; ties keep seat order from the host.
  s.placings = s.slots.map((_, i) => i).sort((a, b) => s.totals![a]! - s.totals![b]!);
}

export function result(state: LuckyState): RoundResult | null {
  if (state.phase !== 'over') return null;
  return { points: state.totals!.slice(), placings: state.placings!.slice() };
}

/** Seats that share the lowest total. */
export function winners(state: LuckyState): SeatId[] {
  if (!state.totals) return [];
  const best = Math.min(...state.totals);
  return state.totals.map((t, i) => (t === best ? i : -1)).filter((i) => i >= 0);
}

// -------------------------------------------------------------- masking

/**
 * The table as a phone may hold it: every slot and the centre deck are
 * placeholders (nobody sees their own cards either). The card being drawn
 * stays visible only to the player holding it, or to all if it came off
 * Discard. After the reveal everything is public.
 */
export function mask(state: LuckyState, seat: SeatId | 'public'): LuckyState {
  const s = clone(state);
  if (s.phase === 'over') return s;
  s.slots = s.slots.map((x) => x.map(() => HIDDEN));
  s.deck = s.deck.map(() => HIDDEN);
  if (s.drawn && !(s.drawnFrom === 'discard' || seat === s.turn)) s.drawn = HIDDEN;
  return s;
}

const fixedRng = createRng(0);

/**
 * Advances a masked copy by one log entry. Cards that become public (a
 * swapped-out card, a thrown card, the reveal) come from the entry's events;
 * shuffles move placeholders, so the fixed RNG changes nothing visible.
 */
export function applyPublic(state: LuckyState, seat: SeatId, move: LuckyMove, events: readonly GameEvent[]): LuckyState {
  // A power card turns public when it's used; the event names it.
  const used = events.find((e) => e.type === 'power');
  if (move.type === 'use' && used && state.drawn !== used.card) state = { ...state, drawn: used.card as Card };
  const next = applyTrusted(state, seat, move, fixedRng).state;
  for (const e of events) {
    if (e.type === 'swapped' || e.type === 'discarded') {
      next.discard[next.discard.length - 1] = (e.type === 'swapped' ? e.out : e.card) as Card;
    } else if (e.type === 'drew' && e.from === 'deck' && seat === state.turn && next.drawn === HIDDEN) {
      // stays hidden; the drawer learns it from their private event
    } else if (e.type === 'revealed') {
      next.slots = (e.slots as Card[][]).map((x) => x.slice());
      score(next);
    }
  }
  return next;
}

/** A private event for `seat` (its drawn card) folded into its masked copy. */
export function applyPrivate(state: LuckyState, seat: SeatId, e: GameEvent): LuckyState {
  if (e.type !== 'drawn_card' || state.turn !== seat || state.drawnFrom !== 'deck') return state;
  const s = clone(state);
  s.drawn = e.card as Card;
  return s;
}

/** FNV-1a over the public view: equal on every phone that applied the same log. */
export function checksum(state: LuckyState): string {
  const text = JSON.stringify(view(state, 'public'));
  let h = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) {
    h ^= text.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return (h >>> 0).toString(16).padStart(8, '0');
}

// ----------------------------------------------------------------- view

export type LuckyView = {
  seat: SeatId | 'public';
  config: LuckySevenConfig;
  players: number;
  turn: SeatId;
  step: LuckyState['step'];
  /** The card in hand this turn, if this seat may see it. */
  drawn: Card | null;
  drawnFrom: LuckyState['drawnFrom'];
  deckCount: number;
  discard: Card[];
  used: Card[];
  /** locked[seat][slot]: a K sits on it. */
  locked: boolean[][];
  turns: number;
  maxTurns: number;
  phase: LuckyState['phase'];
  /** Every slot, only after the reveal. */
  revealed: Card[][] | null;
  totals: number[] | null;
  placings: SeatId[] | null;
};

export function view(state: LuckyState, seat: SeatId | 'public'): LuckyView {
  const seesDrawn = state.drawn !== null && state.drawn !== HIDDEN && (state.drawnFrom === 'discard' || seat === state.turn);
  return {
    seat,
    config: state.config,
    players: state.players,
    turn: state.turn,
    step: state.step,
    drawn: seesDrawn ? state.drawn : null,
    drawnFrom: state.drawnFrom,
    deckCount: state.deck.length,
    discard: state.discard.slice(),
    used: state.used.slice(),
    locked: state.locks.map((x) => x.map((k) => k !== null)),
    turns: state.turns,
    maxTurns: state.maxTurns,
    phase: state.phase,
    revealed: state.phase === 'over' ? state.slots.map((x) => x.slice()) : null,
    totals: state.totals && state.totals.slice(),
    placings: state.placings && state.placings.slice(),
  };
}
