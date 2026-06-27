import { test, expect } from '@playwright/test';
import {
  clickCommandPaletteCommand,
  clickSidebarTool,
  harnessURL,
  openSettings,
  openTopBarOverflow
} from './harness-helpers';
import {
  expectAllVisibleInteractiveTargets,
  expectHitTarget,
  expectNoOverlappingInteractiveTargets
} from './interaction-audit-helpers';

test('mock harness audits every visible interactive click target across workspace states', async ({ page }) => {
  await page.goto(harnessURL());

  await expectAllVisibleInteractiveTargets(page, 'initial workspace');
  await expectNoOverlappingInteractiveTargets(page, 'initial workspace');

  await openTopBarOverflow(page);
  await expect(page.getByTestId('top-bar-overflow-menu')).toHaveAttribute('open', '');
  await expectAllVisibleInteractiveTargets(page, 'top-bar overflow menu');
  await expectNoOverlappingInteractiveTargets(page, 'top-bar overflow menu');
  await page.getByTestId('top-bar-overflow-button').click();

  await page.getByTestId('model-picker-button').click();
  await expect(page.getByTestId('model-browser')).toBeVisible();
  await expectAllVisibleInteractiveTargets(page, 'model picker');
  await expectNoOverlappingInteractiveTargets(page, 'model picker');
  await page.getByTestId('model-picker-button').click();

  await openTopBarOverflow(page);
  await page.getByTestId('top-bar-overflow-search').click();
  await expect(page.getByTestId('search-panel')).toBeVisible();
  await expectAllVisibleInteractiveTargets(page, 'search panel');
  await expectNoOverlappingInteractiveTargets(page, 'search panel');
  await page.getByTestId('search-close').click();

  await openTopBarOverflow(page);
  await page.getByTestId('top-bar-overflow-command-palette').click();
  await expect(page.getByTestId('command-palette-panel')).toBeVisible();
  await expectAllVisibleInteractiveTargets(page, 'command palette');
  await expectNoOverlappingInteractiveTargets(page, 'command palette');
  await page.getByTestId('command-palette-close').click();

  await openTopBarOverflow(page);
  await page.getByTestId('top-bar-overflow-keyboard-shortcuts').click();
  await expect(page.getByTestId('keyboard-shortcuts-panel')).toBeVisible();
  await expectAllVisibleInteractiveTargets(page, 'keyboard shortcuts panel');
  await expectNoOverlappingInteractiveTargets(page, 'keyboard shortcuts panel');
  await page.getByTestId('keyboard-shortcuts-close').click();

  await openSettings(page);
  await expect(page.getByTestId('settings-panel')).toBeVisible();
  await expectAllVisibleInteractiveTargets(page, 'settings panel');
  await expectNoOverlappingInteractiveTargets(page, 'settings panel');
  await page.getByTestId('settings-cancel').click();

  await clickSidebarTool(page, 'browser-button');
  await expect(page.getByTestId('browser-pane')).toBeVisible();
  await expectAllVisibleInteractiveTargets(page, 'browser pane');
  await expectNoOverlappingInteractiveTargets(page, 'browser pane');

  await clickSidebarTool(page, 'terminal-button');
  await expect(page.getByTestId('terminal-pane')).toBeVisible();
  await expectAllVisibleInteractiveTargets(page, 'terminal pane');
  await expectNoOverlappingInteractiveTargets(page, 'terminal pane');

  await page.getByTestId('extensions-button').click();
  await expect(page.getByTestId('extensions-pane')).toBeVisible();
  await expectAllVisibleInteractiveTargets(page, 'extensions pane');
  await expectNoOverlappingInteractiveTargets(page, 'extensions pane');

  await page.getByTestId('automations-button').click();
  await expect(page.getByTestId('automations-pane')).toBeVisible();
  await expectAllVisibleInteractiveTargets(page, 'automations pane');
  await expectNoOverlappingInteractiveTargets(page, 'automations pane');

  await clickSidebarTool(page, 'command-palette-button');
  await clickCommandPaletteCommand(page, '>create worktree', 'git-worktree-create');
  await expect(page.getByTestId('worktree-create-panel')).toBeVisible();
  await expectAllVisibleInteractiveTargets(page, 'worktree create dialog');
  await expectNoOverlappingInteractiveTargets(page, 'worktree create dialog');
  await page.getByTestId('worktree-dialog-cancel').click();

  await clickSidebarTool(page, 'command-palette-button');
  await clickCommandPaletteCommand(page, '>open worktree', 'git-worktree-open');
  await expect(page.getByTestId('worktree-open-panel')).toBeVisible();
  await expectAllVisibleInteractiveTargets(page, 'worktree open dialog');
  await expectNoOverlappingInteractiveTargets(page, 'worktree open dialog');
  await page.getByTestId('worktree-dialog-cancel').click();

  await clickSidebarTool(page, 'memories-button');
  await expect(page.getByTestId('memories-pane')).toBeVisible();
  await expectAllVisibleInteractiveTargets(page, 'memories pane');
  await expectNoOverlappingInteractiveTargets(page, 'memories pane');

  await page.getByLabel('Message').fill('git diff');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('review-pane')).toBeVisible();
  await expectAllVisibleInteractiveTargets(page, 'review pane');
  await expectNoOverlappingInteractiveTargets(page, 'review pane');

  await page.getByLabel('Message').fill('run whoami');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('tool-card').last()).toHaveAttribute('data-status', 'done');
  await expectAllVisibleInteractiveTargets(page, 'tool-card transcript');
  await expectNoOverlappingInteractiveTargets(page, 'tool-card transcript');

  await page.keyboard.press('Meta+F');
  await expect(page.getByTestId('find-bar')).toBeVisible();
  await expectAllVisibleInteractiveTargets(page, 'find bar');
  await expectNoOverlappingInteractiveTargets(page, 'find bar');
  await page.getByTestId('find-close').click();
});

test('mock harness keeps banner and recovery actions at least 44px', async ({ page }) => {
  test.setTimeout(60000);
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('long context ' + 'word '.repeat(22000));
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('context-banner')).toBeVisible();
  await expectHitTarget(page.getByTestId('context-compact'), 'context compact button');
  await expectHitTarget(page.getByTestId('context-new-thread'), 'context new thread button');
  await expectHitTarget(page.getByTestId('context-fork-last'), 'context fork button');

  await page.getByLabel('Message').fill('trigger network failure');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('runtime-issue')).toBeVisible();
  await expectHitTarget(page.getByTestId('runtime-issue-action'), 'runtime recovery button');
});

test('mock harness keeps secondary pane actions at least 44px', async ({ page }) => {
  await page.goto(harnessURL());

  await clickSidebarTool(page, 'terminal-button');
  await expect(page.getByTestId('terminal-pane')).toBeVisible();
  await expectHitTarget(page.getByTestId('terminal-clear'), 'terminal clear button');
  await expectHitTarget(page.getByTestId('terminal-run'), 'terminal run button');

  await clickSidebarTool(page, 'browser-button');
  await expect(page.getByTestId('browser-pane')).toBeVisible();
  await expectHitTarget(page.getByTestId('browser-back'), 'browser back button');
  await expectHitTarget(page.getByTestId('browser-forward'), 'browser forward button');
  await expectHitTarget(page.getByTestId('browser-reload'), 'browser reload button');
  await expectHitTarget(page.getByTestId('browser-session'), 'browser session button');
  await expectHitTarget(page.getByTestId('browser-open'), 'browser open button');
  await expectHitTarget(page.getByTestId('browser-add-comment'), 'browser comment button');

  await page.getByTestId('extensions-button').click();
  await expect(page.getByTestId('extensions-pane')).toBeVisible();
  await expectHitTarget(page.getByTestId('extension-install'), 'extension install button');
  await expectHitTarget(page.getByTestId('extension-start'), 'extension start button');

  await clickSidebarTool(page, 'memories-button');
  await expect(page.getByTestId('memories-pane')).toBeVisible();
  await expectHitTarget(page.getByTestId('memories-add'), 'memory add button');
  await expectHitTarget(page.getByTestId('memory-edit'), 'memory edit button');
  await expectHitTarget(page.getByTestId('memory-delete'), 'memory delete button');

  await page.getByTestId('automations-button').click();
  await expect(page.getByTestId('automations-pane')).toBeVisible();
  await expectHitTarget(page.getByTestId('automation-create-follow-up'), 'automation follow-up button');
  await expectHitTarget(page.getByTestId('automation-create-workspace-schedule'), 'automation workspace button');
  await page.getByTestId('automation-create-workspace-schedule').click();
  await expectHitTarget(page.getByTestId('automation-run'), 'automation run button');
  await expectHitTarget(page.getByTestId('automation-primary-action'), 'automation primary action button');
  await expectHitTarget(page.getByTestId('automation-delete'), 'automation delete button');
});
