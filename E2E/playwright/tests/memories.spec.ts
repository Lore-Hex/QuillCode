import { test, expect } from '@playwright/test';
import { clickSidebarTool, harnessURL } from './harness-helpers';

test('mock harness shows memories from sidebar and command palette', async ({ page }) => {
  await page.goto(harnessURL());

  await expect(page.getByTestId('project-memories-status')).toHaveText('2 memories');
  await clickSidebarTool(page, 'memories-button');

  await expect(page.getByTestId('memories-pane')).toBeVisible();
  await expect(page.getByTestId('memories-subtitle')).toHaveText('1 global memory · 1 project memory');
  await expect(page.getByTestId('memory-item')).toHaveCount(2);
  await expect(page.getByTestId('memory-title').first()).toHaveText('Preferences');
  await expect(page.getByTestId('memory-path').first()).toHaveText('memories/preferences.md');
  await expect(page.getByTestId('memory-edit')).toHaveCount(2);
  await expect(page.getByTestId('memory-delete')).toHaveCount(2);
  await expect(page.getByTestId('memories-add')).toBeVisible();

  await page.getByTestId('memory-edit').first().click();
  await expect(page.getByLabel('Message')).toHaveValue(
    '/remember-edit global:memories/preferences.md\nPrefer focused tests, small reviewable commits, and direct status updates while work is running.'
  );
  await page.getByLabel('Message').fill('/remember-edit global:memories/preferences.md\nPrefer durable memory edit tests');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByText('Updated memory: Prefer Durable Memory Edit Tests. Future turns will use the revised memory.')).toBeVisible();
  await expect(page.getByTestId('top-bar-title')).toHaveText('Updated memory: Prefer Durable Memory Edit Tests');
  await expect(page.getByTestId('memory-title').first()).toHaveText('Prefer Durable Memory Edit Tests');
  await expect(page.getByTestId('memory-preview').first()).toHaveText('Prefer durable memory edit tests');

  await page.getByTestId('memory-item').filter({ hasText: '.quillcode/memories/project.md' }).getByTestId('memory-edit').click();
  await expect(page.getByLabel('Message')).toHaveValue(
    '/remember-edit project:.quillcode/memories/project.md\nQuillCode should stay native Swift/SwiftUI and keep Codex parity decisions documented.'
  );
  await page.getByLabel('Message').fill('/remember-edit project:.quillcode/memories/project.md\nProject memory edits should stay local and reviewable');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByText('Updated memory: Project Memory Edits Should Stay Local And Reviewable. Future turns will use the revised memory.')).toBeVisible();
  await expect(page.getByTestId('top-bar-title')).toHaveText('Updated memory: Project Memory Edits Should Stay Local And Reviewable');
  await expect(page.getByTestId('memory-item').filter({ hasText: '.quillcode/memories/project.md' }).getByTestId('memory-preview')).toHaveText(
    'Project memory edits should stay local and reviewable'
  );

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
  await expect(page.getByTestId('memory-edit')).toHaveCount(3);
  await expect(page.getByTestId('memory-delete')).toHaveCount(3);

  await page.getByTestId('memory-delete').first().click();

  await expect(page.getByText('Forgot memory: Prefer Small Reviewable Commits. It will no longer be included as background context.')).toBeVisible();
  await expect(page.getByTestId('project-memories-status')).toHaveText('2 memories');
  await expect(page.getByTestId('top-bar-title')).toHaveText('Forgot memory: Prefer Small Reviewable Commits');
  await expect(page.getByTestId('memories-subtitle')).toHaveText('1 global memory · 1 project memory');
  await expect(page.getByTestId('memory-item')).toHaveCount(2);
  await expect(page.getByTestId('memory-title').first()).toHaveText('Prefer Durable Memory Edit Tests');
  await expect(page.getByTestId('memory-edit')).toHaveCount(2);
  await expect(page.getByTestId('memory-delete')).toHaveCount(2);

  await page.getByTestId('memory-item').filter({ hasText: '.quillcode/memories/project.md' }).getByTestId('memory-delete').click();

  await expect(page.getByText('Forgot memory: Project Memory Edits Should Stay Local And Reviewable. It will no longer be included as background context.')).toBeVisible();
  await expect(page.getByTestId('project-memories-status')).toHaveText('1 memory');
  await expect(page.getByTestId('memories-subtitle')).toHaveText('1 global memory · 0 project memories');
  await expect(page.getByTestId('memory-item')).toHaveCount(1);
  await expect(page.getByTestId('memory-title').first()).toHaveText('Prefer Durable Memory Edit Tests');
  await expect(page.getByTestId('memory-delete')).toHaveCount(1);
});
