// One online Big Two table. Every phone runs this; the phone whose uid is
// meta.hostUid also runs the referee (HostCore + HostRelay).
//
//   waiting  -> the waiting room: members join, Ready, host adds bots, Start
//   playing  -> every phone follows the log; the host takes intents
//   host gone (offline and silent for migrateAfterMs, spec: 60 s)
//            -> the next online seated human claims meta/hostUid, loads
//               hostState and carries on from the same log position
// Anyone who arrives after Start watches as a spectator.

import { createRng, type GameEvent } from '@efoc/engine';
import { inApp, send } from '../bridge';
import { HostCore, type HostSnapshot, type SeatInfo } from '../host/hostCore';
import { L, fmt } from '../strings';
import { arr, Follower, type FollowUpdate } from './follower';
import { HostRelay } from './hostRelay';
import { lobbySeats, renderLobby } from './lobby';
import { netGame, type Conn, type NetGame, type NetTable, type OnlineGameId } from './netGame';
import { HEARTBEAT_MS, P, type Member, type RoomMeta, type SeatEntry } from './protocol';
import { TIMESTAMP, type Json, type RoomStore } from './store';

export interface Me {
  uid: string;
  name: string;
  avatar: string;
}

export interface CreateRoom {
  gameId?: OnlineGameId;
  groupId: string;
  /** The group's member uids (copied into rooms/{id}/allowed). */
  allowed: string[];
  turnMs?: number;
  migrateAfterMs?: number;
  previewMs?: number;
}

export interface OnlineOptions {
  /** Which game this page is (until the room's meta says). */
  gameId?: OnlineGameId;
  /** Play my seat with a bot (tests). */
  autopilot?: boolean;
  /** Multiplies bot thinking time when this phone referees (tests). */
  botSpeed?: number;
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
    gameId: c.gameId ?? 'bigtwo',
    groupId: c.groupId,
    hostUid: me.uid,
    status: 'waiting',
    mode: 'standard',
    pokerHands: true,
    humour: 'spicy',
    bots: [],
    createdAt: store.now(),
    turnMs: c.turnMs ?? (c.gameId === 'zombie' ? 15_000 : 20_000),
    migrateAfterMs: c.migrateAfterMs ?? 60_000,
    previewMs: c.previewMs ?? 15_000,
  };
  // meta first in the same write, so the allowed rule sees this uid as host.
  await store.update({ [P.meta(room)]: meta as unknown as Json, [P.allowed(room)]: allowed });
}

export class OnlineGame {
  private meta: RoomMeta | null = null;
  private members: Record<string, Member> = {};
  private presence: Record<string, { online?: boolean; lastSeen?: number; left?: boolean }> = {};
  private connKey = '';
  /** When the last match's results were written: the key for "I'm in". */
  private resultsAt = 0;
  private rematchKey = '';
  private table: NetTable | null = null;
  private follower: Follower | null = null;
  /* eslint-disable-next-line @typescript-eslint/no-explicit-any */
  private host: HostCore<any, any, any, any> | null = null;
  private relay: HostRelay | null = null;
  private seats: SeatEntry[] = [];
  private mySeat: number | 'public' = 'public';
  private lastN = -1;
  /* eslint-disable-next-line @typescript-eslint/no-explicit-any */
  private lastView: any = null;
  private timers: number[] = [];
  private claiming = false;
  private autoTimer = 0;

  constructor(
    private readonly store: RoomStore,
    readonly room: string,
    private readonly me: Me,
    private readonly root: HTMLElement,
    private readonly opts: OnlineOptions,
  ) {
    this.game = netGame(opts.gameId);
  }

  private game: NetGame;

  /** Join (or rejoin) the room and keep presence fresh. */
  async start(): Promise<void> {
    const p = P.presenceOf(this.room, this.me.uid);
    const beat = (): void => void this.store.set(p, { online: true, lastSeen: this.store.now() });
    beat();
    this.store.onDisconnect(p, { online: false, lastSeen: TIMESTAMP });
    this.timers.push(window.setInterval(beat, HEARTBEAT_MS));
    this.timers.push(window.setInterval(() => this.checkHost(), 1000));
    this.timers.push(window.setInterval(() => this.checkConnections(), 1000));

    this.showWaitingForRoom();
    this.store.watch(P.members(this.room), (v) => {
      this.members = (v as unknown as Record<string, Member>) ?? {};
      this.refreshRematch();
      // The host took me off the waiting list.
      if (this.joinedAs === 'member' && this.meta?.status === 'waiting' && !this.members[this.me.uid] && !this.leaving) {
        this.end(L().ui.removedFromTable);
        return;
      }
      this.refreshLobby();
    });
    this.store.watch(P.presence(this.room), (v) => {
      this.presence = (v as Record<string, { online?: boolean; lastSeen?: number }>) ?? {};
      this.refreshLobby();
    });
    this.store.watch(P.meta(this.room), (v) => this.onMeta(v as RoomMeta | null));
    this.store.watch(P.results(this.room), (v) => {
      this.resultsAt = Number((v as { at?: number } | null)?.at ?? 0);
      this.refreshRematch();
    });
  }

  stop(): void {
    this.timers.forEach((t) => window.clearInterval(t));
    this.follower?.stop();
    this.relay?.stop();
    this.host?.stop();
  }

  // --------------------------------------------------------------- meta

  private joining = false;
  private joinedAs: 'member' | 'spectator' | null = null;

  /**
   * Join the room the first time it is seen open: a member while it is
   * waiting, a spectator once it has started without me. Runs on every meta
   * change, so a phone that opened the link before the host created the
   * table joins as soon as the table appears.
   */
  private async ensureJoined(meta: RoomMeta): Promise<void> {
    if (this.joining || this.joinedAs || meta.status === 'closed') return;
    this.joining = true;
    try {
      if (meta.status === 'waiting') {
        const existing = (await this.store.get(P.member(this.room, this.me.uid))) as Member | null;
        if (!existing) await this.store.set(P.member(this.room, this.me.uid), { name: this.me.name, avatar: this.me.avatar, ready: false, joinedAt: this.store.now() });
        this.joinedAs = 'member';
      } else if (arr<SeatEntry>(meta.seats).some((s) => s.uid === this.me.uid)) {
        this.joinedAs = 'member'; // rejoining my own seat
      } else {
        // Claim a free spectator slot (at most 8 watch).
        const slots = ((await this.store.get(P.spectatorSlots(this.room))) as Record<string, string> | null) ?? {};
        const mine = Object.entries(slots).find(([, u]) => u === this.me.uid)?.[0];
        const free = mine ?? ['0', '1', '2', '3', '4', '5', '6', '7'].find((k) => !slots[k]);
        if (free !== undefined) {
          await this.store.update({
            [`${P.spectatorSlots(this.room)}/${free}`]: this.me.uid,
            [P.spectator(this.room, this.me.uid)]: { name: this.me.name, avatar: this.me.avatar, slot: Number(free) },
          });
        }
        this.joinedAs = 'spectator';
      }
    } finally {
      this.joining = false;
    }
  }

  /** Before the host has created the table. */
  private showWaitingForRoom(): void {
    if (this.meta) return;
    this.root.className = `efoc-root ${this.game.felt}`;
    this.root.innerHTML = '<div class="overlay lobby"><div class="sheet setup-sheet"><h2></h2><p class="lobby-wait"></p></div></div>';
    this.root.querySelector('h2')!.textContent = `🃏 ${this.game.title()}`;
    this.root.querySelector('.lobby-wait')!.textContent = L().ui.waitingForTable;
  }

  private onMeta(meta: RoomMeta | null): void {
    if (this.ended) return;
    if (!meta) {
      this.showWaitingForRoom();
      return;
    }
    if (meta.status === 'closed') {
      if (!this.leaving) this.end(L().ui.tableClosed);
      return;
    }
    // The room says which game this is.
    if (meta.gameId && meta.gameId !== this.game.id && !this.table) this.game = netGame(meta.gameId);
    void this.ensureJoined(meta);
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

  private leaving = false;
  private ended = false;

  /** The table is over for this phone before it started: a note and a way back. */
  private end(message: string): void {
    if (this.ended) return;
    this.ended = true;
    this.stop();
    this.root.className = `efoc-root ${this.game.felt}`;
    this.root.innerHTML = '<div class="overlay lobby"><div class="sheet setup-sheet"><h2></h2><p class="lobby-wait lobby-ended"></p><div class="sheet-actions"><button type="button" class="btn btn-primary"></button></div></div></div>';
    this.root.querySelector('h2')!.textContent = `🃏 ${this.game.title()}`;
    this.root.querySelector('.lobby-ended')!.textContent = message;
    const back = this.root.querySelector('button')!;
    back.textContent = L().ui.back;
    back.addEventListener('click', () => this.opts.onExit());
  }

  /** I leave on purpose: my seat goes (or, as host, the whole table). */
  private async leaveTable(close: boolean): Promise<void> {
    this.leaving = true;
    try {
      if (close) await this.store.update({ [`${P.meta(this.room)}/status`]: 'closed' });
      else await this.store.set(P.member(this.room, this.me.uid), null);
    } catch {
      /* leave anyway */
    }
    this.stop();
    this.opts.onExit();
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
    renderLobby(this.root, { meta: m, members: this.members, online, me: this.me.uid, title: this.game.title(), felt: this.game.felt, houseRules: this.game.houseRules }, {
      setReady: (ready) => void this.store.set(`${P.member(this.room, this.me.uid)}/ready`, ready),
      addBot: () => {
        const used = new Set(m.bots.map((b) => b.name));
        const pick = BOT_NAMES.find(([n]) => !used.has(n)) ?? BOT_NAMES[0]!;
        void this.store.set(`${P.meta(this.room)}/bots`, [...m.bots, { uid: null, name: pick[0], avatar: pick[1], bot: pick[2] }] as unknown as Json);
      },
      removeBot: (i) => void this.store.set(`${P.meta(this.room)}/bots`, m.bots.filter((_, k) => k !== i) as unknown as Json),
      setRule: (patch) => void this.store.update(Object.fromEntries(Object.entries(patch).map(([k, v]) => [`${P.meta(this.room)}/${k}`, v as Json]))),
      invite: inApp() ? () => send({ t: 'invite' }) : undefined,
      removePlayer: (uid) => void this.store.set(P.member(this.room, uid), null),
      leave: () => void this.leaveTable(false),
      closeTable: () => void this.leaveTable(true),
      start: () => {
        const seats = lobbySeats(m, this.members);
        if (seats.length < 2) return;
        void this.store.update({ [`${P.meta(this.room)}/seats`]: seats as unknown as Json, [`${P.meta(this.room)}/status`]: 'playing' });
      },
    });
  }

  // -------------------------------------------------------------- table

  private startTable(meta: RoomMeta): void {
    this.seats = arr<SeatEntry>(meta.seats);
    const seat = this.seats.findIndex((s) => s.uid === this.me.uid);
    this.mySeat = seat >= 0 ? seat : 'public';
    const me = seat >= 0 ? seat : 0;
    this.table = this.game.createTable(
      this.root,
      me,
      this.seats.map((s) => ({ name: s.name, avatar: s.avatar, bot: !!s.bot })),
      meta.hostUid === this.me.uid,
      {
        move: (m) => void this.intent(m),
        ready: () => void this.intent({ type: 'ready' }),
        back: () => void this.intent({ type: 'back' }),
        playAgain: () => this.host?.playAgain(),
        exit: () => void this.quitTable(),
      },
      meta.humour,
    );
    this.root.classList.toggle('spectator', this.mySeat === 'public');
    this.root.dataset.turnMs = String(meta.turnMs);
    this.follower = new Follower(
      this.store,
      this.room,
      this.seats.length,
      this.mySeat,
      (u) => this.onFollow(u),
      (r) => {
        this.table?.reject(r);
        if (this.opts.autopilot) this.autopilot(); // try again, like a person would
      },
      this.game,
    );
    this.follower.start();
    (window as unknown as { __efoc: unknown }).__efoc = this.debug();
  }

  private onFollow(u: FollowUpdate): void {
    this.lastN = u.n;
    this.lastView = u.view;
    this.table?.update(u.view as never, u.events as GameEvent[], { deadline: u.entry.deadline, afk: u.entry.afk, totals: u.entry.totals });
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
      if (!view || this.mySeat === 'public' || view.phase !== 'play') return;
      if (!(this.game.canMove ? this.game.canMove(view, this.mySeat) : view.turn === this.mySeat)) return;
      const move = this.game.module.bot(view, 'normal', createRng(Math.floor(Math.random() * 2 ** 31)));
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
    const rand = (): number => {
      seed = (Math.imul(seed, 1103515245) + 12345) >>> 0;
      return seed / 2 ** 32;
    };
    const host = new HostCore(this.game.module, this.seatInfo(), this.game.config(meta), {
      turnMs: meta.turnMs,
      botSpeed: this.opts.botSpeed,
      ...this.game.hostOptions(meta, this.seats.map((s) => s.name), rand),
    });
    this.host = host;
    this.relay = new HostRelay(this.store, this.room, host, this.seats, this.game);
    const saved = (await this.store.get(P.hostState(this.room))) as unknown as HostSnapshot<Json> | null;
    if (saved) {
      const restored: HostSnapshot<unknown> = {
        ...saved,
        state: this.game.revive(saved.state, this.seats.length),
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

  /**
   * Each seat's connection, for the seat chips: online, reconnecting
   * (offline, its seat held), left (tapped Leave), or a bot. The host lets a
   * bot play a seat whose player left, so nobody waits for them.
   */
  private checkConnections(): void {
    const m = this.meta;
    if (!m || m.status !== 'playing' || !this.table) return;
    const conn: Conn[] = this.seats.map((s) => {
      if (!s.uid) return 'bot';
      if (this.presence[s.uid]?.left) return 'left';
      return this.online(s.uid) || s.uid === this.me.uid ? 'online' : 'away';
    });
    const key = conn.join();
    if (key !== this.connKey) {
      this.connKey = key;
      this.table.setConnection(conn);
    }
    this.refreshRematch();
    if (this.host) conn.forEach((c, i) => c === 'left' && !this.host!.afk[i] && this.host!.setAfk(i, true));
  }

  /** "Who's in for another?" on the results screen. */
  private refreshRematch(): void {
    const m = this.meta;
    if (!m || !this.table || !this.resultsAt || this.mySeat === 'public') return;
    const at = this.resultsAt;
    const rows = this.seats
      .filter((s) => s.uid && s.uid !== this.me.uid)
      .map((s) => {
        const left = this.presence[s.uid!]?.left || !this.online(s.uid);
        const state: 'in' | 'waiting' | 'left' = left ? 'left' : this.members[s.uid!]?.again === at ? 'in' : 'waiting';
        return { name: s.name, avatar: s.avatar, state };
      });
    const isHost = m.hostUid === this.me.uid;
    const mineIn = this.members[this.me.uid]?.again === at;
    const key = JSON.stringify([at, rows, isHost, mineIn]);
    if (key === this.rematchKey) return;
    this.rematchKey = key;
    this.table.setRematch({ rows, isHost, mineIn, onIn: () => void this.store.set(`${P.member(this.room, this.me.uid)}/again`, at) });
  }

  /** Leave mid-game (or after it): say so, so nobody waits for me. */
  private async quitTable(): Promise<void> {
    const p = P.presenceOf(this.room, this.me.uid);
    const gone = { online: false, left: true, lastSeen: TIMESTAMP };
    // Replace the onDisconnect write too, or it would clear `left` as we go.
    this.store.onDisconnect(p, gone);
    this.stop();
    try {
      await this.store.set(p, gone);
    } catch {
      /* leave anyway */
    }
    this.opts.onExit();
  }

  /** Host migration: take over if the host has been silent too long and I'm next in line. */
  private checkHost(): void {
    const m = this.meta;
    if (!m || m.status !== 'playing' || m.hostUid === this.me.uid || this.claiming || this.mySeat === 'public') return;
    // Same test as the security rule: the host's presence says offline and
    // it has been silent for migrateAfterMs.
    const hp = this.presence[m.hostUid];
    const silentFor = this.store.now() - (hp?.lastSeen ?? 0);
    if (hp?.online !== false || silentFor < m.migrateAfterMs) return;
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
