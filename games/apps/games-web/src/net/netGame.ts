// What the online layer needs to know about each game. Room, relay and
// follower are the same for every game; this adapter supplies the rules
// module, how a masked copy follows the log, what each player's private
// data is, the table, and the house-rule defaults.
//
// Private data travels two ways:
//   - at a snapshot (a new deal, every 20 entries) the host writes each
//     player's private fields to hands/{uid} (handAt), with n;
//   - events with `to` (a drawn card, a peek) never go in the public log:
//     the relay writes them to hands/{uid}/ev/{n}, and that player's
//     follower applies them after entry n.

import { bigtwo, lucky7, type GameEvent, type GameModule, type Rng } from '@efoc/engine';
import type { Humour } from '../feel/jester';
import { BigTwoCommentator, dwellMs as bigTwoDwell } from '../games/bigtwo/commentary';
import { BigTwoTable } from '../games/bigtwo/table';
import { LuckySevenCommentator } from '../games/lucky7/commentary';
import { luckyHostOptions } from '../games/lucky7/practice';
import { LuckySevenTable } from '../games/lucky7/table';
import type { HostOptions } from '../host/hostCore';
import type { RematchInfo } from '../table/rematch';
import { L } from '../strings';
import { arr, reviveState as reviveBigTwo } from './follower';
import type { RoomMeta } from './protocol';
import type { Json } from './store';

export type OnlineGameId = 'bigtwo' | 'lucky7';

export interface TableUpdateMeta {
  deadline: number | null;
  afk: boolean[];
  totals?: number[];
}

/** The parts of a game table the online layer drives. */
export interface NetTable {
  isHost: boolean;
  readonly feel: unknown;
  update(view: never, events: GameEvent[], meta: TableUpdateMeta): void;
  reject(reason: string): void;
  notice(text: string): void;
  setConnection(conn: Conn[]): void;
  setRematch(info: RematchInfo | null): void;
}

/** A seat's connection on an online table. */
export type Conn = 'online' | 'away' | 'left' | 'bot';

export interface NetTableHooks {
  move(m: unknown): void;
  ready(): void;
  back(): void;
  playAgain(): void;
  exit(): void;
}

export interface SeatMeta {
  name: string;
  avatar: string;
  bot: boolean;
}

/* eslint-disable @typescript-eslint/no-explicit-any */
export interface NetGame {
  id: OnlineGameId;
  title(): string;
  /** Background class for the waiting room and table. */
  felt: string;
  /** Big Two's mode and poker-hands rules appear in the waiting room. */
  houseRules: boolean;
  module: GameModule<any, any, any, any> & { nextRound?: (s: any, rng: Rng) => any };
  config(meta: RoomMeta): unknown;
  hostOptions(meta: RoomMeta, names: string[], rand: () => number): Omit<HostOptions, 'turnMs'>;
  /** Shape-check an intent's move before the engine sees it. */
  cleanMove(raw: unknown): unknown | null;
  /** Each player's private fields at a snapshot. */
  handAt(state: any, seat: number): Record<string, Json>;
  mask(state: any): any;
  revive(raw: Json, players: number): any;
  /** Fold my private snapshot fields (and earlier private events) into my copy. */
  loadHand(state: any, seat: number, hand: Record<string, Json> | null, earlier: GameEvent[]): any;
  applyEntry(state: any, seat: number, move: unknown, events: GameEvent[]): any;
  applyPrivate(state: any, seat: number, events: GameEvent[]): any;
  checksum(state: any): string;
  view(state: any, seat: number | 'public'): any;
  createTable(root: HTMLElement, me: number, seats: SeatMeta[], isHost: boolean, hooks: NetTableHooks, humour: Humour): NetTable;
}
/* eslint-enable @typescript-eslint/no-explicit-any */

// ------------------------------------------------------------- Big Two

const bigTwoGame: NetGame = {
  id: 'bigtwo',
  title: () => L().ui.setupTitle,
  felt: 'felt-bigtwo',
  houseRules: true,
  module: { ...bigtwo.bigTwo, nextRound: bigtwo.nextRound },
  config: (meta) => ({ ...bigtwo.defaultConfig, mode: meta.mode, pokerHands: meta.pokerHands }),
  hostOptions: (meta, names, rand) => {
    const commentator = new BigTwoCommentator(names, rand);
    commentator.director.humour = meta.humour;
    return {
      previewMs: meta.previewMs,
      commentate: (events, state) => commentator.comment(events, state as bigtwo.BigTwoState),
      dwell: bigTwoDwell,
    };
  },
  cleanMove: (raw) => {
    const move = raw as { type?: unknown; cards?: unknown } | null;
    if (move && move.type === 'pass') return { type: 'pass' };
    if (move && move.type === 'play') return { type: 'play', cards: arr<string>(move.cards).filter((c) => typeof c === 'string').slice(0, 13) };
    return null;
  },
  handAt: (s: bigtwo.BigTwoState, seat) => ({
    cards: s.hands[seat]!,
    mustInclude: s.mustInclude && s.hands[seat]!.includes(s.mustInclude) ? s.mustInclude : null,
  }),
  mask: (s: bigtwo.BigTwoState) => bigtwo.mask(s, 'public'),
  revive: (raw, players) => reviveBigTwo(raw, players),
  loadHand: (s: bigtwo.BigTwoState, seat, hand) => {
    s.hands[seat] = arr<string>(hand?.cards);
    if (hand?.mustInclude) s.mustInclude = hand.mustInclude as string;
    return s;
  },
  applyEntry: (s: bigtwo.BigTwoState, seat, move) => bigtwo.applyTrusted(s, seat, move as bigtwo.BigTwoMove).state,
  applyPrivate: (s) => s,
  checksum: (s: bigtwo.BigTwoState) => bigtwo.checksum(s),
  view: (s: bigtwo.BigTwoState, seat) => bigtwo.view(s, seat),
  createTable: (root, me, seats, isHost, hooks, humour) =>
    new BigTwoTable(
      root,
      me,
      seats,
      isHost,
      {
        move: (m) => hooks.move(m),
        ready: () => hooks.ready(),
        back: () => hooks.back(),
        playAgain: () => hooks.playAgain(),
        exit: () => hooks.exit(),
      },
      { humour, sound: true, reducedMotion: false, fourColour: false },
    ) as unknown as NetTable,
};

// ------------------------------------------------------------- Lucky 7

type L7 = lucky7.LuckyState;

/** Lucky 7 state back from the database: fill in what Firebase dropped. */
function reviveLucky(raw: Json, players: number): L7 {
  const s = raw as unknown as L7;
  const rows = <T>(v: unknown, empty: T): T[][] => {
    const a = arr<unknown>(v);
    const out: T[][] = [];
    for (let i = 0; i < players; i++) {
      const r = arr<T>(a[i]);
      const row: T[] = [];
      for (let k = 0; k < lucky7.SLOTS; k++) row.push(r[k] === undefined || r[k] === null ? empty : r[k]!);
      out.push(row);
    }
    return out;
  };
  return {
    ...s,
    players,
    slots: rows<string>(s.slots, lucky7.HIDDEN),
    locks: rows<string | null>(s.locks, null),
    deck: arr<string>(s.deck),
    discard: arr<string>(s.discard),
    used: arr<string>(s.used),
    discardBy: s.discardBy ?? null,
    drawn: s.drawn ?? null,
    drawnFrom: s.drawnFrom ?? null,
    totals: s.totals ? arr<number>(s.totals) : null,
    placings: s.placings ? arr<number>(s.placings) : null,
    config: { ...lucky7.defaultConfig, ...(s.config ?? {}) },
  };
}

const MOVE_TYPES = new Set(['draw', 'swap', 'discard', 'use', 'peek']);
const int = (v: unknown): number | undefined => (Number.isInteger(v) ? (v as number) : undefined);
const targetOf = (v: unknown): lucky7.Target | null | undefined => {
  if (v === null) return null;
  if (!v || typeof v !== 'object') return undefined;
  const t = v as { seat?: unknown; slot?: unknown };
  const seat = int(t.seat);
  const slot = int(t.slot);
  return seat === undefined || slot === undefined ? undefined : { seat, slot };
};

const luckySevenGame: NetGame = {
  id: 'lucky7',
  title: () => L().l7.title,
  felt: 'felt-lucky7',
  houseRules: false,
  module: lucky7.luckySeven,
  config: () => lucky7.defaultConfig,
  hostOptions: (meta, names, rand) => {
    const commentator = new LuckySevenCommentator(names, rand);
    commentator.director.humour = meta.humour;
    const { turnMs: _turnMs, ...rest } = luckyHostOptions(meta.turnMs, commentator);
    return rest as Omit<HostOptions, 'turnMs'>;
  },
  cleanMove: (raw) => {
    const m = raw as Record<string, unknown> | null;
    if (!m || typeof m.type !== 'string' || !MOVE_TYPES.has(m.type)) return null;
    switch (m.type) {
      case 'draw':
        return m.from === 'deck' || m.from === 'discard' ? { type: 'draw', from: m.from } : null;
      case 'swap':
        return int(m.slot) === undefined ? null : { type: 'swap', slot: int(m.slot) };
      case 'discard':
        return { type: 'discard' };
      case 'peek': {
        // Firebase drops nulls: a missing target means "no target".
        const t = m.target === undefined ? null : targetOf(m.target);
        return t === undefined ? null : { type: 'peek', target: t };
      }
      default: {
        const out: Record<string, unknown> = { type: 'use' };
        if (m.mine !== undefined) out.mine = int(m.mine);
        if (m.seat !== undefined) out.seat = int(m.seat);
        if (m.target !== undefined) out.target = targetOf(m.target);
        else if (m.mine === undefined && m.seat === undefined) out.target = null; // a 9's skip, or a J
        return out;
      }
    }
  },
  handAt: () => ({}),
  mask: (s: L7) => lucky7.mask(s, 'public'),
  revive: reviveLucky,
  loadHand: (s: L7, seat, _hand, earlier) => {
    // Back mid-turn holding a card from the deck: it's in my private events.
    if (s.turn === seat && s.step === 'act' && s.drawnFrom === 'deck') {
      const drew = [...earlier].reverse().find((e) => e.type === 'drawn_card');
      if (drew) return lucky7.applyPrivate(s, seat, drew);
    }
    return s;
  },
  applyEntry: (s: L7, seat, move, events) => lucky7.applyPublic(s, seat, move as lucky7.LuckyMove, events),
  applyPrivate: (s: L7, seat, events) => events.reduce((acc, e) => lucky7.applyPrivate(acc, seat, e), s),
  checksum: (s: L7) => lucky7.checksum(s),
  view: (s: L7, seat) => lucky7.view(s, seat),
  createTable: (root, me, seats, isHost, hooks, humour) =>
    new LuckySevenTable(
      root,
      me,
      seats,
      isHost,
      { move: (m) => hooks.move(m), back: () => hooks.back(), playAgain: () => hooks.playAgain(), exit: () => hooks.exit() },
      { humour, sound: true, reducedMotion: false },
    ) as unknown as NetTable,
};

export const NET_GAMES: Record<OnlineGameId, NetGame> = { bigtwo: bigTwoGame, lucky7: luckySevenGame };

export const netGame = (id: unknown): NetGame => NET_GAMES[id === 'lucky7' ? 'lucky7' : 'bigtwo'];
