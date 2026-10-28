// Zombie: Practice against bots (everyone's hand at their edge, the
// exchange expanding, every card I pick keeping a 44 px strip, up to 8
// players; pointing then confirming; throwing pairs by hand or Auto-throw; a
// whole game to the loser's moment and results), and online over the room
// store with no hidden card ever reaching the wrong phone or the public log.
// ?anim=0.05 runs the (deliberately slow) animations fast.
import { expect, test, type Page } from '@playwright/test';

const errorsOf = (page: Page): string[] => {
  const errs: string[] = [];
  page.on('pageerror', (e) => errs.push(String(e)));
  page.on('console', (m) => m.type() === 'error' && errs.push(m.text()));
  return errs;
};

const host = (page: Page, expr: string) => page.evaluate((expr) => new Function('h', `return ${expr}`)((window as any).__efoc.host), expr);
const FAST = 'mute=1&humour=off&anim=0.05&reduced=1';

/** Boxes on the table: badges, my hand, the pile label, the bar, and the cards I may pick. */
async function tableBoxes(page: Page) {
  return page.evaluate(() => {
    const r = (e: Element) => e.getBoundingClientRect();
    const still = (e: Element) => (e as HTMLElement).getAnimations({ subtree: true }).length === 0;
    const picks = [...document.querySelectorAll<HTMLElement>('.zb-back.pickable')].filter(still);
    return {
      badges: [...document.querySelectorAll<HTMLElement>('.zb-seat')].filter(still).map((e) => ({ seat: e.dataset.seat!, box: r(e), active: e.classList.contains('zb-active') })),
      hand: [...document.querySelectorAll('.zb-hand .zb-mine-wrap')].filter(still).map(r),
      backs: [...document.querySelectorAll<HTMLElement>('.zb-back')].filter(still).map((e) => ({ seat: e.dataset.seat!, box: r(e) })),
      picks: picks.map(r),
      // What a finger hits: the point of each pick card not covered by the next one.
      hits: picks.map((e) => {
        const b = r(e);
        const pts = [0.15, 0.3, 0.5, 0.7, 0.85].flatMap((fx) => [0.15, 0.5, 0.85].map((fy) => [b.left + b.width * fx, b.top + b.height * fy]));
        return pts.some(([x, y]) => document.elementFromPoint(x!, y!)?.closest('.zb-back') === e);
      }),
      bar: r(document.querySelector('.action-bar')!),
      vw: innerWidth,
      vh: innerHeight,
    };
  });
}

const hit = (a: DOMRect, b: DOMRect) => a.left + 1 < b.right && b.left + 1 < a.right && a.top + 1 < b.bottom && b.top + 1 < a.bottom;

function layoutProblems(b: Awaited<ReturnType<typeof tableBoxes>>): string[] {
  const out: string[] = [];
  const rest = b.badges.filter((x) => !x.active);
  for (const x of b.badges) {
    if (x.box.left < -1 || x.box.right > b.vw + 1 || x.box.top < -1 || x.box.bottom > b.bar.top) out.push(`seat ${x.seat}'s badge off the table`);
    for (const h of b.hand) if (hit(x.box, h)) out.push(`seat ${x.seat}'s badge on my hand`);
  }
  // At rest, badges and fans keep apart and away from my hand. (The two in the exchange are drawn over the table on purpose.)
  for (let i = 0; i < rest.length; i++) for (let j = i + 1; j < rest.length; j++) if (hit(rest[i]!.box, rest[j]!.box)) out.push(`badges ${rest[i]!.seat} and ${rest[j]!.seat} overlap`);
  const restSeats = new Set(rest.map((x) => x.seat));
  for (const c of b.backs.filter((x) => restSeats.has(x.seat))) {
    for (const x of rest) if (x.seat !== c.seat && hit(c.box, x.box)) out.push(`seat ${c.seat}'s cards on seat ${x.seat}'s badge`);
    for (const h of b.hand) if (hit(c.box, h)) out.push(`seat ${c.seat}'s cards on my hand`);
  }
  for (const p of b.picks) if (p.left < 0 || p.right > b.vw || p.top < 0 || p.bottom > b.bar.top) out.push('a card to pick is off the screen');
  b.hits.forEach((ok, i) => ok || out.push(`pick card ${i} can't be tapped`));
  return out;
}

/** Throws my dealt pairs and waits until it's my turn to pick. */
async function toMyPick(page: Page): Promise<void> {
  const all = page.getByRole('button', { name: /Throw/ });
  await all.click({ timeout: 15_000 }).catch(() => undefined);
  await expect(page.locator('.zb-back.pickable').first()).toBeVisible({ timeout: 30_000 });
}

for (const players of [2, 4, 6, 8]) {
  test(`${players} players on a small phone: hands at their edges, my pick spread big with 44 px strips, nothing overlaps`, async ({ page }) => {
    await page.setViewportSize({ width: 360, height: 780 });
    const errs = errorsOf(page);
    await page.goto(`/zombie/?players=${players}&seed=4&turn=60000&${FAST}`);
    await expect(page.locator('.zb-seat')).toHaveCount(players - 1);
    await toMyPick(page);
    await page.waitForTimeout(300);
    const b = await tableBoxes(page);
    expect(layoutProblems(b)).toEqual([]);
    expect(b.picks.length).toBe(await host(page, 'h.state.hands[h.state.hands.findIndex((x, i) => i > 0 && x.length)].length'));
    // The two in the exchange are expanded; everyone else rests.
    expect(b.badges.filter((x) => x.active).map((x) => x.seat)).toEqual([String(await host(page, 'h.game.view(h.state, 0).from'))]);
    expect(errs).toEqual([]);
  });
}

for (const size of [{ width: 360, height: 740 }, { width: 390, height: 844 }]) {
  test(`8 players at ${size.width}×${size.height}: a whole game never overlaps or leaves the screen`, async ({ page }) => {
    test.setTimeout(240_000);
    await page.setViewportSize(size);
    const errs = errorsOf(page);
    await page.goto(`/zombie/?players=8&seed=6&autoplay=1&speed=0.1&turn=4000&${FAST}`);
    await expect(page.locator('.zb-seat')).toHaveCount(7);
    const active = new Set<string>();
    while (!(await page.locator('.overlay.results').isVisible())) {
      const b = await tableBoxes(page);
      expect(layoutProblems({ ...b, hits: [] })).toEqual([]);
      for (const x of b.badges) if (x.active) active.add(x.seat);
      await page.waitForTimeout(150);
    }
    expect(active.size).toBeGreaterThanOrEqual(2);
    expect(errs).toEqual([]);
  });
}

test('a whole game against bots: the loser gets eaten, results list the safe order and the Zombie story', async ({ page }) => {
  test.setTimeout(180_000);
  const errs = errorsOf(page);
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(`/zombie/?players=4&seed=11&autoplay=1&speed=0.05&turn=4000&${FAST}`);
  await expect(page.locator('.overlay.results')).toBeVisible({ timeout: 150_000 });
  const s = await host(page, '({ loser: h.state.loser, placings: h.game.result(h.state).placings, hand: h.state.hands[h.state.loser] })');
  expect(s.hand).toEqual(['JK']);
  expect(s.placings[3]).toBe(s.loser);
  await expect(page.locator('.zb-standings .standing')).toHaveCount(4);
  await expect(page.locator('.zb-standings .standing').last()).toHaveClass(/zb-lost/);
  await expect(page.locator('.zb-stats li').first()).toContainText('changed hands');
  if (s.loser !== 0) await expect(page.locator(`.zb-seat[data-seat="${s.loser}"]`)).toHaveClass(/zb-eaten/);
  await page.getByRole('button', { name: 'Play again' }).click();
  await expect(page.locator('.overlay.results')).toBeHidden();
  expect(await host(page, 'h.state.phase')).toBe('play');
  expect(errs).toEqual([]);
});

test('the deal: my pairs glow; tap one to throw it, then Throw all; nothing moves on until everyone has thrown', async ({ page }) => {
  const errs = errorsOf(page);
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(`/zombie/?players=3&seed=2&turn=60000&${FAST}`);
  await expect(page.locator('.zb-mine-wrap.zb-paired').first()).toBeVisible({ timeout: 10_000 });
  const pairs: string[][] = await host(page, 'h.game.view(h.state, 0).hand.length && __pairs(h.state.hands[0])'.replace('__pairs', '((hand) => { const m = new Map(), o = []; for (const c of hand) { if (c === "JK") continue; const r = c[0]; if (m.has(r)) { o.push([m.get(r), c]); m.delete(r); } else m.set(r, c); } return o; })'));
  expect(pairs.length).toBeGreaterThan(1);
  expect(await host(page, 'h.state.step')).toBe('deal');
  await expect(page.locator('.zb-mine-wrap.pickable')).toHaveCount(pairs.length * 2);
  await page.locator(`.zb-mine-wrap[data-card="${pairs[0]![0]}"]`).click();
  await expect.poll(() => host(page, 'h.state.pairs[0]')).toBe(1);
  expect(await host(page, `h.state.hands[0].includes("${pairs[0]![1]}")`)).toBe(false);
  await page.getByRole('button', { name: /Throw/ }).click();
  await expect.poll(() => host(page, 'h.state.pairs[0]')).toBe(pairs.length);
  await expect.poll(() => host(page, 'h.state.step'), { timeout: 20_000 }).toBe('draw');
  expect(errs).toEqual([]);
});

test('my pick: tap a card to point at it (it lifts, the host knows), tap it again to take it; it lands at the end of my hand', async ({ page }) => {
  const errs = errorsOf(page);
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(`/zombie/?players=3&seed=2&turn=60000&${FAST}`);
  await toMyPick(page);
  const before: { from: number; theirs: string[] } = await host(page, '({ from: h.game.view(h.state, 0).from, theirs: h.state.hands[h.game.view(h.state, 0).from].slice() })');
  await page.locator('.zb-back.pickable').nth(1).click();
  await expect.poll(() => host(page, 'h.state.aim')).toBe(1);
  await expect(page.locator('.zb-back.aimed')).toHaveCount(1);
  expect(await host(page, 'h.state.turn')).toBe(0); // pointing doesn't take the turn
  // Change my mind, then confirm with the button.
  await page.locator('.zb-back.pickable').nth(0).click();
  await expect.poll(() => host(page, 'h.state.aim')).toBe(0);
  await page.getByRole('button', { name: /Take it/ }).click();
  const taken = before.theirs[0]!;
  await expect.poll(() => host(page, `h.state.hands[0].includes("${taken}")`)).toBe(true);
  const mine: string[] = await host(page, 'h.state.hands[0].slice()');
  expect(mine[mine.length - 1]).toBe(taken);
  await expect.poll(() => page.locator('.zb-hand .zb-mine-wrap').evaluateAll((els) => (els as HTMLElement[]).sort((a, b) => Number(a.style.zIndex) - Number(b.style.zIndex)).map((e) => e.dataset.card))).toEqual(mine);
  expect(errs).toEqual([]);
});

test('a drawn pair waits for me to throw it; with Auto-throw on (menu) pairs throw themselves', async ({ page }) => {
  const errs = errorsOf(page);
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(`/zombie/?players=3&seed=2&turn=60000&${FAST}`);
  await toMyPick(page);
  // Stack the next hand so my pick makes a pair.
  await page.evaluate(() => {
    const h = (window as any).__efoc.host;
    const s = h.state;
    const from = h.game.view(s, 0).from;
    const mine = s.hands[0].find((c: string) => c !== 'JK')!;
    const hands = s.hands.map((x: string[]) => x.slice());
    const mate = hands.findIndex((x: string[], i: number) => i !== 0 && x.some((c) => c[0] === mine[0]));
    const card = hands[mate].find((c: string) => c[0] === mine[0]);
    hands[mate] = hands[mate].filter((c: string) => c !== card);
    hands[from].unshift(card);
    if (mate !== from) hands[mate].push(hands[from].pop());
    h.state = { ...s, hands };
  });
  await page.locator('.zb-back.pickable').nth(0).click();
  await page.locator('.zb-back.aimed').click();
  await expect.poll(() => host(page, 'h.state.step')).toBe('throw');
  await expect(page.locator('.zb-mine-wrap.zb-paired')).toHaveCount(2);
  const n = await host(page, 'h.state.pairs[0]');
  await page.locator('.zb-mine-wrap.pickable').first().click();
  await expect.poll(() => host(page, 'h.state.pairs[0]')).toBe(n + 1);
  // Auto-throw.
  await page.getByRole('button', { name: 'Menu' }).click();
  await page.getByRole('switch', { name: 'Auto-throw pairs' }).click();
  await expect(page.getByRole('switch', { name: 'Auto-throw pairs' })).toHaveAttribute('aria-checked', 'true');
  expect(await page.evaluate(() => localStorage.getItem('efoc.zombie.autoThrow'))).toBe('1');
  expect(errs).toEqual([]);
});

test('Auto-throw throws the deal pairs by itself; the Zombie card has its own face; the menu explains the rules', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.addInitScript(() => localStorage.setItem('efoc.zombie.autoThrow', '1'));
  await page.goto(`/zombie/?players=4&seed=3&turn=60000&${FAST}`);
  expect(await host(page, 'h.state.hands[0].includes("JK")')).toBe(true);
  await expect(page.locator('.zb-hand .zb-zombie-card')).toHaveCount(1);
  await expect.poll(() => host(page, 'h.game.view(h.state, 0).hand.length > 0 && h.state.step')).toBe('draw');
  await page.getByRole('button', { name: 'Menu' }).click();
  await expect(page.locator('.l7-help li')).toHaveCount(5);
});

// ------------------------------------------------------------- online

const status = (p: Page) => p.evaluate(() => (window as any).__room?.status() ?? { host: false, n: -1, drift: 0, seat: null, phase: null });

test('online: three phones and a bot play Zombie; no phone ever shows a card it may not see', async ({ context }) => {
  test.setTimeout(240_000);
  const room = `zb-${Date.now()}`;
  const uids = ['z1', 'z2', 'z3'];
  const pages: Page[] = [];
  for (const [i, uid] of uids.entries()) {
    const page: Page = await context.newPage();
    await page.setViewportSize({ width: 390, height: 844 });
    const create = i === 0 ? `&create=1&allowed=${uids.join(',')}` : '';
    await page.goto(`/zombie/?room=${room}&uid=${uid}&name=P${i + 1}&turn=6000&autopilot=1&speed=0.2&${FAST}${create}`);
    if (i === 0) await expect(page.locator('.overlay.lobby')).toBeVisible();
    pages.push(page);
  }
  for (const p of pages) await expect(p.locator('.lobby-seat')).toHaveCount(3);
  await pages[0]!.getByRole('button', { name: '+ Add bot' }).click();
  for (const p of pages) await expect(p.locator('.lobby-seat')).toHaveCount(4);
  for (const p of pages) await p.getByRole('button', { name: 'Ready?' }).click();
  await pages[0]!.getByRole('button', { name: 'Start' }).click();
  await expect(pages[1]!.locator('.zb-seat')).toHaveCount(3);

  /**
   * Cards in each phone's DOM (flights aside) that were never in its own
   * hand nor on the pile. Host state is read before and after, since a
   * phone may show the table a moment behind the host.
   */
  const seen = uids.map(() => new Set<string>());
  const hostNow = () => pages[0]!.evaluate(() => (window as any).__room.host.state);
  const leaks = async (): Promise<string[]> => {
    const seats = await Promise.all(pages.map(async (p) => (await status(p)).seat as number));
    const note = (s: any) => s.phase === 'play' && seats.forEach((seat, i) => [...s.hands[seat], ...s.pile].forEach((c: string) => seen[i]!.add(c)));
    const before = await hostNow();
    note(before);
    const shown = await Promise.all(pages.map((p) => p.evaluate(() => [...document.querySelectorAll('[data-card]')].filter((e) => !e.closest('.zb-flights')).map((e) => (e as HTMLElement).dataset.card!))));
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
  const losers = await Promise.all(pages.map((p) => p.locator('.zb-standings .standing.zb-lost .who').textContent()));
  expect(losers.filter((w) => w?.includes('You')).length).toBeLessThanOrEqual(1);
  expect(new Set(losers.filter((w) => !w?.includes('You'))).size).toBe(1);
  // The public log never names a drawn card or a shuffled order.
  const log: string = await pages[0]!.evaluate((room) => {
    const out: string[] = [];
    for (let i = 0; i < localStorage.length; i++) {
      const k = localStorage.key(i)!;
      if (k.includes(`rooms/${room}/log`)) out.push(localStorage.getItem(k)!);
    }
    return out.join('\n');
  }, room);
  expect(log).toContain('"shuffled"');
  expect(log).not.toContain('drawn_card');
  expect(log).not.toContain('"type":"hand"');
});
