import { test, expect, type Page } from '@playwright/test';
import {
  clickCommandPaletteCommand,
  clickSidebarTool,
  fillCommandPalette,
  harnessURL,
  openSettings,
  openTopBarOverflow
} from './harness-helpers';
import {
  expectAllVisibleInteractiveTargets,
  expectCriticalTargetRegistry,
  expectCriticalTargetSurfaceRegistry,
  expectHitTarget,
  interactionAuditReport,
  clickTargetInteriorPoint,
  expectNoAmbiguousAdjacentInteractiveTargets,
  expectNoNestedInteractiveTargets,
  expectNoOverlappingInteractiveTargets,
  expectTextEntryFocusFromInteriorPoint
} from './interaction-audit-helpers';

async function expectInteractionTargetsClean(page: Page, label: string) {
  await expectAllVisibleInteractiveTargets(page, label);
  await expectNoNestedInteractiveTargets(page, label);
  await expectNoOverlappingInteractiveTargets(page, label);
  await expectNoAmbiguousAdjacentInteractiveTargets(page, label);
  await expectCommandTargetsRoutable(page, label);
}

async function expectCommandTargetsRoutable(page: Page, label: string) {
  const report = await page.evaluate(() => {
    const harness = window as typeof window & {
      __quillCodeCommandRoutingAudit?: () => {
        unroutableCommands: Array<{ commandID: string; title: string; enabled: boolean }>;
        unroutableTargets: Array<{ commandID: string; testid: string; text: string }>;
      };
    };
    return harness.__quillCodeCommandRoutingAudit?.() ?? {
      unroutableCommands: [{ commandID: 'missing-audit-hook', title: 'Missing audit hook', enabled: true }],
      unroutableTargets: []
    };
  });

  expect(
    report.unroutableCommands,
    `${label} should not publish command IDs the harness cannot route`
  ).toEqual([]);
  expect(
    report.unroutableTargets,
    `${label} should not render visible enabled command targets with unroutable command IDs`
  ).toEqual([]);
}

test('critical click-target registry covers primary workspace surfaces', async ({ page }) => {
  await page.goto(harnessURL());

  await expectCriticalTargetSurfaceRegistry('primary workspace chrome', [
    {
      label: 'sidebar primary actions',
      requiredKinds: ['row'],
      probes: [
        { label: 'new chat', locator: page.getByTestId('new-chat-button'), expectedKind: 'row' },
        { label: 'sidebar search', locator: page.getByTestId('sidebar-search-button'), expectedKind: 'row' },
        { label: 'sidebar tools', locator: page.getByTestId('sidebar-tools-button'), expectedKind: 'row' }
      ]
    },
    {
      label: 'project list',
      requiredKinds: ['icon', 'row'],
      probes: [
        { label: 'open project', locator: page.getByTestId('add-project-button'), expectedKind: 'icon' },
        { label: 'first project row', locator: page.getByTestId('project-item').first(), expectedKind: 'row' }
      ]
    },
    {
      label: 'top bar actions',
      requiredKinds: ['capsule', 'icon'],
      probes: [
        { label: 'model picker', locator: page.getByTestId('model-picker-button'), expectedKind: 'capsule' },
        { label: 'top-bar overflow', locator: page.getByTestId('top-bar-overflow-button'), expectedKind: 'icon' }
      ]
    },
    {
      label: 'composer',
      requiredKinds: ['text-entry', 'text'],
      probes: [
        { label: 'composer text entry', locator: page.getByLabel('Message'), expectedKind: 'text-entry' },
        { label: 'composer send', locator: page.getByRole('button', { name: 'Send' }), expectedKind: 'text' }
      ]
    }
  ]);

  await openTopBarOverflow(page);
  await expectCriticalTargetSurfaceRegistry('top-bar overflow menu', [
    {
      label: 'menu rows',
      requiredKinds: ['row'],
      probes: [
        { label: 'search', locator: page.getByTestId('top-bar-overflow-search'), expectedKind: 'row' },
        { label: 'command palette', locator: page.getByTestId('top-bar-overflow-command-palette'), expectedKind: 'row' },
        { label: 'keyboard shortcuts', locator: page.getByTestId('top-bar-overflow-keyboard-shortcuts'), expectedKind: 'row' },
        { label: 'settings', locator: page.getByTestId('top-bar-overflow-settings'), expectedKind: 'row' }
      ]
    }
  ]);
  await page.getByTestId('top-bar-overflow-button').click();

  await page.getByTestId('model-picker-button').click();
  await expect(page.getByTestId('model-browser')).toBeVisible();
  await expectCriticalTargetRegistry('model picker', [
    { label: 'model search', locator: page.getByTestId('model-search'), expectedKind: 'text-entry' },
    { label: 'first model option', locator: page.getByTestId('model-option').first(), expectedKind: 'row' },
    { label: 'first model details', locator: page.getByTestId('model-detail-button').first(), expectedKind: 'icon' },
    { label: 'first model favorite', locator: page.getByTestId('model-favorite-button').first(), expectedKind: 'icon' }
  ]);
  await page.getByTestId('model-picker-button').click();

  await openTopBarOverflow(page);
  await page.getByTestId('top-bar-overflow-command-palette').click();
  await expect(page.getByTestId('command-palette-panel')).toBeVisible();
  await fillCommandPalette(page, '>git');
  await expectCriticalTargetRegistry('command palette', [
    { label: 'command search', locator: page.getByTestId('command-palette-input'), expectedKind: 'text-entry' },
    { label: 'close command palette', locator: page.getByTestId('command-palette-close'), expectedKind: 'text' },
    { label: 'first command result', locator: page.getByTestId('command-palette-result').first(), expectedKind: 'row' }
  ]);
  await page.getByTestId('command-palette-close').click();

  await openSettings(page);
  await expect(page.getByTestId('settings-panel')).toBeVisible();
  await expectCriticalTargetRegistry('settings panel', [
    { label: 'API base URL', locator: page.getByLabel('TrustedRouter API base URL'), expectedKind: 'text-entry' },
    { label: 'authentication selector', locator: page.getByLabel('Authentication'), expectedKind: 'text-entry' },
    { label: 'TrustedRouter sign in', locator: page.getByTestId('settings-sign-in'), expectedKind: 'text' },
    { label: 'cancel', locator: page.getByTestId('settings-cancel'), expectedKind: 'text' },
    { label: 'save', locator: page.getByTestId('settings-save'), expectedKind: 'text' }
  ]);
  await page.getByTestId('settings-cancel').click();

  await clickSidebarTool(page, 'terminal-button');
  await expect(page.getByTestId('terminal-pane')).toBeVisible();
  await expectCriticalTargetRegistry('terminal pane', [
    { label: 'clear', locator: page.getByTestId('terminal-clear'), expectedKind: 'text' },
    { label: 'command input', locator: page.getByTestId('terminal-input'), expectedKind: 'text-entry' },
    { label: 'run', locator: page.getByTestId('terminal-run'), expectedKind: 'text' }
  ]);

  await clickSidebarTool(page, 'activity-button');
  await expect(page.getByTestId('activity-pane')).toBeVisible();
  await expectCriticalTargetRegistry('activity pane', [
    { label: 'plan section toggle', locator: page.getByTestId('activity-plan-section').getByTestId('activity-section-toggle'), expectedKind: 'row' },
    { label: 'source open', locator: page.getByTestId('activity-source-action').filter({ hasText: 'Open' }), expectedKind: 'form-action' },
    { label: 'source edit', locator: page.getByTestId('activity-source-action').filter({ hasText: 'Edit' }), expectedKind: 'form-action' }
  ]);

  await clickSidebarTool(page, 'browser-button');
  await expect(page.getByTestId('browser-pane')).toBeVisible();
  await expectCriticalTargetRegistry('browser pane', [
    { label: 'active browser tab', locator: page.getByTestId('browser-tab').first(), expectedKind: 'capsule' },
    { label: 'back', locator: page.getByTestId('browser-back'), expectedKind: 'icon' },
    { label: 'forward', locator: page.getByTestId('browser-forward'), expectedKind: 'icon' },
    { label: 'reload', locator: page.getByTestId('browser-reload'), expectedKind: 'icon' },
    { label: 'address', locator: page.getByTestId('browser-address'), expectedKind: 'text-entry' },
    { label: 'open', locator: page.getByTestId('browser-open'), expectedKind: 'text' },
    { label: 'comment input', locator: page.getByTestId('browser-comment-input'), expectedKind: 'text-entry' },
    { label: 'add comment', locator: page.getByTestId('browser-add-comment'), expectedKind: 'text' }
  ]);

  await page.getByTestId('extensions-button').click();
  await expect(page.getByTestId('extensions-pane')).toBeVisible();
  await page.getByTestId('extension-start').click();
  await expect(page.getByTestId('extension-item').nth(2)).toContainText('Ready');
  await expectCriticalTargetRegistry('extensions pane', [
    { label: 'install extension', locator: page.getByTestId('extension-install'), expectedKind: 'form-action' },
    { label: 'stop MCP server', locator: page.getByTestId('extension-stop'), expectedKind: 'form-action' },
    { label: 'read MCP resource', locator: page.getByTestId('extension-mcp-resource-action').first(), expectedKind: 'capsule' },
    { label: 'use MCP prompt', locator: page.getByTestId('extension-mcp-prompt-action'), expectedKind: 'capsule' }
  ]);

  await clickSidebarTool(page, 'memories-button');
  await expect(page.getByTestId('memories-pane')).toBeVisible();
  await expectCriticalTargetRegistry('memories pane', [
    { label: 'add memory', locator: page.getByTestId('memories-add'), expectedKind: 'text' },
    { label: 'edit memory', locator: page.getByTestId('memory-edit').first(), expectedKind: 'form-action' },
    { label: 'forget memory', locator: page.getByTestId('memory-delete').first(), expectedKind: 'form-action' }
  ]);

  await page.getByTestId('automations-button').click();
  await expect(page.getByTestId('automations-pane')).toBeVisible();
  await page.getByTestId('automation-create-workspace-schedule').click();
  await expect(page.getByTestId('automation-card')).toBeVisible();
  await expectCriticalTargetRegistry('automations pane', [
    { label: 'schedule follow-up', locator: page.getByTestId('automation-schedule-follow-up').first(), expectedKind: 'text' },
    { label: 'create workspace schedule', locator: page.getByTestId('automation-create-workspace-schedule'), expectedKind: 'text' },
    { label: 'run automation', locator: page.getByTestId('automation-run'), expectedKind: 'text' },
    { label: 'pause automation', locator: page.getByTestId('automation-primary-action'), expectedKind: 'text' },
    { label: 'delete automation', locator: page.getByTestId('automation-delete'), expectedKind: 'text' }
  ]);

  await page.getByLabel('Message').fill('run whoami');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('tool-card').last()).toHaveAttribute('data-status', 'done');
  await expectCriticalTargetRegistry('transcript tool card', [
    { label: 'tool disclosure', locator: page.getByTestId('tool-card-details').last().locator('summary'), expectedKind: 'row' },
    { label: 'message composer', locator: page.getByLabel('Message'), expectedKind: 'text-entry' },
    { label: 'send after transcript update', locator: page.getByRole('button', { name: 'Send' }), expectedKind: 'text' }
  ]);
});

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
      <button
        type="button"
        data-testid="near-edge-blocked-target"
        style="position: fixed; left: 24px; top: 408px; z-index: 1000; width: 120px; height: 48px;"
      >Near edge blocked</button>
      <button
        type="button"
        data-testid="missing-affordance-target"
        style="position: fixed; left: 24px; top: 220px; z-index: 1000; width: 96px; height: 48px; cursor: default;"
      >Looks dead</button>
      <button
        type="button"
        data-testid="missing-contract-target"
        style="position: fixed; left: 24px; top: 348px; z-index: 1000; width: 112px; height: 48px; cursor: pointer;"
      >No contract</button>
      <button
        type="button"
        class="hit-target-text-entry"
        data-testid="button-declared-as-text-entry-target"
        data-hit-target-kind="text-entry"
        data-hit-target-action="text-input"
        data-hit-target-source="explicit"
        style="position: fixed; left: 164px; top: 24px; z-index: 1000; width: 156px; height: 48px; cursor: pointer;"
      >Wrong kind</button>
      <button
        type="button"
        class="hit-target-text"
        data-testid="button-declared-as-link-action"
        data-hit-target-kind="text"
        data-hit-target-action="link"
        data-hit-target-source="explicit"
        style="position: fixed; left: 164px; top: 84px; z-index: 1000; width: 156px; height: 48px; cursor: pointer;"
      >Wrong action</button>
      <a
        href="#"
        class="hit-target-text"
        data-testid="link-declared-as-press-target"
        data-hit-target-kind="text"
        data-hit-target-action="press"
        data-hit-target-source="explicit"
        style="position: fixed; left: 164px; top: 144px; z-index: 1000; width: 156px; height: 48px; cursor: pointer;"
      >Wrong link</a>
      <button
        type="button"
        class="hit-target-row"
        data-testid="kind-class-mismatch-target"
        data-hit-target-kind="icon"
        data-hit-target-action="press"
        data-hit-target-source="explicit"
        style="position: fixed; left: 164px; top: 204px; z-index: 1000; width: 156px; height: 48px; cursor: pointer;"
      >Mismatch</button>
      <button
        type="button"
        class="hit-target-text"
        data-testid="too-close-a"
        data-hit-target-kind="text"
        data-hit-target-action="press"
        data-hit-target-source="explicit"
        style="position: fixed; left: 164px; top: 264px; z-index: 1000; width: 80px; height: 48px; cursor: pointer;"
      >Close A</button>
      <button
        type="button"
        class="hit-target-text"
        data-testid="too-close-b"
        data-hit-target-kind="text"
        data-hit-target-action="press"
        data-hit-target-source="explicit"
        style="position: fixed; left: 246px; top: 264px; z-index: 1000; width: 80px; height: 48px; cursor: pointer;"
      >Close B</button>
      <span
        aria-hidden="true"
        style="position: fixed; left: 24px; top: 144px; z-index: 1001; width: 28px; height: 28px; background: rgba(255, 93, 82, 0.85);"
      ></span>
      <span
        aria-hidden="true"
        style="position: fixed; left: 132px; top: 408px; z-index: 1001; width: 12px; height: 48px; background: rgba(255, 93, 82, 0.85);"
      ></span>
      <input
        type="checkbox"
        id="tiny-checkbox"
        data-testid="tiny-checkbox"
        style="position: fixed; left: -1000px; top: -1000px; width: 1px; height: 1px;"
      >
      <label
        for="tiny-checkbox"
        data-testid="tiny-checkbox-label"
        style="position: fixed; left: 24px; top: 280px; z-index: 1000; width: 22px; height: 22px;"
      >Tiny</label>
      <input
        type="checkbox"
        id="disabled-checkbox"
        disabled
        data-testid="disabled-checkbox"
        style="position: fixed; left: -1000px; top: -1000px; width: 1px; height: 1px;"
      >
      <label
        for="disabled-checkbox"
        data-testid="disabled-checkbox-label"
        style="position: fixed; left: 24px; top: 312px; z-index: 1000; width: 22px; height: 22px;"
      >Disabled</label>
    `;
    document.body.appendChild(fixture);
  });

  const report = await interactionAuditReport(page);
  const issueFor = (testid: string) => report.targetIssues.find((issue) => issue.testid === testid);

  expect(issueFor('bad-pointer-target')?.reason).toContain('pointer_events_none');
  expect(issueFor('edge-blocked-target')?.reason).toContain('interior_click_area_blocked');
  expect(issueFor('near-edge-blocked-target')?.reason).toContain('interior_click_area_blocked');
  expect(issueFor('missing-affordance-target')?.reason).toContain('missing_click_affordance');
  expect(issueFor('missing-contract-target')?.reason).toContain('missing_shared_hit_target_contract');
  expect(issueFor('button-declared-as-text-entry-target')?.reason).toContain('element_action_mismatch');
  expect(issueFor('button-declared-as-link-action')?.reason).toContain('hit_target_action_mismatch');
  expect(issueFor('button-declared-as-link-action')?.reason).toContain('element_action_mismatch');
  expect(issueFor('link-declared-as-press-target')?.reason).toContain('element_action_mismatch');
  expect(issueFor('kind-class-mismatch-target')?.reason).toContain('hit_target_kind_class_mismatch');
  expect(issueFor('tiny-checkbox-label')?.reason).toContain('too_small');
  expect(issueFor('disabled-pointer-target')).toBeUndefined();
  expect(issueFor('disabled-checkbox-label')).toBeUndefined();

  expect(report.clearanceIssues).toContainEqual(
    expect.objectContaining({
      a: expect.stringContaining('too-close-a'),
      axis: 'x',
      b: expect.stringContaining('too-close-b'),
      gap: 2
    })
  );
});

test('command routing audit catches visible dead command targets', async ({ page }) => {
  await page.goto(harnessURL());

  await expectCommandTargetsRoutable(page, 'initial workspace');
  await page.evaluate(() => {
    const fixture = document.createElement('button');
    fixture.type = 'button';
    fixture.textContent = 'Dead command';
    fixture.setAttribute('data-testid', 'dead-command-target');
    fixture.setAttribute('data-command-id', 'definitely-not-routable');
    fixture.style.position = 'fixed';
    fixture.style.left = '24px';
    fixture.style.top = '24px';
    fixture.style.zIndex = '1000';
    fixture.style.width = '160px';
    fixture.style.height = '48px';
    document.body.appendChild(fixture);
  });

  const report = await page.evaluate(() => {
    const harness = window as typeof window & {
      __quillCodeCommandRoutingAudit: () => {
        unroutableTargets: Array<{ commandID: string; testid: string; text: string }>;
      };
    };
    return harness.__quillCodeCommandRoutingAudit();
  });

  expect(report.unroutableTargets).toContainEqual({
    commandID: 'definitely-not-routable',
    testid: 'dead-command-target',
    text: 'Dead command'
  });
});

test('critical controls respond from the full interior click target, not only the center', async ({ page }) => {
  await page.goto(harnessURL());

  const initialProjectCount = await page.getByTestId('project-item').count();
  await clickTargetInteriorPoint(page.getByTestId('add-project-button'), 'add project bottom interior', 0.5, 0.82);
  await expect(page.getByTestId('project-item')).toHaveCount(initialProjectCount + 1);

  await clickTargetInteriorPoint(page.getByTestId('top-bar-overflow-button'), 'top-bar overflow leading interior', 0.2, 0.5);
  await expect(page.getByTestId('top-bar-overflow-menu')).toHaveAttribute('open', '');
  await clickTargetInteriorPoint(page.getByTestId('top-bar-overflow-button'), 'top-bar overflow trailing interior', 0.8, 0.5);
  await expect(page.getByTestId('top-bar-overflow-menu')).not.toHaveAttribute('open', '');

  await clickTargetInteriorPoint(page.getByTestId('model-picker-button'), 'model picker leading interior', 0.2, 0.5);
  await expect(page.getByTestId('model-browser')).toBeVisible();
  await clickTargetInteriorPoint(page.getByTestId('model-picker-button'), 'model picker trailing interior', 0.8, 0.5);
  await expect(page.getByTestId('model-browser')).not.toBeVisible();

  await clickTargetInteriorPoint(page.getByTestId('sidebar-tools-button'), 'sidebar tools leading interior', 0.2, 0.5);
  await expect(page.getByTestId('sidebar-tools-menu')).toHaveAttribute('open', '');
  await clickTargetInteriorPoint(page.getByTestId('browser-button'), 'browser tool row trailing interior', 0.85, 0.5);
  await expect(page.getByTestId('browser-pane')).toBeVisible();

  await page.getByLabel('Message').fill('run whoami');
  await clickTargetInteriorPoint(page.getByRole('button', { name: 'Send' }), 'composer send button leading interior', 0.2, 0.5);
  await expect(page.getByTestId('tool-card').last()).toHaveAttribute('data-status', 'done');
  await clickTargetInteriorPoint(page.getByTestId('tool-card-details').last().locator('summary'), 'tool details disclosure leading interior', 0.2, 0.5);
  await expect(page.getByTestId('tool-card-details').last()).toHaveAttribute('open', '');
});

test('secondary pane controls respond from the full interior click target', async ({ page }) => {
  await page.goto(harnessURL());

  await clickSidebarTool(page, 'activity-button');
  await expect(page.getByTestId('activity-pane')).toBeVisible();
  await clickTargetInteriorPoint(
    page.getByTestId('activity-plan-section').getByTestId('activity-section-toggle'),
    'activity plan toggle trailing interior',
    0.85,
    0.5
  );
  await expect(page.getByTestId('activity-plan-section')).toHaveAttribute('data-collapsed', 'true');
  await clickTargetInteriorPoint(
    page.getByTestId('activity-plan-section').getByTestId('activity-section-toggle'),
    'activity plan toggle leading interior',
    0.15,
    0.5
  );
  await expect(page.getByTestId('activity-plan-section')).toHaveAttribute('data-collapsed', 'false');
  await clickTargetInteriorPoint(
    page.getByTestId('activity-source-action').filter({ hasText: 'Open' }),
    'activity source Open leading interior',
    0.2,
    0.5
  );
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.file.read');
  await clickTargetInteriorPoint(
    page.getByTestId('activity-source-action').filter({ hasText: 'Edit' }),
    'activity source Edit trailing interior',
    0.8,
    0.5
  );
  await expect(page.getByLabel('Message')).toHaveValue('Edit instruction source AGENTS.md: ');
  const activityActionLayout = await page.getByTestId('activity-source-action').first().evaluate((button) => {
    const section = button.closest('[data-testid="activity-source-section"]');
    const buttonRect = button.getBoundingClientRect();
    const sectionRect = section?.getBoundingClientRect();
    return {
      buttonWidth: Math.round(buttonRect.width),
      sectionWidth: Math.round(sectionRect?.width ?? 0)
    };
  });
  expect(activityActionLayout.buttonWidth).toBeLessThan(activityActionLayout.sectionWidth - 24);

  await clickSidebarTool(page, 'terminal-button');
  await expect(page.getByTestId('terminal-pane')).toBeVisible();
  await page.getByLabel('Terminal command').fill('pwd');
  await clickTargetInteriorPoint(page.getByTestId('terminal-run'), 'terminal run trailing interior', 0.85, 0.5);
  await expect(page.getByTestId('terminal-stdout').last()).toContainText('/mock/QuillCode');
  await clickTargetInteriorPoint(page.getByTestId('terminal-clear'), 'terminal clear leading interior', 0.2, 0.5);
  await expect(page.getByTestId('terminal-entry')).toHaveCount(0);

  await clickSidebarTool(page, 'browser-button');
  await expect(page.getByTestId('browser-pane')).toBeVisible();
  await page.getByLabel('Browser address').fill('localhost:5173');
  await clickTargetInteriorPoint(page.getByTestId('browser-open'), 'browser open trailing interior', 0.85, 0.5);
  await expect(page.getByTestId('browser-current-url')).toHaveText('http://localhost:5173');
  await clickTargetInteriorPoint(page.getByTestId('browser-new-tab'), 'browser new tab leading interior', 0.2, 0.5);
  await expect(page.getByTestId('browser-tab')).toHaveCount(2);
  await page.getByLabel('Browser address').fill('example.com/docs');
  await clickTargetInteriorPoint(page.getByTestId('browser-open'), 'browser second tab open trailing interior', 0.85, 0.5);
  await expect(page.getByTestId('browser-current-url')).toHaveText('https://example.com/docs');
  await clickTargetInteriorPoint(page.getByTestId('browser-tab').first(), 'browser tab leading interior', 0.2, 0.5);
  await expect(page.getByTestId('browser-current-url')).toHaveText('http://localhost:5173');
  await page.getByLabel('Browser comment').fill('edge click works');
  await clickTargetInteriorPoint(page.getByTestId('browser-add-comment'), 'browser add comment trailing interior', 0.85, 0.5);
  await expect(page.getByTestId('browser-comment')).toContainText('edge click works');

  await page.getByTestId('extensions-button').click();
  await expect(page.getByTestId('extensions-pane')).toBeVisible();
  await clickTargetInteriorPoint(page.getByTestId('extension-start'), 'extension start trailing interior', 0.85, 0.5);
  await expect(page.getByTestId('extension-item').nth(2)).toContainText('Ready');
  await clickTargetInteriorPoint(page.getByTestId('extension-mcp-resource-action').first(), 'MCP resource capsule leading interior', 0.2, 0.5);
  await expect(page.getByTestId('tool-card').last()).toContainText('host.mcp.resource.read');
  await clickTargetInteriorPoint(page.getByTestId('extension-stop'), 'extension stop leading interior', 0.2, 0.5);
  await expect(page.getByTestId('extension-item').nth(2)).toContainText('Stopped');

  await clickSidebarTool(page, 'memories-button');
  await expect(page.getByTestId('memories-pane')).toBeVisible();
  await clickTargetInteriorPoint(page.getByTestId('memories-add'), 'memory add trailing interior', 0.85, 0.5);
  await expect(page.getByLabel('Message')).toHaveValue('/remember ');
  await clickTargetInteriorPoint(page.getByTestId('memory-edit').first(), 'memory edit leading interior', 0.2, 0.5);
  await expect(page.getByLabel('Message')).toHaveValue(/\/remember-edit global:memories\/preferences\.md/);

  await page.getByTestId('automations-button').click();
  await expect(page.getByTestId('automations-pane')).toBeVisible();
  await clickTargetInteriorPoint(page.getByTestId('automation-create-workspace-schedule'), 'automation create workspace trailing interior', 0.85, 0.5);
  await expect(page.getByTestId('automation-card')).toBeVisible();
  await clickTargetInteriorPoint(page.getByTestId('automation-run'), 'automation run leading interior', 0.2, 0.5);
  await expect(page.getByTestId('sidebar-item').first()).toContainText('Scheduled check: QuillCode');
  await expect(page.getByTestId('message').first()).toContainText('Run the scheduled workspace check for QuillCode.');
});

test('critical text entry targets focus and type from interior edges', async ({ page }) => {
  await page.goto(harnessURL());

  await openTopBarOverflow(page);
  await page.getByTestId('top-bar-overflow-search').click();
  await expect(page.getByTestId('search-panel')).toBeVisible();
  await expectTextEntryFocusFromInteriorPoint(page.getByTestId('search-input'), 'search input leading interior', 0.15, 0.5);
  await page.keyboard.type('launch');
  await expect(page.getByTestId('search-input')).toHaveValue('launch');
  await page.getByTestId('search-close').click();

  await openTopBarOverflow(page);
  await page.getByTestId('top-bar-overflow-command-palette').click();
  await expect(page.getByTestId('command-palette-panel')).toBeVisible();
  await expectTextEntryFocusFromInteriorPoint(page.getByTestId('command-palette-input'), 'command palette trailing interior', 0.85, 0.5);
  await page.keyboard.type('git');
  await expect(page.getByTestId('command-palette-input')).toHaveValue('git');
  await page.getByTestId('command-palette-close').click();

  await clickSidebarTool(page, 'terminal-button');
  await expect(page.getByTestId('terminal-pane')).toBeVisible();
  await expectTextEntryFocusFromInteriorPoint(page.getByTestId('terminal-input'), 'terminal input leading interior', 0.15, 0.5);
  await page.keyboard.type('pwd');
  await expect(page.getByTestId('terminal-input')).toHaveValue('pwd');

  await clickSidebarTool(page, 'browser-button');
  await expect(page.getByTestId('browser-pane')).toBeVisible();
  await expectTextEntryFocusFromInteriorPoint(page.getByTestId('browser-address'), 'browser address trailing interior', 0.85, 0.5);
  await page.keyboard.type('localhost:5173');
  await expect(page.getByTestId('browser-address')).toHaveValue('localhost:5173');
  await expectTextEntryFocusFromInteriorPoint(page.getByTestId('browser-comment-input'), 'browser comment leading interior', 0.15, 0.5);
  await page.keyboard.type('looks good');
  await expect(page.getByTestId('browser-comment-input')).toHaveValue('looks good');

  await openSettings(page);
  await expect(page.getByTestId('settings-panel')).toBeVisible();
  const baseURL = page.getByLabel('TrustedRouter API base URL');
  await expectTextEntryFocusFromInteriorPoint(baseURL, 'settings API base URL input leading interior', 0.15, 0.5);
  await baseURL.press(process.platform === 'darwin' ? 'Meta+A' : 'Control+A');
  await page.keyboard.type('https://api.trustedrouter.com/v1');
  await expect(baseURL).toHaveValue('https://api.trustedrouter.com/v1');
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

test('mock harness audits narrow viewport click targets across squeezed states', async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 720 });
  await page.goto(harnessURL());

  await expectInteractionTargetsClean(page, 'narrow initial workspace');

  await openTopBarOverflow(page);
  await expect(page.getByTestId('top-bar-overflow-menu')).toHaveAttribute('open', '');
  await expectInteractionTargetsClean(page, 'narrow top-bar overflow menu');
  await page.getByTestId('top-bar-overflow-button').click();

  await page.getByTestId('model-picker-button').click();
  await expect(page.getByTestId('model-browser')).toBeVisible();
  await expectInteractionTargetsClean(page, 'narrow model picker');
  await page.getByTestId('model-picker-button').click();

  await openTopBarOverflow(page);
  await page.getByTestId('top-bar-overflow-command-palette').click();
  await expect(page.getByTestId('command-palette-panel')).toBeVisible();
  await expectInteractionTargetsClean(page, 'narrow command palette');
  await clickCommandPaletteCommand(page, '>browser', 'toggle-browser');
  await expect(page.getByTestId('browser-pane')).toBeVisible();
  await expectInteractionTargetsClean(page, 'narrow browser pane');

  await openSettings(page);
  await expect(page.getByTestId('settings-panel')).toBeVisible();
  await expectInteractionTargetsClean(page, 'narrow settings panel');
  await page.getByTestId('settings-cancel').click();

  await page.getByLabel('Message').fill('run whoami');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('tool-card').last()).toHaveAttribute('data-status', 'done');
  await expectInteractionTargetsClean(page, 'narrow transcript with tool card');

  await page.keyboard.press('Meta+F');
  await expect(page.getByTestId('find-bar')).toBeVisible();
  await expectInteractionTargetsClean(page, 'narrow find bar');
  await page.getByTestId('find-close').click();
});
