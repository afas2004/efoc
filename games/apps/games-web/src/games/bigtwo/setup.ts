// The setup sheet before a Practice game: players, mode, poker hands and
// humour. The last choices are remembered on this device.

import type { Humour } from '../../feel/jester';
import { sound, unlockAudio } from '../../feel/sound';
import { L } from '../../strings';

export interface SetupChoice {
  players: number;
  mode: 'standard' | 'fightTillTheEnd';
  pokerHands: boolean;
  humour: Humour;
}

const KEY = 'efoc.bigtwo.setup';

export function loadChoice(): SetupChoice {
  const fallback: SetupChoice = { players: 4, mode: 'standard', pokerHands: true, humour: 'spicy' };
  try {
    return { ...fallback, ...(JSON.parse(localStorage.getItem(KEY) ?? '{}') as Partial<SetupChoice>) };
  } catch {
    return fallback;
  }
}

function saveChoice(c: SetupChoice): void {
  try {
    localStorage.setItem(KEY, JSON.stringify(c));
  } catch {
    /* private mode */
  }
}

export function showSetup(root: HTMLElement, onStart: (c: SetupChoice) => void): void {
  const u = L().ui;
  const choice = loadChoice();
  root.innerHTML = '';
  root.className = 'efoc-root felt-bigtwo';
  const overlay = document.createElement('div');
  overlay.className = 'overlay setup';
  root.appendChild(overlay);
  const sheet = document.createElement('div');
  sheet.className = 'sheet setup-sheet';
  overlay.appendChild(sheet);

  const render = (): void => {
    sheet.innerHTML = '';
    const h = document.createElement('h2');
    h.textContent = `🃏 ${u.setupTitle} · ${u.practice}`;
    sheet.appendChild(h);

    const group = (label: string): HTMLElement => {
      const g = document.createElement('div');
      g.className = 'setup-group';
      const l = document.createElement('div');
      l.className = 'setup-label';
      l.textContent = label;
      g.appendChild(l);
      sheet.appendChild(g);
      return g;
    };
    const seg = (parent: HTMLElement, items: { label: string; on: boolean; pick: () => void; hint?: string }[], cls = ''): void => {
      const row = document.createElement('div');
      row.className = `segmented ${cls}`;
      for (const it of items) {
        const b = document.createElement('button');
        b.type = 'button';
        b.className = `seg${it.on ? ' on' : ''}`;
        b.setAttribute('aria-pressed', String(it.on));
        b.innerHTML = '<b></b>';
        b.firstElementChild!.textContent = it.label;
        if (it.hint) {
          const s = document.createElement('small');
          s.textContent = it.hint;
          b.appendChild(s);
        }
        b.addEventListener('click', () => {
          unlockAudio();
          sound.click();
          it.pick();
          render();
        });
        row.appendChild(b);
      }
      parent.appendChild(row);
    };

    seg(group(u.players), [2, 3, 4, 5, 6, 7, 8].map((n) => ({ label: String(n), on: choice.players === n, pick: () => (choice.players = n) })), 'players');
    seg(
      group(u.mode),
      [
        { label: u.modeStandard, hint: u.modeStandardHint, on: choice.mode === 'standard', pick: () => (choice.mode = 'standard') },
        { label: u.modeFtte, hint: u.modeFtteHint, on: choice.mode === 'fightTillTheEnd', pick: () => (choice.mode = 'fightTillTheEnd') },
      ],
      'modes',
    );
    seg(
      group(u.pokerHands),
      [
        { label: u.on, hint: u.pokerHandsHint, on: choice.pokerHands, pick: () => (choice.pokerHands = true) },
        { label: u.off, on: !choice.pokerHands, pick: () => (choice.pokerHands = false) },
      ],
      'modes',
    );
    seg(group(u.humour), (['off', 'mild', 'spicy'] as Humour[]).map((h) => ({
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
      saveChoice(choice);
      onStart({ ...choice });
    });
    sheet.appendChild(start);
  };
  render();
}
