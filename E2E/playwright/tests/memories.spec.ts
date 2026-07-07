import { test, expect, type Page } from '@playwright/test';
import { clickSidebarTool, harnessURL } from './harness-helpers';

const projectMemoryPath = '.quillcode/memories/project.md';

const projectMemoryRow = (page: Page) => page.getByTestId('memory-item').filter({
  hasText: projectMemoryPath
});

// Scope by the memory's (edit-stable) path instead of `.first()`: the unscoped
// `getByTestId('memory-preview').first()` could transiently resolve against a re-rendering
// memory list during the async mock edit turn, flaking under parallel load.
const globalMemoryRow = (page: Page) => page.getByTestId('memory-item').filter({
  hasText: 'memories/preferences.md'
});

async function submitComposer(page: Page, value: string) {
  const message = page.getByLabel('Message');
  // Root cause of the flake: the mock harness rebuilds the composer <textarea> on every render(),
  // and this test fills OVER a draft that clicking "Edit" pre-populated. A plain fill() does
  // select-then-insert, and under parallel load a render() rebuilds the textarea between those two
  // steps — dropping the selection so the new text is APPENDED to the old draft (the two
  // /remember-edit commands get concatenated, so the wrong memory content is submitted). Setting the
  // value atomically and dispatching the input event the harness listens for avoids that race; the
  // toHaveValue guard confirms the draft is exactly `value` before we send.
  await message.evaluate((el, v) => {
    (el as HTMLTextAreaElement).value = v as string;
    el.dispatchEvent(new Event('input', { bubbles: true }));
  }, value);
  await expect(message).toHaveValue(value);
  await page.getByRole('button', { name: 'Send' }).click();
}

async function expectMemoryPane(page: Page, subtitle: string, count: number) {
  await expect(page.getByTestId('memories-pane')).toBeVisible();
  await expect(page.getByTestId('memories-subtitle')).toHaveText(subtitle);
  await expect(page.getByTestId('memory-item')).toHaveCount(count);
  await expect(page.getByTestId('memory-edit')).toHaveCount(count);
  await expect(page.getByTestId('memory-delete')).toHaveCount(count);
}

test('mock harness shows memories from sidebar and command palette', async ({ page }) => {
  await page.goto(harnessURL());

  await expect(page.getByTestId('project-memories-status')).toHaveText('2 memories');
  await clickSidebarTool(page, 'memories-button');

  await expectMemoryPane(page, '1 global memory · 1 project memory', 2);
  await expect(globalMemoryRow(page).getByTestId('memory-title')).toHaveText('Preferences');
  await expect(globalMemoryRow(page).getByTestId('memory-path')).toHaveText('memories/preferences.md');
  await expect(page.getByTestId('memories-add')).toBeVisible();

  await globalMemoryRow(page).getByTestId('memory-edit').click();
  await expect(page.getByLabel('Message')).toHaveValue(
    [
      '/remember-edit global:memories/preferences.md',
      'Prefer focused tests, small reviewable commits, and direct status updates while work is running.'
    ].join('\n')
  );
  await submitComposer(page, '/remember-edit global:memories/preferences.md\nPrefer durable memory edit tests');

  await expect(page.getByText(
    'Updated memory: Prefer Durable Memory Edit Tests. Future turns will use the revised memory.'
  )).toBeVisible();
  await expect(page.getByTestId('top-bar-title')).toHaveText('Updated memory: Prefer Durable Memory Edit Tests');
  await expect(globalMemoryRow(page).getByTestId('memory-title')).toHaveText('Prefer Durable Memory Edit Tests');
  await expect(globalMemoryRow(page).getByTestId('memory-preview')).toHaveText('Prefer durable memory edit tests');

  await projectMemoryRow(page).getByTestId('memory-edit').click();
  await expect(page.getByLabel('Message')).toHaveValue(
    [
      `/remember-edit project:${projectMemoryPath}`,
      'QuillCode should stay native Swift/SwiftUI and keep Codex parity decisions documented.'
    ].join('\n')
  );
  await submitComposer(page, `/remember-edit project:${projectMemoryPath}\nProject memory edits should stay local and reviewable`);

  await expect(page.getByText(
    'Updated memory: Project Memory Edits Should Stay Local And Reviewable. Future turns will use the revised memory.'
  )).toBeVisible();
  await expect(page.getByTestId('top-bar-title'))
    .toHaveText('Updated memory: Project Memory Edits Should Stay Local And Reviewable');
  await expect(projectMemoryRow(page).getByTestId('memory-preview'))
    .toHaveText('Project memory edits should stay local and reviewable');

  await clickSidebarTool(page, 'command-palette-button');
  await page.getByLabel('Search commands').fill('>memories');
  await page.getByTestId('command-palette-result').filter({ hasText: 'Memories' }).click();

  await expect(page.getByTestId('memories-pane')).toHaveCount(0);

  await clickSidebarTool(page, 'command-palette-button');
  await page.getByLabel('Search commands').fill('>save');
  const addMemoryResult = page.getByTestId('command-palette-result').filter({ hasText: 'Add memory' });
  await expect(addMemoryResult).toHaveCount(1);
  await addMemoryResult.click();

  await expect(page.getByLabel('Message')).toHaveValue('/remember ');
  await submitComposer(page, '/remember Prefer small reviewable commits');

  await expect(page.getByText(
    'Saved memory: Prefer Small Reviewable Commits. It will be included as background context in future turns.'
  )).toBeVisible();
  await expect(page.getByTestId('project-memories-status')).toHaveText('3 memories');
  await expect(page.getByTestId('top-bar-title')).toHaveText('Memory: Prefer Small Reviewable Commits');

  await clickSidebarTool(page, 'memories-button');
  await expectMemoryPane(page, '2 global memories · 1 project memory', 3);
  const savedMemoryRow = page.getByTestId('memory-item').filter({ hasText: 'Prefer Small Reviewable Commits' });
  await expect(savedMemoryRow.getByTestId('memory-title')).toHaveText('Prefer Small Reviewable Commits');
  await expect(savedMemoryRow.getByTestId('memory-path')).toContainText('memories/manual-');

  await savedMemoryRow.getByTestId('memory-delete').click();

  await expect(page.getByText(
    'Forgot memory: Prefer Small Reviewable Commits. It will no longer be included as background context.'
  )).toBeVisible();
  await expect(page.getByTestId('project-memories-status')).toHaveText('2 memories');
  await expect(page.getByTestId('top-bar-title')).toHaveText('Forgot memory: Prefer Small Reviewable Commits');
  await expectMemoryPane(page, '1 global memory · 1 project memory', 2);
  await expect(globalMemoryRow(page).getByTestId('memory-title')).toHaveText('Prefer Durable Memory Edit Tests');

  await projectMemoryRow(page).getByTestId('memory-delete').click();

  await expect(page.getByText(
    'Forgot memory: Project Memory Edits Should Stay Local And Reviewable. It will no longer be included as background context.'
  )).toBeVisible();
  await expect(page.getByTestId('project-memories-status')).toHaveText('1 memory');
  await expect(page.getByTestId('memories-subtitle'))
    .toHaveText('1 global memory · 0 project memories');
  await expect(page.getByTestId('memory-item')).toHaveCount(1);
  await expect(globalMemoryRow(page).getByTestId('memory-title')).toHaveText('Prefer Durable Memory Edit Tests');
  await expect(page.getByTestId('memory-delete')).toHaveCount(1);
});

test('mock harness surfaces memory conflicts with edit actions', async ({ page }) => {
  await page.goto(harnessURL());
  await clickSidebarTool(page, 'memories-button');

  await projectMemoryRow(page).getByTestId('memory-edit').click();
  await submitComposer(
    page,
    [
      `/remember-edit project:${projectMemoryPath}`,
      'Avoid focused tests, small reviewable commits, and direct status updates while work is running.'
    ].join('\n')
  );

  await expect(page.getByTestId('memories-subtitle'))
    .toHaveText('1 global memory · 1 project memory · 1 conflict');
  await expect(page.getByTestId('memory-conflict')).toBeVisible();
  await expect(page.getByTestId('memory-conflict-title'))
    .toHaveText('Memory conflict: focused tests small reviewable commits and direct status updates while work is running');
  await expect(page.getByTestId('memory-conflict-edit')).toHaveCount(2);

  await page.getByTestId('memory-conflict-edit').first().click();

  await expect(page.getByLabel('Message')).toHaveValue(
    [
      '/remember-edit global:memories/preferences.md',
      'Prefer focused tests, small reviewable commits, and direct status updates while work is running.'
    ].join('\n')
  );
});

test('mock harness redacts blocked memory attempts and offers a safe retry', async ({ page }) => {
  await page.goto(harnessURL());

  await submitComposer(page, '/remember api_key=SYNTHETIC_TEST_SECRET_DO_NOT_USE');
  await clickSidebarTool(page, 'memories-button');

  await expect(page.getByTestId('memories-subtitle'))
    .toHaveText('1 global memory · 1 project memory · 1 blocked attempt');
  await expect(page.getByTestId('memory-redaction-review')).toBeVisible();
  await expect(page.getByTestId('memory-redaction-title')).toHaveText('Memory redaction blocked');
  await expect(page.getByTestId('memory-redaction-input'))
    .toContainText('<redacted memory content>');
  await expect(page.locator('body')).not.toContainText('SYNTHETIC_TEST_SECRET_DO_NOT_USE');

  await page.getByTestId('memory-redaction-add').click();

  await expect(page.getByLabel('Message')).toHaveValue('/remember ');
});
