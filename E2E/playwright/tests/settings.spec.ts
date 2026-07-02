import { test, expect } from '@playwright/test';
import { harnessURL, openSettings } from './harness-helpers';

test('mock harness shows actionable Computer Use setup in settings', async ({ page }) => {
  await page.goto(harnessURL());

  await openSettings(page);
  const settingsPanel = page.getByTestId('settings-panel');
  await expect(settingsPanel).toBeVisible();
  await expect(settingsPanel.getByTestId('computer-use-settings')).toBeVisible();
  await expect(settingsPanel.getByTestId('computer-use-settings-status')).toHaveText('Setup needed');
  await expect(settingsPanel.getByTestId('computer-use-permission')).toHaveCount(2);
  await expect(settingsPanel.getByTestId('computer-use-permission').nth(0)).toContainText('Screen Recording');
  await expect(settingsPanel.getByTestId('computer-use-permission').nth(1)).toContainText('Accessibility');

  await settingsPanel.getByTestId('computer-use-permission-open').first().click();
  await expect(settingsPanel.getByTestId('computer-use-last-opened')).toContainText('Privacy_ScreenCapture');

  await settingsPanel.getByTestId('computer-use-refresh').click();
  await expect(page.getByTestId('computer-use-status')).toHaveText('Needs Screen Recording + Accessibility');
});

test('mock harness edits Computer Use approved apps in settings', async ({ page }) => {
  await page.goto(harnessURL());

  await openSettings(page);
  let settingsPanel = page.getByTestId('settings-panel');
  await expect(settingsPanel.getByTestId('computer-use-approval-settings')).toBeVisible();
  await expect(settingsPanel.getByTestId('computer-use-approval-status')).toHaveText('Unrestricted');
  await expect(settingsPanel.getByTestId('computer-use-approval-summary')).toContainText('may operate whichever app');

  await settingsPanel.getByTestId('computer-use-approved-bundles').fill(
    ' com.apple.Terminal, com.apple.Terminal\ncom.google.Chrome '
  );
  await settingsPanel.getByTestId('computer-use-approved-app-names').fill(' Terminal,\nterminal\nGoogle Chrome ');
  await settingsPanel.getByTestId('settings-save').click();
  await expect(settingsPanel).toBeHidden();

  await openSettings(page);
  settingsPanel = page.getByTestId('settings-panel');
  await expect(settingsPanel.getByTestId('computer-use-approval-status')).toHaveText('4 approved');
  await expect(settingsPanel.getByTestId('computer-use-approval-summary')).toContainText(
    '2 bundle IDs and 2 app names'
  );
  await expect(settingsPanel.getByTestId('computer-use-approved-bundles')).toHaveValue(
    'com.apple.Terminal\ncom.google.Chrome'
  );
  await expect(settingsPanel.getByTestId('computer-use-approved-app-names')).toHaveValue(
    'Terminal\nGoogle Chrome'
  );

  await settingsPanel.getByTestId('computer-use-approvals-reset').click();
  await expect(settingsPanel.getByTestId('computer-use-approval-status')).toHaveText('Unrestricted');
  await expect(settingsPanel.getByTestId('computer-use-approved-bundles')).toHaveValue('');
  await expect(settingsPanel.getByTestId('computer-use-approved-app-names')).toHaveValue('');
});

test('mock harness shows actionable TrustedRouter runtime issue', async ({ page }) => {
  await page.goto(harnessURL());

  await openSettings(page);
  await expect(page.getByTestId('settings-panel')).toBeVisible();
  await page.getByTestId('settings-save').click();

  await expect(page.getByTestId('settings-panel')).toBeHidden();
  await expect(page.getByTestId('runtime-issue-pill')).toHaveText('TrustedRouter sign-in needed');
  await expect(page.getByTestId('runtime-issue')).toBeVisible();
  await expect(page.getByTestId('runtime-issue-title')).toHaveText('TrustedRouter sign-in needed');
  await expect(page.getByTestId('runtime-issue-message')).toContainText('Sign in with TrustedRouter');
  await expect(page.getByTestId('runtime-issue-action')).toHaveText('Open Settings');

  await page.getByTestId('runtime-issue-action').click();
  const settingsPanel = page.getByTestId('settings-panel');
  await expect(settingsPanel.getByTestId('runtime-issue')).toBeVisible();
  await expect(settingsPanel.getByTestId('runtime-issue-title')).toHaveText('TrustedRouter sign-in needed');
});

test('mock harness retries the last user turn from a runtime issue', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('trigger network failure');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('runtime-issue')).toBeVisible();
  await expect(page.getByTestId('runtime-issue-title')).toHaveText('TrustedRouter network issue');
  await expect(page.getByTestId('runtime-issue-action')).toHaveText('Retry');

  await page.getByTestId('runtime-issue-action').click();

  await expect(page.getByTestId('runtime-issue')).toHaveCount(0);
  await expect(page.getByText('Retry completed after reconnecting to TrustedRouter.')).toBeVisible();
  await expect(page.getByTestId('tool-card-title')).toHaveText('host.shell.run');
  await expect(page.getByTestId('tool-card-input')).toContainText('whoami');
  await expect(page.getByTestId('message').filter({ hasText: 'trigger network failure' })).toHaveCount(2);
});

test('mock harness shows runtime diagnostics in settings', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('trigger network failure');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('runtime-issue-title')).toHaveText('TrustedRouter network issue');

  await openSettings(page);
  const settingsPanel = page.getByTestId('settings-panel');

  await expect(settingsPanel.getByTestId('runtime-diagnostics')).toBeVisible();
  await expect(settingsPanel.getByTestId('runtime-diagnostic')).toHaveCount(7);
  await expect(settingsPanel.getByTestId('runtime-diagnostic').nth(0)).toContainText('API base URL');
  await expect(settingsPanel.getByTestId('runtime-diagnostic').nth(0)).toContainText('https://api.trustedrouter.com/v1');
  await expect(settingsPanel.getByTestId('runtime-diagnostic').nth(1)).toContainText('TrustedRouter login');
  await expect(settingsPanel.getByTestId('runtime-diagnostic').nth(2)).toContainText('Missing');
  await expect(settingsPanel.getByTestId('runtime-diagnostic').nth(3)).toContainText('trustedrouter/fast');
  await expect(settingsPanel.getByTestId('runtime-diagnostic').nth(4)).toContainText('trustedrouter');
  await expect(settingsPanel.getByTestId('runtime-diagnostic').nth(5)).toContainText('Failed');
  await expect(settingsPanel.getByTestId('runtime-diagnostic').nth(6)).toContainText('Bearer ...redacted');
  await expect(settingsPanel).not.toContainText('secretDiagnosticToken');
});

test('mock harness opens model picker from malformed model issue', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('trigger malformed model action');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('runtime-issue')).toBeVisible();
  await expect(page.getByTestId('runtime-issue-title')).toHaveText('Model response was malformed');
  await expect(page.getByTestId('runtime-issue-message')).toContainText('Try Nike 1.0');
  await expect(page.getByTestId('runtime-issue-action')).toHaveText('Switch model');

  await page.getByTestId('runtime-issue-action').click();

  await expect(page.getByTestId('model-browser')).toBeVisible();
  await expect(page.getByTestId('model-search')).toBeFocused();
  await page.getByTestId('model-search').fill('synth');
  await expect(page.getByTestId('model-option')).toHaveCount(2);
  await expect(page.getByTestId('model-option').nth(0)).toContainText('Synth');
  await expect(page.getByTestId('model-option').nth(1)).toContainText('Synth Code');
});

test('mock harness surfaces rate limits with model-switch recovery and diagnostics', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('trigger rate limit');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('runtime-issue')).toBeVisible();
  await expect(page.getByTestId('runtime-issue')).toHaveAttribute('data-severity', 'warning');
  await expect(page.getByTestId('runtime-issue-title')).toHaveText('TrustedRouter rate limit reached');
  await expect(page.getByTestId('runtime-issue-message')).toContainText('switch models');
  await expect(page.getByTestId('runtime-issue-action')).toHaveText('Switch model');

  await page.getByTestId('runtime-issue-action').click();
  await expect(page.getByTestId('model-browser')).toBeVisible();
  await expect(page.getByTestId('model-search')).toBeFocused();

  await openSettings(page);
  const settingsPanel = page.getByTestId('settings-panel');
  await expect(settingsPanel.getByTestId('runtime-diagnostic').filter({ hasText: 'Provider status' })).toContainText('Rate limited');
  await expect(settingsPanel.getByTestId('runtime-diagnostic').filter({ hasText: 'Retry after' })).toContainText('120s');
  await expect(settingsPanel.getByTestId('runtime-diagnostic').filter({ hasText: 'Rate limit remaining' })).toContainText('0');
});

test('mock harness surfaces provider outages with model-switch recovery and diagnostics', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('trigger provider outage');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('runtime-issue')).toBeVisible();
  await expect(page.getByTestId('runtime-issue')).toHaveAttribute('data-severity', 'warning');
  await expect(page.getByTestId('runtime-issue-title')).toHaveText('TrustedRouter provider unavailable');
  await expect(page.getByTestId('runtime-issue-message')).toContainText('deepseek');
  await expect(page.getByTestId('runtime-issue-action')).toHaveText('Switch model');

  await page.getByTestId('runtime-issue-action').click();
  await expect(page.getByTestId('model-browser')).toBeVisible();
  await expect(page.getByTestId('model-search')).toBeFocused();

  await openSettings(page);
  const settingsPanel = page.getByTestId('settings-panel');
  await expect(settingsPanel.getByTestId('runtime-diagnostic').nth(4)).toContainText('Provider');
  await expect(settingsPanel.getByTestId('runtime-diagnostic').nth(4)).toContainText('deepseek');
  await expect(settingsPanel.getByTestId('runtime-diagnostic').filter({ hasText: 'Provider status' })).toContainText('Unavailable');
  await expect(settingsPanel.getByTestId('runtime-diagnostic').filter({ hasText: 'HTTP status' })).toContainText('503');
  await expect(settingsPanel.getByTestId('runtime-diagnostic').filter({ hasText: 'Request ID' })).toContainText('req_abc123');
});
