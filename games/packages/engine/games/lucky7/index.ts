import type { GameModule } from '../../core/types';
import { bot } from './bot';
import { defaultConfig, type LuckySevenConfig } from './config';
import { apply, legalMoves, result, setup, validate, view, type LuckyMove, type LuckyState, type LuckyView } from './rules';

export const luckySeven: GameModule<LuckySevenConfig, LuckyState, LuckyMove, LuckyView> = {
  id: 'lucky7',
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
