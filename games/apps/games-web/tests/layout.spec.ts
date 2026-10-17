// Layout gate: a full match at five screen sizes and 2, 4 and 8 seats,
// with no overlap and touch targets of at least 44 px.

import { expect, test, type Page } from '@playwright/test';

const SIZES = [
  { name: 'small phone', width: 360, height: 780 },
  { name: 'iPhone', width: 390, height: 844 },
  { name: 'large phone', width: 412, height: 915 },
  { name: 'tablet', width: 768, height: 1024 },
  { name: 'landscape phone', width: 844, height: 390 },
];
const PLAYERS = [2, 4, 8];
const MIN = 44;

interface Problem {
  problems: string[];
}

/** Measures the table once and returns anything that breaks the layout rules. */
async function check(page: Page): Promise<Problem> {
  return page.evaluate((MIN) => {
    const problems: string[] = [];
    // Screen shake moves the whole table on purpose; measure between shakes.
    if ((document.querySelector('.table') as HTMLElement).getAnimations().length > 0) return { problems };
    const vw = window.innerWidth;
    const vh = window.innerHeight;
    const box = (el: Element) => el.getBoundingClientRect();
    const hit = (a: DOMRect, b: DOMRect) => a.left < b.right - 0.5 && b.left < a.right - 0.5 && a.top < b.bottom - 0.5 && b.top < a.bottom - 0.5;
    const inside = (r: DOMRect) => r.left >= -0.5 && r.top >= -0.5 && r.right <= vw + 0.5 && r.bottom <= vh + 0.5;
    const settled = (el: Element) => (el as HTMLElement).getAnimations().length === 0;

    const seats = [...document.querySelectorAll('.seat')].map(box);
    const bar = document.querySelector('.action-bar')!;
    const barBox = box(bar);
    const timer = box(document.querySelector('.timer-bar')!);
    const hand = [...document.querySelectorAll('.card.in-hand')].filter(settled) as HTMLElement[];
    const handBoxes = hand.map(box);
    const table = [...document.querySelectorAll('.card:not(.in-hand)')].filter(
      (c) => settled(c) && Number(getComputedStyle(c).opacity) > 0.9,
    );

    seats.forEach((s, i) => {
      if (!inside(s)) problems.push(`seat ${i} is off screen`);
      seats.forEach((t, j) => j > i && hit(s, t) && problems.push(`seats ${i} and ${j} overlap`));
      if (hit(s, barBox)) problems.push(`seat ${i} overlaps the action bar`);
      if (hit(s, timer)) problems.push(`seat ${i} overlaps the timer`);
      handBoxes.forEach((h, k) => hit(s, h) && problems.push(`seat ${i} overlaps hand card ${k}`));
      table.forEach((c) => hit(s, box(c)) && problems.push(`seat ${i} overlaps table card ${(c as HTMLElement).dataset.card}`));
    });
    const chip = document.querySelector('.turn-chip:not(.hidden)');
    if (chip) {
      const cb = box(chip);
      seats.forEach((s, i) => hit(s, cb) && problems.push(`seat ${i} overlaps the turn chip`));
      if (hit(cb, barBox)) problems.push('turn chip overlaps the action bar');
      if (!inside(cb)) problems.push('turn chip is off screen');
    }
    handBoxes.forEach((h, k) => {
      if (!inside(h)) problems.push(`hand card ${k} is off screen`);
      if (hit(h, barBox)) problems.push(`hand card ${k} overlaps the action bar`);
    });
    if (!inside(barBox)) problems.push('action bar is off screen');
    for (const b of bar.querySelectorAll('button')) {
      const r = box(b);
      if (getComputedStyle(b).display === 'none') continue;
      if (r.width < MIN || r.height < MIN) problems.push(`button "${b.textContent}" is ${r.width.toFixed(0)}×${r.height.toFixed(0)}`);
    }
    // Every hand card keeps a touch strip of at least 44 px: the part of it
    // that no later card covers.
    // Group cards into rows: a new row starts more than 20 px below the last.
    const rows = new Map<number, DOMRect[]>();
    let rowTop = -Infinity;
    for (const h of [...handBoxes].sort((a, b) => a.top - b.top)) {
      if (h.top - rowTop > 20) rowTop = h.top;
      rows.set(rowTop, [...(rows.get(rowTop) ?? []), h]);
    }
    const rowKeys = [...rows.keys()].sort((a, b) => a - b);
    rowKeys.forEach((k, ri) => {
      const row = rows.get(k)!.sort((a, b) => a.left - b.left);
      row.forEach((r, i) => {
        const next = row[i + 1];
        const w = next ? next.left - r.left : r.width;
        if (w < MIN - 1) problems.push(`hand card strip is ${w.toFixed(1)} px wide`);
        // Back rows are covered from below by the front row.
        const front = rows.get(rowKeys[ri + 1]!);
        if (front) {
          const h = front[0]!.top - r.top;
          if (h < MIN - 1) problems.push(`back-row card strip is ${h.toFixed(1)} px tall`);
        }
      });
    });
    return { problems };
  }, MIN);
}

for (const size of SIZES) {
  for (const players of PLAYERS) {
    test(`${size.name} ${size.width}×${size.height}, ${players} players: full match, no overlap, 44 px targets`, async ({ page }) => {
      await page.setViewportSize({ width: size.width, height: size.height });
      await page.goto(`/bigtwo/?players=${players}&seed=${players * 11}&tutorial=0&autoplay=1&speed=${players === 2 ? 0.4 : 0.15}&mute=1`);
      await expect(page.locator('.seat')).toHaveCount(players - 1);
      const seen = new Set<string>();
      let samples = 0;
      // Sample the layout through the match until results show.
      while (!(await page.locator('.overlay.results').isVisible())) {
        const { problems } = await check(page);
        problems.forEach((p) => seen.add(p));
        samples++;
        await page.waitForTimeout(150);
        if (samples > 600) break;
      }
      await expect(page.locator('.overlay.results')).toBeVisible();
      await expect(page.locator('.standing')).toHaveCount(players);
      for (const b of await page.locator('.overlay.results button').all()) {
        const r = (await b.boundingBox())!;
        expect(r.height, 'results buttons are 44 px tall').toBeGreaterThanOrEqual(MIN);
      }
      expect([...seen], `layout problems over ${samples} samples`).toEqual([]);
      expect(samples).toBeGreaterThan(2);
    });
  }
}
