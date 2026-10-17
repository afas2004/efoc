// The waiting room (spec "Waiting room"): the table greyed out with the
// seats filling up. Everyone toggles Ready; the host sets the house rules,
// adds bots to empty seats and taps Start once at least two seats are
// filled and every human is ready.

import { sound, unlockAudio } from '../feel/sound';
import { L, fmt } from '../strings';
import type { Member, RoomMeta, SeatEntry } from './protocol';

export interface LobbyState {
  meta: RoomMeta;
  members: Record<string, Member>;
  online: Set<string>;
  me: string;
}

export interface LobbyActions {
  setReady(ready: boolean): void;
  addBot(): void;
  removeBot(i: number): void;
  setRule(patch: Partial<Pick<RoomMeta, 'mode' | 'pokerHands' | 'humour'>>): void;
  start(): void;
  /** Only inside the EFOC app: share a link to this table. */
  invite?(): void;
}

/** Seats in the order they will sit: humans by join time, then bots. */
export function lobbySeats(meta: RoomMeta, members: Record<string, Member>): SeatEntry[] {
  const humans = Object.entries(members)
    .sort((a, b) => a[1].joinedAt - b[1].joinedAt)
    .map(([uid, m]) => ({ uid, name: m.name, avatar: m.avatar, bot: null }));
  return [...humans, ...(meta.bots ?? [])].slice(0, 8);
}

export function renderLobby(root: HTMLElement, st: LobbyState, act: LobbyActions): void {
  const u = L().ui;
  const isHost = st.meta.hostUid === st.me;
  root.className = 'efoc-root felt-bigtwo';
  let overlay = root.querySelector('.overlay.lobby') as HTMLElement | null;
  if (!overlay) {
    root.innerHTML = '';
    overlay = document.createElement('div');
    overlay.className = 'overlay lobby';
    root.appendChild(overlay);
  }
  overlay.innerHTML = '';
  const sheet = document.createElement('div');
  sheet.className = 'sheet setup-sheet';
  overlay.appendChild(sheet);
  const h = document.createElement('h2');
  h.textContent = `🃏 ${u.setupTitle} · ${u.waitingRoom}`;
  sheet.appendChild(h);

  const seats = lobbySeats(st.meta, st.members);
  const list = document.createElement('ol');
  list.className = 'lobby-seats';
  sheet.appendChild(list);
  seats.forEach((s, i) => {
    const li = document.createElement('li');
    const m = s.uid ? st.members[s.uid] : null;
    const online = s.uid ? st.online.has(s.uid) : true;
    li.className = `lobby-seat${s.bot ? ' bot' : m?.ready ? ' ready' : ''}${online ? '' : ' offline'}`;
    const tags = [
      s.uid === st.meta.hostUid ? u.hostTag : '',
      s.uid === st.me ? u.youTag : '',
      s.bot ? u.botTag : '',
      !online ? u.offline : '',
    ].filter(Boolean);
    li.innerHTML = '<span class="lobby-avatar"></span><span class="lobby-name"></span><span class="lobby-tags"></span><span class="lobby-state"></span>';
    li.querySelector('.lobby-avatar')!.textContent = s.avatar;
    li.querySelector('.lobby-name')!.textContent = s.name;
    li.querySelector('.lobby-tags')!.textContent = tags.join(' · ');
    li.querySelector('.lobby-state')!.textContent = s.bot ? '🤖' : m?.ready ? `✓ ${u.isReady}` : u.notReady;
    if (isHost && s.bot) {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'btn btn-ghost lobby-remove';
      b.textContent = u.removeBot;
      b.addEventListener('click', () => act.removeBot(i - seats.filter((x) => !x.bot).length));
      li.appendChild(b);
    }
    list.appendChild(li);
  });

  const row = document.createElement('div');
  row.className = 'sheet-actions';
  sheet.appendChild(row);
  const btn = (cls: string, text: string, on: () => void, disabled = false): HTMLButtonElement => {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = cls;
    b.textContent = text;
    b.disabled = disabled;
    b.addEventListener('click', () => {
      unlockAudio();
      sound.click();
      on();
    });
    row.appendChild(b);
    return b;
  };
  const meReady = st.members[st.me]?.ready ?? false;
  if (st.members[st.me]) btn(`btn ${meReady ? 'btn-turn' : 'btn-secondary'}`, meReady ? `✓ ${u.isReady}` : u.readyQ, () => act.setReady(!meReady));
  if (isHost) btn('btn btn-secondary', u.addBot, () => act.addBot(), seats.length >= 8);
  if (act.invite) btn('btn btn-secondary btn-invite', u.invite, () => act.invite!());

  // House rules: the host picks, everyone sees them.
  const rules = document.createElement('div');
  rules.className = 'lobby-rules';
  sheet.appendChild(rules);
  const seg = (label: string, items: { text: string; on: boolean; pick: () => void }[]): void => {
    const g = document.createElement('div');
    g.className = 'setup-group';
    g.innerHTML = '<div class="setup-label"></div><div class="segmented"></div>';
    g.firstElementChild!.textContent = label;
    for (const it of items) {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = `seg${it.on ? ' on' : ''}`;
      b.innerHTML = '<b></b>';
      b.firstElementChild!.textContent = it.text;
      b.disabled = !isHost;
      b.addEventListener('click', it.pick);
      g.lastElementChild!.appendChild(b);
    }
    rules.appendChild(g);
  };
  const m = st.meta;
  seg(u.mode, [
    { text: u.modeStandard, on: m.mode === 'standard', pick: () => act.setRule({ mode: 'standard' }) },
    { text: u.modeFtte, on: m.mode === 'fightTillTheEnd', pick: () => act.setRule({ mode: 'fightTillTheEnd' }) },
  ]);
  seg(u.pokerHands, [
    { text: u.on, on: m.pokerHands, pick: () => act.setRule({ pokerHands: true }) },
    { text: u.off, on: !m.pokerHands, pick: () => act.setRule({ pokerHands: false }) },
  ]);
  seg(u.humour, (['off', 'mild', 'spicy'] as const).map((hm) => ({
    text: { off: u.humourOff, mild: u.humourMild, spicy: u.humourSpicy }[hm],
    on: m.humour === hm,
    pick: () => act.setRule({ humour: hm }),
  })));

  const humansReady = seats.filter((s) => !s.bot).every((s) => st.members[s.uid!]?.ready);
  const canStart = seats.length >= 2 && humansReady;
  if (isHost) {
    const start = document.createElement('button');
    start.type = 'button';
    start.className = 'btn btn-primary btn-start';
    start.textContent = canStart ? u.startGame : seats.length < 2 ? u.needPlayers : u.needReady;
    start.disabled = !canStart;
    start.addEventListener('click', () => {
      unlockAudio();
      act.start();
    });
    sheet.appendChild(start);
  } else {
    const p = document.createElement('p');
    p.className = 'lobby-wait';
    p.textContent = u.waitingHost;
    sheet.appendChild(p);
  }
  const count = document.createElement('p');
  count.className = 'lobby-wait';
  count.textContent = fmt(u.onlineCount, { n: seats.length });
  sheet.appendChild(count);
}
