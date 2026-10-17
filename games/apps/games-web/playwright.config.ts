import { defineConfig, devices } from '@playwright/test';

// Feel and layout gates for the table (spec "Testing layers"). Runs against
// the production build served locally, in Practice mode with bots.
export default defineConfig({
  testDir: 'tests',
  timeout: 120_000,
  fullyParallel: true,
  workers: 4,
  reporter: [['list']],
  use: {
    baseURL: 'http://127.0.0.1:4173',
    ...devices['Desktop Chrome'],
    hasTouch: true,
    // Multiplayer tests run several "phones" as tabs; keep background tabs
    // running at full speed like real phones would.
    launchOptions: {
      args: ['--disable-background-timer-throttling', '--disable-renderer-backgrounding', '--disable-backgrounding-occluded-windows'],
    },
  },
  webServer: {
    command: 'npm run build && npx vite preview --port 4173 --strictPort --host 127.0.0.1',
    url: 'http://127.0.0.1:4173/bigtwo/',
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
});
