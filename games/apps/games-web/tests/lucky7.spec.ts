// Lucky 7 Practice: a full game against bots, the layout at phone sizes,
// tapping where a card goes (docs/table-feel.md), and every way of picking a
// target (your card, theirs on the table, a focus sheet when cards are small).
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
    const slots = s.slots.map((r: string[]) => r.slice());
    if (deck.length === s.deck.length) {
      // Dealt to someone: give them the deck's top card instead.
      for (const row of slots) for (let i = 0; i < row.length; i++) if (row[i] === card) {
        row[i] = s.deck[s.deck.length - 1];
        deck.splice(deck.indexOf(row[i]), 1);
      }
    }
    host.state = { ...s, slots, deck: [...deck, card] };
  }, card);
}

const host = (page: Page, expr: string) => page.evaluate((expr) => new Function('h', `return ${expr}`)((window as any).__efoc.host), expr);
const theirCard = (page: Page, seat: number, slot: number) => page.locator(`.l7-card[data-seat="${seat}"][data-slot="${slot}"]`);

for (const players of [2, 4, 8]) {
  test(`${players} players on a small phone: cards on the table don't overlap`, async ({ page }) => {
    await page.setViewportSize({ width: 360, height: 780 });
    const errs = errorsOf(page);
    await page.goto(`/lucky7/?players=${players}&seed=4&mute=1&turn=60000`);
    await expect(page.locator('.l7-slot')).toHaveCount(3);
    await expect(page.locator('.l7-seat')).toHaveCount(players - 1);
    await expect(page.locator('.l7-card')).toHaveCount(players * 3);
    // Hold a card so the card in play shows too.
    await page.locator('.l7-deck').click();
    await expect(page.locator('.l7-play')).toBeVisible();
    const boxes = await page.evaluate(() => {
      const r = (el: Element) => el.getBoundingClientRect();
      return {
        all: [
          ...[...document.querySelectorAll('.l7-seat')].map(r),
          ...[...document.querySelectorAll('.l7-card')].map(r),
          r(document.querySelector('.l7-piles')!),
          r(document.querySelector('.l7-play')!),
        ],
        bar: r(document.querySelector('.action-bar')!),
      };
    });
    const hit = (a: DOMRect, b: DOMRect) => a.left + 1 < b.right && b.left + 1 < a.right && a.top + 1 < b.bottom && b.top + 1 < a.bottom;
    const all = boxes.all;
    for (let i = 0; i < all.length; i++) for (let j = i + 1; j < all.length; j++) expect(hit(all[i]!, all[j]!), `boxes ${i} and ${j}`).toBe(false);
    for (const b of all) {
      expect(b.left).toBeGreaterThanOrEqual(0);
      expect(b.right).toBeLessThanOrEqual(360);
      expect(b.bottom).toBeLessThanOrEqual(boxes.bar.top);
    }
    expect(errs).toEqual([]);
  });
}

for (const size of [{ width: 360, height: 740 }, { width: 390, height: 844 }]) {
  test(`8 players at ${size.width}×${size.height}: mini seats grow on their turn without overlapping or leaving the screen`, async ({ page }) => {
    await page.setViewportSize(size);
    const errs = errorsOf(page);
    await page.goto('/lucky7/?players=8&seed=4&mute=1&autoplay=1&speed=0.3&turn=4000&reduced=1&humour=off');
    await expect(page.locator('.l7-card')).toHaveCount(24);
    const grownSeen = new Set<string>();
    const deadline = Date.now() + 60_000;
    while (grownSeen.size < 7 && Date.now() < deadline) {
      const r = await page.evaluate(() => {
        const box = (e: Element) => e.getBoundingClientRect();
        const hit = (a: DOMRect, b: DOMRect) => a.left + 1 < b.right && b.left + 1 < a.right && a.top + 1 < b.bottom && b.top + 1 < a.bottom;
        const problems: string[] = [];
        // Only cards at rest: no flight, pop, lift or peek in the way of measuring.
        const cards = [...document.querySelectorAll<HTMLElement>('.l7-card')].filter(
          (c) => !c.closest('.l7-mine') && c.style.visibility !== 'hidden' && !c.classList.contains('lifted') && !c.dataset.peekLeft && c.getAnimations({ subtree: true }).length === 0,
        );
        const bySeat = new Map<string, DOMRect[]>();
        for (const c of cards) bySeat.set(c.dataset.seat!, [...(bySeat.get(c.dataset.seat!) ?? []), box(c)]);
        const chips = new Map([...document.querySelectorAll<HTMLElement>('.l7-seat')].map((s) => [s.dataset.seat!, box(s)]));
        const bar = box(document.querySelector('.action-bar')!);
        const prompt = box(document.querySelector('.l7-prompt')!);
        const grown = document.querySelector<HTMLElement>('.l7-card.grown')?.dataset.seat ?? null;
        const seats = [...bySeat.keys()];
        for (const s of seats) {
          for (const b of bySeat.get(s)!) {
            if (b.left < 0 || b.top < 0 || b.right > innerWidth || b.bottom > Math.min(bar.top, prompt.top)) problems.push(`seat ${s} card off its area`);
            for (const [t, c] of chips) if (t !== s && hit(b, c)) problems.push(`seat ${s} card on seat ${t}'s badge`);
            for (const t of seats) if (t > s) for (const o of bySeat.get(t)!) if (hit(b, o)) problems.push(`seats ${s} and ${t} cards overlap`);
          }
          const own = bySeat.get(s)!;
          own.forEach((a, i) => own.forEach((b, j) => j > i && hit(a, b) && problems.push(`seat ${s} cards overlap each other`)));
        }
        for (const p of ['.l7-deck', '.l7-discard', '.l7-used']) {
          const pb = box(document.querySelector(p)!);
          for (const s of seats) for (const b of bySeat.get(s)!) if (hit(b, pb)) problems.push(`seat ${s} card on ${p}`);
        }
        const w = (s: string) => Math.round(bySeat.get(s)?.[0]?.width ?? 0);
        return { problems, grown, grownW: grown ? w(grown) : 0, restW: seats.filter((s) => s !== grown).map(w) };
      });
      expect(r.problems).toEqual([]);
      for (const w of r.restW) if (w) expect(w).toBeLessThanOrEqual(24);
      if (r.grown !== null && r.grownW) {
        expect(r.grownW).toBeGreaterThanOrEqual(40);
        grownSeen.add(r.grown);
      }
      await page.waitForTimeout(150);
    }
    expect(grownSeen.size).toBe(7);
    expect(errs).toEqual([]);
  });
}

test('a whole game against bots ends with the reveal, then everyone ranked lowest first', async ({ page }) => {
  const errs = errorsOf(page);
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/lucky7/?players=4&seed=11&mute=1&autoplay=1&speed=0.02&turn=4000&reduced=1');
  await expect(page.locator('.overlay.results')).toBeVisible({ timeout: 120_000 });
  // The reveal turned every card on the table face up before the results.
  await expect(page.locator('.l7-card.face')).toHaveCount(12);
  await expect(page.locator('.l7-standings .standing')).toHaveCount(4);
  await expect(page.locator('.l7-res-cards').first().locator('.card')).toHaveCount(3);
  const nums = (await page.locator('.l7-standings .standing .pts').allTextContents()).map((t) => Number(t.replace(/\D/g, '')));
  expect(nums).toEqual(nums.slice().sort((a, b) => a - b));
  expect(errs).toEqual([]);
});

test('tap the deck, then tap one of my cards: it flies in, the old card flies face up to Discard', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/lucky7/?players=3&seed=5&mute=1&turn=60000');
  await expect(page.locator('.l7-prompt')).toHaveText(/Your turn/);
  await expect(page.locator('.l7-deck')).toHaveClass(/pickable/);
  await page.locator('.l7-deck').click();
  await expect(page.locator('.l7-play .card')).toBeVisible();
  // Holding a card: my cards and Discard light up.
  await expect(page.locator('.l7-slot.pickable')).toHaveCount(3);
  await expect(page.locator('.l7-discard')).toHaveClass(/throw/);
  const before = await host(page, 'h.state.slots[0][1]');
  await page.locator('.l7-slot').nth(1).click();
  await expect(page.locator('.l7-flyer')).toHaveCount(2); // in and out at once
  await expect(page.locator('.l7-discard .card')).toHaveAttribute('data-card', before as string);
  await expect(page.locator('.l7-flyer')).toHaveCount(0);
  await expect(page.locator('.l7-prompt')).toHaveText(/turn…/);
});

test('or tap Discard to throw the card away', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/lucky7/?players=2&seed=8&mute=1&turn=60000');
  await page.locator('.l7-deck').click();
  const drawn = await host(page, 'h.state.drawn');
  await page.locator('.l7-discard').click();
  await expect(page.locator('.l7-discard .card')).toHaveAttribute('data-card', drawn as string);
});

test('Q: pick my card, then theirs right on the table; the two cards cross', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/lucky7/?players=4&seed=6&mute=1&turn=60000&speed=0.05');
  await expect(page.locator('.l7-prompt')).toHaveText(/Your turn/);
  await stackDeck(page, 'Qc');
  await page.locator('.l7-deck').click();
  await expect(page.locator('.l7-power-tag')).toContainText('Swap');
  await page.getByRole('button', { name: /Use/ }).click();
  await page.locator('.l7-slot').nth(0).click();
  await expect(page.locator('.l7-slot.selected')).toHaveCount(1);
  await expect(page.locator('.l7-card.pickable:not(.mine)')).toHaveCount(9);
  const mine = await host(page, 'h.state.slots[0][0]');
  const theirs = await host(page, 'h.state.slots[2][2]');
  await theirCard(page, 2, 2).click();
  await expect.poll(() => page.locator('.l7-flyer').count()).toBeGreaterThan(0);
  expect([await host(page, 'h.state.slots[0][0]'), await host(page, 'h.state.slots[2][2]')]).toEqual([theirs, mine]);
});

test('8 players: small cards are picked in the focus sheet', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/lucky7/?players=8&seed=6&mute=1&turn=60000');
  await stackDeck(page, 'Kc');
  await page.locator('.l7-deck').click();
  await page.getByRole('button', { name: /Use/ }).click();
  await page.locator('.l7-seat.pickable').first().click();
  await expect(page.locator('.l7-focus-sheet')).toBeVisible();
  const seat = Number(await page.locator('.l7-seat.pickable').first().getAttribute('data-seat'));
  await page.locator('.l7-focus-slots .l7-slot').nth(1).click();
  await expect(page.locator('.l7-focus-sheet')).toBeHidden();
  await expect(theirCard(page, seat, 1).locator('.l7-lock')).toBeVisible();
});

test('K locks a card (a K and padlock sit on it); a J then shows ALL my open cards (the locked one stays hidden)', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/lucky7/?players=2&seed=7&mute=1&turn=60000');
  await stackDeck(page, 'Kc');
  await page.locator('.l7-deck').click();
  await page.getByRole('button', { name: /Use/ }).click();
  await page.locator('.l7-slot').nth(1).click(); // lock my own card 2
  await expect(page.locator('.l7-slot').nth(1).locator('.l7-lock')).toBeVisible();
  // The bot moves; my turn again.
  await expect(page.locator('.l7-prompt')).toHaveText(/Your turn/, { timeout: 15_000 });
  await stackDeck(page, 'Jc');
  await page.locator('.l7-deck').click();
  await page.getByRole('button', { name: /Use/ }).click();
  // Either all of mine (my open cards glow, and a button) or one of theirs.
  await expect(page.locator('.l7-prompt')).toHaveText(/all your cards, or tap one card of someone else/);
  await expect(page.locator('.l7-card.pickable')).toHaveCount(5);
  await expect(page.locator('.l7-slot').nth(1)).not.toHaveClass(/pickable/);
  await expect(page.getByRole('button', { name: '👀 All my cards' })).toBeVisible();
  const mine = (await host(page, 'h.state.slots[0]')) as string[];
  await page.locator('.l7-slot').nth(2).click();
  // Both open cards face up for me, with a countdown; the locked one stays down; none of theirs.
  await expect(page.locator('.l7-slot').nth(0).locator('.card')).toHaveAttribute('data-card', mine[0]!);
  await expect(page.locator('.l7-slot').nth(2).locator('.card')).toHaveAttribute('data-card', mine[2]!);
  await expect(page.locator('.l7-slot').nth(0)).toHaveAttribute('data-peek-left', /👀/);
  await expect(page.locator('.l7-slot').nth(1)).not.toHaveClass(/face/);
  await expect(page.locator('.l7-card.face')).toHaveCount(2);
  await expect(page.locator('.l7-card.pickable')).toHaveCount(0);
});

test("a J can peek at someone else's card instead", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/lucky7/?players=2&seed=9&mute=1&turn=60000');
  await stackDeck(page, 'Jd');
  await page.locator('.l7-deck').click();
  await page.getByRole('button', { name: /Use/ }).click();
  const card = (await host(page, 'h.state.slots[1][0]')) as string;
  await theirCard(page, 1, 0).click();
  await expect(theirCard(page, 1, 0)).toHaveClass(/face/);
  await expect(theirCard(page, 1, 0).locator('.card')).toHaveAttribute('data-card', card);
  await expect(page.locator('.l7-mine .card')).toHaveCount(0); // none of mine shown
});
