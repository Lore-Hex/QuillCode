import { test, expect } from '@playwright/test';
import { harnessURL } from './harness-helpers';

test('detached managed task creates a branch from the task header', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('/new-worktree');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('top-bar-worktree')).toHaveText('Worktree');
  const createBranch = page.getByTestId('top-bar-create-branch-here');
  await expect(createBranch).toBeVisible();
  await createBranch.click();

  const panel = page.getByTestId('worktree-create-branch-panel');
  await expect(panel).toBeVisible();
  await expect(page.getByTestId('worktree-create-branch-input')).toBeFocused();
  await expect(page.getByTestId('worktree-create-branch-submit')).toBeDisabled();

  await page.getByLabel('Branch name').fill('feature/managed-task');
  await expect(page.getByTestId('worktree-create-branch-submit')).toBeEnabled();
  await page.getByTestId('worktree-create-branch-submit').click();

  await expect(panel).toHaveCount(0);
  await expect(page.getByTestId('top-bar-worktree')).toHaveText('Worktree feature/managed-task');
  await expect(page.getByTestId('top-bar-create-branch-here')).toHaveCount(0);
  await expect(page.getByTestId('sidebar-worktree-branch')).toContainText('managed-task');
  await expect(page.getByTestId('sidebar-worktree-branch')).toHaveAttribute('title', 'feature/managed-task');
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.worktree.branch.create');
  await expect(page.getByTestId('tool-card-input').last()).toContainText('feature/managed-task');
});

test('create branch here keeps validation failures in the dialog', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('/new-worktree');
  await page.getByRole('button', { name: 'Send' }).click();
  await page.getByTestId('top-bar-create-branch-here').click();
  await page.getByLabel('Branch name').fill('--invalid branch');
  await page.getByTestId('worktree-create-branch-submit').click();

  await expect(page.getByTestId('worktree-create-branch-panel')).toBeVisible();
  await expect(page.getByTestId('worktree-create-branch-error'))
    .toContainText('unsupported characters');
  await expect(page.getByTestId('top-bar-create-branch-here')).toBeVisible();
});
