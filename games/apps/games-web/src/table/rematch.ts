// "Who's in for another?" on the results screen of an online table. Each
// player taps "I'm in"; the host sees who is in, still deciding, or gone,
// before tapping Play again (seats of people who left are played by bots).

import { sound, unlockAudio } from '../feel/sound';
import { L } from '../strings';

export interface RematchRow {
  name: string;
  avatar: string;
  state: 'in' | 'waiting' | 'left';
}

export interface RematchInfo {
  /** Everyone else at the table (humans only). */
  rows: RematchRow[];
  isHost: boolean;
  /** Have I said I'm in? */
  mineIn: boolean;
  onIn(): void;
}

export function renderRematch(box: HTMLElement, info: RematchInfo | null): void {
  box.innerHTML = '';
  box.classList.toggle('hidden', !info);
  if (!info) return;
  const u = L().ui;
  if (!info.isHost) {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = `btn ${info.mineIn ? 'btn-turn' : 'btn-primary'} btn-im-in`;
    b.textContent = info.mineIn ? u.waitingAgain : u.imIn;
    b.disabled = info.mineIn;
    b.addEventListener('click', () => {
      unlockAudio();
      sound.click();
      info.onIn();
    });
    box.appendChild(b);
  }
  if (!info.rows.length) return;
  const h = document.createElement('div');
  h.className = 'setup-label';
  h.textContent = u.whosIn;
  box.appendChild(h);
  const list = document.createElement('div');
  list.className = 'rematch-list';
  for (const r of info.rows) {
    const chip = document.createElement('span');
    chip.className = `rematch-chip ${r.state}`;
    chip.textContent = `${r.avatar} ${r.name.slice(0, 10)} ${r.state === 'in' ? u.againReady : r.state === 'left' ? u.againLeft : u.againWaiting}`;
    list.appendChild(chip);
  }
  box.appendChild(list);
}
