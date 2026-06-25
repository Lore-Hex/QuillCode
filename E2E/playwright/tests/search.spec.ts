import { test, expect, type Page } from '@playwright/test';
import { harnessURL } from './harness-helpers';

async function openTopBarOverflow(page: Page) {
  await page.getByTestId('top-bar-overflow-button').click();
  await expect(page.getByTestId('top-bar-overflow-menu')).toHaveAttribute('open', '');
}

test('mock harness keeps chat search typeable from sidebar and top bar entry points', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('run whoami');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('sidebar-item')).toContainText('run whoami');

  await page.getByTestId('sidebar-search-button').click();
  await expect(page.getByTestId('search-panel')).toBeVisible();
  await expect(page.getByTestId('search-input')).toBeFocused();
  await page.keyboard.type('whoami');
  await expect(page.getByTestId('search-input')).toHaveValue('whoami');
  await expect(page.getByTestId('search-result')).toContainText('run whoami');
  await page.getByTestId('search-close').click();

  await openTopBarOverflow(page);
  await page.getByTestId('top-bar-overflow-search').click();
  await expect(page.getByTestId('search-panel')).toBeVisible();
  await expect(page.getByTestId('search-input')).toBeFocused();
  await page.keyboard.type('mock-user');
  await expect(page.getByTestId('search-input')).toHaveValue('mock-user');
  await expect(page.getByTestId('search-result')).toContainText('run whoami');
});

test('mock harness keeps command palette search typeable from top bar entry point', async ({ page }) => {
  await page.goto(harnessURL());

  await openTopBarOverflow(page);
  await page.getByTestId('top-bar-overflow-command-palette').click();
  await expect(page.getByTestId('command-palette-panel')).toBeVisible();
  await expect(page.getByTestId('command-palette-input')).toBeFocused();

  await page.keyboard.type('>terminal');

  await expect(page.getByTestId('command-palette-input')).toHaveValue('>terminal');
  await expect(page.getByTestId('command-palette-result').first()).toContainText('Terminal');
});
