// Every phone (spectators too) follows the room: it loads the latest
// snapshot, then applies each log entry in order with the engine's public
// rules, on a masked copy of the table that holds only its own hand. Every
// 20 entries it checks the host's checksum; on a mismatch it reloads the
// snapshot. Joining late or reconnecting is the same path.

import { bigtwo, type GameEvent } from '@efoc/engine';
import { P, type Entry } from './protocol';
import type { Json, RoomStore, Unsubscribe } from './store';

type State = bigtwo.BigTwoState;

/** Realtime Database stores arrays as objects and drops empty ones; put them back. */
/**
 * A list back from the database. Firebase drops empty lists and nulls, and
 * returns a list with many gaps as an object keyed "0", "3", ... — so every
 * value keeps its index (a seat's empty hand must not shift the next seat's
 * hand into its place). Gaps come back as undefined.
 */
export function arr<T = Json>(v: unknown): T[] {
  if (Array.isArray(v)) return v as T[];
  if (v && typeof v === 'object') {
    const out: T[] = [];
    for (const [k, x] of Object.entries(v as Record<string, T>)) {
      const i = Number(k);
      if (Number.isInteger(i) && i >= 0 && i < 10_000) out[i] = x;
    }
    return Array.from(out);
  }
  return [];
}

export function reviveState(raw: Json, players: number): State {
  const s = raw as unknown as State;
  const fill = <T>(v: unknown, n: number, empty: () => T): T[] => {
    const a = arr<T>(v);
    for (let i = 0; i < n; i++) if (a[i] === undefined || a[i] === null) a[i] = empty();
    return a;
  };
  return {
    ...s,
    players,
    hands: fill<Json>(s.hands, players, () => []).map((h) => arr<string>(h)),
    out: arr<string>(s.out),
    pile: arr<string>(s.pile),
    passed: fill<boolean>(s.passed, players, () => false).map(Boolean),
    finished: arr<number>(s.finished),
    onTwo: arr<number>(s.onTwo),
    scores: fill<number>(s.scores, players, () => 0),
    roundPoints: s.roundPoints ? arr<number>(s.roundPoints) : null,
    placings: s.placings ? arr<number>(s.placings) : null,
    lead: s.lead ? { ...s.lead, cards: arr<string>(s.lead.cards), combo: { ...s.lead.combo, key: arr<number>(s.lead.combo.key) } } : null,
    lastPlayer: s.lastPlayer ?? null,
    mustInclude: s.mustInclude ?? null,
    config: s.config,
  };
}

export function reviveEntry(raw: Json): Entry {
  const e = raw as unknown as Entry;
  const move = e.move as { type?: string; cards?: unknown } | null;
  return {
    ...e,
    seat: e.seat ?? null,
    move: (move ? (move.cards !== undefined || move.type === 'play' ? { ...move, cards: arr(move.cards) } : move) : null) as Json,
    events: arr<Json>(e.events).map((ev) => {
      const o = { ...(ev as Record<string, Json>) };
      for (const k of ['cards', 'points', 'placings', 'totals', 'doubled', 'passed', 'scores']) if (k in o) o[k] = arr(o[k]);
      return o;
    }),
    afk: arr<boolean>(e.afk),
    totals: arr<number>(e.totals),
    deadline: e.deadline ?? null,
  };
}

export interface FollowUpdate {
  n: number;
  state: State;
  view: bigtwo.BigTwoView;
  events: GameEvent[];
  entry: Entry;
}

export class Follower {
  state: State | null = null;
  n = -1;
  drift = 0;
  private queue: [number, Json][] = [];
  private busy = false;
  private subs: Unsubscribe[] = [];
  private lastReject = 0;

  constructor(
    private readonly store: RoomStore,
    private readonly room: string,
    private readonly players: number,
    /** My seat, or 'public' for a spectator. */
    private readonly seat: number | 'public',
    private readonly onUpdate: (u: FollowUpdate) => void,
    private readonly onReject: (reason: string) => void,
  ) {}

  start(): void {
    this.subs.push(
      this.store.watchChildren(P.log(this.room), (key, value) => {
        this.queue.push([Number(key), value]);
        void this.drain();
      }),
    );
    if (this.seat !== 'public') {
      this.subs.push(
        this.store.watch(`${P.hand(this.room, this.store.uid)}/rejected`, (v) => {
          const r = v as { at?: number; reason?: string } | null;
          if (!r?.at || r.at <= this.lastReject) return;
          this.lastReject = r.at;
          this.onReject(r.reason ?? 'Rejected');
        }),
      );
    }
  }

  stop(): void {
    this.subs.forEach((u) => u());
    this.subs = [];
  }

  /**
   * Loads the latest snapshot and my hand at it, and jumps to it. `atLeast`
   * waits (briefly) until the snapshot has caught up with that log entry.
   */
  private async load(atLeast = -1): Promise<void> {
    for (let tries = 0; tries < 60; tries++) {
      const snap = (await this.store.get(P.snapshot(this.room))) as { n: number; state: Json } | null;
      const hand =
        this.seat === 'public' ? null : ((await this.store.get(P.hand(this.room, this.store.uid))) as { n?: number; cards?: Json; mustInclude?: string } | null);
      const fresh = snap && snap.n >= atLeast && (this.seat === 'public' || hand?.n === snap.n);
      if (fresh) {
        const state = reviveState(snap.state, this.players);
        if (this.seat !== 'public') {
          state.hands[this.seat] = arr<string>(hand?.cards);
          if (hand?.mustInclude) state.mustInclude = hand.mustInclude;
        }
        this.state = state;
        this.n = snap.n;
        return;
      }
      await new Promise((r) => setTimeout(r, 50));
    }
  }

  private async drain(): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    try {
      this.queue.sort((a, b) => a[0] - b[0]);
      while (this.queue.length > 0) {
        const [n, raw] = this.queue.shift()!;
        if (n <= this.n) continue;
        const entry = reviveEntry(raw);
        const newDeal = entry.events.some((e) => (e as { type?: string }).type === 'round_started');
        if (!this.state || newDeal) {
          await this.load(newDeal ? n : -1);
          if (!this.state) continue;
          if (n < this.n) continue; // the snapshot is already past this entry
          if (n === this.n) {
            this.emit(n, entry);
            continue;
          }
        }
        if (entry.seat !== null && entry.move) {
          this.state = bigtwo.applyTrusted(this.state, entry.seat, entry.move as bigtwo.BigTwoMove).state;
        }
        this.n = n;
        if (entry.sum && bigtwo.checksum(this.state) !== entry.sum) {
          // Drifted from the host: reload the snapshot written with this checksum.
          this.drift++;
          await this.load(n);
        }
        this.emit(n, entry);
      }
    } finally {
      this.busy = false;
    }
  }

  private emit(n: number, entry: Entry): void {
    const s = this.state!;
    const view = bigtwo.view(s, this.seat === 'public' ? 'public' : this.seat);
    this.onUpdate({ n, state: s, view, events: entry.events as unknown as GameEvent[], entry });
  }
}
