import { test, expect, type Page } from '@playwright/test';
import {
  clickCommandPaletteCommand,
  commandPaletteResult,
  expectCommandPaletteClosed,
  expectWorktreeChoicesLoaded,
  fillCommandPalette,
  harnessURL,
  openCommandPalette
} from './harness-helpers';

test.beforeEach(async ({ page }) => {
  await page.goto(harnessURL());
});

async function openWorktreeCommand(page: Page, query: string, commandID: string) {
  await openCommandPalette(page);
  await clickCommandPaletteCommand(page, query, commandID);
}

async function createNewWorktreeTask(
  page: Page,
  environment: 'Automatic' | 'No setup' | 'Development' | 'CI' = 'Automatic',
  name = ''
) {
  await openCommandPalette(page);
  await clickCommandPaletteCommand(page, '>new worktree', 'thread-new-worktree');
  await expect(page.getByTestId('worktree-new-task-panel')).toBeVisible();
  await expect(page.getByLabel('Task name')).toBeFocused();
  if (name) await page.getByLabel('Task name').fill(name);
  await page.getByRole('radio', { name: new RegExp(`^${environment}`) }).check();
  await page.getByTestId('worktree-new-task-submit').click();
  await expect(page.getByTestId('worktree-new-task-panel')).toHaveCount(0);
}

test('mock harness lists worktrees from the command palette', async ({ page }) => {
  await openCommandPalette(page);
  await fillCommandPalette(page, '>worktree');

  // Five git-worktree tools plus task, restore, create, publish, merged cleanup, handoff, and finish actions.
  await expect(page.getByTestId('command-palette-result')).toHaveCount(12);
  await commandPaletteResult(page, 'git-worktree-list').click();

  await expectCommandPaletteClosed(page);
  await expect(page.getByTestId('tool-card-title')).toHaveText('host.git.worktree.list');
  await expect(page.getByTestId('tool-card-output')).toContainText('/mock/quillcode-existing');
  await expect(page.getByTestId('message').last()).toContainText('worktree /mock/QuillCode');
});

test('detached worktree task can create and own a branch in place', async ({ page }) => {
  await createNewWorktreeTask(page);

  await expect(page.getByTestId('top-bar-create-branch-button')).toBeVisible();
  await expect(page.getByTestId('top-bar-handoff-button')).toBeVisible();
  await page.getByTestId('top-bar-create-branch-button').click();

  const branchInput = page.getByLabel('Branch name');
  await expect(page.getByTestId('worktree-create-branch-panel')).toBeVisible();
  await expect(branchInput).toBeFocused();
  await expect(page.getByTestId('worktree-create-branch-submit')).toBeDisabled();
  await branchInput.fill('feature/owned-task');
  await expect(page.getByTestId('worktree-create-branch-submit')).toBeEnabled();
  await page.getByTestId('worktree-create-branch-submit').click();

  await expect(page.getByTestId('worktree-create-branch-panel')).toHaveCount(0);
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.worktree.create_branch');
  await expect(page.getByTestId('tool-card-input').last()).toContainText('feature/owned-task');
  await expect(page.getByTestId('sidebar-item').first()).toContainText('owned-task');
  await expect(page.getByTestId('top-bar-worktree')).toContainText('feature/owned-task');
  await expect(page.getByTestId('top-bar-create-branch-button')).toHaveCount(0);
  await expect(page.getByTestId('top-bar-handoff-button')).toHaveCount(0);
  await expect(page.getByTestId('top-bar-publish-branch-button')).toBeVisible();

  await page.getByTestId('top-bar-publish-branch-button').click();

  const toolTitles = page.getByTestId('tool-card-title');
  await expect(toolTitles.nth((await toolTitles.count()) - 2)).toHaveText('host.git.push');
  await expect(toolTitles.last()).toHaveText('host.git.pr.create');
  await expect(page.getByTestId('tool-card-input').last()).toContainText('feature/owned-task');
  await expect(page.getByTestId('message').last()).toContainText('opened its pull request');
  await expect(page.getByTestId('sidebar-pr-status')).toHaveText('PR #1187 · Open');
  await expect(page.getByTestId('top-bar-publish-branch-button')).toHaveCount(0);
  await expect(page.getByTestId('top-bar-pull-request-button'))
    .toHaveAttribute('data-command-id', 'thread-land-pull-request');
  const pullRequestButtonBounds = await page.getByTestId('top-bar-pull-request-button').boundingBox();
  expect(pullRequestButtonBounds?.width).toBeGreaterThanOrEqual(40);
  expect(pullRequestButtonBounds?.height).toBeGreaterThanOrEqual(40);
  await page.getByTestId('top-bar-overflow-button').click();
  await expect(page.getByTestId('top-bar-overflow-thread-publish-branch')).toBeVisible();
  await page.getByTestId('top-bar-overflow-button').click();

  await page.getByTestId('top-bar-pull-request-button').click();

  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.pr.merge');
  await expect(page.getByTestId('tool-card-input').last()).toContainText('"auto": true');
  await expect(page.getByTestId('sidebar-pr-status')).toHaveText('PR #1187 · Queued');
  await expect(page.getByTestId('top-bar-pull-request-button'))
    .toHaveAttribute('data-command-id', 'thread-refresh-pull-request');

  await page.getByTestId('top-bar-pull-request-button').click();

  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.pr.view');
  await expect(page.getByTestId('sidebar-pr-status')).toHaveText('PR #1187 · Merged');
  await expect(page.getByTestId('top-bar-pull-request-button'))
    .toHaveAttribute('data-command-id', 'thread-cleanup-merged-worktree');

  await page.getByTestId('top-bar-pull-request-button').click();

  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.worktree.remove');
  await expect(page.getByTestId('tool-card-input').last()).toContainText('"force": false');
  await expect(page.getByTestId('sidebar-worktree-branch')).toHaveCount(0);
  await expect(page.getByTestId('sidebar-pr-status')).toHaveText('PR #1187 · Merged');
  await expect(page.getByTestId('message').last()).toContainText('task and PR history remain available');
});

test('finishing a managed task confirms, preserves failed cleanup, and retries safely', async ({ page }) => {
  await createNewWorktreeTask(page, 'Automatic', 'Finish safely');
  await page.evaluate(() => {
    (window as typeof window & {
      __quillCodeFailNextWorktreeFinishCleanup?: boolean
    }).__quillCodeFailNextWorktreeFinishCleanup = true;
  });

  await page.getByTestId('top-bar-overflow-button').click();
  const finishCommand = page.getByTestId('top-bar-overflow-thread-finish-worktree');
  await expect(finishCommand).toHaveText('Finish task in Local');
  await finishCommand.click();

  const finishPanel = page.getByTestId('worktree-finish-panel');
  await expect(finishPanel).toBeVisible();
  await expect(finishPanel).toContainText('Transfer verified task state');
  await expect(finishPanel).toContainText('Preserve concurrent edits');
  await page.getByTestId('worktree-dialog-cancel').click();
  await expect(finishPanel).toHaveCount(0);
  await expect(page.getByTestId('top-bar-worktree')).toHaveText('Worktree');

  await page.getByTestId('top-bar-overflow-button').click();
  await page.getByTestId('top-bar-overflow-thread-finish-worktree').click();
  await page.getByTestId('worktree-finish-submit').click();

  await expect(page.getByTestId('top-bar-worktree')).toHaveText('Local');
  await expect(page.getByTestId('sidebar-worktree-local')).toHaveText('Local');
  await expect(page.getByTestId('message').last()).toContainText(
    'isolated worktree was preserved because Git could not remove it safely'
  );

  await page.getByTestId('top-bar-overflow-button').click();
  const retryCommand = page.getByTestId('top-bar-overflow-thread-finish-worktree');
  await expect(retryCommand).toHaveText('Finish worktree cleanup');
  await retryCommand.click();
  await expect(page.getByTestId('worktree-finish-panel')).toContainText('No task files move during cleanup.');
  await expect(page.getByTestId('worktree-finish-submit')).toHaveText('Retry Cleanup');
  await page.getByTestId('worktree-finish-submit').click();

  await expect(page.getByTestId('top-bar-worktree')).toHaveCount(0);
  await expect(page.getByTestId('sidebar-worktree-local')).toHaveCount(0);
  await expect(page.getByTestId('message').last()).toContainText('completed worktree cleanup');
  await page.getByTestId('top-bar-overflow-button').click();
  await expect(page.getByTestId('top-bar-overflow-thread-finish-worktree')).toHaveCount(0);
});

test('new managed worktree shows automatic environment setup in the transcript', async ({ page }) => {
  await createNewWorktreeTask(page, 'Automatic');

  const setupCard = page.getByTestId('tool-card').last();
  await expect(setupCard.getByTestId('tool-card-title')).toHaveText('host.shell.run');
  await expect(setupCard.getByTestId('tool-card-input')).toContainText(
    '.quillcode/environments/development/setup.sh'
  );
  await expect(setupCard).toHaveAttribute('data-status', 'done');
  await setupCard.click();
  await expect(setupCard.getByTestId('tool-card-output')).toContainText('development environment ready.');
});

test('new worktree task can choose a named environment or skip setup', async ({ page }) => {
  await createNewWorktreeTask(page, 'CI', 'CI investigation');
  await expect(page.getByTestId('tool-card-input').last()).toContainText(
    '.quillcode/environments/ci/setup.sh'
  );
  await expect(page.getByTestId('sidebar-item').first()).toContainText('Worktree: CI investigation');

  await createNewWorktreeTask(page, 'No setup', 'Docs only');
  await expect(page.getByTestId('tool-card')).toHaveCount(0);
  await expect(page.getByTestId('sidebar-item').first()).toContainText('Worktree: Docs only');
});

test('archived managed worktree can be restored with its saved task state', async ({ page }) => {
  await createNewWorktreeTask(page);
  await expect(page.getByTestId('top-bar-worktree')).toHaveText('Worktree');

  await openCommandPalette(page);
  await clickCommandPaletteCommand(page, '>archive chat', 'thread-archive');
  await openCommandPalette(page);
  await clickCommandPaletteCommand(page, '>show archived', 'sidebar-filter:archived');
  await page.getByTestId('sidebar-item').filter({ hasText: 'Worktree: experiment' }).click();
  await expect(page.getByTestId('sidebar-worktree-snapshot')).toBeVisible();
  await openCommandPalette(page);
  await clickCommandPaletteCommand(page, '>unarchive chat', 'thread-unarchive');

  await expect(page.getByTestId('top-bar-worktree')).toHaveText('Worktree saved');
  await expect(page.getByTestId('top-bar-restore-worktree-button')).toBeVisible();

  await page.getByTestId('top-bar-restore-worktree-button').click();

  await expect(page.getByTestId('top-bar-worktree')).toHaveText('Worktree');
  await openCommandPalette(page);
  await clickCommandPaletteCommand(page, '>show all', 'sidebar-filter:all');
  await expect(page.getByTestId('sidebar-worktree-branch')).toContainText('Detached');
  await expect(page.getByTestId('sidebar-worktree-snapshot')).toHaveCount(0);
  await expect(page.getByTestId('message').last()).toContainText(
    'Restored the managed worktree with all staged, unstaged, and local changes.'
  );
});

test('mock harness prunes worktrees from the command palette', async ({ page }) => {
  await openWorktreeCommand(page, '>prune', 'git-worktree-prune');

  await expectCommandPaletteClosed(page);
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
  await page.evaluate(() => {
    (window as typeof window & {
      __quillCodeFailNextWorktreePrunePreview?: boolean
    }).__quillCodeFailNextWorktreePrunePreview = true;
  });

  await openWorktreeCommand(page, '>prune', 'git-worktree-prune');

  await expect(page.getByTestId('worktree-prune-error'))
    .toContainText('Could not preview stale worktree records.');
  await expect(page.getByTestId('worktree-prune-submit')).toBeDisabled();

  await page.getByTestId('worktree-prune-retry').click();

  await expect(page.getByTestId('worktree-prune-record')).toContainText('/mock/quillcode-stale');
  await expect(page.getByTestId('worktree-prune-submit')).toBeEnabled();
});

test('mock harness creates and removes worktrees from dialogs', async ({ page }) => {
  await openWorktreeCommand(page, '>create worktree', 'git-worktree-create');
  await expect(page.getByTestId('worktree-create-panel')).toBeVisible();
  await expect(page.getByTestId('worktree-create-submit')).toBeDisabled();

  await page.getByLabel('Worktree folder').fill('quillcode-feature');
  await page.getByLabel('New branch').fill('feature/quillcode');
  await page.getByLabel('Base ref').fill('main');
  await expect(page.getByTestId('worktree-create-submit')).toBeEnabled();
  await page.getByTestId('worktree-create-submit').click();

  await expect(page.getByTestId('worktree-create-panel')).toHaveCount(0);
  await expect(page.getByTestId('project-item').first()).toContainText('quillcode-feature');
  await expect(page.getByTestId('project-item').first()).toHaveAttribute('title', '/mock/quillcode-feature');
  await expect(page.getByTestId('top-bar-title')).toHaveText('Worktree: feature/quillcode');
  await expect(page.getByTestId('top-bar-subtitle')).toContainText('quillcode-feature - Auto - Nike 1.0');
  await expect(page.getByTestId('sidebar-item').first()).toContainText('Worktree: feature/quillcode');
  await expect(page.getByTestId('message').last())
    .toContainText('Opened worktree quillcode-feature at /mock/quillcode-feature.');

  await openWorktreeCommand(page, '>open worktree', 'git-worktree-open');
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
  await expect(page.getByTestId('message').last())
    .toContainText('Opened worktree quillcode-existing at /mock/quillcode-existing.');

  await openWorktreeCommand(page, '>remove worktree', 'git-worktree-remove');
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
  await page.evaluate(() => {
    (window as typeof window & {
      __quillCodeFailNextWorktreeChoiceLoad?: boolean
    }).__quillCodeFailNextWorktreeChoiceLoad = true;
  });

  await openWorktreeCommand(page, '>open worktree', 'git-worktree-open');
  await expect(page.getByTestId('worktree-open-panel')).toBeVisible();
  await expect(page.getByTestId('worktree-choices-loading')).toBeVisible();
  await expect(page.getByTestId('worktree-choices-error'))
    .toContainText('Could not load registered git worktrees.');
  await expect(page.getByTestId('worktree-choices-retry')).toBeVisible();

  await page.getByTestId('worktree-choices-retry').click();

  await expect(page.getByTestId('worktree-choices-loading')).toBeVisible();
  await expect(page.getByTestId('worktree-choice')).toContainText('quillcode-existing');
  await expect(page.getByTestId('worktree-choices-error')).toHaveCount(0);
});
