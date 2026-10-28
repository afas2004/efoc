// "Practice vs bots" for Zombie: the whole game runs inside the page in
// host mode, alone, with no network.

import { zombie } from '@efoc/engine';
import type { Humour } from '../../feel/jester';
import { HostCore, type Personality, type SeatInfo } from '../../host/hostCore';
import { dwellMs, ZombieCommentator } from './commentary';
import { ZombieTable, type TableSettings } from './table';

export interface PracticeOptions {
  players: number;
  myName: string;
  myAvatar: string;
  seed?: number;
  fast?: boolean;
  botSpeed?: number;
  turnMs?: number;
  /** My seat is played by a bot (layout tests). */
  autoplay?: boolean;
  humour: Humour;
  settings?: Partial<TableSettings>;
  onExit(): void;
}

const BOTS: { name: string; avatar: string; personality: Personality; level: 'easy' | 'normal' }[] = [
  { name: 'Speedy', avatar: '🐇', personality: 'speedy', level: 'easy' },
  { name: 'Grandmaster', avatar: '🦉', personality: 'grandmaster', level: 'normal' },
  { name: 'Bluffer', avatar: '🦊', personality: 'bluffer', level: 'normal' },
  { name: 'Slowpoke', avatar: '🐢', personality: 'slowpoke', level: 'easy' },
  { name: 'Tiger', avatar: '🐯', personality: 'grandmaster', level: 'normal' },
  { name: 'Panda', avatar: '🐼', personality: 'speedy', level: 'normal' },
  { name: 'Kancil', avatar: '🦌', personality: 'bluffer', level: 'easy' },
];

export type ZombieHost = HostCore<zombie.ZombieConfig, zombie.ZombieState, zombie.ZombieMove, zombie.ZombieView>;

/** Zombie's draw clock (Fahmi, 28 Oct: 15 s, then the card pointed at, or a random one). */
export const ZOMBIE_TURN_MS = 15_000;

/** Host options shared by Practice and online tables. */
export function zombieHostOptions(turnMs: number, commentator: ZombieCommentator, extra: { fast?: boolean; botSpeed?: number; seed?: number } = {}) {
  return {
    turnMs,
    ...extra,
    previewMs: 0,
    commentate: (events: Parameters<ZombieCommentator['comment']>[0], state: unknown) => commentator.comment(events, state as zombie.ZombieState),
    dwell: dwellMs,
    // Pointing at a card doesn't take the turn or touch the clock.
    sideMove: (m: unknown) => (m as { type?: string } | null)?.type === 'aim',
    // A blind pick or a throw doesn't depend on which entry it was made against.
    staleOk: (m: unknown) => ['draw', 'throw'].includes((m as { type?: string } | null)?.type ?? ''),
    // The deal's pairs are thrown by everyone at once, on one clock.
    keepClock: (before: unknown, after: unknown) => (before as zombie.ZombieState).step === 'deal' && (after as zombie.ZombieState).step === 'deal',
    // 20 s for the deal's pairs, 15 s to draw, 10 s to throw a drawn pair (Fahmi, 28 Oct).
    turnScale: (state: unknown) => ({ deal: 20 / 15, draw: 1, throw: 10 / 15 })[(state as zombie.ZombieState).step],
  };
}

export function startPractice(root: HTMLElement, o: PracticeOptions): { host: ZombieHost; table: ZombieTable } {
  const players = Math.max(2, Math.min(8, o.players));
  const seats: SeatInfo[] = [
    { name: o.myName, avatar: o.myAvatar, bot: o.autoplay ? { level: 'normal', personality: 'speedy' } : null },
    ...BOTS.slice(0, players - 1).map((b) => ({ name: b.name, avatar: b.avatar, bot: { level: b.level, personality: b.personality } })),
  ];
  let jesterSeed = (o.seed ?? Math.floor(Math.random() * 2 ** 31)) ^ 0x5eed;
  const commentator = new ZombieCommentator(seats.map((s) => s.name), () => {
    jesterSeed = (Math.imul(jesterSeed, 1103515245) + 12345) >>> 0;
    return jesterSeed / 2 ** 32;
  });
  commentator.director.humour = o.humour;
  const host: ZombieHost = new HostCore(zombie.zombie, seats, zombie.defaultConfig, zombieHostOptions(o.turnMs ?? ZOMBIE_TURN_MS, commentator, { fast: o.fast, botSpeed: o.botSpeed, seed: o.seed }));
  const me = 0;
  const table = new ZombieTable(
    root,
    me,
    seats.map((s, i) => ({ name: s.name, avatar: s.avatar, bot: i !== me && s.bot !== null })),
    true,
    {
      move: (m) => {
        const reason = host.submit(me, m);
        if (reason) table.reject(reason);
      },
      playAgain: () => host.playAgain(),
      back: () => host.back(me),
      exit: () => {
        host.stop();
        o.onExit();
      },
    },
    { humour: o.humour, sound: true, reducedMotion: false, ...o.settings },
  );
  host.onEntry((entry) => {
    // Private events are for their own seat only.
    const events = entry.events.filter((e) => e.to === undefined || e.to === me);
    table.update(zombie.view(host.state, me), events, { deadline: entry.deadline, afk: host.afk.slice() });
  });
  host.start();
  return { host, table };
}
