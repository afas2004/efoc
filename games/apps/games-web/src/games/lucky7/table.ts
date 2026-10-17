// The Lucky 7 table: opponents' seats with three mini slots each, the centre
// deck, Discard and Used piles, the card in play, your three face-down slots,
// and a step-by-step action bar (draw, then swap / throw away / use). Power
// cards pick their targets on the table or in a seat focus sheet. Your own
// cards stay face down; a J shows them for a few seconds, only to you.
// State renders at once; effects play on top (spec "Moment tiers").

import { lucky7, type Card, type GameEvent, type SeatId } from '@efoc/engine';
import { haptic } from '../../bridge';
import { banner, burst, confetti, dim, shake, type ColourRole } from '../../feel/effects';
import { jesterText, type Humour, type JesterEvent } from '../../feel/jester';
import { EYES, JESTER_SVG, playEmoji, preloadEmoji } from '../../feel/jesterArt';
import { setMuted, sound, unlockAudio } from '../../feel/sound';
import { FeelQueue } from '../../feel/tiers';
import { L, fmt } from '../../strings';
import { cardLabel, makeBack, makeCard } from '../../table/cardFace';
import { computeLayout, TURN_CHIP_H, type Box, type TableLayout } from '../../table/layout';
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
type Mode = 'none' | 'swap' | 'qMine' | 'qTheirs' | 'lock' | 'unlock' | 'shuffle' | 'peek';

const RESULTS_DELAY_MS = 1600;
const PEEK_RESULT_MS = 3500;

export class LuckySevenTable {
  readonly feel = new FeelQueue();
  private layout!: TableLayout;
  private view: View | null = null;
  private meta: UpdateMeta = { deadline: null, afk: [] };
  private mode: Mode = 'none';
  private qMine: number | null = null;
  /** A move sent and not yet confirmed by the host: no double taps. */
  private sent = false;
  /** My own cards, face up, during a J (null where locked). */
  private ownPeek: { cards: (Card | null)[]; until: number } | null = null;
  /** A card I peeked at, shown over its slot for a moment. */
  private peekShown: { target: Target; card: Card; until: number } | null = null;
  private turnTotal = 20000;
  private lastTickSecond = -1;
  private resultsOpen = false;
  private focusSeat: SeatId | null = null;
  private conn: Conn[] = [];
  private rematch: RematchInfo | null = null;
  private rematchEl: HTMLElement | null = null;

  // DOM
  private table: HTMLElement;
  private seatEls: HTMLElement[] = [];
  private centre: HTMLElement;
  private deckEl: HTMLElement;
  private discardEl: HTMLElement;
  private usedEl: HTMLElement;
  private drawnEl: HTMLElement;
  private mineEl: HTMLElement;
  private slotEls: HTMLElement[] = [];
  private turnChip: HTMLElement;
  private timerBar: HTMLElement;
  private timerFill: HTMLElement;
  private actionBar: HTMLElement;
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
    this.table = el('div', 'table', root);
    this.centre = el('div', 'l7-centre', this.table);
    const piles = el('div', 'l7-piles', this.centre);
    this.deckEl = el('div', 'l7-pile l7-deck', piles);
    this.discardEl = el('div', 'l7-pile l7-discard', piles);
    this.usedEl = el('div', 'l7-pile l7-used', piles);
    this.drawnEl = el('div', 'l7-drawn hidden', this.centre);
    this.mineEl = el('div', 'l7-mine', this.table);
    for (let i = 0; i < lucky7.SLOTS; i++) {
      const s = el('button', 'l7-slot', this.mineEl) as HTMLButtonElement;
      s.type = 'button';
      s.dataset.slot = String(i);
      s.addEventListener('click', () => this.tapMine(i));
      this.slotEls.push(s);
    }
    this.turnChip = el('div', 'turn-chip l7-prompt hidden', this.table);
    this.turnChip.setAttribute('aria-live', 'polite');
    this.timerBar = el('div', 'timer-bar', this.table);
    this.timerFill = el('div', 'timer-fill', this.timerBar);
    this.actionBar = el('div', 'action-bar l7-actions', this.table);
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
    this.view = view;
    this.meta = meta;
    this.sent = false;
    if (meta.deadline && meta.deadline !== prevDeadline) this.turnTotal = Math.max(1000, meta.deadline - Date.now());
    // The host started another match: close the results.
    if (view.phase === 'play' && this.resultsOpen) {
      this.resultsOpen = false;
      this.overlay.className = 'overlay hidden';
      this.ownPeek = null;
      this.peekShown = null;
    }
    if (view.turn !== this.me || view.phase !== 'play') this.resetMode();
    else if (view.step === 'peek' && this.mode !== 'peek') this.mode = this.ownPeek ? 'none' : 'peek';
    else if (view.step !== 'act' && this.mode !== 'peek') this.resetMode();
    for (const e of events) {
      if (e.to !== undefined && e.to !== this.me) continue;
      this.moment(e, view);
    }
    this.render();
    if (view.phase === 'over' && !this.resultsOpen) {
      this.resultsOpen = true;
      window.setTimeout(() => this.results(view), RESULTS_DELAY_MS);
    }
  }

  /** "Who's in for another?" on the results screen (online tables). */
  setRematch(info: RematchInfo | null): void {
    this.rematch = info;
    if (this.rematchEl?.isConnected) renderRematch(this.rematchEl, info);
  }

  /** Who is connected (online tables only); redraws the seats when it changes. */
  setConnection(conn: Conn[]): void {
    this.conn = conn.slice();
    if (this.view) this.renderSeats(this.view);
  }

  /** A short note over the table, e.g. "Mei is now the host". */
  notice(text: string): void {
    const c = this.layout?.stage;
    if (!c) return;
    this.feel.play(2, 'notice', (ctx) => banner(this.fx, text, 'info', 'pop', ctx, { x: c.x + c.w / 2, y: c.y + 8 }));
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

  // ------------------------------------------------------------- layout

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
    if (!b) return this.mineCentre();
    return { x: b.x + b.w / 2, y: b.y + b.h / 2 };
  }

  private mineCentre(): { x: number; y: number } {
    const h = this.layout.hand;
    return { x: h.x + h.w / 2, y: h.y + h.h / 2 };
  }

  private nameOf(seat: SeatId): string {
    return seat === this.me ? L().ui.you : this.seatMeta[seat]?.name ?? '';
  }

  render(): void {
    const v = this.view;
    if (!v) return;
    const vw = this.root.clientWidth || window.innerWidth;
    const vh = this.root.clientHeight || window.innerHeight;
    this.layout = computeLayout(vw, vh, v.players, readInsets(), 3);
    const lay = this.layout;
    this.root.style.setProperty('--card-w', `${lay.handW}px`);
    this.root.style.setProperty('--card-h', `${lay.handH}px`);
    this.root.style.setProperty('--pile-w', `${Math.round(lay.cardW * 1.05)}px`);
    this.root.classList.toggle('final-lap', v.phase === 'play' && v.deckCount <= v.players);
    this.renderSeats(v);
    this.renderCentre(v);
    this.renderMine(v);
    this.renderPrompt(v);
    this.renderActions(v);
    place(this.timerBar, lay.timerBar);
    place(this.actionBar, lay.actionBar);
    if (this.focusSeat !== null) this.renderFocus();
  }

  private renderSeats(v: View): void {
    const lay = this.layout;
    while (this.seatEls.length < v.players - 1) {
      const s = el('button', 'seat l7-seat', this.table) as HTMLButtonElement;
      s.type = 'button';
      s.innerHTML =
        '<div class="avatar"><svg class="ring" viewBox="0 0 36 36"><circle class="ring-bg" cx="18" cy="18" r="16"/><circle class="ring-fg" cx="18" cy="18" r="16"/></svg><span class="face"></span><span class="dot"></span></div>' +
        '<div class="name"></div><div class="l7-mini"></div><div class="chip hidden"></div><div class="stamp"></div>';
      s.addEventListener('click', () => this.tapSeat(Number(s.dataset.seat)));
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
      const mini = s.querySelector('.l7-mini') as HTMLElement;
      if (mini.childElementCount !== lucky7.SLOTS) {
        mini.innerHTML = '';
        for (let i = 0; i < lucky7.SLOTS; i++) mini.appendChild(el('span', 'l7-mini-card', mini));
      }
      [...mini.children].forEach((c, i) => {
        const locked = v.locked[seat]![i]!;
        c.className = `l7-mini-card${locked ? ' locked' : ''}`;
        const peeked = this.peekShown && this.peekShown.target.seat === seat && this.peekShown.target.slot === i && Date.now() < this.peekShown.until;
        const revealed = v.revealed?.[seat]?.[i];
        const face = peeked ? this.peekShown!.card : revealed ?? null;
        c.innerHTML = face ? `<b>${face[0] === 'T' ? '10' : face[0]}</b>` : locked ? '🔒' : '';
        c.classList.toggle('face', !!face);
        c.classList.toggle('red', !!face && (face[1] === 'h' || face[1] === 'd'));
      });
      const isTurn = v.phase === 'play' && v.turn === seat;
      s.classList.toggle('turn', isTurn);
      const afk = this.meta.afk[seat] === true;
      const conn = this.conn[seat];
      s.classList.toggle('bot', meta.bot || afk || conn === 'left');
      s.classList.toggle('conn-away', conn === 'away');
      s.classList.toggle('conn-left', conn === 'left');
      s.classList.toggle('pickable', this.seatPickable(seat));
      const chip = s.querySelector('.chip') as HTMLElement;
      if (conn === 'left' && !v.totals) {
        chip.textContent = L().ui.leftGame;
        chip.className = 'chip chip-danger';
      } else if (conn === 'away' && !v.totals) {
        chip.textContent = L().ui.reconnecting;
        chip.className = 'chip chip-warn';
      } else if (afk) {
        chip.textContent = L().ui.afk;
        chip.className = 'chip chip-danger';
      } else if (v.totals) {
        chip.textContent = fmt(L().l7.total, { n: v.totals[seat]! });
        chip.className = 'chip chip-gold';
      } else chip.className = 'chip hidden';
      s.setAttribute('aria-label', `${meta.name}${isTurn ? ', ' + L().ui.yourTurn.toLowerCase() : ''}`);
    }
    for (let r = v.players - 1; r < this.seatEls.length; r++) this.seatEls[r]!.remove();
    this.seatEls.length = v.players - 1;
  }

  private renderCentre(v: View): void {
    const u = L().l7;
    place(this.centre, this.layout.stage);
    // Centre deck: a back with the count.
    this.deckEl.innerHTML = '';
    if (v.deckCount > 0) this.deckEl.appendChild(makeBack());
    el('span', 'l7-pile-label', this.deckEl).textContent = `${u.deck} · ${v.deckCount}`;
    this.deckEl.classList.toggle('pickable', this.myTurn && v.step === 'draw' && v.deckCount > 0);
    // Discard: the top card, face up.
    this.discardEl.innerHTML = '';
    const top = v.discard[v.discard.length - 1];
    if (top) this.discardEl.appendChild(makeCard(top));
    else el('span', 'l7-empty', this.discardEl);
    el('span', 'l7-pile-label', this.discardEl).textContent = u.discardPile;
    this.discardEl.classList.toggle('pickable', this.myTurn && v.step === 'draw' && !!top);
    this.discardEl.onclick = () => this.myTurn && v.step === 'draw' && top && this.send({ type: 'draw', from: 'discard' });
    this.deckEl.onclick = () => this.myTurn && v.step === 'draw' && v.deckCount > 0 && this.send({ type: 'draw', from: 'deck' });
    // Used: the last power used, dimmed, with the count.
    this.usedEl.innerHTML = '';
    const used = v.used[v.used.length - 1];
    if (used) this.usedEl.appendChild(makeCard(used));
    else el('span', 'l7-empty', this.usedEl);
    el('span', 'l7-pile-label', this.usedEl).textContent = `${u.usedPile} · ${v.used.length}`;
    // The card in play this turn.
    const showDrawn = v.phase === 'play' && v.step === 'act';
    this.drawnEl.classList.toggle('hidden', !showDrawn);
    if (showDrawn) {
      this.drawnEl.innerHTML = '';
      const label = el('div', 'l7-drawn-label', this.drawnEl);
      label.textContent = v.turn === this.me ? u.youDrew : fmt(u.theyDrew, { name: this.nameOf(v.turn) });
      const card = v.drawn ? makeCard(v.drawn) : makeBack();
      card.classList.add('l7-drawn-card');
      this.drawnEl.appendChild(card);
      const p = lucky7.powerOf(v.drawn);
      if (p) el('div', 'l7-power-tag', this.drawnEl).textContent = `⚡ ${u.powers[p]}`;
    }
  }

  private renderMine(v: View): void {
    place(this.mineEl, this.layout.hand);
    const now = Date.now();
    const own = this.ownPeek && now < this.ownPeek.until ? this.ownPeek : null;
    this.slotEls.forEach((s, i) => {
      s.innerHTML = '';
      const locked = v.locked[this.me]![i]!;
      const revealed = v.revealed?.[this.me]?.[i];
      const peekCard = own?.cards[i];
      const shown = revealed ?? peekCard ?? null;
      const card = shown ? makeCard(shown) : makeBack();
      card.classList.add('l7-slot-card');
      s.appendChild(card);
      if (locked) el('span', 'l7-lock', s).textContent = '🔒';
      el('span', 'l7-slot-no', s).textContent = String(i + 1);
      s.classList.toggle('locked', locked);
      s.classList.toggle('pickable', this.minePickable(i));
      s.classList.toggle('selected', this.mode === 'qTheirs' && this.qMine === i);
      s.setAttribute('aria-label', `${L().l7.yourCards} ${i + 1}${locked ? ', ' + L().l7.locked : ''}${shown ? ', ' + cardLabel(shown) : ''}`);
    });
    if (own) {
      const left = Math.ceil((own.until - now) / 1000);
      this.mineEl.dataset.peek = fmt(`${L().l7.ownPeek} · {n}s`, { n: left });
    } else delete this.mineEl.dataset.peek;
  }

  private renderPrompt(v: View): void {
    const u = L().l7;
    const chip = this.turnChip;
    const lay = this.layout;
    chip.style.left = `${lay.hand.x}px`;
    chip.style.width = `${lay.hand.w}px`;
    chip.style.top = 'auto';
    chip.style.bottom = `${lay.vh - lay.hand.y + 6}px`;
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
        swap: u.swapPrompt,
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
    if (v.step === 'draw') {
      const top = v.discard[v.discard.length - 1];
      const take = button(bar, 'btn btn-secondary', top ? fmt(u.takeDiscard, { card: shortCard(top) }) : u.discardPile, u.takeDiscard);
      take.disabled = !top;
      take.addEventListener('click', () => this.send({ type: 'draw', from: 'discard' }));
      button(bar, 'btn btn-primary', u.drawDeck, u.drawDeck).addEventListener('click', () => this.send({ type: 'draw', from: 'deck' }));
      return;
    }
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
    // step 'act'
    if (this.mode !== 'none') {
      button(bar, 'btn btn-secondary', u.cancel, u.cancel).addEventListener('click', () => {
        this.resetMode();
        this.render();
      });
      if (this.mode === 'unlock') button(bar, 'btn btn-primary', u.skip, u.skip).addEventListener('click', () => this.send({ type: 'use', target: null }));
      return;
    }
    const power = lucky7.powerOf(v.drawn);
    const canSwap = v.locked[this.me]!.some((l) => !l);
    const swap = button(bar, 'btn btn-secondary', u.swap, u.swap);
    swap.disabled = !canSwap;
    swap.addEventListener('click', () => {
      this.mode = 'swap';
      this.render();
    });
    button(bar, 'btn btn-secondary', u.discard, u.discard).addEventListener('click', () => this.send({ type: 'discard' }));
    if (power && this.canUse(v, power)) {
      const use = button(bar, 'btn btn-primary btn-power', u.use, `${u.use} ${u.powers[power]}`);
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

  private minePickable(slot: number): boolean {
    const v = this.view;
    if (!v || !this.myTurn) return false;
    const locked = v.locked[this.me]![slot]!;
    if (this.mode === 'swap' || this.mode === 'qMine' || this.mode === 'lock') return !locked;
    if (this.mode === 'unlock') return locked;
    return this.mode === 'shuffle';
  }

  private seatPickable(seat: SeatId): boolean {
    const v = this.view;
    if (!v || !this.myTurn) return false;
    const open = v.locked[seat]!.some((l) => !l);
    if (this.mode === 'qTheirs' || this.mode === 'lock' || this.mode === 'peek') return open;
    if (this.mode === 'unlock') return v.locked[seat]!.some((l) => l);
    return this.mode === 'shuffle';
  }

  private tapMine(slot: number): void {
    if (!this.minePickable(slot)) return;
    switch (this.mode) {
      case 'swap':
        return this.send({ type: 'swap', slot });
      case 'qMine':
        this.qMine = slot;
        this.mode = 'qTheirs';
        sound.click();
        return this.render();
      case 'lock':
        return this.send({ type: 'use', target: { seat: this.me, slot } });
      case 'unlock':
        return this.send({ type: 'use', target: { seat: this.me, slot } });
      case 'shuffle':
        return this.send({ type: 'use', seat: this.me });
      default:
    }
  }

  private tapSeat(seat: SeatId): void {
    if (!this.seatPickable(seat)) return;
    if (this.mode === 'shuffle') return this.send({ type: 'use', seat });
    sound.click();
    this.focusSeat = seat;
    this.renderFocus();
  }

  /** A seat's three slots, big, to pick one of them. */
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
    el('p', 'l7-focus-hint', sheet).textContent = this.renderPromptText();
    const row = el('div', 'l7-focus-slots', sheet);
    for (let i = 0; i < lucky7.SLOTS; i++) {
      const locked = v.locked[seat]![i]!;
      const ok = this.mode === 'unlock' ? locked : !locked;
      const b = el('button', `l7-slot big${locked ? ' locked' : ''}${ok ? ' pickable' : ''}`, row) as HTMLButtonElement;
      b.type = 'button';
      b.disabled = !ok;
      const c = makeBack();
      c.classList.add('l7-slot-card');
      b.appendChild(c);
      if (locked) el('span', 'l7-lock', b).textContent = '🔒';
      el('span', 'l7-slot-no', b).textContent = String(i + 1);
      b.setAttribute('aria-label', `${meta.name} ${i + 1}${locked ? ', ' + L().l7.locked : ''}`);
      b.addEventListener('click', () => this.pickTheirs({ seat, slot: i }));
    }
    const actions = el('div', 'sheet-actions', sheet);
    button(actions, 'btn btn-secondary', L().l7.cancel, L().l7.cancel).addEventListener('click', () => {
      this.closeFocus();
      this.render();
    });
    f.addEventListener('click', (e) => {
      if (e.target === f) {
        this.closeFocus();
        this.render();
      }
    });
  }

  private renderPromptText(): string {
    return this.turnChip.textContent ?? '';
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
      case 'drew':
        this.feel.play(1, 'drew', () => sound.slide());
        break;
      case 'swapped':
        this.stamp(seat!, u.stamps.swap, 'turn');
        this.feel.play(1, 'swapped', () => sound.thud(0));
        break;
      case 'discarded':
        this.stamp(seat!, u.stamps.discard, 'neutral');
        this.feel.play(1, 'discarded', () => sound.thud(1));
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
          this.feel.play(2, 'q_swap', (ctx) => {
            const a = this.seatCentre(seat!);
            const b = this.seatCentre(t.seat);
            burst(this.fx, a.x, a.y, 10, 'power', ctx, 60);
            burst(this.fx, b.x, b.y, 10, 'power', ctx, 60);
            sound.slide();
          });
        } else if (p === 'J') {
          this.stamp(seat!, u.stamps.peek, 'info');
        }
        break;
      }
      case 'card_locked': {
        const t = e.target as Target;
        this.stamp(t.seat, u.stamps.lock, 'danger');
        this.feel.play(2, 'lock', (ctx) => {
          const at = this.slotCentre(t);
          banner(this.fx, '🔒', 'danger', 'pop', ctx, at);
          shake(this.table, 'small', ctx);
          sound.bass();
          haptic(t.seat === this.me ? 'strong' : 'medium');
        });
        break;
      }
      case 'lock_broken': {
        const t = e.target as Target;
        this.stamp(t.seat, u.stamps.unlock, 'good');
        this.feel.play(2, 'unlock', (ctx) => {
          const at = this.slotCentre(t);
          banner(this.fx, '💥🔓', 'good', 'pop', ctx, at);
          burst(this.fx, at.x, at.y, 18, 'good', ctx, 90);
          sound.chime();
          haptic('medium');
        });
        break;
      }
      case 'shuffled': {
        const target = e.target as SeatId;
        this.stamp(target, u.stamps.shuffle, 'power');
        this.feel.play(2, 'shuffle', (ctx) => {
          const at = this.seatCentre(target);
          if (target === this.me) {
            this.mineEl.classList.remove('spin');
            void this.mineEl.offsetWidth;
            this.mineEl.classList.add('spin');
            banner(this.fx, u.shuffledYou, 'power', 'pop', ctx, at);
          } else burst(this.fx, at.x, at.y, 12, 'power', ctx, 70);
          sound.slide();
          haptic(target === this.me ? 'strong' : 'light');
        });
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
          banner(this.fx, `👀 ${shortCard(e.card as Card)} · ${L().l7.peekResult}`, 'info', 'pop', ctx, this.slotCentre(t));
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

  private slotCentre(t: Target): { x: number; y: number } {
    if (t.seat === this.me) return this.pileCentre(this.slotEls[t.slot]!);
    return this.seatCentre(t.seat);
  }

  /** A big word over a seat (or my slots): SWAP, LOCKED!, SHUFFLED! */
  private stamp(seat: SeatId, text: string, role: ColourRole | 'pass'): void {
    const target = seat === this.me ? null : this.seatEls[this.relSeat(seat) - 1];
    const s = target?.querySelector('.stamp') as HTMLElement | null;
    if (s) {
      s.textContent = text;
      s.className = `stamp stamp-${role}`;
      void s.offsetWidth;
      s.classList.add('show');
      return;
    }
    this.feel.play(1, 'stamp', (ctx) => banner(this.fx, text, role === 'pass' ? 'neutral' : role, 'pop', ctx, this.mineCentre()));
  }

  private showJester(e: JesterEvent): void {
    const text = jesterText(e);
    if (!text) return;
    const j = this.jesterEl;
    const lay = this.layout ?? computeLayout(window.innerWidth, window.innerHeight, this.seatMeta.length, readInsets(), 3);
    this.stopEmoji?.();
    this.stopEmoji = e.emoji ? playEmoji(this.jesterEmoji, e.emoji) : null;
    j.className = `jester mood-${e.mood} eyes-${EYES[e.mood]}`;
    this.jesterBubble.textContent = text;
    const w = Math.min(lay.vw - 24, 520);
    j.style.width = `${w}px`;
    j.style.left = `${(lay.vw - w) / 2}px`;
    j.style.top = `${lay.portrait ? Math.max(lay.centre.y, lay.hand.y - TURN_CHIP_H - 116 - 10) : Math.max(4, lay.centre.y - 20)}px`;
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
    // Seats flip one by one, the lowest total last (spec "Final reveal").
    placings.forEach((seat, k) => {
      const li = el('li', `standing${winners.includes(seat) ? ' winner' : ''}`, list);
      li.style.animationDelay = `${(placings.length - 1 - k) * 380}ms`;
      el('span', 'medal', li).textContent = winners.includes(seat) ? '👑' : String(placings.indexOf(seat) + 1);
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
        confetti(this.fx, this.layout.vw, ctx);
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
    if (this.ownPeek) {
      const left = Math.ceil((this.ownPeek.until - Date.now()) / 1000);
      if (this.mineEl.dataset.peekLeft !== String(left)) {
        this.mineEl.dataset.peekLeft = String(left);
        this.renderMine(v!);
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
    }
  };
}

// ---------------------------------------------------------------- helpers

function shortCard(c: Card): string {
  const r = c[0] === 'T' ? '10' : c[0]!;
  return r + ({ d: '♦', c: '♣', h: '♥', s: '♠' } as Record<string, string>)[c[1]!]!;
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
