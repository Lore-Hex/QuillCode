import { test, expect, type Page } from '@playwright/test';
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
  interactionAuditReport,
  expectNoNestedInteractiveTargets,
  expectNoOverlappingInteractiveTargets
} from './interaction-audit-helpers';

async function expectInteractionTargetsClean(page: Page, label: string) {
  await expectAllVisibleInteractiveTargets(page, label);
  await expectNoNestedInteractiveTargets(page, label);
  await expectNoOverlappingInteractiveTargets(page, label);
}

test('mock harness audits every visible interactive click target across workspace states', async ({ page }) => {
  await page.goto(harnessURL());

  await expectInteractionTargetsClean(page, 'initial workspace');

  await page.getByLabel('Message').fill('run whoami');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('sidebar-item')).toContainText('run whoami');
  await expect(page.getByTestId('tool-card').last()).toHaveAttribute('data-status', 'done');

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

test('interaction audit catches dead and edge-blocked visible controls', async ({ page }) => {
  await page.goto(harnessURL());

  await page.evaluate(() => {
    const fixture = document.createElement('div');
    fixture.setAttribute('data-testid', 'interaction-audit-fixture');
    fixture.innerHTML = `
      <button
        type="button"
        data-testid="bad-pointer-target"
        style="position: fixed; left: 24px; top: 24px; z-index: 1000; width: 96px; height: 48px; pointer-events: none;"
      >Dead target</button>
      <button
        type="button"
        disabled
        data-testid="disabled-pointer-target"
        style="position: fixed; left: 24px; top: 84px; z-index: 1000; width: 96px; height: 48px; pointer-events: none;"
      >Disabled target</button>
      <button
        type="button"
        data-testid="edge-blocked-target"
        style="position: fixed; left: 24px; top: 144px; z-index: 1000; width: 96px; height: 64px;"
      >Edge blocked</button>
      <span
        aria-hidden="true"
        style="position: fixed; left: 24px; top: 144px; z-index: 1001; width: 28px; height: 28px; background: rgba(255, 93, 82, 0.85);"
      ></span>
    `;
    document.body.appendChild(fixture);
  });

  const report = await interactionAuditReport(page);
  const issueFor = (testid: string) => report.targetIssues.find((issue) => issue.testid === testid);

  expect(issueFor('bad-pointer-target')?.reason).toContain('pointer_events_none');
  expect(issueFor('edge-blocked-target')?.reason).toContain('interior_click_area_blocked');
  expect(issueFor('disabled-pointer-target')).toBeUndefined();
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
  await expectHitTarget(page.getByTestId('context-fork-summary'), 'context summary fork button');
  await expectHitTarget(page.getByTestId('context-fork-full'), 'context full fork button');

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
  await expectHitTarget(page.getByTestId('browser-tab'), 'browser tab button');
  await expectHitTarget(page.getByTestId('browser-new-tab'), 'browser new tab button');
  await expectHitTarget(page.getByTestId('browser-close-tab'), 'browser close tab button');
  await page.getByTestId('browser-new-tab').click();
  await expect(page.getByTestId('browser-tab')).toHaveCount(2);
  await expectHitTarget(page.getByTestId('browser-close-tab'), 'enabled browser close tab button');
  await expectInteractionTargetsClean(page, 'browser pane with multiple tabs');

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

test('mock harness audits compact viewport click targets across primary states', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(harnessURL());

  await expectInteractionTargetsClean(page, 'compact initial workspace');

  await openTopBarOverflow(page);
  await expect(page.getByTestId('top-bar-overflow-menu')).toHaveAttribute('open', '');
  await expectInteractionTargetsClean(page, 'compact top-bar overflow menu');
  await page.getByTestId('top-bar-overflow-button').click();

  await page.getByTestId('model-picker-button').click();
  await expect(page.getByTestId('model-browser')).toBeVisible();
  await expectInteractionTargetsClean(page, 'compact model picker');
  await page.getByTestId('model-picker-button').click();

  await openTopBarOverflow(page);
  await page.getByTestId('top-bar-overflow-search').click();
  await expect(page.getByTestId('search-panel')).toBeVisible();
  await expectInteractionTargetsClean(page, 'compact search panel');
  await page.getByTestId('search-close').click();

  await openSettings(page);
  await expect(page.getByTestId('settings-panel')).toBeVisible();
  await expectInteractionTargetsClean(page, 'compact settings panel');
  await page.getByTestId('settings-cancel').click();

  await page.getByLabel('Message').fill('run whoami');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('tool-card').last()).toHaveAttribute('data-status', 'done');
  await expectInteractionTargetsClean(page, 'compact tool-card transcript');

  await openTopBarOverflow(page);
  await page.getByTestId('top-bar-overflow-command-palette').click();
  await expect(page.getByTestId('command-palette-panel')).toBeVisible();
  await expectInteractionTargetsClean(page, 'compact command palette');
  await clickCommandPaletteCommand(page, '>terminal', 'toggle-terminal');
  await expect(page.getByTestId('terminal-pane')).toBeVisible();
  await expectInteractionTargetsClean(page, 'compact terminal pane');

  await openTopBarOverflow(page);
  await page.getByTestId('top-bar-overflow-command-palette').click();
  await clickCommandPaletteCommand(page, '>browser', 'toggle-browser');
  await expect(page.getByTestId('browser-pane')).toBeVisible();
  await expectInteractionTargetsClean(page, 'compact browser pane');

  await page.getByLabel('Message').fill('/git');
  await expect(page.getByTestId('slash-suggestions')).toBeVisible();
  await expectInteractionTargetsClean(page, 'compact slash suggestion menu');
  await page.keyboard.press('Escape');
  await page.getByLabel('Message').fill('');

  await page.keyboard.press('Meta+F');
  await expect(page.getByTestId('find-bar')).toBeVisible();
  await expectInteractionTargetsClean(page, 'compact find bar');
  await page.getByTestId('find-close').click();
});
