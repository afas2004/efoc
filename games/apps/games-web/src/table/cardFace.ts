// One card design for every game. Placeholder faces drawn with text and
// suit symbols in the flat Kenney style until the Kenney Boardgame Pack art
// is added (assets/LICENSES.md). Suits never rely on colour alone: each
// face shows its symbol, and the four-colour deck is optional.

import type { Card } from '@efoc/engine';
import { L, fmt } from '../strings';

const SUIT_SYMBOL: Record<string, string> = { d: '♦', c: '♣', h: '♥', s: '♠' };
const RANK_TEXT: Record<string, string> = { T: '10' };

export function rankText(card: Card): string {
  return RANK_TEXT[card[0]!] ?? card[0]!;
}

export function suitSymbol(card: Card): string {
  return SUIT_SYMBOL[card[1]!] ?? '';
}

export function cardLabel(card: Card, selected = false): string {
  const u = L().ui;
  const label = fmt(u.cardLabel, {
    rank: (u.rankNames as Record<string, string>)[card[0]!] ?? card[0]!,
    suit: (u.suitNames as Record<string, string>)[card[1]!] ?? card[1]!,
  });
  return selected ? `${label}, ${u.selected}` : label;
}

/** Short text for a list of cards, e.g. "Q♥ Q♠". */
export function cardsText(cards: readonly Card[]): string {
  return cards.map((c) => rankText(c) + suitSymbol(c)).join(' ');
}

export function makeCard(card: Card): HTMLElement {
  const el = document.createElement('div');
  el.className = `card suit-${card[1]}`;
  el.dataset.card = card;
  const r = rankText(card);
  const s = suitSymbol(card);
  el.innerHTML =
    `<span class="corner tl"><b>${r}</b><i>${s}</i></span>` +
    `<span class="pip">${s}</span>` +
    `<span class="corner br"><b>${r}</b><i>${s}</i></span>`;
  el.setAttribute('aria-label', cardLabel(card));
  return el;
}
