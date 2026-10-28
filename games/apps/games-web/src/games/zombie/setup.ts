// The setup sheet before a Zombie Practice game: players and humour,
// remembered on this device.

import type { Humour } from '../../feel/jester';
import { sound, unlockAudio } from '../../feel/sound';
import { L } from '../../strings';

export interface SetupChoice {
  players: number;
  humour: Humour;
}

const KEY = 'efoc.zombie.setup';

function loadChoice(): SetupChoice {
  const fallback: SetupChoice = { players: 4, humour: 'spicy' };
  try {
    return { ...fallback, ...(JSON.parse(localStorage.getItem(KEY) ?? '{}') as Partial<SetupChoice>) };
  } catch {
    return fallback;
  }
}

export function showSetup(root: HTMLElement, onStart: (c: SetupChoice) => void): void {
  const u = L().ui;
  const choice = loadChoice();
  root.innerHTML = '';
  root.className = 'efoc-root felt-zombie';
  const overlay = document.createElement('div');
  overlay.className = 'overlay setup';
  root.appendChild(overlay);
  const sheet = document.createElement('div');
  sheet.className = 'sheet setup-sheet';
  overlay.appendChild(sheet);

  const render = (): void => {
    sheet.innerHTML = '';
    const h = document.createElement('h2');
    h.textContent = `🧟 ${L().zb.title} · ${u.practice}`;
    sheet.appendChild(h);
    const hint = document.createElement('p');
    hint.className = 'lobby-wait';
    hint.textContent = L().zb.setupHint;
    sheet.appendChild(hint);
    const group = (label: string, items: { label: string; on: boolean; pick: () => void }[], cls = ''): void => {
      const g = document.createElement('div');
      g.className = 'setup-group';
      const l = document.createElement('div');
      l.className = 'setup-label';
      l.textContent = label;
      g.appendChild(l);
      const row = document.createElement('div');
      row.className = `segmented ${cls}`;
      for (const it of items) {
        const b = document.createElement('button');
        b.type = 'button';
        b.className = `seg${it.on ? ' on' : ''}`;
        b.setAttribute('aria-pressed', String(it.on));
        b.innerHTML = '<b></b>';
        b.firstElementChild!.textContent = it.label;
        b.addEventListener('click', () => {
          unlockAudio();
          sound.click();
          it.pick();
          render();
        });
        row.appendChild(b);
      }
      g.appendChild(row);
      sheet.appendChild(g);
    };
    group(u.players, [2, 3, 4, 5, 6, 7, 8].map((n) => ({ label: String(n), on: choice.players === n, pick: () => (choice.players = n) })), 'players');
    group(u.humour, (['off', 'mild', 'spicy'] as Humour[]).map((h) => ({
      label: { off: u.humourOff, mild: u.humourMild, spicy: u.humourSpicy }[h],
      on: choice.humour === h,
      pick: () => (choice.humour = h),
    })));
    const start = document.createElement('button');
    start.type = 'button';
    start.className = 'btn btn-primary btn-start';
    start.textContent = u.start;
    start.addEventListener('click', () => {
      unlockAudio();
      try {
        localStorage.setItem(KEY, JSON.stringify(choice));
      } catch {
        /* private mode */
      }
      onStart({ ...choice });
    });
    sheet.appendChild(start);
  };
  render();
}
