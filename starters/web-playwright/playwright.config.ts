import { defineConfig, devices } from '@playwright/test';

const PORT = 4173;

export default defineConfig({
  testDir: 'e2e',
  retries: process.env.CI ? 1 : 0,
  // `list` lets verify name failed and flaky tests in the job summary; `html` is uploaded on failure.
  reporter: process.env.CI ? [['list'], ['html', { open: 'never' }]] : 'list',
  use: {
    baseURL: `http://localhost:${PORT}`,
    trace: 'on-first-retry',
    video: 'retain-on-failure',
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
  webServer: {
    // Serve the production build (verify runs `build` before `test:e2e`; locally run it first).
    // Vite: `vite preview`. Next.js: `npx next start -p 4173`; its server-side code reads
    // process.env.E2E_API_URL, which verify sets when e2e/mocks.json exists.
    command: `npx vite preview --port ${PORT} --strictPort`,
    url: `http://localhost:${PORT}`,
    reuseExistingServer: !process.env.CI,
  },
});
