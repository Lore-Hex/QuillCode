import { test, expect } from '@playwright/test';

test('mock harness executes simple command flow', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');
  await expect(page.getByTestId('workspace')).toBeVisible();
  await expect(page.getByTestId('top-bar')).toBeVisible();
  await expect(page.getByTestId('sidebar')).toBeVisible();
  await expect(page.getByTestId('project-item')).toContainText('QuillCode');
  await expect(page.getByTestId('project-item')).toHaveAttribute('aria-current', 'true');
  await expect(page.getByTestId('transcript-empty')).toBeVisible();
  await expect(page.getByTestId('model-category')).toHaveCount(2);
  await expect(page.getByLabel('Model')).toHaveValue('trustedrouter/fusion');
  await expect(page.getByTestId('model-pill')).toHaveText('trustedrouter/fusion');
  await expect(page.getByTestId('mode-pill')).toHaveText('Auto');
  await expect(page.getByTestId('send-button')).toBeDisabled();

  await page.getByTestId('settings-button').click();
  await expect(page.getByTestId('settings-panel')).toBeVisible();
  await expect(page.getByTestId('settings-key-status')).toHaveText('No API key saved');
  await page.getByLabel('TrustedRouter API base URL').fill('https://api.trustedrouter.test/v1');
  await page.getByLabel('Enable developer override').check();
  await page.getByLabel('Replace API key').fill('sk-tr-v1-test');
  await page.getByTestId('settings-save').click();
  await expect(page.getByTestId('settings-panel')).toBeHidden();
  await expect(page.getByTestId('agent-status')).toHaveText('TrustedRouter ready');

  await page.getByLabel('Model').selectOption('z-ai/glm-5.2');
  await expect(page.getByTestId('model-pill')).toHaveText('z-ai/glm-5.2');

  await page.getByLabel('Message').fill('run whoami');
  await expect(page.getByTestId('send-button')).toBeEnabled();
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('sidebar-item')).toContainText('run whoami');
  await expect(page.getByTestId('sidebar-item')).toContainText('z-ai/glm-5.2');
  await expect(page.getByTestId('top-bar-title')).toHaveText('run whoami');
  await expect(page.getByTestId('top-bar-subtitle')).toContainText('QuillCode - Auto');
  await expect(page.getByTestId('tool-card-title')).toHaveText('host.shell.run');
  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-status', 'done');
  await expect(page.getByTestId('tool-card-input')).toContainText('whoami');
  await expect(page.getByTestId('tool-card-output')).toContainText('mock-user');
  await expect(page.getByText('Output:\\nmock-user')).toBeVisible();
});

test('mock harness shows git review summary for diff flow', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await page.getByLabel('Message').fill('git diff');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('review-pane')).toBeVisible();
  await expect(page.getByTestId('review-summary')).toHaveText('1 file changed, +1 -0');
  await expect(page.getByTestId('review-file')).toContainText('Sources/App.swift');
  await expect(page.getByTestId('tool-card-title')).toHaveText('host.git.diff');
  await expect(page.getByTestId('tool-card-output')).toContainText('diff --git');
});
