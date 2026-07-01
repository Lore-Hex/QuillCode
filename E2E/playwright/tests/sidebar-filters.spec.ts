import { test, expect, type Page } from '@playwright/test';
import { harnessURL } from './harness-helpers';
import { clickThreadAction, sendSidebarPrompt, sendSidebarPromptThenNewChat } from './sidebar-test-helpers';

const filter = (page: Page, id: string) => page.locator(`[data-testid="sidebar-filter"][data-filter-id="${id}"]`);

test('mock harness filters sidebar chats with saved filters', async ({ page }) => {
  await page.goto(harnessURL());

  await sendSidebarPromptThenNewChat(page, 'recent chat');
  await sendSidebarPrompt(page, 'pinned chat');
  await clickThreadAction(page.getByTestId('sidebar-thread-row').filter({ hasText: 'pinned chat' }), 'Pin');
  await page.getByTestId('new-chat-button').click();
  await sendSidebarPrompt(page, 'archived chat');
  await clickThreadAction(page.getByTestId('sidebar-thread-row').filter({ hasText: 'archived chat' }), 'Archive');

  await expect(page.getByTestId('sidebar-filter')).toHaveCount(4);
  await expect(page.getByTestId('sidebar-filter').nth(0)).toContainText('All');
  await expect(page.getByTestId('sidebar-filter').nth(0).getByTestId('sidebar-filter-count')).toHaveText('3');
  await expect(page.getByTestId('sidebar-filter').nth(1).getByTestId('sidebar-filter-count')).toHaveText('1');
  await expect(page.getByTestId('sidebar-filter').nth(2).getByTestId('sidebar-filter-count')).toHaveText('1');
  await expect(page.getByTestId('sidebar-filter').nth(3).getByTestId('sidebar-filter-count')).toHaveText('1');

  await filter(page, 'pinned').click();
  await expect(filter(page, 'pinned')).toHaveAttribute('aria-pressed', 'true');
  await expect(page.getByTestId('sidebar-thread-row')).toHaveCount(1);
  await expect(page.getByTestId('sidebar-thread-row')).toContainText('pinned chat');
  await expect(page.getByTestId('sidebar')).not.toContainText('recent chat');

  await page.getByTestId('sidebar-bulk-action').filter({ hasText: /^Select$/ }).click();
  await page.getByTestId('sidebar-bulk-action').filter({ hasText: /^Select all$/ }).click();
  await expect(page.getByTestId('sidebar-selection-label')).toHaveText('1 chat selected');
  await expect(page.getByTestId('sidebar-bulk-action').filter({ hasText: /^Pin$/ })).toBeDisabled();
  await filter(page, 'archived').click();

  await expect(page.getByTestId('sidebar-selection')).toHaveCount(0);
  await expect(page.getByTestId('sidebar-thread-row')).toHaveCount(1);
  await expect(page.getByTestId('sidebar-thread-row')).toContainText('archived chat');
  await filter(page, 'recent').click();
  await expect(page.getByTestId('sidebar-thread-row')).toHaveCount(1);
  await expect(page.getByTestId('sidebar-thread-row')).toContainText('recent chat');
});

test('mock harness filters sidebar chats with custom saved searches', async ({ page }) => {
  await page.goto(harnessURL());

  for (const prompt of ['openclaw setup notes', 'quill cloud relay', 'openclaw release follow up']) {
    await sendSidebarPromptThenNewChat(page, prompt);
  }

  await page.evaluate(() => {
    const harness = window as unknown as {
      addSidebarSavedSearch: (title: string, query: string, id: string) => string | null;
    };
    harness.addSidebarSavedSearch('OpenClaw', 'openclaw', 'saved-openclaw');
  });

  const savedSearch = page.locator('[data-testid="sidebar-saved-search"][data-saved-search-id="saved-openclaw"]');
  await expect(page.getByTestId('sidebar-saved-search-bar')).toBeVisible();
  await expect(savedSearch).toContainText('OpenClaw');
  await expect(savedSearch.getByTestId('sidebar-saved-search-count')).toHaveText('2');

  await savedSearch.click({ position: { x: 8, y: 8 } });
  await expect(savedSearch).toHaveAttribute('aria-pressed', 'true');
  await expect(page.getByTestId('sidebar-filter').first()).toHaveAttribute('aria-pressed', 'false');
  await expect(page.getByTestId('sidebar-thread-row')).toHaveCount(2);
  await expect(page.getByTestId('sidebar')).toContainText('openclaw setup notes');
  await expect(page.getByTestId('sidebar')).toContainText('openclaw release follow up');
  await expect(page.getByTestId('sidebar')).not.toContainText('quill cloud relay');

  await page.getByTestId('sidebar-bulk-action').filter({ hasText: /^Select$/ }).click();
  await page.getByTestId('sidebar-bulk-action').filter({ hasText: /^Select all$/ }).click();
  await expect(page.getByTestId('sidebar-selection-label')).toHaveText('2 chats selected');

  await filter(page, 'all').click({ position: { x: 8, y: 8 } });
  await expect(page.getByTestId('sidebar-selection')).toHaveCount(0);
  await expect(filter(page, 'all')).toHaveAttribute('aria-pressed', 'true');
  await expect(page.getByTestId('sidebar-thread-row')).toHaveCount(3);
});

test('mock harness creates and deletes custom saved searches from explicit sidebar targets', async ({ page }) => {
  await page.goto(harnessURL());

  for (const prompt of ['run whoami', 'write hello world notes', 'run df -h']) {
    await sendSidebarPromptThenNewChat(page, prompt);
  }

  await page.getByTestId('sidebar-saved-search-create').click();
  await expect(page.getByTestId('sidebar-saved-search-panel')).toBeVisible();
  await expect(page.getByTestId('sidebar-saved-search-query')).toBeFocused();

  await page.getByTestId('sidebar-saved-search-query').fill('run');
  await page.getByTestId('sidebar-saved-search-title').fill('Shell runs');
  await page.getByTestId('sidebar-saved-search-save').click();

  const savedSearch = page.getByTestId('sidebar-saved-search');
  await expect(savedSearch).toContainText('Shell runs');
  await expect(savedSearch.getByTestId('sidebar-saved-search-count')).toHaveText('2');
  await expect(savedSearch).toHaveAttribute('aria-pressed', 'true');
  await expect(page.getByTestId('sidebar-thread-row')).toHaveCount(2);
  await expect(page.getByTestId('sidebar')).toContainText('run whoami');
  await expect(page.getByTestId('sidebar')).toContainText('run df -h');
  await expect(page.getByTestId('sidebar')).not.toContainText('write hello world notes');

  await page.getByTestId('sidebar-saved-search-delete').click();
  await expect(page.getByTestId('sidebar-saved-search')).toHaveCount(0);
  await expect(page.getByTestId('sidebar-saved-search-empty')).toBeVisible();
  await expect(filter(page, 'all')).toHaveAttribute('aria-pressed', 'true');
  await expect(page.getByTestId('sidebar-thread-row')).toHaveCount(3);
});

test('mock harness reorders custom saved searches from explicit sidebar targets', async ({ page }) => {
  await page.goto(harnessURL());

  for (const prompt of ['run whoami', 'write hello world notes', 'run df -h']) {
    await sendSidebarPromptThenNewChat(page, prompt);
  }

  await page.evaluate(() => {
    const harness = window as unknown as {
      addSidebarSavedSearch: (title: string, query: string, id: string) => string | null;
    };
    harness.addSidebarSavedSearch('Shell runs', 'run', 'saved-shell-runs');
    harness.addSidebarSavedSearch('Notes', 'notes', 'saved-notes');
  });

  const row = (index: number) => page.getByTestId('sidebar-saved-search-row').nth(index);
  await expect(row(0).getByTestId('sidebar-saved-search')).toContainText('Shell runs');
  await expect(row(0).getByTestId('sidebar-saved-search-move-up')).toBeDisabled();
  await expect(row(0).getByTestId('sidebar-saved-search-move-down')).toBeEnabled();
  await expect(row(1).getByTestId('sidebar-saved-search')).toContainText('Notes');
  await expect(row(1).getByTestId('sidebar-saved-search-move-up')).toBeEnabled();
  await expect(row(1).getByTestId('sidebar-saved-search-move-down')).toBeDisabled();
  await expect(page.locator('[data-testid="sidebar-saved-search"][data-saved-search-id="saved-notes"]'))
    .toHaveAttribute('aria-pressed', 'true');

  await row(0).getByTestId('sidebar-saved-search-move-down').click({ position: { x: 8, y: 8 } });
  await expect(row(0).getByTestId('sidebar-saved-search')).toContainText('Notes');
  await expect(row(1).getByTestId('sidebar-saved-search')).toContainText('Shell runs');
  await expect(row(0).getByTestId('sidebar-saved-search-move-up')).toBeDisabled();
  await expect(row(1).getByTestId('sidebar-saved-search-move-down')).toBeDisabled();
  await expect(page.locator('[data-testid="sidebar-saved-search"][data-saved-search-id="saved-notes"]'))
    .toHaveAttribute('aria-pressed', 'true');

  await row(1).getByTestId('sidebar-saved-search-move-up').click({ position: { x: 8, y: 8 } });
  await expect(row(0).getByTestId('sidebar-saved-search')).toContainText('Shell runs');
  await expect(row(1).getByTestId('sidebar-saved-search')).toContainText('Notes');
});
