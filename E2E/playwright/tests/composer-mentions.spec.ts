import { test, expect } from '@playwright/test';
import { harnessURL } from './harness-helpers';

test('mock harness suggests workspace files for @ mentions in the composer', async ({ page }) => {
  await page.goto(harnessURL());

  const message = page.getByLabel('Message');

  await message.fill('@');
  await expect(page.getByTestId('file-mention-suggestions')).toBeVisible();
  await expect(page.getByTestId('file-mention-suggestion')).toHaveCount(4);

  const firstMention = page.getByTestId('file-mention-suggestion').first();
  await expect(firstMention).toContainText('Sources');
  await expect(firstMention).toHaveAttribute('data-kind', 'directory');
  await expect(page.locator('[data-testid="file-mention-suggestion"][data-selected="true"]'))
    .toHaveAttribute('data-kind', 'directory');

  await page.keyboard.press('ArrowDown');
  await expect(page.locator('[data-testid="file-mention-suggestion"][data-selected="true"]'))
    .toContainText('README.md');

  await message.fill('ping name@example.com');
  await expect(page.getByTestId('file-mention-suggestions')).toHaveCount(0);

  await message.fill('look at @Agent');
  await expect(page.getByTestId('file-mention-suggestion')).toHaveCount(1);
  await expect(page.getByTestId('file-mention-suggestion').first()).toContainText('Agent.swift');

  await page.keyboard.press('Enter');
  await expect(message).toHaveValue('look at @Sources/Agent.swift ');
  await expect(message).toBeFocused();
  await expect(page.getByTestId('file-mention-suggestions')).toHaveCount(0);

  await message.fill('read @READ');
  await page.keyboard.press('Tab');
  await expect(message).toHaveValue('read @README.md ');

  await message.fill('open @Agent');
  await page.getByTestId('file-mention-suggestion').first().click();
  await expect(message).toHaveValue('open @Sources/Agent.swift ');
  await expect(message).toBeFocused();

  await message.fill('open @Sour');
  const dirRow = page.locator('[data-testid="file-mention-suggestion"][data-kind="directory"]').first();
  await expect(dirRow).toContainText('Sources');
  await dirRow.click();
  await expect(message).toHaveValue('open @Sources/ ');

  await message.fill('/help');
  await expect(page.getByTestId('file-mention-suggestions')).toHaveCount(0);
  await expect(page.getByTestId('slash-suggestions')).toBeVisible();
});

test('mock harness boosts and badges changed files in @ mentions after a git status', async ({ page }) => {
  await page.goto(harnessURL());
  const message = page.getByLabel('Message');

  await message.fill('@');
  await expect(page.locator('[data-testid="file-mention-suggestion"][data-changed="true"]')).toHaveCount(0);

  await message.fill('/git-status');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.status');

  await message.fill('@');
  const first = page.getByTestId('file-mention-suggestion').first();
  await expect(first).toContainText('Sources/App.swift');
  await expect(first).toHaveAttribute('data-changed', 'true');
  await expect(first.getByTestId('file-mention-changed-badge')).toBeVisible();
  await expect(page.locator('[data-testid="file-mention-suggestion"][data-path="Sources/Agent.swift"]'))
    .toHaveAttribute('data-changed', 'false');
});
