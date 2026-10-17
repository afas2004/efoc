// Starts an online table, for any game page.
//   Plain browser (development, multi-player tests): the localStorage room
//   store, from the URL:
//     ?room=r1&uid=u1&name=Ali&create=1&allowed=u1,u2,u3&turn=20000&migrate=60000&preview=15000&autopilot=1
//   Inside EFOC: the bridge store; the app sends `init` with `online` and
//   proxies every database call (net/bridgeStore.ts).

import type { ToGame } from '../bridge';
import type { OnlineGameId } from './netGame';
import type { RoomStore } from './store';

export type AppOnline = NonNullable<Extract<ToGame, { t: 'init' }>['online']>;

export async function launchOnline(root: HTMLElement, gameId: OnlineGameId, app?: AppOnline): Promise<void> {
  const q = new URLSearchParams(location.search);
  const num = (k: string): number | undefined => (q.has(k) ? Number(q.get(k)) : undefined);
  const { OnlineGame, createRoom, exitApp } = await import('./room');
  let store: RoomStore;
  let me: { uid: string; name: string; avatar: string };
  let room: string;
  let create: { groupId: string; allowed: string[] } | undefined;
  if (app) {
    const { BridgeStore } = await import('./bridgeStore');
    me = { uid: app.uid, name: app.name, avatar: app.avatar };
    room = app.room;
    store = new BridgeStore(app.uid, app.clockOffset ?? 0);
    create = app.create;
  } else {
    const { LocalStore } = await import('./store');
    const uid = q.get('uid') ?? `u${Math.floor(Math.random() * 1e6)}`;
    me = { uid, name: q.get('name') ?? uid, avatar: q.get('avatar') ?? '😎' };
    room = q.get('room')!;
    store = new LocalStore(uid);
    if (q.get('create') === '1') create = { groupId: q.get('group') ?? 'dev', allowed: (q.get('allowed') ?? uid).split(',') };
  }
  if (create) {
    try {
      await createRoom(store, room, me, {
        gameId,
        groupId: create.groupId,
        allowed: create.allowed,
        turnMs: num('turn'),
        migrateAfterMs: num('migrate'),
        previewMs: num('preview'),
      });
    } catch {
      // Already created (the host reopened the page): just join it.
    }
  }
  const game = new OnlineGame(store, room, me, root, { gameId, autopilot: q.get('autopilot') === '1', botSpeed: num('speed'), onExit: exitApp });
  (window as unknown as { __room: unknown }).__room = game;
  await game.start();
}
