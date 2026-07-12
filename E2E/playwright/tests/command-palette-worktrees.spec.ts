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

test('mock harness lists worktrees from the command palette', async ({ page }) => {
  await openCommandPalette(page);
  await fillCommandPalette(page, '>worktree');

  // Five git-worktree tools plus new chat, Handoff, and Create branch here task commands.
  await expect(page.getByTestId('command-palette-result')).toHaveCount(8);
  await commandPaletteResult(page, 'git-worktree-list').click();

  await expectCommandPaletteClosed(page);
  await expect(page.getByTestId('tool-card-title')).toHaveText('host.git.worktree.list');
  await expect(page.getByTestId('tool-card-output')).toContainText('/mock/quillcode-existing');
  await expect(page.getByTestId('message').last()).toContainText('worktree /mock/QuillCode');
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
  await expect(page.getByTestId('project-item').first()).toContainText('/mock/quillcode-feature');
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
