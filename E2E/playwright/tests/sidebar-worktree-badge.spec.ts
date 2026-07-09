import { test, expect } from '@playwright/test';
import { harnessURL } from './harness-helpers';

test('mock harness shows a worktree branch chip on the bound thread row', async ({ page }) => {
  await page.goto(harnessURL());

  // A plain thread has no worktree chip.
  await page.getByLabel('Message').fill('run whoami');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('sidebar-item').first()).toBeVisible();
  await expect(page.getByTestId('sidebar-worktree-branch')).toHaveCount(0);

  // Starting a worktree thread binds it to a branch → the row shows a monospace branch chip.
  await page.getByLabel('Message').fill('/new-worktree');
  await page.getByRole('button', { name: 'Send' }).click();

  const chip = page.getByTestId('sidebar-worktree-branch');
  await expect(chip).toBeVisible();
  await expect(chip).toContainText('experiment');
  await expect(chip).toHaveAttribute('title', 'quill/experiment');
  // No dangling warning for a resolvable binding.
  await expect(page.getByTestId('sidebar-worktree-warning')).toHaveCount(0);
});
