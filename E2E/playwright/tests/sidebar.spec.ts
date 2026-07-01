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
