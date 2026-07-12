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

  await page.getByLabel('Message').fill('/review');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('review-pane')).toBeVisible();
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.diff');

  await page.getByLabel('Message').fill('/git-status');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.status');

  await page.getByLabel('Message').fill('/worktrees');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.worktree.list');
  await expect(page.getByTestId('tool-card-output').last()).toContainText('/mock/quillcode-existing');

  await page.getByLabel('Message').fill('/project open');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('project-item').first()).toContainText('Example Project');
  await expect(page.getByTestId('top-bar-subtitle')).toContainText('Example Project');

  await page.getByLabel('Message').fill('/project list');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('message').last()).toContainText('Projects:\n- Example Project');
  await expect(page.getByTestId('message').last()).toContainText('selected, Local');
  await expect(page.getByTestId('message').last()).toContainText('/mock/example-');

  await page.getByLabel('Message').fill('/project remove');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('project-item')).toHaveCount(1);
  await expect(page.getByTestId('project-item').first()).toContainText('QuillCode');
  await expect(page.getByTestId('project-count')).toHaveText('1 project');

  await page.getByLabel('Message').fill('/project open');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('project-item').first()).toContainText('Example Project');
  await expect(page.getByTestId('top-bar-subtitle')).toContainText('Example Project');

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
  await message.fill('/focus');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(message).toBeFocused();
  await expect(message).toHaveValue('');

  await message.fill('/sidebar');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('sidebar')).toHaveCount(0);
  await expect(message).toHaveValue('');

  await message.fill('/sidebar');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('sidebar')).toBeVisible();
  await expect(message).toHaveValue('');

  await message.fill('/settings');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('settings-panel')).toBeVisible();
  await expect(message).toHaveValue('');
  await page.getByTestId('settings-cancel').click();

  await message.fill('/computer-use');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('settings-panel')).toBeVisible();
  await expect(page.getByTestId('computer-use-settings')).toBeVisible();
  await expect(message).toHaveValue('');
  await page.getByTestId('settings-cancel').click();

  await message.fill('/shortcuts');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('keyboard-shortcuts-panel')).toBeVisible();
  await expect(page.getByTestId('keyboard-shortcuts-list')).toContainText('Search');
  await expect(message).toHaveValue('');
  await page.getByTestId('keyboard-shortcuts-close').click();

  await message.fill('/commands');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('command-palette-panel')).toBeVisible();
  await expect(page.getByTestId('command-palette-input')).toBeFocused();
  await expect(message).toHaveValue('');
  await page.keyboard.press('Escape');

  await message.fill('/plugins');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('extensions-pane')).toBeVisible();
  await expect(message).toHaveValue('');

  await message.fill('/automations');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('automations-pane')).toBeVisible();
  await expect(message).toHaveValue('');

  await message.fill('/activity');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('activity-pane')).toBeVisible();
  await expect(message).toHaveValue('');
});

test('mock harness routes control slash commands through existing stop and retry actions', async ({ page }) => {
  await page.goto(harnessURL());

  const message = page.getByLabel('Message');
  await message.fill('run a stuck task');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('top-bar-stop-button')).toBeVisible();
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.shell.run');

  await message.fill('/stop');
  await page.getByTestId('send-button').click();
  await expect(page.getByTestId('agent-status')).toContainText('Stopped');
  await expect(page.getByTestId('tool-card-status').last()).toHaveText('Failed');
  await expect(page.getByTestId('tool-card-output').last()).toContainText('Stopped by user');
  await expect(page.getByTestId('message').last()).toContainText('/stop');

  await message.fill('whoami');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('message').last()).toContainText('mock-user');
  const shellCardCount = await page.getByTestId('tool-card-title').filter({ hasText: 'host.shell.run' }).count();

  await message.fill('/retry');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('tool-card-title').filter({ hasText: 'host.shell.run' })).toHaveCount(shellCardCount + 1);
  await expect(page.getByTestId('message').last()).toContainText('mock-user');
  await expect(page.getByTestId('message').filter({ hasText: '/retry' })).toHaveCount(1);

  await message.fill('/disconnect');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('agent-status')).toContainText('Stopped');
  await expect(page.getByTestId('message').last()).toContainText('/disconnect');
});

test('mock harness routes history slash commands through workspace back and forward', async ({ page }) => {
  await page.goto(harnessURL());

  const message = page.getByLabel('Message');
  await message.fill('whoami');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('message').last()).toContainText('mock-user');

  await page.keyboard.press('Meta+N');
  await expect(page.getByTestId('transcript-empty')).toBeVisible();

  await message.fill('/back');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('message').filter({ hasText: 'whoami' })).toBeVisible();
  await expect(page.getByTestId('message').filter({ hasText: 'mock-user' })).toBeVisible();

  await message.fill('/forward');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('transcript-empty')).toBeVisible();

  await message.fill('/history back');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('message').filter({ hasText: 'whoami' })).toBeVisible();

  await message.fill('/history forward');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('transcript-empty')).toBeVisible();
});

test('mock harness suggests and runs the new-worktree thread command', async ({ page }) => {
  await page.goto(harnessURL());

  const message = page.getByLabel('Message');

  // Suggestion: /new-w surfaces the new-worktree-chat command, distinct from /new.
  await message.fill('/new-w');
  await expect(page.getByTestId('slash-suggestion').first()).toContainText('/new-worktree');
  await expect(page.getByTestId('slash-suggestion').first()).toContainText('New worktree chat');

  // Execution: /new-worktree routes through the thread-new-worktree command (mock stand-in for the
  // worktree-bound thread native creates) — NOT swallowed by /new, NOT sent as a chat prompt.
  const before = await page.getByTestId('sidebar-thread-row').count();
  await message.fill('/new-worktree');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('message').last())
    .toContainText('Started a detached worktree chat with the current local changes.');
  await expect
    .poll(async () => page.getByTestId('sidebar-thread-row').count())
    .toBeGreaterThan(before);
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

  await message.fill('/project o');
  await expect(page.getByTestId('slash-suggestion').first()).toContainText('/project open');
  await page.keyboard.press('Tab');
  await expect(message).toHaveValue('/project open');

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
