// Placeholder sounds synthesised with Web Audio, so the table has a voice
// before the Kenney packs land (see assets/LICENSES.md). Each function is
// one named slot; swapping in a sample later changes only this file.
// Audio starts after the first tap, as browsers and the WebView require.

let ctx: AudioContext | null = null;
let master: GainNode | null = null;
let muted = false;

export function unlockAudio(): void {
  if (ctx) {
    void ctx.resume();
    return;
  }
  const AC = (window as unknown as { AudioContext?: typeof AudioContext; webkitAudioContext?: typeof AudioContext })
    .AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
  if (!AC) return;
  ctx = new AC();
  master = ctx.createGain();
  master.gain.value = 0.5;
  master.connect(ctx.destination);
}

export function setMuted(m: boolean): void {
  muted = m;
}

function ready(): { ac: AudioContext; out: GainNode } | null {
  if (!ctx || !master || muted || ctx.state !== 'running') return null;
  return { ac: ctx, out: master };
}

function tone(freq: number, ms: number, type: OscillatorType, gain: number, slideTo?: number, delay = 0): void {
  const r = ready();
  if (!r) return;
  const t0 = r.ac.currentTime + delay / 1000;
  const osc = r.ac.createOscillator();
  const g = r.ac.createGain();
  osc.type = type;
  osc.frequency.setValueAtTime(freq, t0);
  if (slideTo) osc.frequency.exponentialRampToValueAtTime(slideTo, t0 + ms / 1000);
  g.gain.setValueAtTime(0.0001, t0);
  g.gain.exponentialRampToValueAtTime(gain, t0 + 0.008);
  g.gain.exponentialRampToValueAtTime(0.0001, t0 + ms / 1000);
  osc.connect(g).connect(r.out);
  osc.start(t0);
  osc.stop(t0 + ms / 1000 + 0.02);
}

function noise(ms: number, gain: number, from: number, to: number, delay = 0): void {
  const r = ready();
  if (!r) return;
  const t0 = r.ac.currentTime + delay / 1000;
  const len = Math.ceil((r.ac.sampleRate * ms) / 1000);
  const buf = r.ac.createBuffer(1, len, r.ac.sampleRate);
  const data = buf.getChannelData(0);
  for (let i = 0; i < len; i++) data[i] = (Math.random() * 2 - 1) * (1 - i / len);
  const src = r.ac.createBufferSource();
  src.buffer = buf;
  const filter = r.ac.createBiquadFilter();
  filter.type = 'bandpass';
  filter.frequency.setValueAtTime(from, t0);
  filter.frequency.exponentialRampToValueAtTime(to, t0 + ms / 1000);
  const g = r.ac.createGain();
  g.gain.value = gain;
  src.connect(filter).connect(g).connect(r.out);
  src.start(t0);
}

export const sound = {
  /** T0: select, sort. */
  click: () => tone(1800, 40, 'square', 0.05),
  /** T1: a card lands. `step` raises the pitch for each card in a multi-card play. */
  thud: (step = 0) => {
    noise(90, 0.5, 900, 300);
    tone(140 * Math.pow(1.12, step), 120, 'sine', 0.35);
  },
  pass: () => tone(420, 90, 'triangle', 0.12, 300),
  /** T2 */
  whoosh: () => noise(320, 0.35, 400, 3200),
  chime: () => {
    tone(880, 260, 'sine', 0.18);
    tone(1320, 320, 'sine', 0.12, undefined, 70);
  },
  /** T3 */
  bass: () => {
    tone(70, 600, 'sine', 0.6, 40);
    noise(400, 0.4, 200, 60);
  },
  /** T4 */
  fanfare: () => [523, 659, 784, 1047].forEach((f, i) => tone(f, 260, 'triangle', 0.2, undefined, i * 130)),
  trombone: () => [392, 370, 349, 294].forEach((f, i) => tone(f, i === 3 ? 700 : 300, 'sawtooth', 0.08, i === 3 ? 260 : undefined, i * 320)),
  /** Timer tick in the last 5 s. */
  tick: () => tone(1200, 30, 'square', 0.04),
  error: () => tone(180, 160, 'square', 0.08, 120),
};
