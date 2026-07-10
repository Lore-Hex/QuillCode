import { test, expect } from '@playwright/test';
import { harnessURL, sendComposerPrompt } from './harness-helpers';

test('durable goal lifecycle stays visible and follows the selected chat', async ({ page }) => {
  await page.goto(harnessURL());

  await sendComposerPrompt(page, '/goal Ship a green release');
  await expect(page.getByTestId('top-bar-goal')).toHaveText('Goal');
  await expect(page.getByTestId('top-bar-goal')).toHaveAttribute('data-tone', 'active');
  await expect(page.getByTestId('top-bar-goal')).toHaveAttribute('title', /Ship a green release/);

  await sendComposerPrompt(page, '/goal block Waiting for CI');
  await expect(page.getByTestId('top-bar-goal')).toHaveText('Goal blocked');
  await expect(page.getByTestId('top-bar-goal')).toHaveAttribute('data-tone', 'blocked');
  await expect(page.getByTestId('message').last()).toContainText('Blocker: Waiting for CI');

  await sendComposerPrompt(page, '/goal resume');
  await expect(page.getByTestId('top-bar-goal')).toHaveText('Goal');
  await expect(page.getByTestId('top-bar-goal')).toHaveAttribute('data-tone', 'active');

  await sendComposerPrompt(page, '/goal complete');
  await expect(page.getByTestId('top-bar-goal')).toHaveText('Goal complete');
  await expect(page.getByTestId('top-bar-goal')).toHaveAttribute('data-tone', 'completed');

  await sendComposerPrompt(page, '/status');
  await expect(page.getByTestId('message').last()).toContainText('Goal: Completed - Ship a green release');

  await page.getByTestId('new-chat-button').click();
  await expect(page.getByTestId('top-bar-goal')).toHaveCount(0);
});

test('slash suggestions expose durable goal management', async ({ page }) => {
  await page.goto(harnessURL());
  await page.getByLabel('Message').fill('/go');

  const suggestion = page.getByTestId('slash-suggestion').filter({ hasText: 'Follow a goal' });
  await expect(suggestion).toBeVisible();
  await suggestion.click();
  await expect(page.getByLabel('Message')).toHaveValue('/goal ');
  await expect(page.getByLabel('Message')).toBeFocused();
});
