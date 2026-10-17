// The room database the page talks to. It mirrors the few Realtime Database
// operations the game needs, so the same game code runs on:
//   - BridgeStore: inside EFOC. Flutter proxies each call to Firebase
//     Realtime Database for this room's paths only; the page never holds a
//     Firebase token, and the security rules decide every read and write.
//   - LocalStore: in a plain browser, for development and the multi-player
//     Playwright tests. It keeps the "database" in localStorage, shared by
//     every tab of the same origin, and enforces no rules.
// Paths use the data model in docs/spec.md ("Realtime Database data model").

export type Json = null | boolean | number | string | Json[] | { [key: string]: Json };
export type Unsubscribe = () => void;

/** Server time at the moment of the write (Firebase's placeholder; LocalStore fills in Date.now()). */
export const TIMESTAMP: Json = { '.sv': 'timestamp' };

const isTimestamp = (v: Json): boolean => isPlainObject(v) && Object.keys(v).length === 1 && v['.sv'] === 'timestamp';

function resolveTimestamps(v: Json, now: number): Json {
  if (isTimestamp(v)) return now;
  if (Array.isArray(v)) return v.map((x) => resolveTimestamps(x, now));
  if (isPlainObject(v)) return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, resolveTimestamps(x, now)]));
  return v;
}

export interface RoomStore {
  readonly uid: string;
  /** Server clock in ms (Date.now() locally; server offset on Firebase). */
  now(): number;
  get(path: string): Promise<Json>;
  /** Calls back with the value now and after every change under `path`. */
  watch(path: string, cb: (value: Json) => void): Unsubscribe;
  /** Calls back once per child of `path`, in key order, now and as new ones arrive. */
  watchChildren(path: string, cb: (key: string, value: Json) => void): Unsubscribe;
  set(path: string, value: Json): Promise<void>;
  /** Multi-path write: `{ 'rooms/x/log/000001': {...}, 'rooms/x/intents/abc': null }`. */
  update(values: Record<string, Json>): Promise<void>;
  /** Adds a child with a new unique, time-ordered key and returns the key. */
  push(path: string, value: Json): Promise<string>;
  /** Writes `value` at `path` when this page goes away. */
  onDisconnect(path: string, value: Json): void;
}

// ------------------------------------------------------------ LocalStore

const PREFIX = 'efoc-db:';

function isPlainObject(v: unknown): v is Record<string, Json> {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}

let pushCounter = 0;
function pushKey(now: number): string {
  pushCounter = (pushCounter + 1) % 1e6;
  return `${now.toString(36).padStart(9, '0')}${pushCounter.toString(36).padStart(4, '0')}${Math.random().toString(36).slice(2, 6)}`;
}

export class LocalStore implements RoomStore {
  private listeners = new Set<{ path: string; fire: () => void }>();
  private disconnectWrites: Record<string, Json> = {};

  constructor(readonly uid: string) {
    window.addEventListener('storage', (e) => {
      if (e.key && e.key.startsWith(PREFIX)) this.changed(e.key.slice(PREFIX.length));
    });
    window.addEventListener('pagehide', () => this.runDisconnect());
  }

  now(): number {
    return Date.now();
  }

  /** Every stored key that is `path`, under it, or above it. */
  private related(path: string): { above: string | null; atOrBelow: string[] } {
    let above: string | null = null;
    const atOrBelow: string[] = [];
    for (let i = 0; i < localStorage.length; i++) {
      const k = localStorage.key(i);
      if (!k || !k.startsWith(PREFIX)) continue;
      const p = k.slice(PREFIX.length);
      if (p === path || p.startsWith(`${path}/`)) atOrBelow.push(p);
      else if (path.startsWith(`${p}/`) && (!above || p.length > above.length)) above = p;
    }
    return { above, atOrBelow };
  }

  private load(key: string): Json {
    const raw = localStorage.getItem(PREFIX + key);
    return raw === null ? null : (JSON.parse(raw) as Json);
  }

  // Each written path is ONE localStorage key holding its whole value.
  // Chrome syncs localStorage to other tabs key by key, so a value split
  // across keys could be seen half-written; one key is all-or-nothing.
  private read(path: string): Json {
    const { above, atOrBelow } = this.related(path);
    if (above) {
      let v: Json = this.load(above);
      for (const part of path.slice(above.length + 1).split('/')) {
        if (!isPlainObject(v)) return null;
        v = v[part] ?? null;
      }
      return v;
    }
    if (atOrBelow.length === 0) return null;
    let root: Json = atOrBelow.includes(path) ? this.load(path) : {};
    for (const k of atOrBelow.sort()) {
      if (k === path) continue;
      if (!isPlainObject(root)) root = {};
      const rel = k.slice(path.length + 1).split('/');
      let node = root as Record<string, Json>;
      rel.forEach((part, i) => {
        if (i === rel.length - 1) node[part] = this.load(k);
        else {
          if (!isPlainObject(node[part])) node[part] = {};
          node = node[part] as Record<string, Json>;
        }
      });
    }
    return root;
  }

  private write(path: string, raw: Json): void {
    const value = resolveTimestamps(raw, Date.now());
    const { above, atOrBelow } = this.related(path);
    if (above) {
      // Edit inside the ancestor's value, keeping it one key.
      const root = this.load(above);
      const obj: Record<string, Json> = isPlainObject(root) ? root : {};
      const parts = path.slice(above.length + 1).split('/');
      let node = obj;
      parts.forEach((part, i) => {
        if (i === parts.length - 1) {
          if (value === null) delete node[part];
          else node[part] = value;
        } else {
          if (!isPlainObject(node[part])) node[part] = {};
          node = node[part] as Record<string, Json>;
        }
      });
      localStorage.setItem(PREFIX + above, JSON.stringify(obj));
      return;
    }
    for (const k of atOrBelow) localStorage.removeItem(PREFIX + k);
    if (value !== null) localStorage.setItem(PREFIX + path, JSON.stringify(value));
  }

  private changed(path: string): void {
    for (const l of [...this.listeners]) {
      if (path === l.path || path.startsWith(`${l.path}/`) || l.path.startsWith(`${path}/`)) l.fire();
    }
  }

  async get(path: string): Promise<Json> {
    return this.read(path);
  }

  watch(path: string, cb: (value: Json) => void): Unsubscribe {
    let last = '';
    const fire = (): void => {
      const v = this.read(path);
      const s = JSON.stringify(v);
      if (s === last) return;
      last = s;
      cb(v);
    };
    const l = { path, fire };
    this.listeners.add(l);
    queueMicrotask(fire);
    return () => this.listeners.delete(l);
  }

  watchChildren(path: string, cb: (key: string, value: Json) => void): Unsubscribe {
    const seen = new Set<string>();
    const fire = (): void => {
      const v = this.read(path);
      if (!isPlainObject(v)) return;
      for (const k of Object.keys(v).sort()) {
        if (seen.has(k)) continue;
        seen.add(k);
        cb(k, v[k]!);
      }
    };
    const l = { path, fire };
    this.listeners.add(l);
    queueMicrotask(fire);
    return () => this.listeners.delete(l);
  }

  async set(path: string, value: Json): Promise<void> {
    this.write(path, value);
    this.changed(path);
  }

  async update(values: Record<string, Json>): Promise<void> {
    for (const [p, v] of Object.entries(values)) this.write(p, v);
    for (const p of Object.keys(values)) this.changed(p);
  }

  async push(path: string, value: Json): Promise<string> {
    const key = pushKey(this.now());
    await this.set(`${path}/${key}`, value);
    return key;
  }

  onDisconnect(path: string, value: Json): void {
    this.disconnectWrites[path] = value;
  }

  /** Runs the onDisconnect writes now (page closing, or a test forcing it). */
  runDisconnect(): void {
    const w = this.disconnectWrites;
    this.disconnectWrites = {};
    for (const [p, v] of Object.entries(w)) this.write(p, v);
  }

  /** Development helper: wipes every room. */
  static clearAll(): void {
    const keys: string[] = [];
    for (let i = 0; i < localStorage.length; i++) {
      const k = localStorage.key(i);
      if (k?.startsWith(PREFIX)) keys.push(k);
    }
    keys.forEach((k) => localStorage.removeItem(k));
  }
}
