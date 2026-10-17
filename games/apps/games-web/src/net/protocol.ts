// Room data model (spec "Realtime Database data model"), as the page uses it.
//
//   rooms/{id}/allowed/{uid}    true                      host writes once, at creation
//   rooms/{id}/meta             RoomMeta                  host (or a migrating member: hostUid only)
//   rooms/{id}/members/{uid}    Member                    that uid, if allowed
//   rooms/{id}/spectators/{uid} {name, avatar, slot}      that uid, if allowed, with a slot
//   rooms/{id}/spectatorSlots/{0-7} uid                   at most 8 spectators
//   rooms/{id}/intents/{push}   Intent                    members, own uid, new entries only
//   rooms/{id}/log/{000123}     Entry                     host, append only
//   rooms/{id}/snapshot         {n, state}                host: masked public state at round start and every 20 entries
//   rooms/{id}/hands/{uid}      {n, cards, mustInclude?, rejected?}   host; only that uid reads
//   rooms/{id}/hostState        HostSnapshot              host only
//   rooms/{id}/results          final standings           host
//   presence/{id}/{uid}         {online, lastSeen}        that uid

import type { Json } from './store';

export const SNAPSHOT_EVERY = 20;
export const HEARTBEAT_MS = 2000;

export type SeatBot = { level: 'easy' | 'normal'; personality: 'speedy' | 'slowpoke' | 'bluffer' | 'grandmaster' };

export interface SeatEntry {
  uid: string | null;
  name: string;
  avatar: string;
  bot: SeatBot | null;
}

export interface RoomMeta {
  gameId: 'bigtwo';
  groupId: string;
  hostUid: string;
  /** 'closed': the host cancelled the table from the waiting room. */
  status: 'waiting' | 'playing' | 'closed';
  /** House rules, chosen by the host in the waiting room. */
  mode: 'standard' | 'fightTillTheEnd';
  pokerHands: boolean;
  humour: 'off' | 'mild' | 'spicy';
  /** Bots the host added in the waiting room. */
  bots: SeatEntry[];
  /** Fixed at Start: who sits where. */
  seats?: SeatEntry[];
  createdAt: number;
  /** Turn time in ms and seconds before a silent host is replaced (spec: 60 s). */
  turnMs: number;
  migrateAfterMs: number;
  previewMs: number;
}

export interface Member {
  name: string;
  avatar: string;
  ready: boolean;
  joinedAt: number;
}

export interface Intent {
  uid: string;
  /** The last log entry the sender had applied. */
  n: number;
  move: Json;
}

export interface Entry {
  seat: number | null;
  move: Json;
  events: Json[];
  deadline: number | null;
  afk: boolean[];
  totals: number[];
  /** Checksum of the public state after this entry, every 20 entries. */
  sum?: string;
}

export const logKey = (n: number): string => String(n).padStart(6, '0');

export const P = {
  room: (id: string) => `rooms/${id}`,
  allowed: (id: string) => `rooms/${id}/allowed`,
  meta: (id: string) => `rooms/${id}/meta`,
  members: (id: string) => `rooms/${id}/members`,
  member: (id: string, uid: string) => `rooms/${id}/members/${uid}`,
  spectator: (id: string, uid: string) => `rooms/${id}/spectators/${uid}`,
  /** 8 numbered slots cap the spectators (rules can't count children). */
  spectatorSlots: (id: string) => `rooms/${id}/spectatorSlots`,
  intents: (id: string) => `rooms/${id}/intents`,
  log: (id: string) => `rooms/${id}/log`,
  entry: (id: string, n: number) => `rooms/${id}/log/${logKey(n)}`,
  snapshot: (id: string) => `rooms/${id}/snapshot`,
  hand: (id: string, uid: string) => `rooms/${id}/hands/${uid}`,
  hostState: (id: string) => `rooms/${id}/hostState`,
  results: (id: string) => `rooms/${id}/results`,
  presence: (id: string) => `presence/${id}`,
  presenceOf: (id: string, uid: string) => `presence/${id}/${uid}`,
};

/** Non-game intents the host handles itself. */
export type ControlMove = { type: 'ready' } | { type: 'back' };

export const isControl = (m: unknown): m is ControlMove =>
  !!m && typeof m === 'object' && ((m as { type?: unknown }).type === 'ready' || (m as { type?: unknown }).type === 'back');
