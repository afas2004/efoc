// RoomStore inside the EFOC app. Every call becomes a bridge message
// {t:'db', ...} that Flutter (GameSession) runs on Firebase Realtime
// Database, limited to this room's paths. The page never holds a Firebase
// token; the security rules decide every read and write.
//
//   page -> app   {t:'db', id, op:'get', path}
//                 {t:'db', id, op:'set', path, value}
//                 {t:'db', id, op:'update', values}
//                 {t:'db', id, op:'push', path, value}
//                 {t:'db', id, op:'onDisconnect', path, value}
//                 {t:'db', id, op:'watch' | 'watchChildren', path}   id names the subscription
//                 {t:'db', id, op:'unwatch'}
//   app -> page   {t:'dbResult', id, ok, value?, error?}   answer to get/set/update/push/onDisconnect
//                 {t:'dbValue', id, value}                 a watch fired
//                 {t:'dbChild', id, key, value}            a watchChildren child arrived
//                 {t:'dbClock', offset}                    server time minus local time, in ms
//
// TIMESTAMP ({'.sv': 'timestamp'}) is Firebase's server-time placeholder;
// Flutter passes it through unchanged.

import { onMessage, send, type ToGame } from '../bridge';
import type { Json, RoomStore, Unsubscribe } from './store';

type DbReply = Extract<ToGame, { t: 'dbResult' }>;

export class BridgeStore implements RoomStore {
  private nextId = 1;
  private offset = 0;
  private pending = new Map<number, { resolve: (r: DbReply) => void }>();
  private values = new Map<number, (value: Json) => void>();
  private children = new Map<number, { seen: Set<string>; cb: (key: string, value: Json) => void }>();

  constructor(readonly uid: string, clockOffset = 0) {
    this.offset = clockOffset;
    onMessage((m) => this.receive(m));
  }

  now(): number {
    return Date.now() + this.offset;
  }

  private receive(m: ToGame): void {
    switch (m.t) {
      case 'dbResult': {
        const p = this.pending.get(m.id);
        if (!p) return;
        this.pending.delete(m.id);
        p.resolve(m);
        return;
      }
      case 'dbValue':
        this.values.get(m.id)?.(m.value as Json);
        return;
      case 'dbChild': {
        const c = this.children.get(m.id);
        if (!c || c.seen.has(m.key)) return;
        c.seen.add(m.key);
        c.cb(m.key, m.value as Json);
        return;
      }
      case 'dbClock':
        if (typeof m.offset === 'number' && Number.isFinite(m.offset)) this.offset = m.offset;
        return;
      default:
    }
  }

  private call(msg: Record<string, unknown>): Promise<Json> {
    const id = this.nextId++;
    return new Promise<Json>((resolve, reject) => {
      this.pending.set(id, {
        resolve: (r) => (r.ok ? resolve((r.value ?? null) as Json) : reject(new Error(r.error ?? 'database error'))),
      });
      send({ t: 'db', id, ...msg } as never);
    });
  }

  get(path: string): Promise<Json> {
    return this.call({ op: 'get', path });
  }

  watch(path: string, cb: (value: Json) => void): Unsubscribe {
    const id = this.nextId++;
    this.values.set(id, cb);
    send({ t: 'db', id, op: 'watch', path });
    return () => this.unwatch(id);
  }

  watchChildren(path: string, cb: (key: string, value: Json) => void): Unsubscribe {
    const id = this.nextId++;
    this.children.set(id, { seen: new Set(), cb });
    send({ t: 'db', id, op: 'watchChildren', path });
    return () => this.unwatch(id);
  }

  private unwatch(id: number): void {
    if (!this.values.delete(id) && !this.children.delete(id)) return;
    send({ t: 'db', id, op: 'unwatch' });
  }

  async set(path: string, value: Json): Promise<void> {
    await this.call({ op: 'set', path, value });
  }

  async update(values: Record<string, Json>): Promise<void> {
    await this.call({ op: 'update', values });
  }

  async push(path: string, value: Json): Promise<string> {
    return String(await this.call({ op: 'push', path, value }));
  }

  onDisconnect(path: string, value: Json): void {
    void this.call({ op: 'onDisconnect', path, value }).catch(() => undefined);
  }
}
