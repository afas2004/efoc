// "Practice vs bots" for Lucky 7: the whole game runs inside the page in
// host mode, alone, with no network.

import { lucky7 } from '@efoc/engine';
import type { Humour } from '../../feel/jester';
import { HostCore, type Personality, type SeatInfo } from '../../host/hostCore';
import { dwellMs, LuckySevenCommentator } from './commentary';
import { LuckySevenTable, type TableSettings } from './table';

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

export type LuckyHost = HostCore<lucky7.LuckySevenConfig, lucky7.LuckyState, lucky7.LuckyMove, lucky7.LuckyView>;

/** Host options shared by Practice and online tables. */
export function luckyHostOptions(turnMs: number, commentator: LuckySevenCommentator, extra: { fast?: boolean; botSpeed?: number; seed?: number } = {}) {
  return {
    turnMs,
    ...extra,
    previewMs: 0,
    commentate: (events: Parameters<LuckySevenCommentator['comment']>[0], state: unknown) => commentator.comment(events, state as lucky7.LuckyState),
    dwell: dwellMs,
    // A J's own-card peek gets its seconds on top of the turn.
    extraMs: (events: { type: string; power?: unknown }[]) => (events.some((e) => e.type === 'power' && e.power === 'J') ? lucky7.defaultConfig.peekSeconds * 1000 : 0),
    // Final lap: every timer halves.
    turnScale: (state: unknown) => {
      const s = state as lucky7.LuckyState;
      return s.phase === 'play' && s.deck.length <= s.players ? 0.5 : 1;
    },
  };
}

export function startPractice(root: HTMLElement, o: PracticeOptions): { host: LuckyHost; table: LuckySevenTable } {
  const players = Math.max(2, Math.min(8, o.players));
  const seats: SeatInfo[] = [
    { name: o.myName, avatar: o.myAvatar, bot: o.autoplay ? { level: 'normal', personality: 'speedy' } : null },
    ...BOTS.slice(0, players - 1).map((b) => ({ name: b.name, avatar: b.avatar, bot: { level: b.level, personality: b.personality } })),
  ];
  let jesterSeed = (o.seed ?? Math.floor(Math.random() * 2 ** 31)) ^ 0x5eed;
  const commentator = new LuckySevenCommentator(seats.map((s) => s.name), () => {
    jesterSeed = (Math.imul(jesterSeed, 1103515245) + 12345) >>> 0;
    return jesterSeed / 2 ** 32;
  });
  commentator.director.humour = o.humour;
  const host: LuckyHost = new HostCore(lucky7.luckySeven, seats, lucky7.defaultConfig, luckyHostOptions(o.turnMs ?? 20_000, commentator, { fast: o.fast, botSpeed: o.botSpeed, seed: o.seed }));
  const me = 0;
  const table = new LuckySevenTable(
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
    table.update(lucky7.view(host.state, me), events, { deadline: entry.deadline, afk: host.afk.slice() });
  });
  host.start();
  return { host, table };
}
