// Big Two page entry. Inside the EFOC app it waits for `init` from Flutter;
// opened on its own (dev server, Playwright) it starts Practice from the URL:
//   ?players=4&seed=1&mode=standard|fightTillTheEnd&fast=1&speed=0.05
//   &turn=20000&autoplay=1&tutorial=0&humour=off|mild|spicy&reduced=1&preview=5000

import './styles.css';
import { bigtwo } from '@efoc/engine';
import { inApp, onMessage, send, startBridge } from './bridge';
import type { Humour } from './feel/jester';
import { launchOnline } from './net/launch';
import { startPractice } from './games/bigtwo/practice';
import { showSetup, type SetupChoice } from './games/bigtwo/setup';

const TUTORIAL_KEY = 'efoc.tutorial.bigtwo';

function storage(): Storage | null {
  try {
    return window.localStorage;
  } catch {
    return null;
  }
}

function tutorialDone(): boolean {
  return storage()?.getItem(TUTORIAL_KEY) === '1';
}

function markTutorialDone(): void {
  try {
    storage()?.setItem(TUTORIAL_KEY, '1');
  } catch {
    /* private mode */
  }
}

const root = document.getElementById('table')!;
const q = new URLSearchParams(location.search);
const num = (k: string): number | undefined => (q.has(k) ? Number(q.get(k)) : undefined);

interface Launch {
  players: number;
  myName: string;
  myAvatar: string;
  humour: Humour;
  mode?: SetupChoice['mode'];
  pokerHands?: boolean;
  tutorial?: boolean;
}

function launch(l: Launch): void {
  const mode = l.mode ?? (q.get('mode') === 'fightTillTheEnd' ? 'fightTillTheEnd' : 'standard');
  const pokerHands = l.pokerHands ?? q.get('poker') !== '0';
  const tutorial = l.tutorial ?? (q.get('tutorial') === '0' ? false : q.get('tutorial') === '1' || !tutorialDone());
  const session = startPractice(root, {
    players: Math.max(2, Math.min(8, l.players)),
    myName: l.myName,
    myAvatar: l.myAvatar,
    config: { ...bigtwo.defaultConfig, mode, pokerHands, roundsToPlay: num('rounds') ?? 1 },
    seed: num('seed'),
    fast: q.get('fast') === '1',
    botSpeed: num('speed'),
    turnMs: num('turn'),
    previewMs: num('preview'),
    autoplay: q.get('autoplay') === '1',
    tutorial,
    humour: l.humour,
    settings: { reducedMotion: q.get('reduced') === '1', sound: q.get('mute') !== '1' },
    onTutorialDone: markTutorialDone,
    onChangeRules: () => setup(l),
    onExit: () => {
      if (inApp()) send({ t: 'exit' });
      else location.reload();
    },
  });
  (window as unknown as { __efoc: unknown }).__efoc = { ...session, feel: session.table.feel };
}

/** The setup sheet, then the game. */
function setup(base: Omit<Launch, 'players' | 'humour'> & Partial<Launch>): void {
  showSetup(root, (c) => launch({ myName: base.myName, myAvatar: base.myAvatar, players: c.players, humour: c.humour, mode: c.mode, pokerHands: c.pokerHands, tutorial: false }));
}

startBridge();
const humourParam = (q.get('humour') as Humour | null) ?? 'spicy';

let launched = false;
if (q.has('room') && !inApp()) {
  void launchOnline(root, 'bigtwo');
} else if (inApp()) {
  onMessage((msg) => {
    if (msg.t !== 'init') return;
    if (msg.online) {
      if (!launched) void launchOnline(root, 'bigtwo', msg.online);
      launched = true;
      return;
    }
    if (msg.practice) {
      // Practice vs bots: the first-time tutorial, then the setup sheet.
      if (launched) return;
      launched = true;
      const myName = msg.players[msg.mySeat]?.name ?? 'Player';
      const myAvatar = msg.players[msg.mySeat]?.avatar ?? '😎';
      if (!tutorialDone()) launch({ players: 4, myName, myAvatar, humour: msg.humour ?? 'spicy' });
      else setup({ myName, myAvatar });
    }
  });
} else if (q.has('players') || q.get('tutorial') === '1' || !tutorialDone()) {
  // Tests and the first-time tutorial start straight away.
  launch({ players: num('players') ?? 4, myName: 'Player', myAvatar: '😎', humour: humourParam });
} else {
  setup({ myName: 'Player', myAvatar: '😎' });
}
