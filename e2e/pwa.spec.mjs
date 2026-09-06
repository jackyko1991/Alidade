// End-to-end check of the deployed PWA (https://jackyko1991.github.io/Alidade/
// by default — override with ALIDADE_URL). Exercises the flow that turned out
// to be the actual load-bearing risk of a Flutter-web + Rust/WASM build: does
// a real browser actually load the wasm module and complete a same-origin
// database download, not just "does the page render". See
// ../docs/web-build.md for the three real, confirmed bugs this style of test
// (driving the live page, not just reading source) caught before this test
// existed.
import { test, expect } from '@playwright/test';

test('loads, has no console errors, and downloads a solver database', async ({ page }) => {
  const consoleErrors = [];
  page.on('pageerror', (err) => consoleErrors.push(err.message));
  page.on('console', (msg) => {
    if (msg.type() === 'error') consoleErrors.push(msg.text());
  });

  // A bare '/' would resolve against baseURL's *origin*, discarding its
  // path (e.g. the '/Alidade/' subpath) per Playwright's URL-joining
  // rules — './' keeps it.
  await page.goto('./');

  // Flutter web renders to a single <canvas> by default (CanvasKit), with no
  // per-widget DOM nodes until semantics are enabled — Flutter injects a
  // full-screen placeholder button for exactly this purpose. Clicking it
  // turns on the semantics tree, after which normal ARIA role/name locators
  // work for the rest of the test instead of brittle pixel coordinates.
  const semanticsPlaceholder = page.locator('flt-semantics-placeholder');
  await semanticsPlaceholder.waitFor({ state: 'attached', timeout: 10_000 });
  // A real actionability-checked click reports "outside of viewport" —
  // this placeholder is sized/positioned by Flutter in a way Playwright's
  // visibility heuristics don't like even though it's genuinely clickable
  // (that's its whole purpose). Dispatch the click directly instead.
  await semanticsPlaceholder.dispatchEvent('click');

  // Fresh browser profile (Playwright's default) means no lens presets
  // exist yet, so the "Add a lens to get started" reminder should appear.
  await expect(page.getByText('Add a lens to get started')).toBeVisible({ timeout: 10_000 });
  await page.getByRole('button', { name: 'Open Settings' }).click();

  await page.getByRole('button', { name: 'Direct FOV' }).click();
  await page.getByRole('textbox', { name: /Horizontal FOV/i }).fill('20');
  await page.getByRole('button', { name: 'Add' }).click();

  // The new row's download icon button is labeled with its size, e.g.
  // "Download database (2.4 MB)" — see lens_picker.dart's IconButton tooltip.
  const downloadButton = page.getByRole('button', { name: /Download database/i });
  await expect(downloadButton).toBeVisible();
  await downloadButton.click();

  // A successful download replaces the download icon with a check mark and
  // loads the database into the Rust solver — the real end-to-end signal
  // that (a) the wasm module initialized, (b) the same-origin `dbs/` fetch
  // wasn't blocked by CORS, and (c) no dart:io/path_provider call crashed.
  await expect(downloadButton).toBeHidden({ timeout: 20_000 });
  await page.getByRole('button', { name: 'Done' }).click();

  // Solve history has the exact same native-only-storage failure mode the
  // database download had (path_provider, no web backend) — opening it used
  // to throw MissingPluginException on web. An empty list is the correct,
  // working result for a fresh profile with no solves yet.
  await page.getByRole('button', { name: 'Solve history' }).click();
  await expect(page.getByText('No solves yet')).toBeVisible({ timeout: 10_000 });
  await page.goBack();

  expect(
    consoleErrors.filter((e) => !e.includes('Buffers cannot be shared')),
    `Unexpected console/page errors:\n${consoleErrors.join('\n')}`,
  ).toEqual([]);
});
