// Shared engine types. Every game module implements GameModule; the host,
// every phone, bots and the simulator all run the same functions.

import type { Rng } from './rng';

export type GameId = 'bigtwo' | 'hearts' | 'twentyone' | 'lucky7' | 'zombie';

/** Seat index at the table, 0-based, in clockwise order. */
export type SeatId = number;

/** Typed engine event. `to` marks a private event for one seat only. */
export interface GameEvent {
  type: string;
  seat?: SeatId;
  to?: SeatId;
  [key: string]: unknown;
}

/** What one seat (or the public) may see. Each game narrows this. */
export type PlayerView = Record<string, unknown>;

export interface RoundResult {
  /** Points per seat for the round; lower is better in every game but 21. */
  points: number[];
  /** Seats in finishing order, best first. */
  placings: SeatId[];
}

export type BotLevel = 'easy' | 'normal';

export type ValidateResult = { ok: true } | { ok: false; reason: string };

export interface GameModule<Config, State, Move, View = PlayerView> {
  id: GameId;
  minPlayers: number;
  maxPlayers: number;
  defaultConfig: Config;
  setup(seats: SeatId[], config: Config, rng: Rng): State;
  legalMoves(state: State, seat: SeatId): Move[];
  validate(state: State, seat: SeatId, move: Move): ValidateResult;
  apply(state: State, seat: SeatId, move: Move, rng: Rng): { state: State; events: GameEvent[] };
  view(state: State, seat: SeatId | 'public'): View;
  result(state: State): RoundResult | null;
  bot(view: View, level: BotLevel, rng: Rng): Move;
}
