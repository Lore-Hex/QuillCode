import { test, expect } from '@playwright/test';
import {
  clickCommandPaletteCommand,
  clickSidebarTool,
  commandPaletteResult,
  fillCommandPalette,
  harnessURL,
  openSettings,
  openTopBarOverflow
} from './harness-helpers';
import {
  expectCriticalTargetRegistry,
  expectCriticalTargetSurfaceRegistry,
  expectHitTarget,
  interactionAuditReport,
  clickTargetInteriorPoint,
  expectTextEntryFocusFromInteriorPoint
} from './interaction-audit-helpers';
import {
  expectCommandTargetsRoutable,
  expectInteractionTargetsClean
} from './interaction-audit-routability';

test('mock harness audits every visible interactive click target across workspace states', async ({ page }) => {
  await page.goto(harnessURL());

  await expectInteractionTargetsClean(page, 'initial workspace');

  await page.getByLabel('Message').fill('run whoami');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('sidebar-item')).toContainText('run whoami');
  await expect(page.getByTestId('tool-card').last()).toHaveAttribute('data-status', 'done');
  await page.evaluate(() => {
    const harness = window as unknown as {
      addSidebarSavedSearch: (title: string, query: string, id: string) => string | null;
    };
    harness.addSidebarSavedSearch('Shell work', 'whoami', 'saved-shell-work');
    harness.addSidebarSavedSearch('Run work', 'run', 'saved-run-work');
  });
  await expect(page.getByTestId('sidebar-saved-search')).toHaveCount(2);
  await expect(page.getByTestId('sidebar-saved-search').first()).toBeVisible();
  await expectInteractionTargetsClean(page, 'sidebar saved-search controls');
  await expectHitTarget(page.getByTestId('sidebar-saved-search-create'), 'sidebar saved-search create button');
  await expectHitTarget(page.getByTestId('sidebar-saved-search').first(), 'sidebar saved-search chip');
  await expectHitTarget(page.getByTestId('sidebar-saved-search-move-down').first(), 'sidebar saved-search move down button');
  await expectHitTarget(page.getByTestId('sidebar-saved-search-move-up').last(), 'sidebar saved-search move up button');
  await expectHitTarget(page.getByTestId('sidebar-saved-search-delete').first(), 'sidebar saved-search delete button');

  await page.getByTestId('sidebar-saved-search-create').click();
  await expect(page.getByTestId('sidebar-saved-search-panel')).toBeVisible();
  await expectInteractionTargetsClean(page, 'sidebar saved-search dialog');
  await expectTextEntryFocusFromInteriorPoint(page.getByTestId('sidebar-saved-search-query'), 'saved-search query leading interior', 0.15, 0.5);
  await expectTextEntryFocusFromInteriorPoint(page.getByTestId('sidebar-saved-search-title'), 'saved-search title trailing interior', 0.85, 0.5);
  await page.getByTestId('sidebar-saved-search-cancel').click();

  await page.getByTestId('sidebar-item-actions').first().locator('summary').click();
  await expect(page.getByTestId('sidebar-item-actions').first()).toHaveAttribute('open', '');
  await expectInteractionTargetsClean(page, 'sidebar thread action menu');
  await page.getByTestId('sidebar-item-actions').first().locator('summary').click();

  await page.getByTestId('project-item-actions').first().locator('summary').click();
  await expect(page.getByTestId('project-item-actions').first()).toHaveAttribute('open', '');
  await expectInteractionTargetsClean(page, 'project action menu');
  await page.getByTestId('project-item-actions').first().locator('summary').click();

  await page.getByTestId('sidebar-bulk-action').filter({ hasText: /^Select$/ }).click();
  await expect(page.getByTestId('sidebar-selection')).toHaveAttribute('data-active', 'true');
  await expectInteractionTargetsClean(page, 'sidebar bulk selection controls');
  await expectHitTarget(page.getByTestId('sidebar-select-toggle').first(), 'sidebar selection toggle');
  await page.getByTestId('sidebar-bulk-action').filter({ hasText: /^Done$/ }).click();

  await openTopBarOverflow(page);
  await expect(page.getByTestId('top-bar-overflow-menu')).toHaveAttribute('open', '');
  await expectInteractionTargetsClean(page, 'top-bar overflow menu');
  await page.getByTestId('top-bar-overflow-button').click();

  await page.getByTestId('model-picker-button').click();
  await expect(page.getByTestId('model-browser')).toBeVisible();
  await expectInteractionTargetsClean(page, 'model picker');
  await page.getByTestId('model-search').fill('no model should match this query');
  await expect(page.getByTestId('model-empty')).toBeVisible();
  await expectInteractionTargetsClean(page, 'model picker empty search');
  await page.getByTestId('model-picker-button').click();

  await openTopBarOverflow(page);
  await page.getByTestId('top-bar-overflow-search').click();
  await expect(page.getByTestId('search-panel')).toBeVisible();
  await expectInteractionTargetsClean(page, 'search panel');
  await page.getByTestId('search-close').click();

  await openTopBarOverflow(page);
  await page.getByTestId('top-bar-overflow-command-palette').click();
  await expect(page.getByTestId('command-palette-panel')).toBeVisible();
  await expectInteractionTargetsClean(page, 'command palette');
  await page.getByTestId('command-palette-close').click();

  await openTopBarOverflow(page);
  await page.getByTestId('top-bar-overflow-keyboard-shortcuts').click();
  await expect(page.getByTestId('keyboard-shortcuts-panel')).toBeVisible();
  await expectInteractionTargetsClean(page, 'keyboard shortcuts panel');
  await page.getByTestId('keyboard-shortcuts-close').click();

  await openSettings(page);
  await expect(page.getByTestId('settings-panel')).toBeVisible();
  await expectInteractionTargetsClean(page, 'settings panel');
  await page.getByTestId('settings-cancel').click();

  await clickSidebarTool(page, 'browser-button');
  await expect(page.getByTestId('browser-pane')).toBeVisible();
  await expectInteractionTargetsClean(page, 'browser pane');

  await clickSidebarTool(page, 'terminal-button');
  await expect(page.getByTestId('terminal-pane')).toBeVisible();
  await expectInteractionTargetsClean(page, 'terminal pane');

  await page.getByTestId('extensions-button').click();
  await expect(page.getByTestId('extensions-pane')).toBeVisible();
  await expectInteractionTargetsClean(page, 'extensions pane');

  await page.getByTestId('automations-button').click();
  await expect(page.getByTestId('automations-pane')).toBeVisible();
  await expectInteractionTargetsClean(page, 'automations pane');

  await clickSidebarTool(page, 'command-palette-button');
  await clickCommandPaletteCommand(page, '>create worktree', 'git-worktree-create');
  await expect(page.getByTestId('worktree-create-panel')).toBeVisible();
  await expectInteractionTargetsClean(page, 'worktree create dialog');
  await page.getByTestId('worktree-dialog-cancel').click();

  await clickSidebarTool(page, 'command-palette-button');
  await clickCommandPaletteCommand(page, '>open worktree', 'git-worktree-open');
  await expect(page.getByTestId('worktree-open-panel')).toBeVisible();
  await expectInteractionTargetsClean(page, 'worktree open dialog');
  await page.getByTestId('worktree-dialog-cancel').click();

  await clickSidebarTool(page, 'command-palette-button');
  await clickCommandPaletteCommand(page, '>remove worktree', 'git-worktree-remove');
  await expect(page.getByTestId('worktree-remove-panel')).toBeVisible();
  await expectInteractionTargetsClean(page, 'worktree remove dialog');
  await page.getByTestId('worktree-dialog-cancel').click();

  await clickSidebarTool(page, 'command-palette-button');
  await clickCommandPaletteCommand(page, '>prune', 'git-worktree-prune');
  await expect(page.getByTestId('worktree-prune-panel')).toBeVisible();
  await expectInteractionTargetsClean(page, 'worktree prune dialog');
  await page.getByTestId('worktree-dialog-cancel').click();

  await clickSidebarTool(page, 'memories-button');
  await expect(page.getByTestId('memories-pane')).toBeVisible();
  await expectInteractionTargetsClean(page, 'memories pane');

  await page.getByLabel('Message').fill('/git');
  await expect(page.getByTestId('slash-suggestions')).toBeVisible();
  await expectInteractionTargetsClean(page, 'slash suggestion menu');
  await page.keyboard.press('Escape');
  await page.getByLabel('Message').fill('');

  await page.getByLabel('Message').fill('/pr review-threads 123');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('review-pane')).toBeVisible();
  await expect(page.getByTestId('pr-review-thread')).toHaveCount(2);
  await expectInteractionTargetsClean(page, 'review pane');
  await page.getByTestId('pr-review-thread-reply').first().click();
  await expect(page.getByTestId('pr-review-thread-reply-form').first()).toBeVisible();
  await expectInteractionTargetsClean(page, 'review reply form');
  await page.getByTestId('pr-review-thread-reply-form').first().getByTestId('pr-review-thread-reply-cancel').click();

  await page.getByLabel('Message').fill('run whoami');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('tool-card').last()).toHaveAttribute('data-status', 'done');
  await expectInteractionTargetsClean(page, 'tool-card transcript');

  await page.evaluate(() => {
    const harness = window as typeof window & {
      addToolCard: (card: Record<string, unknown>) => void;
      render: () => void;
    };
    harness.addToolCard({
      actions: [
        {
          id: 'tool-card-action-approve-interaction-audit',
          kind: 'approve',
          requestID: 'interaction-audit',
          style: 'primary',
          title: 'Run'
        },
        {
          id: 'tool-card-action-deny-interaction-audit',
          kind: 'deny',
          requestID: 'interaction-audit',
          style: 'secondary',
          title: 'Skip'
        }
      ],
      density: 'peek',
      id: 'shell-review-interaction-audit',
      inputJSON: JSON.stringify({ cmd: 'whoami' }, null, 2),
      isExpanded: false,
      reviewState: 'ready',
      status: 'review',
      subtitle: 'Ready to run · whoami',
      title: 'host.shell.run'
    });
    harness.render();
  });
  const actionBar = page.getByTestId('tool-card-actions').last();
  await expect(actionBar.getByRole('button', { name: 'Run' })).toBeVisible();
  await expect(actionBar.getByRole('button', { name: 'Skip' })).toBeVisible();
  await expectInteractionTargetsClean(page, 'tool-card action controls');

  await page.keyboard.press('Meta+F');
  await expect(page.getByTestId('find-bar')).toBeVisible();
  await expectInteractionTargetsClean(page, 'find bar');
  await page.getByTestId('find-close').click();
});
