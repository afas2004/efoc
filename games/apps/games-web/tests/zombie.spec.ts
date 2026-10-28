// Zombie: Practice against bots (the layout at phone sizes up to 8 players,
// picking a card, dragging and shuffling my hand, a whole game to the
// loser's moment and results), and online over the room store with no
// hidden card ever reaching the wrong phone or the public log.
import { expect, test, type Page } from '@playwright/test';

const errorsOf = (page: Page): string[] => {
  const errs: string[] = [];
  page.on('pageerror', (e) => errs.push(String(e)));
  page.on('console', (m) => m.type() === 'error' && errs.push(m.text()));
  return errs;
};

const host = (page: Page, expr: string) => page.evaluate((expr) => new Function('h', `return ${expr}`)((window as any).__efoc.host), expr);

/** Every box on the table at rest: seats, the spread being drawn from, the graveyard, my hand. */
async function tableBoxes(page: Page) {
  return page.evaluate(() => {
    const r = (e: Element) => e.getBoundingClientRect();
    const still = (e: Element) => (e as HTMLElement).getAnimations({ subtree: true }).length === 0;
    const picks = [...document.querySelectorAll('.zb-pick:not(.hidden)')].map(r);
    // The strip of each spread card a finger can hit: up to where the next one starts.
    // (Unrotated boxes: the fan tilts its cards a few degrees.)
    const flat = [...document.querySelectorAll<HTMLElement>('.zb-pick:not(.hidden)')].map((e) => ({ x: e.offsetLeft, y: e.offsetTop, w: e.offsetWidth }));
    const strips = flat.map((b, i) => (i + 1 < flat.length && Math.abs(flat[i + 1]!.y - b.y) < 12 ? flat[i + 1]!.x - b.x : b.w));
    const twoRows = new Set(picks.map((b) => Math.round(b.top))).size > 1;
    return {
      seats: [...document.querySelectorAll('.zb-seat')].map(r),
      stage: picks.length ? (() => {
        const xs = picks.map((b) => [b.left, b.right]).flat();
        const ys = picks.map((b) => [b.top, b.bottom]).flat();
        return new DOMRect(Math.min(...xs), Math.min(...ys), Math.max(...xs) - Math.min(...xs), Math.max(...ys) - Math.min(...ys));
      })() : null,
      label: r(document.querySelector('.zb-stage-label')!),
      pile: r(document.querySelector('.zb-pile')!),
      hand: [...document.querySelectorAll('.zb-hand .card')].filter(still).map(r),
      bar: r(document.querySelector('.action-bar')!),
      strips,
      twoRows,
      vw: innerWidth,
    };
  });
}

const hit = (a: DOMRect, b: DOMRect) => a.left + 1 < b.right && b.left + 1 < a.right && a.top + 1 < b.bottom && b.top + 1 < a.bottom;

function layoutProblems(b: Awaited<ReturnType<typeof tableBoxes>>): string[] {
  const out: string[] = [];
  const named: [string, DOMRect][] = [...b.seats.map((s, i) => [`seat ${i}`, s] as [string, DOMRect]), ['pile', b.pile]];
  if (b.stage) named.push(['spread', b.stage]);
  for (let i = 0; i < named.length; i++) for (let j = i + 1; j < named.length; j++) if (hit(named[i]![1], named[j]![1])) out.push(`${named[i]![0]} overlaps ${named[j]![0]}`);
  for (const [n, box] of named) {
    if (box.left < 0 || box.right > b.vw) out.push(`${n} off screen`);
    if (box.bottom > b.bar.top) out.push(`${n} under the action bar`);
    for (const h of b.hand) if (hit(box, h)) out.push(`${n} overlaps my hand`);
  }
  for (const h of b.hand) if (h.left < 0 || h.right > b.vw + 1 || h.bottom > b.bar.top) out.push('a hand card off its area');
  if (b.stage && hit(b.label, b.stage)) out.push('the label sits on the spread');
  for (const s of b.strips) if (s < 44) out.push(`a spread card only ${Math.round(s)} px wide to tap`);
  return out;
}

for (const players of [2, 4, 6, 8]) {
  test(`${players} players on a small phone: nothing overlaps, every card to pick keeps 44 px`, async ({ page }) => {
    await page.setViewportSize({ width: 360, height: 780 });
    const errs = errorsOf(page);
    await page.goto(`/zombie/?players=${players}&seed=4&mute=1&turn=60000&reduced=1&humour=off`);
    await expect(page.locator('.zb-seat')).toHaveCount(players - 1);
    // My turn first: the next player's hand is spread to pick from.
    await expect(page.locator('.zb-pick.pickable').first()).toBeVisible();
    await page.waitForTimeout(1600); // the deal's pairs have dropped
    const b = await tableBoxes(page);
    expect(layoutProblems(b)).toEqual([]);
    expect(b.hand.length).toBe(await host(page, 'h.state.hands[0].length'));
    expect(errs).toEqual([]);
  });
}

for (const size of [{ width: 360, height: 740 }, { width: 390, height: 844 }]) {
  test(`8 players at ${size.width}×${size.height}: a whole game never overlaps or leaves the screen`, async ({ page }) => {
    test.setTimeout(180_000);
    await page.setViewportSize(size);
    const errs = errorsOf(page);
    await page.goto('/zombie/?players=8&seed=6&mute=1&autoplay=1&speed=0.15&turn=4000&reduced=1&humour=off');
    await expect(page.locator('.zb-seat')).toHaveCount(7);
    const seenFrom = new Set<number>();
    while (!(await page.locator('.overlay.results').isVisible())) {
      const b = await tableBoxes(page);
      expect(layoutProblems(b)).toEqual([]);
      const s = await host(page, '({ turn: h.state.turn, phase: h.state.phase })');
      if (s.phase === 'play') seenFrom.add(s.turn);
      await page.waitForTimeout(200);
    }
    expect(seenFrom.size).toBeGreaterThan(3);
    expect(errs).toEqual([]);
  });
}

test('a whole game against bots: the loser gets eaten, results list the safe order and the Zombie story', async ({ page }) => {
  const errs = errorsOf(page);
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/zombie/?players=4&seed=11&mute=1&autoplay=1&speed=0.05&turn=4000&reduced=1');
  await expect(page.locator('.overlay.results')).toBeVisible({ timeout: 120_000 });
  const s = await host(page, '({ loser: h.state.loser, placings: h.game.result(h.state).placings, hand: h.state.hands[h.state.loser] })');
  expect(s.hand).toEqual(['JK']);
  expect(s.placings[3]).toBe(s.loser);
  await expect(page.locator('.zb-standings .standing')).toHaveCount(4);
  await expect(page.locator('.zb-standings .standing').last()).toHaveClass(/zb-lost/);
  await expect(page.locator('.zb-standings .standing.zb-lost .medal')).toHaveText('🧟');
  await expect(page.locator('.zb-stats li').first()).toContainText('changed hands');
  if (s.loser !== 0) await expect(page.locator(`.zb-seat[data-seat="${s.loser}"]`)).toHaveClass(/zb-eaten/);
  // Play again deals a fresh game.
  await page.getByRole('button', { name: 'Play again' }).click();
  await expect(page.locator('.overlay.results')).toBeHidden();
  expect(await host(page, 'h.state.phase')).toBe('play');
  expect(errs).toEqual([]);
});

test('tap one of their cards: it flies to the end of my hand (or drops with its pair)', async ({ page }) => {
  const errs = errorsOf(page);
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/zombie/?players=3&seed=2&mute=1&turn=60000&reduced=1&humour=off&speed=20');
  await expect(page.locator('.zb-pick.pickable')).toHaveCount(await host(page, 'h.state.hands[1].length'));
  const before = await host(page, '({ mine: h.state.hands[0].slice(), theirs: h.state.hands[1].slice() })');
  await page.locator('.zb-pick').nth(1).click();
  const taken = before.theirs[1];
  const after = await host(page, '({ mine: h.state.hands[0].slice(), pile: h.state.pile.slice(-2) })');
  if (after.mine.includes(taken)) expect(after.mine[after.mine.length - 1]).toBe(taken);
  else expect(after.pile).toContain(taken);
  // Once it lands, my hand on screen is exactly my hand.
  await expect.poll(() => page.locator('.zb-hand .card:visible').evaluateAll((els) => (els as HTMLElement[]).sort((a, b) => Number(a.style.zIndex) - Number(b.style.zIndex)).map((e) => e.dataset.card))).toEqual(after.mine);
  expect(errs).toEqual([]);
});

test('drag a card to move it; Shuffle mixes my hand; neither changes whose turn it is', async ({ page }) => {
  const errs = errorsOf(page);
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/zombie/?players=2&seed=5&mute=1&turn=60000&reduced=1&humour=off');
  await page.waitForTimeout(1500);
  const hand: string[] = await host(page, 'h.state.hands[0].slice()');
  expect(hand.length).toBeGreaterThan(2);
  const first = page.locator(`.zb-hand .card[data-card="${hand[0]}"]`);
  const last = page.locator(`.zb-hand .card[data-card="${hand[hand.length - 1]}"]`);
  const a = (await first.boundingBox())!;
  const z = (await last.boundingBox())!;
  await page.mouse.move(a.x + a.width / 2, a.y + a.height / 2);
  await page.mouse.down();
  await page.mouse.move(a.x + 40, a.y + a.height / 2, { steps: 4 });
  await page.mouse.move(z.x + z.width - 4, z.y + z.height / 2, { steps: 8 });
  await page.mouse.up();
  await expect.poll(() => host(page, 'h.state.hands[0].slice()')).toEqual([...hand.slice(1), hand[0]]);
  expect(await host(page, 'h.state.turn')).toBe(0);
  await expect.poll(() => page.locator('.zb-hand .card').evaluateAll((els) => (els as HTMLElement[]).sort((a, b) => Number(a.style.zIndex) - Number(b.style.zIndex)).map((e) => e.dataset.card))).toEqual([...hand.slice(1), hand[0]]);
  // Shuffle: same cards, still my turn.
  const n0 = await host(page, 'h.n');
  await page.getByRole('button', { name: 'Shuffle' }).click();
  await expect.poll(() => host(page, 'h.n')).toBe(n0 + 1);
  expect((await host(page, 'h.state.hands[0].slice()')).sort()).toEqual(hand.slice().sort());
  expect(await host(page, 'h.state.turn')).toBe(0);
  expect(errs).toEqual([]);
});

test('the Zombie card has its own face; the menu explains the rules', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/zombie/?players=4&seed=3&mute=1&turn=60000&reduced=1&humour=off');
  // Seed 3 deals me the Zombie.
  expect(await host(page, 'h.state.hands[0].includes("JK")')).toBe(true);
  await expect(page.locator('.zb-hand .zb-zombie-card')).toHaveCount(1);
  await page.getByRole('button', { name: 'Menu' }).click();
  await expect(page.locator('.l7-help li')).toHaveCount(5);
});

// ------------------------------------------------------------- online

const status = (p: Page) => p.evaluate(() => (window as any).__room?.status() ?? { host: false, n: -1, drift: 0, seat: null, phase: null });

test('online: three phones and a bot play Zombie; no phone ever shows a card it may not see, the log never carries an order', async ({ context }) => {
  test.setTimeout(180_000);
  const room = `zb-${Date.now()}`;
  const uids = ['z1', 'z2', 'z3'];
  const pages: Page[] = [];
  for (const [i, uid] of uids.entries()) {
    const page: Page = await context.newPage();
    await page.setViewportSize({ width: 390, height: 844 });
    const create = i === 0 ? `&create=1&allowed=${uids.join(',')}` : '';
    await page.goto(`/zombie/?room=${room}&uid=${uid}&name=P${i + 1}&mute=1&turn=6000&autopilot=1&speed=0.2${create}`);
    if (i === 0) await expect(page.locator('.overlay.lobby')).toBeVisible();
    pages.push(page);
  }
  for (const p of pages) await expect(p.locator('.lobby-seat')).toHaveCount(3);
  await pages[0]!.getByRole('button', { name: '+ Add bot' }).click();
  for (const p of pages) await expect(p.locator('.lobby-seat')).toHaveCount(4);
  for (const p of pages) await p.getByRole('button', { name: 'Ready?' }).click();
  await pages[0]!.getByRole('button', { name: 'Start' }).click();
  await expect(pages[1]!.locator('.zb-seat')).toHaveCount(3);

  // Shuffle on a phone that isn't the host, through intents.
  await pages[2]!.getByRole('button', { name: 'Shuffle' }).click();

  /**
   * Cards in each phone's DOM (flights aside) that were never in its own
   * hand nor thrown on the graveyard. Host state is read before and after,
   * since a phone may show the table a moment behind the host.
   */
  const seen = uids.map(() => new Set<string>());
  const hostNow = () => pages[0]!.evaluate(() => (window as any).__room.host.state);
  const leaks = async (): Promise<string[]> => {
    const seats = await Promise.all(pages.map(async (p) => (await status(p)).seat as number));
    const note = (s: any) => s.phase === 'play' && seats.forEach((seat, i) => [...s.hands[seat], ...s.pile].forEach((c: string) => seen[i]!.add(c)));
    const before = await hostNow();
    note(before);
    const shown = await Promise.all(pages.map((p) => p.evaluate(() => [...document.querySelectorAll('[data-card]')].filter((e) => !e.closest('.l7-flights')).map((e) => (e as HTMLElement).dataset.card!))));
    const after = await hostNow();
    if (before.phase !== 'play' || after.phase !== 'play') return [];
    note(after);
    const out: string[] = [];
    shown.forEach((cards, i) => cards.forEach((c) => !seen[i]!.has(c) && out.push(`phone ${i + 1} shows ${c}`)));
    return out;
  };
  let checks = 0;
  while (!(await pages[0]!.locator('.overlay.results').isVisible())) {
    expect(await leaks()).toEqual([]);
    checks++;
    await pages[0]!.waitForTimeout(250);
  }
  expect(checks).toBeGreaterThan(5);
  for (const p of pages) await expect(p.locator('.overlay.results')).toBeVisible({ timeout: 30_000 });
  await expect.poll(async () => new Set((await Promise.all(pages.map(status))).map((s) => s.n)).size, { timeout: 5000 }).toBe(1);
  const st = await Promise.all(pages.map(status));
  expect(st.every((s) => s.drift === 0)).toBe(true);
  // Same loser everywhere.
  const losers = await Promise.all(pages.map((p) => p.locator('.zb-standings .standing.zb-lost .who').textContent()));
  const named = losers.map((w, i) => (w?.includes('You') ? `P${i + 1}` : w?.replace(/^\S+\s/, '')));
  expect(new Set(named).size).toBe(1);
  // The public log: no reorder ever names a card, and no draw names the card drawn.
  const log: string = await pages[0]!.evaluate((room) => {
    const out: string[] = [];
    for (let i = 0; i < localStorage.length; i++) {
      const k = localStorage.key(i)!;
      if (k.includes(`rooms/${room}/log`)) out.push(localStorage.getItem(k)!);
    }
    return out.join('\n');
  }, room);
  expect(log).toContain('"order"');
  expect(log).not.toMatch(/"type":"order","cards"/);
  expect(log).not.toContain('drawn_card');
  expect(log).not.toContain('"type":"hand"');
});
