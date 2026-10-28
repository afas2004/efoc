// Zombie's Jester: the host picks at most one line per log entry, so every
// phone shows the same line. Only public facts feed it: pairs thrown face
// up, who got safe, how many cards everyone holds, and the
// loser at the end. Where the Zombie is stays secret: the Jester never
// says who drew it (the host knows; it would give the game away).

import { zombie, type GameEvent } from '@efoc/engine';
import { JesterDirector, type JesterEvent } from '../../feel/jester';
import { rankText } from '../../table/cardFace';
import { animScale } from './table';

type State = zombie.ZombieState;

/** Big moments always speak; the rest wait for the Jester's gap. */
const MAJOR = new Set(['zb_start', 'zb_safe', 'zb_two_left', 'zb_lose']);
/** When several things happen at once, the best story wins. */
const PRIORITY = ['zb_lose', 'zb_two_left', 'zb_safe', 'zb_start', 'zb_one_card', 'zb_pair'];

export class ZombieCommentator {
  readonly director: JesterDirector;
  private saidTwoLeft = false;

  constructor(
    private readonly names: string[],
    rand: () => number,
    now?: () => number,
  ) {
    this.director = new JesterDirector(rand, now);
  }

  comment(events: GameEvent[], state: State): JesterEvent[] {
    const name = (s: number): string => this.names[s] ?? '';
    const candidates: [string, number | null, Record<string, string | number>][] = [];
    const left = state.hands.map((h, i) => (h.length > 0 ? i : -1)).filter((i) => i >= 0);
    for (const e of events) {
      const seat = typeof e.seat === 'number' ? e.seat : null;
      switch (e.type) {
        case 'round_started':
          this.saidTwoLeft = false;
          candidates.push(['zb_start', null, { pairs: state.pile.length / 2 }]);
          break;
        case 'pair':
          candidates.push(['zb_pair', seat, { name: name(seat!), rank: rankText((e.cards as string[])[0]!) }]);
          break;
        case 'safe':
          candidates.push(['zb_safe', seat, { name: name(seat!), place: e.place as number }]);
          break;
        case 'turn':
          if (left.length === 2 && !this.saidTwoLeft) {
            this.saidTwoLeft = true;
            candidates.push(['zb_two_left', null, { a: name(left[0]!), b: name(left[1]!) }]);
          } else {
            const one = left.find((i) => state.hands[i]!.length === 1);
            if (one !== undefined && left.length > 2) candidates.push(['zb_one_card', one, { name: name(one) }]);
          }
          break;
        case 'round_ended': {
          const loser = state.loser!;
          candidates.push(['zb_lose', loser, { name: name(loser), moves: state.stats?.moves ?? 0 }]);
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
 * enough for the wobble, the flight and a pair's drop to play.
 */
export function dwellMs(events: GameEvent[]): number {
  let ms = 0;
  for (const e of events) {
    let t = 0;
    // Matches the table's steps (table.ts): slow on purpose, so everyone can follow.
    if (e.type === 'round_started') t = 4200;
    else if (e.type === 'turn') t = 3900; // shrink, expand, shuffle
    else if (e.type === 'drew') t = 3300; // lift, wobble, fly, turn over
    // A pair thrown during the deal (no turn follows it) flies alongside everyone else's.
    else if (e.type === 'pair') t = events.some((x) => x.type === 'turn' || x.type === 'zombie_loser') ? 1500 : 500;
    else if (e.type === 'safe') t = 600;
    else if (e.type === 'zombie_loser') t = 3400;
    else if (e.type === 'jester') t = 900;
    ms += t;
  }
  return ms * animScale();
}
