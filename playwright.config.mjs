import { defineConfig, devices } from '@playwright/test';

// Scoped to tests/vrt only, so a bare `npx playwright test` does not pick up
// anything else the project might add later under tests/.
export default defineConfig({
  testDir: './tests/vrt',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: [['html', { outputFolder: 'playwright-report', open: 'never' }], ['list']],
  // Baselines are OS-suffixed by directory rather than filename, so the
  // Linux ones (authoritative, committed) and the macOS ones (advisory,
  // gitignored) never collide. See the "Visual regression" section in
  // README.md for the baseline policy.
  snapshotPathTemplate: '{testDir}/__screenshots__/{platform}/{testFileName}/{arg}{ext}',
  use: {
    viewport: { width: 1280, height: 720 },
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
});
