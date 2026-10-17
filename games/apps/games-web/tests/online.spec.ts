// Multiplayer over the local room store: each page is one phone; pages in
// one browser context share localStorage, like phones sharing a database.
import { expect, test, type Page } from '@playwright/test';

test.use({ viewport: { width: 390, height: 844 } });

const status = (p: Page) => p.evaluate(() => (window as any).__room?.status() ?? { host: false, n: -1, drift: 0, seat: null, phase: null });

async function phones(context: any, room: string, uids: string[], extra = '') {
  const pages: Page[] = [];
  for (const [i, uid] of uids.entries()) {
    const page: Page = await context.newPage();
    const create = i === 0 ? `&create=1&allowed=${uids.join(',')}` : '';
    await page.goto(`/bigtwo/?room=${room}&uid=${uid}&name=P${i + 1}&mute=1${create}${extra}`);
    if (i === 0) await expect(page.locator('.overlay.lobby')).toBeVisible();
    pages.push(page);
  }
  return pages;
}

test('three phones and a bot play a full match over the room store', async ({ context }) => {
  const room = `t3-${Date.now()}`;
  const pages = await phones(context, room, ['a1', 'a2', 'a3'], '&turn=8000&preview=0&autopilot=1');
  // Everyone shows in the waiting room; host adds a bot; all ready; host starts.
  for (const p of pages) await expect(p.locator('.lobby-seat')).toHaveCount(3);
  await pages[0]!.getByRole('button', { name: '+ Add bot' }).click();
  for (const p of pages) await expect(p.locator('.lobby-seat')).toHaveCount(4);
  for (const p of pages) await p.getByRole('button', { name: 'Ready?' }).click();
  await pages[0]!.getByRole('button', { name: 'Start' }).click();
  for (const p of pages) await expect(p.locator('.overlay.results')).toBeVisible({ timeout: 90_000 });
  // Everyone ends at the same log position, with no drift from the host.
  await expect.poll(async () => new Set((await Promise.all(pages.map(status))).map((s) => s.n)).size, { timeout: 5000 }).toBe(1);
  const st = await Promise.all(pages.map(status));
  expect(st.map((s) => s.host)).toEqual([true, false, false]);
  expect(st.every((s) => s.drift === 0)).toBe(true);
  // Same winner everywhere (each phone calls itself "You").
  const winners = await Promise.all(pages.map(async (p, i) => {
    const w = await p.locator('.podium-step.p1 .podium-name').textContent();
    return w === 'You' ? `P${i + 1}` : w;
  }));
  expect(new Set(winners).size).toBe(1);
});

test('exit gate: 8 phones finish Fight Till The End after the host drops out', async ({ context }) => {
  test.setTimeout(300_000);
  const room = `t8-${Date.now()}`;
  const uids = ['h1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 'p8'];
  const pages = await phones(context, room, uids, '&turn=6000&preview=0&migrate=5000&autopilot=1');
  for (const p of pages) await expect(p.locator('.lobby-seat')).toHaveCount(8, { timeout: 15_000 });
  await pages[0]!.getByRole('button', { name: 'Fight Till The End' }).click();
  for (const p of pages) await p.getByRole('button', { name: 'Ready?' }).click();
  await pages[0]!.getByRole('button', { name: 'Start' }).click();

  // Let the match get going, then the host's phone disappears.
  await expect.poll(() => status(pages[1]!).then((s) => s.n), { timeout: 60_000 }).toBeGreaterThanOrEqual(15);
  const nAtDrop = (await status(pages[1]!)).n;
  await pages[0]!.close({ runBeforeUnload: true });
  const rest = pages.slice(1);

  // Within migrateAfterMs (+ a heartbeat or two) someone else is referee.
  await expect.poll(async () => (await Promise.all(rest.map(status))).filter((s) => s.host).length, { timeout: 30_000 }).toBe(1);
  const newHost = (await Promise.all(rest.map(status))).findIndex((s) => s.host);
  expect(newHost).toBe(0); // the next seat after the old host

  // The match carries on from the same log and finishes on every phone.
  for (const p of rest) await expect(p.locator('.overlay.results')).toBeVisible({ timeout: 240_000 });
  await expect.poll(async () => new Set((await Promise.all(rest.map(status))).map((s) => s.n)).size, { timeout: 5000 }).toBe(1);
  const st = await Promise.all(rest.map(status));
  expect(st[0]!.n).toBeGreaterThan(nAtDrop);
  expect(st.every((s) => s.drift === 0 && s.phase === 'matchOver')).toBe(true);
  // Fight Till The End: every seat gets a place.
  await expect(rest[0]!.locator('.podium-step')).toHaveCount(3);
  await expect(rest[0]!.locator('.standing')).toHaveCount(5);
});

test('a player who reloads rejoins their seat; a latecomer watches', async ({ context }) => {
  test.setTimeout(240_000);
  const room = `tr-${Date.now()}`;
  const uids = ['r1', 'r2', 'r3', 'r4'];
  const pages = await phones(context, room, uids.slice(0, 3), '&turn=6000&preview=0&autopilot=1');
  // r4 is in the group (allowed) but arrives late.
  await pages[0]!.evaluate((room) => localStorage.setItem(`efoc-db:rooms/${room}/allowed/r4`, 'true'), room);
  for (const p of pages) await p.getByRole('button', { name: 'Ready?' }).click();
  await pages[0]!.getByRole('button', { name: 'Start' }).click();
  await expect.poll(() => status(pages[1]!).then((s) => s.n), { timeout: 60_000 }).toBeGreaterThanOrEqual(8);

  // Phone 2 reloads mid-game: same seat, its hand back, carries on.
  const seatBefore = (await status(pages[1]!)).seat;
  await pages[1]!.reload();
  await expect.poll(() => status(pages[1]!).then((s) => s.n), { timeout: 20_000 }).toBeGreaterThan(0);
  expect((await status(pages[1]!)).seat).toBe(seatBefore);
  await expect(pages[1]!.locator('.card.in-hand').first()).toBeVisible();

  // A latecomer is a spectator: sees the table, never a hand or the action bar.
  const late = await context.newPage();
  await late.goto(`/bigtwo/?room=${room}&uid=r4&name=Late&mute=1`);
  await expect.poll(() => status(late).then((s) => s.seat), { timeout: 20_000 }).toBe('public');
  await expect(late.locator('.seat')).toHaveCount(2);
  await expect(late.locator('.card.in-hand')).toHaveCount(0);
  await expect(late.locator('.action-bar')).toBeHidden();

  for (const p of [...pages, late]) await expect(p.locator('.overlay.results')).toBeVisible({ timeout: 180_000 });
  const st = await Promise.all([...pages, late].map(status));
  expect(st.every((s) => s.drift === 0)).toBe(true);
});

test('players who open the link before the host creates the table still get seats', async ({ context }) => {
  const room = `early-${Date.now()}`;
  const early: Page[] = [];
  for (const [uid, name] of [['e2', 'Ali'], ['e3', 'Mei']]) {
    const p = await context.newPage();
    await p.goto(`/bigtwo/?room=${room}&uid=${uid}&name=${name}&mute=1`);
    await expect(p.getByText('Waiting for the host to open this table…')).toBeVisible();
    early.push(p);
  }
  const host = await context.newPage();
  await host.goto(`/bigtwo/?room=${room}&uid=e1&name=Fahmi&mute=1&preview=0&create=1&allowed=e1,e2,e3`);
  for (const p of [host, ...early]) await expect(p.locator('.lobby-seat')).toHaveCount(3);
  for (const p of [host, ...early]) await p.getByRole('button', { name: 'Ready?' }).click();
  await host.getByRole('button', { name: 'Start' }).click();
  for (const p of early) await expect.poll(() => status(p).then((s) => s.seat), { timeout: 15_000 }).not.toBe('public');
  for (const p of early) await expect(p.locator('.card.in-hand').first()).toBeVisible();
});

test('the waiting room keeps its scroll and buttons through presence heartbeats', async ({ context }) => {
  const room = `ls-${Date.now()}`;
  const host = await context.newPage();
  await host.setViewportSize({ width: 360, height: 560 });
  await host.goto(`/bigtwo/?room=${room}&uid=s1&name=Host&mute=1&create=1&allowed=s1,s2`);
  const guest = await context.newPage();
  await guest.goto(`/bigtwo/?room=${room}&uid=s2&name=Guest&mute=1`);
  await expect(host.locator('.lobby-seat')).toHaveCount(2);
  // Scroll down to Start, and mark the button so a redraw would show.
  await host.evaluate(() => {
    const sheet = document.querySelector('.overlay.lobby .sheet') as HTMLElement;
    sheet.scrollTop = sheet.scrollHeight;
    (document.querySelector('.btn-start') as HTMLElement).dataset.mark = '1';
  });
  const top = await host.evaluate(() => (document.querySelector('.overlay.lobby .sheet') as HTMLElement).scrollTop);
  expect(top).toBeGreaterThan(0);
  await host.waitForTimeout(5000); // two or three heartbeats from each phone
  expect(await host.evaluate(() => (document.querySelector('.overlay.lobby .sheet') as HTMLElement).scrollTop)).toBe(top);
  expect(await host.evaluate(() => (document.querySelector('.btn-start') as HTMLElement).dataset.mark)).toBe('1');
  // A real change still redraws: the guest gets ready.
  await guest.getByRole('button', { name: 'Ready?' }).click();
  await expect(host.locator('.lobby-seat.ready')).toHaveCount(1);
  expect(await host.evaluate(() => (document.querySelector('.overlay.lobby .sheet') as HTMLElement).scrollTop)).toBe(top);
});
