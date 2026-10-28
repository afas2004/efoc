// The Zombie table, laid out like a real one (Fahmi's playtest, 28 Oct).
//
// Everyone's hand sits at the edge of the screen in front of them, the same
// size as mine (smaller on crowded tables), turned the way they hold it,
// half off the screen. When it's someone's turn the two players in the
// exchange expand: their hands slide in and their badges grow, everyone
// else dims. The hand being drawn from shuffles itself, then waits. The
// drawer points at a card (everyone sees it lift, its holder too) and
// confirms; it wobbles, flies slowly to the drawer and, in my hand, turns
// over. A pair glows until it's thrown (tap it, or Auto-throw in the menu)
// and flies face up to the pile in the middle, landing exactly where it
// stays.
//
// Nothing jumps: the table keeps its own copy of what it has shown and
// walks it forward one log entry at a time, playing every step before the
// next. My moves wait until the table has caught up.

import { zombie, type Card, type GameEvent, type SeatId } from '@efoc/engine';
import { haptic } from '../../bridge';
import { banner, burst, confetti, dim, shake, type ColourRole } from '../../feel/effects';
import { jesterText, type Humour, type JesterEvent } from '../../feel/jester';
import { EYES, JESTER_SVG, playEmoji, preloadEmoji } from '../../feel/jesterArt';
import { setMuted, sound, unlockAudio } from '../../feel/sound';
import { FeelQueue } from '../../feel/tiers';
import { L, fmt } from '../../strings';
import { cardImage, cardLabel, makeBack, makeCard } from '../../table/cardFace';
import { computeLayout, handPlaces, JESTER_BAND, MIN_TARGET, TURN_CHIP_H, type TableLayout } from '../../table/layout';
import { renderRematch, type RematchInfo } from '../../table/rematch';

type View = zombie.ZombieView;
type Move = zombie.ZombieMove;

export interface SeatMeta {
  name: string;
  avatar: string;
  bot: boolean;
}

export interface TableSettings {
  humour: Humour;
  sound: boolean;
  reducedMotion: boolean;
}

export interface TableHooks {
  move(move: Move): void;
  playAgain?: () => void;
  back(): void;
  exit(): void;
}

export interface UpdateMeta {
  deadline: number | null;
  afk: boolean[];
}

export type Conn = 'online' | 'away' | 'left' | 'bot';

/** A card's place: its centre, size and turn. */
interface Pose {
  x: number;
  y: number;
  w: number;
  h: number;
  rot: number;
}

type Edge = 'T' | 'L' | 'R' | 'B';

interface SeatGeo {
  edge: Edge;
  /** This seat's stretch of its edge. */
  a0: number;
  a1: number;
  /** The whole edge (an expanded hand may use all of it, over its neighbours). */
  e0: number;
  e1: number;
}

/** What the table shows: the game as far as its animations have got. */
interface Shown {
  view: View;
  /** Cards per seat as drawn now (a card in flight belongs to nobody). */
  counts: number[];
  /** My hand as drawn now. */
  hand: Card[];
  /** My cards still face down (just drawn, about to turn). */
  faceDown: Set<Card>;
  /** Pairs on the pile as drawn now. */
  pile: number;
  /** The two players in the exchange, expanded. */
  drawer: SeatId | null;
  target: SeatId | null;
  aim: number | null;
  /** The hand gathered up while it shuffles. */
  gathered: SeatId | null;
}

/** Animation speed: ?anim=0.1 in tests, 1 at the table. */
export function animScale(): number {
  const v = Number(new URLSearchParams(location.search).get('anim'));
  return v > 0 ? Math.min(1, v) : 1;
}

const RATIO = 1.36;
const BADGE_W = 66;
const BADGE_H = 64;
const STRIP = MIN_TARGET + 2;
/** Cards and badges slide between places this slowly (CSS, scaled). */
const SLIDE_MS = 650;
const AUTO_KEY = 'efoc.zombie.autoThrow';
const isZ = zombie.isZombie;

/** Where opponents sit, clockwise from the player after me. */
const SPOTS: Record<number, string[]> = {
  1: ['T'],
  2: ['L', 'R'],
  3: ['L', 'T', 'R'],
  4: ['L', 'TL', 'TR', 'R'],
  5: ['L', 'TL', 'T', 'TR', 'R'],
  6: ['LD', 'LU', 'TL', 'TR', 'RU', 'RD'],
  7: ['LD', 'LU', 'TL', 'T', 'TR', 'RU', 'RD'],
};

/** A card face, the Zombie included (it has no card image). */
export function makeFace(card: Card): HTMLElement {
  if (!isZ(card)) return makeCard(card);
  const e = document.createElement('div');
  e.className = 'card zb-zombie-card';
  e.dataset.card = card;
  e.innerHTML = '<span class="zb-z-face">🧟</span><span class="zb-z-word">ZOMBIE</span>';
  e.setAttribute('aria-label', L().zb.zombieCard);
  return e;
}

const faceLabel = (c: Card): string => (isZ(c) ? L().zb.zombieCard : cardLabel(c));
const wait = (ms: number): Promise<void> => new Promise((r) => setTimeout(r, ms));
const clamp = (v: number, lo: number, hi: number): number => Math.max(lo, Math.min(hi, v));

export class ZombieTable {
  readonly feel = new FeelQueue();
  private lay!: TableLayout;
  private view: View | null = null;
  private shown: Shown | null = null;
  private queue: { view: View; events: GameEvent[] }[] = [];
  private running = false;
  private meta: UpdateMeta = { deadline: null, afk: [] };
  /** A move sent, not yet confirmed. */
  private sent = false;
  private turnTotal = 15000;
  private lastTickSecond = -1;
  private resultsOpen = false;
  private conn: Conn[] = [];
  private rematch: RematchInfo | null = null;
  private rematchEl: HTMLElement | null = null;
  private autoThrow = false;
  private autoTimer = 0;
  private readonly speed = animScale();
  private eaten = new Set<SeatId>();

  // DOM
  private table: HTMLElement;
  private badges: HTMLElement[] = [];
  private backs: HTMLElement[][] = [];
  private pileEl: HTMLElement;
  private pileCards: HTMLElement[] = [];
  private pileCount: HTMLElement;
  private label: HTMLElement;
  private handLayer: HTMLElement;
  private sprites = new Map<Card, HTMLElement>();
  private handNote: HTMLElement;
  private turnChip: HTMLElement;
  private timerBar: HTMLElement;
  private timerFill: HTMLElement;
  private actionBar: HTMLElement;
  private flights: HTMLElement;
  private fx: HTMLElement;
  private jesterEl: HTMLElement;
  private jesterBubble: HTMLElement;
  private jesterEmoji: HTMLElement;
  private stopEmoji: (() => void) | null = null;
  private jesterTimer = 0;
  private overlay: HTMLElement;
  private live: HTMLElement;

  constructor(
    private readonly root: HTMLElement,
    readonly me: SeatId,
    private readonly seatMeta: SeatMeta[],
    public isHost: boolean,
    private readonly hooks: TableHooks,
    public settings: TableSettings,
  ) {
    root.innerHTML = '';
    root.className = 'efoc-root felt-zombie';
    this.table = el('div', 'table zb-table', root);
    el('div', 'zb-felt', this.table);
    this.pileEl = el('div', 'zb-pile', this.table);
    this.pileCount = el('div', 'zb-pile-label', this.table);
    this.label = el('div', 'zb-label hidden', this.table);
    this.label.setAttribute('aria-live', 'polite');
    this.handLayer = el('div', 'card-layer zb-hand', this.table);
    this.handNote = el('div', 'zb-hand-note hidden', this.table);
    this.turnChip = el('div', 'turn-chip zb-prompt hidden', this.table);
    this.timerBar = el('div', 'timer-bar', this.table);
    this.timerFill = el('div', 'timer-fill', this.timerBar);
    this.actionBar = el('div', 'action-bar zb-actions', this.table);
    this.flights = el('div', 'zb-flights', root);
    this.fx = el('div', 'fx-layer', root);
    this.jesterEl = el('div', 'jester hidden', root);
    this.jesterEl.setAttribute('aria-live', 'polite');
    const figure = el('div', 'jester-figure', this.jesterEl);
    figure.innerHTML = JESTER_SVG;
    this.jesterEmoji = el('div', 'jester-emoji', figure);
    this.jesterBubble = el('div', 'jester-bubble', this.jesterEl);
    preloadEmoji(['laugh', 'explode', 'party', 'cool', 'fire', 'grimace', 'eyeroll', 'scream']);
    this.overlay = el('div', 'overlay hidden', root);
    this.live = el('div', 'sr-only', root);
    this.live.setAttribute('aria-live', 'assertive');
    try {
      this.autoThrow = localStorage.getItem(AUTO_KEY) === '1';
    } catch {
      /* private mode */
    }
    root.style.setProperty('--zb-slide', `${Math.round(SLIDE_MS * this.speed)}ms`);
    document.addEventListener('pointerdown', () => unlockAudio(), { capture: true });
    window.addEventListener('resize', () => this.render());
    this.applySettings();
    this.tick();
  }

  applySettings(): void {
    const reduced = this.settings.reducedMotion || matchMedia('(prefers-reduced-motion: reduce)').matches;
    this.feel.reduced = reduced;
    this.root.classList.toggle('reduced-motion', reduced);
    setMuted(!this.settings.sound);
  }

  /** How long a step takes: slow at the table, quicker only when far behind. */
  private ms(base: number): number {
    const behind = this.queue.length;
    const catchUp = behind > 6 ? 0.15 : behind > 3 ? 0.5 : 1;
    return Math.round(base * this.speed * catchUp * (this.feel.reduced ? 0.5 : 1));
  }

  private pause(base: number): Promise<void> {
    return wait(this.ms(base));
  }

  // ------------------------------------------------------------- updates

  /** New state from the host, with the events that produced it (only mine of the private ones). */
  update(view: View, events: GameEvent[], meta: UpdateMeta): void {
    const prevDeadline = this.meta.deadline;
    this.view = view;
    this.meta = meta;
    if (meta.deadline && meta.deadline !== prevDeadline) this.turnTotal = Math.max(1000, meta.deadline - Date.now());
    if (view.phase === 'play' && (this.resultsOpen || this.eaten.size)) {
      this.resultsOpen = false;
      this.eaten.clear();
      this.overlay.className = 'overlay hidden';
    }
    const mine = events.filter((e) => e.to === undefined || e.to === this.me);
    const dealing = mine.some((e) => e.type === 'round_started');
    if (!this.shown || dealing) {
      this.queue = [];
      this.shown = this.fresh(view, dealing);
    }
    this.queue.push({ view, events: mine });
    void this.run();
  }

  /** The table as a new deal starts it (nothing dealt yet), or as it is when joining late. */
  private fresh(v: View, dealing: boolean): Shown {
    const active = v.phase === 'play' && v.step !== 'deal' && !dealing;
    return {
      view: v,
      counts: dealing ? v.counts.map(() => 0) : v.counts.slice(),
      hand: dealing ? [] : v.hand.slice(),
      faceDown: new Set(),
      pile: dealing ? 0 : v.pile.length / 2,
      drawer: active ? v.turn : null,
      target: active ? v.from : null,
      aim: v.aim,
      gathered: null,
    };
  }

  /** Plays queued entries one after another. */
  private async run(): Promise<void> {
    if (this.running) return;
    this.running = true;
    try {
      while (this.queue.length) {
        const { view, events } = this.queue.shift()!;
        try {
          await this.play(events);
        } catch {
          /* an animation failed: just show the state */
        }
        this.settle(view);
        this.render();
      }
    } finally {
      this.running = false;
      this.render();
      this.maybeAutoThrow();
    }
  }

  /** After an entry has played: the table shows exactly the game. */
  private settle(v: View): void {
    const s = this.shown!;
    s.view = v;
    s.counts = v.counts.slice();
    s.hand = v.hand.slice();
    s.faceDown.clear();
    s.pile = v.pile.length / 2;
    s.aim = v.aim;
    s.gathered = null;
    if (v.phase === 'play' && v.step !== 'deal') {
      s.drawer = v.turn;
      s.target = v.from;
    } else s.drawer = s.target = null;
    this.sent = false;
  }

  /** One log entry, step by step. */
  private async play(events: GameEvent[]): Promise<void> {
    const s = this.shown!;
    for (const e of events) this.moment(e);
    for (const e of events) {
      switch (e.type) {
        case 'round_started':
          await this.deal(this.view!);
          break;
        case 'turn':
          await this.expand(e.seat as SeatId, e.from as SeatId);
          break;
        case 'shuffled':
          await this.shuffleHand(e.seat as SeatId, events.find((x) => x.type === 'hand')?.cards as Card[] | undefined);
          break;
        case 'aim':
          s.aim = e.slot as number;
          this.render();
          sound.click();
          await this.pause(350);
          break;
        case 'drew':
          await this.draw(e, events);
          break;
        case 'pair':
          // At the deal everyone throws at once: others' pairs fly while I keep going.
          if (!this.isMe(e.seat as SeatId) && !events.some((x) => x.type === 'turn' || x.type === 'zombie_loser')) void this.throwPair(e.seat as SeatId, e.cards as Card[]);
          else await this.throwPair(e.seat as SeatId, e.cards as Card[]);
          break;
        case 'safe':
          await this.pause(500);
          break;
        case 'zombie_loser':
          await this.loser(e.seat as SeatId);
          break;
        default:
      }
    }
  }

  setRematch(info: RematchInfo | null): void {
    this.rematch = info;
    if (this.rematchEl?.isConnected) renderRematch(this.rematchEl, info);
  }

  setConnection(conn: Conn[]): void {
    this.conn = conn.slice();
    this.render();
  }

  notice(text: string): void {
    if (!this.lay) return;
    const c = this.centre();
    this.feel.play(2, 'notice', (ctx) => banner(this.fx, text, 'info', 'pop', ctx, { x: c.x, y: c.y0 + 40 }));
  }

  reject(reason: string): void {
    this.sent = false;
    if (this.shown) this.shown.aim = this.view?.aim ?? null;
    this.feel.play(1, 'rejected', (ctx) => banner(this.fx, reason, 'danger', 'pop', ctx, this.handCentre()));
    haptic('error');
    this.render();
  }

  private get spectator(): boolean {
    return this.view?.seat === 'public';
  }

  private isMe(seat: SeatId | null): boolean {
    return seat === this.me && !this.spectator;
  }

  /** The table has caught up with the game: input is open. */
  private get idle(): boolean {
    return !this.running && this.queue.length === 0 && !this.sent;
  }

  private get myDraw(): boolean {
    const v = this.view;
    return !!v && this.idle && !this.spectator && v.phase === 'play' && v.step === 'draw' && v.turn === this.me;
  }

  /** Pairs I may throw now, if any. */
  private myPairs(): Card[][] {
    const v = this.view;
    if (!v || this.spectator || v.phase !== 'play' || !this.idle) return [];
    if (v.step === 'deal' || (v.step === 'throw' && v.turn === this.me)) return zombie.pairsIn(v.hand);
    return [];
  }

  private send(m: Move): void {
    if (this.sent) return;
    if (m.type !== 'aim') this.sent = true;
    unlockAudio();
    this.hooks.move(m);
    this.render();
  }

  // ------------------------------------------------------------ geometry

  private relSeat(seat: SeatId): number {
    const n = this.view?.players ?? this.seatMeta.length;
    return (seat - this.me + n) % n;
  }

  private spots(): string[] {
    return SPOTS[(this.view?.players ?? this.seatMeta.length) - 1] ?? [];
  }

  /** A seat's edge and its stretch of it. */
  private seatGeo(seat: SeatId): SeatGeo {
    const lay = this.lay;
    const ins = readInsets();
    const left = ins.left + 4;
    const right = lay.vw - ins.right - 4;
    if (seat === this.me) return { edge: 'B', a0: left, a1: right, e0: left, e1: right };
    const spots = this.spots();
    const spot = spots[this.relSeat(seat) - 1] ?? 'T';
    const edge = spot[0] as Edge;
    const { rh } = this.restSize();
    const sideTop = ins.top + (spots.some((x) => x[0] === 'T') ? rh / 2 + BADGE_H + 14 : 10);
    const sideBottom = lay.hand.y - TURN_CHIP_H - 6;
    const same = spots.filter((x) => x[0] === edge);
    // Clockwise: up the left side, along the top, down the right.
    const order = edge === 'L' ? same.slice().reverse() : same;
    const k = order.indexOf(spot);
    const [e0, e1] = edge === 'T' ? [left, right] : [sideTop, sideBottom];
    const len = (e1 - e0) / same.length;
    return { edge, a0: e0 + len * k, a1: e0 + len * (k + 1), e0, e1 };
  }

  /** Card size at rest: the same as mine, smaller on crowded tables. */
  private restSize(): { rw: number; rh: number } {
    const n = this.view?.players ?? this.seatMeta.length;
    const scale = n <= 4 ? 1 : n <= 6 ? 0.78 : 0.64;
    return { rw: this.lay.handW * scale, rh: this.lay.handH * scale };
  }

  /** A point `inward` from an edge, `along` it, and the turn of a card held there by whoever sits there. */
  private onEdge(edge: Edge, along: number, inward: number): { x: number; y: number; rot: number } {
    const ins = readInsets();
    const lay = this.lay;
    switch (edge) {
      case 'T':
        return { x: along, y: ins.top + inward, rot: 180 };
      case 'L':
        return { x: ins.left + inward, y: along, rot: 90 };
      case 'R':
        return { x: lay.vw - ins.right - inward, y: along, rot: -90 };
      default:
        return { x: along, y: lay.hand.y + lay.hand.h - inward, rot: 0 };
    }
  }

  /** In the exchange: drawn big and slid in. */
  private active(seat: SeatId): boolean {
    const s = this.shown;
    return !!s && (s.drawer === seat || s.target === seat || this.eaten.has(seat));
  }

  /** Where each of a seat's cards sits: a fan at its edge; slid in, full size and spread when it's in the exchange. */
  private fanPoses(seat: SeatId, count: number): Pose[] {
    const g = this.seatGeo(seat);
    const big = this.active(seat);
    const { rw, rh } = this.restSize();
    const w = big ? this.lay.handW : rw;
    const h = big ? this.lay.handH : rh;
    const s = this.shown;
    const picking = big && s?.target === seat && this.isMe(s.drawer);
    // My pick needs a strip a finger can hit; otherwise a natural overlap.
    const natural = picking ? Math.max(STRIP, w * 0.62) : w * (big ? 0.5 : 0.34);
    // A tilted card reaches a little past its box: keep the ends clear of the screen's edge.
    const [s0, s1] = big ? [g.e0 + 8, g.e1 - 8] : [g.a0, g.a1];
    const span = s1 - s0;
    let rows = 1;
    while (picking && rows < 3 && count > rows && (span - w) / (Math.ceil(count / rows) - 1) < STRIP) rows++;
    const per = Math.ceil(count / rows) || 1;
    const step = per <= 1 ? 0 : Math.min(natural, (span - w) / (per - 1));
    const fanLen = w + step * (per - 1);
    const mid = clamp((g.a0 + g.a1) / 2, s0 + fanLen / 2, s1 - fanLen / 2);
    const gathered = s?.gathered === seat;
    const out: Pose[] = [];
    for (let i = 0; i < count; i++) {
      const row = Math.floor(i / per);
      const k = i - row * per;
      const inRow = Math.min(per, count - row * per);
      const t = inRow <= 1 ? 0 : (k / (inRow - 1)) * 2 - 1;
      const along = gathered ? mid : mid + (k - (inRow - 1) / 2) * step;
      // At rest half the card is off the screen; in the exchange it's all on, in rows if it must.
      let inward = big ? h / 2 + 14 + row * h * 0.58 : 0;
      if (!gathered && rows === 1) inward -= t * t * (big ? 4 : 3);
      if (s?.aim === i && s.target === seat) inward += h * 0.3;
      const p = this.onEdge(g.edge, along, inward);
      const spread = gathered || rows > 1 ? 0 : t * (big ? 4 : 5);
      out.push({ x: p.x, y: p.y, w, h, rot: p.rot + (g.edge === 'T' || g.edge === 'R' ? -spread : spread) });
    }
    return out;
  }

  /** Where a seat's badge sits: just inside its cards, further in (and bigger) in the exchange. */
  private badgePose(seat: SeatId): { x: number; y: number; scale: number } {
    const g = this.seatGeo(seat);
    const big = this.active(seat);
    const { rh } = this.restSize();
    const half = g.edge === 'T' || g.edge === 'B' ? BADGE_H / 2 : BADGE_W / 2;
    let reach = big ? this.lay.handH + 14 : rh / 2 + 4;
    if (big) {
      // Clear of a fan in rows, however deep it goes.
      const ins = readInsets();
      for (const q of this.fanPoses(seat, this.shown?.counts[seat] ?? 0)) {
        const depth = g.edge === 'T' ? q.y - ins.top + q.h / 2 : g.edge === 'L' ? q.x - ins.left + q.h / 2 : g.edge === 'R' ? this.lay.vw - ins.right - q.x + q.h / 2 : 0;
        reach = Math.max(reach, depth + 6);
      }
    }
    const p = this.onEdge(g.edge, (g.a0 + g.a1) / 2, reach + half);
    return { x: p.x, y: p.y, scale: big ? 1.18 : 1 };
  }

  /** The middle of the table, between the seats. */
  private centre(): { x: number; y: number; y0: number; w: number } {
    const lay = this.lay;
    const ins = readInsets();
    const spots = this.spots();
    const { rh } = this.restSize();
    const side = rh / 2 + BADGE_W + 12;
    const x0 = ins.left + (spots.some((x) => x[0] === 'L') ? side : 10);
    const x1 = lay.vw - ins.right - (spots.some((x) => x[0] === 'R') ? side : 10);
    const y0 = ins.top + (spots.some((x) => x[0] === 'T') ? rh / 2 + BADGE_H + 14 : 10);
    const y1 = lay.hand.y - TURN_CHIP_H - 10;
    return { x: (x0 + x1) / 2, y: (y0 + y1) / 2 + 14, y0, w: x1 - x0 };
  }

  private pileW(): number {
    return Math.round(clamp(this.lay.handW * 0.78, 36, 60));
  }

  /** Where pair `i` lies on the pile: a messy stack, but every card stays exactly where it landed. */
  private pilePose(i: number, which: 0 | 1): Pose {
    const c = this.centre();
    const w = this.pileW();
    const h = Math.round(w * RATIO);
    const r = (k: number): number => {
      const x = Math.sin((i + 1) * 12.9898 + k * 78.233) * 43758.5453;
      return x - Math.floor(x);
    };
    const rot = (r(1) - 0.5) * 50;
    const dx = (r(2) - 0.5) * 34;
    const dy = (r(3) - 0.5) * 22;
    const off = which ? w * 0.3 : 0;
    const rad = (rot * Math.PI) / 180;
    return { x: c.x + dx + Math.cos(rad) * off, y: c.y + dy + Math.sin(rad) * off, w, h, rot: rot + (which ? 8 : 0) };
  }

  /** My hand's card places (centres). */
  private handPoses(count: number): Pose[] {
    const lay = this.lay;
    return handPlaces(count, lay).map((p) => ({ x: p.x + lay.handW / 2, y: p.y + lay.handH / 2, w: lay.handW, h: lay.handH, rot: p.rot }));
  }

  private handCentre(): { x: number; y: number } {
    const h = this.lay.hand;
    return { x: h.x + h.w / 2, y: h.y + h.h - this.lay.handH / 2 - 4 };
  }

  private seatCentre(seat: SeatId): { x: number; y: number } {
    if (this.isMe(seat)) return this.handCentre();
    const b = this.badgePose(seat);
    return { x: b.x, y: b.y };
  }

  private nameOf(seat: SeatId): string {
    return this.isMe(seat) ? L().ui.you : this.seatMeta[seat]?.name ?? '';
  }

  /** Card `slot` of a seat holding `count`, as the table is laid out now. */
  private slotPose(seat: SeatId, slot: number, count: number): Pose {
    const fallback = { ...this.seatCentre(seat), w: this.lay.handW, h: this.lay.handH, rot: 0 };
    if (this.isMe(seat)) return this.handPoses(count)[slot] ?? fallback;
    return this.fanPoses(seat, count)[slot] ?? fallback;
  }

  // --------------------------------------------------------------- steps

  /** One card flying from one pose to another, turning as it goes. It ends exactly on `to`. */
  private fly(from: Pose, to: Pose, face: Card | null, flip: 'up' | 'down' | null, base: number): Promise<void> {
    const ms = this.ms(base);
    if (ms < 30) return Promise.resolve();
    const f = el('div', 'zb-flyer', this.flights);
    f.style.width = `${to.w}px`;
    f.style.height = `${to.h}px`;
    const inner = el('div', 'zb-flip', f);
    const front = el('div', 'zb-face front', inner);
    const back = el('div', 'zb-face back', inner);
    if (face) front.appendChild(makeFace(face)).classList.add('zb-fly-face');
    back.style.backgroundImage = `url("${cardImage('back')}")`;
    const pose = (p: Pose, lift = 0): string => `translate(${p.x - to.w / 2}px, ${p.y - to.h / 2 - lift}px) rotate(${p.rot}deg) scale(${p.w / to.w})`;
    const mid: Pose = { x: (from.x + to.x) / 2, y: (from.y + to.y) / 2, w: ((from.w + to.w) / 2) * 1.14, h: 0, rot: (from.rot + to.rot) / 2 };
    const lift = this.feel.reduced ? 0 : Math.min(80, 24 + Math.hypot(to.x - from.x, to.y - from.y) * 0.15);
    const anim = f.animate([{ transform: pose(from) }, { transform: pose(mid, lift), offset: 0.5 }, { transform: pose(to) }], {
      duration: ms,
      easing: 'cubic-bezier(0.45, 0.05, 0.3, 1)',
      fill: 'forwards',
    });
    const startUp = flip === 'down' ? true : flip === 'up' ? false : !!face;
    const endUp = flip === 'up' ? true : flip === 'down' ? false : !!face;
    inner.animate([{ transform: `rotateY(${startUp ? 0 : 180}deg)` }, { transform: `rotateY(${endUp ? 0 : 180}deg)` }], { duration: ms, easing: 'ease-in-out', fill: 'forwards' });
    return anim.finished.then(
      () => {
        f.remove();
        sound.thud(0);
      },
      () => f.remove(),
    );
  }

  /** The deal: cards fly from the middle to everyone in turn; mine land face up. */
  private async deal(v: View): Promise<void> {
    const s = this.shown!;
    this.render();
    await this.pause(500);
    const c = this.centre();
    const from: Pose = { x: c.x, y: c.y, w: this.lay.handW * 0.6, h: this.lay.handH * 0.6, rot: 0 };
    const launched = v.counts.map(() => 0);
    const total = v.counts.reduce((a, b) => a + b, 0);
    const flights: Promise<void>[] = [];
    sound.deal();
    for (let i = 0; launched.reduce((a, b) => a + b, 0) < total; i++) {
      const seat = i % v.players;
      if (launched[seat]! >= v.counts[seat]!) continue;
      const slot = launched[seat]!++;
      const card = this.isMe(seat) ? v.hand[slot] ?? null : null;
      const to = this.slotPose(seat, slot, v.counts[seat]!);
      flights.push(
        this.fly(from, to, card, card ? 'up' : null, 420).then(() => {
          s.counts[seat]!++;
          if (card) s.hand.push(card);
          this.render();
        }),
      );
      await this.pause(45);
    }
    await Promise.all(flights);
    s.counts = v.counts.slice();
    s.hand = v.hand.slice();
    this.render();
    await this.pause(400);
  }

  /** The two players in the exchange grow; the last two shrink back first. */
  private async expand(drawer: SeatId, target: SeatId): Promise<void> {
    const s = this.shown!;
    if (s.drawer !== null && (s.drawer !== drawer || s.target !== target)) {
      s.drawer = s.target = null;
      s.aim = null;
      this.render();
      await this.pause(SLIDE_MS);
    }
    s.drawer = drawer;
    s.target = target;
    s.aim = null;
    this.render();
    if (this.isMe(drawer)) haptic('light');
    await this.pause(SLIDE_MS + 100);
  }

  /** The hand about to be drawn from gathers, mixes and spreads again. Its holder sees the new order. */
  private async shuffleHand(seat: SeatId, order?: Card[]): Promise<void> {
    const s = this.shown!;
    s.gathered = seat;
    this.render();
    sound.deal();
    await this.pause(SLIDE_MS);
    const els = this.isMe(seat) ? [...this.sprites.values()] : this.backs[seat] ?? [];
    if (!this.feel.reduced && this.ms(520) > 60) {
      await Promise.all(
        els.map((e, i) =>
          e
            .animate([{ translate: '0 0' }, { translate: `${(i % 2 ? 1 : -1) * 12}px -10px` }, { translate: `${(i % 2 ? -1 : 1) * 12}px 6px` }, { translate: '0 0' }], { duration: this.ms(560), composite: 'add' })
            .finished.catch(() => undefined),
        ),
      );
    }
    if (order && this.isMe(seat)) s.hand = order.slice();
    s.gathered = null;
    this.render();
    await this.pause(SLIDE_MS);
  }

  /** A draw: the chosen card lifts and wobbles, flies slowly to the drawer and, in my hand, turns over. */
  private async draw(e: GameEvent, events: GameEvent[]): Promise<void> {
    const s = this.shown!;
    const seat = e.seat as SeatId;
    const from = e.from as SeatId;
    const slot = e.slot as number;
    const mine = this.isMe(seat);
    const fromMe = this.isMe(from);
    const card = (events.find((x) => x.type === 'drawn_card')?.card as Card | undefined) ?? null;
    // The pick shows first, even for a quick bot.
    if (s.aim !== slot) {
      s.aim = slot;
      this.render();
      await this.pause(700);
    }
    const fromCount = s.counts[from]!;
    const start = this.slotPose(from, slot, fromCount);
    const leaving = fromMe ? s.hand[slot] ?? null : null;
    // Suspense: a heartbeat wobble on the chosen card, then off it goes and the gap closes.
    s.aim = null;
    s.counts[from] = fromCount - 1;
    if (fromMe && leaving) s.hand = s.hand.filter((c) => c !== leaving);
    this.render();
    await this.wobble(start, leaving);
    const landCount = s.counts[seat]! + 1;
    if (mine && card) {
      s.hand = [...s.hand, card];
      s.faceDown.add(card);
      s.counts[seat] = landCount;
      this.render();
      const sprite = this.sprites.get(card);
      if (sprite) sprite.style.visibility = 'hidden';
      await this.fly(start, this.slotPose(seat, landCount - 1, landCount), null, null, 1150);
      if (sprite) sprite.style.visibility = '';
      // Turn it over, slowly.
      await this.pause(250);
      s.faceDown.delete(card);
      this.render();
      this.turnOver(card);
      await this.pause(900);
      this.announce(fmt(L().zb.youDrew, { card: faceLabel(card) }));
    } else {
      await this.fly(start, this.slotPose(seat, landCount - 1, landCount), leaving, leaving ? 'down' : null, 1150);
      s.counts[seat] = landCount;
      this.render();
      await this.pause(350);
    }
  }

  /** A card turning face up in my hand. */
  private turnOver(card: Card): void {
    const sp = this.sprites.get(card);
    if (!sp || this.feel.reduced) return;
    sp.animate([{ transform: `${sp.style.transform} scaleX(0.02)` }, { transform: sp.style.transform }], { duration: this.ms(750), easing: 'ease-out' });
  }

  private async wobble(at: Pose, face: Card | null): Promise<void> {
    if (this.feel.reduced || this.ms(650) < 60) return;
    const f = el('div', 'zb-flyer zb-wobble', this.flights);
    f.style.width = `${at.w}px`;
    f.style.height = `${at.h}px`;
    if (face) f.appendChild(makeFace(face)).classList.add('zb-fly-face');
    else f.style.backgroundImage = `url("${cardImage('back')}")`;
    const t = (r: number, sc: number): string => `translate(${at.x - at.w / 2}px, ${at.y - at.h / 2}px) rotate(${at.rot + r}deg) scale(${sc})`;
    sound.bass();
    haptic('light');
    await f
      .animate([{ transform: t(0, 1.06) }, { transform: t(-8, 1.12) }, { transform: t(8, 1.08) }, { transform: t(-6, 1.12) }, { transform: t(0, 1.08) }], { duration: this.ms(650), easing: 'ease-in-out' })
      .finished.catch(() => undefined);
    f.remove();
  }

  /** A pair flies face up from its thrower to its place on the pile, and stays exactly there. */
  private async throwPair(seat: SeatId, cards: Card[]): Promise<void> {
    const s = this.shown!;
    const mine = this.isMe(seat);
    const count = s.counts[seat]!;
    const from = cards.map((c, i) => {
      const k = mine ? s.hand.indexOf(c) : Math.max(0, count - 2 + i);
      return this.slotPose(seat, k >= 0 ? k : count - 1, count);
    });
    const i = s.pile;
    s.counts[seat] = Math.max(0, count - 2);
    if (mine) s.hand = s.hand.filter((c) => !cards.includes(c));
    this.render();
    if (mine) haptic('medium');
    await Promise.all(cards.map((c, k) => wait(this.ms(170) * k).then(() => this.fly(from[k]!, this.pilePose(i, k as 0 | 1), c, mine ? null : 'up', 950))));
    s.pile = i + 1;
    this.render();
    await this.pause(250);
  }

  /** The Zombie eats the loser's seat, then the results. */
  private async loser(seat: SeatId): Promise<void> {
    const s = this.shown!;
    s.drawer = s.target = null;
    this.render();
    await this.pause(600);
    this.eaten.add(seat);
    this.render();
    const me = this.isMe(seat);
    const at = this.seatCentre(seat);
    this.feel.play(4, 'zombie_loser', (ctx) => {
      dim(this.fx, ctx);
      this.chomp(at, ctx.reduced);
      banner(this.fx, `🧟 ${me ? L().zb.youBanner : L().zb.zombieBanner}`, 'danger', 'banner', ctx);
      shake(this.table, 'big', ctx);
      sound.bass();
      sound.trombone();
      haptic('strong');
    });
    await this.pause(2800);
    if (!this.resultsOpen && this.view?.phase === 'over') {
      this.resultsOpen = true;
      this.results(this.view);
    }
  }

  // -------------------------------------------------------------- render

  render(): void {
    const s = this.shown;
    if (!s) return;
    const v = s.view;
    const vw = this.root.clientWidth || window.innerWidth;
    const vh = this.root.clientHeight || window.innerHeight;
    this.lay = computeLayout(vw, vh, v.players, readInsets(), 14);
    this.root.style.setProperty('--card-w', `${this.lay.handW}px`);
    this.root.style.setProperty('--card-h', `${this.lay.handH}px`);
    this.root.classList.toggle('zb-exchange', s.drawer !== null);
    this.renderSeats(s);
    this.renderPile(s);
    this.renderHand(s);
    this.renderLabel(s);
    this.renderActions();
    place(this.timerBar, this.lay.timerBar);
    place(this.actionBar, this.lay.actionBar);
  }

  private renderSeats(s: Shown): void {
    const v = s.view;
    for (let seat = 0; seat < v.players; seat++) {
      if (this.isMe(seat)) continue;
      let b = this.badges[seat];
      if (!b) {
        b = el('div', 'seat compact zb-seat', this.table);
        b.innerHTML =
          '<div class="avatar"><svg class="ring" viewBox="0 0 36 36"><circle class="ring-bg" cx="18" cy="18" r="16"/><circle class="ring-fg" cx="18" cy="18" r="16"/></svg><span class="face"></span><span class="dot"></span><span class="zb-eat">🧟</span></div>' +
          '<div class="name"></div><div class="zb-count"></div><div class="chip hidden"></div><div class="stamp"></div>';
        b.dataset.seat = String(seat);
        this.badges[seat] = b;
      }
      const meta = this.seatMeta[seat]!;
      const bp = this.badgePose(seat);
      b.style.width = `${BADGE_W}px`;
      b.style.height = `${BADGE_H}px`;
      b.style.transform = `translate(${bp.x - BADGE_W / 2}px, ${bp.y - BADGE_H / 2}px) scale(${bp.scale})`;
      b.querySelector('.face')!.textContent = meta.avatar;
      b.querySelector('.name')!.textContent = meta.name.slice(0, 8);
      const count = s.counts[seat]!;
      const safe = v.safe.includes(seat) && count === 0;
      b.querySelector('.zb-count')!.textContent = safe ? `✅ ${L().zb.safe}` : cardsText(count);
      const isDrawer = s.drawer === seat;
      const isTarget = s.target === seat;
      b.classList.toggle('turn', isDrawer);
      b.classList.toggle('zb-target', isTarget);
      b.classList.toggle('zb-active', isDrawer || isTarget);
      b.classList.toggle('zb-dim', s.drawer !== null && !isDrawer && !isTarget);
      b.classList.toggle('out', safe);
      b.classList.toggle('zb-eaten', this.eaten.has(seat));
      if (!isDrawer) b.classList.remove('urgent');
      const afk = this.meta.afk[seat] === true;
      const conn = this.conn[seat];
      b.classList.toggle('bot', meta.bot || afk || conn === 'left');
      b.classList.toggle('conn-away', conn === 'away');
      b.classList.toggle('conn-left', conn === 'left');
      const chip = b.querySelector('.chip') as HTMLElement;
      if (conn === 'left') {
        chip.textContent = L().ui.leftGame;
        chip.className = 'chip chip-danger';
      } else if (conn === 'away') {
        chip.textContent = L().ui.reconnecting;
        chip.className = 'chip chip-warn';
      } else if (afk) {
        chip.textContent = L().ui.afk;
        chip.className = 'chip chip-danger';
      } else if (safe) {
        chip.textContent = `#${v.safe.indexOf(seat) + 1}`;
        chip.className = 'chip chip-gold';
      } else chip.className = 'chip hidden';
      b.setAttribute('aria-label', `${meta.name}, ${safe ? L().zb.safe : cardsText(count)}${isDrawer ? ', ' + L().zb.drawingNow : isTarget ? ', ' + L().zb.beingPicked : ''}`);
      // Their cards.
      const row = (this.backs[seat] ??= []);
      while (row.length < count) {
        const c = el('button', 'zb-back', this.table) as HTMLButtonElement;
        c.type = 'button';
        c.dataset.seat = String(seat);
        c.appendChild(makeBack());
        const i = row.length;
        c.addEventListener('click', () => this.tapBack(seat, i));
        row.push(c);
      }
      while (row.length > count) row.pop()!.remove();
      const poses = this.fanPoses(seat, count);
      const picking = this.myDraw && s.target === seat;
      row.forEach((c, i) => {
        const p = poses[i]!;
        c.dataset.slot = String(i);
        c.style.width = `${p.w}px`;
        c.style.height = `${p.h}px`;
        c.style.transform = `translate(${p.x - p.w / 2}px, ${p.y - p.h / 2}px) rotate(${p.rot}deg)`;
        c.style.zIndex = String((this.active(seat) ? 40 : 5) + i);
        c.classList.toggle('pickable', picking);
        c.classList.toggle('aimed', s.target === seat && s.aim === i);
        c.classList.toggle('zb-dim', s.drawer !== null && !this.active(seat));
        (c as HTMLButtonElement).disabled = !picking;
        c.setAttribute('aria-label', fmt(L().zb.pickLabel, { n: i + 1, name: meta.name }));
      });
    }
  }

  private tapBack(seat: SeatId, slot: number): void {
    const s = this.shown;
    if (!s || !this.myDraw || s.target !== seat) return;
    if (s.aim === slot) return this.confirm();
    // Point at it: everyone sees which one (and sees me change my mind).
    s.aim = slot;
    haptic('light');
    sound.click();
    this.send({ type: 'aim', slot });
  }

  private confirm(): void {
    const s = this.shown;
    if (!s || !this.myDraw || s.aim === null) return;
    this.send({ type: 'draw', slot: s.aim });
  }

  private renderPile(s: Shown): void {
    const v = s.view;
    const n = s.pile;
    // Pairs stay where they landed; only the top few are kept as elements.
    const first = Math.max(0, n - 10);
    const want = (n - first) * 2;
    const ids = (k: number): Card | undefined => v.pile[(first + Math.floor(k / 2)) * 2 + (k % 2)] ?? this.view?.pile[(first + Math.floor(k / 2)) * 2 + (k % 2)];
    while (this.pileCards.length > want) this.pileCards.shift()!.remove();
    for (let k = 0; k < want; k++) {
      const card = ids(k);
      let e = this.pileCards[k];
      if (!card) continue;
      if (!e || e.dataset.card !== card) {
        const next = makeFace(card);
        next.classList.add('zb-pile-card');
        if (e) e.replaceWith(next);
        else this.pileEl.appendChild(next);
        this.pileCards[k] = next;
        e = next;
      }
      const p = this.pilePose(first + Math.floor(k / 2), (k % 2) as 0 | 1);
      e.style.width = `${p.w}px`;
      e.style.height = `${p.h}px`;
      e.style.transform = `translate(${p.x - p.w / 2}px, ${p.y - p.h / 2}px) rotate(${p.rot}deg)`;
    }
    const c = this.centre();
    this.pileCount.textContent = `🪦 ${n}`;
    this.pileCount.style.transform = `translate(${c.x - 28}px, ${c.y + this.pileW() * RATIO * 0.5 + 20}px)`;
    this.pileCount.setAttribute('aria-label', fmt(L().zb.pileLabel, { n }));
  }

  private renderHand(s: Shown): void {
    const lay = this.lay;
    const u = L().zb;
    const hand = this.spectator ? [] : s.hand;
    const poses = this.handPoses(hand.length);
    const pairs = this.myPairs().flat();
    // A pair glows as soon as it's in my hand, before I may throw it.
    const glow = new Set<Card>();
    const now = this.view;
    if (now && !this.spectator && (now.step === 'deal' || (now.step === 'throw' && now.turn === this.me))) for (const p of zombie.pairsIn(hand)) for (const c of p) glow.add(c);
    const targeted = this.isMe(s.target);
    const wanted = new Set(hand);
    for (const [card, sp] of this.sprites) {
      if (wanted.has(card)) continue;
      this.sprites.delete(card);
      sp.remove();
    }
    const gathered = s.gathered === this.me && !this.spectator;
    hand.forEach((card, i) => {
      let sp = this.sprites.get(card);
      const p = poses[i]!;
      const lifted = targeted && s.aim === i;
      const c = this.handCentre();
      // In the exchange my hand comes forward a little too.
      const rise = this.isMe(s.drawer) || targeted ? 10 : 0;
      const tf = gathered
        ? `translate(${c.x - p.w / 2}px, ${c.y - p.h / 2}px)`
        : `translate(${p.x - p.w / 2}px, ${p.y - p.h / 2 - rise - (lifted ? lay.handH * 0.3 : 0)}px) rotate(${p.rot}deg)`;
      if (!sp) {
        sp = el('div', 'zb-mine-wrap', this.handLayer);
        sp.dataset.card = card;
        sp.addEventListener('click', () => this.tapMine(card));
        sp.style.transform = tf;
        this.sprites.set(card, sp);
      }
      const down = s.faceDown.has(card) || gathered;
      const paint = down ? 'back' : card;
      if (sp.dataset.paint !== paint) {
        sp.dataset.paint = paint;
        sp.innerHTML = '';
        const face = down ? makeBack() : makeFace(card);
        face.classList.add('zb-mine-face');
        sp.appendChild(face);
      }
      sp.style.width = `${p.w}px`;
      sp.style.height = `${p.h}px`;
      sp.style.transform = tf;
      sp.style.zIndex = String(10 + i);
      sp.classList.toggle('zb-paired', glow.has(card) && !down);
      sp.classList.toggle('pickable', pairs.includes(card));
      sp.classList.toggle('aimed', lifted);
      sp.classList.toggle('zb-shiver', targeted && !this.feel.reduced && !lifted);
      sp.setAttribute('role', pairs.includes(card) ? 'button' : 'img');
      sp.setAttribute('aria-label', down ? u.faceDown : `${faceLabel(card)}${pairs.includes(card) ? ', ' + u.tapToThrow : ''}`);
    });
    const note = this.handNote;
    const v = s.view;
    const safe = !this.spectator && v.safe.includes(this.me) && hand.length === 0;
    if (this.spectator || safe) {
      note.classList.remove('hidden');
      note.textContent = this.spectator ? L().ui.spectating : fmt(u.youreSafe, { place: `#${v.safe.indexOf(this.me) + 1}` });
      place(note, { x: lay.hand.x, y: lay.hand.y + lay.hand.h - lay.handH, w: lay.hand.w, h: lay.handH - 10 });
    } else note.classList.add('hidden');
  }

  private tapMine(card: Card): void {
    const pair = this.myPairs().find((p) => p.includes(card));
    if (pair) this.send({ type: 'throw', rank: pair[0]![0] });
  }

  /** Throws by itself when Auto-throw is on, once the table has caught up. */
  private maybeAutoThrow(): void {
    window.clearTimeout(this.autoTimer);
    if (!this.autoThrow || !this.myPairs().length) return;
    this.autoTimer = window.setTimeout(() => {
      if (this.myPairs().length) this.send({ type: 'throw' });
    }, this.ms(700));
  }

  private renderLabel(s: Shown): void {
    const now = this.view!;
    const u = L().zb;
    const c = this.centre();
    const chip = this.turnChip;
    place(chip, { x: this.lay.hand.x + 8, y: this.lay.hand.y - TURN_CHIP_H + 4, w: this.lay.hand.w - 16, h: TURN_CHIP_H });
    // Just above the pile, clear of an expanded seat at the top.
    const lw = Math.max(150, c.w);
    this.label.style.width = `${lw}px`;
    this.label.style.transform = `translate(${c.x - lw / 2}px, ${c.y - this.pileW() * RATIO * 0.5 - 72}px)`;
    if (now.phase !== 'play') {
      chip.classList.add('hidden');
      this.label.classList.add('hidden');
      return;
    }
    let top: string;
    let bottom: string;
    let mine = false;
    let danger = false;
    // Between two exchanges, already name the next one.
    const d0 = s.drawer ?? (now.step !== 'deal' ? now.turn : null);
    const t0 = s.target ?? (now.step !== 'deal' ? now.from : null);
    if (d0 === null || t0 === null) {
      top = u.dealPhase;
      const left = this.myPairs().length;
      bottom = this.spectator ? u.dealPhase : left ? u.throwYourPairs : u.waitThrows;
      mine = left > 0;
    } else {
      const d = d0;
      const t = t0;
      top = this.isMe(d) ? fmt(u.pickFrom, { name: this.nameOf(t) }) : this.isMe(t) ? fmt(u.pickingYou, { name: this.nameOf(d) }) : fmt(u.picking, { name: this.nameOf(d), from: this.nameOf(t) });
      if (now.step === 'throw' && this.isMe(now.turn)) {
        bottom = this.myPairs().length ? u.throwYourPair : u.drawing;
        mine = true;
      } else if (this.myDraw) {
        bottom = s.aim === null ? u.yourTurn : u.confirmPick;
        mine = true;
      } else if (this.isMe(t)) {
        bottom = u.theyPick;
        danger = true;
      } else bottom = this.isMe(d) ? L().ui.getReady : fmt(L().ui.waitingFor, { name: this.nameOf(d) });
    }
    this.label.textContent = top;
    this.label.classList.remove('hidden');
    this.label.classList.toggle('mine', mine && this.isMe(s.drawer));
    this.label.classList.toggle('danger', danger);
    chip.textContent = bottom;
    chip.classList.remove('hidden');
    chip.classList.toggle('mine', mine);
    chip.classList.toggle('zb-danger', danger);
  }

  private renderActions(): void {
    const u = L().zb;
    const bar = this.actionBar;
    bar.innerHTML = '';
    const v = this.view;
    button(bar, 'btn btn-icon', '☰', L().ui.menu).addEventListener('click', () => this.openMenu());
    if (this.meta.afk[this.me] && !this.spectator) {
      button(bar, 'btn btn-turn', L().ui.imBack, L().ui.imBack).addEventListener('click', () => this.hooks.back());
      return;
    }
    if (!v || this.spectator || v.phase !== 'play') return;
    const pairs = this.myPairs();
    bar.classList.toggle('my-turn', this.myDraw || pairs.length > 0);
    if (this.myDraw && this.shown?.aim !== null) {
      button(bar, 'btn btn-primary', `✋ ${u.takeIt}`, u.takeIt).addEventListener('click', () => this.confirm());
    } else if (pairs.length > 1) {
      const t = fmt(u.throwAll, { n: pairs.length });
      button(bar, 'btn btn-primary', `🪦 ${t}`, t).addEventListener('click', () => this.send({ type: 'throw' }));
    } else if (pairs.length === 1) {
      button(bar, 'btn btn-primary', `🪦 ${u.throwPair}`, u.throwPair).addEventListener('click', () => this.send({ type: 'throw' }));
    }
  }

  // ------------------------------------------------------------- moments

  /** Sounds, stamps and banners, timed to land with the step they belong to. They never move cards. */
  private moment(e: GameEvent): void {
    const u = L().zb;
    const seat = typeof e.seat === 'number' ? e.seat : null;
    switch (e.type) {
      case 'jester':
        window.setTimeout(() => this.showJester(e as JesterEvent), this.ms(900));
        break;
      case 'turn':
        if (this.isMe(seat)) {
          this.lastTickSecond = -1;
          window.setTimeout(() => this.feel.play(1, 'your_turn', () => sound.chime()), this.ms(1400));
        }
        break;
      case 'drawn_card':
        // Mine only. The Zombie's grin plays on my screen alone; everyone else saw a normal draw.
        if (isZ(e.card as Card)) {
          window.setTimeout(
            () =>
              this.feel.play(3, 'zombie_drawn', (ctx) => {
                dim(this.fx, ctx);
                banner(this.fx, `🧟 ${u.gotZombie}`, 'danger', 'banner', ctx);
                shake(this.table, 'big', ctx);
                sound.bass();
                haptic('strong');
                this.announce(u.gotZombie);
              }),
            this.ms(3300),
          );
        }
        break;
      case 'drew':
        if (this.isMe(e.from as SeatId) && this.shown && isZ(this.shown.hand[e.slot as number])) {
          window.setTimeout(
            () =>
              this.feel.play(2, 'zombie_gone', (ctx) => {
                banner(this.fx, u.zombieGone, 'good', 'pop', ctx, this.handCentre());
                sound.chime();
              }),
            this.ms(2600),
          );
        }
        break;
      case 'pair':
        window.setTimeout(() => this.stamp(seat!, u.stamps.pair, 'good'), this.ms(400));
        break;
      case 'safe':
        window.setTimeout(() => {
          const at = this.seatCentre(seat!);
          this.feel.play(2, 'safe', (ctx) => {
            banner(this.fx, this.isMe(seat) ? u.stamps.youSafe : u.stamps.safe, 'good', 'pop', ctx, at);
            burst(this.fx, at.x, at.y, 18, 'good', ctx, 90);
            sound.chime();
          });
        }, this.ms(900));
        break;
      case 'too_slow':
        this.stamp(seat!, L().ui.tooSlow, 'danger');
        break;
      case 'afk':
        if (seat === this.me) haptic('error');
        break;
      default:
    }
  }

  private chomp(at: { x: number; y: number }, reduced: boolean): void {
    const z = el('div', 'zb-chomp', this.fx);
    z.textContent = '🧟';
    z.style.left = `${at.x}px`;
    z.style.top = `${at.y}px`;
    if (!reduced) {
      z.animate(
        [
          { transform: 'translate(-50%, -50%) scale(0.2) rotate(-30deg)', opacity: 0 },
          { transform: 'translate(-50%, -50%) scale(1.6) rotate(8deg)', opacity: 1, offset: 0.35 },
          { transform: 'translate(-50%, -50%) scale(1.2) rotate(-6deg)', offset: 0.5 },
          { transform: 'translate(-50%, -50%) scale(1.5) rotate(6deg)', offset: 0.65 },
          { transform: 'translate(-50%, -50%) scale(1.3) rotate(0deg)', opacity: 1, offset: 0.85 },
          { transform: 'translate(-50%, -50%) scale(1.3)', opacity: 0 },
        ],
        { duration: 2400, easing: 'ease-out', fill: 'forwards' },
      );
    }
    window.setTimeout(() => z.remove(), 2500);
  }

  private announce(text: string): void {
    this.live.textContent = text;
  }

  private stamp(seat: SeatId, text: string, role: ColourRole): void {
    if (!this.lay) return;
    const at = this.seatCentre(seat);
    this.feel.play(1, 'stamp', (ctx) => banner(this.fx, text, role, 'pop', ctx, at));
  }

  private showJester(e: JesterEvent): void {
    const text = jesterText(e);
    if (!text || !this.lay) return;
    const j = this.jesterEl;
    const lay = this.lay;
    this.stopEmoji?.();
    this.stopEmoji = e.emoji ? playEmoji(this.jesterEmoji, e.emoji) : null;
    j.className = `jester mood-${e.mood} eyes-${EYES[e.mood]}`;
    this.jesterBubble.textContent = text;
    const w = Math.min(lay.vw - 24, 520);
    j.style.width = `${w}px`;
    j.style.left = `${(lay.vw - w) / 2}px`;
    j.style.top = `${Math.max(4, lay.hand.y - JESTER_BAND + 10)}px`;
    void j.offsetWidth;
    j.classList.add('show');
    window.clearTimeout(this.jesterTimer);
    const ms = Math.min(6000, 2600 + text.length * 35);
    this.jesterTimer = window.setTimeout(() => {
      j.classList.remove('show');
      j.classList.add('leaving');
      window.setTimeout(() => {
        if (!j.classList.contains('show')) {
          j.className = 'jester hidden';
          this.stopEmoji?.();
          this.stopEmoji = null;
        }
      }, 350);
    }, ms);
  }

  // ------------------------------------------------------------- results

  private results(v: View): void {
    const u = L().zb;
    const placings = v.placings ?? [];
    const loser = v.loser;
    const st = v.stats;
    const name = (s: SeatId): string => `${this.seatMeta[s]!.avatar} ${this.nameOf(s)}`;
    const o = this.overlay;
    o.className = 'overlay results zb-results';
    o.innerHTML = '';
    const card = el('div', 'sheet results-sheet', o);
    el('h2', '', card).textContent = `${L().ui.results} · ${u.title}`;
    el('p', 'zb-results-sub', card).textContent = loser === null ? '' : this.isMe(loser) ? `🧟 ${u.youLose}` : `🧟 ${fmt(u.theyLose, { name: this.nameOf(loser) })}`;
    const list = el('ol', 'standings zb-standings', card);
    placings.forEach((seat, k) => {
      const lost = seat === loser;
      const li = el('li', `standing${k === 0 ? ' winner' : ''}${lost ? ' zb-lost' : ''}`, list);
      li.style.animationDelay = `${k * 90}ms`;
      el('span', 'medal', li).textContent = lost ? '🧟' : k === 0 ? '🥇' : k === 1 ? '🥈' : k === 2 ? '🥉' : String(k + 1);
      el('span', 'who', li).textContent = name(seat);
      el('span', 'pts', li).textContent = lost ? u.zombie : fmt(u.pairsN, { n: v.pairs[seat] ?? 0 });
    });
    if (st) {
      const stats = el('ul', 'zb-stats', card);
      const most = (xs: number[]): SeatId => xs.reduce((best, x, i) => (x > xs[best]! ? i : best), 0);
      const line = (text: string): void => void (el('li', '', stats).textContent = text);
      line(fmt(u.statMoves, { n: st.moves }));
      line(fmt(u.statDealt, { name: name(st.dealtTo) }));
      const held = most(st.held);
      if (st.held[held]! > 0) line(fmt(u.statHeld, { name: name(held), n: st.held[held]! }));
      const hot = most(st.drawnFrom);
      if (st.drawnFrom[hot]! >= 2) line(fmt(u.statHot, { name: name(hot), n: st.drawnFrom[hot]! }));
      const pairs = most(v.pairs);
      line(fmt(u.statPairs, { name: name(pairs), n: v.pairs[pairs]! }));
      line(fmt(u.statDraws, { n: v.draws }));
    }
    this.rematchEl = el('div', 'rematch', card);
    renderRematch(this.rematchEl, this.rematch);
    const actions = el('div', 'sheet-actions', card);
    if (this.isHost && this.hooks.playAgain) {
      button(actions, 'btn btn-primary', L().ui.playAgain, L().ui.playAgain).addEventListener('click', () => {
        this.resultsOpen = false;
        o.className = 'overlay hidden';
        this.hooks.playAgain!();
      });
    }
    button(actions, 'btn btn-secondary', L().ui.leave, L().ui.leave).addEventListener('click', () => this.hooks.exit());
    this.feel.play(4, 'results', (ctx) => {
      if (!this.isMe(loser)) {
        confetti(this.fx, this.lay.vw, ctx);
        sound.fanfare();
      } else sound.trombone();
    });
  }

  private openMenu(): void {
    const o = this.overlay;
    o.className = 'overlay';
    o.innerHTML = '';
    const sheet = el('div', 'sheet', o);
    el('h2', '', sheet).textContent = `🧟 ${L().zb.title}`;
    const help = el('ul', 'l7-help', sheet);
    for (const t of L().zb.help) el('li', '', help).textContent = t;
    // Auto-throw: pairs go to the pile by themselves.
    const b = button(sheet, 'menu-row', '', '');
    b.setAttribute('role', 'switch');
    b.setAttribute('aria-checked', String(this.autoThrow));
    b.setAttribute('aria-label', L().zb.autoThrow);
    b.innerHTML = `<span></span><span class="switch${this.autoThrow ? ' on' : ''}"><span class="knob"></span></span>`;
    b.firstElementChild!.textContent = L().zb.autoThrow;
    b.addEventListener('click', () => {
      this.autoThrow = !this.autoThrow;
      try {
        localStorage.setItem(AUTO_KEY, this.autoThrow ? '1' : '0');
      } catch {
        /* private mode */
      }
      sound.toggle();
      b.querySelector('.switch')!.classList.toggle('on', this.autoThrow);
      b.setAttribute('aria-checked', String(this.autoThrow));
      this.maybeAutoThrow();
    });
    const actions = el('div', 'sheet-actions', sheet);
    button(actions, 'btn btn-secondary', L().ui.leave, L().ui.leave).addEventListener('click', () => this.hooks.exit());
    button(actions, 'btn btn-primary', L().ui.close, L().ui.close).addEventListener('click', () => {
      o.className = 'overlay hidden';
    });
  }

  // ---------------------------------------------------------------- tick

  private tick = (): void => {
    requestAnimationFrame(this.tick);
    const v = this.view;
    if (!v || !this.meta.deadline || v.phase !== 'play') {
      this.timerFill.style.transform = 'scaleX(0)';
      return;
    }
    const left = Math.max(0, this.meta.deadline - Date.now());
    const frac = Math.max(0, Math.min(1, left / this.turnTotal));
    const mine = !this.spectator && (v.step === 'deal' ? zombie.pairsIn(v.hand).length > 0 : v.turn === this.me);
    this.timerFill.style.transform = `scaleX(${mine ? frac : 0})`;
    this.timerBar.classList.toggle('urgent', mine && left <= 5000);
    for (const b of this.badges) {
      if (!b) continue;
      const isTurn = v.step !== 'deal' && Number(b.dataset.seat) === v.turn;
      b.classList.toggle('urgent', isTurn && left <= 5000);
      const ring = b.querySelector('.ring-fg') as SVGCircleElement | null;
      if (ring) ring.style.strokeDashoffset = String(isTurn ? 100.5 * (1 - frac) : 100.5);
    }
    if (mine) {
      const sec = Math.ceil(left / 1000);
      if (left <= 5000 && sec !== this.lastTickSecond && sec > 0) {
        this.lastTickSecond = sec;
        sound.tick();
      }
    }
  };
}

// ---------------------------------------------------------------- helpers

const cardsText = (n: number): string => (n === 1 ? L().zb.oneCard : fmt(L().zb.cards, { n }));

function el(tag: string, cls: string, parent: HTMLElement): HTMLElement {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  parent.appendChild(e);
  return e;
}

function button(parent: HTMLElement, cls: string, text: string, label: string): HTMLButtonElement {
  const b = document.createElement('button');
  b.type = 'button';
  b.className = cls;
  b.textContent = text;
  if (label) b.setAttribute('aria-label', label);
  parent.appendChild(b);
  return b;
}

function place(e: HTMLElement, b: { x: number; y: number; w: number; h: number }): void {
  e.style.left = `${b.x}px`;
  e.style.top = `${b.y}px`;
  e.style.width = `${b.w}px`;
  e.style.height = `${b.h}px`;
}

function readInsets(): { top: number; right: number; bottom: number; left: number } {
  const cs = getComputedStyle(document.documentElement);
  const n = (v: string): number => parseFloat(cs.getPropertyValue(v)) || 0;
  return { top: n('--sat'), right: n('--sar'), bottom: n('--sab'), left: n('--sal') };
}
