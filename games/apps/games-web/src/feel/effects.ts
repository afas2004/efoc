// Visual effects for the moment tiers. Only `transform` and `opacity`
// animate. Shake strength and length come from the tier, never random.
// Reduced motion keeps text, sound and haptics, and swaps motion for a fade.

import type { MomentCtx } from './tiers';

export type ColourRole = 'good' | 'danger' | 'info' | 'power' | 'turn' | 'neutral';

const SHAKE_PX = { small: 4, big: 12 } as const;

export function shake(el: HTMLElement, size: keyof typeof SHAKE_PX, ctx: MomentCtx): void {
  if (ctx.reduced) return;
  const px = SHAKE_PX[size];
  const ms = Math.min(ctx.ms, size === 'big' ? 450 : 220);
  const frames: Keyframe[] = [];
  const steps = 8;
  for (let i = 0; i <= steps; i++) {
    const decay = 1 - i / steps;
    const dx = (i % 2 ? 1 : -1) * px * decay;
    const dy = (i % 3 ? -1 : 1) * px * 0.5 * decay;
    frames.push({ transform: `translate(${dx}px, ${dy}px)` });
  }
  const anim = el.animate(frames, { duration: ms, easing: 'ease-out' });
  ctx.onEnd(() => anim.cancel());
}

/** A pop-up word or banner. Big banners centre on the table and dim it. */
export function banner(layer: HTMLElement, text: string, role: ColourRole, size: 'pop' | 'banner', ctx: MomentCtx, at?: { x: number; y: number }): HTMLElement {
  const el = document.createElement('div');
  el.className = `fx-${size} role-${role}`;
  el.textContent = text;
  el.setAttribute('role', 'status');
  if (at) {
    el.style.left = `${at.x}px`;
    el.style.top = `${at.y}px`;
  }
  layer.appendChild(el);
  const frames: Keyframe[] = ctx.reduced
    ? [{ opacity: 0 }, { opacity: 1, offset: 0.15 }, { opacity: 1, offset: 0.8 }, { opacity: 0 }]
    : size === 'banner'
      ? [
          { opacity: 0, transform: 'translate(-50%, -50%) scale(0.4) rotate(-6deg)' },
          { opacity: 1, transform: 'translate(-50%, -50%) scale(1.12) rotate(2deg)', offset: 0.18 },
          { opacity: 1, transform: 'translate(-50%, -50%) scale(1) rotate(0deg)', offset: 0.3 },
          { opacity: 1, transform: 'translate(-50%, -50%) scale(1)', offset: 0.85 },
          { opacity: 0, transform: 'translate(-50%, -50%) scale(1.1)' },
        ]
      : [
          { opacity: 0, transform: 'translate(-50%, 0) scale(0.6)' },
          { opacity: 1, transform: 'translate(-50%, -14px) scale(1.08)', offset: 0.25 },
          { opacity: 1, transform: 'translate(-50%, -20px) scale(1)', offset: 0.75 },
          { opacity: 0, transform: 'translate(-50%, -28px) scale(1)' },
        ];
  // The bounce belongs to the entrance only. Easing the whole timeline with
  // an overshoot curve would rush into the fade-out and hide the word early.
  frames[0]!.easing = 'cubic-bezier(.2,.9,.3,1.2)';
  el.animate(frames, { duration: ctx.ms, easing: 'linear', fill: 'forwards' });
  ctx.onEnd(() => el.remove());
  return el;
}

/** Dims the table under a T3 banner. Never takes pointer events. */
export function dim(layer: HTMLElement, ctx: MomentCtx): void {
  const el = document.createElement('div');
  el.className = 'fx-dim';
  layer.appendChild(el);
  el.animate([{ opacity: 0 }, { opacity: 1, offset: 0.12 }, { opacity: 1, offset: 0.85 }, { opacity: 0 }], {
    duration: ctx.ms,
    fill: 'forwards',
  });
  ctx.onEnd(() => el.remove());
}

const ROLE_COLOURS: Record<ColourRole, string[]> = {
  good: ['#FACC15', '#FDE68A', '#F59E0B'],
  danger: ['#EF4444', '#F97316', '#FCA5A5'],
  info: ['#3B82F6', '#93C5FD'],
  power: ['#A855F7', '#D8B4FE'],
  turn: ['#22C55E', '#86EFAC'],
  neutral: ['#FFFFFF', '#E5E7EB'],
};

/** A burst of particles from a point. Skipped under reduced motion. */
export function burst(layer: HTMLElement, x: number, y: number, count: number, role: ColourRole, ctx: MomentCtx, spread = 140): void {
  if (ctx.reduced) return;
  const colours = ROLE_COLOURS[role];
  for (let i = 0; i < count; i++) {
    const p = document.createElement('div');
    p.className = 'fx-particle';
    p.style.left = `${x}px`;
    p.style.top = `${y}px`;
    p.style.background = colours[i % colours.length]!;
    layer.appendChild(p);
    const angle = (i / count) * Math.PI * 2 + (i % 3) * 0.2;
    const dist = spread * (0.5 + ((i * 37) % 50) / 100);
    const anim = p.animate(
      [
        { transform: 'translate(-50%, -50%) scale(1)', opacity: 1 },
        { transform: `translate(calc(-50% + ${Math.cos(angle) * dist}px), calc(-50% + ${Math.sin(angle) * dist}px)) scale(0.3)`, opacity: 0 },
      ],
      { duration: Math.min(ctx.ms, 900), easing: 'cubic-bezier(.1,.8,.3,1)', fill: 'forwards' },
    );
    ctx.onEnd(() => {
      anim.cancel();
      p.remove();
    });
  }
}

/** Confetti for the winner on the results screen. */
export function confetti(layer: HTMLElement, width: number, ctx: MomentCtx): void {
  if (ctx.reduced) return;
  const colours = [...ROLE_COLOURS.good, ...ROLE_COLOURS.power, '#22C55E', '#3B82F6'];
  for (let i = 0; i < 48; i++) {
    const p = document.createElement('div');
    p.className = 'fx-confetti';
    p.style.left = `${(i * 97) % width}px`;
    p.style.background = colours[i % colours.length]!;
    layer.appendChild(p);
    const fall = 500 + ((i * 53) % 400);
    const anim = p.animate(
      [
        { transform: `translateY(-20px) rotate(0deg)`, opacity: 1 },
        { transform: `translateY(${fall}px) rotate(${(i % 2 ? 1 : -1) * 540}deg)`, opacity: 0 },
      ],
      { duration: Math.min(ctx.ms, 2200 + (i % 5) * 300), delay: (i % 8) * 60, easing: 'ease-in', fill: 'forwards' },
    );
    ctx.onEnd(() => {
      anim.cancel();
      p.remove();
    });
  }
}
