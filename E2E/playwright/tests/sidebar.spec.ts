import { test, expect } from '@playwright/test';
import { clickSidebarTool, harnessURL } from './harness-helpers';
import { sendSidebarPrompt } from './sidebar-test-helpers';

test('mock harness searches and reopens an existing chat', async ({ page }) => {
  await page.goto(harnessURL());

  await sendSidebarPrompt(page, 'run whoami');
  await expect(page.getByTestId('sidebar-item')).toContainText('run whoami');

  await clickSidebarTool(page, 'sidebar-search-button');
  await expect(page.getByTestId('search-panel')).toBeVisible();
  await expect(page.getByTestId('search-input')).toBeFocused();
  await expect(page.getByTestId('search-result')).toContainText('run whoami');

  await page.keyboard.type('whoami');
  await expect(page.getByTestId('search-input')).toHaveValue('whoami');
  await expect(page.getByTestId('search-result')).toHaveCount(1);
  await expect(page.getByTestId('search-result')).toContainText('Nike 1.0');

  await page.getByTestId('search-input').fill('mock-user');
  await expect(page.getByTestId('search-input')).toHaveValue('mock-user');
  await expect(page.getByTestId('search-result')).toHaveCount(1);
  await expect(page.getByTestId('search-result')).toContainText('run whoami');

  await page.getByTestId('search-result').click();

  await expect(page.getByTestId('search-panel')).toHaveCount(0);
  await expect(page.getByTestId('top-bar-title')).toHaveText('run whoami');
  await expect(page.getByTestId('sidebar-item')).toHaveAttribute('aria-current', 'true');
});

test('mock harness starts a new chat from the sidebar action', async ({ page }) => {
  await page.goto(harnessURL());

  await sendSidebarPrompt(page, 'run whoami');
  await expect(page.getByTestId('sidebar-item')).toContainText('run whoami');

  await page.getByTestId('new-chat-button').click();

  await expect(page.getByTestId('top-bar-title')).toHaveText('QuillCode');
  await expect(page.getByTestId('top-bar-subtitle')).toContainText('Not started');
  await expect(page.getByTestId('transcript-empty')).toBeVisible();
  await expect(page.getByTestId('sidebar-item')).toHaveAttribute('aria-current', 'false');
  await expect(page.getByTestId('sidebar-item')).toContainText('run whoami');
  await expect(page.getByLabel('Message')).toHaveValue('');
});

test('background chat keeps its running indicator while another chat is selected', async ({ page }) => {
  await page.goto(harnessURL());

  await sendSidebarPrompt(page, 'run whoami');
  await expect(page.getByText('mock-user').last()).toBeVisible();
  const backgroundRow = page.getByTestId('sidebar-thread-row').filter({ hasText: 'run whoami' });
  const backgroundThreadID = await backgroundRow.getByTestId('sidebar-item').getAttribute('data-thread-id');
  if (!backgroundThreadID) {
    throw new Error('Expected the background chat row to expose its thread ID');
  }

  await page.getByTestId('new-chat-button').click();
  await sendSidebarPrompt(page, 'show current directory');
  await expect(page.getByTestId('sidebar-thread-row')).toHaveCount(2);
  const selectedRow = page.getByTestId('sidebar-thread-row').filter({ hasText: 'show current directory' });
  await expect(selectedRow.getByTestId('sidebar-item')).toHaveAttribute('aria-current', 'true');

  await page.evaluate(threadID => {
    const harness = window as unknown as {
      __quillCodeTestSetThreadRunStatus: (id: string, status: string | null) => void
    };
    harness.__quillCodeTestSetThreadRunStatus(threadID, 'Running tests');
  }, backgroundThreadID);

  await expect(backgroundRow.getByTestId('sidebar-item')).toHaveAttribute('data-run-status', 'Running tests');
  await expect(backgroundRow.getByTestId('sidebar-run-status')).toHaveAttribute('title', 'Running tests');
  await backgroundRow.getByLabel(/^Actions for /).click();
  await expect(backgroundRow.getByTestId('sidebar-thread-action').filter({ hasText: /^Duplicate$/ })).toHaveCount(0);
  await expect(backgroundRow.getByTestId('sidebar-thread-action').filter({ hasText: /^Delete$/ })).toHaveCount(0);
  await expect(selectedRow.getByTestId('sidebar-run-status')).toHaveCount(0);
  await expect(selectedRow.getByTestId('sidebar-item')).toHaveAttribute('aria-current', 'true');
});
