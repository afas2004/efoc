// The Big Two table: seats, hand, centre, action bar, timers, and every
// key moment from the spec mapped to a tier. State always renders at once;
// effects play on top and never hold the rules back.

import { bigtwo, type Card, type GameEvent, type SeatId } from '@efoc/engine';
import { haptic } from '../../bridge';
import { banner, burst, confetti, dim, shake, type ColourRole } from '../../feel/effects';
import { jesterText, type Humour, type JesterEvent } from '../../feel/jester';
import { EYES, JESTER_SVG, playEmoji, preloadEmoji } from '../../feel/jesterArt';
import { legendary, LEGENDARY_TOTAL_MS } from '../../feel/legendary';
import { sound, unlockAudio, setMuted } from '../../feel/sound';
import { FeelQueue, type Tier } from '../../feel/tiers';
import { L, fmt } from '../../strings';
import { cardLabel, cardsText, makeBack, makeCard } from '../../table/cardFace';
import { TURN_CHIP_H } from '../../table/layout';
import { describeCombo, isLegendary } from './commentary';
import { MatchStats } from './stats';
import { computeLayout, handPlaces, RAISE_PX, type Box, type TableLayout } from '../../table/layout';

type View = bigtwo.BigTwoView;
type Move = bigtwo.BigTwoMove;

export interface SeatMeta {
  name: string;
  avatar: string;
  bot: boolean;
}

export interface TableSettings {
  humour: Humour;
  sound: boolean;
  reducedMotion: boolean;
  fourColour: boolean;
}

export interface TableHooks {
  move(move: Move): void;
  playAgain?: () => void;
  nextRound?: () => void;
  changeRules?: () => void;
  /** Humour is a room setting the host owns. */
  setHumour?: (h: Humour) => void;
  back(): void;
  exit(): void;
}

export interface UpdateMeta {
  deadline: number | null;
  afk: boolean[];
  totals?: number[];
}

interface TrickPlay {
  seat: SeatId;
  cards: Card[];
  kind: string;
}

type SortMode = 'rank' | 'suit' | 'custom';

const TWO = 12;
const LONG_PRESS_MS = 350;
const RESULTS_DELAY_MS = 1400;

export class BigTwoTable {
  readonly feel = new FeelQueue();
  readonly stats = new MatchStats();
  private layout!: TableLayout;
  private view: View | null = null;
  private meta: UpdateMeta = { deadline: null, afk: [] };
  private sprites = new Map<Card, HTMLElement>();
  private selected = new Set<Card>();
  private pending: Card[] | null = null;
  private trick: TrickPlay[] = [];
  /** A trick that ended by auto-pass stays on the table until its moment has played. */
  private clearTimer = 0;
  private clearPending = false;
  /** Every play this round, for the "before" strip. */
  private history: TrickPlay[] = [];
  private sortMode: SortMode = 'rank';
  private customOrder: Card[] = [];
  private outSeats = new Map<SeatId, number>();
  private initialHand = 13;
  private lastTickSecond = -1;
  private announced10 = false;
  private resultsOpen = false;

  // DOM
  private table: HTMLElement;
  private cardLayer: HTMLElement;
  private seatEls: HTMLElement[] = [];
  private centreLabel: HTMLElement;
  private historyEl: HTMLElement;
  private countdown: HTMLElement;
  /** No moves until this time: the look-at-your-cards pause. */
  private previewUntil = 0;
  private lastCount = -1;
  /** True while this update's events include a legendary play. */
  private legendNow = false;
  private turnChip: HTMLElement;
  private handGlow: HTMLElement;
  private timerBar: HTMLElement;
  private timerFill: HTMLElement;
  private actionBar: HTMLElement;
  private playBtn: HTMLButtonElement;
  private passBtn: HTMLButtonElement;
  private sortBtn: HTMLButtonElement;
  private backBtn: HTMLButtonElement;
  private fx: HTMLElement;
  private jesterEl: HTMLElement;
  private jesterBubble: HTMLElement;
  private jesterEmoji: HTMLElement;
  private stopEmoji: (() => void) | null = null;
  private jesterTimer = 0;
  private overlay: HTMLElement;
  private live: HTMLElement;
  private tipEl: HTMLElement;

  constructor(
    private readonly root: HTMLElement,
    readonly me: SeatId,
    private readonly seatMeta: SeatMeta[],
    private readonly isHost: boolean,
    private readonly hooks: TableHooks,
    public settings: TableSettings,
  ) {
    root.innerHTML = '';
    root.className = 'efoc-root felt-bigtwo';
    this.table = el('div', 'table', root);
    this.cardLayer = el('div', 'card-layer', this.table);
    this.centreLabel = el('div', 'centre-label', this.table);
    this.historyEl = el('div', 'history', this.table);
    this.countdown = el('div', 'countdown hidden', root);
    this.handGlow = el('div', 'hand-glow', this.table);
    this.turnChip = el('div', 'turn-chip hidden', this.table);
    this.turnChip.setAttribute('aria-live', 'polite');
    this.timerBar = el('div', 'timer-bar', this.table);
    this.timerFill = el('div', 'timer-fill', this.timerBar);
    this.actionBar = el('div', 'action-bar', this.table);
    const menuBtn = button(this.actionBar, 'btn btn-icon', '☰', L().ui.menu);
    this.sortBtn = button(this.actionBar, 'btn btn-ghost', L().ui.sortRank, L().ui.sort);
    this.backBtn = button(this.actionBar, 'btn btn-turn hidden', L().ui.imBack, L().ui.imBack);
    this.passBtn = button(this.actionBar, 'btn btn-secondary', L().ui.pass, L().ui.pass);
    this.playBtn = button(this.actionBar, 'btn btn-primary', L().ui.play, L().ui.play);
    this.fx = el('div', 'fx-layer', root);
    this.jesterEl = el('div', 'jester hidden', root);
    this.jesterEl.setAttribute('aria-live', 'polite');
    const figure = el('div', 'jester-figure', this.jesterEl);
    figure.innerHTML = JESTER_SVG;
    this.jesterEmoji = el('div', 'jester-emoji', figure);
    this.jesterBubble = el('div', 'jester-bubble', this.jesterEl);
    preloadEmoji(['laugh', 'explode', 'party', 'scream', 'cool', 'fire', 'grimace', 'eyeroll']);
    this.tipEl = el('div', 'tip hidden', root);
    this.overlay = el('div', 'overlay hidden', root);
    this.live = el('div', 'sr-only', root);
    this.live.setAttribute('aria-live', 'assertive');

    menuBtn.addEventListener('click', () => this.openMenu());
    this.sortBtn.addEventListener('click', () => this.toggleSort());
    this.passBtn.addEventListener('click', () => this.pass());
    this.playBtn.addEventListener('click', () => this.play());
    this.backBtn.addEventListener('click', () => this.hooks.back());
    document.addEventListener('pointerdown', () => unlockAudio(), { capture: true });
    window.addEventListener('resize', () => this.render());
    this.applySettings();
    this.tick();
  }

  // ------------------------------------------------------------ settings

  applySettings(): void {
    const reduced = this.settings.reducedMotion || matchMedia('(prefers-reduced-motion: reduce)').matches;
    this.feel.reduced = reduced;
    this.root.classList.toggle('reduced-motion', reduced);
    this.root.classList.toggle('four-colour', this.settings.fourColour);
    setMuted(!this.settings.sound);
  }

  // ------------------------------------------------------------- updates

  /** New state from the host, with the events that produced it. */
  update(view: View, events: GameEvent[], meta: UpdateMeta): void {
    const prev = this.view;
    this.view = view;
    this.meta = meta;
    // A confirmed play replaces the optimistic one.
    if (this.pending && events.some((e) => e.type === 'card_played' && e.seat === this.me)) this.pending = null;
    if (this.pending && view.turn !== this.me) this.pending = null;
    for (const c of [...this.selected]) if (!view.hand.includes(c)) this.selected.delete(c);
    const legend = events.find((e) => e.type === 'card_played' && isLegendary(e.cards as Card[], e.kind as string));
    this.legendNow = !!legend;
    const autoPass = events.some((e) => e.type === 'card_played') && events.some((e) => e.type === 'all_passed');
    for (const e of events) {
      if (e.type === 'all_passed' && autoPass) {
        this.holdTrick(this.legendNow ? LEGENDARY_TOTAL_MS + 1000 : 1600);
        continue;
      }
      if (e.type === 'round_started' && e.round === 1) this.stats.reset(view.players);
      if (e.type === 'round_started') this.previewUntil = Date.now() + ((e.previewMs as number) ?? 0);
      this.stats.feed(e, view.players);
      this.trackTrick(e);
    }
    this.render(prev, events);
    if (legend) this.legendaryPlay(legend, events);
    for (const e of events) this.moment(e, view);
    this.legendNow = false;
    const myTurnNow = view.phase === 'play' && view.turn === this.me;
    const myTurnBefore = !!prev && prev.phase === 'play' && prev.turn === this.me && !events.some((e) => e.type === 'round_started');
    if (myTurnNow && !myTurnBefore && !this.meta.afk[this.me]) this.yourTurn();
  }

  /** The throw-and-slam moment for a single 2♠ or a straight flush. */
  private legendaryPlay(e: GameEvent, events: GameEvent[]): void {
    const seat = e.seat as number;
    const cards = e.cards as Card[];
    const kind = e.kind as string;
    const u = L().ui;
    const name = this.seatMeta[seat]?.name ?? '';
    const unbeatable = events.find((x) => x.type === 'unbeatable');
    if (unbeatable) this.skipAllPassed = true;
    const isTwo = kind === 'single';
    const royal = !isTwo && ['T', 'J', 'Q', 'K', 'A'].every((r) => cards.some((c) => c[0] === r));
    const left = e.left as number;
    const title = isTwo ? u.legend2s : royal ? u.royalFlush : u.straightFlush;
    const subtitle = isTwo
      ? fmt(left === 1 ? u.legend2sWin : u.legend2sSub, { name })
      : fmt(u.flushSub, { name, combo: describeCombo(cards, kind) });
    const sprites = cards.map((c) => this.sprites.get(c)).filter((x): x is HTMLElement => !!x);
    const from = seat === this.me ? this.handTop() : this.seatCentre(seat);
    this.feel.play(
      3,
      'legendary',
      (ctx) =>
        legendary(
          {
            fx: this.fx,
            table: this.table,
            root: this.root,
            sprites,
            from,
            stage: this.layout.stage,
            vw: this.layout.vw,
            cardW: this.layout.handW,
            title,
            subtitle,
            role: left === 1 || royal ? 'good' : 'power',
            afterImpact: () => {
              const passed = (unbeatable?.passed as number[] | undefined) ?? [];
              for (const s of passed) this.stamp(s, L().ui.stampPass, 'pass');
              if (passed.length) sound.pass();
            },
          },
          ctx,
        ),
      LEGENDARY_TOTAL_MS,
    );
  }

  /** The cue that it's my turn: banner over the table, glowing hand, chime, haptic. */
  private yourTurn(): void {
    this.myTurnCue();
    this.feel.play(2, 'your_turn', (ctx) => {
      const c = this.layout.stage;
      banner(this.fx, L().ui.yourTurnBig, 'turn', 'pop', ctx, { x: c.x + c.w / 2, y: this.layout.hand.y - TURN_CHIP_H - 48 });
      sound.chime();
      haptic('medium');
    });
  }

  /** The host rejected my move: snap back with the reason. */
  reject(reason: string): void {
    this.pending = null;
    this.render();
    sound.error();
    haptic('error');
    this.feel.play(1, 'rejected', (ctx) => {
      shake(this.cardLayer, 'small', ctx);
      banner(this.fx, reason, 'danger', 'pop', ctx, this.handTop());
    });
  }

  /** Keeps the current trick on the table for `ms`, then clears it. */
  private holdTrick(ms: number): void {
    this.clearPending = true;
    window.clearTimeout(this.clearTimer);
    this.clearTimer = window.setTimeout(() => {
      if (!this.clearPending) return;
      this.clearPending = false;
      this.trick = [];
      this.render();
    }, ms);
  }

  private trackTrick(e: GameEvent): void {
    if (this.clearPending && (e.type === 'card_played' || e.type === 'round_started')) {
      this.clearPending = false;
      window.clearTimeout(this.clearTimer);
      this.trick = [];
    }
    if (e.type === 'round_started') {
      this.trick = [];
      this.history = [];
      this.outSeats.clear();
      this.customOrder = [];
      this.resultsOpen = false;
      this.closeOverlay();
      this.initialHand = this.view?.hand.length || 13;
    } else if (e.type === 'card_played') {
      const play = { seat: e.seat as number, cards: e.cards as Card[], kind: e.kind as string };
      this.trick.push(play);
      this.history.push(play);
      if (this.history.length > 3) this.history.shift();
    } else if (e.type === 'all_passed') {
      this.trick = [];
    } else if (e.type === 'player_out') {
      this.outSeats.set(e.seat as number, e.place as number);
    }
  }

  // -------------------------------------------------------------- render

  private relSeat(seat: SeatId): number {
    const n = this.view?.players ?? this.seatMeta.length;
    return (seat - this.me + n) % n;
  }

  private seatBox(seat: SeatId): Box | null {
    const r = this.relSeat(seat);
    return r === 0 ? null : this.layout.seats[r - 1] ?? null;
  }

  private seatCentre(seat: SeatId): { x: number; y: number } {
    const b = this.seatBox(seat);
    if (!b) return this.handTop();
    return { x: b.x + b.w / 2, y: b.y + b.h / 2 };
  }

  private handTop(): { x: number; y: number } {
    return { x: this.layout.hand.x + this.layout.hand.w / 2, y: this.layout.hand.y };
  }

  private sortedHand(hand: Card[]): Card[] {
    if (this.sortMode === 'custom') {
      const known = this.customOrder.filter((c) => hand.includes(c));
      return [...known, ...bigtwo.sortCards(hand.filter((c) => !known.includes(c)))];
    }
    if (this.sortMode === 'suit') {
      return [...hand].sort((a, b) => bigtwo.suitIndex(a) - bigtwo.suitIndex(b) || bigtwo.rankIndex(a) - bigtwo.rankIndex(b));
    }
    return bigtwo.sortCards(hand);
  }

  render(prev?: View | null, events: GameEvent[] = []): void {
    const v = this.view;
    if (!v) return;
    const vw = this.root.clientWidth || window.innerWidth;
    const vh = this.root.clientHeight || window.innerHeight;
    this.layout = computeLayout(vw, vh, v.players, readInsets(), Math.max(v.hand.length, 1));
    const lay = this.layout;
    this.root.style.setProperty('--card-w', `${lay.handW}px`);
    this.root.style.setProperty('--card-h', `${lay.handH}px`);

    this.renderSeats(v);
    place(this.timerBar, lay.timerBar);
    place(this.actionBar, lay.actionBar);

    // Cards: my hand (minus an optimistic play) and the centre trick.
    const handCards = this.sortedHand(v.hand.filter((c) => !this.pending?.includes(c)));
    const places = handPlaces(handCards.length, lay);
    const wanted = new Map<Card, { x: number; y: number; rot: number; scale: number; z: number; opacity: number }>();
    handCards.forEach((c, i) => {
      const p = places[i]!;
      const up = this.selected.has(c) ? RAISE_PX : 0;
      wanted.set(c, { x: p.x, y: p.y - up, rot: p.rot, scale: 1, z: 10 + p.z, opacity: 1 });
    });
    const plays: TrickPlay[] = [...this.trick];
    if (this.pending) plays.push({ seat: this.me, cards: this.pending, kind: '' });
    const shown = plays.slice(-2);
    const c = lay.stage;
    // Centre cards shrink to fit the play area: five cards across, current play plus the one under it.
    const HIST_H = 46;
    const LABEL_H = 34;
    const tableScale = Math.min(1.25, (lay.cardW * 1.6) / lay.handW, c.w / (3.5 * lay.handW), Math.max(0.3, (c.h - LABEL_H - HIST_H) / (lay.handH * 1.38)));
    const midY = c.y + HIST_H + (c.h - HIST_H - LABEL_H) * 0.55;
    shown.forEach((play, idx) => {
      const current = idx === shown.length - 1;
      const s = current ? tableScale : tableScale * 0.8;
      const w = lay.handW * s;
      const step = w * 0.62;
      const total = w + step * (play.cards.length - 1);
      const x0 = c.x + (c.w - total) / 2;
      const y = midY - (lay.handH * s) / 2 - (current ? 0 : lay.handH * s * 0.35);
      play.cards.forEach((card, i) => {
        wanted.set(card, { x: x0 + i * step, y, rot: current ? (i - (play.cards.length - 1) / 2) * 2 : -4, scale: s, z: (current ? 300 : 200) + i, opacity: current ? 1 : 0.55 });
      });
    });

    // Remove sprites that left the table.
    for (const [card, sprite] of this.sprites) {
      if (wanted.has(card)) continue;
      this.sprites.delete(card);
      sprite.style.opacity = '0';
      sprite.style.pointerEvents = 'none';
      setTimeout(() => sprite.remove(), 260);
    }
    // Place sprites; new ones start where they come from.
    const playedBy = new Map<Card, SeatId>();
    for (const e of events) if (e.type === 'card_played') for (const card of e.cards as Card[]) playedBy.set(card, e.seat as number);
    const dealing = events.some((e) => e.type === 'round_started');
    let dealIndex = 0;
    for (const [card, t] of wanted) {
      let sprite = this.sprites.get(card);
      if (!sprite) {
        sprite = makeCard(card);
        this.cardLayer.appendChild(sprite);
        this.sprites.set(card, sprite);
        this.bindCard(sprite, card);
        const from = playedBy.has(card) ? this.seatCentre(playedBy.get(card)!) : dealing ? { x: c.x + c.w / 2, y: c.y + c.h / 2 } : null;
        if (from) {
          sprite.classList.add('no-anim');
          sprite.style.transform = `translate(${from.x - lay.handW * 0.2}px, ${from.y - lay.handH * 0.2}px) scale(0.4)`;
          sprite.style.opacity = '0';
          void sprite.offsetWidth;
          sprite.classList.remove('no-anim');
          if (dealing) sprite.style.transitionDelay = `${Math.min(dealIndex++ * 25, 300)}ms`;
        }
      }
      sprite.style.transform = `translate(${t.x}px, ${t.y}px) rotate(${t.rot}deg) scale(${t.scale})`;
      sprite.style.opacity = String(t.opacity);
      sprite.style.zIndex = String(t.z);
      const inHand = t.z < 200;
      sprite.classList.toggle('in-hand', inHand);
      sprite.classList.toggle('selected', this.selected.has(card));
      sprite.setAttribute('aria-label', cardLabel(card, this.selected.has(card)));
      sprite.tabIndex = inHand ? 0 : -1;
      sprite.setAttribute('role', inHand ? 'button' : 'img');
      sprite.setAttribute('aria-pressed', inHand ? String(this.selected.has(card)) : 'false');
      if (dealing) setTimeout(() => (sprite!.style.transitionDelay = ''), 400);
    }

    // Centre label: what is on the table and who played it.
    const top = this.trick[this.trick.length - 1];
    this.centreLabel.textContent = top
      ? `${this.nameOf(top.seat)}: ${describeCombo(top.cards, top.kind)}`
      : '';
    place(this.centreLabel, { x: c.x, y: midY + lay.handH * tableScale * 0.56, w: c.w, h: 30 });
    this.renderHistory(c);
    this.renderTurn(v);

    this.renderButtons();
    void prev;
  }

  /** The two plays before the current one, so a fast table can be followed. */
  private renderHistory(c: Box): void {
    const before = this.history.slice(0, -1).slice(-2);
    const h = this.historyEl;
    h.innerHTML = '';
    if (before.length === 0) {
      h.classList.add('hidden');
      return;
    }
    h.classList.remove('hidden');
    el('span', 'history-label', h).textContent = L().ui.previous;
    for (const p of before) {
      const row = el('span', 'history-item', h);
      el('span', 'history-who', row).textContent = `${this.seatMeta[p.seat]!.avatar} ${this.nameOf(p.seat)}`;
      const cards = el('span', 'history-cards', row);
      for (const card of p.cards) {
        const chip = el('span', `history-card suit-${card[1]}`, cards);
        chip.textContent = cardsText([card]);
      }
    }
    h.style.left = `${c.x}px`;
    h.style.top = `${c.y}px`;
    h.style.width = `${c.w}px`;
  }

  /** Whose turn it is, always visible just above my hand. */
  private renderTurn(v: View): void {
    const chip = this.turnChip;
    const lay = this.layout;
    if (v.phase !== 'play' || this.resultsOpen) {
      chip.className = 'turn-chip hidden';
      this.handGlow.className = 'hand-glow';
      return;
    }
    const mine = v.turn === this.me;
    const u = L().ui;
    const waitS = Math.ceil((this.previewUntil - Date.now()) / 1000);
    chip.textContent = waitS > 0
      ? fmt(u.startingIn, { n: waitS })
      : mine
      ? v.mustInclude
        ? fmt(u.turnOpen, { card: cardsText([v.mustInclude]) })
        : v.lead
          ? u.turnFollow
          : u.turnLead
      : fmt(u.waitingFor, { name: this.seatMeta[v.turn]?.name ?? '' });
    chip.className = `turn-chip${mine ? ' mine' : ''}`;
    const w = Math.min(lay.hand.w, 340);
    place(chip, { x: lay.hand.x + (lay.hand.w - w) / 2, y: lay.hand.y - TURN_CHIP_H - 2, w, h: TURN_CHIP_H });
    this.handGlow.className = `hand-glow${mine ? ' on' : ''}`;
    place(this.handGlow, lay.hand);
  }

  private renderSeats(v: View): void {
    const lay = this.layout;
    while (this.seatEls.length < v.players - 1) {
      const s = el('div', 'seat', this.table);
      s.innerHTML =
        '<div class="avatar"><svg class="ring" viewBox="0 0 36 36"><circle class="ring-bg" cx="18" cy="18" r="16"/><circle class="ring-fg" cx="18" cy="18" r="16"/></svg><span class="face"></span><span class="dot"></span></div>' +
        '<div class="name"></div><div class="info"><span class="count"></span><span class="score"></span></div><div class="chip hidden"></div><div class="fan"></div><div class="stamp"></div>';
      this.seatEls.push(s);
    }
    for (let r = 1; r < v.players; r++) {
      const seat = (this.me + r) % v.players;
      const s = this.seatEls[r - 1]!;
      place(s, lay.seats[r - 1]!);
      s.classList.toggle('compact', lay.compact);
      s.dataset.seat = String(seat);
      const meta = this.seatMeta[seat]!;
      s.querySelector('.face')!.textContent = meta.avatar;
      s.querySelector('.name')!.textContent = meta.name.slice(0, 8);
      const count = v.handCounts[seat]!;
      const fan = s.querySelector('.fan') as HTMLElement;
      const backs = Math.min(count, 5);
      if (fan.childElementCount !== backs) {
        fan.innerHTML = '';
        for (let i = 0; i < backs; i++) fan.appendChild(makeBack());
      }
      fan.dataset.count = String(count);
      s.querySelector('.count')!.textContent = count === 1 ? L().ui.oneCard : fmt(L().ui.cardsLeft, { n: count });
      const total = this.meta.totals?.[seat] ?? v.scores[seat] ?? 0;
      s.querySelector('.score')!.textContent = v.round > 1 || total ? fmt(L().ui.points, { n: total }) : '';
      const isTurn = v.phase === 'play' && v.turn === seat;
      s.classList.toggle('turn', isTurn);
      s.classList.toggle('passed', v.passed[seat] === true && v.lead !== null);
      s.classList.toggle('out', this.outSeats.has(seat));
      s.classList.toggle('last-card', count === 1);
      const afk = this.meta.afk[seat] === true;
      s.classList.toggle('bot', meta.bot || afk);
      const chip = s.querySelector('.chip') as HTMLElement;
      if (this.outSeats.has(seat)) {
        chip.textContent = fmt(L().ui.place, { n: this.outSeats.get(seat)! });
        chip.className = 'chip chip-gold';
      } else if (afk) {
        chip.textContent = L().ui.afk;
        chip.className = 'chip chip-danger';
      } else if (v.passed[seat] && v.lead) {
        chip.textContent = L().ui.pass_chip;
        chip.className = 'chip';
      } else chip.className = 'chip hidden';
      s.setAttribute('aria-label', `${meta.name}, ${s.querySelector('.count')!.textContent}${isTurn ? ', ' + L().ui.yourTurn.toLowerCase() : ''}`);
    }
    for (let r = v.players - 1; r < this.seatEls.length; r++) this.seatEls[r]!.remove();
    this.seatEls.length = v.players - 1;
  }

  private selectionPlay(): bigtwo.Combo | null {
    const v = this.view;
    if (!v || v.phase !== 'play' || v.turn !== this.me || this.pending || Date.now() < this.previewUntil) return null;
    const cards = [...this.selected];
    const combo = bigtwo.classify(cards, v.config);
    if (!combo) return null;
    if (v.mustInclude && !cards.includes(v.mustInclude)) return null;
    if (v.lead) {
      const lead = bigtwo.classify(v.lead.cards, v.config);
      if (!lead || !bigtwo.beats(combo, lead)) return null;
    }
    return combo;
  }

  private renderButtons(): void {
    const v = this.view!;
    const myTurn = v.phase === 'play' && v.turn === this.me && !this.pending;
    const combo = this.selectionPlay();
    this.playBtn.disabled = !combo;
    this.playBtn.textContent = combo ? `${L().ui.play} ${(L().ui.combo as Record<string, string>)[combo.kind]}` : L().ui.play;
    this.passBtn.disabled = !(myTurn && v.lead) || Date.now() < this.previewUntil;
    const afk = this.meta.afk[this.me] === true;
    this.backBtn.classList.toggle('hidden', !afk);
    this.passBtn.classList.toggle('hidden', afk);
    this.actionBar.classList.toggle('my-turn', myTurn);
    this.timerBar.classList.toggle('hidden', !(v.phase === 'play' && this.meta.deadline));
    this.sortBtn.textContent = this.sortMode === 'suit' ? L().ui.sortSuit : L().ui.sortRank;
  }

  // --------------------------------------------------------------- input

  private bindCard(sprite: HTMLElement, card: Card): void {
    let startX = 0;
    let startY = 0;
    let pressTimer: ReturnType<typeof setTimeout> | null = null;
    let dragging = false;
    let moved = false;
    let pointer: number | null = null;
    const base = (): string => sprite.style.transform;
    let startTransform = '';

    sprite.addEventListener('pointerdown', (e) => {
      if (!sprite.classList.contains('in-hand')) return;
      pointer = e.pointerId;
      startX = e.clientX;
      startY = e.clientY;
      moved = false;
      dragging = false;
      startTransform = base();
      try {
        sprite.setPointerCapture(e.pointerId);
      } catch {
        /* synthetic events */
      }
      pressTimer = setTimeout(() => {
        dragging = true;
        sprite.classList.add('dragging');
        haptic('light');
      }, LONG_PRESS_MS);
    });
    sprite.addEventListener('pointermove', (e) => {
      if (pointer !== e.pointerId) return;
      const dx = e.clientX - startX;
      const dy = e.clientY - startY;
      if (Math.abs(dx) > 8 || Math.abs(dy) > 8) moved = true;
      if (dragging) {
        sprite.style.transform = `${startTransform} translate(${dx}px, ${dy}px)`;
        return;
      }
      if (moved && pressTimer) {
        clearTimeout(pressTimer);
        pressTimer = null;
      }
    });
    const up = (e: PointerEvent): void => {
      if (pointer !== e.pointerId) return;
      pointer = null;
      if (pressTimer) clearTimeout(pressTimer);
      pressTimer = null;
      const dx = e.clientX - startX;
      const dy = e.clientY - startY;
      if (dragging) {
        dragging = false;
        sprite.classList.remove('dragging');
        this.dropAt(card, e.clientX);
        return;
      }
      if (dy < -40 && Math.abs(dx) < 50 && this.selected.has(card)) {
        this.play(); // swipe up on a selected card plays
        return;
      }
      if (!moved) this.toggle(card);
    };
    sprite.addEventListener('pointerup', up);
    sprite.addEventListener('pointercancel', (e) => {
      if (pointer !== e.pointerId) return;
      pointer = null;
      if (pressTimer) clearTimeout(pressTimer);
      dragging = false;
      sprite.classList.remove('dragging');
      this.render();
    });
    sprite.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        if (sprite.classList.contains('in-hand')) this.toggle(card);
      }
    });
  }

  private toggle(card: Card): void {
    if (this.selected.has(card)) this.selected.delete(card);
    else this.selected.add(card);
    sound.click();
    haptic('light');
    this.feel.play(0, 'select', () => {});
    this.render();
  }

  private dropAt(card: Card, clientX: number): void {
    const v = this.view!;
    const order = this.sortedHand(v.hand).filter((c) => c !== card);
    const rect = this.root.getBoundingClientRect();
    const x = clientX - rect.left;
    const places = handPlaces(order.length + 1, this.layout);
    let idx = places.findIndex((p) => p.x + this.layout.handW / 2 > x);
    if (idx < 0) idx = order.length;
    order.splice(idx, 0, card);
    this.customOrder = order;
    this.sortMode = 'custom';
    this.feel.play(0, 'reorder', () => {});
    sound.click();
    this.render();
  }

  private toggleSort(): void {
    this.sortMode = this.sortMode === 'suit' ? 'rank' : 'suit';
    sound.sort();
    this.feel.play(0, 'sort', () => {});
    this.render();
  }

  private play(): void {
    const combo = this.selectionPlay();
    if (!combo) return;
    const cards = bigtwo.sortCards([...this.selected]);
    this.selected.clear();
    // Animate at once; the host confirms (or snaps it back) right after.
    this.pending = cards;
    haptic('light');
    this.render();
    this.hooks.move({ type: 'play', cards });
  }

  private pass(): void {
    const v = this.view;
    if (!v || v.turn !== this.me || !v.lead) return;
    this.selected.clear();
    this.hooks.move({ type: 'pass' });
  }

  // ------------------------------------------------------------- moments

  private nameOf(seat: SeatId): string {
    return seat === this.me ? L().ui.you : this.seatMeta[seat]?.name ?? '';
  }

  /** The Jester speaks: big figure, mood, reaction emoji and a speech bubble everyone sees. */
  private showJester(e: JesterEvent): void {
    const text = jesterText(e);
    if (!text) return;
    const j = this.jesterEl;
    const lay = this.layout;
    this.stopEmoji?.();
    this.stopEmoji = e.emoji ? playEmoji(this.jesterEmoji, e.emoji) : null;
    j.className = `jester mood-${e.mood} eyes-${EYES[e.mood]}`;
    this.jesterBubble.textContent = text;
    // Portrait: in the empty band between the centre cards and my hand, below
    // the side seats. Landscape: over the top of the play area.
    const w = Math.min(lay.vw - 24, 520);
    j.style.width = `${w}px`;
    j.style.left = `${(lay.vw - w) / 2}px`;
    const jh = 116;
    j.style.top = `${lay.portrait ? Math.max(lay.centre.y, lay.hand.y - TURN_CHIP_H - jh - 10) : Math.max(4, lay.centre.y - 20)}px`;
    // Restart the entrance animation.
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
    if (e.mood === 'laugh' || e.mood === 'shock') haptic('medium');
  }

  /** A big word that fades in and out over a seat (or my hand): PASS, PAIR, OUT! */
  private stamp(seat: SeatId, text: string, role: ColourRole | 'pass'): void {
    const target = seat === this.me ? null : this.seatEls[this.relSeat(seat) - 1];
    const el = target?.querySelector('.stamp') as HTMLElement | null;
    if (el) {
      el.textContent = text;
      el.className = `stamp stamp-${role}`;
      void el.offsetWidth;
      el.classList.add('show');
      return;
    }
    // My own action: stamp above my hand.
    this.feel.play(1, 'stamp', (ctx) => banner(this.fx, text, role === 'pass' ? 'neutral' : role, 'pop', ctx, this.handTop()));
  }

  private pop(tier: Tier, name: string, text: string, role: ColourRole, at: { x: number; y: number }): void {
    this.feel.play(tier, name, (ctx) => banner(this.fx, text, role, 'pop', ctx, at));
  }

  private moment(e: GameEvent, v: View): void {
    const seat = typeof e.seat === 'number' ? e.seat : null;
    switch (e.type) {
      case 'jester':
        this.showJester(e as JesterEvent);
        break;
      case 'round_started': {
        this.feel.play(1, 'deal', () => sound.deal());
        if (v.config.roundsToPlay > 1 && v.round === v.config.roundsToPlay) this.big('final_round', L().ui.finalRound, 'danger');
        if (v.turn === this.me) this.myTurnCue();
        break;
      }
      case 'card_played': {
        const cards = e.cards as Card[];
        const legendaryHere = this.legendNow && isLegendary(cards, e.kind as string);
        if (!legendaryHere) {
          this.feel.play(1, 'card_played', () => {
            if (seat !== this.me) sound.slide();
            cards.forEach((_, i) => setTimeout(() => sound.thud(i), 120 + i * 55));
          });
        }
        if (seat === this.me) haptic('light');
        if (seat !== null) {
          const kind = (L().ui.combo as Record<string, string>)[e.kind as string] ?? '';
          this.stamp(seat, kind.toUpperCase(), 'turn');
          const isTwo = cards.length === 1 && bigtwo.rankIndex(cards[0]!) === TWO && !legendaryHere;
          const twosInCombo = cards.length > 1 && cards.some((c) => bigtwo.rankIndex(c) === TWO);
          if (twosInCombo && !legendaryHere && (e.left as number) >= this.initialHand / 2) {
            this.big('big_spender', L().ui.bigSpender, 'danger', true);
          }
          if (isTwo) {
            this.pop(2, 'two', '2!', 'danger', { x: this.layout.stage.x + this.layout.stage.w / 2, y: this.layout.stage.y + 20 });
            sound.whoosh();
          }
          if ((e.left as number) === 1) {
            this.pop(2, 'one_card', L().ui.oneCard.toUpperCase() + '!', 'danger', this.seatCentre(seat));
            haptic('medium');
          }
        }
        if (v.phase === 'play' && v.turn === this.me) this.myTurnCue();
        break;
      }
      case 'bomb':
        if (!this.legendNow) this.big('bomb', L().ui.bomb, 'danger', true);
        break;
      case 'unbeatable':
        if (!this.legendNow) this.unbeatable(seat!, (e.left as number) === 1, e.passed as number[]);
        break;
      case 'passed': {
        this.feel.play(1, 'passed', () => sound.pass());
        if (seat !== null) this.stamp(seat, L().ui.stampPass, 'pass');
        if (v.phase === 'play' && v.turn === this.me) this.myTurnCue();
        break;
      }
      case 'all_passed': {
        if (this.skipAllPassed) {
          this.skipAllPassed = false;
          break;
        }
        const winner = seat!;
        this.feel.play(2, 'all_passed', (ctx) => {
          sound.whoosh();
          setTimeout(() => sound.chime(), 120);
          if (winner === this.me) haptic('medium');
          banner(this.fx, L().ui.nobody, 'good', 'pop', ctx, this.seatCentre(winner));
        });
        break;
      }
      case 'player_out': {
        this.feel.play(2, 'player_out', (ctx) => {
          sound.chime();
          haptic('medium');
          const at = this.seatCentre(seat!);
          banner(this.fx, fmt(L().ui.place, { n: e.place as number }), 'good', 'pop', ctx, at);
          burst(this.fx, at.x, at.y, 14, 'good', ctx, 70);
        });
        break;
      }
      case 'too_slow':
        this.pop(1, 'too_slow', L().ui.tooSlow, 'danger', this.seatCentre(seat!));
        break;
      case 'afk':
        if (seat === this.me) haptic('error');
        break;
      case 'double_it':
        this.big('double_it', L().ui.doubleIt, 'danger');
        break;
      case 'match_points':
        // Let the last play land before the results cover the table.
        this.resultsOpen = true;
        window.setTimeout(() => this.results(this.view ?? v, e), RESULTS_DELAY_MS);
        break;
      default:
        break;
    }
  }

  private skipAllPassed = false;

  /**
   * Nothing can beat this play: boom, then every other seat stamps PASS at
   * the same moment. With one card left after it, the win is certain, so it
   * gets the biggest moment in the game.
   */
  private unbeatable(seat: SeatId, unstoppable: boolean, passed: number[]): void {
    this.skipAllPassed = true;
    const text = unstoppable ? L().ui.unstoppable : L().ui.unbeatable;
    this.feel.play(3, unstoppable ? 'unstoppable' : 'unbeatable', (ctx) => {
      dim(this.fx, ctx);
      banner(this.fx, text, unstoppable ? 'good' : 'danger', 'banner', ctx);
      shake(this.table, 'big', ctx);
      const c = this.layout.stage;
      const cx = c.x + c.w / 2;
      const cy = c.y + c.h * 0.5;
      burst(this.fx, cx, cy, unstoppable ? 44 : 30, 'danger', ctx, unstoppable ? 220 : 170);
      if (unstoppable) burst(this.fx, cx, cy, 30, 'good', ctx, 140);
      sound.bass();
      if (unstoppable) window.setTimeout(() => sound.bass(), 260);
      haptic('strong');
      this.root.classList.add(unstoppable ? 'flash-gold' : 'flash-red');
      ctx.onEnd(() => this.root.classList.remove('flash-gold', 'flash-red'));
      // Everyone else passes at once, in sync.
      window.setTimeout(() => {
        for (const s of passed) this.stamp(s, L().ui.stampPass, 'pass');
        sound.pass();
      }, ctx.reduced ? 0 : 450);
    });
  }

  /** A T3: table dims, banner, big shake, burst, bass hit, strong haptic. */
  private big(name: string, text: string, role: ColourRole, explode = false): void {
    this.feel.play(3, name, (ctx) => {
      dim(this.fx, ctx);
      banner(this.fx, text, role, 'banner', ctx);
      shake(this.table, 'big', ctx);
      const c = this.layout.stage;
      if (explode) burst(this.fx, c.x + c.w / 2, c.y + c.h * 0.42, 28, role, ctx, 160);
      sound.bass();
      haptic('strong');
    });
  }

  private myTurnCue(): void {
    this.lastTickSecond = -1;
    this.announced10 = false;
    haptic('light');
  }

  // ------------------------------------------------------------- results

  private results(v: View, e: GameEvent): void {
    if (!this.resultsOpen) return; // a new round started meanwhile
    const placings = e.placings as number[];
    const points = e.points as number[];
    const totals = e.totals as number[];
    const doubled = e.doubled as boolean[];
    const winner = placings[0]!;
    const last = placings[placings.length - 1]!;
    const matchOver = v.phase === 'matchOver';
    this.feel.play(4, 'results', (ctx) => {
      if (winner === this.me) sound.fanfare();
      else if (last === this.me) sound.trombone();
      else sound.chime();
      haptic(winner === this.me ? 'strong' : 'medium');
      confetti(this.fx, this.layout.vw, ctx);
    });
    const o = this.overlay;
    o.innerHTML = '';
    o.className = 'overlay results';
    const card = el('div', 'sheet results-sheet', o);
    const u = L().ui;
    const mode = v.config.mode === 'fightTillTheEnd' ? u.modeFtte : u.modeStandard;
    el('h2', '', card).textContent = `${matchOver ? u.results : fmt(u.round, { n: v.round })} · ${mode}`;
    // Pedestal: 2nd, 1st, 3rd from left to right; the rest listed below.
    const stand = el('div', 'podium', card);
    for (const place of [1, 0, 2]) {
      const seat = placings[place];
      if (seat === undefined || place >= placings.length) continue;
      const step = el('div', `podium-step p${place + 1}`, stand);
      const av = el('div', 'podium-avatar', step);
      av.textContent = this.seatMeta[seat]!.avatar;
      if (place === 0) el('span', 'podium-crown', av).textContent = '👑';
      el('div', 'podium-name', step).textContent = this.nameOf(seat);
      el('div', 'podium-pts', step).textContent = `+${points[seat]}${doubled[seat] ? ` (${u.doubled})` : ''}`;
      el('div', 'podium-block', step).textContent = String(place + 1);
    }
    const podium = el('ol', 'standings rest', card);
    placings.forEach((seat, place) => {
      if (place < 3) return;
      const li = el('li', `standing place-${place + 1}${seat === winner ? ' winner' : ''}${seat === last ? ' last' : ''}`, podium);
      const medal = ['🥇', '🥈', '🥉'][place] ?? `${place + 1}.`;
      li.innerHTML = `<span class="medal"></span><span class="who"></span><span class="pts"></span>`;
      li.querySelector('.medal')!.textContent = medal;
      li.querySelector('.who')!.textContent = `${this.seatMeta[seat]!.avatar} ${this.nameOf(seat)}`;
      const left = v.handCounts[seat]!;
      li.querySelector('.pts')!.textContent =
        `+${points[seat]}${doubled[seat] ? ` (${u.doubled})` : ''}` + (matchOver && v.round > 1 ? ` · ${totals[seat]}` : '') + (left ? ` · ${left === 1 ? u.oneCard : fmt(u.cardsLeft, { n: left })}` : '');
    });

    if (this.stats.verdict) {
      const r = el('div', 'roast', card);
      el('span', 'roast-face', r).textContent = '🃏';
      el('span', '', r).textContent = jesterText(this.stats.verdict);
    }
    const hl = this.stats.top(3);
    if (hl.length > 0) {
      el('h3', 'stats-title', card).textContent = u.highlights;
      const list = el('ol', 'highlights', card);
      const key = { unstoppable: u.hlUnstoppable, unbeatable: u.hlUnbeatable, bomb: u.hlBomb, big: u.hlBig };
      for (const h of hl) {
        el('li', `hl-${h.kind}`, list).textContent = fmt(key[h.kind], { name: this.nameOf(h.seat), combo: describeCombo(h.cards, h.combo) });
      }
    }

    // Stats: per player, then the match as a whole.
    el('h3', 'stats-title', card).textContent = u.stats;
    const table = el('table', 'stats', card);
    const head = el('tr', '', el('thead', '', table));
    for (const h of ['', u.statPlayed, u.statPasses, u.statTwos, u.statBombs, u.statSlow]) el('th', '', head).textContent = h;
    const body = el('tbody', '', table);
    for (const seat of placings) {
      const st = this.stats.seats[seat];
      if (!st) continue;
      const tr = el('tr', seat === this.me ? 'me' : '', body);
      el('th', '', tr).textContent = `${this.seatMeta[seat]!.avatar} ${this.nameOf(seat)}`;
      for (const n of [st.cardsPlayed, st.passes, st.twos, st.bombs, st.tooSlow]) el('td', '', tr).textContent = String(n);
    }
    const facts = el('div', 'stat-facts', card);
    const dur = Math.round(this.stats.durationMs / 1000);
    const fact = (label: string, value: string): void => {
      const f = el('div', 'stat-fact', facts);
      el('span', '', f).textContent = label;
      el('b', '', f).textContent = value;
    };
    fact(u.statDuration, fmt(u.minutes, { m: Math.floor(dur / 60), s: dur % 60 }));
    fact(u.statMoves, String(this.stats.moves));
    const big = this.stats.biggest;
    if (big) fact(u.statBiggest, `${this.nameOf(big.seat)}: ${describeCombo(big.cards, big.kind)}`);
    const mine = this.stats.seats[this.me];
    if (mine?.best) fact(u.statBest, describeCombo(mine.best.cards, mine.best.kind));

    const actions = el('div', 'sheet-actions', card);
    if (this.isHost) {
      if (!matchOver && this.hooks.nextRound) {
        button(actions, 'btn btn-primary', fmt(u.round, { n: v.round + 1 }), '').addEventListener('click', () => this.hooks.nextRound!());
      } else if (this.hooks.playAgain) {
        button(actions, 'btn btn-primary', u.playAgain, u.playAgain).addEventListener('click', () => this.hooks.playAgain!());
      }
      if (this.hooks.changeRules) button(actions, 'btn btn-secondary', u.changeRules, u.changeRules).addEventListener('click', () => this.hooks.changeRules!());
    }
    button(actions, 'btn btn-secondary', u.leave, u.leave).addEventListener('click', () => this.hooks.exit());
  }

  private closeOverlay(): void {
    this.overlay.className = 'overlay hidden';
    this.overlay.innerHTML = '';
  }

  // ---------------------------------------------------------- menu sheet

  private openMenu(): void {
    const o = this.overlay;
    o.innerHTML = '';
    o.className = 'overlay';
    const sheet = el('div', 'sheet', o);
    el('h2', '', sheet).textContent = L().ui.menu;
    const row = (label: string, value: string, onClick: () => void): void => {
      const b = button(sheet, 'menu-row', '', label);
      b.innerHTML = `<span></span><span class="menu-value"></span>`;
      b.firstElementChild!.textContent = label;
      b.lastElementChild!.textContent = value;
      b.addEventListener('click', onClick);
    };
    /** An on/off setting as a switch. */
    const toggle = (label: string, on: boolean, flip: () => void): void => {
      const b = button(sheet, 'menu-row', '', '');
      b.setAttribute('role', 'switch');
      b.setAttribute('aria-checked', String(on));
      b.setAttribute('aria-label', label);
      b.innerHTML = `<span></span><span class="switch${on ? ' on' : ''}"><span class="knob"></span></span>`;
      b.firstElementChild!.textContent = label;
      b.addEventListener('click', () => {
        flip();
        sound.toggle();
        this.applySettings();
        const sw = b.querySelector('.switch')!;
        const now = !sw.classList.contains('on');
        sw.classList.toggle('on', now);
        b.setAttribute('aria-checked', String(now));
      });
    };
    row(L().ui.rules, '›', () => this.openRules());
    if (this.isHost) {
      const g = el('div', 'menu-row menu-seg', sheet);
      el('span', '', g).textContent = L().ui.humour;
      const segs = el('span', 'segmented small', g);
      for (const h of ['off', 'mild', 'spicy'] as Humour[]) {
        const label = { off: L().ui.humourOff, mild: L().ui.humourMild, spicy: L().ui.humourSpicy }[h];
        const b = button(segs, `seg${this.settings.humour === h ? ' on' : ''}`, label, `${L().ui.humour}: ${label}`);
        b.setAttribute('aria-pressed', String(this.settings.humour === h));
        b.addEventListener('click', () => {
          this.settings.humour = h;
          this.hooks.setHumour?.(h);
          sound.click();
          this.applySettings();
          for (const o of segs.querySelectorAll('.seg')) {
            o.classList.toggle('on', o === b);
            o.setAttribute('aria-pressed', String(o === b));
          }
        });
      }
    }
    toggle(L().ui.sound, this.settings.sound, () => (this.settings.sound = !this.settings.sound));
    toggle(L().ui.reducedMotion, this.settings.reducedMotion, () => (this.settings.reducedMotion = !this.settings.reducedMotion));
    toggle(L().ui.fourColour, this.settings.fourColour, () => (this.settings.fourColour = !this.settings.fourColour));
    const actions = el('div', 'sheet-actions', sheet);
    button(actions, 'btn btn-secondary', L().ui.leave, L().ui.leave).addEventListener('click', () => this.hooks.exit());
    button(actions, 'btn btn-primary', L().ui.close, L().ui.close).addEventListener('click', () => this.closeOverlay());
  }

  private openRules(): void {
    const o = this.overlay;
    o.innerHTML = '';
    o.className = 'overlay';
    const sheet = el('div', 'sheet rules-sheet', o);
    el('h2', '', sheet).textContent = L().ui.rules;
    const ul = el('ul', 'rules-list', sheet);
    for (const line of L().rules.bigtwo) el('li', '', ul).textContent = line;
    const actions = el('div', 'sheet-actions', sheet);
    button(actions, 'btn btn-primary', L().ui.close, L().ui.close).addEventListener('click', () => this.closeOverlay());
  }

  // ------------------------------------------------------------ tutorial

  showTip(text: string, onDone: () => void, onSkip: () => void): void {
    const t = this.tipEl;
    t.innerHTML = '';
    t.className = 'tip';
    el('div', 'tip-text', t).textContent = text;
    const a = el('div', 'tip-actions', t);
    button(a, 'btn btn-ghost', L().ui.skipTutorial, L().ui.skipTutorial).addEventListener('click', () => {
      this.hideTip();
      onSkip();
    });
    button(a, 'btn btn-primary', L().ui.gotIt, L().ui.gotIt).addEventListener('click', () => {
      this.hideTip();
      onDone();
    });
    const lay = this.layout;
    t.style.left = `${lay.centre.x}px`;
    t.style.width = `${lay.centre.w}px`;
    t.style.top = `${lay.centre.y + lay.centre.h * 0.55}px`;
  }

  hideTip(): void {
    this.tipEl.className = 'tip hidden';
  }

  get resultsShowing(): boolean {
    return this.resultsOpen;
  }

  // --------------------------------------------------------------- clock

  /** Big countdown over the stage while everyone looks at their new hand. */
  private renderCountdown(): void {
    const left = this.previewUntil - Date.now();
    const c = this.countdown;
    if (left <= -700 || !this.layout) {
      if (this.lastCount !== -1) {
        c.className = 'countdown hidden';
        this.lastCount = -1;
        this.renderButtons();
        if (this.view) this.renderTurn(this.view);
      }
      return;
    }
    const n = Math.ceil(left / 1000);
    if (n === this.lastCount) return;
    this.lastCount = n;
    const st = this.layout.stage;
    c.className = 'countdown';
    c.style.left = `${st.x}px`;
    c.style.top = `${st.y}px`;
    c.style.width = `${st.w}px`;
    c.style.height = `${st.h}px`;
    c.innerHTML = '<div class="countdown-title"></div><div class="countdown-num tick"></div>';
    c.firstElementChild!.textContent = n > 0 ? L().ui.lookAtCards : '';
    c.lastElementChild!.textContent = n > 0 ? String(n) : L().ui.go;
    if (n > 0) sound.tick();
    else sound.chime();
    if (this.view) this.renderTurn(this.view);
    this.renderButtons();
  }

  private tick = (): void => {
    requestAnimationFrame(this.tick);
    if (this.previewUntil > 0) this.renderCountdown();
    const v = this.view;
    if (!v || !this.meta.deadline || v.phase !== 'play') return;
    const total = this.meta.deadline - Date.now();
    const left = Math.max(0, total);
    const turnMs = Number(this.root.dataset.turnMs || 20000);
    const frac = Math.max(0, Math.min(1, left / turnMs));
    const mine = v.turn === this.me;
    this.timerFill.style.transform = `scaleX(${mine ? frac : 0})`;
    this.timerBar.classList.toggle('urgent', mine && left <= 5000);
    // The ring on whoever's turn it is.
    for (const s of this.seatEls) {
      const fg = s.querySelector('.ring-fg') as SVGCircleElement | null;
      if (!fg) continue;
      const isTurn = Number(s.dataset.seat) === v.turn;
      fg.style.strokeDashoffset = String(isTurn ? 100.5 * (1 - frac) : 100.5);
      s.classList.toggle('urgent', isTurn && left <= 5000);
    }
    if (mine) {
      const sec = Math.ceil(left / 1000);
      if (left <= 5000 && sec !== this.lastTickSecond && sec > 0) {
        this.lastTickSecond = sec;
        sound.tick();
      }
      if (left <= 10000 && !this.announced10) {
        this.announced10 = true;
        this.live.textContent = fmt(L().ui.secondsLeft, { n: 10 });
      }
    }
  };

  /** Plain description of what is on the table, for tests and screen readers. */
  describe(): string {
    const v = this.view;
    if (!v) return '';
    return v.lead ? cardsText(v.lead.cards) : '';
  }
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
