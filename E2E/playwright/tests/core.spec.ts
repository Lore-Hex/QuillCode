import { test, expect } from '@playwright/test';
import {
  clickSidebarTool,
  elementRect,
  harnessURL,
  openSidebarTools,
  openTopBarOverflow
} from './harness-helpers';

test('mock harness executes simple command flow', async ({ page }) => {
  await page.goto(harnessURL());
  await expect(page.getByTestId('workspace')).toBeVisible();
  await expect(page.getByTestId('top-bar')).toBeVisible();
  await expect(page.getByTestId('sidebar')).toBeVisible();
  await expect(page.getByTestId('project-item')).toContainText('QuillCode');
  await expect(page.getByTestId('project-item')).toHaveAttribute('aria-current', 'true');
  await expect(page.getByTestId('transcript-empty')).toBeVisible();
  await expect(page.getByTestId('empty-starter-action')).toHaveCount(3);
  await expect(page.locator('[data-testid="top-bar"] [data-testid="model-picker-button"]')).toHaveCount(0);
  await expect(page.getByTestId('composer-surface')).toBeVisible();
  await expect(page.getByTestId('composer-controls')).toBeVisible();
  await expect(page.locator('[data-testid="composer"] [data-testid="model-picker-button"]')).toBeVisible();
  await expect(page.getByTestId('model-picker-button')).toHaveText('Nike 1.0');
  await expect(page.getByTestId('model-picker-button')).not.toContainText('Auto');
  await expect(page.getByTestId('mode-picker-button')).toBeVisible();
  await expect(page.getByTestId('mode-picker-button')).not.toContainText('Mode');
  await expect(page.getByTestId('mode-pill')).toHaveText('Auto');
  await expect(page.locator('[data-testid="mode-picker-button"] .mode-dot')).toHaveCount(1);
  await expect(page.getByTestId('composer-agent-status')).toHaveCount(0);
  const modelButtonBounds = await elementRect(page, '[data-testid="model-picker-button"]');
  const modeButtonBounds = await elementRect(page, '[data-testid="mode-picker-button"]');
  expect(modeButtonBounds.left - modelButtonBounds.right).toBeGreaterThanOrEqual(8);
  await page.getByTestId('model-picker-button').click();
  await expect(page.getByTestId('model-category')).toHaveCount(4);
  await page.getByTestId('model-picker-button').click();
  await expect(page.getByTestId('send-button')).toBeDisabled();

  await expect(page.getByTestId('new-chat-button')).toBeVisible();
  await expect(page.getByTestId('sidebar-search-button')).toBeVisible();
  await expect(page.getByTestId('extensions-button')).toBeVisible();
  await expect(page.getByTestId('automations-button')).toBeVisible();
  await openSidebarTools(page);
  await expect(page.getByTestId('sidebar-tools-section-title')).toHaveText([
    'Navigate',
    'Workspace',
    'Context'
  ]);
  await expect(page.locator('[data-testid="sidebar-tools-section"][data-command-group="navigate"]')).toContainText('Command palette');
  await expect(page.locator('[data-testid="sidebar-tools-section"][data-command-group="workspace"]')).toContainText('Terminal');
  await expect(page.locator('[data-testid="sidebar-tools-section"][data-command-group="workspace"]')).toContainText('Review');
  await page.getByTestId('sidebar-tools-button').click();
  await expect(page.getByTestId('sidebar-tools-menu')).not.toHaveAttribute('open', '');

  await openTopBarOverflow(page);
  await expect(page.getByTestId('top-bar-overflow-command-palette')).toBeVisible();
  await expect(page.getByTestId('top-bar-overflow-search')).toBeVisible();
  await expect(page.getByTestId('top-bar-overflow-computer-use')).toBeVisible();
  await expect(page.getByTestId('top-bar-overflow-settings')).toBeVisible();
  await expect(page.getByTestId('top-bar-overflow-keyboard-shortcuts')).toBeVisible();
  await expect(page.getByTestId('top-bar-overflow-stop-all')).toHaveCount(0);
  await expect(page.getByTestId('top-bar-stop-button')).toHaveCount(0);
  await page.getByTestId('top-bar-overflow-settings').click();
  await expect(page.getByTestId('settings-panel')).toBeVisible();
  await expect(page.getByTestId('settings-key-status')).toHaveText('Not signed in');
  await expect(page.getByTestId('settings-model-catalog-status')).toHaveText('Bundled catalog');
  await expect(page.getByTestId('settings-provider-health')).toHaveText('Provider health unavailable');
  await page.getByTestId('settings-sign-in').click();
  await expect(page.getByTestId('last-opened-url')).toHaveText('http://localhost:3000/callback');
  await page.getByLabel('TrustedRouter API base URL').fill('https://api.trustedrouter.test/v1');
  await page.getByLabel('Authentication').selectOption('developer-override');
  await page.getByLabel('Replace API key').fill('sk-tr-v1-test');
  await page.getByTestId('settings-save').click();
  await expect(page.getByTestId('settings-panel')).toBeHidden();
  await expect(page.getByTestId('agent-status')).toHaveText('TrustedRouter ready');

  await page.getByTestId('model-picker-button').click();
  await page.getByTestId('model-search').fill('glm');
  await page.locator('[data-testid="model-option"][data-model-id="z-ai/glm-5.2"]').click();
  await expect(page.getByTestId('model-picker-button')).toHaveText('z-ai/GLM 5.2');
  await expect(page.getByTestId('mode-pill')).toHaveText('Auto');

  await page.getByLabel('Message').fill('run whoami');
  await expect(page.getByTestId('send-button')).toBeEnabled();
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('sidebar-item')).toContainText('run whoami');
  await expect(page.getByTestId('sidebar-item')).toHaveAttribute('title', 'z-ai/GLM 5.2');
  await expect(page.getByTestId('sidebar-item')).toHaveAttribute('aria-label', /z-ai\/GLM 5\.2/);
  await expect(page.getByTestId('top-bar-title')).toHaveText('run whoami');
  await expect(page.getByTestId('top-bar-subtitle')).toContainText('QuillCode - Auto');
  await expect(page.getByTestId('top-bar-token-budget')).toBeVisible();
  await expect(page.getByTestId('top-bar-token-budget-primary')).toContainText(/\/ .* tokens/);
  await expect(page.getByTestId('top-bar-token-budget-secondary')).toContainText(/left/);
  await expect(page.getByTestId('tool-card-title')).toHaveText('host.shell.run');
  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-status', 'done');
  await expect(page.getByTestId('tool-card-subtitle')).toHaveText('Completed · whoami');
  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-density', 'collapsed');
  await expect(page.getByTestId('tool-card-input')).toContainText('whoami');
  await expect(page.getByTestId('tool-card-output')).toContainText('mock-user');
  await expect(page.getByTestId('tool-card-details')).not.toHaveAttribute('open', '');
  await expect(page.getByTestId('tool-card-details')).toContainText('Show details');
  await expect(page.getByText('You are `mock-user` in this workspace.')).toBeVisible();
  await expect(page.getByTestId('message-copy').first()).toHaveText('Copy');
  await page.getByTestId('message-copy').first().click();
  await expect(page.getByTestId('message-copy').first()).toHaveText('Copied');
  await expect(page.getByTestId('message-copy').first()).toHaveAttribute('data-copied', 'true');
  await expect(page.getByTestId('tool-card-copy')).toHaveText('Copy output');
  await page.getByTestId('tool-card-copy').click();
  await expect(page.getByTestId('tool-card-copy')).toHaveText('Copied');
  await expect(page.getByTestId('tool-card-copy')).toHaveAttribute('data-copied', 'true');
  await expect(page.getByTestId('message-use-as-draft')).toHaveCount(1);
  await page.getByTestId('message-use-as-draft').click();
  await expect(page.getByLabel('Message')).toHaveValue('run whoami');
  await expect(page.getByTestId('send-button')).toBeEnabled();
  await expect(page.getByTestId('message-feedback-up')).toHaveCount(0);
  await expect(page.getByTestId('message-feedback-down')).toHaveCount(0);

  const transcriptItems = page.locator('[data-testid="message"], [data-testid="tool-card"]');
  await expect(transcriptItems.nth(0)).toContainText('run whoami');
  await expect(transcriptItems.nth(1)).toContainText('host.shell.run');
  await expect(transcriptItems.nth(2)).toContainText('You are `mock-user` in this workspace.');
  await expect(page.getByTestId('message-retry')).toHaveCount(1);
  await page.getByTestId('message-retry').click();
  await expect(page.getByTestId('tool-card')).toHaveCount(2);
  await expect(page.getByTestId('message').filter({ hasText: 'You are `mock-user` in this workspace.' })).toHaveCount(2);
  await expect(page.getByTestId('message-retry')).toHaveCount(1);
  await expect(page.getByTestId('message-use-as-draft')).toHaveCount(2);
});

test('empty starter action submits immediately through the normal composer path', async ({ page }) => {
  await page.goto(harnessURL());
  await expect(page.getByTestId('transcript-empty')).toBeVisible();

  await page.getByTestId('empty-starter-action').filter({ hasText: 'Review changes' }).click();

  await expect(page.getByTestId('transcript-empty')).toHaveCount(0);
  await expect(page.getByTestId('message').filter({
    hasText: 'Review the current git diff and call out risks, missing tests, and next steps.'
  })).toBeVisible();
  await expect(page.getByTestId('tool-card').first()).toContainText('host.git.diff');
  await expect(page.getByText('Git diff:')).toBeVisible();
  await expect(page.getByLabel('Message')).toHaveValue('');
  await expect(page.getByTestId('send-button')).toBeDisabled();
});

test('mock harness copies the whole conversation as Markdown from the command palette', async ({ page }) => {
  await page.goto(harnessURL());

  // Seed a conversation so there is something to export.
  await page.getByLabel('Message').fill('Run the tests');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('message').first()).toContainText('Run the tests');

  // Run "Copy conversation" from the command palette.
  await clickSidebarTool(page, 'command-palette-button');
  await page.getByLabel('Search commands').fill('copy conversation');
  await page.locator('[data-testid="command-palette-result"][data-command-id="copy-conversation"]').click();
  await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);

  // A confirmation toast appears — it only shows when the export produced non-empty Markdown.
  await expect(page.getByTestId('conversation-copied-toast')).toBeVisible();

  // The exported Markdown must match the Swift TranscriptMarkdownExporter byte-for-byte
  // (the same fixture is asserted in TranscriptMarkdownExporterTests) — this enforces the
  // Swift↔JS "never drift" contract rather than just trusting the shared-code comments.
  const markdown = await page.evaluate(() => (window as Window & { __lastConversationMarkdown?: string }).__lastConversationMarkdown);
  expect(markdown).toBe(
    '## User\n\nRun the tests\n\n' +
    '### host.shell.run\n\n```\n' +
    '{\n  "ok": true,\n  "stdout": "ran: the tests\\n",\n  "stderr": "",\n  "exitCode": 0\n}\n' +
    '```\n\n## Assistant\n\nOutput:\nran: the tests'
  );

  // Run the file export command. The harness records the suggested file instead of opening
  // a native save panel; this pins the UI routing and Markdown bytes without test flakiness.
  await clickSidebarTool(page, 'command-palette-button');
  await page.getByLabel('Search commands').fill('export conversation');
  await page.locator(
    '[data-testid="command-palette-result"][data-command-id="export-conversation-markdown"]'
  ).click();
  await expect(page.getByTestId('conversation-exported-toast')).toBeVisible();
  const exported = await page.evaluate(() => (
    window as Window & {
      __lastConversationMarkdownExport?: { fileName: string; markdown: string }
    }
  ).__lastConversationMarkdownExport);
  expect(exported?.fileName).toMatch(/\.md$/);
  expect(exported?.markdown).toBe(markdown);

  await page.getByLabel('Message').fill('/copy');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('conversation-copied-toast')).toBeVisible();
  const slashMarkdown = await page.evaluate(() => (
    window as Window & { __lastConversationMarkdown?: string }
  ).__lastConversationMarkdown);
  expect(slashMarkdown).toBe(`${markdown}\n\n## User\n\n/copy`);

  await page.getByLabel('Message').fill('/export');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('conversation-exported-toast')).toBeVisible();
  const slashExported = await page.evaluate(() => (
    window as Window & {
      __lastConversationMarkdownExport?: { fileName: string; markdown: string }
    }
  ).__lastConversationMarkdownExport);
  expect(slashExported?.fileName).toMatch(/\.md$/);
  expect(slashExported?.markdown).toBe(`${slashMarkdown}\n\n## User\n\n/export`);
});

test('mock harness enters Plan mode via /plan and the mode pill reflects it', async ({ page }) => {
  await page.goto(harnessURL());
  const message = page.getByLabel('Message');

  // The pill starts on Auto.
  await expect(page.getByTestId('mode-pill')).toHaveText('Auto');
  await expect(page.getByTestId('mode-picker-button')).toHaveAttribute('data-mode-tone', 'auto');

  // /plan switches into Plan mode (its own pill tone).
  await message.fill('/plan');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('mode-pill')).toHaveText('Plan');
  await expect(page.getByTestId('mode-picker-button')).toHaveAttribute('data-mode-tone', 'plan');

  // /mode auto returns to Auto, proving the toggle is reversible.
  await message.fill('/mode auto');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('mode-pill')).toHaveText('Auto');
  await expect(page.getByTestId('mode-picker-button')).toHaveAttribute('data-mode-tone', 'auto');
});

test('mock harness resumes the agent after approving a Plan-mode block', async ({ page }) => {
  await page.goto(harnessURL());
  const message = page.getByLabel('Message');

  // Enter Plan mode.
  await message.fill('/plan');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('mode-pill')).toHaveText('Plan');

  // A blocked mutating tool surfaces an approvable card while planning.
  await page.evaluate(() => {
    const harness = window as typeof window & {
      addToolCard: (card: Record<string, unknown>) => void;
      render: () => void;
    };
    harness.addToolCard({
      id: 'shell-plan',
      title: 'host.shell.run',
      subtitle: 'Ready to run · touch a.txt',
      status: 'review',
      reviewState: 'ready',
      density: 'peek',
      inputJSON: JSON.stringify({ cmd: 'touch a.txt' }, null, 2),
      isExpanded: false,
      actions: [
        { id: 'tca-approve', title: 'Run', kind: 'approve', requestID: 'plan-approval', style: 'primary' }
      ]
    });
    harness.render();
  });
  await expect(page.getByTestId('tool-card-action').filter({ hasText: 'Run' })).toBeVisible();

  // Approving runs the held tool AND resumes the agent to propose the next step — but the
  // thread STAYS in Plan, and that next step is itself gated (a fresh approvable card), not
  // auto-run. One approval never flips to autonomous execution.
  await page.getByTestId('tool-card-action').filter({ hasText: 'Run' }).first().click();
  await expect(page.getByTestId('mode-pill')).toHaveText('Plan');
  await expect(page.getByTestId('mode-picker-button')).toHaveAttribute('data-mode-tone', 'plan');
  await expect(page.getByTestId('message').last()).toContainText('continuing the plan');
  // The resumed next step surfaces as a new review card awaiting approval.
  await expect(page.getByTestId('tool-card').filter({ hasText: 'touch step-two.txt' })).toHaveAttribute('data-status', 'review');
});

test('Shift+Tab cycles approval mode, including while composing, without double-firing', async ({ page }) => {
  await page.goto(harnessURL());
  const message = page.getByLabel('Message');
  const pill = page.getByTestId('mode-pill');

  // Shift+Tab cycles the full Codex ring: Auto → Plan → Review → Read-only → Auto.
  await expect(pill).toHaveText('Auto');
  await page.keyboard.press('Shift+Tab');
  await expect(pill).toHaveText('Plan');
  await page.keyboard.press('Shift+Tab');
  await expect(pill).toHaveText('Review');
  await page.keyboard.press('Shift+Tab');
  await expect(pill).toHaveText('Read-only');
  await page.keyboard.press('Shift+Tab');
  await expect(pill).toHaveText('Auto');
  await expect(page.getByTestId('mode-picker-button')).toHaveAttribute('data-mode-tone', 'auto');

  // The killer: with a slash draft present, plain Tab still ACCEPTS the suggestion…
  await message.fill('/mod');
  await message.focus();
  await page.keyboard.press('Tab');
  await expect(message).toHaveValue('/mode ');

  // …while Shift+Tab cycles the mode WITHOUT accepting a suggestion or disturbing the draft
  // (no double-fire — the composer leaves Shift+Tab to the global shortcut).
  await message.fill('/mod');
  await message.focus();
  await page.keyboard.press('Shift+Tab');
  await expect(pill).toHaveText('Plan');
  await expect(message).toHaveValue('/mod');
});

test('Shift+Tab does not cycle mode while focus is in a non-composer input', async ({ page }) => {
  await page.goto(harnessURL());
  await expect(page.getByTestId('mode-pill')).toHaveText('Auto');

  // Open the model picker and focus its search field — a non-composer editable input.
  await page.getByTestId('model-picker-button').click();
  await page.getByTestId('model-search').focus();
  await page.keyboard.press('Shift+Tab');

  // Shift+Tab in a search field is reverse focus traversal, NOT mode cycling — the agent's
  // approval mode must not silently change out from under the user.
  await expect(page.getByTestId('mode-pill')).toHaveText('Auto');
});

test('Cmd+Shift+R retries the last turn, and is a no-op with nothing to retry', async ({ page }) => {
  await page.goto(harnessURL());
  const message = page.getByLabel('Message');

  // With no user turn yet, the retry shortcut is disabled — pressing it does nothing.
  await page.keyboard.press('Meta+Shift+R');
  await expect(page.getByTestId('message')).toHaveCount(0);

  // Send a turn and let it FINISH. The composer never locks (it stays enabled during a run so a
  // follow-up can be queued), so composer-enabled is NOT a turn-done signal — wait on the real
  // completion: the agent status returning to Idle. Retry-last-turn is gated on !isSending, so the
  // shortcut is a no-op until the turn actually completes.
  await message.fill('retry me please');
  await message.press('Enter');
  await expect(page.getByTestId('message').filter({ hasText: 'retry me please' })).toHaveCount(1);
  await expect(page.getByTestId('agent-status')).toHaveText('Idle');

  // Cmd+Shift+R re-runs the last user turn: a second identical user message appears.
  await page.keyboard.press('Meta+Shift+R');
  await expect(page.getByTestId('message').filter({ hasText: 'retry me please' })).toHaveCount(2);
});

test('Cmd+L focuses the message input from elsewhere', async ({ page }) => {
  await page.goto(harnessURL());
  const message = page.getByLabel('Message');

  // Move focus off the composer.
  await page.locator('body').click({ position: { x: 4, y: 4 } });
  await expect(message).not.toBeFocused();

  // Cmd+L jumps focus to the message input.
  await page.keyboard.press('Meta+L');
  await expect(message).toBeFocused();
});
