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
  await expect(page.getByTestId('settings-key-status')).toHaveText('Not signed in');
  await page.getByLabel('TrustedRouter API base URL').fill('https://api.trustedrouter.test/v1');
  await page.getByLabel('Authentication').selectOption('developer-override');
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
  await expect(page.getByText('You are `mock-user` in this workspace.')).toBeVisible();
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

  await page.getByTestId('search-input').fill('mock-user');
  await expect(page.getByTestId('search-result')).toHaveCount(1);
  await expect(page.getByTestId('search-result')).toContainText('run whoami');

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

test('mock harness shows context pressure banner and forks from latest turn', async ({ page }) => {
  test.setTimeout(60000);
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  const longPrompt = 'long context ' + 'word '.repeat(22000);
  await page.getByLabel('Message').fill(longPrompt);
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('context-banner')).toBeVisible();
  await expect(page.getByTestId('context-banner-title')).toContainText(/context limit/i);

  await page.getByLabel('Message').fill('run whoami');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('context-banner')).toBeVisible();

  await page.getByTestId('context-fork-last').click();

  await expect(page.getByTestId('top-bar-title')).toContainText('Fork:');
  await expect(page.getByTestId('context-banner')).toHaveCount(0);
  await expect(page.getByTestId('message').first()).toContainText('run whoami');
  await expect(page.getByText('You are `mock-user` in this workspace.')).toBeVisible();
});

test('mock harness runs a command from the command palette', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await page.getByTestId('command-palette-button').click();
  await expect(page.getByTestId('command-palette-panel')).toBeVisible();
  await page.getByLabel('Search commands').fill('terminal');
  await expect(page.getByTestId('command-palette-result')).toHaveCount(1);
  await page.getByTestId('command-palette-result').click();

  await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);
  await expect(page.getByTestId('terminal-pane')).toBeVisible();
});

test('mock harness dispatches workspace keyboard shortcuts', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await page.keyboard.press('Meta+K');
  await expect(page.getByTestId('search-panel')).toBeVisible();
  await page.getByTestId('search-close').click();

  await page.keyboard.press('Meta+Shift+P');
  await expect(page.getByTestId('command-palette-panel')).toBeVisible();
  await page.getByTestId('command-palette-close').click();

  await page.keyboard.press('Control+Backquote');
  await expect(page.getByTestId('terminal-pane')).toBeVisible();

  await page.keyboard.press('Meta+Shift+B');
  await expect(page.getByTestId('browser-pane')).toBeVisible();

  await page.getByLabel('Message').fill('run whoami');
  await page.getByRole('button', { name: 'Send' }).click();
  await page.keyboard.press('Meta+N');

  await expect(page.getByTestId('transcript-empty')).toBeVisible();
});

test('mock harness ranks and navigates command palette with keyboard', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await page.getByTestId('command-palette-button').click();
  await expect(page.getByTestId('command-palette-group').first()).toContainText('Thread');

  await page.getByLabel('Search commands').fill('shell');
  await expect(page.locator('[data-testid="command-palette-result"][data-selected="true"]')).toContainText('Terminal');
  await page.keyboard.press('Enter');
  await expect(page.getByTestId('terminal-pane')).toBeVisible();

  await page.keyboard.press('Meta+Shift+P');
  await page.getByLabel('Search commands').fill('worktree');
  await expect(page.getByTestId('command-palette-group')).toHaveCount(1);
  await expect(page.getByTestId('command-palette-group')).toContainText('Git');
  await expect(page.locator('[data-testid="command-palette-result"][data-selected="true"]')).toContainText('List worktrees');

  await page.keyboard.press('ArrowDown');
  await expect(page.locator('[data-testid="command-palette-result"][data-selected="true"]')).toContainText('Create worktree');
  await page.keyboard.press('Enter');
  await expect(page.getByTestId('worktree-create-panel')).toBeVisible();
});

test('mock harness lists worktrees from the command palette', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await page.getByTestId('command-palette-button').click();
  await page.getByLabel('Search commands').fill('worktree');

  await expect(page.getByTestId('command-palette-result')).toHaveCount(3);
  await page.getByRole('button', { name: /List worktrees/ }).click();

  await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);
  await expect(page.getByTestId('tool-card-title')).toHaveText('host.git.worktree.list');
  await expect(page.getByTestId('tool-card-output')).toContainText('/mock/QuillCode-feature');
  await expect(page.getByTestId('message').last()).toContainText('worktree /mock/QuillCode');
});

test('mock harness prepares pull request creation from the command palette', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await page.getByTestId('command-palette-button').click();
  await page.getByLabel('Search commands').fill('pull request');
  await expect(page.getByTestId('command-palette-result')).toHaveCount(1);
  await page.getByRole('button', { name: /Create pull request/ }).click();

  await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);
  await expect(page.getByLabel('Message')).toHaveValue('Create a pull request titled ');
});

test('mock harness runs local environment action from the command palette', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await page.getByTestId('command-palette-button').click();
  await page.getByLabel('Search commands').fill('bootstrap');
  await expect(page.getByTestId('command-palette-result')).toHaveCount(1);
  await page.getByRole('button', { name: /Run Bootstrap/ }).click();

  await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);
  await expect(page.getByTestId('tool-card-title')).toHaveText('host.shell.run');
  await expect(page.getByTestId('tool-card-input')).toContainText(".quillcode/actions/bootstrap.sh");
  await expect(page.getByTestId('message').last()).toContainText('Local environment action completed');
});

test('mock harness creates and removes worktrees from dialogs', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await page.getByTestId('command-palette-button').click();
  await page.getByLabel('Search commands').fill('create worktree');
  await page.getByRole('button', { name: /Create worktree/ }).click();
  await expect(page.getByTestId('worktree-create-panel')).toBeVisible();
  await expect(page.getByTestId('worktree-create-submit')).toBeDisabled();

  await page.getByLabel('Worktree folder').fill('quillcode-feature');
  await page.getByLabel('New branch').fill('feature/quillcode');
  await page.getByLabel('Base ref').fill('main');
  await expect(page.getByTestId('worktree-create-submit')).toBeEnabled();
  await page.getByTestId('worktree-create-submit').click();

  await expect(page.getByTestId('worktree-create-panel')).toHaveCount(0);
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.worktree.create');
  await expect(page.getByTestId('tool-card-input').last()).toContainText('feature/quillcode');
  await expect(page.getByTestId('message').last()).toContainText('Created worktree quillcode-feature.');

  await page.getByTestId('command-palette-button').click();
  await page.getByLabel('Search commands').fill('remove worktree');
  await page.getByRole('button', { name: /Remove worktree/ }).click();
  await expect(page.getByTestId('worktree-remove-panel')).toBeVisible();

  await page.getByLabel('Worktree folder').fill('quillcode-feature');
  await page.getByLabel('Force removal').check();
  await page.getByTestId('worktree-remove-submit').click();

  await expect(page.getByTestId('worktree-remove-panel')).toHaveCount(0);
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.worktree.remove');
  await expect(page.getByTestId('tool-card-input').last()).toContainText('"force": true');
  await expect(page.getByTestId('message').last()).toContainText('Removed worktree quillcode-feature.');
});

test('mock harness pins and archives chats from the sidebar', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await page.getByLabel('Message').fill('run whoami');
  await page.getByRole('button', { name: 'Send' }).click();
  await page.getByTestId('new-chat-button').click();
  await page.getByLabel('Message').fill('git diff');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('sidebar-thread-row')).toHaveCount(2);
  const whoamiRow = page.getByTestId('sidebar-thread-row').filter({ hasText: 'run whoami' });
  await whoamiRow.getByRole('button', { name: 'Pin' }).click();

  await expect(page.getByTestId('sidebar-section-title')).toContainText(['Pinned', 'Recent']);
  await expect(page.getByTestId('sidebar-thread-row').first()).toContainText('run whoami');
  await expect(page.getByTestId('sidebar-thread-row').first()).toContainText('trustedrouter/fusion');

  await page.getByTestId('sidebar-thread-row').first().getByRole('button', { name: 'Archive' }).click();

  await expect(page.getByTestId('sidebar-thread-row')).toHaveCount(1);
  await expect(page.getByTestId('sidebar-thread-row')).toContainText('git diff');
  await expect(page.getByTestId('top-bar-title')).toHaveText('git diff');
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

test('mock harness opens browser preview and records comments', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await page.getByTestId('command-palette-button').click();
  await page.getByLabel('Search commands').fill('browser');
  await expect(page.getByTestId('command-palette-result')).toHaveCount(1);
  await page.getByTestId('command-palette-result').click();

  await expect(page.getByTestId('browser-pane')).toBeVisible();
  await expect(page.getByTestId('browser-empty')).toBeVisible();

  await page.getByLabel('Browser address').fill('localhost:5173');
  await expect(page.getByTestId('browser-open')).toBeEnabled();
  await page.getByTestId('browser-open').click();

  await expect(page.getByTestId('browser-current-url')).toHaveText('http://localhost:5173');
  await expect(page.getByTestId('browser-status')).toHaveText('Preview ready');

  await page.getByLabel('Browser comment').fill('Check hero spacing');
  await expect(page.getByTestId('browser-add-comment')).toBeEnabled();
  await page.getByTestId('browser-add-comment').click();

  await expect(page.getByTestId('browser-comment')).toContainText('Check hero spacing');
  await expect(page.getByTestId('browser-status-label')).toHaveText('Comment added');
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

  await page.getByLabel('Review note for Sources/App.swift').fill('Check the exported symbol name');
  await page.getByRole('button', { name: 'Add note' }).click();
  await expect(page.getByTestId('review-comment')).toContainText('Check the exported symbol name');
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
