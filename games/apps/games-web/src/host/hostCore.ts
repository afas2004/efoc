// The referee. It runs only on the host's phone (or alone in Practice):
// it deals, checks moves, puts them in one order, runs the turn clock,
// auto-selects at zero, plays bot seats, and applies the pressure rules.
// Every other phone only applies what this produces. Phase 3 wires the same
// class to Realtime Database; Practice wires it straight to the table.

import { createRng, type BotLevel, type GameEvent, type GameModule, type Rng, type SeatId } from '@efoc/engine';

export type Personality = 'speedy' | 'slowpoke' | 'bluffer' | 'grandmaster';

export interface SeatInfo {
  name: string;
  avatar: string;
  bot: null | { level: BotLevel; personality: Personality };
}

export interface LogEntry<Move> {
  n: number;
  seat: SeatId | null;
  move: Move | null;
  events: GameEvent[];
  /** Absolute ms time the current turn auto-selects, or null between rounds. */
  deadline: number | null;
}

export interface HostOptions {
  /** Base turn time in ms (Big Two 20 s). */
  turnMs: number;
  /** Fast room: halves every timer. */
  fast?: boolean;
  /** Multiplies bot thinking delays (tests use a small value). */
  botSpeed?: number;
  /** Fixed seed for the whole match (tests, tutorial). Otherwise crypto. */
  seed?: number;
  now?: () => number;
  /** Extra events for an entry (the Jester line), chosen once by the host. */
  commentate?: (events: GameEvent[], state: unknown) => GameEvent[];
  /** How long the table pauses after an entry before the next bot moves. */
  dwell?: (events: GameEvent[]) => number;
  /** Time to look at your cards after each deal, before the first turn. */
  previewMs?: number;
}

export interface Clock {
  set(fn: () => void, ms: number): unknown;
  clear(handle: unknown): void;
}

const browserClock: Clock = {
  set: (fn, ms) => setTimeout(fn, ms),
  clear: (h) => clearTimeout(h as ReturnType<typeof setTimeout>),
};

function freshSeed(): number {
  const buf = new Uint32Array(1);
  globalThis.crypto.getRandomValues(buf);
  return buf[0]!;
}

// Bots think long enough for people to follow what they did.
const BOT_DELAY: Record<Personality, [number, number]> = {
  speedy: [900, 1300],
  grandmaster: [1600, 2400],
  bluffer: [1300, 2100],
  slowpoke: [2800, 4200],
};

/**
 * A pause at least this long (a legendary play, a bomb, an auto-pass) holds
 * the turn clock and blocks moves until the animation has played, so nobody
 * loses time watching it.
 */
const HOLD_FROM_MS = 1800;

/** Auto-selects in a row before a seat is marked AFK. */
const AFK_AFTER = 2;
/** Slowpoke stamps in one match that trigger "Double it!". */
const SLOWPOKE_LIMIT = 3;

export class HostCore<Config, State, Move, View> {
  state!: State;
  n = 0;
  readonly afk: boolean[];
  readonly stamps: number[];
  readonly doubled: boolean[];
  /** Match totals including pressure doubling. */
  readonly totals: number[];
  private consecutive: number[];
  private timer: unknown = null;
  private botTimer: unknown = null;
  private deadline: number | null = null;
  private rng!: Rng;
  private seedBase: number;
  private round = 0;
  private listeners: ((e: LogEntry<Move>) => void)[] = [];
  private stopped = false;
  private lastDwell = 0;
  /** No moves before this time: the look-at-your-cards pause or a big moment. */
  private holdUntil = 0;
  /** True during the look-at-your-cards pause. */
  private previewing = false;
  private readySeats = new Set<SeatId>();

  constructor(
    readonly game: GameModule<Config, State, Move, View> & { nextRound?: (s: State, rng: Rng) => State },
    readonly seats: SeatInfo[],
    readonly config: Config,
    readonly opts: HostOptions,
    private readonly clock: Clock = browserClock,
  ) {
    const n = seats.length;
    this.afk = new Array<boolean>(n).fill(false);
    this.stamps = new Array<number>(n).fill(0);
    this.doubled = new Array<boolean>(n).fill(false);
    this.totals = new Array<number>(n).fill(0);
    this.consecutive = new Array<number>(n).fill(0);
    this.seedBase = opts.seed ?? freshSeed();
  }

  private now(): number {
    return this.opts.now ? this.opts.now() : Date.now();
  }

  get turnMs(): number {
    return this.opts.fast ? this.opts.turnMs / 2 : this.opts.turnMs;
  }

  onEntry(fn: (e: LogEntry<Move>) => void): void {
    this.listeners.push(fn);
  }

  /** Adds the Jester's line and works out how long the table should pause. */
  private decorate(events: GameEvent[]): GameEvent[] {
    const all = this.opts.commentate ? [...events, ...this.opts.commentate(events, this.state)] : events;
    this.lastDwell = this.opts.dwell ? this.opts.dwell(all) : 0;
    return all;
  }

  private emit(seat: SeatId | null, move: Move | null, events: GameEvent[]): void {
    const entry: LogEntry<Move> = { n: this.n++, seat, move, events, deadline: this.deadline };
    for (const l of this.listeners) l(entry);
  }

  /** Seats that may move now. */
  waiting(): SeatId[] {
    const out: SeatId[] = [];
    for (let s = 0; s < this.seats.length; s++) if (this.game.legalMoves(this.state, s).length > 0) out.push(s);
    return out;
  }

  start(): void {
    this.round = 1;
    this.doubled.fill(false);
    this.rng = createRng(this.seedBase);
    this.state = this.game.setup(this.seats.map((_, i) => i), this.config, this.rng);
    this.dealt();
  }

  /** A new match with the same seats (the host's "Play again"). */
  playAgain(): void {
    this.stopTimers();
    this.seedBase = this.opts.seed !== undefined ? this.seedBase + 1 : freshSeed();
    this.stamps.fill(0);
    this.totals.fill(0);
    this.consecutive.fill(0);
    this.afk.fill(false);
    this.start();
  }

  nextRound(): void {
    if (!this.game.nextRound) return;
    this.round++;
    this.doubled.fill(false);
    this.state = this.game.nextRound(this.state, this.rng);
    this.dealt();
  }

  /** After a deal: a look-at-your-cards pause, then the first turn. */
  private dealt(): void {
    const preview = this.opts.previewMs ?? 0;
    this.previewing = preview > 0;
    this.readySeats.clear();
    this.holdUntil = this.now() + preview;
    const events = this.decorate([{ type: 'round_started', round: this.round, previewMs: preview }]);
    this.lastDwell = Math.max(this.lastDwell, preview);
    this.armTurn(preview);
    this.emit(null, null, events);
    this.scheduleBot();
  }

  /**
   * A player tapped "I'm ready" during the look-at-your-cards pause. When
   * every human is ready the game starts at once.
   */
  ready(seat: SeatId): void {
    if (!this.previewing || this.stopped) return;
    this.readySeats.add(seat);
    const humans = this.seats.map((s, i) => (s.bot ? -1 : i)).filter((i) => i >= 0);
    const allReady = humans.every((i) => this.readySeats.has(i));
    if (!allReady) {
      this.emit(null, null, [{ type: 'ready', seat }]);
      return;
    }
    this.previewing = false;
    this.holdUntil = this.now();
    this.lastDwell = 0;
    this.armTurn(0);
    this.emit(null, null, [{ type: 'ready', seat }, { type: 'preview_ended' }]);
    this.scheduleBot();
  }

  /** A move from a seat. Returns the rejection reason, or null if accepted. */
  submit(seat: SeatId, move: Move, madeAt?: number): string | null {
    if (this.stopped) return 'The match has ended';
    if (madeAt !== undefined && madeAt !== this.n - 1) return 'The table moved on; try again';
    if (this.now() < this.holdUntil) return 'Get ready…';
    const check = this.game.validate(this.state, seat, move);
    if (!check.ok) return check.reason;
    this.consecutive[seat] = 0;
    this.commit(seat, move, []);
    return null;
  }

  /** The player tapped "I'm back". */
  back(seat: SeatId): void {
    if (!this.afk[seat]) return;
    this.afk[seat] = false;
    this.consecutive[seat] = 0;
    this.lastDwell = 0;
    this.emit(null, null, [{ type: 'afk_cleared', seat }]);
    this.scheduleBot();
  }

  stop(): void {
    this.stopped = true;
    this.stopTimers();
  }

  private commit(seat: SeatId, move: Move, extra: GameEvent[]): void {
    const { state, events } = this.game.apply(this.state, seat, move, this.rng);
    this.state = state;
    let all = [...extra, ...events];
    const result = this.game.result(state);
    if (result) {
      this.deadline = null;
      this.stopTimers();
      const points = result.points.map((p, i) => (this.doubled[i] ? p * 2 : p));
      points.forEach((p, i) => (this.totals[i] = this.totals[i]! + p));
      all.push({ type: 'match_points', points, totals: this.totals.slice(), doubled: this.doubled.slice(), placings: result.placings });
      all = this.decorate(all);
    } else {
      all = this.decorate(all);
      // A big moment holds the next turn's clock until it has played.
      this.previewing = false;
      const hold = this.lastDwell >= HOLD_FROM_MS ? this.lastDwell : 0;
      this.holdUntil = this.now() + hold;
      this.armTurn(hold);
    }
    this.emit(seat, move, all);
    if (!result) this.scheduleBot();
  }

  private stopTimers(): void {
    if (this.timer !== null) this.clock.clear(this.timer);
    if (this.botTimer !== null) this.clock.clear(this.botTimer);
    this.timer = this.botTimer = null;
  }

  private armTurn(extraMs = 0): void {
    if (this.timer !== null) this.clock.clear(this.timer);
    this.deadline = this.now() + extraMs + this.turnMs;
    this.timer = this.clock.set(() => this.timeout(), extraMs + this.turnMs);
  }

  private timeout(): void {
    this.timer = null;
    const seats = this.waiting();
    if (seats.length === 0) return;
    // Auto-select with the Easy bot for everyone still choosing.
    const seat = seats[0]!;
    const move = this.game.bot(this.game.view(this.state, seat), 'easy', this.rng);
    const extra: GameEvent[] = [{ type: 'too_slow', seat }];
    this.stamps[seat] = this.stamps[seat]! + 1;
    this.consecutive[seat] = this.consecutive[seat]! + 1;
    if (this.consecutive[seat]! >= AFK_AFTER && !this.afk[seat]) {
      this.afk[seat] = true;
      extra.push({ type: 'afk', seat });
    }
    if (this.stamps[seat] === SLOWPOKE_LIMIT && !this.doubled[seat]) {
      this.doubled[seat] = true;
      extra.push({ type: 'double_it', seat });
    }
    this.commit(seat, move, extra);
  }

  private scheduleBot(): void {
    if (this.botTimer !== null) this.clock.clear(this.botTimer);
    this.botTimer = null;
    const seat = this.waiting().find((s) => this.seats[s]!.bot || this.afk[s]);
    if (seat === undefined) return;
    const info = this.seats[seat]!.bot;
    const [lo, hi] = BOT_DELAY[info?.personality ?? 'grandmaster'];
    const delay = (this.lastDwell + lo + this.rng.next() * (hi - lo)) * (this.opts.botSpeed ?? 1);
    this.botTimer = this.clock.set(() => {
      this.botTimer = null;
      if (!this.waiting().includes(seat)) return;
      const level: BotLevel = info?.level ?? 'normal';
      const move = this.game.bot(this.game.view(this.state, seat), level, this.rng);
      this.commit(seat, move, []);
    }, delay);
  }
}
