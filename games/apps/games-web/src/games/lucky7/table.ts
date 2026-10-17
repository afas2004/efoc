// The Lucky 7 table (docs/table-feel.md). Every player's three face-down
// cards sit on the felt in front of their seat; the deck, Discard and Used
// piles and the card in play sit in the middle. Holding a card, your own
// cards and the Discard pile light up: tap a card to swap into it, tap
// Discard to throw it away. Powers pick their targets on the table (or in a
// focus sheet when cards are small).
//
// Tracking cards is the game, so every move is animated step by step from
// where the card was to where it lands: a swap flies the new card into the
// slot and the old one, flipping face up, onto Discard; a Q's swap crosses
// two cards between players; a K drops onto its card; a 10 gathers and
// re-deals (never showing the real new order); a peek lifts the card being
// looked at. Destinations keep their old look until the flight lands. The
// reveal flips the seats one by one, lowest total last.

import { lucky7, type Card, type GameEvent, type SeatId } from '@efoc/engine';
import { haptic } from '../../bridge';
import { banner, burst, confetti, dim, shake, type ColourRole } from '../../feel/effects';
import { jesterText, type Humour, type JesterEvent } from '../../feel/jester';
import { EYES, JESTER_SVG, playEmoji, preloadEmoji } from '../../feel/jesterArt';
import { setMuted, sound, unlockAudio } from '../../feel/sound';
import { FeelQueue } from '../../feel/tiers';
import { L, fmt } from '../../strings';
import { cardImage, cardLabel, makeBack, makeCard } from '../../table/cardFace';
import { renderRematch, type RematchInfo } from '../../table/rematch';

type View = lucky7.LuckyView;
type Move = lucky7.LuckyMove;
type Target = lucky7.Target;
type Power = lucky7.Power;

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

/** A seat's connection, online only: reconnecting greys it out, left shows a bot took over. */
export type Conn = 'online' | 'away' | 'left' | 'bot';

/** What a tap on a card or seat means right now. */
type Mode = 'none' | 'qMine' | 'qTheirs' | 'lock' | 'unlock' | 'shuffle' | 'peek';

interface Box {
  x: number;
  y: number;
  w: number;
  h: number;
}

interface Geo {
  vw: number;
  vh: number;
  /** My cards. */
  cw: number;
  mine: Box;
  /** Opponents: badge and three card boxes, by seat (mine is empty). */
  opp: { chip: Box; cards: Box[] }[];
  /** Opponents' card width; under 40 px a tap opens the focus sheet. */
  ocw: number;
  piles: Box;
  pw: number;
  play: Box;
  prompt: Box;
  timer: Box;
  bar: Box;
}

const SLOTS = lucky7.SLOTS;
const PEEK_RESULT_MS = 3500;
const FLY_MS = 460;
const RATIO = 1.4;
const key = (seat: SeatId, slot: number): string => `${seat}:${slot}`;
const wait = (ms: number): Promise<void> => new Promise((r) => setTimeout(r, ms));
const clamp = (v: number, lo: number, hi: number): number => Math.max(lo, Math.min(hi, v));

/** Where opponents sit around the felt, by how many there are (as computeLayout). */
const SPOTS: Record<number, string[]> = {
  1: ['T'],
  2: ['TL', 'TR'],
  3: ['L', 'T', 'R'],
  4: ['L', 'TL', 'TR', 'R'],
  5: ['L', 'TL', 'T', 'TR', 'R'],
  6: ['LD', 'LU', 'TL', 'TR', 'RU', 'RD'],
  7: ['LD', 'LU', 'TL', 'T', 'TR', 'RU', 'RD'],
};

/** The whole table's geometry. Pure: viewport in, boxes out. */
export function luckyGeo(vw: number, vh: number, players: number, inset: { top: number; right: number; bottom: number; left: number }): Geo {
  const left = inset.left + 8;
  const right = vw - inset.right - 8;
  const innerW = right - left;
  const top = inset.top + 8;
  const bar: Box = { x: left, y: vh - inset.bottom - 64, w: innerW, h: 60 };
  const timer: Box = { x: left, y: bar.y - 8, w: innerW, h: 5 };
  const cw = Math.round(clamp(Math.min(innerW / 4.6, vh / 8.5), 52, 104));
  const ch = Math.round(cw * RATIO);
  const mine: Box = { x: left, y: timer.y - 22 - ch, w: innerW, h: ch };
  const prompt: Box = { x: left, y: mine.y - 40, w: innerW, h: 34 };
  const R: Box = { x: left, y: top, w: innerW, h: prompt.y - 6 - top };

  const n = players - 1;
  const spots = SPOTS[n] ?? [];
  const topRow = spots.filter((s) => s[0] === 'T').length;
  const gap = 4;
  let ocw = cw * (n === 1 ? 0.85 : n === 2 ? 0.72 : n <= 4 ? 0.6 : 0.45);
  ocw = Math.min(ocw, ((innerW - (topRow - 1) * 12) / Math.max(1, topRow) - 2 * gap) / 3);
  ocw = Math.round(clamp(ocw, 28, 76));
  const och = Math.round(ocw * RATIO);
  const chipH = 26;
  const gw = Math.max(3 * ocw + 2 * gap, 76);
  const gh = chipH + 3 + och;
  const centreOf = (spot: string): { x: number; y: number } => {
    const topX = (): number => {
      const tops = spots.filter((s) => s[0] === 'T');
      const i = tops.indexOf(spot);
      // Evenly spread, so neighbours never touch.
      return clamp(left + (innerW / tops.length) * (i + 0.5), left + gw / 2, right - gw / 2);
    };
    if (spot[0] === 'T') return { x: topX(), y: R.y + gh / 2 };
    const x = spot[0] === 'L' ? left + gw / 2 : right - gw / 2;
    const y = spot.length === 1 ? sideY(0.62) : spot[1] === 'U' ? R.y + R.h * 0.42 : sideY(0.8);
    return { x, y: Math.min(y, R.y + R.h - gh / 2) };
  };
  // Piles in the middle; smaller when side seats share their height.
  const sidesBeside = n >= 6;
  let pw = Math.min(64, cw * 0.66);
  if (sidesBeside) pw = Math.min(pw, (innerW - 2 * gw - 36) / 3);
  pw = Math.round(clamp(pw, 30, 64));
  const ph = Math.round(pw * RATIO);
  const pilesW = 3 * pw + 2 * 12;
  const pilesY = R.y + R.h * (n >= 3 ? 0.36 : 0.4) - ph / 2;
  const piles: Box = { x: Math.round(vw / 2 - pilesW / 2), y: Math.round(Math.max(pilesY, n === 0 ? R.y : R.y + gh + 22)), w: pilesW, h: ph };
  const hw = Math.round(clamp(pw * 1.3, 44, 86));
  const play: Box = { x: Math.round(vw / 2 - hw / 2), y: piles.y + ph + 40, w: hw, h: Math.round(hw * RATIO) };
  // Seats level with the middle sit below the card in play when they'd reach it.
  const sideY = (frac: number): number => {
    const y = R.y + R.h * frac;
    const reaches = gw * 2 + hw + 16 > innerW;
    return reaches ? Math.max(y, play.y + play.h + 22 + gh / 2) : y;
  };

  const opp: Geo['opp'] = Array.from({ length: players }, () => ({ chip: { x: 0, y: 0, w: 0, h: 0 }, cards: [] }));
  spots.forEach((spot, r) => {
    const seatRel = r + 1;
    const c = centreOf(spot);
    const x0 = c.x - gw / 2;
    const y0 = c.y - gh / 2;
    const rowW = 3 * ocw + 2 * gap;
    const cards: Box[] = [];
    for (let i = 0; i < SLOTS; i++) cards.push({ x: Math.round(c.x - rowW / 2 + i * (ocw + gap)), y: Math.round(y0 + chipH + 3), w: ocw, h: och });
    opp[seatRel] = { chip: { x: Math.round(x0), y: Math.round(y0), w: Math.round(gw), h: chipH }, cards };
  });
  return { vw, vh, cw, mine, opp, ocw, piles, pw, play, prompt, timer, bar };
}

export class LuckySevenTable {
  readonly feel = new FeelQueue();
  private geo!: Geo;
  private view: View | null = null;
  private prev: View | null = null;
  private meta: UpdateMeta = { deadline: null, afk: [] };
  private mode: Mode = 'none';
  private qMine: number | null = null;
  /** A move sent and not yet confirmed by the host: no double taps. */
  private sent = false;
  /** My own cards, face up, during a J (null where locked). */
  private ownPeek: { cards: (Card | null)[]; until: number } | null = null;
  /** A card I peeked at, shown face up in its slot for a moment. */
  private peekShown: { target: Target; card: Card; until: number } | null = null;
  private turnTotal = 20000;
  private lastTickSecond = -1;
  private resultsOpen = false;
  private focusSeat: SeatId | null = null;
  private conn: Conn[] = [];
  private rematch: RematchInfo | null = null;
  private rematchEl: HTMLElement | null = null;

  // Animation: what hasn't landed yet keeps its old look.
  private anim: Promise<void> = Promise.resolve();
  private hideSlots = new Set<string>();
  private hideLocks = new Set<string>();
  private hidePlay = false;
  private discardLag = 0;
  private usedLag = 0;
  private lifted = new Set<string>();
  /** Seats flipped face up in the final reveal. */
  private revealedSeats = new Set<SeatId>();

  // DOM
  private table: HTMLElement;
  private chips: HTMLElement[] = [];
  private cardEls = new Map<string, HTMLElement>();
  private pilesEl: HTMLElement;
  private deckEl: HTMLElement;
  private discardEl: HTMLElement;
  private usedEl: HTMLElement;
  private playEl: HTMLElement;
  private mineEl: HTMLElement;
  private slotEls: HTMLElement[] = [];
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
  private focusEl: HTMLElement;
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
    root.className = 'efoc-root felt-lucky7';
    this.table = el('div', 'table l7-table', root);
    el('div', 'l7-felt', this.table);
    this.pilesEl = el('div', 'l7-piles', this.table);
    this.deckEl = el('button', 'l7-pile l7-deck', this.pilesEl);
    this.discardEl = el('button', 'l7-pile l7-discard', this.pilesEl);
    this.usedEl = el('div', 'l7-pile l7-used', this.pilesEl);
    this.deckEl.addEventListener('click', () => this.tapDeck());
    this.discardEl.addEventListener('click', () => this.tapDiscard());
    this.playEl = el('div', 'l7-drawn l7-play hidden', this.table);
    this.mineEl = el('div', 'l7-mine', this.table);
    for (let i = 0; i < SLOTS; i++) {
      const s = el('button', 'l7-slot l7-card mine', this.mineEl) as HTMLButtonElement;
      s.type = 'button';
      s.dataset.seat = String(me);
      s.dataset.slot = String(i);
      s.addEventListener('click', () => this.tapCard({ seat: me, slot: i }));
      this.slotEls.push(s);
      this.cardEls.set(key(me, i), s);
    }
    this.turnChip = el('div', 'turn-chip l7-prompt hidden', this.table);
    this.turnChip.setAttribute('aria-live', 'polite');
    this.timerBar = el('div', 'timer-bar', this.table);
    this.timerFill = el('div', 'timer-fill', this.timerBar);
    this.actionBar = el('div', 'action-bar l7-actions', this.table);
    this.flights = el('div', 'l7-flights', root);
    this.fx = el('div', 'fx-layer', root);
    this.jesterEl = el('div', 'jester hidden', root);
    this.jesterEl.setAttribute('aria-live', 'polite');
    const figure = el('div', 'jester-figure', this.jesterEl);
    figure.innerHTML = JESTER_SVG;
    this.jesterEmoji = el('div', 'jester-emoji', figure);
    this.jesterBubble = el('div', 'jester-bubble', this.jesterEl);
    preloadEmoji(['laugh', 'explode', 'party', 'cool', 'fire', 'grimace', 'eyeroll']);
    this.focusEl = el('div', 'overlay l7-focus hidden', root);
    this.overlay = el('div', 'overlay hidden', root);
    this.live = el('div', 'sr-only', root);
    this.live.setAttribute('aria-live', 'assertive');
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

  // ------------------------------------------------------------- updates

  /** New state from the host, with the events that produced it (only mine of the private ones). */
  update(view: View, events: GameEvent[], meta: UpdateMeta): void {
    const prevDeadline = this.meta.deadline;
    this.prev = this.view;
    this.view = view;
    this.meta = meta;
    this.sent = false;
    if (meta.deadline && meta.deadline !== prevDeadline) this.turnTotal = Math.max(1000, meta.deadline - Date.now());
    // The host started another match: close the results.
    if (view.phase === 'play' && (this.resultsOpen || this.revealedSeats.size)) {
      this.resultsOpen = false;
      this.revealedSeats.clear();
      this.overlay.className = 'overlay hidden';
      this.ownPeek = null;
      this.peekShown = null;
    }
    if (view.turn !== this.me || view.phase !== 'play') this.resetMode();
    else if (view.step === 'peek' && this.mode !== 'peek') this.mode = this.ownPeek ? 'none' : 'peek';
    else if (view.step !== 'act' && this.mode !== 'peek') this.resetMode();
    const mine = events.filter((e) => e.to === undefined || e.to === this.me);
    // Set up what must wait for its flight before drawing the new state.
    this.planFlights(mine, this.prev, view);
    for (const e of mine) this.moment(e, view);
    this.render();
  }

  /** "Who's in for another?" on the results screen (online tables). */
  setRematch(info: RematchInfo | null): void {
    this.rematch = info;
    if (this.rematchEl?.isConnected) renderRematch(this.rematchEl, info);
  }

  /** Who is connected (online tables only); redraws the seats when it changes. */
  setConnection(conn: Conn[]): void {
    this.conn = conn.slice();
    if (this.view) this.render();
  }

  /** A short note over the table, e.g. "Mei is now the host". */
  notice(text: string): void {
    if (!this.geo) return;
    const p = this.geo.piles;
    this.feel.play(2, 'notice', (ctx) => banner(this.fx, text, 'info', 'pop', ctx, { x: p.x + p.w / 2, y: p.y - 10 }));
  }

  /** The host turned a move down (stale or illegal): try again. */
  reject(reason: string): void {
    this.sent = false;
    this.feel.play(1, 'rejected', (ctx) => banner(this.fx, reason, 'danger', 'pop', ctx, this.mineCentre()));
    haptic('error');
    this.render();
  }

  private resetMode(): void {
    this.mode = 'none';
    this.qMine = null;
    this.closeFocus();
  }

  private send(m: Move): void {
    if (this.sent) return;
    this.sent = true;
    unlockAudio();
    sound.click();
    this.mode = 'none';
    this.qMine = null;
    this.closeFocus();
    this.hooks.move(m);
    this.render();
  }

  private get myTurn(): boolean {
    const v = this.view;
    return !!v && v.phase === 'play' && v.turn === this.me && !this.sent;
  }

  // ------------------------------------------------------------ flights

  private rectOf(e: Element): DOMRect {
    return e.getBoundingClientRect();
  }

  /** Where the card in play sits (from the layout: the spot hides between turns). */
  private playRect(): DOMRect {
    const b = this.geo.play;
    return new DOMRect(b.x, b.y, b.w, b.h);
  }

  private slotEl(t: Target): HTMLElement | undefined {
    return this.cardEls.get(key(t.seat, t.slot));
  }

  /** The card in play, as the table showed it: its face if I could see it. */
  private heldFace(prev: View | null): Card | null {
    return prev?.drawn ?? null;
  }

  /** Animation steps waiting their turn. */
  private backlog = 0;

  /** Runs animation steps one after another. A backlog (moves arriving faster than cards can fly) speeds them up, then skips them. */
  private chain(step: () => Promise<void>): void {
    this.backlog++;
    this.anim = this.anim
      .then(step)
      .catch(() => undefined)
      .then(() => {
        this.backlog--;
        this.render();
      });
  }

  /**
   * One card flying from one box to another along an arc, optionally
   * flipping. Resolves when it lands.
   */
  private fly(from: DOMRect, to: DOMRect, face: Card | null, flip: 'up' | 'down' | null, o: { ms?: number; bend?: number } = {}): Promise<void> {
    const reduced = this.feel.reduced;
    // Catching up: quicker flights, and none at all far behind.
    if (this.backlog > 8) return Promise.resolve();
    const ms = reduced || this.backlog > 3 ? 160 : o.ms ?? FLY_MS;
    const f = el('div', 'l7-flyer', this.flights);
    f.style.left = `${from.left}px`;
    f.style.top = `${from.top}px`;
    f.style.width = `${from.width}px`;
    f.style.height = `${from.height}px`;
    const inner = el('div', 'l7-flip', f);
    const front = el('div', 'l7-face front', inner);
    const back = el('div', 'l7-face back', inner);
    if (face) front.style.backgroundImage = `url("${cardImage(face)}")`;
    back.style.backgroundImage = `url("${cardImage('back')}")`;
    // Which side shows at the start and at the end.
    const startUp = flip === 'down' ? true : flip === 'up' ? false : !!face;
    const endUp = flip === 'up' ? true : flip === 'down' ? false : !!face;
    const dx = to.left - from.left;
    const dy = to.top - from.top;
    const sx = to.width / from.width;
    const sy = to.height / from.height;
    const bend = o.bend ?? 1;
    const lift = reduced ? 0 : Math.min(60, 18 + Math.hypot(dx, dy) * 0.12) * bend;
    const tilt = reduced ? 0 : (dx >= 0 ? 8 : -8) * bend;
    const move = f.animate(
      [
        { transform: 'translate(0px, 0px) scale(1, 1) rotate(0deg)', offset: 0 },
        { transform: `translate(${dx * 0.5}px, ${dy * 0.5 - lift}px) scale(${(1 + sx) / 2 + 0.1}, ${(1 + sy) / 2 + 0.1}) rotate(${tilt}deg)`, offset: 0.5 },
        { transform: `translate(${dx}px, ${dy}px) scale(${sx}, ${sy}) rotate(0deg)`, offset: 1 },
      ],
      { duration: ms, easing: 'cubic-bezier(0.3, 0.7, 0.35, 1)', fill: 'forwards' },
    );
    const r0 = startUp ? 0 : 180;
    const r1 = endUp ? 0 : 180;
    inner.animate([{ transform: `rotateY(${r0}deg)` }, { transform: `rotateY(${r1}deg)` }], { duration: ms, easing: 'ease-in-out', fill: 'forwards' });
    return move.finished.then(() => {
      f.remove();
      sound.thud(0);
    }, () => f.remove());
  }

  /** The 10's shuffle: cards gather, spin together, and deal back. Shows nothing of the new order. */
  private async shuffleSeat(seat: SeatId, slots: number[]): Promise<void> {
    const els = slots.map((i) => this.slotEl({ seat, slot: i })).filter((x): x is HTMLElement => !!x);
    if (!els.length) return;
    const rects = els.map((e) => this.rectOf(e));
    const mid = rects[Math.floor(rects.length / 2)]!;
    slots.forEach((i) => this.hideSlots.add(key(seat, i)));
    this.render();
    await Promise.all(rects.map((r) => this.fly(r, mid, null, null, { ms: 320, bend: 0.4 })));
    // A spinning stack while they mix.
    const stack = el('div', 'l7-flyer l7-stack', this.flights);
    stack.style.left = `${mid.left}px`;
    stack.style.top = `${mid.top}px`;
    stack.style.width = `${mid.width}px`;
    stack.style.height = `${mid.height}px`;
    stack.style.backgroundImage = `url("${cardImage('back')}")`;
    if (!this.feel.reduced && this.backlog <= 3) await stack.animate([{ transform: 'rotate(0)' }, { transform: 'rotate(-14deg) scale(1.1)' }, { transform: 'rotate(14deg) scale(1.1)' }, { transform: 'rotate(0)' }], { duration: 520 }).finished;
    stack.remove();
    await Promise.all(rects.map((r) => this.fly(mid, r, null, null, { ms: 320, bend: 0.4 })));
    slots.forEach((i) => this.hideSlots.delete(key(seat, i)));
  }

  /**
   * Turns this entry's public events into flights. What a flight carries
   * keeps its old look (hidden slot, lagging pile) until it lands. Flights
   * use where things are on screen now, after this update is drawn.
   */
  private planFlights(events: GameEvent[], prev: View | null, v: View): void {
    const held = this.heldFace(prev);
    for (const e of events) {
      const seat = typeof e.seat === 'number' ? e.seat : null;
      switch (e.type) {
        case 'drew': {
          this.hidePlay = true;
          const fromDeck = e.from === 'deck';
          const face = fromDeck ? null : (e.card as Card);
          this.chain(async () => {
            const src = this.rectOf(fromDeck ? this.deckEl : this.discardEl);
            this.render();
            const dst = this.playRect();
            sound.slide();
            // My own draw turns face up as it reaches me.
            const mineFace = fromDeck && seat === this.me ? this.view?.drawn ?? null : face;
            await this.fly(src, dst, mineFace, fromDeck && mineFace ? 'up' : null);
            this.hidePlay = false;
          });
          break;
        }
        case 'swapped': {
          const t = { seat: seat!, slot: e.slot as number };
          this.hideSlots.add(key(t.seat, t.slot));
          this.discardLag++;
          const out = e.out as Card;
          this.chain(async () => {
            const slot = this.slotEl(t);
            if (!slot) return;
            const at = this.rectOf(slot);
            const play = this.playRect();
            const pile = this.rectOf(this.discardEl);
            await Promise.all([this.fly(play, at, held, held ? 'down' : null), this.fly(at, pile, out, 'up', { bend: -0.6 })]);
            this.hideSlots.delete(key(t.seat, t.slot));
            this.discardLag--;
          });
          break;
        }
        case 'discarded': {
          this.discardLag++;
          const card = e.card as Card;
          this.chain(async () => {
            await this.fly(this.playRect(), this.rectOf(this.discardEl), card, held ? null : 'up');
            this.discardLag--;
          });
          break;
        }
        case 'power': {
          const card = e.card as Card;
          const p = e.power as Power;
          const t = (e.target ?? null) as Target | null;
          if (p === 'K' && t) {
            // The K drops onto the card it locks.
            this.hideLocks.add(key(t.seat, t.slot));
            this.chain(async () => {
              const slot = this.slotEl(t);
              if (slot) await this.fly(this.playRect(), this.rectOf(slot), card, null);
              this.hideLocks.delete(key(t.seat, t.slot));
            });
            break;
          }
          // Every other power goes to Used first.
          this.usedLag++;
          this.chain(async () => {
            await this.fly(this.playRect(), this.rectOf(this.usedEl), card, null);
            this.usedLag--;
          });
          if (p === 'Q' && t) {
            const a: Target = { seat: seat!, slot: e.mine as number };
            this.hideSlots.add(key(a.seat, a.slot));
            this.hideSlots.add(key(t.seat, t.slot));
            this.chain(async () => {
              const ea = this.slotEl(a);
              const eb = this.slotEl(t);
              if (ea && eb) {
                const ra = this.rectOf(ea);
                const rb = this.rectOf(eb);
                sound.slide();
                await Promise.all([this.fly(ra, rb, null, null, { ms: 620 }), this.fly(rb, ra, null, null, { ms: 620, bend: -1 })]);
              }
              this.hideSlots.delete(key(a.seat, a.slot));
              this.hideSlots.delete(key(t.seat, t.slot));
            });
          } else if (p === '9' && t) {
            // The broken lock's K goes to Used too.
            this.usedLag++;
            const k = v.used[v.used.length - 1] ?? null; // the 9 went first, then the K
            this.chain(async () => {
              const slot = this.slotEl(t);
              if (slot && k) await this.fly(this.rectOf(slot), this.rectOf(this.usedEl), k, null, { bend: -0.5 });
              this.usedLag--;
            });
          } else if (p === 'T') {
            const target = (t?.seat ?? seat)!;
            const open = [0, 1, 2].filter((i) => !v.locked[target]![i]);
            this.chain(() => this.shuffleSeat(target, open));
          }
          break;
        }
        case 'peeked': {
          // Everyone sees which card is being looked at, never its face.
          const t = e.target as Target;
          this.chain(async () => {
            this.lifted.add(key(t.seat, t.slot));
            this.render();
            await wait(this.feel.reduced || this.backlog > 3 ? 300 : 1300);
            this.lifted.delete(key(t.seat, t.slot));
          });
          break;
        }
        case 'revealed': {
          this.chain(() => this.reveal(v));
          break;
        }
        default:
      }
    }
  }

  /** Seats flip face up one by one, the lowest total last; then results. */
  private async reveal(v: View): Promise<void> {
    const totals = v.totals ?? [];
    const order = Array.from({ length: v.players }, (_, i) => i).sort((a, b) => totals[b]! - totals[a]! || b - a);
    await wait(400);
    for (const seat of order) {
      const cards = v.revealed?.[seat] ?? [];
      const flips = cards.map((c, i) => {
        const e = this.slotEl({ seat, slot: i });
        if (!e) return Promise.resolve();
        const r = this.rectOf(e);
        this.hideSlots.add(key(seat, i));
        return this.fly(r, r, c, 'up', { ms: 420, bend: 0.3 });
      });
      this.render();
      await Promise.all(flips);
      cards.forEach((_, i) => this.hideSlots.delete(key(seat, i)));
      this.revealedSeats.add(seat);
      this.render();
      sound.thud(1);
      await wait(this.feel.reduced ? 80 : 160);
    }
    await wait(700);
    if (!this.resultsOpen && this.view?.phase === 'over') {
      this.resultsOpen = true;
      this.results(this.view);
    }
  }

  // ------------------------------------------------------------- layout

  private relSeat(seat: SeatId): number {
    const n = this.view?.players ?? this.seatMeta.length;
    return (seat - this.me + n) % n;
  }

  private seatCentre(seat: SeatId): { x: number; y: number } {
    if (seat === this.me) return this.mineCentre();
    const g = this.geo.opp[this.relSeat(seat)];
    if (!g || !g.cards.length) return this.mineCentre();
    const a = g.cards[0]!;
    const b = g.cards[SLOTS - 1]!;
    return { x: (a.x + b.x + b.w) / 2, y: a.y + a.h / 2 };
  }

  private mineCentre(): { x: number; y: number } {
    const m = this.geo.mine;
    return { x: m.x + m.w / 2, y: m.y + m.h / 2 };
  }

  private nameOf(seat: SeatId): string {
    return seat === this.me ? L().ui.you : this.seatMeta[seat]?.name ?? '';
  }

  render(): void {
    const v = this.view;
    if (!v) return;
    const vw = this.root.clientWidth || window.innerWidth;
    const vh = this.root.clientHeight || window.innerHeight;
    this.geo = luckyGeo(vw, vh, v.players, readInsets());
    const g = this.geo;
    this.root.style.setProperty('--card-w', `${g.cw}px`);
    this.root.style.setProperty('--card-h', `${Math.round(g.cw * RATIO)}px`);
    this.root.style.setProperty('--pile-w', `${g.pw}px`);
    this.root.classList.toggle('final-lap', v.phase === 'play' && v.deckCount <= v.players);
    this.renderSeats(v);
    this.renderCards(v);
    this.renderCentre(v);
    this.renderPrompt(v);
    this.renderActions(v);
    place(this.timerBar, g.timer);
    place(this.actionBar, g.bar);
    if (this.focusSeat !== null) this.renderFocus();
  }

  private renderSeats(v: View): void {
    const g = this.geo;
    for (let r = 1; r < v.players; r++) {
      const seat = (this.me + r) % v.players;
      let s = this.chips[r - 1];
      if (!s) {
        s = el('button', 'seat l7-seat', this.table) as HTMLButtonElement;
        (s as HTMLButtonElement).type = 'button';
        s.innerHTML = '<span class="avatar"><span class="face"></span><span class="dot"></span></span><span class="name"></span><span class="chip hidden"></span><span class="stamp"></span>';
        s.addEventListener('click', () => this.tapSeat(Number(s!.dataset.seat)));
        this.chips[r - 1] = s;
      }
      place(s, g.opp[r]!.chip);
      s.dataset.seat = String(seat);
      const meta = this.seatMeta[seat]!;
      s.querySelector('.face')!.textContent = meta.avatar;
      s.querySelector('.name')!.textContent = meta.name.slice(0, 9);
      const isTurn = v.phase === 'play' && v.turn === seat;
      s.classList.toggle('turn', isTurn);
      if (!isTurn) s.classList.remove('urgent');
      const afk = this.meta.afk[seat] === true;
      const conn = this.conn[seat];
      s.classList.toggle('bot', meta.bot || afk || conn === 'left');
      s.classList.toggle('conn-away', conn === 'away');
      s.classList.toggle('conn-left', conn === 'left');
      s.classList.toggle('pickable', this.seatPickable(seat) && (this.mode === 'shuffle' || g.ocw < 40));
      const chip = s.querySelector('.chip') as HTMLElement;
      const done = this.revealedSeats.has(seat) && v.totals;
      if (done) {
        chip.textContent = fmt(L().l7.total, { n: v.totals![seat]! });
        chip.className = 'chip chip-gold';
      } else if (conn === 'left') {
        chip.textContent = L().ui.leftGame;
        chip.className = 'chip chip-danger';
      } else if (conn === 'away') {
        chip.textContent = L().ui.reconnecting;
        chip.className = 'chip chip-warn';
      } else if (afk) {
        chip.textContent = L().ui.afk;
        chip.className = 'chip chip-danger';
      } else chip.className = 'chip hidden';
      s.setAttribute('aria-label', `${meta.name}${isTurn ? ', ' + L().ui.yourTurn.toLowerCase() : ''}`);
    }
    for (let r = v.players - 1; r < this.chips.length; r++) this.chips[r]!.remove();
    this.chips.length = Math.max(0, v.players - 1);
  }

  /** Every slot on the table: backs, locks, peeks, the reveal. */
  private renderCards(v: View): void {
    const g = this.geo;
    const now = Date.now();
    const own = this.ownPeek && now < this.ownPeek.until ? this.ownPeek : null;
    place(this.mineEl, g.mine);
    for (let seat = 0; seat < v.players; seat++) {
      for (let i = 0; i < SLOTS; i++) {
        const k = key(seat, i);
        let c = this.cardEls.get(k);
        if (!c) {
          c = el('button', 'l7-card l7-mini-card', this.table) as HTMLButtonElement;
          (c as HTMLButtonElement).type = 'button';
          c.dataset.seat = String(seat);
          c.dataset.slot = String(i);
          const t = { seat, slot: i };
          c.addEventListener('click', () => this.tapCard(t));
          this.cardEls.set(k, c);
        }
        if (seat !== this.me) {
          const box = g.opp[this.relSeat(seat)]?.cards[i];
          if (box) place(c, box);
        }
        const locked = v.locked[seat]![i]! && !this.hideLocks.has(k);
        const peeked = this.peekShown && this.peekShown.target.seat === seat && this.peekShown.target.slot === i && now < this.peekShown.until ? this.peekShown.card : null;
        const revealed = this.revealedSeats.has(seat) ? v.revealed?.[seat]?.[i] ?? null : null;
        const face = revealed ?? (seat === this.me ? own?.cards[i] ?? null : peeked);
        const want = `${face ?? 'back'}|${locked}`;
        if (c.dataset.paint !== want) {
          c.dataset.paint = want;
          c.innerHTML = '';
          const card = face ? makeCard(face) : makeBack();
          card.classList.add('l7-slot-card');
          c.appendChild(card);
          if (locked) {
            const k7 = el('span', 'l7-lock', c);
            k7.innerHTML = '<span class="l7-lock-k"></span><b>🔒</b>';
            (k7.firstElementChild as HTMLElement).style.backgroundImage = `url("${cardImage('Ks')}")`;
          }
          if (seat === this.me) el('span', 'l7-slot-no', c).textContent = String(i + 1);
        }
        c.classList.toggle('face', !!face);
        c.classList.toggle('locked', locked);
        c.style.visibility = this.hideSlots.has(k) ? 'hidden' : '';
        c.classList.toggle('lifted', this.lifted.has(k));
        c.classList.toggle('pickable', this.cardPickable({ seat, slot: i }));
        c.classList.toggle('selected', this.mode === 'qTheirs' && seat === this.me && this.qMine === i);
        c.setAttribute('aria-label', `${seat === this.me ? L().l7.yourCards : this.seatMeta[seat]?.name ?? ''} ${i + 1}${locked ? ', ' + L().l7.locked : ''}${face ? ', ' + cardLabel(face) : ''}`);
      }
    }
    if (own) {
      const left = Math.ceil((own.until - now) / 1000);
      this.mineEl.dataset.peek = `${L().l7.ownPeek} · ${left}s`;
    } else delete this.mineEl.dataset.peek;
  }

  private renderCentre(v: View): void {
    const u = L().l7;
    const g = this.geo;
    place(this.pilesEl, g.piles);
    // Centre deck: a back with the count.
    this.deckEl.innerHTML = '';
    if (v.deckCount > 0) this.deckEl.appendChild(makeBack());
    el('span', 'l7-pile-label', this.deckEl).textContent = g.pw < 44 ? String(v.deckCount) : `${u.deck} · ${v.deckCount}`;
    this.deckEl.classList.toggle('pickable', this.myTurn && v.step === 'draw' && v.deckCount > 0);
    this.deckEl.setAttribute('aria-label', `${u.deck}, ${fmt(u.left, { n: v.deckCount })}`);
    // Discard: the top card (one still flying shows the card under it).
    this.discardEl.innerHTML = '';
    const top = v.discard[v.discard.length - 1 - this.discardLag];
    if (top) this.discardEl.appendChild(makeCard(top));
    else el('span', 'l7-empty', this.discardEl);
    el('span', 'l7-pile-label', this.discardEl).textContent = u.discardPile;
    const canTake = this.myTurn && v.step === 'draw' && v.discard.length > 0;
    const canThrow = this.myTurn && v.step === 'act' && this.mode === 'none';
    this.discardEl.classList.toggle('pickable', canTake || canThrow);
    this.discardEl.classList.toggle('throw', canThrow);
    this.discardEl.setAttribute('aria-label', canThrow ? u.discard : top ? fmt(u.takeDiscard, { card: cardLabel(top) }) : u.discardPile);
    // Used: the last power used, with the count.
    this.usedEl.innerHTML = '';
    const used = v.used[v.used.length - 1 - this.usedLag];
    if (used) this.usedEl.appendChild(makeCard(used));
    else el('span', 'l7-empty', this.usedEl);
    el('span', 'l7-pile-label', this.usedEl).textContent = g.pw < 44 ? String(v.used.length - this.usedLag) : `${u.usedPile} · ${v.used.length - this.usedLag}`;
    // The card in play this turn.
    place(this.playEl, g.play);
    const showPlay = v.phase === 'play' && v.step === 'act';
    this.playEl.classList.toggle('hidden', !showPlay);
    this.playEl.style.visibility = this.hidePlay ? 'hidden' : '';
    const want = showPlay ? `${v.turn}|${v.drawn ?? 'back'}` : '';
    if (this.playEl.dataset.paint !== want) {
      this.playEl.dataset.paint = want;
      this.playEl.innerHTML = '';
      if (showPlay) {
        el('div', 'l7-drawn-label', this.playEl).textContent = v.turn === this.me ? u.youDrew : fmt(u.theyDrew, { name: this.nameOf(v.turn) });
        const card = v.drawn ? makeCard(v.drawn) : makeBack();
        card.classList.add('l7-drawn-card');
        this.playEl.appendChild(card);
        const p = lucky7.powerOf(v.drawn);
        if (p) el('div', 'l7-power-tag', this.playEl).textContent = `⚡ ${u.powers[p]}`;
      }
    }
  }

  private renderPrompt(v: View): void {
    const u = L().l7;
    const chip = this.turnChip;
    const pr = this.geo.prompt;
    chip.style.left = `${pr.x}px`;
    chip.style.width = `${pr.w}px`;
    chip.style.top = 'auto';
    chip.style.bottom = `${this.geo.vh - this.geo.mine.y + 14}px`;
    if (v.phase !== 'play') {
      chip.classList.add('hidden');
      return;
    }
    chip.classList.remove('hidden');
    let text: string;
    if (v.turn !== this.me) text = fmt(u.waitingFor, { name: this.nameOf(v.turn) });
    else if (this.ownPeek && Date.now() < this.ownPeek.until) text = u.remember;
    else if (v.step === 'draw') text = u.drawPrompt;
    else if (v.step === 'peek') text = u.pickPeek;
    else
      text = {
        none: u.actPrompt,
        qMine: u.pickMine,
        qTheirs: u.pickTheirs,
        lock: u.pickAny,
        unlock: u.pickLocked,
        shuffle: u.pickSeat,
        peek: u.pickPeek,
      }[this.mode];
    chip.textContent = text;
    chip.classList.toggle('mine', v.turn === this.me);
  }

  private renderActions(v: View): void {
    const u = L().l7;
    const bar = this.actionBar;
    bar.innerHTML = '';
    button(bar, 'btn btn-icon', '☰', L().ui.menu).addEventListener('click', () => this.openMenu());
    if (this.meta.afk[this.me]) {
      button(bar, 'btn btn-turn', L().ui.imBack, L().ui.imBack).addEventListener('click', () => this.hooks.back());
      return;
    }
    if (!this.myTurn || v.phase !== 'play') return;
    if (v.step === 'peek') {
      if (this.ownPeek && Date.now() < this.ownPeek.until) {
        button(bar, 'btn btn-primary', L().ui.gotIt, L().ui.gotIt).addEventListener('click', () => {
          this.ownPeek = null;
          this.mode = 'peek';
          this.render();
        });
      } else if (!this.anyOpponentOpen(v)) {
        button(bar, 'btn btn-primary', u.skip, u.skip).addEventListener('click', () => this.send({ type: 'peek', target: null }));
      }
      return;
    }
    if (v.step !== 'act') return;
    if (this.mode !== 'none') {
      button(bar, 'btn btn-secondary', u.cancel, u.cancel).addEventListener('click', () => {
        this.resetMode();
        this.render();
      });
      if (this.mode === 'unlock') button(bar, 'btn btn-primary', u.skip, u.skip).addEventListener('click', () => this.send({ type: 'use', target: null }));
      return;
    }
    const power = lucky7.powerOf(v.drawn);
    if (power && this.canUse(v, power)) {
      const use = button(bar, 'btn btn-primary btn-power', `${u.use} · ${u.powers[power]}`, `${u.use} ${u.powers[power]}`);
      use.title = fmt(u.powerHelp[power], { n: v.config.peekSeconds });
      use.addEventListener('click', () => this.startPower(power));
    }
  }

  // --------------------------------------------------------- targeting

  private canUse(v: View, p: Power): boolean {
    const myOpen = v.locked[this.me]!.some((l) => !l);
    if (p === 'Q') return myOpen && this.anyOpponentOpen(v);
    if (p === 'K') return v.locked.some((row) => row.some((l) => !l));
    return true;
  }

  private anyOpponentOpen(v: View): boolean {
    return v.locked.some((row, seat) => seat !== this.me && row.some((l) => !l));
  }

  private startPower(p: Power): void {
    if (p === 'J') return this.send({ type: 'use' });
    this.mode = ({ Q: 'qMine', K: 'lock', '9': 'unlock', T: 'shuffle' } as const)[p];
    this.render();
  }

  /** Can this card be tapped now, and what for. */
  private cardPickable(t: Target): boolean {
    const v = this.view;
    if (!v || !this.myTurn) return false;
    const locked = v.locked[t.seat]![t.slot]!;
    const mine = t.seat === this.me;
    if (v.step === 'peek') return this.mode === 'peek' && !mine && !locked;
    if (v.step !== 'act') return false;
    switch (this.mode) {
      case 'none':
        return mine && !locked; // swap into it
      case 'qMine':
        return mine && !locked;
      case 'qTheirs':
        return !mine && !locked;
      case 'lock':
        return !locked;
      case 'unlock':
        return locked;
      case 'shuffle':
        return mine;
      default:
        return false;
    }
  }

  private seatPickable(seat: SeatId): boolean {
    const v = this.view;
    if (!v || !this.myTurn) return false;
    if (this.mode === 'shuffle') return true;
    return [0, 1, 2].some((i) => this.cardPickable({ seat, slot: i }));
  }

  private tapDeck(): void {
    const v = this.view;
    if (v && this.myTurn && v.step === 'draw' && v.deckCount > 0) this.send({ type: 'draw', from: 'deck' });
  }

  private tapDiscard(): void {
    const v = this.view;
    if (!v || !this.myTurn) return;
    if (v.step === 'draw' && v.discard.length > 0) this.send({ type: 'draw', from: 'discard' });
    else if (v.step === 'act' && this.mode === 'none') this.send({ type: 'discard' });
  }

  private tapCard(t: Target): void {
    if (!this.cardPickable(t)) {
      // Small opponent cards: the badge's focus sheet picks them.
      if (t.seat !== this.me && this.seatPickable(t.seat)) this.tapSeat(t.seat);
      return;
    }
    if (t.seat !== this.me && this.geo.ocw < 40 && this.mode !== 'shuffle') return this.tapSeat(t.seat);
    switch (this.mode) {
      case 'none':
        return this.send({ type: 'swap', slot: t.slot });
      case 'qMine':
        this.qMine = t.slot;
        this.mode = 'qTheirs';
        sound.click();
        return this.render();
      case 'shuffle':
        return this.send({ type: 'use', seat: t.seat });
      default:
        return this.pickTheirs(t);
    }
  }

  private tapSeat(seat: SeatId): void {
    if (!this.seatPickable(seat)) return;
    if (this.mode === 'shuffle') return this.send({ type: 'use', seat });
    sound.click();
    this.focusSeat = seat;
    this.renderFocus();
  }

  /** A seat's three cards, big, to pick one of them. */
  private renderFocus(): void {
    const v = this.view;
    const seat = this.focusSeat;
    if (!v || seat === null) return this.closeFocus();
    const f = this.focusEl;
    f.className = 'overlay l7-focus';
    f.innerHTML = '';
    const sheet = el('div', 'sheet l7-focus-sheet', f);
    const meta = this.seatMeta[seat]!;
    el('h2', '', sheet).textContent = `${meta.avatar} ${meta.name}`;
    el('p', 'l7-focus-hint', sheet).textContent = this.turnChip.textContent ?? '';
    const row = el('div', 'l7-focus-slots', sheet);
    for (let i = 0; i < SLOTS; i++) {
      const locked = v.locked[seat]![i]!;
      const ok = this.cardPickable({ seat, slot: i });
      const b = el('button', `l7-slot big${locked ? ' locked' : ''}${ok ? ' pickable' : ''}`, row) as HTMLButtonElement;
      b.type = 'button';
      b.disabled = !ok;
      const c = makeBack();
      c.classList.add('l7-slot-card');
      b.appendChild(c);
      if (locked) el('span', 'l7-lock', b).innerHTML = '<b>🔒</b>';
      el('span', 'l7-slot-no', b).textContent = String(i + 1);
      b.setAttribute('aria-label', `${meta.name} ${i + 1}${locked ? ', ' + L().l7.locked : ''}`);
      b.addEventListener('click', () => this.pickTheirs({ seat, slot: i }));
    }
    const actions = el('div', 'sheet-actions', sheet);
    button(actions, 'btn btn-secondary', L().l7.cancel, L().l7.cancel).addEventListener('click', () => {
      this.closeFocus();
      this.render();
    });
    f.onclick = (e) => {
      if (e.target === f) {
        this.closeFocus();
        this.render();
      }
    };
  }

  private closeFocus(): void {
    this.focusSeat = null;
    this.focusEl.className = 'overlay l7-focus hidden';
    this.focusEl.innerHTML = '';
  }

  private pickTheirs(t: Target): void {
    switch (this.mode) {
      case 'qTheirs':
        if (this.qMine !== null) this.send({ type: 'use', mine: this.qMine, target: t });
        return;
      case 'lock':
      case 'unlock':
        return this.send({ type: 'use', target: t });
      case 'peek':
        return this.send({ type: 'peek', target: t });
      default:
    }
  }

  // ------------------------------------------------------------- moments

  private moment(e: GameEvent, v: View): void {
    const u = L().l7;
    const seat = typeof e.seat === 'number' ? e.seat : null;
    switch (e.type) {
      case 'jester':
        this.showJester(e as JesterEvent);
        break;
      case 'turn':
        if (e.seat === this.me) {
          this.lastTickSecond = -1;
          haptic('light');
          this.feel.play(1, 'your_turn', () => sound.chime());
        }
        break;
      case 'swapped':
        this.stamp(seat!, u.stamps.swap, 'turn');
        break;
      case 'discarded':
        this.stamp(seat!, u.stamps.discard, 'neutral');
        break;
      case 'gift_grabbed':
        this.feel.play(2, 'gift', (ctx) => {
          const c = this.pileCentre(this.discardEl);
          banner(this.fx, u.gift, 'good', 'pop', ctx, c);
          burst(this.fx, c.x, c.y, 16, 'good', ctx, 80);
          sound.chime();
          haptic('medium');
        });
        break;
      case 'power': {
        const p = e.power as Power;
        if (p === 'Q') {
          const t = e.target as Target;
          this.stamp(seat!, u.stamps.qswap, 'power');
          if (t.seat !== seat) this.stamp(t.seat, u.stamps.qswap, 'power');
        } else if (p === 'J') this.stamp(seat!, u.stamps.peek, 'info');
        break;
      }
      case 'card_locked': {
        const t = e.target as Target;
        this.stamp(t.seat, u.stamps.lock, 'danger');
        haptic(t.seat === this.me ? 'strong' : 'medium');
        break;
      }
      case 'lock_broken': {
        const t = e.target as Target;
        this.stamp(t.seat, u.stamps.unlock, 'good');
        this.feel.play(2, 'unlock', (ctx) => {
          const at = this.seatCentre(t.seat);
          burst(this.fx, at.x, at.y, 18, 'good', ctx, 90);
          sound.chime();
          haptic('medium');
        });
        break;
      }
      case 'shuffled': {
        const target = e.target as SeatId;
        this.stamp(target, u.stamps.shuffle, 'power');
        if (target === this.me) this.feel.play(2, 'shuffle', (ctx) => banner(this.fx, u.shuffledYou, 'power', 'pop', ctx, this.mineCentre()));
        haptic(target === this.me ? 'strong' : 'light');
        break;
      }
      case 'peek_own': {
        const ms = ((e.seconds as number) ?? v.config.peekSeconds) * 1000;
        this.ownPeek = { cards: e.cards as (Card | null)[], until: Date.now() + ms };
        this.mode = 'none';
        haptic('medium');
        window.setTimeout(() => {
          if (!this.ownPeek) return;
          this.ownPeek = null;
          if (this.view?.step === 'peek' && this.view.turn === this.me) this.mode = 'peek';
          this.render();
        }, ms);
        break;
      }
      case 'peek_card': {
        const t = e.target as Target;
        this.peekShown = { target: t, card: e.card as Card, until: Date.now() + PEEK_RESULT_MS };
        this.feel.play(2, 'peek', (ctx) => {
          banner(this.fx, `👀 ${L().l7.peekResult}`, 'info', 'pop', ctx, this.seatCentre(t.seat));
          haptic('medium');
        });
        window.setTimeout(() => this.render(), PEEK_RESULT_MS + 50);
        break;
      }
      case 'final_lap':
        this.feel.play(3, 'final_lap', (ctx) => {
          dim(this.fx, ctx);
          banner(this.fx, u.finalLap, 'danger', 'banner', ctx);
          shake(this.table, 'big', ctx);
          sound.bass();
          haptic('strong');
        });
        break;
      case 'too_slow':
        this.stamp(seat!, L().ui.tooSlow, 'danger');
        break;
      case 'afk':
        if (seat === this.me) haptic('error');
        break;
      case 'revealed':
        this.feel.play(3, 'reveal', (ctx) => {
          banner(this.fx, u.reveal, 'good', 'banner', ctx);
          sound.bass();
          haptic('strong');
        });
        break;
      default:
    }
  }

  private pileCentre(p: HTMLElement): { x: number; y: number } {
    const r = p.getBoundingClientRect();
    return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
  }

  /** A big word over a seat's cards (or mine): SWAP, LOCKED!, SHUFFLED! */
  private stamp(seat: SeatId, text: string, role: ColourRole | 'pass'): void {
    if (!this.geo) return;
    const at = this.seatCentre(seat);
    this.feel.play(1, 'stamp', (ctx) => banner(this.fx, text, role === 'pass' ? 'neutral' : role, 'pop', ctx, at));
  }

  private showJester(e: JesterEvent): void {
    const text = jesterText(e);
    if (!text) return;
    const j = this.jesterEl;
    const g = this.geo ?? luckyGeo(window.innerWidth, window.innerHeight, this.seatMeta.length, readInsets());
    this.stopEmoji?.();
    this.stopEmoji = e.emoji ? playEmoji(this.jesterEmoji, e.emoji) : null;
    j.className = `jester mood-${e.mood} eyes-${EYES[e.mood]}`;
    this.jesterBubble.textContent = text;
    const w = Math.min(g.vw - 24, 520);
    j.style.width = `${w}px`;
    j.style.left = `${(g.vw - w) / 2}px`;
    j.style.top = `${Math.max(4, g.prompt.y - 124)}px`;
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
    const u = L().l7;
    const totals = v.totals ?? [];
    const placings = v.placings ?? [];
    const best = Math.min(...totals);
    const winners = placings.filter((s) => totals[s] === best);
    const o = this.overlay;
    o.className = 'overlay results l7-results';
    o.innerHTML = '';
    const card = el('div', 'sheet results-sheet', o);
    el('h2', '', card).textContent = `${L().ui.results} · ${u.title}`;
    el('p', 'l7-results-sub', card).textContent = winners.length > 1 ? u.tie : u.winner;
    const list = el('ol', 'standings l7-standings', card);
    placings.forEach((seat, k) => {
      const li = el('li', `standing${winners.includes(seat) ? ' winner' : ''}`, list);
      li.style.animationDelay = `${k * 90}ms`;
      el('span', 'medal', li).textContent = winners.includes(seat) ? '👑' : String(k + 1);
      el('span', 'who', li).textContent = `${this.seatMeta[seat]!.avatar} ${seat === this.me ? L().ui.you : this.seatMeta[seat]!.name}`;
      const cards = el('span', 'l7-res-cards', li);
      for (const c of v.revealed?.[seat] ?? []) cards.appendChild(makeCard(c));
      el('span', 'pts', li).textContent = fmt(u.total, { n: totals[seat]! });
    });
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
      if (winners.includes(this.me)) {
        confetti(this.fx, this.geo.vw, ctx);
        sound.fanfare();
      } else sound.trombone();
    });
  }

  private openMenu(): void {
    const o = this.overlay;
    o.className = 'overlay';
    o.innerHTML = '';
    const sheet = el('div', 'sheet', o);
    el('h2', '', sheet).textContent = L().l7.title;
    const help = el('ul', 'l7-help', sheet);
    el('li', '', help).textContent = L().l7.setupHint;
    for (const p of ['J', 'Q', 'K', '9', 'T'] as Power[]) {
      el('li', '', help).textContent = `${p === 'T' ? '10' : p} · ${L().l7.powers[p]}: ${fmt(L().l7.powerHelp[p], { n: this.view?.config.peekSeconds ?? 10 })}`;
    }
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
    if (this.ownPeek && v) {
      const left = Math.ceil((this.ownPeek.until - Date.now()) / 1000);
      if (this.mineEl.dataset.peekLeft !== String(left)) {
        this.mineEl.dataset.peekLeft = String(left);
        this.renderCards(v);
      }
    }
    if (!v || !this.meta.deadline || v.phase !== 'play') {
      this.timerFill.style.transform = 'scaleX(0)';
      return;
    }
    const left = Math.max(0, this.meta.deadline - Date.now());
    const frac = Math.max(0, Math.min(1, left / this.turnTotal));
    const mine = v.turn === this.me;
    this.timerFill.style.transform = `scaleX(${mine ? frac : 0})`;
    this.timerBar.classList.toggle('urgent', mine && left <= 5000);
    for (const s of this.chips) {
      const isTurn = Number(s.dataset.seat) === v.turn;
      s.classList.toggle('urgent', isTurn && left <= 5000);
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

function place(e: HTMLElement, b: Box): void {
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
