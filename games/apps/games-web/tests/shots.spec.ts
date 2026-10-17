// Not a gate: takes screenshots of key table states for a human to review.
// Run with SHOTS=<dir> npx playwright test shots
import { expect, test } from '@playwright/test';

const dir = process.env.SHOTS;
test.skip(!dir, 'set SHOTS=<dir> to take review screenshots');
test.use({ viewport: { width: 390, height: 844 } });

test('review: countdown, turn, history, menu', async ({ page }) => {
  await page.goto('/bigtwo/?preview=5000&players=4&seed=21&tutorial=0&mute=1&speed=0.3');
  await page.waitForTimeout(1600);
  await page.screenshot({ path: `${dir}/0-countdown.png` });
  await expect.poll(() => page.evaluate(() => (window as any).__efoc.table.view?.turn), { timeout: 20_000 }).toBe(0);
  await page.waitForTimeout(5000);
  await page.screenshot({ path: `${dir}/1-your-turn.png` });
  await page.evaluate(() => {
    const { host } = (window as any).__efoc;
    const m = host.game.legalMoves(host.state, 0).find((x: any) => x.type === 'play');
    (window as any).__efoc.table.hooks.move(m);
  });
  await page.waitForTimeout(4000);
  await page.screenshot({ path: `${dir}/2-history-waiting.png` });
});

test('review: the 2♠ arrives', async ({ page }) => {
  await page.goto('/bigtwo/?preview=0&players=4&seed=21&tutorial=0&mute=1&speed=50');
  await page.waitForTimeout(1200);
  // Speedy (seat 1) throws the 2♠ with one card left, through the real host path:
  // give seat 1 the turn, a 2♠ and one other card, then let the engine apply it.
  await page.evaluate(() => {
    const { host } = (window as any).__efoc;
    const s = host.state;
    const owner = s.hands.findIndex((h: string[]) => h.includes('2s'));
    s.hands[owner] = s.hands[owner].filter((c: string) => c !== '2s');
    const spare = s.hands[1].pop();
    s.hands[owner].push(spare);
    s.hands[1] = ['2s', s.hands[1][0]];
    s.out.push(...s.hands[1].slice(2));
    s.turn = 1;
    s.mustInclude = null;
    s.lead = null;
    host.submit(1, { type: 'play', cards: ['2s'] });
  });
  const t0 = Date.now();
  for (const [ms, name] of [[300, '3a-throw'], [750, '3b-apex'], [1300, '3c-impact'], [2300, '3d-announce'], [4600, '3e-landed']] as const) {
    await page.waitForTimeout(Math.max(0, ms - (Date.now() - t0)));
    await page.screenshot({ path: `${dir}/${name}.png` });
  }
});

test('review: pedestal', async ({ page }) => {
  await page.goto('/bigtwo/?preview=0&players=5&seed=4&tutorial=0&autoplay=1&speed=0.05&mute=1');
  await expect(page.locator('.overlay.results')).toBeVisible({ timeout: 60_000 });
  await page.waitForTimeout(1600);
  await page.screenshot({ path: `${dir}/5-pedestal.png`, fullPage: true });
});
