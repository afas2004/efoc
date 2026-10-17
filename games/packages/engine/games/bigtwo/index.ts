import type { GameModule } from '../../core/types';
import { bot } from './bot';
import { defaultConfig, type BigTwoConfig } from './config';
import {
  apply,
  legalMoves,
  result,
  setup,
  validate,
  view,
  type BigTwoMove,
  type BigTwoState,
  type BigTwoView,
} from './rules';

export const bigTwo: GameModule<BigTwoConfig, BigTwoState, BigTwoMove, BigTwoView> = {
  id: 'bigtwo',
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
