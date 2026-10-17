// The Jester mascot: an original character drawn for EFOC as inline SVG, so
// it scales crisply and costs no download. Moods switch eyes and mouth; CSS
// (styles.css, .jester-*) moves him: idle bob, talking mouth, laughing
// shake, shocked jump, smug tilt, sad droop, cheering hop. A Noto animated
// emoji pops beside him for the reaction.

import type { Mood } from './jester';

export const JESTER_SVG = `
<svg class="jester-svg" viewBox="0 0 120 130" aria-hidden="true">
  <g class="j-body">
    <!-- collar -->
    <path class="j-collar" d="M22 104 L32 92 L42 104 L52 92 L60 104 L68 92 L78 104 L88 92 L98 104 L92 118 Q60 128 28 118 Z" fill="#7c3aed" stroke="#3b0764" stroke-width="2.5" stroke-linejoin="round"/>
    <circle cx="32" cy="104" r="3.4" fill="#facc15"/><circle cx="60" cy="108" r="3.4" fill="#facc15"/><circle cx="88" cy="104" r="3.4" fill="#facc15"/>
    <!-- head -->
    <ellipse cx="60" cy="72" rx="30" ry="29" fill="#fde7c9" stroke="#3b0764" stroke-width="2.5"/>
    <!-- hat: three floppy points with bells -->
    <g class="j-hat">
      <path d="M31 58 Q14 30 6 18 Q26 26 42 44 Z" fill="#a855f7" stroke="#3b0764" stroke-width="2.5" stroke-linejoin="round"/>
      <path d="M44 46 Q52 14 60 4 Q68 14 76 46 Z" fill="#facc15" stroke="#3b0764" stroke-width="2.5" stroke-linejoin="round"/>
      <path d="M89 58 Q106 30 114 18 Q94 26 78 44 Z" fill="#22c55e" stroke="#3b0764" stroke-width="2.5" stroke-linejoin="round"/>
      <path d="M28 60 Q60 38 92 60 Q60 52 28 60 Z" fill="#3b0764"/>
      <circle class="j-bell j-bell-l" cx="6" cy="18" r="5.5" fill="#facc15" stroke="#3b0764" stroke-width="2"/>
      <circle class="j-bell j-bell-m" cx="60" cy="5" r="5.5" fill="#a855f7" stroke="#3b0764" stroke-width="2"/>
      <circle class="j-bell j-bell-r" cx="114" cy="18" r="5.5" fill="#facc15" stroke="#3b0764" stroke-width="2"/>
    </g>
    <!-- cheeks -->
    <circle cx="40" cy="82" r="5" fill="#fb7185" opacity="0.55"/><circle cx="80" cy="82" r="5" fill="#fb7185" opacity="0.55"/>
    <!-- eyes per mood -->
    <g class="j-eyes j-eyes-open"><circle cx="48" cy="70" r="4.2" fill="#1f1235"/><circle cx="72" cy="70" r="4.2" fill="#1f1235"/><circle cx="49.5" cy="68.5" r="1.4" fill="#fff"/><circle cx="73.5" cy="68.5" r="1.4" fill="#fff"/></g>
    <g class="j-eyes j-eyes-happy"><path d="M42 71 Q48 64 54 71" fill="none" stroke="#1f1235" stroke-width="3" stroke-linecap="round"/><path d="M66 71 Q72 64 78 71" fill="none" stroke="#1f1235" stroke-width="3" stroke-linecap="round"/></g>
    <g class="j-eyes j-eyes-wide"><circle cx="48" cy="69" r="6.5" fill="#fff" stroke="#1f1235" stroke-width="2"/><circle cx="72" cy="69" r="6.5" fill="#fff" stroke="#1f1235" stroke-width="2"/><circle cx="48" cy="69" r="2.6" fill="#1f1235"/><circle cx="72" cy="69" r="2.6" fill="#1f1235"/></g>
    <g class="j-eyes j-eyes-smug"><path d="M42 70 L54 70" stroke="#1f1235" stroke-width="3" stroke-linecap="round"/><path d="M66 70 L78 70" stroke="#1f1235" stroke-width="3" stroke-linecap="round"/><path d="M43 66 Q48 63 54 66" fill="none" stroke="#1f1235" stroke-width="2" stroke-linecap="round"/><path d="M66 63 Q72 60 78 64" fill="none" stroke="#1f1235" stroke-width="2" stroke-linecap="round"/></g>
    <g class="j-eyes j-eyes-sad"><circle cx="48" cy="72" r="3.6" fill="#1f1235"/><circle cx="72" cy="72" r="3.6" fill="#1f1235"/><path d="M41 64 L54 67" stroke="#1f1235" stroke-width="2.4" stroke-linecap="round"/><path d="M79 64 L66 67" stroke="#1f1235" stroke-width="2.4" stroke-linecap="round"/></g>
    <!-- mouths per mood -->
    <g class="j-mouth j-mouth-talk"><path class="j-lip" d="M48 86 Q60 96 72 86 Q60 90 48 86 Z" fill="#7f1d1d" stroke="#1f1235" stroke-width="2.2" stroke-linejoin="round"/></g>
    <g class="j-mouth j-mouth-laugh"><path d="M44 84 Q60 104 76 84 Z" fill="#7f1d1d" stroke="#1f1235" stroke-width="2.4" stroke-linejoin="round"/><path d="M50 86 Q60 92 70 86" fill="#fff"/></g>
    <g class="j-mouth j-mouth-shock"><ellipse cx="60" cy="90" rx="7" ry="9" fill="#7f1d1d" stroke="#1f1235" stroke-width="2.4"/></g>
    <g class="j-mouth j-mouth-smug"><path d="M48 88 Q62 94 74 84" fill="none" stroke="#1f1235" stroke-width="3" stroke-linecap="round"/></g>
    <g class="j-mouth j-mouth-sad"><path d="M48 92 Q60 82 72 92" fill="none" stroke="#1f1235" stroke-width="3" stroke-linecap="round"/></g>
    <g class="j-mouth j-mouth-cheer"><path d="M46 84 Q60 100 74 84 Z" fill="#7f1d1d" stroke="#1f1235" stroke-width="2.4" stroke-linejoin="round"/></g>
  </g>
</svg>`;

/** Eye set per mood (mouths match the mood name). */
export const EYES: Record<Mood, string> = {
  talk: 'open',
  laugh: 'happy',
  shock: 'wide',
  smug: 'smug',
  sad: 'sad',
  cheer: 'happy',
};

// ------------------------------------------------------- emoji reactions

type LottiePlayer = {
  loadAnimation(o: { container: Element; renderer: 'svg'; loop: boolean; autoplay: boolean; animationData: unknown }): { destroy(): void };
};

let lottie: Promise<LottiePlayer | null> | null = null;
const cache = new Map<string, Promise<unknown>>();

function player(): Promise<LottiePlayer | null> {
  lottie ??= import('lottie-web/build/player/lottie_light').then(
    (m) => (m as unknown as { default: LottiePlayer }).default,
    () => null,
  );
  return lottie;
}

/** Plays a Noto animated emoji in `box` until the returned stop is called. */
export function playEmoji(box: HTMLElement, name: string): () => void {
  let anim: { destroy(): void } | null = null;
  let stopped = false;
  const data = cache.get(name) ?? fetch(new URL(`../emoji/${name}.json`, location.href)).then((r) => (r.ok ? r.json() : null)).catch(() => null);
  cache.set(name, data);
  void Promise.all([player(), data]).then(([p, json]) => {
    if (stopped || !p || !json) return;
    anim = p.loadAnimation({ container: box, renderer: 'svg', loop: true, autoplay: true, animationData: json });
  });
  return () => {
    stopped = true;
    anim?.destroy();
    box.innerHTML = '';
  };
}

/** Warms the cache so the first reaction appears without a gap. */
export function preloadEmoji(names: string[]): void {
  void player();
  for (const n of names) {
    if (!cache.has(n)) cache.set(n, fetch(new URL(`../emoji/${n}.json`, location.href)).then((r) => (r.ok ? r.json() : null)).catch(() => null));
  }
}
