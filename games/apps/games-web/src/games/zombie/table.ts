// The Zombie table. My hand sits at the bottom in my own order: drag a card
// to move it, or tap Shuffle. On my turn the hand I draw from is spread big
// in the middle, face down: tap one. It wobbles with a heartbeat, flies to
// me and flips; a pair it makes flies face up to the graveyard. When
// someone draws from me, my cards shiver and the picked one flies off.
//
// Hidden information stays hidden on screen too: other hands are only
// backs, a reorder shows only that someone shuffled, and the Zombie's grin
// on a drawn card plays only on the drawer's phone. The loser's seat gets
// eaten at the end, for everyone.

import { zombie, type Card, type GameEvent, type SeatId } from '@efoc/engine';
import { haptic } from '../../bridge';
import { banner, burst, confetti, dim, shake, type ColourRole } from '../../feel/effects';
import { jesterText, type Humour, type JesterEvent } from '../../feel/jester';
import { EYES, JESTER_SVG, playEmoji, preloadEmoji } from '../../feel/jesterArt';
import { setMuted, sound, unlockAudio } from '../../feel/sound';
import { FeelQueue } from '../../feel/tiers';
import { L, fmt } from '../../strings';
import { cardImage, cardLabel, makeBack, makeCard } from '../../table/cardFace';
import { computeLayout, handPlaces, JESTER_BAND, MIN_TARGET, TURN_CHIP_H, type Box, type TableLayout } from '../../table/layout';
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

const RATIO = 1.36;
const FLY_MS = 480;
const WOBBLE_MS = 400;
const wait = (ms: number): Promise<void> => new Promise((r) => setTimeout(r, ms));
const clamp = (v: number, lo: number, hi: number): number => Math.max(lo, Math.min(hi, v));
const isZ = zombie.isZombie;

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

export class ZombieTable {
  readonly feel = new FeelQueue();
  private lay!: TableLayout;
  private view: View | null = null;
  private meta: UpdateMeta = { deadline: null, afk: [] };
  private sent = false;
  /** My drag result, shown until the host's copy of my hand catches up. */
  private localOrder: Card[] | null = null;
  private turnTotal = 15000;
  private lastTickSecond = -1;
  private resultsOpen = false;
  private conn: Conn[] = [];
  private rematch: RematchInfo | null = null;
  private rematchEl: HTMLElement | null = null;

  // Animation: what hasn't landed yet keeps its old look.
  private anim: Promise<void> = Promise.resolve();
  private backlog = 0;
  /** My cards still flying in (or out to the pile). */
  private hideMine = new Set<Card>();
  /** Pair cards still flying to the graveyard. */
  private pileLag = 0;
  /** Per seat: cards on the way in that its count shouldn't show yet (or out, negative). */
  private countLag: number[] = [];
  /** The card I just drew, marked NEW for a moment. */
  private fresh: { card: Card; until: number } | null = null;
  /** Pairs I just made (at the deal, or by a draw): shown in my hand glowing until they drop. */
  private glowing: Card[] = [];
  /** The stage card being picked (lifted) while its draw plays. */
  private picking: number | null = null;
  /** Seats eaten by the Zombie (the loser, after its moment). */
  private eaten = new Set<SeatId>();

  // DOM
  private table: HTMLElement;
  private seatEls: HTMLElement[] = [];
  private stageEl: HTMLElement;
  private stageLabel: HTMLElement;
  private stageCards: HTMLElement[] = [];
  private pileEl: HTMLElement;
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
    this.stageEl = el('div', 'zb-stage', this.table);
    this.stageLabel = el('div', 'zb-stage-label', this.stageEl);
    this.pileEl = el('div', 'zb-pile', this.table);
    this.handLayer = el('div', 'card-layer zb-hand', this.table);
    this.handNote = el('div', 'zb-hand-note hidden', this.table);
    this.turnChip = el('div', 'turn-chip zb-prompt hidden', this.table);
    this.turnChip.setAttribute('aria-live', 'polite');
    this.timerBar = el('div', 'timer-bar', this.table);
    this.timerFill = el('div', 'timer-fill', this.timerBar);
    this.actionBar = el('div', 'action-bar zb-actions', this.table);
    this.flights = el('div', 'l7-flights', root);
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
    const prev = this.view;
    this.view = view;
    this.meta = meta;
    if (events.some((e) => e.type === 'drew' || e.type === 'round_started') || view.turn !== this.me) this.sent = false;
    if (meta.deadline && meta.deadline !== prevDeadline) this.turnTotal = Math.max(1000, meta.deadline - Date.now());
    // The host started another match: close the results.
    if (view.phase === 'play' && (this.resultsOpen || this.eaten.size)) {
      this.resultsOpen = false;
      this.eaten.clear();
      this.overlay.className = 'overlay hidden';
    }
    // My drag order holds until the host's copy agrees, or the hand changed under it.
    if (this.localOrder && (sameOrder(this.localOrder, view.hand) || !samePile(this.localOrder, view.hand))) this.localOrder = null;
    const mine = events.filter((e) => e.to === undefined || e.to === this.me);
    if (this.countLag.length !== view.players) this.countLag = new Array<number>(view.players).fill(0);
    this.planFlights(mine, prev, view);
    for (const e of mine) this.moment(e, view);
    this.render();
  }

  setRematch(info: RematchInfo | null): void {
    this.rematch = info;
    if (this.rematchEl?.isConnected) renderRematch(this.rematchEl, info);
  }

  setConnection(conn: Conn[]): void {
    this.conn = conn.slice();
    if (this.view) this.render();
  }

  notice(text: string): void {
    if (!this.lay) return;
    const c = this.lay.stage;
    this.feel.play(2, 'notice', (ctx) => banner(this.fx, text, 'info', 'pop', ctx, { x: c.x + c.w / 2, y: c.y + 20 }));
  }

  /** The host turned a move down. A reorder that missed a draw just snaps to the real hand. */
  reject(reason: string): void {
    this.sent = false;
    this.localOrder = null;
    if (reason !== 'Your hand changed') {
      this.feel.play(1, 'rejected', (ctx) => banner(this.fx, reason, 'danger', 'pop', ctx, this.handCentre()));
      haptic('error');
    }
    this.render();
  }

  private get spectator(): boolean {
    return this.view?.seat === 'public';
  }

  private get myTurn(): boolean {
    const v = this.view;
    return !!v && !this.spectator && v.phase === 'play' && v.turn === this.me && !this.sent;
  }

  /** My hand as I see it: my drag order if one is pending. */
  private myHand(v: View): Card[] {
    return this.localOrder ?? v.hand;
  }

  private send(m: Move): void {
    if (m.type === 'draw') {
      if (this.sent) return;
      this.sent = true;
    }
    unlockAudio();
    this.hooks.move(m);
    this.render();
  }

  // ------------------------------------------------------------ flights

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

  /** One card flying between two boxes along an arc, optionally flipping. */
  private fly(from: DOMRect, to: DOMRect, face: Card | null, flip: 'up' | 'down' | null, o: { ms?: number; bend?: number } = {}): Promise<void> {
    const reduced = this.feel.reduced;
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
    if (face) {
      if (isZ(face)) front.appendChild(makeFace(face)).classList.add('zb-fly-face');
      else front.style.backgroundImage = `url("${cardImage(face)}")`;
    }
    back.style.backgroundImage = `url("${cardImage('back')}")`;
    const startUp = flip === 'down' ? true : flip === 'up' ? false : !!face;
    const endUp = flip === 'up' ? true : flip === 'down' ? false : !!face;
    const dx = to.left - from.left;
    const dy = to.top - from.top;
    const sx = to.width / from.width;
    const sy = to.height / from.height;
    const bend = o.bend ?? 1;
    const lift = reduced ? 0 : Math.min(70, 20 + Math.hypot(dx, dy) * 0.14) * bend;
    const tilt = reduced ? 0 : (dx >= 0 ? 10 : -10) * bend;
    const move = f.animate(
      [
        { transform: 'translate(0px, 0px) scale(1, 1) rotate(0deg)', offset: 0 },
        { transform: `translate(${dx * 0.5}px, ${dy * 0.5 - lift}px) scale(${(1 + sx) / 2 + 0.12}, ${(1 + sy) / 2 + 0.12}) rotate(${tilt}deg)`, offset: 0.5 },
        { transform: `translate(${dx}px, ${dy}px) scale(${sx}, ${sy}) rotate(0deg)`, offset: 1 },
      ],
      { duration: ms, easing: 'cubic-bezier(0.3, 0.7, 0.35, 1)', fill: 'forwards' },
    );
    inner.animate([{ transform: `rotateY(${startUp ? 0 : 180}deg)` }, { transform: `rotateY(${endUp ? 0 : 180}deg)` }], { duration: ms, easing: 'ease-in-out', fill: 'forwards' });
    return move.finished.then(
      () => {
        f.remove();
        sound.thud(0);
      },
      () => f.remove(),
    );
  }

  /** The suspense beat before a hidden card turns: a 400 ms wobble with a heartbeat (spec). */
  private async wobble(at: DOMRect): Promise<void> {
    if (this.feel.reduced || this.backlog > 3) return;
    const f = el('div', 'l7-flyer zb-wobble', this.flights);
    f.style.left = `${at.left}px`;
    f.style.top = `${at.top}px`;
    f.style.width = `${at.width}px`;
    f.style.height = `${at.height}px`;
    f.style.backgroundImage = `url("${cardImage('back')}")`;
    sound.bass();
    await f.animate(
      [
        { transform: 'translateY(-14px) rotate(0deg) scale(1.08)' },
        { transform: 'translateY(-14px) rotate(-7deg) scale(1.12)' },
        { transform: 'translateY(-14px) rotate(7deg) scale(1.08)' },
        { transform: 'translateY(-14px) rotate(-5deg) scale(1.12)' },
        { transform: 'translateY(-14px) rotate(0deg) scale(1.08)' },
      ],
      { duration: WOBBLE_MS, easing: 'ease-in-out' },
    ).finished.catch(() => undefined);
    f.remove();
  }

  private rectOf(b: Box): DOMRect {
    return new DOMRect(b.x, b.y, b.w, b.h);
  }

  private seatRect(seat: SeatId): DOMRect {
    if (seat === this.me && !this.spectator) {
      const c = this.handCentre();
      return new DOMRect(c.x - this.lay.handW / 2, c.y - this.lay.handH / 2, this.lay.handW, this.lay.handH);
    }
    const s = this.seatEls[this.relSeat(seat) - 1];
    const r = s ? s.getBoundingClientRect() : new DOMRect(this.lay.vw / 2, 0, 0, 0);
    const w = this.lay.cardW * 0.8;
    return new DOMRect(r.left + r.width / 2 - w / 2, r.top + r.height / 2 - (w * RATIO) / 2, w, w * RATIO);
  }

  private pileRect(): DOMRect {
    return this.pileEl.getBoundingClientRect();
  }

  /**
   * Turns this entry's public events (and my private ones) into flights. A
   * card still flying keeps its old look: hidden in my hand, a seat count
   * not yet changed, the pile not yet grown.
   */
  private planFlights(events: GameEvent[], prev: View | null, v: View): void {
    const drew = events.find((e) => e.type === 'drew');
    if (events.some((e) => e.type === 'round_started')) {
      // My pairs from the deal glow in my hand, then drop to the graveyard.
      const pairs = v.seat === 'public' ? [] : v.dealPairs[this.me] ?? [];
      const all = v.dealPairs.flat();
      this.glowing = pairs.slice();
      this.pileLag = all.length;
      this.chain(async () => {
        await wait(this.feel.reduced ? 300 : 1100);
        const rects = new Map<Card, DOMRect>();
        for (const c of this.glowing) {
          const s = this.sprites.get(c);
          if (s) rects.set(c, s.getBoundingClientRect());
        }
        const flights: Promise<void>[] = [];
        for (const [c, r] of rects) flights.push(this.fly(r, this.pileRect(), c, null, { ms: 520 }));
        // Everyone else's pairs drop from their seats.
        for (let seat = 0; seat < v.players; seat++) {
          if (seat === this.me && v.seat !== 'public') continue;
          const p = v.dealPairs[seat] ?? [];
          if (p.length) flights.push(this.fly(this.seatRect(seat), this.pileRect(), p[p.length - 1]!, 'up', { ms: 560 }));
        }
        this.glowing = [];
        this.render();
        if (flights.length) sound.deal();
        await Promise.all(flights);
        this.pileLag = 0;
      });
      return;
    }
    if (!drew || !prev) return;
    const seat = drew.seat as SeatId;
    const from = drew.from as SeatId;
    const slot = drew.slot as number;
    const mine = seat === this.me && v.seat !== 'public';
    const fromMe = from === this.me && v.seat !== 'public';
    const card = (events.find((e) => e.type === 'drawn_card')?.card as Card | undefined) ?? null;
    const pair = events.find((e) => e.type === 'pair');
    const pairCards = (pair?.cards as Card[] | undefined) ?? [];
    const drawnFace = mine ? card : fromMe ? this.myHand(prev)[slot] ?? null : null;
    // Where the card was: in my hand, or in the spread on the stage.
    let fromRect: DOMRect;
    if (fromMe) {
      const lost = this.myHand(prev)[slot];
      const s = lost ? this.sprites.get(lost) : undefined;
      fromRect = s ? s.getBoundingClientRect() : this.seatRect(from);
      if (lost && s) {
        // It leaves my hand at once; its flight shows the way.
        s.style.visibility = 'hidden';
      }
    } else {
      const s = this.stageCards[slot];
      fromRect = s && !s.classList.contains('hidden') ? s.getBoundingClientRect() : this.seatRect(from);
    }
    // The drawer's count changes as the cards land, not before.
    if (!mine) this.countLag[seat] = 1 - (pair ? 2 : 0);
    if (pair) this.pileLag += 2;
    if (mine && card) this.hideMine.add(card);
    // My new pair: both cards join up at the end of my hand and glow before they drop.
    if (mine && pair) this.glowing = [...this.glowing, ...pairCards];
    if (fromMe && drawnFace && isZ(drawnFace)) {
      // My Zombie left. Only I know: phew.
      this.chain(async () => {
        this.feel.play(2, 'zombie_gone', (ctx) => {
          banner(this.fx, L().zb.zombieGone, 'good', 'pop', ctx, this.handCentre());
          sound.chime();
          haptic('medium');
        });
      });
    }
    this.picking = fromMe ? null : slot;
    this.chain(async () => {
      await this.wobble(fromRect);
      this.picking = null;
      this.render();
      let landed: DOMRect;
      if (mine && card) {
        const s = this.sprites.get(card);
        landed = s ? s.getBoundingClientRect() : this.seatRect(seat);
        await this.fly(fromRect, landed, card, 'up', { ms: 560 });
        this.hideMine.delete(card);
        this.fresh = { card, until: Date.now() + 2600 };
        this.render();
      } else {
        landed = this.seatRect(seat);
        // Only the giver sees the face as it leaves; everyone else sees a back.
        await this.fly(fromRect, landed, drawnFace, fromMe ? 'down' : null, { ms: 520 });
      }
      if (!mine) this.countLag[seat] = pair ? -2 : 0;
      this.render();
      if (pair) {
        await wait(this.feel.reduced ? 60 : mine ? 650 : 260);
        const rects = pairCards.map((c) => {
          const s = mine ? this.sprites.get(c) : undefined;
          return s ? s.getBoundingClientRect() : landed;
        });
        if (!mine) this.countLag[seat] = 0;
        this.glowing = this.glowing.filter((c) => !pairCards.includes(c));
        this.render();
        await Promise.all(pairCards.map((c, i) => this.fly(rects[i]!, this.pileRect(), c, mine ? null : 'up', { ms: 500 })));
        this.pileLag = Math.max(0, this.pileLag - 2);
      }
    });
  }

  // ------------------------------------------------------------- layout

  private relSeat(seat: SeatId): number {
    const n = this.view?.players ?? this.seatMeta.length;
    return (seat - this.me + n) % n;
  }

  private handCentre(): { x: number; y: number } {
    const h = this.lay.hand;
    return { x: h.x + h.w / 2, y: h.y + h.h - this.lay.handH / 2 - 4 };
  }

  private nameOf(seat: SeatId): string {
    return seat === this.me && !this.spectator ? L().ui.you : this.seatMeta[seat]?.name ?? '';
  }

  render(): void {
    const v = this.view;
    if (!v) return;
    const vw = this.root.clientWidth || window.innerWidth;
    const vh = this.root.clientHeight || window.innerHeight;
    this.lay = computeLayout(vw, vh, v.players, readInsets(), 14);
    const lay = this.lay;
    this.root.style.setProperty('--card-w', `${lay.handW}px`);
    this.root.style.setProperty('--card-h', `${lay.handH}px`);
    this.renderSeats(v);
    this.renderStage(v);
    this.renderPile(v);
    this.renderHand(v);
    this.renderPrompt(v);
    this.renderActions(v);
    place(this.timerBar, lay.timerBar);
    place(this.actionBar, lay.actionBar);
  }

  private renderSeats(v: View): void {
    const lay = this.lay;
    while (this.seatEls.length < v.players - 1) {
      const s = el('div', 'seat zb-seat', this.table);
      s.innerHTML =
        '<div class="avatar"><svg class="ring" viewBox="0 0 36 36"><circle class="ring-bg" cx="18" cy="18" r="16"/><circle class="ring-fg" cx="18" cy="18" r="16"/></svg><span class="face"></span><span class="dot"></span><span class="zb-eat">🧟</span></div>' +
        '<div class="name"></div><div class="info"><span class="count"></span></div><div class="chip hidden"></div><div class="fan"></div><div class="stamp"></div>';
      this.seatEls.push(s);
    }
    for (let r = 1; r < v.players; r++) {
      const seat = (this.me + r) % v.players;
      const s = this.seatEls[r - 1]!;
      place(s, lay.seats[r - 1]!);
      s.dataset.seat = String(seat);
      s.classList.toggle('compact', lay.compact);
      const meta = this.seatMeta[seat]!;
      s.querySelector('.face')!.textContent = meta.avatar;
      s.querySelector('.name')!.textContent = meta.name.slice(0, 8);
      const count = Math.max(0, v.counts[seat]! - (this.countLag[seat] ?? 0));
      const safe = v.safe.includes(seat) && count === 0;
      const isTurn = v.phase === 'play' && v.turn === seat;
      const isFrom = v.phase === 'play' && v.from === seat;
      s.classList.toggle('turn', isTurn);
      s.classList.toggle('zb-drawing', isTurn);
      s.classList.toggle('zb-target', isFrom);
      s.classList.toggle('out', safe);
      s.classList.toggle('zb-eaten', this.eaten.has(seat));
      if (!isTurn) s.classList.remove('urgent');
      const fan = s.querySelector('.fan') as HTMLElement;
      const backs = Math.min(5, count);
      if (fan.childElementCount !== backs) {
        fan.innerHTML = '';
        for (let i = 0; i < backs; i++) fan.appendChild(makeBack());
      }
      fan.dataset.count = String(count);
      s.querySelector('.count')!.textContent = safe ? L().zb.safe : fmt(L().zb.cards, { n: count });
      const afk = this.meta.afk[seat] === true;
      const conn = this.conn[seat];
      s.classList.toggle('bot', meta.bot || afk || conn === 'left');
      s.classList.toggle('conn-away', conn === 'away');
      s.classList.toggle('conn-left', conn === 'left');
      const chip = s.querySelector('.chip') as HTMLElement;
      if (safe) {
        chip.textContent = `✅ ${ordinal(v.safe.indexOf(seat) + 1)}`;
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
      s.setAttribute('aria-label', `${meta.name}, ${safe ? L().zb.safe : fmt(L().zb.cards, { n: count })}${isTurn ? ', ' + L().ui.yourTurn.toLowerCase() : ''}`);
    }
    for (let r = v.players - 1; r < this.seatEls.length; r++) this.seatEls[r]!.remove();
    this.seatEls.length = Math.max(0, v.players - 1);
  }

  /** The hand being drawn from, spread face down in the middle. Tappable on my turn. */
  private renderStage(v: View): void {
    const lay = this.lay;
    const st = lay.stage;
    place(this.stageEl, st);
    const u = L().zb;
    const play = v.phase === 'play';
    const from = v.from;
    const fromMe = from === this.me && !this.spectator;
    const n = play && !fromMe ? v.counts[from]! : 0;
    this.stageLabel.textContent = !play
      ? ''
      : v.turn === this.me && !this.spectator
        ? fmt(u.pickFrom, { name: this.nameOf(from) })
        : fromMe
          ? fmt(u.pickingYou, { name: this.nameOf(v.turn) })
          : fmt(u.picking, { name: this.nameOf(v.turn), from: this.nameOf(from) });
    this.stageLabel.classList.toggle('mine', this.myTurn);
    this.stageLabel.classList.toggle('danger', fromMe);
    // Card size and rows: every card keeps a 44 px touch strip.
    // The label on top, the graveyard at the bottom, the spread between.
    const top = 44;
    const areaW = st.w - 8;
    const areaH = Math.max(40, this.pileBox().y - st.y - 22 - top);
    // Cards overlap, but each keeps a strip of at least 44 px to tap: as
    // many rows as it takes (the middle is narrow between side seats),
    // picking the layout with the biggest cards.
    const STRIP = MIN_TARGET + 2;
    const OFFSET = 0.55; // each row below shows 55% of the one above
    let rows = 1;
    let w = 0;
    for (let r = 1; r <= Math.max(1, Math.min(4, n)); r++) {
      const per = Math.ceil(n / r);
      const byW = per <= 1 ? areaW : areaW - (per - 1) * STRIP;
      const byH = areaH / (RATIO * (1 + OFFSET * (r - 1)));
      const cand = Math.floor(Math.min(lay.handW * 1.15, 96, byW, byH));
      if (cand > w + 2) {
        w = cand;
        rows = r;
      }
    }
    w = Math.max(w, STRIP);
    const natural = Math.max(w * 0.75, STRIP);
    const h = Math.round(w * RATIO);
    const perRow = Math.ceil(n / rows);
    const blockH = h * (1 + OFFSET * (rows - 1));
    while (this.stageCards.length < n) {
      const i = this.stageCards.length;
      const b = el('button', 'zb-pick', this.stageEl) as HTMLButtonElement;
      b.type = 'button';
      b.appendChild(makeBack());
      b.addEventListener('click', () => this.pick(i));
      this.stageCards.push(b);
    }
    this.stageCards.forEach((b, i) => {
      if (i >= n) {
        b.classList.add('hidden');
        return;
      }
      b.classList.remove('hidden');
      const row = Math.floor(i / perRow);
      const k = i - row * perRow;
      const inRow = Math.min(perRow, n - row * perRow);
      const step = inRow <= 1 ? 0 : Math.min(natural, (areaW - w) / (inRow - 1));
      const total = w + step * (inRow - 1);
      const x0 = (st.w - total) / 2;
      const y0 = top + (areaH - blockH) / 2 + row * h * OFFSET;
      const t = inRow <= 1 ? 0 : (k / (inRow - 1)) * 2 - 1;
      b.style.left = `${Math.round(x0 + k * step)}px`;
      b.style.top = `${Math.round(y0 + (rows === 1 ? t * t * 8 : 0))}px`;
      b.style.width = `${w}px`;
      b.style.height = `${h}px`;
      b.style.zIndex = String(10 + i);
      b.style.transform = rows === 1 ? `rotate(${t * 6}deg)` : '';
      b.classList.toggle('pickable', this.myTurn);
      b.classList.toggle('lifted', this.picking === i);
      (b as HTMLButtonElement).disabled = !this.myTurn;
      b.setAttribute('aria-label', fmt(u.pickLabel, { n: i + 1, name: this.nameOf(from) }));
    });
  }

  private pick(slot: number): void {
    if (!this.myTurn) return;
    this.picking = slot;
    haptic('light');
    this.send({ type: 'draw', slot });
  }

  /** The graveyard: bottom middle of the stage, its label just under it. */
  private pileBox(): Box {
    const st = this.lay.stage;
    const w = Math.round(clamp(this.lay.cardW * 0.8, 30, 52));
    const h = Math.round(w * RATIO);
    return { x: Math.round(st.x + st.w / 2 - w / 2), y: Math.round(st.y + st.h - h - 18), w, h };
  }

  private renderPile(v: View): void {
    place(this.pileEl, this.pileBox());
    const shown = Math.max(0, v.pile.length - this.pileLag);
    const top = v.pile[shown - 1];
    const want = `${top ?? ''}|${shown}`;
    if (this.pileEl.dataset.paint === want) return;
    this.pileEl.dataset.paint = want;
    this.pileEl.innerHTML = '';
    if (top) this.pileEl.appendChild(makeFace(top));
    el('span', 'zb-pile-label', this.pileEl).textContent = `🪦 ${shown / 2}`;
    this.pileEl.setAttribute('aria-label', fmt(L().zb.pileLabel, { n: shown / 2 }));
  }

  private renderHand(v: View): void {
    const lay = this.lay;
    const u = L().zb;
    const hand = this.spectator ? [] : [...this.myHand(v), ...this.glowing];
    const places = handPlaces(hand.length, lay);
    const targeted = v.phase === 'play' && v.from === this.me && !this.spectator;
    const now = Date.now();
    const wanted = new Set(hand);
    for (const [card, s] of this.sprites) {
      if (wanted.has(card)) continue;
      this.sprites.delete(card);
      s.remove();
    }
    hand.forEach((card, i) => {
      let s = this.sprites.get(card);
      const p = places[i]!;
      if (!s) {
        s = makeFace(card);
        s.classList.add('in-hand', 'zb-mine', 'no-anim');
        this.handLayer.appendChild(s);
        this.sprites.set(card, s);
        this.bindDrag(s, card);
        s.style.transform = `translate(${p.x}px, ${p.y}px) rotate(${p.rot}deg)`;
        void s.offsetWidth;
        s.classList.remove('no-anim');
      }
      if (!s.classList.contains('dragging')) s.style.transform = `translate(${p.x}px, ${p.y}px) rotate(${p.rot}deg)`;
      s.style.zIndex = String(10 + p.z);
      s.style.visibility = this.hideMine.has(card) ? 'hidden' : '';
      s.classList.toggle('zb-paired', this.glowing.includes(card));
      s.classList.toggle('zb-fresh', !!this.fresh && this.fresh.card === card && now < this.fresh.until);
      s.classList.toggle('zb-shiver', targeted && !this.feel.reduced);
      s.setAttribute('aria-label', `${faceLabel(card)}, ${fmt(u.position, { n: i + 1 })}`);
    });
    // Safe, a spectator, or the loser: a note where the hand was.
    const note = this.handNote;
    const safe = !this.spectator && v.safe.includes(this.me) && hand.length === 0;
    if (this.spectator || safe) {
      note.classList.remove('hidden');
      note.textContent = this.spectator ? L().ui.spectating : fmt(u.youreSafe, { place: ordinal(v.safe.indexOf(this.me) + 1) });
      place(note, { x: lay.hand.x, y: lay.hand.y + lay.hand.h - lay.handH, w: lay.hand.w, h: lay.handH - 10 });
    } else note.classList.add('hidden');
  }

  /** Drag a card along my hand to move it; drop sends my new order. */
  private bindDrag(sprite: HTMLElement, card: Card): void {
    let pointer: number | null = null;
    let startX = 0;
    let startY = 0;
    let startTransform = '';
    let dragging = false;
    sprite.addEventListener('pointerdown', (e) => {
      if (this.spectator || this.view?.phase !== 'play') return;
      pointer = e.pointerId;
      startX = e.clientX;
      startY = e.clientY;
      startTransform = sprite.style.transform;
      dragging = false;
      try {
        sprite.setPointerCapture(e.pointerId);
      } catch {
        /* synthetic events */
      }
    });
    sprite.addEventListener('pointermove', (e) => {
      if (pointer !== e.pointerId) return;
      const dx = e.clientX - startX;
      const dy = e.clientY - startY;
      if (!dragging && Math.hypot(dx, dy) > 6) {
        dragging = true;
        sprite.classList.add('dragging');
        haptic('light');
      }
      if (dragging) sprite.style.transform = `${startTransform} translate(${dx}px, ${dy}px)`;
    });
    const end = (e: PointerEvent, drop: boolean): void => {
      if (pointer !== e.pointerId) return;
      pointer = null;
      if (!dragging) return;
      dragging = false;
      sprite.classList.remove('dragging');
      if (drop) this.dropAt(card, e.clientX, e.clientY);
      else this.render();
    };
    sprite.addEventListener('pointerup', (e) => end(e, true));
    sprite.addEventListener('pointercancel', (e) => end(e, false));
  }

  /** The card goes to the spot nearest where it was dropped (one row or two). */
  private dropAt(card: Card, x: number, y: number): void {
    const v = this.view;
    if (!v) return;
    const hand = this.myHand(v).filter((c) => c !== card);
    const { handW: w, handH: h } = this.lay;
    const places = handPlaces(hand.length + 1, this.lay);
    let at = 0;
    places.forEach((p, i) => {
      const d = Math.hypot(p.x + w / 2 - x, p.y + h / 2 - y);
      const best = places[at]!;
      if (d < Math.hypot(best.x + w / 2 - x, best.y + h / 2 - y)) at = i;
    });
    hand.splice(at, 0, card);
    if (sameOrder(hand, this.myHand(v))) return this.render();
    sound.slide();
    this.order(hand);
  }

  private order(cards: Card[]): void {
    this.localOrder = cards.slice();
    this.send({ type: 'order', cards });
  }

  private shuffle(): void {
    const v = this.view;
    if (!v) return;
    const hand = this.myHand(v).slice();
    for (let i = hand.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [hand[i], hand[j]] = [hand[j]!, hand[i]!];
    }
    sound.deal();
    haptic('medium');
    // The cards gather and spread again.
    for (const s of this.sprites.values()) {
      if (this.feel.reduced) break;
      s.animate([{ translate: '0 0' }, { translate: '0 -22px' }, { translate: '0 0' }], { duration: 360, easing: 'ease-out', composite: 'add' });
    }
    this.order(hand);
  }

  private renderPrompt(v: View): void {
    const u = L().zb;
    const chip = this.turnChip;
    const lay = this.lay;
    place(chip, { x: lay.hand.x + 8, y: lay.hand.y - TURN_CHIP_H + 4, w: lay.hand.w - 16, h: TURN_CHIP_H });
    if (v.phase !== 'play') {
      chip.classList.add('hidden');
      return;
    }
    chip.classList.remove('hidden');
    let text: string;
    if (this.spectator) text = fmt(u.picking, { name: this.nameOf(v.turn), from: this.nameOf(v.from) });
    else if (v.turn === this.me) text = this.sent ? u.drawing : u.yourTurn;
    else if (v.from === this.me) text = fmt(u.pickingYou, { name: this.nameOf(v.turn) });
    else text = fmt(L().ui.waitingFor, { name: this.nameOf(v.turn) });
    chip.textContent = text;
    chip.classList.toggle('mine', v.turn === this.me && !this.spectator);
    chip.classList.toggle('zb-danger', v.from === this.me && !this.spectator);
  }

  private renderActions(v: View): void {
    const u = L().zb;
    const bar = this.actionBar;
    bar.innerHTML = '';
    bar.classList.toggle('my-turn', this.myTurn);
    button(bar, 'btn btn-icon', '☰', L().ui.menu).addEventListener('click', () => this.openMenu());
    if (this.meta.afk[this.me] && !this.spectator) {
      button(bar, 'btn btn-turn', L().ui.imBack, L().ui.imBack).addEventListener('click', () => this.hooks.back());
      return;
    }
    if (this.spectator || v.phase !== 'play') return;
    const hand = this.myHand(v);
    if (hand.length > 1) {
      const b = button(bar, 'btn btn-primary zb-shuffle', `🔀 ${u.shuffle}`, u.shuffle);
      b.title = u.shuffleHelp;
      b.addEventListener('click', () => this.shuffle());
    }
  }

  // ------------------------------------------------------------- moments

  private moment(e: GameEvent, v: View): void {
    const u = L().zb;
    const seat = typeof e.seat === 'number' ? e.seat : null;
    switch (e.type) {
      case 'jester':
        this.chain(async () => {
          this.showJester(e as JesterEvent);
        });
        break;
      case 'round_started':
        this.feel.play(2, 'deal', (ctx) => {
          banner(this.fx, u.dealt, 'info', 'pop', ctx, { x: this.lay.stage.x + this.lay.stage.w / 2, y: this.lay.stage.y + this.lay.stage.h / 2 });
          sound.deal();
        });
        break;
      case 'turn':
        if (e.seat === this.me && !this.spectator) {
          this.lastTickSecond = -1;
          haptic('light');
          this.feel.play(1, 'your_turn', () => sound.chime());
        } else if (e.from === this.me && !this.spectator) haptic('light');
        break;
      case 'drawn_card':
        // Mine only. The Zombie's grin plays on my screen alone; everyone else saw a normal draw.
        if (isZ(e.card as Card)) {
          this.chain(async () => {
            this.feel.play(3, 'zombie_drawn', (ctx) => {
              dim(this.fx, ctx);
              banner(this.fx, `🧟 ${u.gotZombie}`, 'danger', 'banner', ctx);
              shake(this.table, 'big', ctx);
              sound.bass();
              sound.trombone();
              haptic('strong');
            });
            this.announce(u.gotZombie);
          });
        } else this.announce(fmt(u.youDrew, { card: faceLabel(e.card as Card) }));
        break;
      case 'pair':
        this.chain(async () => this.stamp(seat!, u.stamps.pair, 'good'));
        break;
      case 'shuffled':
        if (seat !== this.me || this.spectator) {
          this.stamp(seat!, '🔀', 'info');
          const s = this.seatEls[this.relSeat(seat!) - 1];
          s?.querySelector('.fan')?.animate([{ transform: 'rotate(0)' }, { transform: 'rotate(-18deg)' }, { transform: 'rotate(18deg)' }, { transform: 'rotate(0)' }], { duration: 420 });
        }
        break;
      case 'safe':
        this.chain(async () => {
          const at = this.seatCentreOf(seat!);
          this.feel.play(2, 'safe', (ctx) => {
            banner(this.fx, seat === this.me && !this.spectator ? u.stamps.youSafe : u.stamps.safe, 'good', 'pop', ctx, at);
            burst(this.fx, at.x, at.y, 18, 'good', ctx, 90);
            sound.chime();
            haptic(seat === this.me ? 'strong' : 'light');
          });
        });
        break;
      case 'too_slow':
        this.stamp(seat!, L().ui.tooSlow, 'danger');
        break;
      case 'afk':
        if (seat === this.me) haptic('error');
        break;
      case 'zombie_loser':
        this.chain(async () => {
          await wait(400);
          const at = this.seatCentreOf(seat!);
          this.eaten.add(seat!);
          this.render();
          const me = seat === this.me && !this.spectator;
          this.feel.play(4, 'zombie_loser', (ctx) => {
            dim(this.fx, ctx);
            this.chomp(at, ctx.reduced);
            banner(this.fx, me ? `🧟 ${u.youLose}` : `🧟 ${fmt(u.theyLose, { name: this.nameOf(seat!) })}`, 'danger', 'banner', ctx);
            shake(this.table, 'big', ctx);
            sound.bass();
            sound.trombone();
            haptic('strong');
          });
          await wait(this.feel.reduced ? 800 : 2600);
          if (!this.resultsOpen && this.view?.phase === 'over') {
            this.resultsOpen = true;
            this.results(this.view);
          }
        });
        break;
      default:
    }
  }

  /** The Zombie eats the loser's seat: a big head that bites down on it. */
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

  private seatCentreOf(seat: SeatId): { x: number; y: number } {
    const r = this.seatRect(seat);
    return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
  }

  private announce(text: string): void {
    this.live.textContent = text;
  }

  /** A big word over a seat (or my hand): PAIR!, SAFE! */
  private stamp(seat: SeatId, text: string, role: ColourRole): void {
    if (!this.lay) return;
    const at = this.seatCentreOf(seat);
    this.feel.play(1, 'stamp', (ctx) => banner(this.fx, text, role, 'pop', ctx, at));
  }

  private showJester(e: JesterEvent): void {
    const text = jesterText(e);
    if (!text) return;
    const j = this.jesterEl;
    const lay = this.lay;
    this.stopEmoji?.();
    this.stopEmoji = e.emoji ? playEmoji(this.jesterEmoji, e.emoji) : null;
    j.className = `jester mood-${e.mood} eyes-${EYES[e.mood]}`;
    this.jesterBubble.textContent = text;
    const w = Math.min(lay.vw - 24, 520);
    j.style.width = `${w}px`;
    j.style.left = `${(lay.vw - w) / 2}px`;
    j.style.top = `${Math.max(4, lay.hand.y - JESTER_BAND + 20)}px`;
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
    el('p', 'zb-results-sub', card).textContent = loser === null ? '' : loser === this.me && !this.spectator ? `🧟 ${u.youLose}` : `🧟 ${fmt(u.theyLose, { name: this.nameOf(loser) })}`;
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
      if (loser !== this.me && !this.spectator) {
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
    if (this.fresh && Date.now() > this.fresh.until && v) {
      this.fresh = null;
      this.renderHand(v);
    }
    if (!v || !this.meta.deadline || v.phase !== 'play') {
      this.timerFill.style.transform = 'scaleX(0)';
      return;
    }
    const left = Math.max(0, this.meta.deadline - Date.now());
    const frac = Math.max(0, Math.min(1, left / this.turnTotal));
    const mine = v.turn === this.me && !this.spectator;
    this.timerFill.style.transform = `scaleX(${mine ? frac : 0})`;
    this.timerBar.classList.toggle('urgent', mine && left <= 5000);
    for (const s of this.seatEls) {
      const isTurn = Number(s.dataset.seat) === v.turn;
      s.classList.toggle('urgent', isTurn && left <= 5000);
      const ring = s.querySelector('.ring-fg') as SVGCircleElement | null;
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

const sameOrder = (a: readonly Card[], b: readonly Card[]): boolean => a.length === b.length && a.every((c, i) => c === b[i]);
const samePile = (a: readonly Card[], b: readonly Card[]): boolean => a.length === b.length && a.every((c) => b.includes(c));

function ordinal(n: number): string {
  return fmt(L().zb.place, { n });
}

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
