// Playwright end-to-end tests for the demo video flow (docs/product/DEMO_SCRIPT.md).
// Starts its own Rails server. Never point this at port 3100.
const { defineConfig, devices } = require('@playwright/test');
const path = require('path');

const PORT = Number(process.env.E2E_PORT || 3211);
const ROOT = path.resolve(__dirname, '../..');
if (PORT === 3100) throw new Error('Port 3100 is the shared dev server. Pick another E2E_PORT.');

module.exports = defineConfig({
  testDir: __dirname,
  outputDir: path.join(ROOT, 'tmp/playwright/results'),
  timeout: 90_000,
  expect: { timeout: 10_000 },
  fullyParallel: false,
  workers: 1,
  retries: 0,
  reporter: [['list'], ['html', { open: 'never', outputFolder: path.join(ROOT, 'tmp/playwright/report') }]],
  use: {
    baseURL: `http://127.0.0.1:${PORT}`,
    viewport: { width: 1440, height: 900 },
    acceptDownloads: true,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'], viewport: { width: 1440, height: 900 } } }],
  webServer: {
    // LAUNCHY_DRY_RUN and BROWSER stop letter_opener from opening browser tabs.
    command: `script/with-ruby bin/rails db:prepare && script/dev -P tmp/pids/e2e-${PORT}.pid --port ${PORT}`,
    cwd: ROOT,
    url: `http://127.0.0.1:${PORT}/up`,
    reuseExistingServer: false,
    timeout: 120_000,
    env: { LAUNCHY_DRY_RUN: 'true', BROWSER: '/usr/bin/true', RAILS_ENV: 'development', RFQ_LIVE_MODELS: '0' },
    stdout: 'ignore',
    stderr: 'pipe',
  },
});
