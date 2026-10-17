import { resolve } from 'node:path';
import { defineConfig } from 'vite';

// One HTML page per game, published to games.efoc.party/<game>/.
export default defineConfig({
  base: './',
  build: {
    rollupOptions: {
      input: {
        bigtwo: resolve(__dirname, 'bigtwo/index.html'),
      },
    },
  },
});
