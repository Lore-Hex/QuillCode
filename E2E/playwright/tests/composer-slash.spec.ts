import { test, expect } from '@playwright/test';
import { harnessURL } from './harness-helpers';

test('mock harness routes slash commands to workspace actions', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('/terminal');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('terminal-pane')).toBeVisible();
  await expect(page.getByText('Terminal opened.')).toBeVisible();

  await page.getByLabel('Message').fill('/browser');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('browser-pane')).toBeVisible();
  await expect(page.getByText('Browser opened.')).toBeVisible();

  await page.getByLabel('Message').fill('/diff');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.diff');

  await page.getByLabel('Message').fill('/git-status');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.status');

  await page.getByLabel('Message').fill('/worktrees');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.worktree.list');
  await expect(page.getByTestId('tool-card-output').last()).toContainText('/mock/quillcode-existing');

  await page.getByLabel('Message').fill('/worktree create slash-worktree --branch slash/demo --base main');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('project-item').first()).toContainText('slash-worktree');
  await expect(page.getByTestId('top-bar-title')).toHaveText('Worktree: slash/demo');
  await expect(page.getByTestId('message').last()).toContainText('Opened worktree slash-worktree at /mock/slash-worktree.');

  await page.getByLabel('Message').fill('/worktree open slash-worktree');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('top-bar-title')).toHaveText('Worktree: slash-worktree');
  await expect(page.getByTestId('message').last()).toContainText('Opened worktree slash-worktree at /mock/slash-worktree.');

  await page.getByLabel('Message').fill('/worktree remove slash-worktree --force');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.worktree.remove');
  await expect(page.getByTestId('tool-card-input').last()).toContainText('"force": true');
  await expect(page.getByTestId('message').last()).toContainText('Removed worktree slash-worktree.');

  await page.getByLabel('Message').fill('/worktree prune --dry-run --verbose');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.worktree.prune');
  await expect(page.getByTestId('tool-card-input').last()).toContainText('"dryRun": true');
  await expect(page.getByTestId('message').last()).toContainText('No stale worktree records found.');

  await page.getByLabel('Message').fill('/pr');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByLabel('Message')).toHaveValue('Create a pull request titled ');

  await page.getByLabel('Message').fill('/pr fill');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.pr.create');
  await expect(page.getByTestId('tool-card-input').last()).toContainText('"fill": true');
  await expect(page.getByTestId('message').last()).toContainText('Opened a pull request for the current branch');

  await page.getByLabel('Message').fill('/compact');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('top-bar-title')).toContainText('Compact:');
  await expect(page.getByTestId('message').first()).toContainText('Context compacted from');
});

test('mock harness opens search surfaces from composer slash commands', async ({ page }) => {
  await page.goto(harnessURL());

  const message = page.getByLabel('Message');
  await message.fill('needle in the transcript');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('sidebar-item')).toContainText('needle in the transcript');

  await message.fill('/search');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('search-panel')).toBeVisible();
  await expect(page.getByTestId('search-input')).toBeFocused();
  await expect(message).toHaveValue('');
  await page.keyboard.type('needle');
  await expect(page.getByTestId('search-result')).toContainText('needle in the transcript');
  await page.getByTestId('search-close').click();

  await message.fill('/find');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('find-input')).toBeFocused();
  await expect(message).toHaveValue('');
  await page.keyboard.type('needle');
  await expect(page.getByTestId('find-status')).toContainText('1 of 1');
});

test('mock harness opens utility surfaces from composer slash commands', async ({ page }) => {
  await page.goto(harnessURL());

  const message = page.getByLabel('Message');
  await message.fill('/settings');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('settings-panel')).toBeVisible();
  await expect(message).toHaveValue('');
  await page.getByTestId('settings-cancel').click();

  await message.fill('/shortcuts');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('keyboard-shortcuts-panel')).toBeVisible();
  await expect(page.getByTestId('keyboard-shortcuts-list')).toContainText('Search');
  await expect(message).toHaveValue('');
});

test('mock harness suggests slash commands in the composer', async ({ page }) => {
  await page.goto(harnessURL());

  const message = page.getByLabel('Message');
  await message.fill('/');
  await expect(page.getByTestId('slash-suggestions')).toBeVisible();
  await expect(page.getByTestId('slash-suggestion')).toHaveCount(6);
  await expect(page.getByTestId('slash-suggestion').first()).toContainText('/help');
  await expect(page.locator('[data-testid="slash-suggestion"][data-selected="true"]')).toContainText('/help');

  await page.keyboard.press('ArrowDown');
  await expect(page.locator('[data-testid="slash-suggestion"][data-selected="true"]')).toContainText('/status');

  await message.fill('/workt');
  await expect(page.getByTestId('slash-suggestion').first()).toContainText('/worktrees');
  await page.keyboard.press('Enter');
  await expect(message).toHaveValue('/worktrees');
  await expect(message).toBeFocused();

  await page.keyboard.press('Enter');
  await expect(page.getByTestId('slash-suggestions')).toHaveCount(0);
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.worktree.list');

  await message.fill('/worktree c');
  await expect(page.getByTestId('slash-suggestion').first()).toContainText('/worktree create path');
  await page.keyboard.press('Tab');
  await expect(message).toHaveValue('/worktree create ');

  await message.fill('/project r');
  await page.keyboard.press('ArrowDown');
  await expect(page.locator('[data-testid="slash-suggestion"][data-selected="true"]')).toContainText('/project rename name');
  await page.keyboard.press('Tab');
  await expect(message).toHaveValue('/project rename ');

  await message.fill('/fol');
  await expect(page.getByTestId('slash-suggestion').first()).toContainText('/follow-up when');
  await page.keyboard.press('Enter');
  await expect(message).toHaveValue('/follow-up in ');

  await message.fill('/workspace-c');
  await expect(page.getByTestId('slash-suggestion').first()).toContainText('/workspace-check when');
  await page.keyboard.press('Enter');
  await expect(message).toHaveValue('/workspace-check in ');

  await message.fill('/suba');
  await expect(page.getByTestId('slash-suggestion').first()).toContainText('/subagents objective | Name: role');
  await page.keyboard.press('Enter');
  await expect(message).toHaveValue('/subagents ');

  await message.fill('/workt');
  await page.getByTestId('slash-suggestion').first().click();
  await expect(message).toHaveValue('/worktrees');
  await expect(message).toBeFocused();
});
