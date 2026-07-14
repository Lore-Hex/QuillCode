import { test, expect, type Page } from '@playwright/test';
import {
  clickCommandPaletteCommand,
  expectCommandPaletteClosed,
  expectSelectedCommandPaletteResult,
  fillCommandPalette,
  harnessURL,
  openCommandPalette
} from './harness-helpers';

test.beforeEach(async ({ page }) => {
  await page.goto(harnessURL());
  await openCommandPalette(page);
});

async function enter(page: Page) {
  await page.keyboard.press('Enter');
}

async function cmdP(page: Page) {
  await page.keyboard.press('Meta+Shift+P');
}

async function down(page: Page) {
  await page.keyboard.press('ArrowDown');
}

async function shellFilter(page: Page) {
  await fillCommandPalette(page, '>shell');
}

test('mock harness runs a command from the command palette', async ({ page }) => {
  await expect(page.getByTestId('command-palette-input')).toBeFocused();
  await clickCommandPaletteCommand(page, '>terminal', 'toggle-terminal');

  await expectCommandPaletteClosed(page);
  await expect(page.getByTestId('terminal-pane')).toBeVisible();
});

test('mock harness command palette scopes actions and slash commands', async ({ page }) => {
  await expect(page.getByText('> actions · / slash')).toBeVisible();

  await shellFilter(page);
  await expect(page.getByTestId('command-palette-scope')).toHaveText('Actions');
  await expect(page.getByTestId('command-palette-result').first()).toContainText('Terminal');

  await fillCommandPalette(page, '/mode');
  await expect(page.getByTestId('command-palette-scope')).toHaveText('Slash');
  await expect(page.getByTestId('command-palette-group')).toContainText('Slash Commands');
  await expect(page.getByTestId('command-palette-result').first()).toContainText('/mode auto|plan|review|read-only');

  await enter(page);

  await expectCommandPaletteClosed(page);
  await expect(page.getByLabel('Message')).toHaveValue('/mode ');
  await expect(page.getByLabel('Message')).toBeFocused();
});

test('mock harness ranks and navigates command palette with keyboard', async ({ page }) => {
  await expect(page.getByTestId('command-palette-group').first()).toContainText('Thread');

  await shellFilter(page);
  await expectSelectedCommandPaletteResult(page, 'Terminal');
  await enter(page);
  await expect(page.getByTestId('terminal-pane')).toBeVisible();

  await cmdP(page);
  await fillCommandPalette(page, '>shortcuts');
  await expectSelectedCommandPaletteResult(page, 'Keyboard shortcuts');
  await enter(page);
  await expect(page.getByTestId('keyboard-shortcuts-panel')).toBeVisible();
  await expect(page.getByTestId('keyboard-shortcut-row').filter({ hasText: 'New chat' }))
    .toContainText('Cmd+N');
  await expect(page.getByTestId('keyboard-shortcut-row').filter({ hasText: 'Search' }))
    .toContainText('Cmd+G');
  await expect(page.getByTestId('keyboard-shortcut-row').filter({ hasText: 'Keyboard shortcuts' }))
    .toContainText('Cmd+Shift+/');
  await page.getByTestId('keyboard-shortcuts-close').click();

  await cmdP(page);
  await fillCommandPalette(page, '>worktree');
  // "worktree" surfaces the new-worktree-chat thread command (Thread group, ranked ahead of Git by
  // category order) above the git-worktree tool commands (Git group).
  await expect(page.getByTestId('command-palette-group')).toHaveCount(2);
  await expect(page.getByTestId('command-palette-group').first()).toContainText('Thread');
  await expect(page.getByTestId('command-palette-group').nth(1)).toContainText('Git');
  await expectSelectedCommandPaletteResult(page, 'New worktree task');

  await down(page);
  await expectSelectedCommandPaletteResult(page, 'List worktrees');
  await down(page);
  await expectSelectedCommandPaletteResult(page, 'Create worktree');
  await down(page);
  await expectSelectedCommandPaletteResult(page, 'Open worktree');
  await enter(page);
  await expect(page.getByTestId('worktree-open-panel')).toBeVisible();
});
