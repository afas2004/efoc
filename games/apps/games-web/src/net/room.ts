// One online Big Two table. Every phone runs this; the phone whose uid is
// meta.hostUid also runs the referee (HostCore + HostRelay).
//
//   waiting  -> the waiting room: members join, Ready, host adds bots, Start
//   playing  -> every phone follows the log; the host takes intents
//   host gone (offline and silent for migrateAfterMs, spec: 60 s)
//            -> the next online seated human claims meta/hostUid, loads
//               hostState and carries on from the same log position
// Anyone who arrives after Start watches as a spectator.

import { bigtwo, type GameEvent } from '@efoc/engine';
import { inApp, send } from '../bridge';
import { BigTwoCommentator, dwellMs } from '../games/bigtwo/commentary';
import { BigTwoTable } from '../games/bigtwo/table';
import { HostCore, type HostSnapshot, type SeatInfo } from '../host/hostCore';
import { L, fmt } from '../strings';
import { arr, Follower, reviveState, type FollowUpdate } from './follower';
import { HostRelay } from './hostRelay';
import { lobbySeats, renderLobby } from './lobby';
import { HEARTBEAT_MS, P, type Member, type RoomMeta, type SeatEntry } from './protocol';
import type { Json, RoomStore } from './store';

export interface Me {
  uid: string;
  name: string;
  avatar: string;
}

export interface CreateRoom {
  groupId: string;
  /** The group's member uids (copied into rooms/{id}/allowed). */
  allowed: string[];
  turnMs?: number;
  migrateAfterMs?: number;
  previewMs?: number;
}

export interface OnlineOptions {
  /** Play my seat with a bot (tests). */
  autopilot?: boolean;
  onExit(): void;
}

const BOT_NAMES: [string, string, SeatEntry['bot']][] = [
  ['Speedy', '🐇', { level: 'easy', personality: 'speedy' }],
  ['Grandmaster', '🦉', { level: 'normal', personality: 'grandmaster' }],
  ['Bluffer', '🦊', { level: 'normal', personality: 'bluffer' }],
  ['Slowpoke', '🐢', { level: 'easy', personality: 'slowpoke' }],
  ['Tiger', '🐯', { level: 'normal', personality: 'grandmaster' }],
  ['Panda', '🐼', { level: 'normal', personality: 'speedy' }],
  ['Kancil', '🦌', { level: 'easy', personality: 'bluffer' }],
];

export async function createRoom(store: RoomStore, room: string, me: Me, c: CreateRoom): Promise<void> {
  const allowed: Record<string, Json> = {};
  for (const uid of new Set([...c.allowed, me.uid])) allowed[uid] = true;
  const meta: RoomMeta = {
    gameId: 'bigtwo',
    groupId: c.groupId,
    hostUid: me.uid,
    status: 'waiting',
    mode: 'standard',
    pokerHands: true,
    humour: 'spicy',
    bots: [],
    createdAt: store.now(),
    turnMs: c.turnMs ?? 20_000,
    migrateAfterMs: c.migrateAfterMs ?? 60_000,
    previewMs: c.previewMs ?? 15_000,
  };
  // meta first in the same write, so the allowed rule sees this uid as host.
  await store.update({ [P.meta(room)]: meta as unknown as Json, [P.allowed(room)]: allowed });
}

export class OnlineGame {
  private meta: RoomMeta | null = null;
  private members: Record<string, Member> = {};
  private presence: Record<string, { online?: boolean; lastSeen?: number }> = {};
  private table: BigTwoTable | null = null;
  private follower: Follower | null = null;
  private host: HostCore<bigtwo.BigTwoConfig, bigtwo.BigTwoState, bigtwo.BigTwoMove, bigtwo.BigTwoView> | null = null;
  private relay: HostRelay | null = null;
  private seats: SeatEntry[] = [];
  private mySeat: number | 'public' = 'public';
  private lastN = -1;
  private lastView: bigtwo.BigTwoView | null = null;
  private timers: number[] = [];
  private claiming = false;
  private autoTimer = 0;

  constructor(
    private readonly store: RoomStore,
    readonly room: string,
    private readonly me: Me,
    private readonly root: HTMLElement,
    private readonly opts: OnlineOptions,
  ) {}

  /** Join (or rejoin) the room and keep presence fresh. */
  async start(): Promise<void> {
    const p = P.presenceOf(this.room, this.me.uid);
    const beat = (): void => void this.store.set(p, { online: true, lastSeen: this.store.now() });
    beat();
    this.store.onDisconnect(p, { online: false, lastSeen: this.store.now() });
    this.timers.push(window.setInterval(beat, HEARTBEAT_MS));
    this.timers.push(window.setInterval(() => this.checkHost(), 1000));

    const meta = (await this.store.get(P.meta(this.room))) as RoomMeta | null;
    if (meta && meta.status === 'waiting') {
      const existing = (await this.store.get(P.member(this.room, this.me.uid))) as Member | null;
      if (!existing) await this.store.set(P.member(this.room, this.me.uid), { name: this.me.name, avatar: this.me.avatar, ready: false, joinedAt: this.store.now() });
    } else if (meta && !arr<SeatEntry>(meta.seats).some((s) => s.uid === this.me.uid)) {
      await this.store.set(P.spectator(this.room, this.me.uid), { name: this.me.name, avatar: this.me.avatar });
    }
    this.store.watch(P.members(this.room), (v) => {
      this.members = (v as unknown as Record<string, Member>) ?? {};
      this.refreshLobby();
    });
    this.store.watch(P.presence(this.room), (v) => {
      this.presence = (v as Record<string, { online?: boolean; lastSeen?: number }>) ?? {};
      this.refreshLobby();
    });
    this.store.watch(P.meta(this.room), (v) => this.onMeta(v as RoomMeta | null));
  }

  stop(): void {
    this.timers.forEach((t) => window.clearInterval(t));
    this.follower?.stop();
    this.relay?.stop();
    this.host?.stop();
  }

  // --------------------------------------------------------------- meta

  private onMeta(meta: RoomMeta | null): void {
    if (!meta) return;
    meta.bots = arr<SeatEntry>(meta.bots);
    const prevHost = this.meta?.hostUid;
    this.meta = meta;
    if (meta.status === 'waiting') {
      this.refreshLobby();
      return;
    }
    if (!this.table) this.startTable(meta);
    if (meta.hostUid === this.me.uid && !this.host) void this.becomeHost(prevHost !== undefined && prevHost !== this.me.uid);
    if (this.table) this.table.isHost = meta.hostUid === this.me.uid;
  }

  private online(uid: string | null): boolean {
    if (!uid) return false;
    const p = this.presence[uid];
    return !!p?.online && this.store.now() - (p.lastSeen ?? 0) < HEARTBEAT_MS * 3;
  }

  private refreshLobby(): void {
    const m = this.meta;
    if (!m || m.status !== 'waiting') return;
    const online = new Set(Object.keys(this.members).filter((u) => this.online(u)));
    renderLobby(this.root, { meta: m, members: this.members, online, me: this.me.uid }, {
      setReady: (ready) => void this.store.set(`${P.member(this.room, this.me.uid)}/ready`, ready),
      addBot: () => {
        const used = new Set(m.bots.map((b) => b.name));
        const pick = BOT_NAMES.find(([n]) => !used.has(n)) ?? BOT_NAMES[0]!;
        void this.store.set(`${P.meta(this.room)}/bots`, [...m.bots, { uid: null, name: pick[0], avatar: pick[1], bot: pick[2] }] as unknown as Json);
      },
      removeBot: (i) => void this.store.set(`${P.meta(this.room)}/bots`, m.bots.filter((_, k) => k !== i) as unknown as Json),
      setRule: (patch) => void this.store.update(Object.fromEntries(Object.entries(patch).map(([k, v]) => [`${P.meta(this.room)}/${k}`, v as Json]))),
      start: () => {
        const seats = lobbySeats(m, this.members);
        if (seats.length < 2) return;
        void this.store.update({ [`${P.meta(this.room)}/seats`]: seats as unknown as Json, [`${P.meta(this.room)}/status`]: 'playing' });
      },
    });
  }

  // -------------------------------------------------------------- table

  private config(meta: RoomMeta): bigtwo.BigTwoConfig {
    return { ...bigtwo.defaultConfig, mode: meta.mode, pokerHands: meta.pokerHands };
  }

  private startTable(meta: RoomMeta): void {
    this.seats = arr<SeatEntry>(meta.seats);
    const seat = this.seats.findIndex((s) => s.uid === this.me.uid);
    this.mySeat = seat >= 0 ? seat : 'public';
    const me = seat >= 0 ? seat : 0;
    this.table = new BigTwoTable(
      this.root,
      me,
      this.seats.map((s) => ({ name: s.name, avatar: s.avatar, bot: !!s.bot })),
      meta.hostUid === this.me.uid,
      {
        move: (m) => void this.intent(m),
        ready: () => void this.intent({ type: 'ready' }),
        back: () => void this.intent({ type: 'back' }),
        playAgain: () => this.host?.playAgain(),
        exit: () => {
          this.stop();
          this.opts.onExit();
        },
      },
      { humour: meta.humour, sound: true, reducedMotion: false, fourColour: false },
    );
    this.root.classList.toggle('spectator', this.mySeat === 'public');
    this.root.dataset.turnMs = String(meta.turnMs);
    this.follower = new Follower(this.store, this.room, this.seats.length, this.mySeat, (u) => this.onFollow(u), (r) => {
      this.table?.reject(r);
      if (this.opts.autopilot) this.autopilot(); // try again, like a person would
    });
    this.follower.start();
    (window as unknown as { __efoc: unknown }).__efoc = this.debug();
  }

  private onFollow(u: FollowUpdate): void {
    this.lastN = u.n;
    this.lastView = u.view;
    this.table?.update(u.view, u.events as GameEvent[], { deadline: u.entry.deadline, afk: u.entry.afk, totals: u.entry.totals });
    if (u.events.some((e) => e.type === 'host_changed')) {
      const name = String(u.events.find((e) => e.type === 'host_changed')!.name ?? '');
      this.table?.notice(fmt(L().ui.hostChanged, { name }));
    }
    if (this.opts.autopilot) this.autopilot();
  }

  /** Tests: play my own seat with the Normal bot, through intents like a person. */
  private autopilot(): void {
    window.clearTimeout(this.autoTimer);
    const v = this.lastView;
    if (!v || this.mySeat === 'public' || v.phase !== 'play') return;
    this.autoTimer = window.setTimeout(() => {
      const view = this.lastView;
      if (!view || view.turn !== this.mySeat || view.phase !== 'play') return;
      const move = bigtwo.bot(view, 'normal', { next: Math.random, int: (n) => Math.floor(Math.random() * n), shuffle: (a) => [...a] });
      void this.intent(move);
    }, 250 + Math.random() * 250);
  }

  private async intent(move: unknown): Promise<void> {
    if (this.mySeat === 'public') return;
    await this.store.push(P.intents(this.room), { uid: this.me.uid, n: this.lastN, move: move as Json });
  }

  // --------------------------------------------------------------- host

  private seatInfo(): SeatInfo[] {
    return this.seats.map((s) => ({ name: s.name, avatar: s.avatar, bot: s.bot }));
  }

  private async becomeHost(migrated: boolean): Promise<void> {
    const meta = this.meta!;
    let seed = Math.floor(Math.random() * 2 ** 31);
    const commentator = new BigTwoCommentator(this.seats.map((s) => s.name), () => {
      seed = (Math.imul(seed, 1103515245) + 12345) >>> 0;
      return seed / 2 ** 32;
    });
    commentator.director.humour = meta.humour;
    const host = new HostCore({ ...bigtwo.bigTwo, nextRound: bigtwo.nextRound }, this.seatInfo(), this.config(meta), {
      turnMs: meta.turnMs,
      previewMs: meta.previewMs,
      commentate: (events, state) => commentator.comment(events, state as bigtwo.BigTwoState),
      dwell: dwellMs,
    });
    this.host = host;
    this.relay = new HostRelay(this.store, this.room, host, this.seats);
    const saved = (await this.store.get(P.hostState(this.room))) as unknown as HostSnapshot<Json> | null;
    if (saved) {
      const restored: HostSnapshot<bigtwo.BigTwoState> = {
        ...saved,
        state: reviveState(saved.state, this.seats.length),
        totals: arr<number>(saved.totals),
        stamps: arr<number>(saved.stamps),
        doubled: arr<boolean>(saved.doubled),
        afk: arr<boolean>(saved.afk),
      };
      host.restore(restored, migrated ? [{ type: 'host_changed', uid: this.me.uid, name: this.me.name }] : []);
      // Seats whose phones are gone (the old host's, at least) are played
      // by a bot until their owner taps "I'm back".
      for (let i = 0; i < this.seats.length; i++) {
        const s = this.seats[i]!;
        if (s.uid && s.uid !== this.me.uid && !this.online(s.uid)) host.setAfk(i, true);
      }
    } else {
      host.start();
    }
    this.relay.listen();
    if (this.table) this.table.isHost = true;
    (window as unknown as { __efoc: unknown }).__efoc = this.debug();
  }

  /** Host migration: take over if the host has been silent too long and I'm next in line. */
  private checkHost(): void {
    const m = this.meta;
    if (!m || m.status !== 'playing' || m.hostUid === this.me.uid || this.claiming || this.mySeat === 'public') return;
    const hp = this.presence[m.hostUid];
    const silentFor = this.store.now() - (hp?.lastSeen ?? 0);
    if (silentFor < m.migrateAfterMs) return;
    const hostSeat = this.seats.findIndex((s) => s.uid === m.hostUid);
    for (let k = 1; k <= this.seats.length; k++) {
      const s = this.seats[(Math.max(hostSeat, 0) + k) % this.seats.length]!;
      if (!s.uid || !this.online(s.uid)) continue;
      if (s.uid !== this.me.uid) return; // someone earlier in line will take over
      this.claiming = true;
      void this.store.set(`${P.meta(this.room)}/hostUid`, this.me.uid).finally(() => (this.claiming = false));
      return;
    }
  }

  // -------------------------------------------------------------- tests

  private debug(): unknown {
    return {
      table: this.table,
      feel: this.table?.feel,
      host: this.host,
      relay: this.relay,
      follower: this.follower,
      room: this,
    };
  }

  /** Test hook: is this phone the host, and how far has it followed the log? */
  status(): { host: boolean; n: number; drift: number; seat: number | 'public'; phase: string | null } {
    return {
      host: !!this.host,
      n: this.lastN,
      drift: this.follower?.drift ?? 0,
      seat: this.mySeat,
      phase: this.lastView?.phase ?? null,
    };
  }
}

export function exitApp(): void {
  if (inApp()) send({ t: 'exit' });
  else location.reload();
}
