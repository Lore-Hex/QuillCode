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
  await expect(statusMessage).toContainText('Mode: Auto');
  await expect(statusMessage).toContainText('Model: Nike 1.0 (trustedrouter/fast)');
  await expect(statusMessage).toContainText('Agent: Idle');
});

test('mock harness reports Synth status with preferred slash alias after model switch', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByTestId('model-picker-button').click();
  await page.locator('[data-testid="model-option"][data-model-id="tr/synth"]').click();
  await expect(page.getByTestId('model-picker-button')).toHaveText('Synth');

  await page.getByLabel('Message').fill('/status');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('top-bar-subtitle')).toContainText('QuillCode - Auto - Synth');
  const statusMessage = page.getByTestId('message').filter({ hasText: 'Project: QuillCode' });
  await expect(statusMessage).toContainText('Model: Synth (/synth)');
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
