// The Jester: one mascot who comments on play so the whole table knows what
// just happened. The HOST picks every line and sends it in the log as a
// `jester` event, so all players and spectators see the same line at the
// same moment. Lines live in the locale file keyed by event; the event's
// facts (who, what combo, next player) fill the placeholders.
//
// Rules (spec "Humour system", adjusted after playtest):
//   - big moments (bomb, last card, going out, win) always get a line,
//   - smaller ones wait 15 s after the last line,
//   - never the same target twice in a row for small moments,
//   - a player gets as many cheering lines as teasing ones,
//   - Off / Mild / Spicy per room; Spicy unlocks lines marked spicy.
// Lines only ever use public information.

import type { GameEvent } from '@efoc/engine';
import { L, fmt } from '../strings';

export type Humour = 'off' | 'mild' | 'spicy';
export type Mood = 'talk' | 'laugh' | 'shock' | 'smug' | 'sad' | 'cheer';

interface Line {
  text: string;
  tone: 'tease' | 'cheer' | 'neutral';
  spicy?: boolean;
}

/** What the host sends; every phone renders it the same way. */
export interface JesterEvent extends GameEvent {
  type: 'jester';
  key: string;
  idx: number;
  target: number | null;
  vars: Record<string, string | number>;
  mood: Mood;
  /** A Noto reaction to pop beside the Jester, e.g. 'laugh', 'explode'. */
  emoji: string | null;
}

export const JESTER_GAP_MS = 15_000;

/** Mood and reaction per event key. */
const STYLE: Record<string, { mood: Mood; emoji: string | null }> = {
  round_start: { mood: 'talk', emoji: 'cool' },
  bomb: { mood: 'shock', emoji: 'explode' },
  all_passed: { mood: 'smug', emoji: 'cool' },
  two_early: { mood: 'shock', emoji: 'fire' },
  big_play: { mood: 'shock', emoji: 'fire' },
  pass_streak: { mood: 'laugh', emoji: 'eyeroll' },
  too_slow: { mood: 'laugh', emoji: 'laugh' },
  double_it: { mood: 'laugh', emoji: 'laugh' },
  one_card: { mood: 'shock', emoji: 'scream' },
  player_out: { mood: 'cheer', emoji: 'party' },
  win: { mood: 'cheer', emoji: 'party' },
  last_place: { mood: 'sad', emoji: 'grimace' },
  cheer: { mood: 'cheer', emoji: null },
};

export class JesterDirector {
  humour: Humour = 'mild';
  private lastAt = -Infinity;
  private lastTarget: number | null = null;
  private lastKey = '';
  private teased = new Map<number, number>();
  private cheered = new Map<number, number>();

  constructor(
    private readonly rand: () => number,
    private readonly now: () => number = () => Date.now(),
  ) {}

  /** Picks a line, or null if the Jester stays quiet. `major` skips the gap. */
  pick(key: string, target: number | null, vars: Record<string, string | number>, major: boolean): JesterEvent | null {
    if (this.humour === 'off') return null;
    const t = this.now();
    if (!major && t - this.lastAt < JESTER_GAP_MS) return null;
    if (!major && target !== null && target === this.lastTarget) return null;
    const banks = L().jester as Record<string, Line[]>;
    let useKey = key;
    let pool = (banks[key] ?? []).map((line, idx) => ({ line, idx }));
    pool = pool.filter(({ line }) => this.humour === 'spicy' || !line.spicy);
    if (target !== null && (this.teased.get(target) ?? 0) > (this.cheered.get(target) ?? 0)) {
      // Owed a cheer: this event's cheering lines, or the generic bank.
      const cheers = pool.filter(({ line }) => line.tone === 'cheer');
      if (cheers.length > 0) pool = cheers;
      else if (!major) {
        useKey = 'cheer';
        pool = (banks.cheer ?? []).map((line, idx) => ({ line, idx }));
      }
    }
    if (pool.length === 0) return null;
    const { line, idx } = pool[Math.floor(this.rand() * pool.length)]!;
    this.lastAt = t;
    this.lastTarget = target;
    this.lastKey = useKey;
    if (target !== null) {
      const m = line.tone === 'tease' ? this.teased : line.tone === 'cheer' ? this.cheered : null;
      m?.set(target, (m.get(target) ?? 0) + 1);
    }
    const style = STYLE[useKey] ?? { mood: 'talk' as Mood, emoji: null };
    return { type: 'jester', key: useKey, idx, target, vars, mood: line.tone === 'tease' && style.mood === 'talk' ? 'laugh' : style.mood, emoji: style.emoji };
  }

  get last(): string {
    return this.lastKey;
  }
}

/** The line's text in this phone's locale. */
export function jesterText(e: JesterEvent): string {
  const bank = (L().jester as Record<string, Line[]>)[e.key];
  const line = bank?.[e.idx];
  return line ? fmt(line.text, e.vars) : '';
}

export function isTease(e: JesterEvent): boolean {
  const bank = (L().jester as Record<string, Line[]>)[e.key];
  return bank?.[e.idx]?.tone === 'tease';
}
