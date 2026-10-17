// Moment tiers. Every engine event maps to one tier, and the tier sets how
// long and how loud the reaction is, so a moment of the same weight feels
// the same in every game. See spec "Moment tiers".
//
//   T0 Touch   150 ms   select, sort, drag
//   T1 Play    300 ms   normal play, draw, pass
//   T2 Swing   700 ms   beat a strong play, take points, a good grab
//   T3 Big    1500 ms   bomb, shoot the moon, comeback; tap to skip; one at a time
//   T4 Ending 4000 ms   round and match results; tap to skip
//   Legendary 3800 ms   a T3 for the rarest plays (2♠ single, straight
//                       flush): thrown, slammed, announced. Longer than the
//                       spec's 1.5 s at Fahmi's request; still never blocks
//                       input, and a tap skips it.
//
// T0 and T1 never queue. One T3 plays at a time and the rest wait. Input is
// never blocked: the T3 dimmer ignores pointer events and a tap anywhere
// skips it.

export type Tier = 0 | 1 | 2 | 3 | 4;

export const TIER_MS: Record<Tier, number> = { 0: 150, 1: 300, 2: 700, 3: 1500, 4: 4000 };

/** A running moment. The effect gets this and must stop when told. */
export interface MomentCtx {
  ms: number;
  reduced: boolean;
  /** Called by the effect if it wants to end early. */
  end(): void;
  /** Registers cleanup that runs when the moment ends or is skipped. */
  onEnd(fn: () => void): void;
}

export type Effect = (ctx: MomentCtx) => void;

export interface FeelRecord {
  tier: Tier;
  name: string;
  start: number;
  end: number | null;
  skipped: boolean;
}

interface Pending {
  tier: Tier;
  name: string;
  effect: Effect;
  ms?: number;
}

/** Longest a T3 may run when it asks for more than the standard 1.5 s. */
export const LEGENDARY_MS = 3800;

export class FeelQueue {
  readonly log: FeelRecord[] = [];
  reduced = false;
  private bigQueue: Pending[] = [];
  private bigActive: (() => void) | null = null;

  constructor(private readonly now: () => number = () => performance.now()) {
    // A tap anywhere skips the current T3/T4 without swallowing the tap.
    if (typeof document !== 'undefined') {
      document.addEventListener('pointerdown', () => this.skip(), { capture: true });
    }
  }

  play(tier: Tier, name: string, effect: Effect, ms?: number): void {
    if (tier >= 3) {
      this.bigQueue.push({ tier, name, effect, ms: ms === undefined ? undefined : Math.min(ms, LEGENDARY_MS) });
      if (!this.bigActive) this.nextBig();
      return;
    }
    this.run({ tier, name, effect }, () => {});
  }

  /** Skips the current T3/T4 animation. */
  skip(): void {
    this.bigActive?.();
  }

  get busyBig(): boolean {
    return this.bigActive !== null;
  }

  private nextBig(): void {
    const next = this.bigQueue.shift();
    if (!next) return;
    this.bigActive = this.run(next, () => {
      this.bigActive = null;
      this.nextBig();
    });
  }

  private run(p: Pending, after: () => void): () => void {
    const rec: FeelRecord = { tier: p.tier, name: p.name, start: this.now(), end: null, skipped: false };
    this.log.push(rec);
    if (this.log.length > 500) this.log.splice(0, this.log.length - 500);
    const cleanups: (() => void)[] = [];
    let done = false;
    const finish = (skipped: boolean): void => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      rec.end = this.now();
      rec.skipped = skipped;
      for (const c of cleanups) {
        try {
          c();
        } catch {
          /* an effect failing must never block the table */
        }
      }
      after();
    };
    const ms = p.ms ?? TIER_MS[p.tier];
    const timer = setTimeout(() => finish(false), ms);
    try {
      p.effect({ ms, reduced: this.reduced, end: () => finish(false), onEnd: (fn) => cleanups.push(fn) });
    } catch {
      finish(false);
    }
    return () => finish(true);
  }
}
