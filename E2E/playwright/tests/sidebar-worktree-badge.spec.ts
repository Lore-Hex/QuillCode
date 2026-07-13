import { test, expect } from '@playwright/test';
import { harnessURL } from './harness-helpers';

test('mock harness shows a detached chip on a managed worktree thread row', async ({ page }) => {
  await page.goto(harnessURL());

  // A plain thread has no worktree chip.
  await page.getByLabel('Message').fill('run whoami');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('sidebar-item').first()).toBeVisible();
  await expect(page.getByTestId('sidebar-worktree-branch')).toHaveCount(0);

  // Managed worktree tasks start detached, avoiding repository branch pollution.
  await page.getByLabel('Message').fill('/new-worktree');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('worktree-new-task-panel')).toBeVisible();
  await page.getByTestId('worktree-new-task-submit').click();

  const chip = page.getByTestId('sidebar-worktree-branch');
  await expect(chip).toBeVisible();
  await expect(chip).toContainText('Detached');
  await expect(chip).toHaveAttribute('title', '');
  // No dangling warning for a resolvable binding.
  await expect(page.getByTestId('sidebar-worktree-warning')).toHaveCount(0);
});
