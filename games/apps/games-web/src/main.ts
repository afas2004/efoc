// Table client entry. The table shell, card renderer, tiers, Jester and
// bridge arrive in Phase 2; this only proves the engine wires in.
import { fullDeck } from '@efoc/engine';

const table = document.getElementById('table');
if (table) table.textContent = `EFOC table client — ${fullDeck().length} cards ready.`;
