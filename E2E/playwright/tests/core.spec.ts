import { test, expect } from '@playwright/test';

test('mock harness executes simple command flow', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');
  await expect(page.getByTestId('workspace')).toBeVisible();
  await expect(page.getByTestId('top-bar')).toBeVisible();
  await expect(page.getByTestId('sidebar')).toBeVisible();
  await expect(page.getByTestId('project-item')).toContainText('QuillCode');
  await expect(page.getByTestId('project-item')).toHaveAttribute('aria-current', 'true');
  await expect(page.getByTestId('transcript-empty')).toBeVisible();
  await expect(page.getByTestId('model-category')).toHaveCount(2);
  await expect(page.getByLabel('Model')).toHaveValue('trustedrouter/fusion');
  await expect(page.getByTestId('model-pill')).toHaveText('trustedrouter/fusion');
  await expect(page.getByTestId('mode-pill')).toHaveText('Auto');
  await expect(page.getByTestId('send-button')).toBeDisabled();

  await page.getByTestId('settings-button').click();
  await expect(page.getByTestId('settings-panel')).toBeVisible();
  await expect(page.getByTestId('settings-key-status')).toHaveText('No API key saved');
  await page.getByLabel('TrustedRouter API base URL').fill('https://api.trustedrouter.test/v1');
  await page.getByLabel('Enable developer override').check();
  await page.getByLabel('Replace API key').fill('sk-tr-v1-test');
  await page.getByTestId('settings-save').click();
  await expect(page.getByTestId('settings-panel')).toBeHidden();
  await expect(page.getByTestId('agent-status')).toHaveText('TrustedRouter ready');

  await page.getByLabel('Model').selectOption('z-ai/glm-5.2');
  await expect(page.getByTestId('model-pill')).toHaveText('z-ai/glm-5.2');

  await page.getByLabel('Message').fill('run whoami');
  await expect(page.getByTestId('send-button')).toBeEnabled();
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('sidebar-item')).toContainText('run whoami');
  await expect(page.getByTestId('sidebar-item')).toContainText('z-ai/glm-5.2');
  await expect(page.getByTestId('top-bar-title')).toHaveText('run whoami');
  await expect(page.getByTestId('top-bar-subtitle')).toContainText('QuillCode - Auto');
  await expect(page.getByTestId('tool-card-title')).toHaveText('host.shell.run');
  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-status', 'done');
  await expect(page.getByTestId('tool-card-input')).toContainText('whoami');
  await expect(page.getByTestId('tool-card-output')).toContainText('mock-user');
  await expect(page.getByText('Output:\\nmock-user')).toBeVisible();
});

test('mock harness searches and reopens an existing chat', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await page.getByLabel('Message').fill('run whoami');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('sidebar-item')).toContainText('run whoami');

  await page.getByTestId('sidebar-search-button').click();
  await expect(page.getByTestId('search-panel')).toBeVisible();
  await expect(page.getByTestId('search-result')).toContainText('run whoami');

  await page.getByTestId('search-input').fill('whoami');
  await expect(page.getByTestId('search-result')).toHaveCount(1);
  await expect(page.getByTestId('search-result')).toContainText('trustedrouter/fusion');
  await page.getByTestId('search-result').click();

  await expect(page.getByTestId('search-panel')).toHaveCount(0);
  await expect(page.getByTestId('top-bar-title')).toHaveText('run whoami');
  await expect(page.getByTestId('sidebar-item')).toHaveAttribute('aria-current', 'true');
});

test('mock harness starts a new chat from the sidebar action', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await page.getByLabel('Message').fill('run whoami');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('sidebar-item')).toContainText('run whoami');

  await page.getByTestId('new-chat-button').click();

  await expect(page.getByTestId('top-bar-title')).toHaveText('QuillCode');
  await expect(page.getByTestId('top-bar-subtitle')).toContainText('Not started');
  await expect(page.getByTestId('transcript-empty')).toBeVisible();
  await expect(page.getByTestId('sidebar-item')).toHaveAttribute('aria-current', 'false');
  await expect(page.getByTestId('sidebar-item')).toContainText('run whoami');
  await expect(page.getByLabel('Message')).toHaveValue('');
});

test('mock harness opens a new project from the sidebar', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await page.getByTestId('add-project-button').click();

  await expect(page.getByTestId('project-item')).toHaveCount(2);
  await expect(page.getByTestId('project-item').first()).toContainText('Example Project 2');
  await expect(page.getByTestId('project-item').first()).toContainText('/mock/example-2');
  await expect(page.getByTestId('project-item').first()).toHaveAttribute('aria-current', 'true');
  await expect(page.getByTestId('top-bar-subtitle')).toContainText('Example Project 2');

  await page.getByTestId('terminal-button').click();
  await expect(page.getByTestId('terminal-cwd')).toHaveText('/mock/example-2');
});

test('mock harness runs a command in the integrated terminal', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await page.getByTestId('terminal-button').click();
  await expect(page.getByTestId('terminal-pane')).toBeVisible();
  await expect(page.getByTestId('terminal-cwd')).toHaveText('/mock/QuillCode');
  await expect(page.getByTestId('terminal-empty')).toBeVisible();

  await page.getByLabel('Terminal command').fill('pwd');
  await expect(page.getByTestId('terminal-run')).toBeEnabled();
  await page.getByTestId('terminal-run').click();

  await expect(page.getByTestId('terminal-entry')).toContainText('$ pwd');
  await expect(page.getByTestId('terminal-status')).toHaveText('Done · exit 0');
  await expect(page.getByTestId('terminal-stdout')).toContainText('/mock/QuillCode');
  await expect(page.getByLabel('Terminal command')).toHaveValue('');
});

test('mock harness shows git review summary for diff flow', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await page.getByLabel('Message').fill('git diff');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('review-pane')).toBeVisible();
  await expect(page.getByTestId('review-summary')).toHaveText('1 file changed, +1 -0');
  await expect(page.getByTestId('review-file')).toContainText('Sources/App.swift');
  await expect(page.getByTestId('tool-card-title')).toHaveText('host.git.diff');
  await expect(page.getByTestId('tool-card-output')).toContainText('diff --git');
});

test('mock harness stages a changed file from the review pane', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await page.getByLabel('Message').fill('git diff');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('review-pane')).toBeVisible();
  await expect(page.getByTestId('review-action')).toHaveCount(4);

  await page.getByRole('button', { name: 'Stage', exact: true }).click();

  await expect(page.getByTestId('review-pane')).toHaveCount(0);
  await expect(page.getByTestId('agent-status')).toHaveText('Idle');
  await expect(page.getByTestId('tool-card-title')).toHaveText([
    'host.git.diff',
    'host.git.stage',
    'host.git.diff'
  ]);
  await expect(page.getByTestId('tool-card-input').nth(1)).toContainText('Sources/App.swift');
});

test('mock harness stages a single hunk from the review pane', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await page.getByLabel('Message').fill('git diff');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('review-hunk')).toBeVisible();
  await expect(page.getByTestId('review-hunk-header')).toContainText('@@ -1 +1,2 @@');

  await page.getByRole('button', { name: 'Stage hunk' }).click();

  await expect(page.getByTestId('review-pane')).toHaveCount(0);
  await expect(page.getByTestId('tool-card-title')).toHaveText([
    'host.git.diff',
    'host.git.stage_hunk',
    'host.git.diff'
  ]);
  await expect(page.getByTestId('tool-card-input').nth(1)).toContainText('Sources/App.swift');
});

test('mock harness commits staged changes in one turn', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await page.getByLabel('Message').fill('commit these changes with message Add hello file');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.git.commit');
  await expect(page.getByTestId('tool-card-input')).toContainText('Add hello file');
  await expect(page.getByTestId('tool-card-output')).toContainText('[main abc1234] Add hello file');
  await expect(page.getByText('Output:\\n[main abc1234] Add hello file')).toBeVisible();
});

test('mock harness handles slash mode locally', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await page.getByLabel('Message').fill('/mode review');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('mode-pill')).toHaveText('Review');
  await expect(page.getByTestId('top-bar-subtitle')).toContainText('QuillCode - Review');
  await expect(page.getByText('Mode set to Review.')).toBeVisible();
  await expect(page.getByTestId('tool-card')).toHaveCount(0);
});
