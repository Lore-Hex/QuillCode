import { test, expect } from '@playwright/test';
import {
  clickCommandPaletteCommand,
  clickSidebarTool,
  commandPaletteResult,
  fillCommandPalette,
  harnessURL
} from './harness-helpers';

test('mock harness runs a command from the command palette', async ({ page }) => {
  await page.goto(harnessURL());

  await clickSidebarTool(page, 'command-palette-button');
  await expect(page.getByTestId('command-palette-panel')).toBeVisible();
  await expect(page.getByTestId('command-palette-input')).toBeFocused();
  await clickCommandPaletteCommand(page, '>terminal', 'toggle-terminal');

  await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);
  await expect(page.getByTestId('terminal-pane')).toBeVisible();
});

test('mock harness command palette scopes actions and slash commands', async ({ page }) => {
  await page.goto(harnessURL());

  await clickSidebarTool(page, 'command-palette-button');
  await expect(page.getByTestId('command-palette-panel')).toBeVisible();
  await expect(page.getByText('> actions · / slash')).toBeVisible();

  await fillCommandPalette(page, '>shell');
  await expect(page.getByTestId('command-palette-scope')).toHaveText('Actions');
  await expect(page.getByTestId('command-palette-result').first()).toContainText('Terminal');

  await fillCommandPalette(page, '/mode');
  await expect(page.getByTestId('command-palette-scope')).toHaveText('Slash');
  await expect(page.getByTestId('command-palette-group')).toContainText('Slash Commands');
  await expect(page.getByTestId('command-palette-result').first()).toContainText('/mode auto|review|read-only');

  await page.keyboard.press('Enter');

  await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);
  await expect(page.getByLabel('Message')).toHaveValue('/mode ');
  await expect(page.getByLabel('Message')).toBeFocused();
});

test('mock harness ranks and navigates command palette with keyboard', async ({ page }) => {
  await page.goto(harnessURL());

  await clickSidebarTool(page, 'command-palette-button');
  await expect(page.getByTestId('command-palette-group').first()).toContainText('Thread');

  await fillCommandPalette(page, '>shell');
  await expect(page.locator('[data-testid="command-palette-result"][data-selected="true"]')).toContainText('Terminal');
  await page.keyboard.press('Enter');
  await expect(page.getByTestId('terminal-pane')).toBeVisible();

  await page.keyboard.press('Meta+Shift+P');
  await fillCommandPalette(page, '>shortcuts');
  await expect(page.locator('[data-testid="command-palette-result"][data-selected="true"]')).toContainText('Keyboard shortcuts');
  await page.keyboard.press('Enter');
  await expect(page.getByTestId('keyboard-shortcuts-panel')).toBeVisible();
  await expect(page.getByTestId('keyboard-shortcut-row').filter({ hasText: 'New chat' })).toContainText('Cmd+N');
  await expect(page.getByTestId('keyboard-shortcut-row').filter({ hasText: 'Search' })).toContainText('Cmd+K');
  await expect(page.getByTestId('keyboard-shortcut-row').filter({ hasText: 'Keyboard shortcuts' })).toContainText('Cmd+/');
  await page.getByTestId('keyboard-shortcuts-close').click();

  await page.keyboard.press('Meta+Shift+P');
  await fillCommandPalette(page, '>worktree');
  await expect(page.getByTestId('command-palette-group')).toHaveCount(1);
  await expect(page.getByTestId('command-palette-group')).toContainText('Git');
  await expect(page.locator('[data-testid="command-palette-result"][data-selected="true"]')).toContainText('List worktrees');

  await page.keyboard.press('ArrowDown');
  await expect(page.locator('[data-testid="command-palette-result"][data-selected="true"]')).toContainText('Create worktree');
  await page.keyboard.press('ArrowDown');
  await expect(page.locator('[data-testid="command-palette-result"][data-selected="true"]')).toContainText('Open worktree');
  await page.keyboard.press('Enter');
  await expect(page.getByTestId('worktree-open-panel')).toBeVisible();
});

test('mock harness lists worktrees from the command palette', async ({ page }) => {
  await page.goto(harnessURL());

  await clickSidebarTool(page, 'command-palette-button');
  await fillCommandPalette(page, '>worktree');

  await expect(page.getByTestId('command-palette-result')).toHaveCount(5);
  await commandPaletteResult(page, 'git-worktree-list').click();

  await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);
  await expect(page.getByTestId('tool-card-title')).toHaveText('host.git.worktree.list');
  await expect(page.getByTestId('tool-card-output')).toContainText('/mock/quillcode-existing');
  await expect(page.getByTestId('message').last()).toContainText('worktree /mock/QuillCode');
});

test('mock harness prunes worktrees from the command palette', async ({ page }) => {
  await page.goto(harnessURL());

  await clickSidebarTool(page, 'command-palette-button');
  await fillCommandPalette(page, '>prune');
  await commandPaletteResult(page, 'git-worktree-prune').click();

  await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);
  await expect(page.getByTestId('tool-card-title')).toHaveText('host.git.worktree.prune');
  await expect(page.getByTestId('tool-card-input')).toContainText('"dryRun": true');
  await expect(page.getByTestId('message').last()).toContainText('No stale worktree records found.');
});

test('mock harness prepares pull request creation from the command palette', async ({ page }) => {
  await page.goto(harnessURL());

  await clickSidebarTool(page, 'command-palette-button');
  await fillCommandPalette(page, '>create pull request');
  await expect(page.getByTestId('command-palette-result')).toHaveCount(1);
  await commandPaletteResult(page, 'git-pr-create').click();

  await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);
  await expect(page.getByLabel('Message')).toHaveValue('Create a pull request titled ');
});

test('mock harness views pull request details, checks, and diff from the command palette', async ({ page }) => {
  await page.goto(harnessURL());

  await clickSidebarTool(page, 'command-palette-button');
  await fillCommandPalette(page, '>view pull request');
  await expect(page.getByTestId('command-palette-result')).toHaveCount(1);
  await commandPaletteResult(page, 'git-pr-view').click();

  await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);
  await expect(page.getByTestId('tool-card-title')).toHaveText('host.git.pr.view');
  await expect(page.getByTestId('message').last()).toContainText('Current pull request');
  await expect(page.getByTestId('tool-card-artifact-label')).toContainText('github.com/Lore-Hex/QuillCode/pull/42');

  await clickSidebarTool(page, 'command-palette-button');
  await fillCommandPalette(page, '>pr checks');
  await expect(page.getByTestId('command-palette-result')).toHaveCount(1);
  await commandPaletteResult(page, 'git-pr-checks').click();

  await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.pr.checks');
  await expect(page.getByTestId('message').last()).toContainText('QuillCode Tests');

  await clickSidebarTool(page, 'command-palette-button');
  await fillCommandPalette(page, '>pr diff');
  await expect(page.getByTestId('command-palette-result')).toHaveCount(1);
  await commandPaletteResult(page, 'git-pr-diff').click();

  await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.pr.diff');
  await expect(page.getByTestId('message').last()).toContainText('PR diff preview from GitHub CLI');
});

test('mock harness runs local environment action from the command palette', async ({ page }) => {
  await page.goto(harnessURL());

  await clickSidebarTool(page, 'command-palette-button');
  await fillCommandPalette(page, '>QUILL_ENV');
  await expect(page.getByTestId('command-palette-result')).toHaveCount(1);
  await fillCommandPalette(page, '>warm caches');
  await expect(page.getByTestId('command-palette-result')).toHaveCount(1);
  await expect(page.getByTestId('command-palette-result')).toContainText('Install dependencies and warm caches.');
  await commandPaletteResult(page, 'local-env:.quillcode/actions/bootstrap.sh').click();

  await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);
  await expect(page.getByTestId('tool-card-title')).toHaveText('host.shell.run');
  await expect(page.getByTestId('tool-card-input')).toContainText(".quillcode/actions/bootstrap.sh");
  await expect(page.getByTestId('tool-card-input')).toContainText('QUILL_ENV');
  await expect(page.getByTestId('tool-card-input')).toContainText('<redacted>');
  await expect(page.getByTestId('tool-card-input')).not.toContainText('"dev"');
  await expect(page.getByTestId('message').last()).toContainText('Local environment action completed');
});

test('mock harness creates and removes worktrees from dialogs', async ({ page }) => {
  await page.goto(harnessURL());

  await clickSidebarTool(page, 'command-palette-button');
  await clickCommandPaletteCommand(page, '>create worktree', 'git-worktree-create');
  await expect(page.getByTestId('worktree-create-panel')).toBeVisible();
  await expect(page.getByTestId('worktree-create-submit')).toBeDisabled();

  await page.getByLabel('Worktree folder').fill('quillcode-feature');
  await page.getByLabel('New branch').fill('feature/quillcode');
  await page.getByLabel('Base ref').fill('main');
  await expect(page.getByTestId('worktree-create-submit')).toBeEnabled();
  await page.getByTestId('worktree-create-submit').click();

  await expect(page.getByTestId('worktree-create-panel')).toHaveCount(0);
  await expect(page.getByTestId('project-item').first()).toContainText('quillcode-feature');
  await expect(page.getByTestId('project-item').first()).toContainText('/mock/quillcode-feature');
  await expect(page.getByTestId('top-bar-title')).toHaveText('Worktree: feature/quillcode');
  await expect(page.getByTestId('top-bar-subtitle')).toContainText('quillcode-feature - Auto - Nike 1.0');
  await expect(page.getByTestId('sidebar-item').first()).toContainText('Worktree: feature/quillcode');
  await expect(page.getByTestId('message').last()).toContainText('Opened worktree quillcode-feature at /mock/quillcode-feature.');

  await clickSidebarTool(page, 'command-palette-button');
  await clickCommandPaletteCommand(page, '>open worktree', 'git-worktree-open');
  await expect(page.getByTestId('worktree-open-panel')).toBeVisible();
  await expect(page.getByTestId('worktree-open-submit')).toBeDisabled();
  await expect(page.getByTestId('worktree-choices-loading')).toBeVisible();
  await expect(page.getByTestId('worktree-choice')).toContainText(['QuillCode', 'quillcode-existing']);
  await expect(page.getByTestId('worktree-choices-loading')).toHaveCount(0);

  await page.getByTestId('worktree-choice').filter({ hasText: 'quillcode-existing' }).click();
  await expect(page.getByLabel('Worktree folder')).toHaveValue('/mock/quillcode-existing');
  await expect(page.getByTestId('worktree-open-submit')).toBeEnabled();
  await page.getByTestId('worktree-open-submit').click();

  await expect(page.getByTestId('worktree-open-panel')).toHaveCount(0);
  await expect(page.getByTestId('project-item').first()).toContainText('quillcode-existing');
  await expect(page.getByTestId('top-bar-title')).toHaveText('Worktree: quillcode-existing');
  await expect(page.getByTestId('message').last()).toContainText('Opened worktree quillcode-existing at /mock/quillcode-existing.');

  await clickSidebarTool(page, 'command-palette-button');
  await clickCommandPaletteCommand(page, '>remove worktree', 'git-worktree-remove');
  await expect(page.getByTestId('worktree-remove-panel')).toBeVisible();
  await expect(page.getByTestId('worktree-choices-loading')).toBeVisible();
  await expect(page.getByTestId('worktree-choice')).toContainText(['QuillCode', 'quillcode-feature']);
  await expect(page.getByTestId('worktree-choices-loading')).toHaveCount(0);

  await page.getByTestId('worktree-choice').filter({ hasText: 'quillcode-feature' }).click();
  await expect(page.getByLabel('Worktree folder')).toHaveValue('/mock/quillcode-feature');
  await page.getByLabel('Force removal').check();
  await page.getByTestId('worktree-remove-submit').click();

  await expect(page.getByTestId('worktree-remove-panel')).toHaveCount(0);
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.worktree.remove');
  await expect(page.getByTestId('tool-card-input').last()).toContainText('"force": true');
  await expect(page.getByTestId('message').last()).toContainText('Removed worktree quillcode-feature.');
});

test('mock harness retries failed worktree choice loading', async ({ page }) => {
  await page.goto(harnessURL());
  await page.evaluate(() => {
    (window as typeof window & { __quillCodeFailNextWorktreeChoiceLoad?: boolean }).__quillCodeFailNextWorktreeChoiceLoad = true;
  });

  await clickSidebarTool(page, 'command-palette-button');
  await clickCommandPaletteCommand(page, '>open worktree', 'git-worktree-open');
  await expect(page.getByTestId('worktree-open-panel')).toBeVisible();
  await expect(page.getByTestId('worktree-choices-loading')).toBeVisible();
  await expect(page.getByTestId('worktree-choices-error')).toContainText('Could not load registered git worktrees.');
  await expect(page.getByTestId('worktree-choices-retry')).toBeVisible();

  await page.getByTestId('worktree-choices-retry').click();

  await expect(page.getByTestId('worktree-choices-loading')).toBeVisible();
  await expect(page.getByTestId('worktree-choice')).toContainText('quillcode-existing');
  await expect(page.getByTestId('worktree-choices-error')).toHaveCount(0);
});
