import { test, expect, type Page } from '@playwright/test';
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

async function fillComposerAndSend(page: Page, text: string) {
  const composer = page.getByLabel('Message');
  const sendButton = page.getByTestId('send-button');
  await expect(sendButton).toBeVisible();
  await composer.fill(text);
  await expect(sendButton).toBeEnabled();
  await sendButton.click();
}

test('primary utility controls activate from near-edge target points', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('run whoami');
  await expect(page.getByTestId('send-button')).toBeEnabled();
  await clickTargetInteriorPoint(page.getByRole('button', { name: 'Send' }), 'send button trailing edge', 0.92, 0.5);
  await expect(page.getByTestId('tool-card').last()).toHaveAttribute('data-status', 'done');
  await expect(page.getByTestId('sidebar-item')).toContainText('run whoami');

  await openTopBarOverflow(page);
  await clickTargetInteriorPoint(
    page.getByTestId('top-bar-overflow-search'),
    'top-bar search row trailing edge',
    0.92,
    0.5
  );
  await expect(page.getByTestId('search-panel')).toBeVisible();
  await page.getByTestId('search-input').fill('whoami');
  await expect(page.getByTestId('search-result')).toHaveCount(1);
  await clickTargetInteriorPoint(page.getByTestId('search-result').first(), 'search result trailing edge', 0.92, 0.5);
  await expect(page.getByTestId('search-panel')).not.toBeVisible();

  await clickSidebarTool(page, 'command-palette-button');
  await fillCommandPalette(page, '>browser');
  await clickTargetInteriorPoint(
    commandPaletteResult(page, 'toggle-browser'),
    'command palette browser result leading edge',
    0.08,
    0.5
  );
  await expect(page.getByTestId('browser-pane')).toBeVisible();

  await page.getByTestId('model-picker-button').click();
  await expect(page.getByTestId('model-browser')).toBeVisible();
  const firstModelRow = page.getByTestId('model-row').first();
  const detailButton = firstModelRow.getByTestId('model-detail-button');
  const expandedBefore = await detailButton.getAttribute('aria-expanded');
  await clickTargetInteriorPoint(detailButton, 'model detail icon leading edge', 0.08, 0.5);
  await expect(detailButton).toHaveAttribute('aria-expanded', expandedBefore === 'true' ? 'false' : 'true');
  const favoriteLabelBefore = await firstModelRow.getByTestId('model-favorite-button').getAttribute('aria-label');
  await clickTargetInteriorPoint(
    firstModelRow.getByTestId('model-favorite-button'),
    'model favorite icon trailing edge',
    0.92,
    0.5
  );
  await expect(firstModelRow.getByTestId('model-favorite-button')).not.toHaveAttribute(
    'aria-label',
    favoriteLabelBefore || ''
  );
  await clickTargetInteriorPoint(
    firstModelRow.getByTestId('model-option'),
    'model option row trailing edge',
    0.92,
    0.5
  );
  await expect(page.getByTestId('model-browser')).not.toBeVisible();

  await openSettings(page);
  await expect(page.getByTestId('settings-panel')).toBeVisible();
  await clickTargetInteriorPoint(page.getByTestId('settings-sign-in'), 'settings sign-in leading edge', 0.08, 0.5);
  await expect(page.getByTestId('settings-login-status')).toContainText('Opening TrustedRouter sign in');
  await clickTargetInteriorPoint(page.getByTestId('settings-save'), 'settings save trailing edge', 0.92, 0.5);
  await expect(page.getByTestId('settings-panel')).not.toBeVisible();

  await clickSidebarTool(page, 'command-palette-button');
  await clickCommandPaletteCommand(page, '>open worktree', 'git-worktree-open');
  await expect(page.getByTestId('worktree-open-panel')).toBeVisible();
  const worktreeChoice = page.getByTestId('worktree-choice').first();
  await expect(worktreeChoice).toBeVisible();
  const worktreeChoicePath = await worktreeChoice.getAttribute('data-path');
  await clickTargetInteriorPoint(worktreeChoice, 'worktree choice trailing edge', 0.92, 0.5);
  await expect(page.getByLabel('Worktree folder')).toHaveValue(worktreeChoicePath || '');
  await clickTargetInteriorPoint(page.getByTestId('worktree-dialog-cancel'), 'worktree cancel leading edge', 0.08, 0.5);
  await expect(page.getByTestId('worktree-open-panel')).not.toBeVisible();
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
  await clickTargetInteriorPoint(
    page.getByTestId('browser-open'),
    'browser second tab open trailing interior',
    0.85,
    0.5
  );
  await expect(page.getByTestId('browser-current-url')).toHaveText('https://example.com/docs');
  await clickTargetInteriorPoint(page.getByTestId('browser-tab').first(), 'browser tab leading interior', 0.2, 0.5);
  await expect(page.getByTestId('browser-current-url')).toHaveText('http://localhost:5173');
  await page.getByLabel('Browser comment').fill('edge click works');
  await clickTargetInteriorPoint(
    page.getByTestId('browser-add-comment'),
    'browser add comment trailing interior',
    0.85,
    0.5
  );
  await expect(page.getByTestId('browser-comment')).toContainText('edge click works');

  await page.getByTestId('extensions-button').click();
  await expect(page.getByTestId('extensions-pane')).toBeVisible();
  const filesystemMCP = page.getByTestId('extension-item').filter({ hasText: 'Filesystem MCP' });
  await clickTargetInteriorPoint(
    filesystemMCP.getByTestId('extension-start'),
    'extension start trailing interior',
    0.85,
    0.5
  );
  await expect(filesystemMCP).toContainText('Ready');
  await clickTargetInteriorPoint(
    filesystemMCP.getByTestId('extension-mcp-resource-action').first(),
    'MCP resource capsule leading interior',
    0.2,
    0.5
  );
  await expect(page.getByTestId('tool-card').last()).toContainText('host.mcp.resource.read');
  await clickTargetInteriorPoint(
    filesystemMCP.getByTestId('extension-stop'),
    'extension stop leading interior',
    0.2,
    0.5
  );
  await expect(filesystemMCP).toContainText('Stopped');

  await clickSidebarTool(page, 'memories-button');
  await expect(page.getByTestId('memories-pane')).toBeVisible();
  await clickTargetInteriorPoint(page.getByTestId('memories-add'), 'memory add trailing interior', 0.85, 0.5);
  await expect(page.getByLabel('Message')).toHaveValue('/remember ');
  await clickTargetInteriorPoint(page.getByTestId('memory-edit').first(), 'memory edit leading interior', 0.2, 0.5);
  await expect(page.getByLabel('Message')).toHaveValue(/\/remember-edit global:memories\/preferences\.md/);

  await page.getByTestId('automations-button').click();
  await expect(page.getByTestId('automations-pane')).toBeVisible();
  await clickTargetInteriorPoint(
    page.getByTestId('automation-create-workspace-schedule'),
    'automation create workspace trailing interior',
    0.85,
    0.5
  );
  await expect(page.getByTestId('automation-card')).toBeVisible();
  await clickTargetInteriorPoint(page.getByTestId('automation-run'), 'automation run leading interior', 0.2, 0.5);
  await expect(page.getByTestId('sidebar-item').first()).toContainText('Scheduled check: QuillCode');
  await expect(page.getByTestId('message').first()).toContainText('Run the scheduled workspace check for QuillCode.');
});

test('sidebar and project controls activate from near-edge target points', async ({ page }) => {
  await page.goto(harnessURL());

  await clickTargetInteriorPoint(page.getByTestId('new-chat-button'), 'new chat trailing edge', 0.92, 0.5);
  await expect(page.getByTestId('transcript-empty')).toBeVisible();
  await clickTargetInteriorPoint(page.getByTestId('sidebar-search-button'), 'sidebar search leading edge', 0.08, 0.5);
  await expect(page.getByTestId('search-panel')).toBeVisible();
  await page.getByTestId('search-close').click();

  await fillComposerAndSend(page, 'run whoami');
  await expect(page.getByTestId('tool-card').last()).toHaveAttribute('data-status', 'done');

  await page.evaluate(() => {
    const harness = window as unknown as {
      addSidebarSavedSearch: (title: string, query: string, id: string) => string | null;
    };
    harness.addSidebarSavedSearch('Shell work', 'whoami', 'saved-shell-work');
    harness.addSidebarSavedSearch('Run work', 'run', 'saved-run-work');
  });
  await expect(page.getByTestId('sidebar-saved-search')).toHaveCount(2);

  await clickTargetInteriorPoint(
    page.getByTestId('sidebar-filter').filter({ hasText: 'Pinned' }),
    'sidebar pinned filter trailing edge',
    0.92,
    0.5
  );
  await expect(
    page.getByTestId('sidebar-filter').filter({ hasText: 'Pinned' })
  ).toHaveAttribute('aria-pressed', 'true');
  await clickTargetInteriorPoint(
    page.getByTestId('sidebar-filter').filter({ hasText: 'All' }),
    'sidebar all filter leading edge',
    0.08,
    0.5
  );
  await expect(page.getByTestId('sidebar-filter').filter({ hasText: 'All' })).toHaveAttribute('aria-pressed', 'true');

  const firstSavedSearchTitle = await page.getByTestId('sidebar-saved-search').first().textContent();
  await clickTargetInteriorPoint(
    page.getByTestId('sidebar-saved-search').first(),
    'saved search trailing edge',
    0.92,
    0.5
  );
  await expect(page.getByTestId('sidebar-saved-search').first()).toHaveAttribute('aria-pressed', 'true');
  await clickTargetInteriorPoint(
    page.getByTestId('sidebar-saved-search-move-down').first(),
    'saved search move down leading edge',
    0.08,
    0.5
  );
  await expect(page.getByTestId('sidebar-saved-search').nth(1)).toContainText(
    firstSavedSearchTitle?.replace(/\d+/g, '').trim() || 'Shell work'
  );
  await clickTargetInteriorPoint(
    page.getByTestId('sidebar-saved-search-delete').first(),
    'saved search delete trailing edge',
    0.92,
    0.5
  );
  await expect(page.getByTestId('sidebar-saved-search')).toHaveCount(1);

  await clickTargetInteriorPoint(page.getByTestId('sidebar-item').first(), 'sidebar item trailing edge', 0.92, 0.5);
  await expect(page.getByTestId('sidebar-item').first()).toHaveAttribute('aria-current', 'true');
  await clickTargetInteriorPoint(
    page.getByTestId('sidebar-item-actions').first().locator('summary'),
    'sidebar thread menu leading edge',
    0.08,
    0.5
  );
  await expect(page.getByTestId('sidebar-item-actions').first()).toHaveAttribute('open', '');
  await clickTargetInteriorPoint(
    page.getByTestId('sidebar-thread-action').filter({ hasText: 'Duplicate' }),
    'sidebar duplicate action trailing edge',
    0.92,
    0.5
  );
  await expect(page.getByTestId('top-bar-title')).toContainText('Copy:');

  await clickTargetInteriorPoint(page.getByTestId('project-item').first(), 'project row trailing edge', 0.92, 0.5);
  await expect(page.getByTestId('project-item').first()).toHaveAttribute('aria-current', 'true');
  await clickTargetInteriorPoint(
    page.getByTestId('project-item-actions').first().locator('summary'),
    'project menu leading edge',
    0.08,
    0.5
  );
  await expect(page.getByTestId('project-item-actions').first()).toHaveAttribute('open', '');
  await clickTargetInteriorPoint(
    page.getByTestId('project-action').filter({ hasText: 'Refresh context' }),
    'project refresh action trailing edge',
    0.92,
    0.5
  );
  await expect(page.getByTestId('message').last()).toContainText('Refreshed project context');
});

test('transcript, recovery, and suggestion controls activate from near-edge target points', async ({ page }) => {
  await page.goto(harnessURL());

  await clickTargetInteriorPoint(
    page.getByTestId('empty-starter-action').first(),
    'empty starter trailing edge',
    0.92,
    0.5
  );
  await expect(page.getByTestId('message').first()).toContainText('Review the current git diff');

  await page.getByLabel('Message').fill('/git');
  await expect(page.getByTestId('slash-suggestions')).toBeVisible();
  await clickTargetInteriorPoint(
    page.getByTestId('slash-suggestion').first(),
    'slash suggestion leading edge',
    0.08,
    0.5
  );
  await expect(page.getByLabel('Message')).toHaveValue(/^\/[a-z-]+/);

  await fillComposerAndSend(page, 'run whoami');
  await expect(page.getByTestId('tool-card').last()).toHaveAttribute('data-status', 'done');

  const whoamiAnswer = page.getByTestId('message').filter({ hasText: 'You are `mock-user` in this workspace.' });
  await expect(whoamiAnswer).toBeVisible();
  await clickTargetInteriorPoint(
    whoamiAnswer.getByTestId('message-feedback-up'),
    'assistant feedback leading edge',
    0.08,
    0.5
  );
  await expect(whoamiAnswer.getByTestId('message-feedback-up')).toHaveAttribute('data-selected', 'true');
  await clickTargetInteriorPoint(
    page.getByTestId('message-use-as-draft').last(),
    'user use-as-draft trailing edge',
    0.92,
    0.5
  );
  await expect(page.getByLabel('Message')).toHaveValue('run whoami');
  await clickTargetInteriorPoint(page.getByTestId('message-retry').last(), 'assistant retry trailing edge', 0.92, 0.5);
  await expect(page.getByTestId('tool-card').last()).toHaveAttribute('data-status', 'done');

  await fillComposerAndSend(page, 'long context ' + 'word '.repeat(22000));
  await expect(page.getByTestId('context-banner')).toBeVisible();
  await clickTargetInteriorPoint(page.getByTestId('context-new-thread'), 'context new-thread trailing edge', 0.92, 0.5);
  await expect(page.getByTestId('transcript-empty')).toBeVisible();

  await fillComposerAndSend(page, 'trigger network failure');
  await expect(page.getByTestId('runtime-issue-action')).toHaveText('Retry');
  await clickTargetInteriorPoint(page.getByTestId('runtime-issue-action'), 'runtime retry leading edge', 0.08, 0.5);
  await expect(page.getByTestId('runtime-issue')).not.toBeVisible();
});

test('critical text entry targets focus and type from interior edges', async ({ page }) => {
  await page.goto(harnessURL());

  await openTopBarOverflow(page);
  await page.getByTestId('top-bar-overflow-search').click();
  await expect(page.getByTestId('search-panel')).toBeVisible();
  await expectTextEntryFocusFromInteriorPoint(
    page.getByTestId('search-input'),
    'search input leading interior',
    0.15,
    0.5
  );
  await page.keyboard.type('launch');
  await expect(page.getByTestId('search-input')).toHaveValue('launch');
  await page.getByTestId('search-close').click();

  await openTopBarOverflow(page);
  await page.getByTestId('top-bar-overflow-command-palette').click();
  await expect(page.getByTestId('command-palette-panel')).toBeVisible();
  await expectTextEntryFocusFromInteriorPoint(
    page.getByTestId('command-palette-input'),
    'command palette trailing interior',
    0.85,
    0.5
  );
  await page.keyboard.type('git');
  await expect(page.getByTestId('command-palette-input')).toHaveValue('git');
  await page.getByTestId('command-palette-close').click();

  await clickSidebarTool(page, 'terminal-button');
  await expect(page.getByTestId('terminal-pane')).toBeVisible();
  await expectTextEntryFocusFromInteriorPoint(
    page.getByTestId('terminal-input'),
    'terminal input leading interior',
    0.15,
    0.5
  );
  await page.keyboard.type('pwd');
  await expect(page.getByTestId('terminal-input')).toHaveValue('pwd');

  await clickSidebarTool(page, 'browser-button');
  await expect(page.getByTestId('browser-pane')).toBeVisible();
  await expectTextEntryFocusFromInteriorPoint(
    page.getByTestId('browser-address'),
    'browser address trailing interior',
    0.85,
    0.5
  );
  await page.keyboard.type('localhost:5173');
  await expect(page.getByTestId('browser-address')).toHaveValue('localhost:5173');
  await expectTextEntryFocusFromInteriorPoint(
    page.getByTestId('browser-comment-input'),
    'browser comment leading interior',
    0.15,
    0.5
  );
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
