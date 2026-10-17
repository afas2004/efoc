// Lucky 7 page entry. Inside the EFOC app it waits for `init` from Flutter;
// opened on its own (dev server, Playwright) it starts Practice from the URL:
//   ?players=4&seed=1&fast=1&speed=0.05&turn=20000&autoplay=1&humour=off|mild|spicy&reduced=1&mute=1
// or an online table on the localStorage store (see net/launch.ts): ?room=...&uid=...

import './styles.css';
import { inApp, onMessage, send, startBridge } from './bridge';
import type { Humour } from './feel/jester';
import { startPractice } from './games/lucky7/practice';
import { launchOnline } from './net/launch';
import { showSetup } from './games/lucky7/setup';

const root = document.getElementById('table')!;
const q = new URLSearchParams(location.search);
const num = (k: string): number | undefined => (q.has(k) ? Number(q.get(k)) : undefined);

function launch(players: number, myName: string, myAvatar: string, humour: Humour): void {
  const session = startPractice(root, {
    players,
    myName,
    myAvatar,
    humour,
    seed: num('seed'),
    fast: q.get('fast') === '1',
    botSpeed: num('speed'),
    turnMs: num('turn'),
    autoplay: q.get('autoplay') === '1',
    settings: { reducedMotion: q.get('reduced') === '1', sound: q.get('mute') !== '1' },
    onExit: () => {
      if (inApp()) send({ t: 'exit' });
      else location.reload();
    },
  });
  (window as unknown as { __efoc: unknown }).__efoc = { ...session, feel: session.table.feel };
}

startBridge();
const humourParam = (q.get('humour') as Humour | null) ?? 'spicy';
let launched = false;

if (q.has('room') && !inApp()) {
  void launchOnline(root, 'lucky7');
} else if (inApp()) {
  onMessage((msg) => {
    if (msg.t !== 'init' || launched) return;
    if (msg.online) {
      launched = true;
      void launchOnline(root, 'lucky7', msg.online);
      return;
    }
    if (msg.practice) {
      launched = true;
      const myName = msg.players[msg.mySeat]?.name ?? 'Player';
      const myAvatar = msg.players[msg.mySeat]?.avatar ?? '😎';
      showSetup(root, (c) => launch(c.players, myName, myAvatar, c.humour));
    }
  });
} else if (q.has('players')) {
  launch(num('players') ?? 4, 'Player', '😎', humourParam);
} else {
  showSetup(root, (c) => launch(c.players, 'Player', '😎', c.humour));
}
