// Feel gate: each tier stays inside its time budget, one T3 at a time,
// the reduced-motion path, and input is never blocked for over 1.5 s.

import { expect, test, type Page } from '@playwright/test';

const BUDGET: Record<number, number> = { 0: 150, 1: 300, 2: 700, 3: 1500, 4: 4000 };
const SLACK = 60; // timer jitter in a busy test browser

test.use({ viewport: { width: 360, height: 780 } });

type Rec = { tier: number; name: string; start: number; end: number | null; skipped: boolean };

const feelLog = (page: Page) => page.evaluate(() => (window as any).__efoc.feel.log as Rec[]);

/** Fires a table moment as if the engine emitted it. */
const fire = (page: Page, event: Record<string, unknown>) =>
  page.evaluate((e) => {
    const t = (window as any).__efoc.table;
    t.moment(e, t.view);
  }, event);

test('every moment stays inside its tier budget over a full match', async ({ page }) => {
  await page.goto('/bigtwo/?players=4&seed=5&tutorial=0&autoplay=1&speed=0.05&mute=1');
  await expect(page.locator('.overlay.results')).toBeVisible({ timeout: 60_000 });
  await page.waitForTimeout(BUDGET[4] + 200);
  const log = await feelLog(page);
  expect(log.length).toBeGreaterThan(10);
  for (const r of log) {
    expect(r.end, `${r.name} finished`).not.toBeNull();
    expect(r.end! - r.start, `${r.name} (T${r.tier})`).toBeLessThanOrEqual(BUDGET[r.tier]! + SLACK);
  }
  const tiers = new Set(log.map((r) => r.tier));
  expect(tiers.has(1) && tiers.has(4)).toBe(true);
});

test('one T3 at a time: the rest queue', async ({ page }) => {
  await page.goto('/bigtwo/?players=4&seed=5&tutorial=0&mute=1');
  await expect(page.locator('.seat')).toHaveCount(3);
  for (let i = 0; i < 3; i++) await fire(page, { type: 'bomb', seat: 1, kind: 'fourkind' });
  await page.waitForTimeout(3 * BUDGET[3] + 400);
  const bigs = (await feelLog(page)).filter((r) => r.tier === 3);
  expect(bigs).toHaveLength(3);
  for (let i = 1; i < bigs.length; i++) {
    expect(bigs[i]!.start, 'next T3 starts after the previous one ends').toBeGreaterThanOrEqual(bigs[i - 1]!.end! - 1);
  }
  for (const b of bigs) expect(b.end! - b.start).toBeLessThanOrEqual(BUDGET[3] + SLACK);
});

test('input is never blocked by a T3, and a tap skips it', async ({ page }) => {
  await page.goto('/bigtwo/?players=4&seed=5&tutorial=0&mute=1');
  const card = page.locator('.card.in-hand').first();
  await expect(card).toBeVisible();
  await page.waitForTimeout(500);
  await fire(page, { type: 'bomb', seat: 1, kind: 'fourkind' });
  await expect(page.locator('.fx-banner')).toBeVisible();
  // The dimmer is on screen, but the card under it still takes the tap at once.
  const t0 = Date.now();
  await card.click();
  await expect(card).toHaveClass(/selected/);
  expect(Date.now() - t0).toBeLessThan(1500);
  const big = (await feelLog(page)).find((r) => r.tier === 3)!;
  expect(big.skipped).toBe(true);
  expect(big.end! - big.start).toBeLessThan(BUDGET[3]);
  await expect(page.locator('.fx-banner')).toHaveCount(0);
});

test('reduced motion keeps text and drops motion', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.goto('/bigtwo/?players=4&seed=5&tutorial=0&mute=1');
  await expect(page.locator('.efoc-root.reduced-motion')).toHaveCount(1);
  const transition = await page.locator('.card').first().evaluate((c) => getComputedStyle(c).transitionProperty);
  expect(transition).not.toContain('transform');
  await fire(page, { type: 'bomb', seat: 1, kind: 'fourkind' });
  await expect(page.locator('.fx-banner')).toHaveText('BOMB!');
  await expect(page.locator('.fx-particle')).toHaveCount(0);
});

test('select, play and the host confirms; Pass only when following', async ({ page }) => {
  await page.goto('/bigtwo/?players=2&seed=8&tutorial=0&speed=0.05&mute=1');
  // Wait for my turn.
  await expect.poll(() => page.evaluate(() => (window as any).__efoc.table.view?.turn), { timeout: 15_000 }).toBe(0);
  const move = await page.evaluate(() => {
    const { host } = (window as any).__efoc;
    const moves = host.game.legalMoves(host.state, 0).filter((m: any) => m.type === 'play');
    return moves.sort((a: any, b: any) => a.cards.length - b.cards.length)[0].cards as string[];
  });
  const lead = await page.evaluate(() => (window as any).__efoc.table.view.lead);
  await expect(page.getByRole('button', { name: 'Pass' })).toBeEnabled({ enabled: lead !== null });
  const play = page.locator('.action-bar .btn-primary');
  await expect(play).toBeDisabled();
  for (const c of move) await page.locator(`.card.in-hand[data-card="${c}"]`).click();
  await expect(play).toBeEnabled();
  await play.click();
  for (const c of move) await expect(page.locator(`.card.in-hand[data-card="${c}"]`)).toHaveCount(0);
  const pile = await page.evaluate(() => (window as any).__efoc.table.view.pile as string[]);
  for (const c of move) expect(pile).toContain(c);
});

test('a rejected move snaps back with the reason', async ({ page }) => {
  await page.goto('/bigtwo/?players=4&seed=5&tutorial=0&mute=1');
  await expect(page.locator('.card.in-hand')).toHaveCount(13);
  await page.evaluate(() => {
    const t = (window as any).__efoc.table;
    t.pending = t.view.hand.slice(0, 1);
    t.render();
    t.reject('Not your turn');
  });
  await expect(page.locator('.fx-pop', { hasText: 'Not your turn' })).toBeVisible();
  await expect(page.locator('.card.in-hand')).toHaveCount(13);
});

test('cards and actions have spoken labels', async ({ page }) => {
  await page.goto('/bigtwo/?players=4&seed=5&tutorial=0&mute=1');
  const first = page.locator('.card.in-hand').first();
  await expect(first).toHaveAttribute('aria-label', /^(Three|Four|Five|Six|Seven|Eight|Nine|Ten|Jack|Queen|King|Ace|Two) of (diamonds|clubs|hearts|spades)$/);
  await first.click();
  await expect(first).toHaveAttribute('aria-label', /, selected$/);
  for (const name of ['Menu', 'Sort', 'Pass', 'Play']) await expect(page.getByRole('button', { name, exact: true })).toHaveCount(1);
});

test('the first visit runs the tutorial; Play again starts a new match', async ({ page }) => {
  await page.goto('/bigtwo/?mute=1&speed=0.05');
  await expect(page.locator('.tip')).toContainText('3♦');
  await expect(page.locator('.seat')).toHaveCount(3);
  await page.getByRole('button', { name: 'Skip tutorial' }).click();
  await expect(page.locator('.tip')).toBeHidden();
  expect(await page.evaluate(() => localStorage.getItem('efoc.tutorial.bigtwo'))).toBe('1');

  await page.goto('/bigtwo/?players=3&seed=4&tutorial=0&autoplay=1&speed=0.05&mute=1');
  await expect(page.locator('.overlay.results')).toBeVisible({ timeout: 60_000 });
  await page.getByRole('button', { name: 'Play again' }).click();
  await expect(page.locator('.overlay.results')).toBeHidden();
  await expect(page.locator('.card.in-hand')).not.toHaveCount(0);
});
