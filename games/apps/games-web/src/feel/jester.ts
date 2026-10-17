// The Jester: one mascot who comments on play. Lines live in the locale
// file keyed by event. Rules (spec "Humour system"):
//   - at most one line per 15 s,
//   - never the same target twice in a row,
//   - a player gets as many cheering lines as teasing ones,
//   - Off / Mild / Spicy per room; Spicy unlocks lines marked spicy.

import { L, fmt } from '../strings';

export type Humour = 'off' | 'mild' | 'spicy';

interface Line {
  text: string;
  tone: 'tease' | 'cheer' | 'neutral';
  spicy?: boolean;
}

export interface JesterSay {
  text: string;
  tone: Line['tone'];
  target: number | null;
}

export const JESTER_GAP_MS = 15_000;

export class Jester {
  humour: Humour = 'mild';
  private lastAt = -Infinity;
  private lastTarget: number | null = null;
  private teased = new Map<number, number>();
  private cheered = new Map<number, number>();
  private lastText = '';

  constructor(
    private readonly rand: () => number = Math.random,
    private readonly now: () => number = () => Date.now(),
  ) {}

  /**
   * A line for `event` about seat `target` (or the table), or null if the
   * Jester stays quiet. `force` skips the 15 s gap for results screens.
   */
  say(event: string, target: number | null, name: string, force = false): JesterSay | null {
    if (this.humour === 'off') return null;
    const t = this.now();
    if (!force && t - this.lastAt < JESTER_GAP_MS) return null;
    if (target !== null && target === this.lastTarget && !force) return null;
    const bank = (L().jester as Record<string, Line[]>)[event];
    if (!bank) return null;
    let pool = bank.filter((l) => this.humour === 'spicy' || !l.spicy);
    if (target !== null && (this.teased.get(target) ?? 0) > (this.cheered.get(target) ?? 0)) {
      // Owed a cheer: use this event's cheering lines, or the generic bank.
      const cheers = pool.filter((l) => l.tone === 'cheer');
      pool = cheers.length > 0 ? cheers : (L().jester.cheer as Line[]);
    }
    pool = pool.filter((l) => l.text !== this.lastText);
    if (pool.length === 0) return null;
    const line = pool[Math.floor(this.rand() * pool.length)]!;
    this.lastAt = t;
    this.lastTarget = target;
    this.lastText = line.text;
    if (target !== null) {
      const m = line.tone === 'tease' ? this.teased : line.tone === 'cheer' ? this.cheered : null;
      m?.set(target, (m.get(target) ?? 0) + 1);
    }
    return { text: fmt(line.text, { name }), tone: line.tone, target };
  }
}
