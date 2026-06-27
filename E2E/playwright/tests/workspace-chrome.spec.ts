import { test, expect } from '@playwright/test';
import {
  harnessURL,
  openTopBarOverflow
} from './harness-helpers';

test('mock harness opens utilities from the top-bar overflow', async ({ page }) => {
  await page.goto(harnessURL());

  await openTopBarOverflow(page);
  await page.getByTestId('top-bar-overflow-keyboard-shortcuts').click();
  await expect(page.getByTestId('keyboard-shortcuts-panel')).toBeVisible();
  await page.getByTestId('keyboard-shortcuts-close').click();

  await openTopBarOverflow(page);
  await page.getByTestId('top-bar-overflow-search').click();
  await expect(page.getByTestId('search-panel')).toBeVisible();
  await expect(page.getByTestId('search-input')).toBeFocused();
  await page.keyboard.type('Nike');
  await expect(page.getByTestId('search-input')).toHaveValue('Nike');
  await page.getByTestId('search-close').click();

  await openTopBarOverflow(page);
  await page.getByTestId('top-bar-overflow-command-palette').click();
  await expect(page.getByTestId('command-palette-panel')).toBeVisible();
  await expect(page.getByTestId('command-palette-input')).toBeFocused();
  await page.keyboard.type('>search');
  await expect(page.getByTestId('command-palette-input')).toHaveValue('>search');
  await page.getByTestId('command-palette-close').click();

  await openTopBarOverflow(page);
  await expect(page.getByTestId('top-bar-overflow-stop-all')).toHaveCount(0);
  await expect(page.getByTestId('top-bar-stop-button')).toHaveCount(0);
});

test('mock harness opens Computer Use setup from the top-bar overflow', async ({ page }) => {
  await page.goto(harnessURL());

  await openTopBarOverflow(page);
  await page.getByTestId('top-bar-overflow-computer-use').click();

  const settingsPanel = page.getByTestId('settings-panel');
  await expect(settingsPanel).toBeVisible();
  await expect(settingsPanel.getByTestId('computer-use-settings')).toBeVisible();
  await expect(settingsPanel.getByTestId('computer-use-settings-status')).toHaveText('Setup needed');
  await expect(settingsPanel.getByTestId('computer-use-next-action')).toContainText('Open Screen Recording first');

  await settingsPanel.getByTestId('computer-use-permission-open').first().click();
  await expect(settingsPanel.getByTestId('computer-use-last-opened')).toContainText('Privacy_ScreenCapture');
});

test('mock harness disconnects remote project connections from the top-bar overflow', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('/ssh quill@feather.local:/srv/quill');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('top-bar-subtitle')).toContainText('feather.local · quill');

  await openTopBarOverflow(page);
  await expect(page.getByTestId('top-bar-overflow-disconnect-all')).toBeVisible();
  await page.getByTestId('top-bar-overflow-disconnect-all').click();

  await expect(page.getByTestId('top-bar-subtitle')).toContainText('No project');
  await openTopBarOverflow(page);
  await expect(page.getByTestId('top-bar-overflow-disconnect-all')).toHaveCount(0);
});
