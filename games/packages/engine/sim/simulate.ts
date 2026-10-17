// Bot-vs-bot simulator. For every game it checks, after every move:
//   - the player to move always has a legal move,
//   - every bot move passes validate() (bots only see view()),
//   - every card is in exactly one place (hands, out, pile),
//   - no view leaks a card from another player's hand,
// and per game: it ends within a move cap, the result is sane, and
// replaying the move log with the same seed reproduces the final state.
//
//   npm run sim                         10,000 games per player count 2–8, per mode
//   npm run sim -- --games 500 --players 4 --variants

import { fullDeck, isCard, type Card } from '../core/cards';
import { createRng, type Rng } from '../core/rng';
import type { BotLevel } from '../core/types';
import { bigTwo, defaultConfig, nextRound, type BigTwoConfig, type BigTwoMove, type BigTwoState } from '../games/bigtwo/index';

export interface SimOptions {
  games: number;
  players: number;
  config: BigTwoConfig;
  seed: number;
  /** Randomise house-rule flags and round count per game. */
  variants?: boolean;
  maxMovesPerRound?: number;
}

export interface SimReport {
  players: number;
  games: number;
  moves: number;
  rounds: number;
  failures: string[];
  ms: number;
}

const DECK = new Set(fullDeck());

function collectCards(value: unknown, out: Set<Card>): void {
  if (typeof value === 'string') {
    if (isCard(value)) out.add(value);
  } else if (Array.isArray(value)) {
    for (const v of value) collectCards(v, out);
  } else if (value && typeof value === 'object') {
    for (const v of Object.values(value)) collectCards(v, out);
  }
}

function checkConservation(s: BigTwoState): string | null {
  const all = [...s.hands.flat(), ...s.out, ...s.pile];
  if (all.length !== 52) return `card count ${all.length}, expected 52`;
  const seen = new Set(all);
  if (seen.size !== 52) return 'a card is in two places';
  for (const c of seen) if (!DECK.has(c)) return `unknown card ${c}`;
  return null;
}

function checkViews(s: BigTwoState): string | null {
  const pub = new Set<Card>();
  collectCards(bigTwo.view(s, 'public'), pub);
  for (let seat = 0; seat < s.players; seat++) {
    for (const c of s.hands[seat]!) if (pub.has(c)) return `public view shows ${c} from seat ${seat}'s hand`;
  }
  for (let seat = 0; seat < s.players; seat++) {
    const seen = new Set<Card>();
    collectCards(bigTwo.view(s, seat), seen);
    for (let other = 0; other < s.players; other++) {
      if (other === seat) continue;
      for (const c of s.hands[other]!) if (seen.has(c)) return `seat ${seat}'s view shows ${c} from seat ${other}`;
    }
  }
  return null;
}

function checkResult(s: BigTwoState): string | null {
  const r = bigTwo.result(s);
  if (!r) return 'round ended without a result';
  if (new Set(r.placings).size !== s.players || r.placings.length !== s.players) return 'placings are not one per seat';
  if (r.points.some((p) => p < 0 || !Number.isInteger(p))) return 'negative or fractional points';
  if (r.points[r.placings[0]!] !== 0) return 'the winner took points';
  if (s.config.mode === 'standard' && s.hands[r.placings[0]!]!.length !== 0) return 'winner still holds cards';
  if (s.config.mode === 'fightTillTheEnd' && s.hands.filter((h) => h.length > 0).length > 1) {
    return 'more than one player still holds cards at the end';
  }
  return null;
}

function randomConfig(base: BigTwoConfig, rng: Rng): BigTwoConfig {
  const coin = () => rng.next() < 0.5;
  return {
    ...base,
    mode: coin() ? 'standard' : 'fightTillTheEnd',
    allowA2345: coin(),
    allow23456: coin(),
    allowTriples: coin(),
    fourOfAKindKicker: coin(),
    flushCompare: coin() ? 'suitFirst' : 'highCardFirst',
    passLocksOut: coin(),
    pokerHands: coin(),
    roundsToPlay: 1 + rng.int(3),
  };
}

interface Played {
  final: BigTwoState;
  moves: [number, BigTwoMove][];
  rounds: number;
}

/** Plays one match. Returns the failure message, or the played match. */
function playMatch(players: number, config: BigTwoConfig, seed: number, levels: BotLevel[], cap: number, checks: boolean): Played | string {
  const dealRng = createRng(seed);
  const botRng = createRng(seed ^ 0x9e3779b9);
  const seats = [...Array(players).keys()];
  let s = bigTwo.setup(seats, config, dealRng);
  const moves: [number, BigTwoMove][] = [];
  let rounds = 1;
  let movesThisRound = 0;
  for (;;) {
    if (s.phase !== 'play') {
      if (checks) {
        const bad = checkResult(s);
        if (bad) return bad;
      }
      if (s.phase === 'matchOver') return { final: s, moves, rounds };
      s = nextRound(s, dealRng);
      rounds++;
      movesThisRound = 0;
      continue;
    }
    if (++movesThisRound > cap) return `round ${rounds} did not end within ${cap} moves`;
    const seat = s.turn;
    if (checks) {
      const legal = bigTwo.legalMoves(s, seat);
      if (legal.length === 0) return `seat ${seat} has no legal move`;
      for (let other = 0; other < players; other++) {
        if (other !== seat && bigTwo.legalMoves(s, other).length > 0) return `seat ${other} can move out of turn`;
      }
    }
    const move = bigTwo.bot(bigTwo.view(s, seat), levels[seat]!, botRng);
    const ok = bigTwo.validate(s, seat, move);
    if (!ok.ok) return `bot at seat ${seat} made an illegal move ${JSON.stringify(move)}: ${ok.reason}`;
    s = bigTwo.apply(s, seat, move, botRng).state;
    moves.push([seat, move]);
    if (checks) {
      const bad = checkConservation(s) ?? checkViews(s);
      if (bad) return bad;
    }
  }
}

/** Replays a recorded move log from the seed; the final state must match exactly. */
function replay(players: number, config: BigTwoConfig, seed: number, moves: [number, BigTwoMove][]): BigTwoState {
  const dealRng = createRng(seed);
  let s = bigTwo.setup([...Array(players).keys()], config, dealRng);
  for (const [seat, move] of moves) {
    while (s.phase === 'roundOver') s = nextRound(s, dealRng);
    s = bigTwo.apply(s, seat, move, dealRng).state;
  }
  while (s.phase === 'roundOver') s = nextRound(s, dealRng);
  return s;
}

export function simulate(opts: SimOptions): SimReport {
  const start = performance.now();
  const cap = opts.maxMovesPerRound ?? 2000;
  const failures: string[] = [];
  let moves = 0;
  let rounds = 0;
  for (let g = 0; g < opts.games; g++) {
    const seed = (opts.seed + g * 7919) >>> 0;
    const pick = createRng(seed ^ 0x51ed270b);
    const config = opts.variants ? randomConfig(opts.config, pick) : opts.config;
    const levels: BotLevel[] = Array.from({ length: opts.players }, () => (pick.next() < 0.5 ? 'easy' : 'normal'));
    const label = `players=${opts.players} seed=${seed} config=${JSON.stringify(config)}`;
    let played: Played | string;
    try {
      played = playMatch(opts.players, config, seed, levels, cap, true);
    } catch (e) {
      played = `threw: ${(e as Error).message}`;
    }
    if (typeof played === 'string') {
      failures.push(`${label}: ${played}`);
      continue;
    }
    moves += played.moves.length;
    rounds += played.rounds;
    const again = replay(opts.players, config, seed, played.moves);
    if (JSON.stringify(again) !== JSON.stringify(played.final)) failures.push(`${label}: replay differs from the original`);
  }
  return { players: opts.players, games: opts.games, moves, rounds, failures, ms: performance.now() - start };
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
  const variants = process.argv.includes('--variants');
  const runs: { name: string; config: BigTwoConfig; variants: boolean }[] = variants
    ? [{ name: 'random flags', config: defaultConfig, variants: true }]
    : [
        { name: 'standard', config: { ...defaultConfig, mode: 'standard' }, variants: false },
        { name: 'fight till the end', config: { ...defaultConfig, mode: 'fightTillTheEnd' }, variants: false },
      ];

  let failed = 0;
  console.log(`Big Two simulation: ${games} games per row, seed ${seed}\n`);
  console.log('mode                 players   games   rounds     moves   failures   time');
  for (const run of runs) {
    for (const players of counts) {
      const r = simulate({ games, players, config: run.config, seed, variants: run.variants });
      failed += r.failures.length;
      console.log(
        `${run.name.padEnd(20)} ${String(players).padStart(7)} ${String(r.games).padStart(7)} ${String(r.rounds).padStart(8)} ${String(r.moves).padStart(9)} ${String(r.failures.length).padStart(10)}   ${(r.ms / 1000).toFixed(1)}s`,
      );
      for (const f of r.failures.slice(0, 5)) console.log(`  FAIL ${f}`);
    }
  }
  console.log(failed === 0 ? '\nPASS: no failures.' : `\nFAILED: ${failed} game(s).`);
  process.exitCode = failed === 0 ? 0 : 1;
}

if (process.argv[1] && /simulate\.ts$/.test(process.argv[1])) main();
