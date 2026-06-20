import { test, expect } from '@playwright/test';

test('mock harness executes simple command flow', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');
  await expect(page.getByText('QuillCode')).toBeVisible();
  await page.getByLabel('Message').fill('run whoami');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByText('host.shell.run queued')).toBeVisible();
  await expect(page.getByText('Output:')).toBeVisible();
});

