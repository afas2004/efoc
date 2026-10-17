// Lucky 7 Practice: a full game against bots, the layout at phone sizes,
// and every way of picking a target (your slot, a seat's focus sheet).
import { expect, test, type Page } from '@playwright/test';

const errorsOf = (page: Page): string[] => {
  const errs: string[] = [];
  page.on('pageerror', (e) => errs.push(String(e)));
  page.on('console', (m) => m.type() === 'error' && errs.push(m.text()));
  return errs;
};

/** Puts `card` on top of the centre deck (the host lives in the page). */
async function stackDeck(page: Page, card: string): Promise<void> {
  await page.evaluate((card) => {
    const host = (window as any).__efoc.host;
    const s = host.state;
    const deck = s.deck.filter((c: string) => c !== card);
    let found = deck.length !== s.deck.length;
    // Not in the deck (dealt or gone)? Swap it with the top card wherever it is.
    const slots = s.slots.map((r: string[]) => r.slice());
    if (!found) {
      for (const row of slots) for (let i = 0; i < row.length; i++) if (row[i] === card) {
        row[i] = s.deck[s.deck.length - 1];
        deck.splice(deck.indexOf(row[i]), 1);
        found = true;
      }
    }
    host.state = { ...s, slots, deck: [...deck, card] };
  }, card);
}

for (const players of [2, 4, 8]) {
  test(`${players} players on a small phone: seats, piles and my slots don't overlap`, async ({ page }) => {
    await page.setViewportSize({ width: 360, height: 780 });
    const errs = errorsOf(page);
    await page.goto(`/lucky7/?players=${players}&seed=4&mute=1&turn=60000`);
    await expect(page.locator('.l7-slot')).toHaveCount(3);
    await expect(page.locator('.l7-seat')).toHaveCount(players - 1);
    const boxes = await page.evaluate(() => {
      const r = (el: Element) => el.getBoundingClientRect();
      return {
        seats: [...document.querySelectorAll('.l7-seat')].map(r),
        piles: r(document.querySelector('.l7-piles')!),
        mine: [...document.querySelectorAll('.l7-slot')].map(r),
        bar: r(document.querySelector('.action-bar')!),
      };
    });
    const hit = (a: DOMRect, b: DOMRect) => a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom;
    const all = [...boxes.seats, boxes.piles, ...boxes.mine];
    for (let i = 0; i < all.length; i++) for (let j = i + 1; j < all.length; j++) expect(hit(all[i]!, all[j]!), `boxes ${i} and ${j}`).toBe(false);
    for (const b of all) {
      expect(b.left).toBeGreaterThanOrEqual(0);
      expect(b.right).toBeLessThanOrEqual(360);
      expect(b.bottom).toBeLessThanOrEqual(boxes.bar.top);
    }
    for (const s of boxes.mine) expect(s.width).toBeGreaterThanOrEqual(44);
    expect(errs).toEqual([]);
  });
}

test('a whole game against bots ends with everyone revealed, lowest first', async ({ page }) => {
  const errs = errorsOf(page);
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/lucky7/?players=4&seed=11&mute=1&autoplay=1&speed=0.02&turn=4000&reduced=1');
  await expect(page.locator('.overlay.results')).toBeVisible({ timeout: 90_000 });
  await expect(page.locator('.l7-standings .standing')).toHaveCount(4);
  await expect(page.locator('.l7-res-cards').first().locator('.card')).toHaveCount(3);
  const totals = await page.locator('.l7-standings .standing .pts').allTextContents();
  const nums = totals.map((t) => Number(t.replace(/\D/g, '')));
  expect(nums).toEqual(nums.slice().sort((a, b) => a - b));
  expect(errs).toEqual([]);
});

test('my turn: draw, then swap into a slot; the old card goes face up on Discard', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/lucky7/?players=3&seed=5&mute=1&turn=60000&speed=0.05');
  await expect(page.locator('.l7-prompt')).toHaveText(/Your turn/);
  await page.getByRole('button', { name: 'Draw', exact: true }).click();
  await expect(page.locator('.l7-drawn .card')).toBeVisible();
  await page.getByRole('button', { name: 'Swap in' }).click();
  await expect(page.locator('.l7-slot.pickable')).toHaveCount(3);
  const before = await page.evaluate(() => (window as any).__efoc.host.state.slots[0][1]);
  await page.locator('.l7-slot').nth(1).click();
  await expect(page.locator('.l7-discard .card')).toHaveAttribute('data-card', before);
  await expect(page.locator('.l7-prompt')).toHaveText(/turn…/);
});

test('Q: pick my card, then a player, then their card in the focus sheet', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/lucky7/?players=4&seed=6&mute=1&turn=60000&speed=0.05');
  await expect(page.locator('.l7-prompt')).toHaveText(/Your turn/);
  await stackDeck(page, 'Qc');
  await page.getByRole('button', { name: 'Draw', exact: true }).click();
  await expect(page.locator('.l7-power-tag')).toContainText('Swap');
  await page.getByRole('button', { name: /Use/ }).click();
  await page.locator('.l7-slot').nth(0).click();
  await expect(page.locator('.l7-slot.selected')).toHaveCount(1);
  await expect(page.locator('.l7-seat.pickable')).toHaveCount(3);
  const mine = await page.evaluate(() => (window as any).__efoc.host.state.slots[0][0]);
  const seat = Number(await page.locator('.l7-seat.pickable').first().getAttribute('data-seat'));
  const theirs = await page.evaluate((seat) => (window as any).__efoc.host.state.slots[seat][2], seat);
  await page.locator('.l7-seat.pickable').first().click();
  await expect(page.locator('.l7-focus-sheet')).toBeVisible();
  await page.locator('.l7-focus-slots .l7-slot').nth(2).click();
  await expect(page.locator('.l7-focus-sheet')).toBeHidden();
  const after = await page.evaluate((seat) => [(window as any).__efoc.host.state.slots[0][0], (window as any).__efoc.host.state.slots[seat][2]], seat);
  expect(after).toEqual([theirs, mine]);
});

test('K locks a card (padlock everywhere); J then shows my own cards except the locked one', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/lucky7/?players=2&seed=7&mute=1&turn=60000&speed=0.05');
  await stackDeck(page, 'Kc');
  await page.getByRole('button', { name: 'Draw', exact: true }).click();
  await page.getByRole('button', { name: /Use/ }).click();
  await page.locator('.l7-slot').nth(1).click(); // lock my own slot 2
  await expect(page.locator('.l7-slot').nth(1).locator('.l7-lock')).toBeVisible();
  // The bot moves; my turn again.
  await expect(page.locator('.l7-prompt')).toHaveText(/Your turn/, { timeout: 15_000 });
  await stackDeck(page, 'Jc');
  await page.getByRole('button', { name: 'Draw', exact: true }).click();
  await page.getByRole('button', { name: /Use/ }).click();
  // Own cards face up, except the locked one.
  await expect(page.locator('.l7-mine .card')).toHaveCount(2);
  await expect(page.locator('.l7-mine[data-peek]')).toBeVisible();
  await page.getByRole('button', { name: 'Got it' }).click();
  await expect(page.locator('.l7-mine .card')).toHaveCount(0);
  // Then peek at the bot's card through the focus sheet.
  await page.locator('.l7-seat.pickable').first().click();
  const card = await page.evaluate(() => (window as any).__efoc.host.state.slots[1][0]);
  await page.locator('.l7-focus-slots .l7-slot').nth(0).click();
  await expect(page.locator('.l7-seat .l7-mini-card.face').first()).toBeVisible();
  expect(await page.locator('.l7-seat .l7-mini-card.face').first().textContent()).toContain(card[0] === 'T' ? '10' : card[0]);
});
