import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: '.',
  timeout: 30_000,
  use: {
    baseURL: process.env.ALIDADE_URL || 'https://jackyko1991.github.io/Alidade/',
    trace: 'retain-on-failure',
  },
  reporter: [['list']],
});
