// Generic helpers for building card combinations. Games decide what a
// combination is worth; these only enumerate.

/** Every k-element subset of `items`, in index order. */
export function combinations<T>(items: readonly T[], k: number): T[][] {
  const out: T[][] = [];
  const pick: T[] = [];
  const walk = (start: number): void => {
    if (pick.length === k) {
      out.push(pick.slice());
      return;
    }
    for (let i = start; i <= items.length - (k - pick.length); i++) {
      pick.push(items[i]!);
      walk(i + 1);
      pick.pop();
    }
  };
  walk(0);
  return out;
}

/** One element from each group, every way (cartesian product). */
export function product<T>(groups: readonly (readonly T[])[]): T[][] {
  let out: T[][] = [[]];
  for (const g of groups) {
    const next: T[][] = [];
    for (const prefix of out) for (const item of g) next.push([...prefix, item]);
    out = next;
  }
  return out;
}

export function groupBy<T, K>(items: readonly T[], key: (item: T) => K): Map<K, T[]> {
  const map = new Map<K, T[]>();
  for (const item of items) {
    const k = key(item);
    const list = map.get(k);
    if (list) list.push(item);
    else map.set(k, [item]);
  }
  return map;
}

/** Lexicographic compare of two number keys: negative, zero or positive. */
export function compareKeys(a: readonly number[], b: readonly number[]): number {
  const n = Math.min(a.length, b.length);
  for (let i = 0; i < n; i++) {
    const d = a[i]! - b[i]!;
    if (d !== 0) return d;
  }
  return a.length - b.length;
}
