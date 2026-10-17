// Not a gate: takes screenshots of key table states for a human to review.
// Run with SHOTS=<dir> npx playwright test shots
import { expect, test } from '@playwright/test';

const dir = process.env.SHOTS;
test.skip(!dir, 'set SHOTS=<dir> to take review screenshots');
test.use({ viewport: { width: 390, height: 844 } });

test('review screenshots', async ({ page }) => {
  await page.goto('/bigtwo/?players=4&seed=21&tutorial=0&mute=1&speed=0.3');
  await expect.poll(() => page.evaluate(() => (window as any).__efoc.table.view?.turn), { timeout: 20_000 }).toBe(0);
  await page.waitForTimeout(900);
  await page.screenshot({ path: `${dir}/1-your-turn.png` });

  // Let a few plays happen so the history strip fills, then catch someone else's turn.
  await page.evaluate(() => {
    const { host } = (window as any).__efoc;
    const m = host.game.legalMoves(host.state, 0).find((x: any) => x.type === 'play');
    (window as any).__efoc.table.hooks.move(m);
  });
  await page.waitForTimeout(4000);
  await page.screenshot({ path: `${dir}/2-history-waiting.png` });

  // The unstoppable moment, as if a player just played 2♠ with two cards left.
  await page.evaluate(() => {
    const t = (window as any).__efoc.table;
    t.moment({ type: 'unbeatable', seat: 1, kind: 'single', cards: ['2s'], left: 1, passed: [0, 2, 3] }, t.view);
    t.moment({ type: 'jester', key: 'unstoppable', idx: 0, target: 1, vars: { name: 'Speedy', combo: 'a single 2♠' }, mood: 'shock', emoji: 'scream' }, t.view);
  });
  await page.waitForTimeout(650);
  await page.screenshot({ path: `${dir}/3-unstoppable.png` });

  await page.waitForTimeout(2500);
  await page.getByRole('button', { name: 'Menu' }).click();
  await page.waitForTimeout(300);
  await page.screenshot({ path: `${dir}/4-menu.png` });
});
