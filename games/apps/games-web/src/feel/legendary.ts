// The legendary moment for the rarest plays (a single 2♠, a straight or
// royal flush). Borrowed from card-game "ultimate" reveals: the card is
// thrown up spinning with a rainbow edge, hangs for a beat, slams onto the
// table with a shockwave, and then a big announcement takes the screen.
//
//   0     ms  cards leave the hand/seat, spinning upward, rainbow glow on
//   700   ms  apex: hang and wobble while the tension note rises
//   1050  ms  slam down onto the table
//   1180  ms  impact: shockwave rings, debris, big shake, double bass, flash
//   1350  ms  announcement: sunburst rays, pulsing box, sparkles, confetti
//   3800  ms  everything clears (a tap skips at any point)
//
// Reduced motion: no throw or shake; the cards fade in and the announcement
// still shows its text.

import type { Box } from '../table/layout';
import { haptic } from '../bridge';
import { confetti, shake, type ColourRole } from './effects';
import { playEmoji } from './jesterArt';
import { sound } from './sound';
import type { MomentCtx } from './tiers';

export const LEGENDARY_TOTAL_MS = 3800;
const T_APEX = 700;
const T_SLAM = 1050;
const T_IMPACT = 1180;
const T_ANNOUNCE = 1350;

export interface LegendaryOptions {
  fx: HTMLElement;
  table: HTMLElement;
  root: HTMLElement;
  sprites: HTMLElement[];
  /** Where the cards come from (a seat, or my hand). */
  from: { x: number; y: number };
  stage: Box;
  vw: number;
  cardW: number;
  title: string;
  subtitle: string;
  role: ColourRole;
  /** Extra beats right after the slam (e.g. everyone's PASS stamps). */
  afterImpact?: () => void;
}

export function legendary(o: LegendaryOptions, ctx: MomentCtx): void {
  const timers: number[] = [];
  const at = (ms: number, fn: () => void): void => {
    timers.push(window.setTimeout(fn, ms));
  };
  ctx.onEnd(() => timers.forEach((t) => window.clearTimeout(t)));

  // Dim the table under the whole moment.
  const dimEl = document.createElement('div');
  dimEl.className = 'fx-dim';
  o.fx.appendChild(dimEl);
  dimEl.animate([{ opacity: 0 }, { opacity: 1, offset: 0.08 }, { opacity: 1, offset: 0.9 }, { opacity: 0 }], { duration: ctx.ms, fill: 'forwards' });
  ctx.onEnd(() => dimEl.remove());

  // 1. Throw and slam.
  const cx = o.stage.x + o.stage.w / 2;
  const apexY = Math.max(10, o.stage.y - 40);
  o.sprites.forEach((sprite, i) => {
    sprite.classList.add('legendary', 'no-anim');
    sprite.style.zIndex = String(900 + i);
    ctx.onEnd(() => sprite.classList.remove('legendary', 'no-anim'));
    if (ctx.reduced) {
      sprite.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 400, fill: 'none' });
      return;
    }
    const final = sprite.style.transform;
    const n = o.sprites.length;
    const spread = (i - (n - 1) / 2) * o.cardW * 0.9;
    const w = sprite.offsetWidth || o.cardW;
    const h = sprite.offsetHeight || o.cardW * 1.36;
    // Spin around the card's centre (sprites use a top-left origin).
    const spin = (x: number, y: number, deg: number, sc: number): string =>
      `translate(${x}px, ${y}px) translate(${w / 2}px, ${h / 2}px) rotate(${deg}deg) scale(${sc}) translate(${-w / 2}px, ${-h / 2}px)`;
    const from = spin(o.from.x - w / 2, o.from.y - h / 2, 0, 0.6);
    const apex = spin(cx - w / 2 + spread, apexY, 540 + i * 30, 1.9);
    const hang = spin(cx - w / 2 + spread, apexY - 14, 700 + i * 30, 2);
    const anim = sprite.animate(
      [
        { transform: from, opacity: 0.6, easing: 'cubic-bezier(.15,.7,.3,1)' },
        { transform: apex, opacity: 1, offset: T_APEX / T_IMPACT, easing: 'ease-in-out' },
        { transform: hang, offset: T_SLAM / T_IMPACT, easing: 'cubic-bezier(.7,0,1,.6)' },
        { transform: `${final} scale(1.18)`, offset: 0.97 },
        { transform: final },
      ],
      { duration: T_IMPACT + i * 40, fill: 'none' },
    );
    ctx.onEnd(() => anim.cancel());
  });
  // Rising tension while it flies.
  sound.rise();
  sound.whoosh();

  // 2. Impact.
  at(ctx.reduced ? 0 : T_IMPACT, () => {
    const impactY = o.stage.y + o.stage.h * 0.55;
    sound.bass();
    window.setTimeout(() => sound.bass(), 180);
    haptic('strong');
    if (!ctx.reduced) {
      shake(o.table, 'big', { ...ctx, ms: 600 });
      for (let r = 0; r < 3; r++) ring(o.fx, cx, impactY, r * 110, ctx);
      debris(o.fx, cx, impactY, ctx);
      o.root.classList.add('flash-gold');
      window.setTimeout(() => o.root.classList.remove('flash-gold'), 900);
    }
    const boom = document.createElement('div');
    boom.className = 'legend-boom';
    boom.style.left = `${cx}px`;
    boom.style.top = `${impactY}px`;
    o.fx.appendChild(boom);
    const stop = playEmoji(boom, 'explode');
    window.setTimeout(() => {
      stop();
      boom.remove();
    }, 1100);
    ctx.onEnd(() => {
      stop();
      boom.remove();
    });
    o.afterImpact?.();
  });

  // 3. Announcement.
  at(ctx.reduced ? 0 : T_ANNOUNCE, () => {
    const wrap = document.createElement('div');
    wrap.className = `legend-wrap role-${o.role}-legend`;
    wrap.innerHTML =
      '<div class="legend-rays"></div>' +
      '<div class="legend-box"><div class="legend-title"></div><div class="legend-sub"></div></div>' +
      '<div class="legend-emoji legend-emoji-l"></div><div class="legend-emoji legend-emoji-r"></div>';
    wrap.querySelector('.legend-title')!.textContent = o.title;
    wrap.querySelector('.legend-sub')!.textContent = o.subtitle;
    wrap.setAttribute('role', 'status');
    o.fx.appendChild(wrap);
    const stopL = playEmoji(wrap.querySelector('.legend-emoji-l') as HTMLElement, 'sparkles');
    const stopR = playEmoji(wrap.querySelector('.legend-emoji-r') as HTMLElement, 'starstruck');
    const remaining = Math.max(600, ctx.ms - (ctx.reduced ? 0 : T_ANNOUNCE));
    wrap.animate(
      ctx.reduced
        ? [{ opacity: 0 }, { opacity: 1, offset: 0.1 }, { opacity: 1, offset: 0.85 }, { opacity: 0 }]
        : [
            { opacity: 0, transform: 'translate(-50%, -50%) scale(0.2) rotate(-12deg)', easing: 'cubic-bezier(.2,1.4,.4,1)' },
            { opacity: 1, transform: 'translate(-50%, -50%) scale(1) rotate(0deg)', offset: 0.16 },
            { opacity: 1, transform: 'translate(-50%, -50%) scale(1)', offset: 0.86 },
            { opacity: 0, transform: 'translate(-50%, -50%) scale(1.25)' },
          ],
      { duration: remaining, fill: 'forwards', easing: 'linear' },
    );
    if (!ctx.reduced) {
      sparkles(wrap, ctx);
      confetti(o.fx, o.vw, { ...ctx, ms: remaining });
    }
    sound.fanfare();
    ctx.onEnd(() => {
      stopL();
      stopR();
      wrap.remove();
    });
  });
}

/** An expanding shockwave ring. */
function ring(layer: HTMLElement, x: number, y: number, delay: number, ctx: MomentCtx): void {
  const el = document.createElement('div');
  el.className = 'legend-ring';
  el.style.left = `${x}px`;
  el.style.top = `${y}px`;
  layer.appendChild(el);
  const a = el.animate(
    [
      { transform: 'translate(-50%, -50%) scale(0.1)', opacity: 0.95 },
      { transform: 'translate(-50%, -50%) scale(3.2)', opacity: 0 },
    ],
    { duration: 700, delay, easing: 'cubic-bezier(.1,.8,.3,1)', fill: 'both' },
  );
  ctx.onEnd(() => {
    a.cancel();
    el.remove();
  });
  window.setTimeout(() => el.remove(), 700 + delay);
}

/** Chips of felt and sparks thrown out by the slam. */
function debris(layer: HTMLElement, x: number, y: number, ctx: MomentCtx): void {
  const colours = ['#facc15', '#fde68a', '#ffffff', '#f97316', '#a855f7', '#22c55e'];
  for (let i = 0; i < 36; i++) {
    const p = document.createElement('div');
    p.className = i % 3 === 0 ? 'legend-spark' : 'fx-particle';
    p.style.left = `${x}px`;
    p.style.top = `${y}px`;
    p.style.background = colours[i % colours.length]!;
    layer.appendChild(p);
    const angle = Math.PI + (i / 36) * Math.PI + ((i * 13) % 7) * 0.03; // mostly upward
    const dist = 80 + ((i * 47) % 140);
    const anim = p.animate(
      [
        { transform: 'translate(-50%, -50%) scale(1.2)', opacity: 1 },
        { transform: `translate(calc(-50% + ${Math.cos(angle) * dist}px), calc(-50% + ${Math.sin(angle) * dist * 0.9}px)) scale(0.8)`, opacity: 1, offset: 0.6 },
        { transform: `translate(calc(-50% + ${Math.cos(angle) * dist * 1.15}px), calc(-50% + ${Math.sin(angle) * dist * 0.9 + 60}px)) scale(0.3)`, opacity: 0 },
      ],
      { duration: 1000, easing: 'cubic-bezier(.1,.8,.4,1)', fill: 'forwards' },
    );
    ctx.onEnd(() => {
      anim.cancel();
      p.remove();
    });
    window.setTimeout(() => p.remove(), 1000);
  }
}

/** Twinkling stars orbiting the announcement box. */
function sparkles(wrap: HTMLElement, ctx: MomentCtx): void {
  for (let i = 0; i < 14; i++) {
    const s = document.createElement('span');
    s.className = 'legend-star';
    s.textContent = i % 2 ? '✦' : '★';
    const angle = (i / 14) * Math.PI * 2;
    s.style.left = `${50 + Math.cos(angle) * 58}%`;
    s.style.top = `${50 + Math.sin(angle) * 70}%`;
    s.style.animationDelay = `${(i % 7) * 120}ms`;
    wrap.appendChild(s);
  }
  void ctx;
}
