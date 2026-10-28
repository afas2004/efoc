// Zombie bot-vs-bot simulator: the same gate as Big Two's. After every move:
//   - the player to move always has a legal move, nobody else does,
//   - every bot move passes validate() (bots only see view()),
//   - every card is in exactly one place (hands, pile): 53 cards,
//   - no view and no public event shows a card from someone's hand,
//   - private events go only to the seat they're for,
//   - every phone's masked copy (each seat and a spectator), fed only the
//     public log with reorders stripped plus its own private events, matches
//     the host's checksum and shows its seat exactly the host's view,
// and per game: it ends within a move cap, the result is sane, and
// replaying the move log with the same seed reproduces the final state.
// Players also drag their hands around at random moments (reorders) on
// anyone's turn, as people do.
//
//   npm run sim:zombie                    10,000 games per player count 2–8
//   npm run sim:zombie -- --games 500 --players 4

import { fullDeck, isCard, JOKER, type Card } from '../core/cards';
import { createRng } from '../core/rng';
import type { BotLevel, GameEvent } from '../core/types';
import {
  applyPublic,
  applyPrivate,
  checksum,
  defaultConfig,
  HIDDEN,
  mask,
  zombie,
  type ZombieMove,
  type ZombieState,
} from '../games/zombie/index';

export interface ZombieSimReport {
  players: number;
  games: number;
  moves: number;
  failures: string[];
  ms: number;
}

const DECK = new Set(fullDeck(true));

function collectCards(value: unknown, out: Set<Card>): void {
  if (typeof value === 'string') {
    if (isCard(value)) out.add(value);
  } else if (Array.isArray(value)) {
    for (const v of value) collectCards(v, out);
  } else if (value && typeof value === 'object') {
    for (const v of Object.values(value)) collectCards(v, out);
  }
}

function checkConservation(s: ZombieState): string | null {
  const all = [...s.hands.flat(), ...s.pile];
  if (all.length !== 53) return `card count ${all.length}, expected 53`;
  const seen = new Set(all);
  if (seen.size !== 53) return 'a card is in two places';
  for (const c of seen) if (!DECK.has(c)) return `unknown card ${c}`;
  if (s.hands.filter((h) => h.includes(JOKER)).length !== 1) return 'the Zombie is not in exactly one hand';
  return null;
}

/** Cards in someone's hand that `seat` mustn't see (the loser's hand is public at the end). */
function secretsFor(s: ZombieState, seat: number | 'public'): Set<Card> {
  const out = new Set<Card>();
  s.hands.forEach((h, i) => {
    if (i === seat || (s.phase === 'over' && i === s.loser)) return;
    for (const c of h) out.add(c);
  });
  return out;
}

function checkViews(s: ZombieState): string | null {
  for (const seat of [...s.hands.keys(), 'public' as const]) {
    const seen = new Set<Card>();
    collectCards(zombie.view(s, seat), seen);
    const secret = secretsFor(s, seat);
    for (const c of seen) if (secret.has(c)) return `${seat}'s view shows ${c} from another hand`;
  }
  return null;
}

/** What the public log carries: a reorder loses its cards. */
const publicMove = (m: ZombieMove): { type: string; slot?: number } => (m.type === 'order' ? { type: 'order' } : m);

function checkEvents(before: ZombieState, after: ZombieState, seat: number, move: ZombieMove, events: GameEvent[]): string | null {
  const pub = events.filter((e) => e.to === undefined);
  // At the end the loser's hand is shown; until then nothing in any hand is.
  const secret = after.phase === 'over' ? secretsFor(after, 'public') : new Set([...secretsFor(before, 'public'), ...secretsFor(after, 'public')]);
  // Cards thrown face up this move are public now.
  for (const e of pub) if (e.type === 'pair') for (const c of e.cards as Card[]) secret.delete(c);
  const leaked = new Set<Card>();
  collectCards([pub, publicMove(move)], leaked);
  for (const c of leaked) if (secret.has(c)) return `a public event shows ${c}`;
  for (const e of events) {
    if (e.to === undefined) continue;
    if ((e.type === 'drawn_card' || e.type === 'hand') && e.to !== seat) return `private ${e.type} went to seat ${e.to}, not ${seat}`;
    if (e.type === 'hand') {
      const mine = new Set(after.hands[seat]);
      if ((e.cards as Card[]).some((c) => !mine.has(c))) return 'a private hand event names a card not in that hand';
    }
  }
  return null;
}

function checkFollowers(host: ZombieState, copies: ZombieState[]): string | null {
  const sum = checksum(host);
  for (let i = 0; i < copies.length; i++) {
    const c = copies[i]!;
    const who = i === host.players ? 'spectator' : `seat ${i}`;
    if (checksum(c) !== sum) return `copy ${who} drifted from the host`;
    if (i < host.players && JSON.stringify(zombie.view(c, i)) !== JSON.stringify(zombie.view(host, i))) return `${who}'s view differs from the host's`;
    if (c.hands.some((h, k) => k !== i && !(host.phase === 'over' && k === host.loser) && h.some((x) => x !== HIDDEN))) return `copy ${who} holds someone else's card`;
  }
  return null;
}

function checkResult(s: ZombieState): string | null {
  const r = zombie.result(s);
  if (!r) return 'round ended without a result';
  if (r.placings.length !== s.players || new Set(r.placings).size !== s.players) return 'placings are not one per seat';
  const loser = r.placings[s.players - 1]!;
  if (!s.hands[loser]!.includes(JOKER)) return 'the last place does not hold the Zombie';
  if (r.points.reduce((a, b) => a + b, 0) !== 1 || r.points[loser] !== 1) return 'only the loser takes a point';
  if (s.draws < s.maxDraws && s.hands.filter((h) => h.length > 0).length !== 1) return 'more than one hand left at the end';
  if (s.draws < s.maxDraws && s.hands[loser]!.length !== 1) return 'the loser holds more than the Zombie';
  return null;
}

type Logged = [number, ZombieMove];

function playMatch(players: number, seed: number, levels: BotLevel[], follow: boolean): { final: ZombieState; moves: Logged[] } | string {
  const rng = createRng(seed);
  const botRng = createRng(seed ^ 0x9e3779b9);
  let s = zombie.setup([...Array(players).keys()], defaultConfig, rng);
  let copies = follow ? [...s.hands.map((_, i) => mask(s, i)), mask(s, 'public')] : [];
  const moves: Logged[] = [];
  const cap = 4000;
  if (checkConservation(s) ?? checkViews(s)) return `bad deal: ${checkConservation(s) ?? checkViews(s)}`;
  while (s.phase === 'play') {
    if (moves.length > cap) return `did not end within ${cap} moves`;
    let seat = s.turn;
    const legal = zombie.legalMoves(s, seat);
    if (legal.length === 0) return `seat ${seat} has no legal move`;
    for (let other = 0; other < players; other++) if (other !== seat && zombie.legalMoves(s, other).length > 0) return `seat ${other} can move out of turn`;
    let move: ZombieMove = zombie.bot(zombie.view(s, seat), levels[seat]!, botRng);
    // Now and then someone drags their own hand around, on anyone's turn.
    if (botRng.next() < 0.25) {
      const who = botRng.int(players);
      if (s.hands[who]!.length > 0) {
        seat = who;
        move = { type: 'order', cards: botRng.shuffle(s.hands[who]!) };
      }
    }
    const ok = zombie.validate(s, seat, move);
    if (!ok.ok) return `seat ${seat} made an illegal move ${JSON.stringify(move)}: ${ok.reason}`;
    const before = s;
    const r = zombie.apply(s, seat, move, rng);
    s = r.state;
    moves.push([seat, move]);
    const bad = checkConservation(s) ?? checkViews(s) ?? checkEvents(before, s, seat, move, r.events);
    if (bad) return bad;
    if (follow) {
      const pub = r.events.filter((e) => e.to === undefined);
      copies = copies.map((c, i) => {
        let next = applyPublic(c, seat, publicMove(move), pub);
        for (const e of r.events) if (e.to === i) next = applyPrivate(next, i, e);
        return next;
      });
      const drift = checkFollowers(s, copies);
      if (drift) return drift;
    }
  }
  return checkResult(s) ?? { final: s, moves };
}

/** Replays a recorded move log from the seed; the final state must match exactly. */
function replay(players: number, seed: number, moves: Logged[]): ZombieState {
  const rng = createRng(seed);
  let s = zombie.setup([...Array(players).keys()], defaultConfig, rng);
  for (const [seat, move] of moves) s = zombie.apply(s, seat, move, rng).state;
  return s;
}

export function simulateZombie(opts: { games: number; players: number; seed: number }): ZombieSimReport {
  const start = performance.now();
  const failures: string[] = [];
  let moves = 0;
  for (let g = 0; g < opts.games; g++) {
    const seed = (opts.seed + g * 7919) >>> 0;
    const pick = createRng(seed ^ 0x51ed270b);
    const levels: BotLevel[] = Array.from({ length: opts.players }, () => (pick.next() < 0.5 ? 'easy' : 'normal'));
    const label = `players=${opts.players} seed=${seed}`;
    let played: ReturnType<typeof playMatch>;
    try {
      played = playMatch(opts.players, seed, levels, g % 5 === 0);
    } catch (e) {
      played = `threw: ${(e as Error).message}`;
    }
    if (typeof played === 'string') {
      failures.push(`${label}: ${played}`);
      continue;
    }
    moves += played.moves.length;
    const again = replay(opts.players, seed, played.moves);
    if (JSON.stringify(again) !== JSON.stringify(played.final)) failures.push(`${label}: replay differs from the original`);
  }
  return { players: opts.players, games: opts.games, moves, failures, ms: performance.now() - start };
}

// ------------------------------------------------------------------ CLI

function arg(name: string): string | undefined {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? process.argv[i + 1] : undefined;
}

function main(): void {
  const games = Number(arg('games') ?? 10_000);
  const playerArg = arg('players');
  const counts = playerArg ? [Number(playerArg)] : [2, 3, 4, 5, 6, 7, 8];
  const seed = Number(arg('seed') ?? 1);
  let failed = 0;
  console.log(`Zombie simulation: ${games} games per row, seed ${seed}\n`);
  console.log('players   games     moves   failures   time');
  for (const players of counts) {
    const r = simulateZombie({ games, players, seed });
    failed += r.failures.length;
    console.log(`${String(players).padStart(7)} ${String(r.games).padStart(7)} ${String(r.moves).padStart(9)} ${String(r.failures.length).padStart(10)}   ${(r.ms / 1000).toFixed(1)}s`);
    for (const f of r.failures.slice(0, 5)) console.log(`  FAIL ${f}`);
  }
  console.log(failed === 0 ? '\nPASS: no failures.' : `\nFAILED: ${failed} game(s).`);
  process.exitCode = failed === 0 ? 0 : 1;
}

if (process.argv[1] && /zombie\.ts$/.test(process.argv[1])) main();
