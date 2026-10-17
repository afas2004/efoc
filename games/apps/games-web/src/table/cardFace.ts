// One card design for every game: Kenney Boardgame Pack faces (CC0, see
// assets/LICENSES.md) with our own large corner index on top, so a card
// stays readable when only its left strip shows. Suits never rely on colour
// alone: each index shows its symbol, and the four-colour deck is optional.

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

export const cardImage = (id: string): string => new URL(`../cards/${id}.png`, location.href).href;

export function makeCard(card: Card): HTMLElement {
  const el = document.createElement('div');
  el.className = `card suit-${card[1]}`;
  el.dataset.card = card;
  el.style.backgroundImage = `url("${cardImage(card)}")`;
  const r = rankText(card);
  const s = suitSymbol(card);
  el.innerHTML = `<span class="idx"><b>${r}</b><i>${s}</i></span>`;
  el.setAttribute('aria-label', cardLabel(card));
  return el;
}

/** A face-down card back, e.g. for the small fans on opponents' seats. */
export function makeBack(): HTMLElement {
  const el = document.createElement('span');
  el.className = 'back';
  el.style.backgroundImage = `url("${cardImage('back')}")`;
  return el;
}
