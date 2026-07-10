import { test, expect } from '@playwright/test';
import { harnessURL } from './harness-helpers';

test('mock harness reports workspace status from composer with branded default model', async ({ page }) => {
  await page.goto(harnessURL());

  await expect(page.getByTestId('model-picker-button')).toHaveText('Nike 1.0');
  await page.getByLabel('Message').fill('/status');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('top-bar-title')).toHaveText('/status');
  await expect(page.getByTestId('top-bar-subtitle')).toContainText('QuillCode - Auto - Nike 1.0');
  await expect(page.getByTestId('tool-card')).toHaveCount(0);

  const statusMessage = page.getByTestId('message').filter({ hasText: 'Project: QuillCode' });
  await expect(statusMessage).toContainText('Thread: /status');
  await expect(statusMessage).toContainText('Instructions: 1 instruction file loaded');
  await expect(statusMessage).toContainText('Memories: 2 memories');
  await expect(statusMessage).toContainText('Goal: No durable goal');
  await expect(statusMessage).toContainText('Mode: Auto');
  await expect(statusMessage).toContainText('Model: Nike 1.0 (trustedrouter/fast)');
  await expect(statusMessage).toContainText('Agent: Idle');
});

test('mock harness reports Prometheus status with preferred slash alias after model switch', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByTestId('model-picker-button').click();
  await page.locator('[data-testid="model-option"][data-model-id="trustedrouter/fusion"]').click();
  await expect(page.getByTestId('model-picker-button')).toHaveText('Prometheus 1.0');

  await page.getByLabel('Message').fill('/status');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('top-bar-subtitle')).toContainText('QuillCode - Auto - Prometheus 1.0');
  const statusMessage = page.getByTestId('message').filter({ hasText: 'Project: QuillCode' });
  await expect(statusMessage).toContainText('Model: Prometheus 1.0 (/prometheus)');
});

test('mock harness surfaces the branch and ahead/behind chip after a git status', async ({ page }) => {
  await page.goto(harnessURL());

  // No branch chip until a git status runs.
  await expect(page.getByTestId('top-bar-branch')).toHaveCount(0);

  await page.getByLabel('Message').fill('/git-status');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.status');
  await expect(page.getByTestId('top-bar-branch')).toBeVisible();
  await expect(page.getByTestId('top-bar-branch')).toHaveText('main');

  // The chip is additive: the existing subtitle is unchanged.
  await expect(page.getByTestId('top-bar-subtitle')).toContainText('QuillCode');

  // Switching to another project drops the chip so a stale branch is never shown.
  await page.getByTestId('add-project-button').click();
  await expect(page.getByTestId('top-bar-branch')).toHaveCount(0);
});

test('mock harness surfaces the prominent token budget meter after a turn completes', async ({ page }) => {
  await page.goto(harnessURL());

  // No token budget meter until a thread exists and a turn reports usage.
  await expect(page.getByTestId('top-bar-token-budget')).toHaveCount(0);
  await expect(page.getByTestId('top-bar-usage')).toHaveCount(0);

  await page.getByLabel('Message').fill('Run the tests');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('top-bar-token-budget')).toBeVisible();
  await expect(page.getByTestId('top-bar-token-budget-primary')).toContainText(/\/ .* tokens/);
  await expect(page.getByTestId('top-bar-token-budget-secondary')).toContainText('left');
  await expect(page.getByTestId('top-bar-token-budget-secondary')).toContainText('%');
  await expect(page.getByTestId('top-bar-token-quota-limits')).toHaveCount(0);
  await expect(page.getByTestId('top-bar-usage')).toHaveCount(0);
  // Additive: the existing subtitle is unchanged.
  await expect(page.getByTestId('top-bar-subtitle')).toContainText('QuillCode');

  // The meter is per-thread, so a fresh thread shows nothing until its own first turn.
  await page.getByTestId('new-chat-button').click();
  await expect(page.getByTestId('top-bar-token-budget')).toHaveCount(0);
  await expect(page.getByTestId('top-bar-usage')).toHaveCount(0);
});

test('mock harness token abbreviator matches the Swift boundary table byte-for-byte', async ({ page }) => {
  await page.goto(harnessURL());
  // Drives the JS twin of WorkspaceTokenUsageLabelBuilder.abbreviate (Swift) across the
  // same boundaries asserted in WorkspaceTokenUsageLabelBuilderTests, so the two formatters
  // can't drift (esp. the 999999 -> "1m" unit-roll case the normal flow never reaches).
  const results = await page.evaluate(() => {
    const abbreviate = (window as Window & { abbreviateTokens?: (n: number) => string }).abbreviateTokens;
    return [0, 999, 1000, 1050, 1500, 12000, 999949, 999999, 1000000, 1500000].map(value => abbreviate?.(value));
  });
  expect(results).toEqual(['0', '999', '1k', '1.1k', '1.5k', '12k', '999.9k', '1m', '1m', '1.5m']);
});
