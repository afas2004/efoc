// All visible text comes from the locale file, Jester lines included.
// The Jester speaks a Manglish mix from day one; more locales need no code.

import en from './locales/en-MY.json';

export type Locale = typeof en;
let locale: Locale = en;

export function setLocale(l: Locale): void {
  locale = l;
}

export function L(): Locale {
  return locale;
}

/** Fills `{key}` placeholders. */
export function fmt(text: string, vars: Record<string, string | number> = {}): string {
  return text.replace(/\{(\w+)\}/g, (_, k: string) => String(vars[k] ?? `{${k}}`));
}
