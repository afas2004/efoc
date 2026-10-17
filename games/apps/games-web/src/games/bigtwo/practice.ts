// "Practice vs bots": the whole game runs inside the page in host mode,
// alone, with no network. The first time, it runs as the tutorial round.

import { bigtwo, createRng } from '@efoc/engine';
import { HostCore, type Personality, type SeatInfo } from '../../host/hostCore';
import type { Humour } from '../../feel/jester';
import { L } from '../../strings';
import { BigTwoCommentator, dwellMs } from './commentary';
import { BigTwoTable, type TableSettings } from './table';

export interface PracticeOptions {
  players: number;
  myName: string;
  myAvatar: string;
  config: bigtwo.BigTwoConfig;
  seed?: number;
  fast?: boolean;
  /** Multiplies bot thinking time; tests pass a small value. */
  botSpeed?: number;
  turnMs?: number;
  /** My seat is played by a bot (layout tests). */
  autoplay?: boolean;
  tutorial: boolean;
  humour: Humour;
  settings?: Partial<TableSettings>;
  onExit(): void;
  onTutorialDone(): void;
  /** Back to the setup sheet (results screen "Change rules"). */
  onChangeRules?: () => void;
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

/** A seed whose deal gives seat 0 the 3♦, so the tutorial starts with you. */
function tutorialSeed(players: number, config: bigtwo.BigTwoConfig): number {
  for (let seed = 1; ; seed++) {
    const s = bigtwo.setup([...Array(players).keys()], config, createRng(seed));
    if (s.turn === 0 && s.mustInclude === '3d') return seed;
  }
}

export function startPractice(root: HTMLElement, o: PracticeOptions): { host: HostCore<bigtwo.BigTwoConfig, bigtwo.BigTwoState, bigtwo.BigTwoMove, bigtwo.BigTwoView>; table: BigTwoTable } {
  const players = o.tutorial ? 4 : o.players;
  const seats: SeatInfo[] = [
    { name: o.myName, avatar: o.myAvatar, bot: o.autoplay ? { level: 'normal', personality: 'speedy' } : null },
    ...BOTS.slice(0, players - 1).map((b) => ({ name: b.name, avatar: b.avatar, bot: { level: b.level, personality: b.personality } })),
  ];
  const turnMs = o.tutorial ? 60_000 : o.turnMs ?? 20_000;
  // The host's Jester: seeded per match, so a replay picks the same lines.
  let jesterSeed = (o.seed ?? Math.floor(Math.random() * 2 ** 31)) ^ 0x5eed;
  const commentator = new BigTwoCommentator(seats.map((s) => s.name), () => {
    jesterSeed = (Math.imul(jesterSeed, 1103515245) + 12345) >>> 0;
    return jesterSeed / 2 ** 32;
  });
  commentator.director.humour = o.humour;
  const host = new HostCore(
    { ...bigtwo.bigTwo, nextRound: bigtwo.nextRound },
    seats,
    o.config,
    {
      turnMs,
      fast: o.fast,
      botSpeed: o.tutorial ? 1.4 : o.botSpeed,
      seed: o.tutorial ? tutorialSeed(players, o.config) : o.seed,
      commentate: (events, state) => commentator.comment(events, state as bigtwo.BigTwoState),
      dwell: dwellMs,
    },
  );
  const settings: TableSettings = { humour: o.humour, sound: true, reducedMotion: false, fourColour: false, ...o.settings };
  const me = 0;
  const table = new BigTwoTable(
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
      nextRound: () => host.nextRound(),
      changeRules: o.onChangeRules
        ? () => {
            host.stop();
            o.onChangeRules!();
          }
        : undefined,
      setHumour: (h) => (commentator.director.humour = h),
      back: () => host.back(me),
      exit: () => {
        host.stop();
        o.onExit();
      },
    },
    settings,
  );
  root.dataset.turnMs = String(host.turnMs);

  // Tutorial tips, each shown once at the right moment.
  const shown = new Set<string>();
  let tutorialOn = o.tutorial;
  const tip = (key: keyof ReturnType<typeof L>['tutorial']): void => {
    if (!tutorialOn || shown.has(key)) return;
    shown.add(key);
    table.showTip(L().tutorial[key], () => {}, () => {
      tutorialOn = false;
      o.onTutorialDone();
    });
  };

  host.onEntry((entry) => {
    const view = bigtwo.view(host.state, me);
    table.update(view, entry.events, { deadline: entry.deadline, afk: host.afk.slice(), totals: host.totals.slice() });
    if (!tutorialOn) return;
    const types = entry.events.map((e) => e.type);
    if (types.includes('round_started')) tip('lead3d');
    else if (types.includes('all_passed') && view.turn === me && view.phase === 'play') tip('freeLead');
    else if (view.turn === me && view.lead && view.lead.seat !== me && view.phase === 'play') tip('beatIt');
    else if (entry.seat === me && shown.has('lead3d')) tip('order');
    if (types.includes('match_points')) {
      tip('goal');
      tutorialOn = false;
      o.onTutorialDone();
    }
  });
  host.start();
  return { host, table };
}
