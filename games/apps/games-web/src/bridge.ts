// Bridge between the game page and the EFOC Flutter app. JSON messages with
// a type field `t` (spec "Bridge protocol").
//   Android: Flutter calls window.efoc.receive(msg); the page answers with
//            flutter_inappwebview.callHandler('efoc', msg).
//   Web:     the page runs in an <iframe> on efoc.party and both sides use
//            postMessage, checking the other side's origin.
//   Alone:   no host app (dev server, Playwright) — Practice only.
// The page never holds a Firebase token: it only receives state and sends
// moves.

export const RENDERER_VERSION = '0.2.0';

export type HapticKind = 'light' | 'medium' | 'strong' | 'error';

export type ToGame =
  | {
      t: 'init';
      gameId: string;
      mySeat: number;
      isHost: boolean;
      isSpectator: boolean;
      practice?: boolean;
      players: { name: string; avatar: string; bot?: boolean }[];
      locale?: string;
      settings?: Record<string, unknown>;
      humour?: 'off' | 'mild' | 'spicy';
      insets?: { top: number; right: number; bottom: number; left: number };
      /** An online table: the page runs it on the bridge store (src/net/bridgeStore.ts). */
      online?: {
        room: string;
        uid: string;
        name: string;
        avatar: string;
        /** Server time minus local time, in ms. */
        clockOffset?: number;
        /** Set when this phone opens the table: the group and its member uids. */
        create?: { groupId: string; allowed: string[] };
      };
    }
  | { t: 'log'; entries: unknown[] }
  | { t: 'private'; data: unknown }
  | { t: 'snapshot'; n: number; state: unknown }
  | { t: 'rejected'; n: number; reason: string }
  | { t: 'pause' }
  | { t: 'resume' }
  | { t: 'intent'; seat: number; n: number; move: unknown }
  | { t: 'restore'; state: unknown }
  | { t: 'dbResult'; id: number; ok: boolean; value?: unknown; error?: string }
  | { t: 'dbValue'; id: number; value: unknown }
  | { t: 'dbChild'; id: number; key: string; value: unknown }
  | { t: 'dbClock'; offset: number };

export type FromGame =
  | { t: 'ready'; version: string }
  | { t: 'move'; n: number; move: unknown }
  | { t: 'output'; entry: unknown; private: Record<string, unknown>; snapshot?: unknown }
  | { t: 'vote'; yes?: boolean; start?: boolean }
  | { t: 'haptic'; kind: HapticKind }
  | { t: 'exit' }
  | { t: 'db'; id: number; op: 'get' | 'set' | 'update' | 'push' | 'onDisconnect' | 'watch' | 'watchChildren' | 'unwatch'; path?: string; value?: unknown; values?: Record<string, unknown> };

/** Origins allowed to embed the page and talk to it on the web. */
const PARENT_ORIGINS = [/^https:\/\/(www\.)?efoc\.party$/, /^http:\/\/localhost(:\d+)?$/, /^http:\/\/127\.0\.0\.1(:\d+)?$/];

const isAllowedOrigin = (o: string): boolean => PARENT_ORIGINS.some((r) => r.test(o));

interface InAppWebView {
  callHandler(name: string, ...args: unknown[]): Promise<unknown>;
}

type Listener = (msg: ToGame) => void;
const listeners: Listener[] = [];
let parentOrigin: string | null = null;

function deliver(msg: unknown): void {
  if (!msg || typeof msg !== 'object' || typeof (msg as { t?: unknown }).t !== 'string') return;
  for (const l of listeners) l(msg as ToGame);
}

export function onMessage(fn: Listener): void {
  listeners.push(fn);
}

export function inApp(): boolean {
  return !!(window as unknown as { flutter_inappwebview?: InAppWebView }).flutter_inappwebview || window.parent !== window;
}

export function send(msg: FromGame): void {
  const wv = (window as unknown as { flutter_inappwebview?: InAppWebView }).flutter_inappwebview;
  if (wv) {
    void wv.callHandler('efoc', msg);
    return;
  }
  if (window.parent !== window && parentOrigin) window.parent.postMessage(msg, parentOrigin);
}

export function haptic(kind: HapticKind): void {
  if (inApp()) send({ t: 'haptic', kind });
  else if ('vibrate' in navigator) {
    const ms = { light: 8, medium: 18, strong: [30, 40, 30], error: [12, 30, 12] }[kind];
    try {
      navigator.vibrate(ms);
    } catch {
      /* not allowed before a tap */
    }
  }
}

export function startBridge(): void {
  (window as unknown as { efoc: { receive: (m: unknown) => void } }).efoc = { receive: deliver };
  if (window.parent !== window) {
    window.addEventListener('message', (e: MessageEvent) => {
      if (e.source !== window.parent || !isAllowedOrigin(e.origin)) return;
      parentOrigin = e.origin;
      deliver(e.data);
    });
    // The first message from the app tells us its origin; until then we
    // announce readiness to any allowed origin by trying each known one.
    for (const o of ['https://efoc.party', 'https://www.efoc.party']) {
      try {
        window.parent.postMessage({ t: 'ready', version: RENDERER_VERSION }, o);
      } catch {
        /* wrong origin: ignored by the browser */
      }
    }
  }
  send({ t: 'ready', version: RENDERER_VERSION });
}
