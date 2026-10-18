// Lucky 7's Jester: the host picks at most one line per log entry, so every
// phone shows the same line. Only public facts feed it: thrown and
// swapped-out cards (face up on Discard), powers used, locks, whose turn is
// next, the deck count, and which cards a J looked at. Hidden faces never do.
//
// Beyond the big moments it watches for the table's stories: a good card
// thrown away, a 9 thrown right when the next player is locked, a power
// left on Discard for the next player, a good card swapped out by mistake,
// revenge and grudges, the deck's halfway point and last card, close wins.

import { lucky7, type GameEvent } from '@efoc/engine';
import { JesterDirector, type JesterEvent } from '../../feel/jester';
import { L } from '../../strings';

type State = lucky7.LuckyState;
type Target = lucky7.Target;

/** Big moments always speak; the rest wait for the Jester's gap. */
const MAJOR = new Set(['l7_bait_9', 'l7_revenge', 'l7_last_card', 'l7_final_lap', 'l7_win', 'l7_zero', 'l7_close', 'l7_unlock']);
/** When several things happen at once, the best story wins. */
const PRIORITY = [
  'l7_zero',
  'l7_close',
  'l7_win',
  'l7_last_card',
  'l7_final_lap',
  'l7_bait_9',
  'l7_revenge',
  'l7_bait_power',
  'l7_swap_out_good',
  'l7_gift',
  'l7_grudge',
  'l7_unlock',
  'l7_lock',
  'l7_lock_self',
  'l7_shuffle',
  'l7_swap',
  'l7_dump',
  'l7_swap_out_high',
  'l7_halfway',
  'l7_dump_low',
  'l7_peek_other',
  'l7_peek_own',
];

const short = (c: string): string => (c[0] === 'T' ? '10' : c[0]!) + ({ d: '♦', c: '♣', h: '♥', s: '♠' } as Record<string, string>)[c[1]!]!;

export class LuckySevenCommentator {
  readonly director: JesterDirector;
  /** Who last used a power on each seat (for revenge). */
  private lastAttacker = new Map<number, number>();
  /** The last seat targeted by anyone's power (for grudges). */
  private lastVictim: number | null = null;
  private deckAtStart = 0;

  constructor(
    private readonly names: string[],
    rand: () => number,
    now?: () => number,
  ) {
    this.director = new JesterDirector(rand, now);
  }

  comment(events: GameEvent[], state: State): JesterEvent[] {
    const name = (s: number): string => this.names[s] ?? '';
    const n = state.players;
    const candidates: [string, number | null, Record<string, string | number>][] = [];
    // The deck at the deal (the first entry sees it whole).
    if (state.turns === 0) this.deckAtStart = state.deck.length;
    const nextSeat = (seat: number): number => (seat + 1) % n;
    const lockedCount = (seat: number): number => state.locks[seat]!.filter((k) => k !== null).length;

    for (const e of events) {
      const seat = typeof e.seat === 'number' ? e.seat : null;
      switch (e.type) {
        case 'discarded': {
          const card = e.card as string;
          const next = nextSeat(seat!);
          const p = lucky7.powerOf(card);
          if (p === '9' && lockedCount(next) > 0) candidates.push(['l7_bait_9', next, { name: name(seat!), next: name(next) }]);
          else if (p) candidates.push(['l7_bait_power', seat, { name: name(seat!), next: name(next), power: L().l7.powers[p], card: short(card) }]);
          else if (lucky7.cardPoints(card) <= 1) candidates.push(['l7_dump', seat, { name: name(seat!), card: short(card), next: name(next) }]);
          else if (lucky7.cardPoints(card) <= 3) candidates.push(['l7_dump_low', seat, { name: name(seat!), card: short(card) }]);
          break;
        }
        case 'swapped': {
          // The card that came out is public now: a good one swapped away by mistake, or a big one finally gone.
          const out = e.out as string;
          if (lucky7.cardPoints(out) <= 1) candidates.push(['l7_swap_out_good', seat, { name: name(seat!), card: short(out) }]);
          else if (lucky7.cardPoints(out) >= 10) candidates.push(['l7_swap_out_high', seat, { name: name(seat!), card: short(out) }]);
          break;
        }
        case 'gift_grabbed':
          candidates.push(['l7_gift', e.from as number, { name: name(seat!), giver: name(e.from as number), card: short(e.card as string) }]);
          break;
        case 'power': {
          const t = (e.target ?? null) as Target | null;
          const victim = e.power === 'T' || e.power === 'Q' || e.power === 'K' ? (t?.seat ?? null) : null;
          if (victim !== null && victim !== seat) {
            if (this.lastAttacker.get(seat!) === victim) candidates.push(['l7_revenge', seat, { name: name(seat!), victim: name(victim) }]);
            else if (this.lastVictim === victim) candidates.push(['l7_grudge', victim, { victim: name(victim) }]);
            this.lastAttacker.set(victim, seat!);
            this.lastVictim = victim;
          }
          if (e.power === 'Q' && t) candidates.push(['l7_swap', t.seat, { name: name(seat!), victim: name(t.seat) }]);
          break;
        }
        case 'peeked': {
          // Said once the J's choice is made: their own cards, or one of someone else's.
          if (e.own) candidates.push(['l7_peek_own', seat, { name: name(seat!) }]);
          else if (e.target) candidates.push(['l7_peek_other', (e.target as Target).seat, { name: name(seat!), victim: name((e.target as Target).seat) }]);
          break;
        }
        case 'card_locked': {
          const t = e.target as Target;
          if (t.seat === seat) candidates.push(['l7_lock_self', seat, { name: name(seat!) }]);
          else candidates.push(['l7_lock', t.seat, { name: name(seat!), victim: name(t.seat) }]);
          break;
        }
        case 'lock_broken': {
          const t = e.target as Target;
          candidates.push(['l7_unlock', seat, { name: name(seat!), victim: name(t.seat) }]);
          break;
        }
        case 'shuffled':
          candidates.push(['l7_shuffle', e.target as number, { name: name(seat!), victim: name(e.target as number) }]);
          break;
        case 'turn': {
          if (!e.fromDeck) break; // the count didn't move
          const deck = e.deck as number;
          if (deck === 1) candidates.push(['l7_last_card', e.seat as number, { name: name(e.seat as number) }]);
          else if (this.deckAtStart > 8 && deck === Math.floor(this.deckAtStart / 2)) candidates.push(['l7_halfway', null, { left: deck }]);
          break;
        }
        case 'final_lap':
          candidates.push(['l7_final_lap', null, {}]);
          break;
        case 'round_ended': {
          const points = e.points as number[];
          const placings = e.placings as number[];
          const best = points[placings[0]!]!;
          const winners = placings.filter((p) => points[p] === best);
          const runnerUp = placings.find((p) => points[p]! > best);
          const last = placings[placings.length - 1]!;
          const vars = { name: winners.map(name).join(' & '), total: best, last: name(last), worst: points[last]! };
          if (best === 0) candidates.push(['l7_zero', placings[0]!, vars]);
          else if (runnerUp !== undefined && points[runnerUp]! - best === 1) candidates.push(['l7_close', placings[0]!, { ...vars, second: name(runnerUp) }]);
          else candidates.push(['l7_win', placings[0]!, vars]);
          break;
        }
        default:
          break;
      }
    }
    const rank = (k: string): number => (PRIORITY.includes(k) ? PRIORITY.indexOf(k) : 100);
    candidates.sort((a, b) => rank(a[0]) - rank(b[0]));
    for (const [key, target, vars] of candidates) {
      const line = this.director.pick(key, target, vars, MAJOR.has(key));
      if (line) return [line];
    }
    return [];
  }
}

/**
 * How long the table pauses after an entry before the next bot moves: long
 * enough for its card flights to land (docs/table-feel.md "Pacing").
 */
export function dwellMs(events: GameEvent[]): number {
  let ms = 0;
  for (const e of events) {
    let t = 0;
    if (e.type === 'drew') t = 650;
    else if (e.type === 'swapped' || e.type === 'discarded') t = 900;
    else if (e.type === 'power') t = ({ J: 900, Q: 1500, K: 900, '9': e.target ? 1400 : 900, T: 1900 } as Record<string, number>)[e.power as string] ?? 900;
    else if (e.type === 'peeked') t = 1600;
    else if (e.type === 'final_lap') t = 1600;
    else if (e.type === 'round_ended') t = 1500;
    else if (e.type === 'jester') t = 900;
    ms = Math.max(ms, t);
  }
  return ms;
}
