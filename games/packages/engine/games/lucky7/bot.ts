// Lucky 7 bots. They see only view(), like a person: no slot is ever
// visible, and they remember nothing between turns, so they play the odds.
// An unknown slot is worth about 6 on average, so any card worth 4 or less
// is worth swapping in, and a 7 or an A on Discard is worth taking.
//   easy:   draws from the centre deck, swaps low cards in, otherwise random.
//   normal: grabs a low Discard card, swaps in anything 4 or less, and uses
//           powers to sabotage: locks and shuffles the player doing best.

import type { BotLevel, SeatId } from '../../core/types';
import type { Rng } from '../../core/rng';
import { cardPoints, powerOf, type LuckyMove, type LuckyView, type Target } from './rules';

const SWAP_AT_MOST = 4;

const openSlots = (v: LuckyView, seat: SeatId): number[] => [0, 1, 2].filter((i) => !v.locked[seat]![i]);
const opponents = (v: LuckyView, me: SeatId): SeatId[] => Array.from({ length: v.players }, (_, i) => i).filter((i) => i !== me);

function pick<T>(items: readonly T[], rng: Rng): T {
  return items[rng.int(items.length)]!;
}

export function bot(v: LuckyView, level: BotLevel, rng: Rng): LuckyMove {
  if (v.seat === 'public') throw new Error('A bot needs a seat view');
  const me = v.seat;

  if (v.step === 'draw') {
    const top = v.discard[v.discard.length - 1];
    const wantTop = top !== undefined && cardPoints(top) <= (level === 'normal' ? 2 : 1);
    return { type: 'draw', from: wantTop || v.deckCount === 0 ? 'discard' : 'deck' };
  }

  if (v.step === 'peek') {
    const targets: Target[] = [];
    for (const seat of opponents(v, me)) for (const slot of openSlots(v, seat)) targets.push({ seat, slot });
    // Every opponent card locked: a look at one of mine instead.
    if (!targets.length) for (const slot of openSlots(v, me)) targets.push({ seat: me, slot });
    return { type: 'peek', target: targets.length ? pick(targets, rng) : null };
  }

  // step 'act': the drawn card is in view (this seat drew it).
  const card = v.drawn;
  const mine = openSlots(v, me);
  const low = card !== null && cardPoints(card) <= SWAP_AT_MOST;
  if (low && mine.length) return { type: 'swap', slot: pick(mine, rng) };

  const power = powerOf(card);
  if (power && (level === 'normal' || rng.next() < 0.5)) {
    const use = usePower(v, me, power, rng);
    if (use) return use;
  }
  if (level === 'easy' && mine.length && rng.next() < 0.15) return { type: 'swap', slot: pick(mine, rng) };
  return { type: 'discard' };
}

function usePower(v: LuckyView, me: SeatId, power: NonNullable<ReturnType<typeof powerOf>>, rng: Rng): LuckyMove | null {
  const opp = opponents(v, me);
  // Without memory, "doing best" is a guess: whoever has fewest locks to hide behind.
  const victim = opp.slice().sort((a, b) => openSlots(v, b).length - openSlots(v, a).length)[0]!;
  switch (power) {
    case 'J':
      return { type: 'use' };
    case 'Q': {
      const mine = openSlots(v, me);
      const theirs: Target[] = [];
      for (const seat of opp) for (const slot of openSlots(v, seat)) theirs.push({ seat, slot });
      if (!mine.length || !theirs.length) return null;
      return { type: 'use', mine: pick(mine, rng), target: pick(theirs, rng) };
    }
    case 'K': {
      const open = openSlots(v, victim);
      return open.length ? { type: 'use', target: { seat: victim, slot: pick(open, rng) } } : null;
    }
    case '9': {
      // Free one of my own cards so I can swap it out later.
      const locked = [0, 1, 2].filter((i) => v.locked[me]![i]);
      return { type: 'use', target: locked.length ? { seat: me, slot: pick(locked, rng) } : null };
    }
    case 'T':
      return openSlots(v, victim).length > 1 ? { type: 'use', seat: victim } : null;
  }
}

