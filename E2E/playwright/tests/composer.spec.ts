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
  await expect(page.getByTestId('mode-pill')).toHaveText('Review');
  await expect(page.getByTestId('model-picker-button')).toHaveText('Nike 1.0');

  await page.getByTestId('mode-picker-button').click();
  await expect(page.getByTestId('mode-pill')).toHaveText('Read-only');
  await expect(page.getByTestId('mode-picker-button')).toHaveAttribute('data-mode-tone', 'read-only');
  await expect(page.getByTestId('model-picker-button')).not.toContainText('Read-only');
});

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

  await page.getByLabel('Message').fill('/compact');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('top-bar-title')).toContainText('Compact:');
  await expect(page.getByTestId('message').first()).toContainText('Context compacted from');
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

  await message.fill('/workt');
  await page.getByTestId('slash-suggestion').first().click();
  await expect(message).toHaveValue('/worktrees');
  await expect(message).toBeFocused();
});

test('mock harness suggests workspace files for @ mentions in the composer', async ({ page }) => {
  await page.goto(harnessURL());

  const message = page.getByLabel('Message');

  // A bare @ surfaces workspace files, shallowest path first.
  await message.fill('@');
  await expect(page.getByTestId('file-mention-suggestions')).toBeVisible();
  await expect(page.getByTestId('file-mention-suggestion')).toHaveCount(2);
  await expect(page.getByTestId('file-mention-suggestion').first()).toContainText('README.md');
  await expect(page.locator('[data-testid="file-mention-suggestion"][data-selected="true"]')).toContainText('README.md');

  // ArrowDown moves the active mention.
  await page.keyboard.press('ArrowDown');
  await expect(page.locator('[data-testid="file-mention-suggestion"][data-selected="true"]')).toContainText('Sources/Agent.swift');

  // An email-style token is not treated as a mention.
  await message.fill('ping name@example.com');
  await expect(page.getByTestId('file-mention-suggestions')).toHaveCount(0);

  // A name prefix ranks the matching file first.
  await message.fill('look at @Agent');
  await expect(page.getByTestId('file-mention-suggestion')).toHaveCount(1);
  await expect(page.getByTestId('file-mention-suggestion').first()).toContainText('Agent.swift');

  // Enter accepts the active mention, replacing the @token and adding a trailing space.
  await page.keyboard.press('Enter');
  await expect(message).toHaveValue('look at @Sources/Agent.swift ');
  await expect(message).toBeFocused();
  await expect(page.getByTestId('file-mention-suggestions')).toHaveCount(0);

  // Tab completes the selected file mention.
  await message.fill('read @READ');
  await page.keyboard.press('Tab');
  await expect(message).toHaveValue('read @README.md ');

  // Click-to-insert accepts a file mention.
  await message.fill('open @Agent');
  await page.getByTestId('file-mention-suggestion').first().click();
  await expect(message).toHaveValue('open @Sources/Agent.swift ');
  await expect(message).toBeFocused();

  // Slash commands take precedence over file mentions.
  await message.fill('/help');
  await expect(page.getByTestId('file-mention-suggestions')).toHaveCount(0);
  await expect(page.getByTestId('slash-suggestions')).toBeVisible();
});

test('mock harness searches and selects models from the composer', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByTestId('model-picker-button').click();
  await expect(page.getByTestId('model-browser')).toBeVisible();
  await expect(page.getByTestId('model-result-count')).toHaveText('5 models available');
  await expect(page.getByTestId('model-option-summary').first()).toContainText('Fast everyday agent');
  await expect(page.getByTestId('model-badge').nth(0)).toHaveText('Current');
  await expect(page.getByTestId('model-badge').nth(1)).toHaveText('Default');
  await expect(page.getByTestId('model-badge').nth(2)).toHaveText('Recommended');
  await expect(page.getByTestId('model-detail-button').first()).toHaveAttribute('aria-expanded', 'true');
  await expect(page.getByTestId('model-capability')).toContainText('Nike 1.0 is the fast default');
  await expect(page.getByTestId('model-metadata-row').filter({ hasText: 'trustedrouter/fast' })).toBeVisible();
  await expect(page.getByTestId('model-metadata-row').filter({ hasText: 'Current, Default, Recommended' })).toBeVisible();
  await expect(page.getByTestId('model-option')).toHaveCount(5);

  await page.getByTestId('model-detail-button').nth(1).click();
  await expect(page.getByTestId('model-detail-button').nth(1)).toHaveAttribute('aria-expanded', 'true');
  await expect(page.getByTestId('model-capability')).toContainText('Synth is the balanced model');
  await expect(page.getByTestId('model-metadata-row').filter({ hasText: 'tr/synth' })).toBeVisible();

  await page.getByTestId('model-detail-button').nth(2).click();
  await expect(page.getByTestId('model-detail-button').nth(2)).toHaveAttribute('aria-expanded', 'true');
  await expect(page.getByTestId('model-capability')).toContainText('Synth Code is the code-focused model');
  await expect(page.getByTestId('model-metadata-row').filter({ hasText: 'tr/synth-code' })).toBeVisible();

  await page.getByTestId('model-search').fill('default model');
  await expect(page.getByTestId('model-result-count')).toHaveText('1 model for "default model"');
  await expect(page.getByTestId('model-option')).toHaveCount(1);
  await expect(page.getByTestId('model-option')).toContainText('Nike 1.0');
  await page.getByTestId('model-search').fill('');

  await page.getByTestId('model-favorite-button').nth(1).click();
  await expect(page.getByTestId('model-browser')).toBeVisible();
  await expect(page.getByTestId('model-category').first()).toContainText('Favorites');
  await expect(page.getByTestId('model-option')).toHaveCount(6);
  await expect(page.getByTestId('model-favorite-button').first()).toHaveAttribute('aria-label', 'Remove favorite model');

  await page.getByTestId('model-search').fill('favorite');
  await expect(page.getByTestId('model-category')).toHaveCount(1);
  await expect(page.getByTestId('model-category')).toContainText('Favorites');
  await expect(page.getByTestId('model-option')).toHaveCount(1);

  await page.getByTestId('model-search').fill('moon k2');
  await expect(page.getByTestId('model-option')).toHaveCount(1);
  await expect(page.getByTestId('model-option')).toContainText('moonshotai/Kimi K2.6');

  await page.getByTestId('model-option').click();
  await expect(page.getByTestId('model-picker-button')).toHaveText('moonshotai/Kimi K2.6');
  await expect(page.getByTestId('mode-pill')).toHaveText('Auto');
  await expect(page.getByTestId('model-browser')).toHaveCount(0);

  await page.getByTestId('model-picker-button').click();
  await page.getByTestId('model-search').fill('not-a-model');
  await expect(page.getByTestId('model-result-count')).toHaveText('0 models for "not-a-model"');
  await expect(page.getByTestId('model-empty')).toBeVisible();
  await page.getByTestId('model-clear-search').first().click();
  await expect(page.getByTestId('model-search')).toBeFocused();
  await expect(page.getByTestId('model-result-count')).toHaveText('6 models available');
  await expect(page.getByTestId('model-option')).toHaveCount(6);
});

test('mock harness supports keyboard navigation in the model picker', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByTestId('model-picker-button').click();
  await expect(page.getByTestId('model-search')).toBeFocused();
  await page.getByTestId('model-search').fill('synth');

  await expect(page.getByTestId('model-option')).toHaveCount(2);
  await expect(page.getByTestId('model-option').nth(0)).toHaveAttribute('data-highlighted', 'true');

  await page.keyboard.press('ArrowDown');
  await expect(page.getByTestId('model-option').nth(1)).toHaveAttribute('data-highlighted', 'true');

  await page.keyboard.press('Enter');
  await expect(page.getByTestId('model-picker-button')).toHaveText('Synth Code');
  await expect(page.getByTestId('model-browser')).toHaveCount(0);
});
