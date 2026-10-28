import type { GameModule } from '../../core/types';
import { bot } from './bot';
import { defaultConfig, type ZombieConfig } from './config';
import { apply, legalMoves, result, setup, validate, view, type ZombieMove, type ZombieState, type ZombieView } from './rules';

export const zombie: GameModule<ZombieConfig, ZombieState, ZombieMove, ZombieView> = {
  id: 'zombie',
  minPlayers: 2,
  maxPlayers: 8,
  defaultConfig,
  setup,
  legalMoves,
  validate,
  apply,
  view,
  result,
  bot,
};

export * from './config';
export * from './rules';
export { bot } from './bot';
