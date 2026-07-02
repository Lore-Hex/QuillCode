import { test, expect } from '@playwright/test';
import { harnessURL } from './harness-helpers';

test('mock harness dispatches workspace keyboard shortcuts', async ({ page }) => {
  await page.goto(harnessURL());

  await page.keyboard.press('Meta+K');
  await expect(page.getByTestId('search-panel')).toBeVisible();
  await page.getByTestId('search-close').click();

  await page.keyboard.press('Meta+Shift+P');
  await expect(page.getByTestId('command-palette-panel')).toBeVisible();
  await page.getByTestId('command-palette-close').click();

  await page.keyboard.press('Meta+/');
  await expect(page.getByTestId('keyboard-shortcuts-panel')).toBeVisible();
  await expect(page.getByTestId('keyboard-shortcut-row').filter({ hasText: 'Keyboard shortcuts' })).toContainText('Cmd+/');
  await expect(page.locator('[data-testid="keyboard-shortcut-row"][data-command-id="workspace-back"]')).toContainText('Cmd+Option+←');
  await expect(page.locator('[data-testid="keyboard-shortcut-row"][data-command-id="workspace-forward"]')).toContainText('Cmd+Option+→');
  await expect(page.getByTestId('keyboard-shortcut-row').filter({ hasText: 'Browser: Back' })).toContainText('Cmd+[');
  await expect(page.getByTestId('keyboard-shortcut-row').filter({ hasText: 'Browser: Forward' })).toContainText('Cmd+]');
  await expect(page.getByTestId('keyboard-shortcut-row').filter({ hasText: 'Browser: Reload' })).toContainText('Cmd+R');
  await page.getByTestId('keyboard-shortcuts-close').click();

  await expect(page.getByTestId('workspace')).toHaveAttribute('data-sidebar-visible', 'true');
  await page.keyboard.press('Meta+B');
  await expect(page.getByTestId('workspace')).toHaveAttribute('data-sidebar-visible', 'false');
  await expect(page.getByTestId('sidebar')).toHaveCount(0);
  await page.keyboard.press('Meta+B');
  await expect(page.getByTestId('workspace')).toHaveAttribute('data-sidebar-visible', 'true');
  await expect(page.getByTestId('sidebar')).toBeVisible();

  await page.keyboard.press('Control+Backquote');
  await expect(page.getByTestId('terminal-pane')).toBeVisible();

  await page.keyboard.press('Meta+Shift+B');
  await expect(page.getByTestId('browser-pane')).toBeVisible();
  await page.getByLabel('Browser address').fill('localhost:5173');
  await page.getByTestId('browser-open').click();
  await page.getByLabel('Browser address').fill('example.com/docs');
  await page.getByTestId('browser-open').click();
  await expect(page.getByTestId('browser-current-url')).toHaveText('https://example.com/docs');
  await page.keyboard.press('Meta+[');
  await expect(page.getByTestId('browser-current-url')).toHaveText('http://localhost:5173');
  await page.keyboard.press('Meta+]');
  await expect(page.getByTestId('browser-current-url')).toHaveText('https://example.com/docs');
  await page.keyboard.press('Meta+R');
  await expect(page.getByTestId('browser-status-label')).toHaveText('Reloaded');

  await page.getByLabel('Message').fill('run whoami');
  await page.getByRole('button', { name: 'Send' }).click();

  await page.keyboard.press('Meta+F');
  await expect(page.getByTestId('find-bar')).toBeVisible();
  await expect(page.getByTestId('find-input')).toBeFocused();
  await page.getByTestId('find-input').fill('host.shell.run');
  await expect(page.getByTestId('find-status')).toHaveText('1 of 1');
  await expect(page.locator('.find-active')).toContainText('host.shell.run');

  await page.getByTestId('find-input').fill('mock-user');
  await expect(page.getByTestId('find-status')).toHaveText('1 of 2');
  await page.getByTestId('find-next').click();
  await expect(page.getByTestId('find-status')).toHaveText('2 of 2');
  await page.getByTestId('find-close').click();
  await expect(page.getByTestId('find-bar')).toHaveCount(0);

  await page.keyboard.press('Meta+N');

  await expect(page.getByTestId('transcript-empty')).toBeVisible();

  await page.keyboard.press('Meta+Alt+ArrowLeft');
  await expect(page.getByTestId('message').filter({ hasText: 'run whoami' })).toBeVisible();

  await page.keyboard.press('Meta+Alt+ArrowRight');
  await expect(page.getByTestId('transcript-empty')).toBeVisible();
});
