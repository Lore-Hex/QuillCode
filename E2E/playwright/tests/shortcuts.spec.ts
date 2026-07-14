import { test, expect, type Page } from '@playwright/test';
import { harnessURL, sendComposerPrompt } from './harness-helpers';

function shortcutRow(page: Page, commandID: string) {
  return page.locator(
    `[data-testid="keyboard-shortcut-row"][data-command-id="${commandID}"]`
  );
}

async function openShortcuts(page: Page) {
  await page.keyboard.press('Meta+Shift+/');
  await expect(page.getByTestId('keyboard-shortcuts-panel')).toBeVisible();
  await expect(page.getByTestId('keyboard-shortcuts-input')).toBeFocused();
}

async function selectedThreadID(page: Page): Promise<string> {
  const threadID = await page.locator('.sidebar-item.selected').getAttribute('data-thread-id');
  if (threadID === null) {
    throw new Error('Expected the selected task to expose a stable thread ID.');
  }
  return threadID;
}

async function dispatchAppShortcut(
  page: Page,
  event: {
    key: string;
    code: string;
    metaKey?: boolean;
    ctrlKey?: boolean;
    altKey?: boolean;
    shiftKey?: boolean;
  }
) {
  await page.evaluate(shortcut => (window as any).__quillCodeTestDispatchShortcut(shortcut), event);
}

test.beforeEach(async ({ page }) => {
  await page.goto(harnessURL());
});

test('dispatches Codex-compatible workspace shortcuts', async ({ page }) => {
  await page.keyboard.press('Meta+K');
  await expect(page.getByTestId('command-palette-panel')).toBeVisible();
  await page.getByTestId('command-palette-close').click();

  await page.keyboard.press('Meta+Shift+P');
  await expect(page.getByTestId('command-palette-panel')).toBeVisible();
  await page.getByTestId('command-palette-close').click();

  await page.keyboard.press('Meta+G');
  await expect(page.getByTestId('search-panel')).toBeVisible();
  await page.getByTestId('search-close').click();

  await openShortcuts(page);
  await expect(shortcutRow(page, 'command-palette')).toContainText('Cmd+K');
  await expect(shortcutRow(page, 'search')).toContainText('Cmd+G');
  await expect(shortcutRow(page, 'keyboard-shortcuts')).toContainText('Cmd+Shift+/');
  await expect(shortcutRow(page, 'workspace-back')).toContainText('Cmd+[');
  await expect(shortcutRow(page, 'workspace-forward')).toContainText('Cmd+]');
  await expect(shortcutRow(page, 'previous-task')).toContainText('Cmd+Shift+[');
  await expect(shortcutRow(page, 'next-task')).toContainText('Cmd+Shift+]');

  await page.getByTestId('keyboard-shortcuts-mode-keystroke').click();
  await expect(page.getByTestId('keyboard-shortcuts-input')).toBeFocused();
  await page.keyboard.press('Meta+G');
  await expect(page.getByTestId('keyboard-shortcuts-input')).toHaveValue('Cmd+G');
  await expect(shortcutRow(page, 'search')).toBeVisible();
  await expect(shortcutRow(page, 'new-chat')).toHaveCount(0);
  await page.getByTestId('keyboard-shortcuts-done').click();

  await expect(page.getByTestId('workspace')).toHaveAttribute('data-sidebar-visible', 'true');
  await page.keyboard.press('Meta+B');
  await expect(page.getByTestId('workspace')).toHaveAttribute('data-sidebar-visible', 'false');
  await expect(page.getByTestId('sidebar')).toHaveCount(0);
  await page.keyboard.press('Meta+B');
  await expect(page.getByTestId('workspace')).toHaveAttribute('data-sidebar-visible', 'true');

  await page.keyboard.press('Control+Backquote');
  await expect(page.getByTestId('terminal-pane')).toBeVisible();
  // Chromium reserves Cmd+J; dispatch the app-level event exercised by the native shell.
  await dispatchAppShortcut(page, { key: 'j', code: 'KeyJ', metaKey: true });
  await expect(page.getByTestId('terminal-pane')).toHaveCount(0);
  await dispatchAppShortcut(page, { key: 'j', code: 'KeyJ', metaKey: true });
  await expect(page.getByTestId('terminal-pane')).toBeVisible();

  await page.keyboard.press('Meta+Shift+B');
  await expect(page.getByTestId('browser-pane')).toBeVisible();
  await page.getByLabel('Browser address').fill('example.com/docs');
  await page.getByTestId('browser-open').click();
  await page.keyboard.press('Meta+R');
  await expect(page.getByTestId('browser-status-label')).toHaveText('Reloaded');

  await sendComposerPrompt(page, 'run whoami');
  await expect(page.getByTestId('message').filter({ hasText: 'run whoami' })).toBeVisible();

  await page.keyboard.press('Meta+F');
  await expect(page.getByTestId('find-input')).toBeFocused();
  await page.getByTestId('find-input').fill('host.shell.run');
  await expect(page.getByTestId('find-status')).toHaveText('1 of 1');
  await page.getByTestId('find-close').click();

  await page.keyboard.press('Meta+N');
  await expect(page.getByTestId('transcript-empty')).toBeVisible();
  await page.keyboard.press('Meta+[');
  await expect(page.getByTestId('message').filter({ hasText: 'run whoami' })).toBeVisible();
  await page.keyboard.press('Meta+]');
  await expect(page.getByTestId('transcript-empty')).toBeVisible();
});

test('searches, customizes, persists, rejects conflicts, and resets shortcuts', async ({ page }) => {
  await openShortcuts(page);
  const searchInput = page.getByTestId('keyboard-shortcuts-input');
  await searchInput.fill('search');
  await expect(shortcutRow(page, 'search')).toBeVisible();
  await expect(shortcutRow(page, 'new-chat')).toHaveCount(0);

  await shortcutRow(page, 'search').getByTestId('keyboard-shortcut-edit').click();
  await page.keyboard.press('Meta+Alt+S');
  await expect(shortcutRow(page, 'search')).toContainText('Cmd+Option+S');
  await expect(shortcutRow(page, 'search')).toContainText('Customized');
  await page.getByTestId('keyboard-shortcuts-done').click();

  await page.keyboard.press('Meta+G');
  await expect(page.getByTestId('search-panel')).toHaveCount(0);
  await page.keyboard.press('Meta+Alt+S');
  await expect(page.getByTestId('search-panel')).toBeVisible();
  await page.getByTestId('search-close').click();

  await page.reload();
  await page.keyboard.press('Meta+Alt+S');
  await expect(page.getByTestId('search-panel')).toBeVisible();
  await page.getByTestId('search-close').click();

  await openShortcuts(page);
  await shortcutRow(page, 'search').getByTestId('keyboard-shortcut-edit').click();
  await page.keyboard.press('Meta+K');
  await expect(page.getByTestId('keyboard-shortcuts-validation'))
    .toContainText('already used by Command palette');
  await page.keyboard.press('Escape');
  await expect(shortcutRow(page, 'search')).toContainText('Cmd+Option+S');

  await page.getByTestId('keyboard-shortcuts-reset-all').click();
  await expect(shortcutRow(page, 'search')).toContainText('Cmd+G');
  await expect(shortcutRow(page, 'search')).not.toContainText('Customized');
  await page.getByTestId('keyboard-shortcuts-done').click();

  await page.keyboard.press('Meta+G');
  await expect(page.getByTestId('search-panel')).toBeVisible();
});

test('routes task navigation, quick chat, review, scale, and dictation shortcuts', async ({ page }) => {
  await sendComposerPrompt(page, 'first task');
  await expect(page.getByTestId('message').filter({ hasText: 'first task' })).toBeVisible();

  // Chromium reserves Cmd+Option+N; the native app receives this chord directly.
  await dispatchAppShortcut(page, {
    key: 'n',
    code: 'KeyN',
    metaKey: true,
    altKey: true
  });
  await expect(page.getByTestId('side-conversation')).toBeVisible();
  await page.getByTestId('side-conversation-return').click();

  const firstThreadID = await selectedThreadID(page);
  await page.keyboard.press('Meta+N');
  await sendComposerPrompt(page, 'second task');
  const secondThreadID = await selectedThreadID(page);
  expect(secondThreadID).not.toBe(firstThreadID);

  await dispatchAppShortcut(page, {
    key: '{',
    code: 'BracketLeft',
    metaKey: true,
    shiftKey: true
  });
  await expect(page.locator('.sidebar-item.selected')).toHaveAttribute('data-thread-id', firstThreadID);
  await dispatchAppShortcut(page, {
    key: '}',
    code: 'BracketRight',
    metaKey: true,
    shiftKey: true
  });
  await expect(page.locator('.sidebar-item.selected')).toHaveAttribute('data-thread-id', secondThreadID);

  await page.keyboard.press('Control+Shift+G');
  await expect(page.getByTestId('review-pane')).toBeVisible();
  await dispatchAppShortcut(page, {
    key: 'b',
    code: 'KeyB',
    metaKey: true,
    altKey: true
  });
  await expect(page.getByTestId('workspace')).toHaveAttribute('data-review-visible', 'false');
  await expect(page.getByTestId('review-pane')).toHaveCount(0);
  await dispatchAppShortcut(page, {
    key: 'b',
    code: 'KeyB',
    metaKey: true,
    altKey: true
  });
  await expect(page.getByTestId('review-pane')).toBeVisible();

  await expect(page.getByTestId('workspace')).toHaveAttribute('data-text-scale', 'standard');
  await dispatchAppShortcut(page, {
    key: '+',
    code: 'Equal',
    metaKey: true,
    shiftKey: true
  });
  await expect(page.getByTestId('workspace')).toHaveAttribute('data-text-scale', 'large');
  await dispatchAppShortcut(page, { key: '-', code: 'Minus', metaKey: true });
  await expect(page.getByTestId('workspace')).toHaveAttribute('data-text-scale', 'standard');

  await page.getByTestId('top-bar-title').click();
  await page.keyboard.press('Control+Shift+D');
  await expect(page.getByLabel('Message')).toBeFocused();
});
