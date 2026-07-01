import { test, expect } from '@playwright/test';
import { clickSidebarTool, harnessURL } from './harness-helpers';
import { clickProjectAction } from './sidebar-test-helpers';

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
