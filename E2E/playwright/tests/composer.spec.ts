import { test, expect } from '@playwright/test';
import { harnessURL } from './harness-helpers';

test('mock harness composer supports multiline editing and Enter-to-send', async ({ page }) => {
  await page.goto(harnessURL());

  const message = page.getByLabel('Message');
  await expect(message).toHaveJSProperty('tagName', 'TEXTAREA');
  await message.fill('first line');
  const initialHeight = await message.evaluate((element: HTMLTextAreaElement) => element.clientHeight);

  await message.press('Shift+Enter');
  await page.keyboard.type('second line');

  await expect(message).toHaveValue('first line\nsecond line');
  const expandedHeight = await message.evaluate((element: HTMLTextAreaElement) => element.clientHeight);
  expect(expandedHeight).toBeGreaterThan(initialHeight);
  await expect(page.getByTestId('message')).toHaveCount(0);

  await message.press('Enter');

  await expect(message).toHaveValue('');
  await expect(page.getByTestId('message').first()).toContainText('first line');
  await expect(page.getByTestId('message').first()).toContainText('second line');
});

test('mock harness shows sent message and thinking state before async work completes', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('slow task');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByLabel('Message')).toBeDisabled();
  await expect(page.getByTestId('message').first()).toContainText('slow task');
  await expect(page.getByTestId('thinking-indicator')).toBeVisible();
  await expect(page.getByTestId('thinking-title')).toHaveText('Thinking');
  await expect(page.getByTestId('thinking-subtitle')).toContainText(/Preparing the next step|host\.shell\.run/);
  await expect(page.getByTestId('agent-status')).toHaveText('Running');
  await expect(page.getByText('Long-running task completed.')).toHaveCount(0);
});

test('mock harness stops an active composer run from the composer', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('slow task');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('agent-status')).toHaveText('Running');
  await expect(page.getByTestId('top-bar-stop-button')).toBeVisible();
  await expect(page.getByTestId('stop-button')).toBeVisible();
  await expect(page.getByTestId('send-button')).toHaveCount(0);
  await expect(page.getByLabel('Message')).toBeDisabled();
  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-status', 'running');

  await page.getByTestId('top-bar-stop-button').click();

  await expect(page.getByTestId('agent-status')).toHaveText('Stopped');
  await expect(page.getByTestId('top-bar-stop-button')).toHaveCount(0);
  await expect(page.getByTestId('stop-button')).toHaveCount(0);
  await expect(page.getByTestId('send-button')).toBeDisabled();
  await expect(page.getByLabel('Message')).toBeEnabled();
  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-status', 'failed');
  await expect(page.getByTestId('tool-card')).toContainText('Stopped');

  await page.waitForTimeout(2200);
  await expect(page.getByText('Long-running task completed.')).toHaveCount(0);
  await expect(page.getByTestId('agent-status')).toHaveText('Stopped');
});

test('mock harness handles slash mode locally', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('/mode review');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('mode-pill')).toHaveText('Review');
  await expect(page.getByTestId('mode-picker-button')).toContainText('Review');
  await expect(page.getByTestId('mode-picker-button')).toHaveAttribute('data-mode-tone', 'review');
  await expect(page.getByTestId('top-bar-subtitle')).toContainText('QuillCode - Review');
  await expect(page.getByText('Mode set to Review.')).toBeVisible();
  await expect(page.getByTestId('tool-card')).toHaveCount(0);
});

test('mock harness changes approval mode independently from model selection', async ({ page }) => {
  await page.goto(harnessURL());

  await expect(page.getByTestId('model-picker-button')).toHaveText('Nike 1.0');
  await expect(page.getByTestId('mode-pill')).toHaveText('Auto');

  await page.getByTestId('mode-picker-button').click();
  await expect(page.getByTestId('mode-pill')).toHaveText('Plan');
  await expect(page.getByTestId('mode-picker-button')).toHaveAttribute('data-mode-tone', 'plan');
  await expect(page.getByTestId('model-picker-button')).toHaveText('Nike 1.0');

  await page.getByTestId('mode-picker-button').click();
  await expect(page.getByTestId('mode-pill')).toHaveText('Review');

  await page.getByTestId('mode-picker-button').click();
  await expect(page.getByTestId('mode-pill')).toHaveText('Read-only');
  await expect(page.getByTestId('mode-picker-button')).toHaveAttribute('data-mode-tone', 'read-only');
  await expect(page.getByTestId('model-picker-button')).not.toContainText('Read-only');
});
