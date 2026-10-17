// Host-side commentary for Big Two: turns engine events into Jester lines
// everyone sees, and says how long the table should breathe after each
// action so players can take it in.

import { bigtwo, type Card, type GameEvent } from '@efoc/engine';
import { JesterDirector, type JesterEvent } from '../../feel/jester';
import { L, fmt } from '../../strings';
import { rankText, suitSymbol } from '../../table/cardFace';

type State = bigtwo.BigTwoState;

/** "a pair of 5s", "a straight up to 9", "a single 2♠". */
export function describeCombo(cards: readonly Card[], kind: string): string {
  const d = L().ui.describe as Record<string, string>;
  const byRank = new Map<string, number>();
  for (const c of cards) byRank.set(c[0]!, (byRank.get(c[0]!) ?? 0) + 1);
  const ranked = [...byRank.entries()].sort((a, b) => b[1] - a[1] || bigtwo.RANK_ORDER[b[0] as never] - bigtwo.RANK_ORDER[a[0] as never]);
  const top = bigtwo.sortCards(cards)[cards.length - 1]!;
  const name = (r: string): string => rankText(`${r}d`);
  const suitName = (L().ui.suitNames as Record<string, string>)[top[1]!] ?? '';
  const straightTop = kind === 'straight' || kind === 'straightflush' ? straightTopRank(cards) : top[0]!;
  return fmt(d[kind] ?? '{card}', {
    card: rankText(top) + suitSymbol(top),
    rank: kind.includes('straight') ? name(straightTop) : name(ranked[0]![0]),
    rank2: name(ranked[1]?.[0] ?? ranked[0]![0]),
    suit: suitName.replace(/s$/, ''),
  });
}

function straightTopRank(cards: readonly Card[]): string {
  const idx = cards.map(bigtwo.rankIndex).sort((a, b) => a - b);
  // A-2-3-4-5 and 2-3-4-5-6 (when allowed) top out at the 5 and 6.
  const key = idx.join(',');
  if (key === '0,1,2,11,12') return '5';
  if (key === '0,1,2,3,12') return '6';
  return cards.find((c) => bigtwo.rankIndex(c) === idx[4])![0]!;
}

const MAJOR = new Set(['out_on_two', 'unstoppable', 'unbeatable', 'bomb', 'one_card', 'player_out', 'win', 'double_it', 'round_start']);
/** When several big things happen at once, the rarest wins the line. */
const PRIORITY = ['out_on_two', 'unstoppable', 'unbeatable', 'bomb', 'win', 'double_it', 'player_out', 'one_card', 'round_start'];

export class BigTwoCommentator {
  readonly director: JesterDirector;
  private passStreak: number[] = [];
  /** The last play made, kept across log entries for the all-passed line. */
  private lastPlay: { seat: number; cards: Card[]; kind: string } | null = null;

  constructor(
    private readonly names: string[],
    rand: () => number,
    now?: () => number,
  ) {
    this.director = new JesterDirector(rand, now);
  }

  /** Jester events to append to this log entry (at most one). */
  comment(events: GameEvent[], state: State): JesterEvent[] {
    if (this.passStreak.length !== state.players) this.passStreak = new Array<number>(state.players).fill(0);
    const name = (s: number): string => this.names[s] ?? '';
    const candidates: [string, number | null, Record<string, string | number>][] = [];
    for (const e of events) {
      const seat = typeof e.seat === 'number' ? e.seat : null;
      switch (e.type) {
        case 'round_started': {
          this.passStreak.fill(0);
          const opener = state.turn;
          candidates.push(['round_start', null, { name: name(opener), card: state.mustInclude ? rankText(state.mustInclude) + suitSymbol(state.mustInclude) : '' }]);
          break;
        }
        case 'card_played': {
          const cards = e.cards as Card[];
          this.lastPlay = { seat: seat!, cards, kind: e.kind as string };
          this.passStreak[seat!] = 0;
          const combo = describeCombo(cards, e.kind as string);
          const left = e.left as number;
          if (left === 1) candidates.push(['one_card', seat, { name: name(seat!), combo }]);
          else if (cards.some((c) => bigtwo.rankIndex(c) === 12) && cards[0] !== '2s' && left >= 5) candidates.push(['two_early', seat, { name: name(seat!), combo, n: left }]);
          else if (cards.length === 5 && !bigtwo.isBomb(e.kind as bigtwo.ComboKind)) candidates.push(['big_play', seat, { name: name(seat!), combo }]);
          break;
        }
        case 'unbeatable': {
          const combo = describeCombo(e.cards as Card[], e.kind as string);
          // With one card left and the lead, the win is certain.
          candidates.push([(e.left as number) === 1 ? 'unstoppable' : 'unbeatable', seat, { name: name(seat!), combo }]);
          break;
        }
        case 'bomb':
          if (this.lastPlay) candidates.push(['bomb', seat, { name: name(seat!), combo: describeCombo(this.lastPlay.cards, this.lastPlay.kind) }]);
          break;
        case 'passed': {
          const n = (this.passStreak[seat!] ?? 0) + 1;
          this.passStreak[seat!] = n;
          if (n >= 3) candidates.push(['pass_streak', seat, { name: name(seat!), n }]);
          break;
        }
        case 'all_passed': {
          const lead = this.lastPlay;
          candidates.push(['all_passed', seat, { name: name(seat!), combo: lead ? describeCombo(lead.cards, lead.kind) : '' }]);
          break;
        }
        case 'player_out':
          if (e.onTwo) candidates.push(['out_on_two', seat, { name: name(seat!) }]);
          else if (state.phase === 'play') candidates.push(['player_out', seat, { name: name(seat!), place: e.place as number }]);
          break;
        case 'too_slow':
          candidates.push(['too_slow', seat, { name: name(seat!) }]);
          break;
        case 'double_it':
          candidates.push(['double_it', seat, { name: name(seat!) }]);
          break;
        case 'round_ended': {
          const placings = e.placings as number[];
          candidates.push(['win', placings[0]!, { name: name(placings[0]!) }]);
          break;
        }
        default:
          break;
      }
    }
    // Most important first: big moments beat chatter.
    const rank = (k: string): number => (PRIORITY.includes(k) ? PRIORITY.indexOf(k) : MAJOR.has(k) ? 50 : 100);
    candidates.sort((a, b) => rank(a[0]) - rank(b[0]));
    for (const [key, target, vars] of candidates) {
      const line = this.director.pick(key, target, vars, MAJOR.has(key));
      if (line) return [line];
    }
    return [];
  }
}

/** How long the table pauses after an entry before the next bot moves. */
/** The rarest plays: a single 2♠ or any straight flush. */
export function isLegendary(cards: readonly Card[], kind: string): boolean {
  return (kind === 'single' && cards[0] === '2s') || kind === 'straightflush';
}

export function dwellMs(events: GameEvent[]): number {
  let ms = 0;
  for (const e of events) {
    if (e.type === 'card_played' && isLegendary(e.cards as Card[], e.kind as string)) ms = Math.max(ms, 4300);
    if (e.type === 'round_started') ms = Math.max(ms, (e.previewMs as number) ?? 0);
    if (e.type === 'unbeatable') ms = Math.max(ms, (e.left as number) === 1 ? 3200 : 2400);
    else if (e.type === 'bomb' || e.type === 'double_it') ms = Math.max(ms, 1800);
    else if (e.type === 'all_passed' || e.type === 'player_out') ms = Math.max(ms, 1200);
    else if (e.type === 'jester') ms = Math.max(ms, 900);
    else if (e.type === 'card_played') ms = Math.max(ms, 500);
  }
  return ms;
}
