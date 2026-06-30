import { test, expect } from '@playwright/test';
import { harnessURL } from './harness-helpers';

test('mock harness scaffolds AGENTS.md via /init and refuses to overwrite it', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('/init');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.file.write');
  await expect(page.getByText(/Created AGENTS\.md/)).toBeVisible();

  // Running it again is non-destructive — it refuses rather than clobber the file.
  await page.getByLabel('Message').fill('/init');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByText(/AGENTS\.md already exists/)).toBeVisible();
});
