// Table geometry for 2 to 8 players. Pure: viewport in, boxes out.
// Portrait phone (360 × 780) is the primary layout; the hand and action bar
// sit at the bottom, and the play area shrinks before the hand does.
// See spec "Mobile layout for 2 to 8 players" and "Table layout".

export interface Box {
  x: number;
  y: number;
  w: number;
  h: number;
}

export interface Insets {
  top: number;
  right: number;
  bottom: number;
  left: number;
}

export interface CardPlace {
  x: number;
  y: number;
  rot: number;
  z: number;
}

export interface TableLayout {
  vw: number;
  vh: number;
  portrait: boolean;
  /** Table card size: cardW = min(vw / 8.5, vh / 6), height = 1.4 × width. */
  cardW: number;
  cardH: number;
  /** Hand cards are bigger so every card keeps a 44 px touch strip. */
  handW: number;
  handH: number;
  compact: boolean;
  /** Opponent seats, in clockwise order starting from the player after you. */
  seats: Box[];
  centre: Box;
  hand: Box;
  timerBar: Box;
  actionBar: Box;
}

export const MIN_TARGET = 44;
const GUTTER = 8;
const ACTION_H = 60;
const RAISE = 18;

const clamp = (v: number, lo: number, hi: number): number => Math.max(lo, Math.min(hi, v));

export function seatSize(compact: boolean): { w: number; h: number } {
  return compact ? { w: 68, h: 78 } : { w: 84, h: 96 };
}

/** Hand card size for a viewport. */
function handCardSize(vw: number, vh: number, portrait: boolean): { w: number; h: number } {
  const w = portrait ? clamp(Math.min(vw / 6.2, vh / 9), 46, 84) : clamp(Math.min(vw / 12, vh / 7), 46, 84);
  return { w: Math.round(w), h: Math.round(w * 1.4) };
}

/** How the hand fits: one row if every card keeps a 44 px strip, else two rows. */
export function handRows(count: number, width: number, cardW: number): 1 | 2 {
  if (count <= 1) return 1;
  if (count > 13) return 2;
  const step = (width - cardW) / (count - 1);
  return step >= MIN_TARGET + 4 ? 1 : 2;
}

function handHeight(rows: 1 | 2, cardH: number): number {
  return rows === 1 ? cardH + RAISE + 6 : cardH + rowOffset(cardH) + RAISE + 6;
}

const rowOffset = (cardH: number): number => Math.max(MIN_TARGET + 4, Math.round(cardH * 0.6));

/** Slot names for opponent seats, clockwise from the player after you. */
type Slot = 'L' | 'LU' | 'LD' | 'TL' | 'T' | 'TR' | 'R' | 'RU' | 'RD';

const PORTRAIT_SLOTS: Record<number, Slot[]> = {
  1: ['T'],
  2: ['L', 'R'],
  3: ['L', 'T', 'R'],
  4: ['L', 'TL', 'TR', 'R'],
  5: ['L', 'TL', 'T', 'TR', 'R'],
  6: ['LD', 'LU', 'TL', 'TR', 'RU', 'RD'],
  7: ['LD', 'LU', 'TL', 'T', 'TR', 'RU', 'RD'],
};

export function computeLayout(vw: number, vh: number, players: number, insets: Insets = { top: 0, right: 0, bottom: 0, left: 0 }, handCount = 13): TableLayout {
  const portrait = vh >= vw;
  const cardW = Math.round(Math.min(vw / 8.5, vh / 6));
  const cardH = Math.round(cardW * 1.4);
  const { w: handW, h: handH } = handCardSize(vw, vh, portrait);
  const left = insets.left + GUTTER;
  const right = vw - insets.right - GUTTER;
  const innerW = right - left;

  const actionBar: Box = { x: left, y: vh - insets.bottom - ACTION_H - 4, w: innerW, h: ACTION_H };
  const timerBar: Box = { x: left, y: actionBar.y - 8, w: innerW, h: 5 };
  // Reserve room for the worst case (two rows) so the table doesn't jump as the hand shrinks.
  const rows = handRows(Math.max(handCount, 1), innerW, handW);
  const hH = handHeight(portrait ? 2 : rows, handH);
  const hand: Box = { x: left, y: timerBar.y - 4 - hH, w: innerW, h: hH };

  const top = insets.top + GUTTER;
  const playBottom = hand.y - 4;
  const opponents = players - 1;
  const compact = players >= 5 || !portrait;
  const seat = seatSize(compact);

  const seats: Box[] = [];
  let centre: Box;
  if (portrait) {
    const playH = playBottom - top;
    const slots = PORTRAIT_SLOTS[opponents] ?? [];
    const hasSides = slots.some((s) => s[0] === 'L');
    const topRow = slots.filter((s) => s[0] === 'T');
    const sideX = { L: left, R: right - seat.w };
    const rowY = {
      T: top,
      mid: top + Math.max(seat.h + GUTTER, playH * 0.3),
      up: top + Math.max(seat.h + GUTTER, playH * 0.24),
      down: top + Math.max(seat.h * 2 + GUTTER * 2, playH * 0.52),
    };
    const topX = (slot: Slot): number => {
      const n = topRow.length;
      const i = topRow.indexOf(slot);
      const frac = n === 1 ? 0.5 : n === 2 ? [0.3, 0.7][i]! : [0.22, 0.5, 0.78][i]!;
      return clamp(vw * frac - seat.w / 2, left, right - seat.w);
    };
    for (const slot of slots) {
      let x: number;
      let y: number;
      if (slot[0] === 'T') {
        x = topX(slot);
        y = rowY.T;
      } else {
        x = sideX[slot[0] as 'L' | 'R'];
        y = slot.length === 1 ? rowY.mid : slot[1] === 'U' ? rowY.up : rowY.down;
      }
      seats.push({ x: Math.round(x), y: Math.round(y), w: seat.w, h: seat.h });
    }
    const cx0 = hasSides ? left + seat.w + GUTTER : left;
    const cx1 = hasSides ? right - seat.w - GUTTER : right;
    const cy0 = topRow.length > 0 ? top + seat.h + GUTTER : top;
    centre = { x: cx0, y: cy0, w: cx1 - cx0, h: Math.max(0, playBottom - cy0) };
  } else {
    // Landscape and tablet: seats along a shallow arc across the top.
    const n = opponents;
    const span = innerW - seat.w;
    for (let i = 0; i < n; i++) {
      const t = n === 1 ? 0.5 : i / (n - 1);
      const x = left + span * (n === 1 ? 0.5 : 0.04 + t * 0.92);
      const dip = Math.pow(2 * t - 1, 2) * 0.25; // a shallow arc: ends sit a little lower
      const y = top + dip * Math.min(48, (playBottom - top - seat.h) * 0.35);
      seats.push({ x: Math.round(x), y: Math.round(y), w: seat.w, h: seat.h });
    }
    // The centre sits between the two end seats and below the rest.
    const cx0 = n >= 2 ? seats[0]!.x + seat.w + GUTTER : left;
    const cx1 = n >= 2 ? seats[n - 1]!.x - GUTTER : right;
    const inner = n >= 2 ? seats.slice(1, -1) : seats;
    const cy0 = Math.max(top, ...inner.map((b) => b.y + b.h)) + GUTTER;
    centre = { x: cx0, y: cy0, w: cx1 - cx0, h: Math.max(0, playBottom - cy0) };
  }
  return { vw, vh, portrait, cardW, cardH, handW, handH, compact, seats, centre, hand, timerBar, actionBar };
}

/** Where each hand card sits: a shallow fan when it fits, else a flat overlap, else two rows. */
export function handPlaces(count: number, layout: TableLayout): CardPlace[] {
  const { hand, handW: w, handH: h } = layout;
  const rows = handRows(count, hand.w, w);
  const places: CardPlace[] = [];
  const bottomY = hand.y + hand.h - h - 4;
  if (rows === 1) {
    const naturalStep = w * 0.92;
    const step = count <= 1 ? 0 : Math.min(naturalStep, (hand.w - w) / (count - 1));
    const total = w + step * (count - 1);
    const x0 = hand.x + (hand.w - total) / 2;
    const fan = step >= w * 0.8; // fan only when cards barely overlap, so the tilt never eats a touch strip
    for (let i = 0; i < count; i++) {
      const t = count <= 1 ? 0 : (i / (count - 1)) * 2 - 1;
      // The arc lifts the middle rather than dropping the ends, and the ends
      // sit a little higher to leave room for their tilt.
      places.push({
        x: x0 + i * step,
        y: bottomY + (fan ? -10 + t * t * 4 : 0),
        rot: fan ? t * 5 : 0,
        z: i,
      });
    }
    return places;
  }
  const back = Math.ceil(count / 2);
  const front = count - back;
  const rowSpec: [number, number][] = [
    [back, bottomY - rowOffset(h)],
    [front, bottomY],
  ];
  let z = 0;
  for (const [n, y] of rowSpec) {
    const step = n <= 1 ? 0 : Math.min(w * 0.92, (hand.w - w) / (n - 1));
    const total = w + step * (n - 1);
    const x0 = hand.x + (hand.w - total) / 2;
    for (let i = 0; i < n; i++) places.push({ x: x0 + i * step, y, rot: 0, z: z++ });
  }
  return places;
}

export const RAISE_PX = RAISE;

export function overlaps(a: Box, b: Box): boolean {
  return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
}
