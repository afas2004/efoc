// Zombie bots. They see only view(), like a person: their own hand and how
// many cards everyone holds. Every slot of the hand they draw from is
// face down, so the pick is random; the skill is in hiding.
//   easy:   random pick; shuffles after drawing now and then.
//   normal: random pick; usually shuffles after drawing, almost always when
//           it holds the Zombie (a little tell, like a nervous person).

import type { BotLevel } from '../../core/types';
import type { Rng } from '../../core/rng';
import { isZombie, type ZombieMove, type ZombieView } from './rules';

export function bot(v: ZombieView, level: BotLevel, rng: Rng): ZombieMove {
  if (v.seat === 'public') throw new Error('A bot needs a seat view');
  const slot = rng.int(Math.max(1, v.counts[v.from]!));
  const holding = v.hand.some(isZombie);
  const p = level === 'easy' ? 0.3 : holding ? 0.9 : 0.5;
  return rng.next() < p ? { type: 'draw', slot, shuffle: true } : { type: 'draw', slot };
}
