// Table sounds. Card and UI sounds are Kenney samples (CC0, see
// assets/LICENSES.md); the big moments (bass hit, fanfare, sad trombone,
// chime) are still synthesised. If a sample can't load or decode (for
// example Ogg on an older iPhone), its slot falls back to the synth.
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
  void loadSamples(ctx);
}

const SAMPLE_NAMES = ['place-1', 'place-2', 'place-3', 'place-4', 'slide-1', 'slide-2', 'shuffle', 'fan', 'click', 'switch', 'rollover'];
const samples = new Map<string, AudioBuffer>();

async function loadSamples(ac: AudioContext): Promise<void> {
  await Promise.all(
    SAMPLE_NAMES.map(async (n) => {
      try {
        const res = await fetch(new URL(`../sounds/${n}.ogg`, location.href));
        if (!res.ok) return;
        samples.set(n, await ac.decodeAudioData(await res.arrayBuffer()));
      } catch {
        /* keep the synth fallback */
      }
    }),
  );
}

/** Plays a sample; returns false if it isn't available. */
function sample(name: string, gain = 0.8, rate = 1, delay = 0): boolean {
  const r = ready();
  const buf = samples.get(name);
  if (!r || !buf) return false;
  const src = r.ac.createBufferSource();
  src.buffer = buf;
  src.playbackRate.value = rate;
  const g = r.ac.createGain();
  g.gain.value = gain;
  src.connect(g).connect(r.out);
  src.start(r.ac.currentTime + delay / 1000);
  return true;
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
  click: () => sample('click', 0.6) || tone(1800, 40, 'square', 0.05),
  /** T1: a card lands. `step` raises the pitch for each card in a multi-card play. */
  thud: (step = 0) => {
    if (sample(`place-${(step % 4) + 1}`, 0.9, Math.pow(1.06, step))) return;
    noise(90, 0.5, 900, 300);
    tone(140 * Math.pow(1.12, step), 120, 'sine', 0.35);
  },
  /** A card flying in from another seat. */
  slide: () => sample('slide-1', 0.7) || noise(160, 0.25, 600, 1800),
  deal: () => sample('shuffle', 0.8) || [0, 1, 2, 3].forEach((i) => noise(80, 0.3, 900, 300, i * 70)),
  sort: () => sample('fan', 0.7) || tone(900, 60, 'triangle', 0.06),
  toggle: () => sample('switch', 0.6) || tone(1400, 40, 'square', 0.04),
  pass: () => sample('rollover', 0.7, 0.8) || tone(420, 90, 'triangle', 0.12, 300),
  /** Tension while a legendary card flies up. */
  rise: () => {
    tone(196, 950, 'sawtooth', 0.05, 880);
    tone(294, 950, 'triangle', 0.06, 1320);
  },
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
