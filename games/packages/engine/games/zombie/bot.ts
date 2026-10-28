// Zombie bots. They see only view(), like a person: their own hand and how
// many cards everyone holds. Every card of the hand they draw from is face
// down and freshly shuffled, so the pick is random; pairs are thrown at once.
// A timed-out human gets the same: the card they were pointing at, if any.

import type { BotLevel } from '../../core/types';
import type { Rng } from '../../core/rng';
import type { ZombieMove, ZombieView } from './rules';

export function bot(v: ZombieView, _level: BotLevel, rng: Rng): ZombieMove {
  if (v.seat === 'public') throw new Error('A bot needs a seat view');
  if (v.step !== 'draw') return { type: 'throw' };
  if (v.aim !== null && v.aim < v.counts[v.from]!) return { type: 'draw', slot: v.aim };
  return { type: 'draw', slot: rng.int(Math.max(1, v.counts[v.from]!)) };
}
