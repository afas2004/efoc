// Big Two bots. They only see view(), the same as a human.
//   easy:   a random legal move, weighted toward low cards.
//   normal: holds 2s and bombs, plays the lowest beating combo, and
//           fights hard when an opponent is about to go out.

import { compareKeys } from '../../core/combos';
import type { Rng } from '../../core/rng';
import type { BotLevel } from '../../core/types';
import {
  classify,
  isBomb,
  legalPlays,
  rankIndex,
  sortCards,
  type BigTwoMove,
  type BigTwoView,
  type Play,
} from './rules';

const TWO = 12;
const PASS: BigTwoMove = { type: 'pass' };
const playOf = (p: Play): BigTwoMove => ({ type: 'play', cards: p.cards });

export function bot(view: BigTwoView, level: BotLevel, rng: Rng): BigTwoMove {
  if (view.seat === 'public') throw new Error('A bot needs a seat view');
  const lead = view.lead ? classify(view.lead.cards, view.config) : null;
  const plays = legalPlays(view.hand, lead, view.mustInclude, view.config);
  if (plays.length === 0) return PASS; // only possible when following
  return level === 'easy' ? easy(plays, lead !== null, rng) : normal(view, plays, lead !== null);
}

function easy(plays: Play[], canPass: boolean, rng: Rng): BigTwoMove {
  // Weight each play by how low its cards are; passing gets a fixed share.
  const weights = plays.map((p) => {
    const avg = p.cards.reduce((sum, c) => sum + rankIndex(c), 0) / p.cards.length;
    return 1 / (1 + avg);
  });
  const passWeight = canPass ? 0.15 : 0;
  const total = weights.reduce((a, b) => a + b, 0) + passWeight;
  let pick = rng.next() * total;
  for (let i = 0; i < plays.length; i++) {
    pick -= weights[i]!;
    if (pick < 0) return playOf(plays[i]!);
  }
  return canPass ? PASS : playOf(plays[plays.length - 1]!);
}

const usesTwo = (p: Play): boolean => p.cards.some((c) => rankIndex(c) === TWO);
const lowestFirst = (a: Play, b: Play): number => compareKeys(a.combo.key, b.combo.key);

function normal(view: BigTwoView, plays: Play[], following: boolean): BigTwoMove {
  const me = view.seat as number;
  const hand = view.hand;

  // Go out if one play empties the hand.
  const finisher = plays.find((p) => p.cards.length === hand.length);
  if (finisher) return playOf(finisher);

  const opponentCounts = view.handCounts.filter((n, seat) => seat !== me && n > 0);
  const fewest = Math.min(...opponentCounts);
  const danger = fewest <= 2;

  // Cards that belong to a four of a kind we'd rather keep as a bomb.
  const quadRanks = new Set<number>();
  const byRank = new Map<number, number>();
  for (const c of hand) byRank.set(rankIndex(c), (byRank.get(rankIndex(c)) ?? 0) + 1);
  for (const [r, n] of byRank) if (n === 4) quadRanks.add(r);
  const breaksBomb = (p: Play): boolean =>
    !isBomb(p.combo.kind) && p.cards.some((c) => quadRanks.has(rankIndex(c)));
  const precious = (p: Play): boolean => usesTwo(p) || isBomb(p.combo.kind) || breaksBomb(p);

  if (following) {
    const sorted = [...plays].sort(lowestFirst);
    if (danger) {
      // Stop them: a single against someone on one card gets our best single.
      if (view.lead!.cards.length === 1 && fewest === 1) return playOf(sorted[sorted.length - 1]!);
      return playOf(sorted[0]!);
    }
    const cheap = sorted.find((p) => !precious(p));
    if (cheap) return playOf(cheap);
    // Only 2s or bombs beat it: spend them when our hand is nearly done.
    return hand.length <= 4 ? playOf(sorted[0]!) : PASS;
  }

  // Leading: shed the lowest card, in the biggest combo that holds it.
  const low = view.mustInclude ?? sortCards(hand)[0]!;
  const withLow = plays.filter((p) => p.cards.includes(low));
  const pool = withLow.filter((p) => !precious(p));
  const candidates = pool.length > 0 ? pool : withLow.length > 0 ? withLow : plays;
  if (danger && fewest === 1) {
    // A lone single would hand them the win: lead a bigger combo, or our top single.
    const multi = plays.filter((p) => p.cards.length > 1).sort((a, b) => b.cards.length - a.cards.length);
    if (multi.length > 0) return playOf(multi[0]!);
    return playOf([...plays].sort(lowestFirst)[plays.length - 1]!);
  }
  const best = [...candidates].sort(
    (a, b) => b.cards.length - a.cards.length || lowestFirst(a, b),
  )[0]!;
  return playOf(best);
}
