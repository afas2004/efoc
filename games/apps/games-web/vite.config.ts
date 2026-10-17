import { resolve } from 'node:path';
import { defineConfig } from 'vite';

// One HTML page per game, published to games.efoc.party/<game>/.
// games/assets is served and copied as-is (cards, sounds, emoji, CNAME,
// LICENSES.md), so asset URLs are /cards/Qh.png and so on.
export default defineConfig({
  base: './',
  publicDir: resolve(__dirname, '../../assets'),
  build: {
    rollupOptions: {
      input: {
        bigtwo: resolve(__dirname, 'bigtwo/index.html'),
      },
    },
  },
});
