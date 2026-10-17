// Lucky 7's Jester: the host picks at most one line per log entry from the
// public events, so every phone shows the same line. Peeks and drawn cards
// are private and never reach here.

import { lucky7, type GameEvent } from '@efoc/engine';
import { JesterDirector, type JesterEvent } from '../../feel/jester';

type State = lucky7.LuckyState;

/** Big moments always speak; the rest wait for the Jester's gap. */
const MAJOR = new Set(['l7_gift', 'l7_lock', 'l7_lock_self', 'l7_unlock', 'l7_shuffle', 'l7_final_lap', 'l7_win', 'l7_zero']);
const PRIORITY = ['l7_zero', 'l7_win', 'l7_final_lap', 'l7_gift', 'l7_unlock', 'l7_lock', 'l7_lock_self', 'l7_shuffle', 'l7_swap', 'l7_peek', 'l7_dump'];

export class LuckySevenCommentator {
  readonly director: JesterDirector;

  constructor(
    private readonly names: string[],
    rand: () => number,
    now?: () => number,
  ) {
    this.director = new JesterDirector(rand, now);
  }

  comment(events: GameEvent[], _state: State): JesterEvent[] {
    const name = (s: number): string => this.names[s] ?? '';
    const candidates: [string, number | null, Record<string, string | number>][] = [];
    for (const e of events) {
      const seat = typeof e.seat === 'number' ? e.seat : null;
      switch (e.type) {
        case 'gift_grabbed':
          candidates.push(['l7_gift', e.from as number, { name: name(seat!), giver: name(e.from as number) }]);
          break;
        case 'card_locked': {
          const t = e.target as lucky7.Target;
          if (t.seat === seat) candidates.push(['l7_lock_self', seat, { name: name(seat!) }]);
          else candidates.push(['l7_lock', t.seat, { name: name(seat!), victim: name(t.seat) }]);
          break;
        }
        case 'lock_broken':
          candidates.push(['l7_unlock', seat, { name: name(seat!) }]);
          break;
        case 'shuffled':
          candidates.push(['l7_shuffle', e.target as number, { name: name(seat!), victim: name(e.target as number) }]);
          break;
        case 'power':
          if (e.power === 'Q') candidates.push(['l7_swap', (e.target as lucky7.Target).seat, { name: name(seat!), victim: name((e.target as lucky7.Target).seat) }]);
          if (e.power === 'J') candidates.push(['l7_peek', seat, { name: name(seat!) }]);
          break;
        case 'discarded':
          if (lucky7.cardPoints(e.card as string) <= 1) candidates.push(['l7_dump', seat, { name: name(seat!) }]);
          break;
        case 'final_lap':
          candidates.push(['l7_final_lap', null, {}]);
          break;
        case 'round_ended': {
          const points = e.points as number[];
          const placings = e.placings as number[];
          const best = points[placings[0]!]!;
          const winners = placings.filter((p) => points[p] === best);
          candidates.push([best === 0 ? 'l7_zero' : 'l7_win', placings[0]!, { name: winners.map(name).join(' & '), total: best }]);
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

/** How long the table pauses after an entry before the next bot moves. */
export function dwellMs(events: GameEvent[]): number {
  let ms = 0;
  for (const e of events) {
    if (e.type === 'round_ended') ms = Math.max(ms, 1500);
    else if (e.type === 'final_lap') ms = Math.max(ms, 1600);
    else if (e.type === 'card_locked' || e.type === 'lock_broken' || e.type === 'shuffled' || e.type === 'gift_grabbed') ms = Math.max(ms, 1300);
    else if (e.type === 'power' || e.type === 'swapped' || e.type === 'discarded') ms = Math.max(ms, 700);
    else if (e.type === 'jester') ms = Math.max(ms, 900);
    else if (e.type === 'drew') ms = Math.max(ms, 400);
  }
  return ms;
}
