import { test, expect, type Page } from '@playwright/test';
import {
  clickCommandPaletteCommand,
  clickSidebarTool,
  commandPaletteResult,
  fillCommandPalette,
  harnessURL
} from './harness-helpers';

async function expectWorktreeChoicesLoaded(page: Page, labels: string[]) {
  await expect(page.getByTestId('worktree-choice')).toContainText(labels);
  await expect(page.getByTestId('worktree-choices-loading')).toHaveCount(0);
}

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
  await expect(page.getByTestId('worktree-prune-panel')).toBeVisible();
  await expect(page.getByTestId('worktree-prune-record')).toContainText('/mock/quillcode-stale');
  await expect(page.getByTestId('worktree-prune-loading')).toHaveCount(0);
  await expect(page.getByTestId('worktree-prune-submit')).toBeEnabled();

  await page.getByTestId('worktree-prune-submit').click();

  await expect(page.getByTestId('worktree-prune-panel')).toHaveCount(0);
  await expect(page.getByTestId('tool-card-title')).toHaveText('host.git.worktree.prune');
  await expect(page.getByTestId('tool-card-input')).toContainText('"dryRun": false');
  await expect(page.getByTestId('tool-card-input')).toContainText('"verbose": true');
  await expect(page.getByTestId('message').last()).toContainText('Pruned stale worktree records.');
});

test('mock harness retries failed worktree prune preview', async ({ page }) => {
  await page.goto(harnessURL());
  await page.evaluate(() => {
    (window as typeof window & { __quillCodeFailNextWorktreePrunePreview?: boolean }).__quillCodeFailNextWorktreePrunePreview = true;
  });

  await clickSidebarTool(page, 'command-palette-button');
  await fillCommandPalette(page, '>prune');
  await commandPaletteResult(page, 'git-worktree-prune').click();

  await expect(page.getByTestId('worktree-prune-error')).toContainText('Could not preview stale worktree records.');
  await expect(page.getByTestId('worktree-prune-submit')).toBeDisabled();

  await page.getByTestId('worktree-prune-retry').click();

  await expect(page.getByTestId('worktree-prune-record')).toContainText('/mock/quillcode-stale');
  await expect(page.getByTestId('worktree-prune-submit')).toBeEnabled();
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
  await expect(commandPaletteResult(page, 'git-pr-view')).toBeVisible();
  await commandPaletteResult(page, 'git-pr-view').click();

  await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);
  await expect(page.getByTestId('tool-card-title')).toHaveText('host.git.pr.view');
  await expect(page.getByTestId('message').last()).toContainText('Current pull request');
  await expect(page.getByTestId('tool-card-artifact-label')).toContainText('github.com/Lore-Hex/QuillCode/pull/42');

  await clickSidebarTool(page, 'command-palette-button');
  await fillCommandPalette(page, '>pr checks');
  await expect(commandPaletteResult(page, 'git-pr-checks')).toBeVisible();
  await commandPaletteResult(page, 'git-pr-checks').click();

  await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.pr.checks');
  await expect(page.getByTestId('message').last()).toContainText('QuillCode Tests');

  await clickSidebarTool(page, 'command-palette-button');
  await fillCommandPalette(page, '>pr diff');
  await expect(commandPaletteResult(page, 'git-pr-diff')).toBeVisible();
  await commandPaletteResult(page, 'git-pr-diff').click();

  await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.pr.diff');
  await expect(page.getByTestId('message').last()).toContainText('PR diff preview from GitHub CLI');
});

test('mock harness covers the full pull request command family from the command palette', async ({ page }) => {
  await page.goto(harnessURL());

  const pullRequestCommandIDs = [
    'git-pr-create',
    'git-pr-view',
    'git-pr-checks',
    'git-pr-diff',
    'git-pr-checkout',
    'git-pr-reviewers',
    'git-pr-comment',
    'git-pr-review',
    'git-pr-review-comment',
    'git-pr-review-reply',
    'git-pr-review-threads',
    'git-pr-review-thread',
    'git-pr-labels',
    'git-pr-merge'
  ];

  await clickSidebarTool(page, 'command-palette-button');
  await fillCommandPalette(page, '>pull request');
  for (const commandID of pullRequestCommandIDs) {
    await expect(commandPaletteResult(page, commandID), `${commandID} should be visible in the rendered command palette`).toBeVisible();
  }
  await page.getByTestId('command-palette-close').click();

  const draftCommands = [
    {
      id: 'git-pr-checkout',
      query: '>checkout pull request',
      draft: 'Checkout pull request '
    },
    {
      id: 'git-pr-reviewers',
      query: '>request reviewers',
      draft: 'Request reviewers for the current pull request: '
    },
    {
      id: 'git-pr-comment',
      query: '>comment on pull request',
      draft: 'Comment on the current pull request: '
    },
    {
      id: 'git-pr-review-comment',
      query: '>line comment',
      draft: 'Comment on a pull request line: '
    },
    {
      id: 'git-pr-review-reply',
      query: '>inline reply',
      draft: 'Reply to pull request review comment: '
    },
    {
      id: 'git-pr-review-thread',
      query: '>resolve review thread',
      draft: 'Resolve pull request review thread: '
    },
    {
      id: 'git-pr-labels',
      query: '>label pull request',
      draft: 'Label the current pull request: '
    },
    {
      id: 'git-pr-merge',
      query: '>merge pull request',
      draft: 'Merge the current pull request with squash'
    }
  ];

  for (const command of draftCommands) {
    await clickSidebarTool(page, 'command-palette-button');
    await clickCommandPaletteCommand(page, command.query, command.id);
    await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);
    await expect(page.getByLabel('Message'), `${command.id} should prepare a focused composer draft`).toHaveValue(command.draft);
    await expect(page.getByLabel('Message')).toBeFocused();
  }

  await clickSidebarTool(page, 'command-palette-button');
  await clickCommandPaletteCommand(page, '>review diff', 'git-diff');
  await expect(page.getByTestId('review-pane')).toBeVisible();
  const firstLineCommentForm = page.getByTestId('review-line-comment-form').first();
  await firstLineCommentForm.getByTestId('review-line-comment-input').fill('Cover this new line.');
  await firstLineCommentForm.getByRole('button', { name: 'Add' }).click();
  await expect(page.getByTestId('review-line-comment')).toContainText('Cover this new line.');
  const secondLineCommentForm = page.getByTestId('review-line-comment-form').nth(1);
  await secondLineCommentForm.getByTestId('review-line-comment-input').fill('Skip this draft note.');
  await secondLineCommentForm.getByRole('button', { name: 'Add' }).click();
  await expect(page.getByTestId('review-line-comment').nth(1)).toContainText('Skip this draft note.');

  await clickSidebarTool(page, 'command-palette-button');
  await clickCommandPaletteCommand(page, '>approve pr', 'git-pr-review');
  await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);
  await expect(page.getByTestId('review-pane')).toBeVisible();
  await expect(page.getByTestId('pr-review-draft')).toBeVisible();
  await expect(page.getByTestId('review-summary')).toHaveText('Submit approve review with 2 inline notes');
  await expect(page.getByTestId('pr-review-draft-include-inline-comments')).toBeChecked();
  await expect(page.getByTestId('pr-review-draft-inline-comment')).toHaveCount(2);
  await expect(page.getByTestId('pr-review-draft-inline-comment').first()).toContainText('Sources/App.swift:1');
  await expect(page.getByTestId('pr-review-draft-inline-comment').first()).toContainText('Cover this new line.');
  await page.getByTestId('pr-review-draft-inline-comment-toggle').nth(1).click();
  await expect(page.getByTestId('review-summary')).toHaveText('Submit approve review with 1 of 2 inline notes');
  await page.getByTestId('pr-review-draft-action').selectOption('request_changes');
  await page.getByTestId('pr-review-draft-selector').fill('123');
  await expect(page.getByTestId('pr-review-draft-submit')).toBeDisabled();
  await page.getByTestId('pr-review-draft-body').fill('Please add a regression test.');
  await expect(page.getByTestId('pr-review-draft-submit')).toBeEnabled();
  await page.getByTestId('pr-review-draft-submit').click();
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.pr.review');
  const inlineReviewCommentCard = page.getByTestId('tool-card').filter({ hasText: 'host.git.pr.review_comment' }).last();
  await expect(inlineReviewCommentCard).toContainText('"path": "Sources/App.swift"');
  await expect(inlineReviewCommentCard).toContainText('"body": "Cover this new line."');
  await expect(page.getByTestId('tool-card').filter({ hasText: 'host.git.pr.review_comment' })).toHaveCount(1);
  await expect(page.getByTestId('tool-card').last()).toContainText('"action": "request_changes"');
  await expect(page.getByTestId('tool-card').last()).toContainText('"selector": "123"');
  await expect(page.getByTestId('message').last()).toContainText('Pull request review submitted: request changes with 1 inline note.');

  await clickSidebarTool(page, 'command-palette-button');
  await clickCommandPaletteCommand(page, '>review threads', 'git-pr-review-threads');

  await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.pr.review_threads');
  await expect(page.getByTestId('review-pane')).toBeVisible();
  await expect(page.getByTestId('pr-review-thread')).toHaveCount(2);
  await expect(page.getByTestId('message').last()).toContainText('Found 2 review threads: 1 unresolved, 1 resolved.');
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
  await expectWorktreeChoicesLoaded(page, ['QuillCode', 'quillcode-existing']);

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
  await expectWorktreeChoicesLoaded(page, ['QuillCode', 'quillcode-feature']);

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
