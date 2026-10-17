// Match stats for the results screen, built from public log events only, so
// every phone (and spectator) shows the same numbers.

import { bigtwo, type Card, type GameEvent } from '@efoc/engine';

export interface SeatStats {
  cardsPlayed: number;
  plays: number;
  passes: number;
  twos: number;
  bombs: number;
  tooSlow: number;
  roasted: number;
  /** Best play by combo strength, e.g. a full house. */
  best: { cards: Card[]; kind: string; rank: number } | null;
}

const KIND_RANK: Record<string, number> = {
  single: 0, pair: 1, triple: 2, quad: 3, twopair: 4, trips: 5, straight: 6, flush: 7, fullhouse: 8, fourkind: 9, straightflush: 10,
};

export class MatchStats {
  seats: SeatStats[] = [];
  moves = 0;
  startedAt = Date.now();
  biggest: { seat: number; cards: Card[]; kind: string; rank: number } | null = null;

  reset(players: number): void {
    this.seats = Array.from({ length: players }, () => ({
      cardsPlayed: 0, plays: 0, passes: 0, twos: 0, bombs: 0, tooSlow: 0, roasted: 0, best: null,
    }));
    this.moves = 0;
    this.startedAt = Date.now();
    this.biggest = null;
  }

  feed(e: GameEvent, players: number): void {
    if (this.seats.length !== players) this.reset(players);
    const seat = typeof e.seat === 'number' ? e.seat : -1;
    const s = this.seats[seat];
    switch (e.type) {
      case 'card_played': {
        if (!s) return;
        const cards = e.cards as Card[];
        const kind = e.kind as string;
        this.moves++;
        s.plays++;
        s.cardsPlayed += cards.length;
        s.twos += cards.filter((c) => bigtwo.rankIndex(c) === 12).length;
        // Strength: combo kind first, then the top card.
        const rank = (KIND_RANK[kind] ?? 0) * 100 + Math.max(...cards.map(bigtwo.cardValue));
        if (!s.best || rank > s.best.rank) s.best = { cards, kind, rank };
        if (!this.biggest || rank > this.biggest.rank) this.biggest = { seat, cards, kind, rank };
        break;
      }
      case 'passed':
        if (s) {
          s.passes++;
          this.moves++;
        }
        break;
      case 'bomb':
        if (s) s.bombs++;
        break;
      case 'too_slow':
        if (s) s.tooSlow++;
        break;
      case 'jester': {
        const target = e.target as number | null;
        if (target !== null && this.seats[target] && (e.mood === 'laugh' || e.mood === 'sad')) this.seats[target]!.roasted++;
        break;
      }
      default:
        break;
    }
  }

  get durationMs(): number {
    return Date.now() - this.startedAt;
  }
}
