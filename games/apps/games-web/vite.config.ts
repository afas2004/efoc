import { resolve } from 'node:path';
import { defineConfig } from 'vite';

// One HTML page per game, published to games.efoc.party/efoc/<game>/,
// plus index.html: the efoc landing page at games.efoc.party/efoc/.
// games/assets is served and copied as-is (cards, sounds, emoji,
// LICENSES.md); every URL is relative, so the site works under any path.
export default defineConfig({
  base: './',
  publicDir: resolve(__dirname, '../../assets'),
  build: {
    rollupOptions: {
      input: {
        index: resolve(__dirname, 'index.html'),
        bigtwo: resolve(__dirname, 'bigtwo/index.html'),
        lucky7: resolve(__dirname, 'lucky7/index.html'),
      },
    },
  },
});
