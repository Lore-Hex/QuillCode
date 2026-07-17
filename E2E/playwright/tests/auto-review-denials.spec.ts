import { test, expect } from '@playwright/test';
import { elementRect, harnessURL, sendComposerPrompt } from './harness-helpers';

test('Auto-review denial can be inspected and retried exactly once', async ({ page }) => {
  await page.goto(harnessURL());

  await sendComposerPrompt(page, 'Trigger Auto review denial');

  await expect(page.getByTestId('tool-card')).toHaveCount(1);
  await expect(page.getByTestId('tool-card').first()).toHaveAttribute('data-status', 'done');
  await expect(page.getByTestId('tool-card-subtitle').first()).toContainText('Denied');
  await expect(page.getByTestId('tool-card-output')).toHaveCount(0);
  await expect(page.getByTestId('message').last()).toContainText('nothing ran');
  await expect(page.getByTestId('message')).toHaveCount(2);

  await sendComposerPrompt(page, '/approve');

  const dialog = page.getByTestId('auto-review-denials-dialog');
  const denial = page.getByTestId('auto-review-denial');
  const retry = page.getByTestId('auto-review-denial-retry');
  await expect(dialog).toBeVisible();
  await expect(denial).toHaveAttribute('data-retry-state', 'available');
  await expect(denial).toContainText('Shell command');
  await expect(denial).toContainText('whoami');
  await expect(denial).toContainText('No request found');
  await expect(retry).toBeEnabled();
  await expect(page.getByTestId('message')).toHaveCount(2);
  const retryBounds = await elementRect(page, '[data-testid="auto-review-denial-retry"]');
  expect(retryBounds.width).toBeGreaterThanOrEqual(40);
  expect(retryBounds.height).toBeGreaterThanOrEqual(40);

  await retry.click();
  await expect(retry).toHaveText('Reviewing');
  await expect(retry).toBeDisabled();
  await expect(denial).toHaveAttribute('data-retry-state', 'consumed');
  await expect(retry).toHaveText('Retry used');

  await expect(page.getByTestId('tool-card')).toHaveCount(2);
  await expect(page.getByTestId('tool-card').last()).toHaveAttribute('data-status', 'done');
  await expect(page.getByTestId('tool-card-input').last()).toContainText('whoami');
  await expect(page.getByTestId('tool-card-output').last()).toContainText('mock-user');
  await expect(page.getByTestId('message').last()).toContainText('exact action passed Auto review');

  await page.getByTestId('auto-review-denials-close').click();
  await expect(dialog).toHaveCount(0);
  await sendComposerPrompt(page, '/approve');
  await expect(page.getByTestId('auto-review-denial')).toHaveAttribute('data-retry-state', 'consumed');
  await expect(page.getByTestId('auto-review-denial-retry')).toBeDisabled();
  await expect(page.getByTestId('tool-card')).toHaveCount(2);
  await expect(page.getByTestId('message')).toHaveCount(3);
});

test('/approve shows an empty state for a task without denials', async ({ page }) => {
  await page.goto(harnessURL());
  await sendComposerPrompt(page, 'Hello');

  await sendComposerPrompt(page, '/approve');

  await expect(page.getByTestId('auto-review-denials-dialog')).toBeVisible();
  await expect(page.getByTestId('auto-review-denials-empty')).toHaveText('No recent denials');
  await page.keyboard.press('Escape');
  await expect(page.getByTestId('auto-review-denials-dialog')).toHaveCount(0);
});
