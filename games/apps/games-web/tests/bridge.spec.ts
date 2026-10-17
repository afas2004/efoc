// The page inside EFOC: a stand-in for the Flutter app (lib/games/) hosts two
// "phones" as iframes, answers their {t:'db'} bridge messages from one
// in-memory database, and only lets them touch rooms/{id}, presence/{id} and
// chat/{id}, like GameSession does. No LocalStore and no Firebase token.
import { expect, test, type Page } from '@playwright/test';

test.use({ viewport: { width: 900, height: 860 } });

const HARNESS = `<!doctype html><meta charset="utf-8"><title>bridge harness</title>
<style>body{margin:0;display:flex}iframe{width:450px;height:844px;border:0}</style>
<body><script>
const db = { root: {} };
const subs = []; // {frame, id, path, kind, seen, last}
const disconnect = new Map(); // frame -> {path: value}
const errors = [];
const parts = (p) => p.split('/').filter(Boolean);
const isObj = (v) => v && typeof v === 'object' && !Array.isArray(v);
function resolveTs(v) {
  if (isObj(v) && v['.sv'] === 'timestamp') return Date.now();
  if (Array.isArray(v)) return v.map(resolveTs);
  if (isObj(v)) return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, resolveTs(x)]));
  return v;
}
function read(path) {
  let n = db.root;
  for (const k of parts(path)) { if (!isObj(n)) return null; n = n[k]; if (n === undefined) return null; }
  return n ?? null;
}
function prune(v) {
  if (!isObj(v)) return v;
  for (const k of Object.keys(v)) { v[k] = prune(v[k]); if (v[k] === null || (isObj(v[k]) && !Object.keys(v[k]).length)) delete v[k]; }
  return v;
}
function write(path, value) {
  value = resolveTs(value);
  if (Array.isArray(value)) value = Object.fromEntries(value.map((x, i) => [String(i), x]));
  const ks = parts(path); let n = db.root;
  ks.forEach((k, i) => {
    if (i === ks.length - 1) { if (value === null) delete n[k]; else n[k] = JSON.parse(JSON.stringify(value)); }
    else { if (!isObj(n[k])) n[k] = {}; n = n[k]; }
  });
  prune(db.root);
}
let pushN = 0;
const pushKey = () => Date.now().toString(36).padStart(9, '0') + (pushN++).toString(36).padStart(5, '0');
function allowedPath(room, path) {
  const [top, id] = parts(path);
  return ['rooms', 'presence', 'chat'].includes(top) && id === room;
}
function fire() {
  for (const s of subs) {
    const v = read(s.path);
    if (s.kind === 'watch') {
      const j = JSON.stringify(v);
      if (j !== s.last) { s.last = j; s.frame.post({ t: 'dbValue', id: s.id, value: v }); }
    } else if (isObj(v)) {
      for (const k of Object.keys(v).sort()) if (!s.seen.has(k)) { s.seen.add(k); s.frame.post({ t: 'dbChild', id: s.id, key: k, value: v[k] }); }
    }
  }
}
const frames = [];
function addPhone(o) {
  const el = document.createElement('iframe');
  el.src = '/bigtwo/?' + o.query;
  const frame = { el, uid: o.uid, room: o.room, post: (m) => el.contentWindow && el.contentWindow.postMessage(m, location.origin) };
  frames.push(frame);
  disconnect.set(frame, {});
  el.addEventListener('load', () => frame.post({ t: 'init', gameId: 'bigtwo', mySeat: 0, isHost: false, isSpectator: false, players: [],
    online: { room: o.room, uid: o.uid, name: o.name, avatar: o.avatar, clockOffset: 0, create: o.create } }));
  document.body.appendChild(el);
}
function dropPhone(i) {
  const f = frames[i];
  for (const [p, v] of Object.entries(disconnect.get(f))) write(p, v);
  subs.splice(0, subs.length, ...subs.filter((s) => s.frame !== f));
  f.el.remove();
  fire();
}
window.addEventListener('message', (e) => {
  const f = frames.find((x) => x.el.contentWindow === e.source);
  if (!f || e.origin !== location.origin) return;
  const m = e.data;
  if (!m || m.t !== 'db') return;
  const reply = (ok, value, error) => f.post({ t: 'dbResult', id: m.id, ok, value, error });
  const paths = m.op === 'update' ? Object.keys(m.values || {}) : m.op === 'unwatch' ? [] : [m.path];
  if (paths.some((p) => typeof p !== 'string' || !allowedPath(f.room, p))) {
    errors.push(m.op + ' ' + paths.join(','));
    if (!['watch', 'watchChildren'].includes(m.op)) reply(false, null, 'path not allowed');
    return;
  }
  switch (m.op) {
    case 'get': reply(true, read(m.path)); break;
    case 'set': write(m.path, m.value); reply(true, null); fire(); break;
    case 'update': for (const [p, v] of Object.entries(m.values)) write(p, v); reply(true, null); fire(); break;
    case 'push': { const k = pushKey(); write(m.path + '/' + k, m.value); reply(true, k); fire(); break; }
    case 'onDisconnect': disconnect.get(f)[m.path] = m.value; reply(true, null); break;
    case 'watch': case 'watchChildren': subs.push({ frame: f, id: m.id, path: m.path, kind: m.op, seen: new Set(), last: undefined }); fire(); break;
    case 'unwatch': subs.splice(0, subs.length, ...subs.filter((s) => !(s.frame === f && s.id === m.id))); break;
  }
});
window.harness = { addPhone, dropPhone, db, errors, read };
</script></body>`;

async function openHarness(page: Page): Promise<void> {
  await page.route('**/harness.html', (r) => r.fulfill({ contentType: 'text/html', body: HARNESS }));
  await page.goto('/harness.html');
}

test('two phones and a bot play a match through the app bridge', async ({ page }) => {
  await openHarness(page);
  const room = `br-${Date.now()}`;
  const q = 'mute=1&turn=8000&preview=0&autopilot=1';
  await page.evaluate(
    ({ room, q }) => {
      const h = (window as any).harness;
      h.addPhone({ room, uid: 'b1', name: 'Host', avatar: '🦁', query: q, create: { groupId: 'g1', allowed: ['b1', 'b2'] } });
      h.addPhone({ room, uid: 'b2', name: 'Guest', avatar: '🐸', query: q });
    },
    { room, q },
  );
  const phones = [page.frameLocator('iframe').nth(0), page.frameLocator('iframe').nth(1)];
  for (const f of phones) await expect(f.locator('.lobby-seat')).toHaveCount(2);
  await phones[0]!.getByRole('button', { name: '+ Add bot' }).click();
  for (const f of phones) await expect(f.locator('.lobby-seat')).toHaveCount(3);
  for (const f of phones) await f.getByRole('button', { name: 'Ready?' }).click();
  await phones[0]!.getByRole('button', { name: 'Start' }).click();
  for (const f of phones) await expect(f.locator('.overlay.results')).toBeVisible({ timeout: 90_000 });

  const db = await page.evaluate((room) => {
    const h = (window as any).harness;
    return { errors: h.errors, allowed: h.read(`rooms/${room}/allowed`), presence: h.read(`presence/${room}`), host: h.read(`rooms/${room}/meta/hostUid`), results: !!h.read(`rooms/${room}/results`) };
  }, room);
  expect(db.errors).toEqual([]); // the page only touched its own room
  expect(db.allowed).toEqual({ b1: true, b2: true });
  expect(db.host).toBe('b1');
  expect(db.results).toBe(true);
  expect(Object.keys(db.presence).sort()).toEqual(['b1', 'b2']);

  // Closing a phone runs its onDisconnect write, with the server's time.
  const before = Date.now();
  await page.evaluate(() => (window as any).harness.dropPhone(1));
  const p2 = await page.evaluate((room) => (window as any).harness.read(`presence/${room}/b2`), room);
  expect(p2.online).toBe(false);
  expect(p2.lastSeen).toBeGreaterThanOrEqual(before);
});
