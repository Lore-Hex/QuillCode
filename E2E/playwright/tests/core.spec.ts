import { test, expect } from '@playwright/test';
import {
  clickSidebarTool,
  openSidebarTools,
  openTopBarOverflow
} from './harness-helpers';

function expectPresent<T>(value: T | null, label: string): T {
  expect(value, label).not.toBeNull();
  return value as T;
}

test('mock harness executes simple command flow', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');
  await expect(page.getByTestId('workspace')).toBeVisible();
  await expect(page.getByTestId('top-bar')).toBeVisible();
  await expect(page.getByTestId('sidebar')).toBeVisible();
  await expect(page.getByTestId('project-item')).toContainText('QuillCode');
  await expect(page.getByTestId('project-item')).toHaveAttribute('aria-current', 'true');
  await expect(page.getByTestId('transcript-empty')).toBeVisible();
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
  const modelButtonBox = await page.getByTestId('model-picker-button').boundingBox();
  const modeButtonBox = await page.getByTestId('mode-picker-button').boundingBox();
  const modelButtonBounds = expectPresent(modelButtonBox, 'model picker button should have bounds');
  const modeButtonBounds = expectPresent(modeButtonBox, 'mode picker button should have bounds');
  expect(modeButtonBounds.x - (modelButtonBounds.x + modelButtonBounds.width)).toBeGreaterThanOrEqual(8);
  await page.getByTestId('model-picker-button').click();
  await expect(page.getByTestId('model-category')).toHaveCount(2);
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
  await page.getByTestId('model-option').click();
  await expect(page.getByTestId('model-picker-button')).toHaveText('z-ai/GLM 5.2');
  await expect(page.getByTestId('mode-pill')).toHaveText('Auto');

  await page.getByLabel('Message').fill('run whoami');
  await expect(page.getByTestId('send-button')).toBeEnabled();
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('sidebar-item')).toContainText('run whoami');
  await expect(page.getByTestId('sidebar-item')).toContainText('z-ai/GLM 5.2');
  await expect(page.getByTestId('top-bar-title')).toHaveText('run whoami');
  await expect(page.getByTestId('top-bar-subtitle')).toContainText('QuillCode - Auto');
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
  await expect(page.getByTestId('message-feedback-up')).toHaveCount(1);
  await expect(page.getByTestId('message-feedback-down')).toHaveCount(1);
  await page.getByTestId('message-feedback-up').click();
  await expect(page.getByTestId('message-feedback-up')).toHaveAttribute('data-selected', 'true');
  await expect(page.getByTestId('message-feedback-down')).toHaveAttribute('data-selected', 'false');
  await page.getByTestId('message-feedback-down').click();
  await expect(page.getByTestId('message-feedback-up')).toHaveAttribute('data-selected', 'false');
  await expect(page.getByTestId('message-feedback-down')).toHaveAttribute('data-selected', 'true');

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

test('mock harness exposes actionable approval buttons on review cards', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await page.evaluate(() => {
    const harness = window as typeof window & {
      addToolCard: (card: Record<string, unknown>) => void;
      render: () => void;
    };
    harness.addToolCard({
      id: 'shell-review',
      title: 'host.shell.run',
      subtitle: 'Ready to run · whoami',
      status: 'review',
      reviewState: 'ready',
      density: 'expanded',
      inputJSON: JSON.stringify({ cmd: 'whoami' }, null, 2),
      isExpanded: true,
      actions: [
        {
          id: 'tool-card-action-approve-approval-1',
          title: 'Run',
          kind: 'approve',
          requestID: 'approval-1',
          style: 'primary'
        },
        {
          id: 'tool-card-action-deny-approval-1',
          title: 'Skip',
          kind: 'deny',
          requestID: 'approval-1',
          style: 'secondary'
        }
      ]
    });
    harness.render();
  });

  await expect(page.getByTestId('tool-card')).toHaveCount(1);
  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-status', 'review');
  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-review-state', 'ready');
  await expect(page.getByTestId('tool-card-status')).toHaveText('Ready');
  await expect(page.getByTestId('tool-card-actions')).toBeVisible();
  await expect(page.getByTestId('tool-card-action').filter({ hasText: 'Run' })).toBeVisible();
  await expect(page.getByTestId('tool-card-action').filter({ hasText: 'Skip' })).toBeVisible();
  const runBox = await page.getByTestId('tool-card-action').filter({ hasText: 'Run' }).boundingBox();
  const skipBox = await page.getByTestId('tool-card-action').filter({ hasText: 'Skip' }).boundingBox();
  const runBounds = expectPresent(runBox, 'run approval action should have bounds');
  const skipBounds = expectPresent(skipBox, 'skip approval action should have bounds');
  expect(runBounds.width).toBeGreaterThan(skipBounds.width);

  await page.getByTestId('tool-card-action').filter({ hasText: 'Run' }).click();

  await expect(page.getByTestId('tool-card')).toHaveCount(2);
  await expect(page.getByTestId('tool-card').first()).toHaveAttribute('data-status', 'done');
  await expect(page.getByTestId('tool-card-subtitle').first()).toHaveText('Approved · whoami');
  await expect(page.getByTestId('tool-card-actions')).toHaveCount(0);
  await expect(page.getByTestId('tool-card').nth(1)).toHaveAttribute('data-status', 'done');
  await expect(page.getByTestId('tool-card-output').last()).toContainText('mock-user');
  await expect(page.getByTestId('message').last()).toContainText('Approved and ran the tool.');
});

test('mock harness shows denied review cards as needs review without actions', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await page.evaluate(() => {
    const harness = window as typeof window & {
      addToolCard: (card: Record<string, unknown>) => void;
      render: () => void;
    };
    harness.addToolCard({
      id: 'shell-blocked-review',
      title: 'host.shell.run',
      subtitle: 'Blocked · rm -rf /',
      status: 'review',
      reviewState: 'needsReview',
      density: 'expanded',
      inputJSON: JSON.stringify({ cmd: 'rm -rf /' }, null, 2),
      isExpanded: true,
      actions: []
    });
    harness.render();
  });

  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-status', 'review');
  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-review-state', 'needsReview');
  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-status-label', 'Needs review');
  await expect(page.getByTestId('tool-card-status')).toHaveText('Needs review');
  await expect(page.getByTestId('tool-card-action')).toHaveCount(0);
});

test('mock harness preserves transcript scroll intent as new events append', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await page.evaluate(() => {
    const harness = window as unknown as { sendMessage: (value: string) => void };
    for (let index = 0; index < 24; index += 1) {
      harness.sendMessage(`run whoami ${index}`);
    }
  });

  const timeline = page.getByTestId('timeline');
  await expect(timeline).toBeVisible();
  const scrollable = await page.evaluate(() => document.documentElement.scrollHeight > window.innerHeight);
  expect(scrollable).toBe(true);

  const midScroll = await page.evaluate(() => {
    const nextScrollY = Math.floor((document.documentElement.scrollHeight - window.innerHeight) / 2);
    window.scrollTo(0, nextScrollY);
    return window.scrollY;
  });
  await page.evaluate(() => {
    const harness = window as unknown as { sendMessage: (value: string) => void };
    harness.sendMessage('run whoami while reading history');
  });
  const afterMidAppend = await page.evaluate(() => window.scrollY);
  expect(Math.abs(afterMidAppend - midScroll)).toBeLessThanOrEqual(1);

  await page.evaluate(() => {
    window.scrollTo(0, document.documentElement.scrollHeight);
  });
  await page.evaluate(() => {
    const harness = window as unknown as { sendMessage: (value: string) => void };
    harness.sendMessage('run whoami at bottom');
  });
  const bottomDistance = await page.evaluate(() =>
    Math.max(0, document.documentElement.scrollHeight - window.innerHeight - window.scrollY)
  );
  expect(bottomDistance).toBeLessThanOrEqual(1);
});

test('mock harness shows model-authored task plan in Activity', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await page.getByLabel('Message').fill('plan the QuillCode work');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.plan.update');
  await expect(page.getByText('Updated the task plan.')).toBeVisible();

  await clickSidebarTool(page, 'activity-button');
  await expect(page.getByTestId('activity-pane')).toBeVisible();
  await expect(page.getByTestId('activity-plan')).toHaveCount(3);
  await expect(page.getByTestId('activity-plan').nth(0)).toContainText('Inspect current state');
  await expect(page.getByTestId('activity-plan').nth(0)).toContainText('Done');
  await expect(page.getByTestId('activity-plan').nth(1)).toContainText('Implement requested change');
  await expect(page.getByTestId('activity-plan').nth(1)).toContainText('Running');
  await expect(page.getByTestId('activity-plan').nth(1)).toContainText('Keep the slice reviewable.');
  await expect(page.getByTestId('activity-plan').nth(2)).toContainText('Validate and summarize');
  await expect(page.getByTestId('activity-plan').nth(2)).toContainText('Pending');
  await expect(page.getByTestId('activity-plan-section')).toContainText('3 items');
});

test('mock harness shows context pressure banner and compacts or forks from latest turn', async ({ page }) => {
  test.setTimeout(60000);
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  const longPrompt = 'long context ' + 'word '.repeat(22000);
  await page.getByLabel('Message').fill(longPrompt);
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('context-banner')).toBeVisible();
  await expect(page.getByTestId('context-banner-title')).toContainText(/context limit/i);

  await page.getByLabel('Message').fill('run whoami');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('context-banner')).toBeVisible();

  await page.getByTestId('context-compact').click();

  await expect(page.getByTestId('top-bar-title')).toContainText('Compact:');
  await expect(page.getByTestId('context-banner')).toHaveCount(0);
  await expect(page.getByTestId('message').first()).toContainText('Context compacted from');
  await expect(page.getByTestId('message').nth(1)).toContainText('run whoami');

  await page.getByRole('textbox', { name: 'Message' }).fill('long context again ' + 'word '.repeat(22000));
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('context-banner')).toBeVisible();
  await page.getByRole('textbox', { name: 'Message' }).fill('run whoami');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('context-banner')).toBeVisible();

  await page.getByTestId('context-fork-last').click();

  await expect(page.getByTestId('top-bar-title')).toContainText('Fork:');
  await expect(page.getByTestId('context-banner')).toHaveCount(0);
  await expect(page.getByTestId('message').first()).toContainText('run whoami');
  await expect(page.getByText('You are `mock-user` in this workspace.')).toBeVisible();
});
test('mock harness shows memories from sidebar and command palette', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await expect(page.getByTestId('project-memories-status')).toHaveText('2 memories');
  await clickSidebarTool(page, 'memories-button');

  await expect(page.getByTestId('memories-pane')).toBeVisible();
  await expect(page.getByTestId('memories-subtitle')).toHaveText('1 global memory · 1 project memory');
  await expect(page.getByTestId('memory-item')).toHaveCount(2);
  await expect(page.getByTestId('memory-title').first()).toHaveText('Preferences');
  await expect(page.getByTestId('memory-path').first()).toHaveText('memories/preferences.md');
  await expect(page.getByTestId('memory-delete')).toHaveCount(1);
  await expect(page.getByTestId('memories-add')).toBeVisible();

  await clickSidebarTool(page, 'command-palette-button');
  await page.getByLabel('Search commands').fill('>memories');
  await page.getByTestId('command-palette-result').filter({ hasText: 'Memories' }).click();

  await expect(page.getByTestId('memories-pane')).toHaveCount(0);

  await clickSidebarTool(page, 'command-palette-button');
  await page.getByLabel('Search commands').fill('>save');
  await expect(page.getByTestId('command-palette-result')).toHaveCount(1);
  await expect(page.getByTestId('command-palette-result')).toContainText('Add memory');
  await page.getByTestId('command-palette-result').click();

  await expect(page.getByLabel('Message')).toHaveValue('/remember ');
  await page.getByLabel('Message').fill('/remember Prefer small reviewable commits');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByText('Saved memory: Prefer Small Reviewable Commits. It will be included as background context in future turns.')).toBeVisible();
  await expect(page.getByTestId('project-memories-status')).toHaveText('3 memories');
  await expect(page.getByTestId('top-bar-title')).toHaveText('Memory: Prefer Small Reviewable Commits');

  await clickSidebarTool(page, 'memories-button');
  await expect(page.getByTestId('memories-pane')).toBeVisible();
  await expect(page.getByTestId('memories-subtitle')).toHaveText('2 global memories · 1 project memory');
  await expect(page.getByTestId('memory-item')).toHaveCount(3);
  await expect(page.getByTestId('memory-title').first()).toHaveText('Prefer Small Reviewable Commits');
  await expect(page.getByTestId('memory-path').first()).toContainText('memories/manual-');
  await expect(page.getByTestId('memory-delete')).toHaveCount(2);

  await page.getByTestId('memory-delete').first().click();

  await expect(page.getByText('Forgot memory: Prefer Small Reviewable Commits. It will no longer be included as background context.')).toBeVisible();
  await expect(page.getByTestId('project-memories-status')).toHaveText('2 memories');
  await expect(page.getByTestId('top-bar-title')).toHaveText('Forgot memory: Prefer Small Reviewable Commits');
  await expect(page.getByTestId('memories-subtitle')).toHaveText('1 global memory · 1 project memory');
  await expect(page.getByTestId('memory-item')).toHaveCount(2);
  await expect(page.getByTestId('memory-title').first()).toHaveText('Preferences');
  await expect(page.getByTestId('memory-delete')).toHaveCount(1);
});
