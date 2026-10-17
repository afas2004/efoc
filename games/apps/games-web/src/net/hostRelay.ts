// The host's link to the room: intents in, log entries out. Each accepted
// move becomes one multi-path write: the log entry, the host's full state
// (for migration), and at a new deal or every 20 entries a masked public
// snapshot plus each player's hand. Rejections go to that player only.

import { bigtwo } from '@efoc/engine';
import type { HostCore, LogEntry } from '../host/hostCore';
import { arr } from './follower';
import { P, SNAPSHOT_EVERY, isControl, type Entry, type Intent, type SeatEntry } from './protocol';
import type { Json, RoomStore, Unsubscribe } from './store';

type Host = HostCore<bigtwo.BigTwoConfig, bigtwo.BigTwoState, bigtwo.BigTwoMove, bigtwo.BigTwoView>;

export class HostRelay {
  private subs: Unsubscribe[] = [];
  /** Writes go out one at a time, in log order. */
  private chain: Promise<void> = Promise.resolve();
  writes = 0;

  constructor(
    private readonly store: RoomStore,
    private readonly room: string,
    private readonly host: Host,
    private readonly seats: SeatEntry[],
  ) {
    host.onEntry((e) => this.publish(e));
  }

  /** Starts taking intents. Call after the host has started or restored. */
  listen(): void {
    this.subs.push(
      this.store.watchChildren(P.intents(this.room), (key, value) => {
        this.chain = this.chain.then(() => this.handle(key, value));
      }),
    );
  }

  stop(): void {
    this.subs.forEach((u) => u());
    this.subs = [];
  }

  private async handle(key: string, raw: Json): Promise<void> {
    const intent = raw as unknown as Intent | null;
    const done: Record<string, Json> = { [`${P.intents(this.room)}/${key}`]: null };
    if (!intent) return;
    const seat = this.seats.findIndex((s) => s.uid === intent.uid);
    if (seat < 0) {
      await this.store.update(done);
      return;
    }
    // Shape-check before the engine sees it (spec: Security).
    const move = intent.move as { type?: unknown; cards?: unknown } | null;
    if (isControl(move)) {
      if (move.type === 'ready') this.host.ready(seat);
      else this.host.back(seat);
      await this.store.update(done);
      return;
    }
    const clean: bigtwo.BigTwoMove | null =
      move && move.type === 'pass'
        ? { type: 'pass' }
        : move && move.type === 'play'
          ? { type: 'play', cards: arr<string>(move.cards).filter((c) => typeof c === 'string').slice(0, 13) }
          : null;
    const reason = clean ? this.host.submit(seat, clean, typeof intent.n === 'number' ? intent.n : undefined) : 'Bad move';
    if (reason) {
      done[`${P.hand(this.room, intent.uid)}/rejected`] = { n: intent.n, reason, at: this.store.now() };
    }
    await this.store.update(done);
  }

  private publish(e: LogEntry<bigtwo.BigTwoMove>): void {
    const s = this.host.state;
    const entry: Entry = {
      seat: e.seat,
      move: e.move as unknown as Json,
      events: e.events as unknown as Json[],
      deadline: e.deadline,
      afk: this.host.afk.slice(),
      totals: this.host.totals.slice(),
    };
    const updates: Record<string, Json> = {};
    const newDeal = e.events.some((x) => x.type === 'round_started');
    const snap = newDeal || e.n % SNAPSHOT_EVERY === 0;
    if (e.n % SNAPSHOT_EVERY === 0) entry.sum = bigtwo.checksum(s);
    if (snap) {
      updates[P.snapshot(this.room)] = { n: e.n, state: bigtwo.mask(s, 'public') as unknown as Json };
      this.seats.forEach((seat, i) => {
        if (!seat.uid) return;
        const base = P.hand(this.room, seat.uid);
        updates[`${base}/n`] = e.n;
        updates[`${base}/cards`] = s.hands[i]!;
        updates[`${base}/mustInclude`] = s.mustInclude && s.hands[i]!.includes(s.mustInclude) ? s.mustInclude : null;
      });
    }
    updates[P.entry(this.room, e.n)] = entry as unknown as Json;
    updates[P.hostState(this.room)] = this.host.save() as unknown as Json;
    const result = this.host.matchOver ? e.events.find((x) => x.type === 'match_points') : null;
    if (result) updates[P.results(this.room)] = { at: this.store.now(), ...(result as unknown as Record<string, Json>) };
    this.writes++;
    this.chain = this.chain.then(() => this.store.update(updates));
  }
}
