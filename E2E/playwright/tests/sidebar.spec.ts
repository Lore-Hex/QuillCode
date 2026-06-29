import { test, expect, type Locator } from '@playwright/test';
import { clickSidebarTool, harnessURL } from './harness-helpers';

async function clickProjectAction(row: Locator, name: string) {
  await row.getByLabel(/^Actions for project /).click();
  await row.getByRole('button', { name }).click();
}

test('mock harness searches and reopens an existing chat', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('run whoami');
  await page.getByRole('button', { name: 'Send' }).click();
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

  await page.getByLabel('Message').fill('run whoami');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('sidebar-item')).toContainText('run whoami');

  await page.getByTestId('new-chat-button').click();

  await expect(page.getByTestId('top-bar-title')).toHaveText('QuillCode');
  await expect(page.getByTestId('top-bar-subtitle')).toContainText('Not started');
  await expect(page.getByTestId('transcript-empty')).toBeVisible();
  await expect(page.getByTestId('sidebar-item')).toHaveAttribute('aria-current', 'false');
  await expect(page.getByTestId('sidebar-item')).toContainText('run whoami');
  await expect(page.getByLabel('Message')).toHaveValue('');
});

test('mock harness manages chat lifecycle from the sidebar', async ({ page }) => {
  await page.goto(harnessURL());
  const clickThreadAction = async (row: Locator, name: string) => {
    await row.getByLabel(/^Actions for /).click();
    await row.getByTestId('sidebar-thread-action').filter({ hasText: new RegExp(`^${name}$`) }).click();
  };

  await page.getByLabel('Message').fill('run whoami');
  await page.getByRole('button', { name: 'Send' }).click();
  await page.getByTestId('new-chat-button').click();
  await page.getByLabel('Message').fill('git diff');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('sidebar-thread-row')).toHaveCount(2);
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
  await expect(page.getByTestId('sidebar-thread-row')).toHaveCount(3);

  await clickThreadAction(copiedRow, 'Archive');

  await expect(page.getByTestId('sidebar-section-title')).toContainText(['Pinned', 'Today', 'Archived']);
  await expect(page.getByTestId('sidebar-thread-row')).toHaveCount(3);
  await expect(page.getByTestId('sidebar-thread-row').last()).toContainText('Copy: Renamed whoami');
  await expect(page.getByTestId('top-bar-title')).toHaveText('Renamed whoami');

  await clickThreadAction(page.getByTestId('sidebar-thread-row').last(), 'Unarchive');
  await expect(page.getByTestId('top-bar-title')).toHaveText('Copy: Renamed whoami');
  await expect(page.getByTestId('sidebar-section-title')).toContainText(['Pinned', 'Today']);

  await clickThreadAction(page.getByTestId('sidebar-thread-row').filter({ hasText: 'Copy: Renamed whoami' }), 'Delete');
  await expect(page.getByTestId('sidebar-thread-row')).toHaveCount(2);
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
  const sidebarSection = (title: string) => page.getByTestId('sidebar-section').filter({
    has: page.getByTestId('sidebar-section-title').filter({ hasText: new RegExp(`^${title}$`) })
  });
  await expect(sidebarSection('Today').getByTestId('sidebar-thread-row')).toContainText('today chat');
  await expect(sidebarSection('Yesterday').getByTestId('sidebar-thread-row')).toContainText('yesterday chat');
  await expect(sidebarSection('Previous 7 days').getByTestId('sidebar-thread-row')).toContainText('earlier week chat');
  await expect(sidebarSection('Older').getByTestId('sidebar-thread-row')).toContainText('older chat');
});

test('mock harness bulk-selects chats from the sidebar', async ({ page }) => {
  await page.goto(harnessURL());

  for (const prompt of ['run whoami', 'git diff', 'review tests']) {
    await page.getByLabel('Message').fill(prompt);
    await page.getByRole('button', { name: 'Send' }).click();
    await page.getByTestId('new-chat-button').click();
  }

  await expect(page.getByTestId('sidebar-thread-row')).toHaveCount(3);
  await page.getByTestId('sidebar-bulk-action').filter({ hasText: /^Select$/ }).click();
  await expect(page.getByTestId('sidebar-selection')).toHaveAttribute('data-active', 'true');

  await page.getByTestId('sidebar-thread-row').nth(0).getByTestId('sidebar-select-toggle').click();
  await page.getByTestId('sidebar-thread-row').nth(1).getByTestId('sidebar-select-toggle').click();
  await expect(page.getByTestId('sidebar-selection-label')).toHaveText('2 chats selected');

  await page.getByTestId('sidebar-bulk-action').filter({ hasText: /^Archive$/ }).click();
  await expect(page.getByTestId('sidebar-selection')).toHaveCount(0);
  const sidebarSection = (title: string) => page.getByTestId('sidebar-section').filter({
    has: page.getByTestId('sidebar-section-title').filter({ hasText: new RegExp(`^${title}$`) })
  });
  await expect(sidebarSection('Archived').getByTestId('sidebar-thread-row')).toHaveCount(2);
  await expect(sidebarSection('Today').getByTestId('sidebar-thread-row')).toHaveCount(1);

  await page.getByTestId('sidebar-bulk-action').filter({ hasText: /^Select$/ }).click();
  await page.getByTestId('sidebar-bulk-action').filter({ hasText: 'Select all' }).click();
  await expect(page.getByTestId('sidebar-selection-label')).toHaveText('3 chats selected');
  await page.getByTestId('sidebar-bulk-action').filter({ hasText: /^Delete$/ }).click();

  await expect(page.getByTestId('sidebar-thread-row')).toHaveCount(0);
  await expect(page.getByTestId('sidebar-title-row')).toHaveCount(0);
  await expect(page.getByTestId('sidebar-empty')).toHaveText('No chats yet');
});

test('mock harness filters sidebar chats with saved filters', async ({ page }) => {
  await page.goto(harnessURL());
  const clickThreadAction = async (row: Locator, name: string) => {
    await row.getByLabel(/^Actions for /).click();
    await row.getByTestId('sidebar-thread-action').filter({ hasText: new RegExp(`^${name}$`) }).click();
  };

  await page.getByLabel('Message').fill('recent chat');
  await page.getByRole('button', { name: 'Send' }).click();
  await page.getByTestId('new-chat-button').click();
  await page.getByLabel('Message').fill('pinned chat');
  await page.getByRole('button', { name: 'Send' }).click();
  await clickThreadAction(page.getByTestId('sidebar-thread-row').filter({ hasText: 'pinned chat' }), 'Pin');
  await page.getByTestId('new-chat-button').click();
  await page.getByLabel('Message').fill('archived chat');
  await page.getByRole('button', { name: 'Send' }).click();
  await clickThreadAction(page.getByTestId('sidebar-thread-row').filter({ hasText: 'archived chat' }), 'Archive');

  await expect(page.getByTestId('sidebar-filter')).toHaveCount(4);
  await expect(page.getByTestId('sidebar-filter').nth(0)).toContainText('All');
  await expect(page.getByTestId('sidebar-filter').nth(0).getByTestId('sidebar-filter-count')).toHaveText('3');
  await expect(page.getByTestId('sidebar-filter').nth(1).getByTestId('sidebar-filter-count')).toHaveText('1');
  await expect(page.getByTestId('sidebar-filter').nth(2).getByTestId('sidebar-filter-count')).toHaveText('1');
  await expect(page.getByTestId('sidebar-filter').nth(3).getByTestId('sidebar-filter-count')).toHaveText('1');

  const filter = (id: string) => page.locator(`[data-testid="sidebar-filter"][data-filter-id="${id}"]`);
  await filter('pinned').click();
  await expect(filter('pinned')).toHaveAttribute('aria-pressed', 'true');
  await expect(page.getByTestId('sidebar-thread-row')).toHaveCount(1);
  await expect(page.getByTestId('sidebar-thread-row')).toContainText('pinned chat');
  await expect(page.getByTestId('sidebar')).not.toContainText('recent chat');

  await page.getByTestId('sidebar-bulk-action').filter({ hasText: /^Select$/ }).click();
  await page.getByTestId('sidebar-bulk-action').filter({ hasText: /^Select all$/ }).click();
  await expect(page.getByTestId('sidebar-selection-label')).toHaveText('1 chat selected');
  await expect(page.getByTestId('sidebar-bulk-action').filter({ hasText: /^Pin$/ })).toBeDisabled();
  await filter('archived').click();

  await expect(page.getByTestId('sidebar-selection')).toHaveCount(0);
  await expect(page.getByTestId('sidebar-thread-row')).toHaveCount(1);
  await expect(page.getByTestId('sidebar-thread-row')).toContainText('archived chat');
  await filter('recent').click();
  await expect(page.getByTestId('sidebar-thread-row')).toHaveCount(1);
  await expect(page.getByTestId('sidebar-thread-row')).toContainText('recent chat');
});

test('mock harness filters sidebar chats with custom saved searches', async ({ page }) => {
  await page.goto(harnessURL());

  for (const prompt of ['openclaw setup notes', 'quill cloud relay', 'openclaw release follow up']) {
    await page.getByLabel('Message').fill(prompt);
    await page.getByRole('button', { name: 'Send' }).click();
    await page.getByTestId('new-chat-button').click();
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

  await page.locator('[data-testid="sidebar-filter"][data-filter-id="all"]').click({ position: { x: 8, y: 8 } });
  await expect(page.getByTestId('sidebar-selection')).toHaveCount(0);
  await expect(page.locator('[data-testid="sidebar-filter"][data-filter-id="all"]')).toHaveAttribute('aria-pressed', 'true');
  await expect(page.getByTestId('sidebar-thread-row')).toHaveCount(3);
});

test('mock harness creates and deletes custom saved searches from explicit sidebar targets', async ({ page }) => {
  await page.goto(harnessURL());

  for (const prompt of ['run whoami', 'write hello world notes', 'run df -h']) {
    await page.getByLabel('Message').fill(prompt);
    await page.getByRole('button', { name: 'Send' }).click();
    await page.getByTestId('new-chat-button').click();
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
  await expect(page.locator('[data-testid="sidebar-filter"][data-filter-id="all"]')).toHaveAttribute('aria-pressed', 'true');
  await expect(page.getByTestId('sidebar-thread-row')).toHaveCount(3);
});

test('mock harness manages projects from the sidebar', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByTestId('add-project-button').click();

  await expect(page.getByTestId('project-item')).toHaveCount(2);
  await expect(page.getByTestId('project-item').first()).toContainText('Example Project 2');
  await expect(page.getByTestId('project-item').first()).toContainText('/mock/example-2');
  await expect(page.getByTestId('project-item').first()).toHaveAttribute('aria-current', 'true');
  await expect(page.getByTestId('top-bar-subtitle')).toContainText('Example Project 2');

  await clickSidebarTool(page, 'terminal-button');
  await expect(page.getByTestId('terminal-cwd')).toHaveText('/mock/example-2');

  const activeProjectRow = page.getByTestId('project-row').first();
  page.once('dialog', async dialog => {
    expect(dialog.message()).toContain('Rename project');
    await dialog.accept('Renamed Project');
  });
  await clickProjectAction(activeProjectRow, 'Rename');
  await expect(page.getByTestId('project-item').first()).toContainText('Renamed Project');
  await expect(page.getByTestId('top-bar-subtitle')).toContainText('Renamed Project');

  await clickProjectAction(page.getByTestId('project-row').first(), 'Refresh context');
  await expect(page.getByTestId('message').last()).toContainText('Refreshed project context for Renamed Project.');

  await clickProjectAction(page.getByTestId('project-row').first(), 'New chat');
  await expect(page.getByTestId('top-bar-title')).toHaveText('New chat');
  await expect(page.getByTestId('sidebar-item').first()).toContainText('New chat');

  await clickProjectAction(page.getByTestId('project-row').first(), 'Remove from list');
  await expect(page.getByTestId('project-item')).toHaveCount(1);
  await expect(page.getByTestId('project-item').first()).toContainText('QuillCode');
});

test('mock harness adds an SSH remote project from command palette and slash command', async ({ page }) => {
  await page.goto(harnessURL());

  await clickSidebarTool(page, 'command-palette-button');
  await page.getByLabel('Search commands').fill('>ssh');
  await expect(page.getByTestId('command-palette-result')).toHaveCount(1);
  await expect(page.getByTestId('command-palette-result')).toContainText('Project: Add SSH Remote');
  await page.getByTestId('command-palette-result').click();
  await expect(page.getByLabel('Message')).toHaveValue('/ssh user@host:/absolute/path');

  await page.getByLabel('Message').fill('/ssh quill@feather.local:/srv/quill');
  await page.getByRole('button', { name: 'Send' }).click();

  const remoteProject = page.getByTestId('project-row').first();
  await expect(remoteProject.getByTestId('project-item')).toContainText('feather.local · quill');
  await expect(remoteProject.getByTestId('project-item')).toContainText('ssh://quill@feather.local/srv/quill');
  await expect(remoteProject.getByTestId('project-connection-kind')).toHaveText('SSH Remote');
  await expect(page.getByTestId('top-bar-subtitle')).toContainText('feather.local · quill');
  await expect(page.getByTestId('message').last()).toContainText('Added SSH Remote');

  await clickProjectAction(remoteProject, 'Refresh context');
  await expect(page.getByTestId('message').last()).toContainText('Refreshed project context for feather.local · quill.');

  await clickSidebarTool(page, 'terminal-button');
  await expect(page.getByTestId('terminal-pane')).toBeVisible();
  await expect(page.getByTestId('terminal-cwd')).toHaveText('ssh://quill@feather.local/srv/quill');
  await page.getByTestId('terminal-input').fill('pwd');
  await page.getByTestId('terminal-run').click();
  await expect(page.getByTestId('terminal-status')).toHaveText('Done · exit 0');
  await expect(page.getByTestId('terminal-stdout')).toHaveText('/srv/quill\n');
  await expect(page.getByTestId('terminal-entry')).toHaveAttribute('data-execution-context', 'ssh-remote');
  await expect(page.getByTestId('terminal-execution-context')).toHaveText('SSH Remote · feather.local');

  await page.getByLabel('Message').fill('whoami');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.shell.run');
  await expect(page.getByTestId('tool-card').last()).toHaveAttribute('data-execution-context', 'ssh-remote');
  await expect(page.getByTestId('tool-card-execution-context').last()).toHaveText('SSH Remote · feather.local');
  await expect(page.getByTestId('tool-card-output').last()).toContainText('quill');
  await expect(page.getByText('You are `quill` in this workspace.')).toBeVisible();

  await clickSidebarTool(page, 'command-palette-button');
  await page.getByLabel('Search commands').fill('>git status');
  await page.getByTestId('command-palette-result').filter({ hasText: 'Git status' }).click();
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.status');
  await expect(page.getByTestId('tool-card').last()).toHaveAttribute('data-execution-context', 'ssh-remote');
  await expect(page.getByTestId('tool-card-execution-context').last()).toHaveText('SSH Remote · feather.local');
  await expect(page.getByTestId('tool-card-output').last()).toContainText('ssh://quill@feather.local/srv/quill');

  await clickSidebarTool(page, 'command-palette-button');
  await page.getByLabel('Search commands').fill('>review diff');
  await page.getByTestId('command-palette-result').filter({ hasText: 'Review diff' }).click();
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.diff');
  await expect(page.getByTestId('tool-card').last()).toHaveAttribute('data-execution-context', 'ssh-remote');
  await expect(page.getByTestId('tool-card-execution-context').last()).toHaveText('SSH Remote · feather.local');
  await expect(page.getByTestId('review-pane')).toBeVisible();
  await expect(page.getByTestId('review-file')).toContainText('Sources/App.swift');

  await page.getByLabel('Message').fill('Can you write a file that says hello world');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.shell.run');
  await expect(page.getByTestId('tool-card-input').last()).toContainText('printf %s');
  await expect(page.getByText('Wrote `hello.txt` on feather.local · quill.')).toBeVisible();
});
