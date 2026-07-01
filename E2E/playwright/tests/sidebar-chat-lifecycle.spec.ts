import { test, expect } from '@playwright/test';
import { harnessURL } from './harness-helpers';
import {
  clickThreadAction,
  expectThreadCount,
  sendSidebarPrompt,
  sendSidebarPromptThenNewChat,
  sidebarSection
} from './sidebar-test-helpers';

test('mock harness manages chat lifecycle from the sidebar', async ({ page }) => {
  await page.goto(harnessURL());

  await sendSidebarPromptThenNewChat(page, 'run whoami');
  await sendSidebarPrompt(page, 'git diff');

  await expectThreadCount(page, 2);
  const whoamiRow = page.getByTestId('sidebar-thread-row').filter({ hasText: 'run whoami' });
  await clickThreadAction(whoamiRow, 'Pin');

  await expect(page.getByTestId('sidebar-section-title')).toContainText(['Pinned', 'Today']);
  await expect(page.getByTestId('sidebar-thread-row').first()).toContainText('run whoami');
  await expect(page.getByTestId('sidebar-thread-row').first()).toContainText('Nike 1.0');

  page.once('dialog', async dialog => {
    expect(dialog.message()).toContain('Rename chat');
    await dialog.accept('Renamed whoami');
  });
  await clickThreadAction(page.getByTestId('sidebar-thread-row').first(), 'Rename');
  await expect(page.getByTestId('sidebar-thread-row').first()).toContainText('Renamed whoami');

  await clickThreadAction(page.getByTestId('sidebar-thread-row').first(), 'Duplicate');
  await expect(page.getByTestId('top-bar-title')).toHaveText('Copy: Renamed whoami');
  const copiedRow = page.getByTestId('sidebar-thread-row').filter({ hasText: 'Copy: Renamed whoami' });
  await expect(copiedRow).toBeVisible();
  await expectThreadCount(page, 3);

  await clickThreadAction(copiedRow, 'Archive');

  await expect(page.getByTestId('sidebar-section-title')).toContainText(['Pinned', 'Today', 'Archived']);
  await expectThreadCount(page, 3);
  await expect(page.getByTestId('sidebar-thread-row').last()).toContainText('Copy: Renamed whoami');
  await expect(page.getByTestId('top-bar-title')).toHaveText('Renamed whoami');

  await clickThreadAction(page.getByTestId('sidebar-thread-row').last(), 'Unarchive');
  await expect(page.getByTestId('top-bar-title')).toHaveText('Copy: Renamed whoami');
  await expect(page.getByTestId('sidebar-section-title')).toContainText(['Pinned', 'Today']);

  await clickThreadAction(page.getByTestId('sidebar-thread-row').filter({ hasText: 'Copy: Renamed whoami' }), 'Delete');
  await expectThreadCount(page, 2);
  await expect(page.getByTestId('sidebar')).not.toContainText('Copy: Renamed whoami');
});

test('mock harness groups sidebar chats by recency bucket', async ({ page }) => {
  await page.goto(harnessURL());

  await page.evaluate(() => {
    const harness = window as unknown as {
      sendMessage: (value: string) => void;
      newChat: () => void;
      setSidebarItemUpdatedAt: (title: string, updatedAt: string) => void;
    };
    const localNoonDaysAgo = (days: number) => {
      const date = new Date();
      date.setHours(12, 0, 0, 0);
      date.setDate(date.getDate() - days);
      return date.toISOString();
    };

    harness.sendMessage('today chat');
    harness.setSidebarItemUpdatedAt('today chat', localNoonDaysAgo(0));
    harness.newChat();
    harness.sendMessage('yesterday chat');
    harness.setSidebarItemUpdatedAt('yesterday chat', localNoonDaysAgo(1));
    harness.newChat();
    harness.sendMessage('earlier week chat');
    harness.setSidebarItemUpdatedAt('earlier week chat', localNoonDaysAgo(3));
    harness.newChat();
    harness.sendMessage('older chat');
    harness.setSidebarItemUpdatedAt('older chat', localNoonDaysAgo(14));
  });

  await expect(page.getByTestId('sidebar-section-title')).toContainText([
    'Today',
    'Yesterday',
    'Previous 7 days',
    'Older'
  ]);
  await expect(sidebarSection(page, 'Today').getByTestId('sidebar-thread-row')).toContainText('today chat');
  await expect(sidebarSection(page, 'Yesterday').getByTestId('sidebar-thread-row')).toContainText('yesterday chat');
  await expect(sidebarSection(page, 'Previous 7 days').getByTestId('sidebar-thread-row'))
    .toContainText('earlier week chat');
  await expect(sidebarSection(page, 'Older').getByTestId('sidebar-thread-row')).toContainText('older chat');
});

test('mock harness bulk-selects chats from the sidebar', async ({ page }) => {
  await page.goto(harnessURL());

  for (const prompt of ['run whoami', 'git diff', 'review tests']) {
    await sendSidebarPromptThenNewChat(page, prompt);
  }

  await expectThreadCount(page, 3);
  await page.getByTestId('sidebar-bulk-action').filter({ hasText: /^Select$/ }).click();
  await expect(page.getByTestId('sidebar-selection')).toHaveAttribute('data-active', 'true');

  await page.getByTestId('sidebar-thread-row').nth(0).getByTestId('sidebar-select-toggle').click();
  await page.getByTestId('sidebar-thread-row').nth(1).getByTestId('sidebar-select-toggle').click();
  await expect(page.getByTestId('sidebar-selection-label')).toHaveText('2 chats selected');

  await page.getByTestId('sidebar-bulk-action').filter({ hasText: /^Archive$/ }).click();
  await expect(page.getByTestId('sidebar-selection')).toHaveCount(0);
  await expect(sidebarSection(page, 'Archived').getByTestId('sidebar-thread-row')).toHaveCount(2);
  await expect(sidebarSection(page, 'Today').getByTestId('sidebar-thread-row')).toHaveCount(1);

  await page.getByTestId('sidebar-bulk-action').filter({ hasText: /^Select$/ }).click();
  await page.getByTestId('sidebar-bulk-action').filter({ hasText: 'Select all' }).click();
  await expect(page.getByTestId('sidebar-selection-label')).toHaveText('3 chats selected');
  await page.getByTestId('sidebar-bulk-action').filter({ hasText: /^Delete$/ }).click();

  await expectThreadCount(page, 0);
  await expect(page.getByTestId('sidebar-title-row')).toHaveCount(0);
  await expect(page.getByTestId('sidebar-empty')).toHaveText('No chats yet');
});
