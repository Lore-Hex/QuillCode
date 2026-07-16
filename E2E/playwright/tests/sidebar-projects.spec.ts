import { test, expect } from '@playwright/test';
import { clickSidebarTool, harnessURL } from './harness-helpers';
import { clickProjectAction } from './sidebar-test-helpers';

test('mock harness manages projects from the sidebar', async ({ page }) => {
  await page.goto(harnessURL());
  await expect(page.getByTestId('project-count')).toHaveText('1 project');

  await page.getByTestId('add-project-button').click();

  await expect(page.getByTestId('project-item')).toHaveCount(2);
  await expect(page.getByTestId('project-count')).toHaveText('2 projects');
  await expect(page.getByTestId('project-item').first()).toContainText('Example Project 2');
  await expect(page.getByTestId('project-item').first()).toHaveAttribute('title', '/mock/example-2');
  await expect(page.getByTestId('project-item').first()).toHaveAttribute('aria-current', 'true');
  await expect(page.getByTestId('top-bar-subtitle')).toContainText('Example Project 2');

  await clickSidebarTool(page, 'terminal-button');
  await expect(page.getByTestId('terminal-cwd')).toHaveText('/mock/example-2');

  await page.getByLabel('Message').fill('/project bottom');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('project-item').first()).toContainText('QuillCode');
  await page.getByLabel('Message').fill('/project top');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('project-item').first()).toContainText('Example Project 2');

  await clickProjectAction(page.getByTestId('project-row').first(), 'Move down');
  await expect(page.getByTestId('project-item').first()).toContainText('QuillCode');
  await clickProjectAction(page.getByTestId('project-row').nth(1), 'Move up');
  await expect(page.getByTestId('project-item').first()).toContainText('Example Project 2');
  await clickProjectAction(page.getByTestId('project-row').first(), 'Move to bottom');
  await expect(page.getByTestId('project-item').first()).toContainText('QuillCode');
  await clickProjectAction(page.getByTestId('project-row').nth(1), 'Move to top');
  await expect(page.getByTestId('project-item').first()).toContainText('Example Project 2');
  await page.getByTestId('project-row').nth(1).dragTo(page.getByTestId('project-row').first());
  await expect(page.getByTestId('project-item').first()).toContainText('QuillCode');
  await page.getByTestId('project-row').nth(1).dragTo(page.getByTestId('project-row').first());
  await expect(page.getByTestId('project-item').first()).toContainText('Example Project 2');

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
  await expect(page.getByTestId('project-count')).toHaveText('1 project');
  await expect(page.getByTestId('project-item').first()).toContainText('QuillCode');
});

test('mock harness discovers and probes an SSH remote from the native connection dialog', async ({ page }) => {
  await page.goto(harnessURL());

  await clickSidebarTool(page, 'command-palette-button');
  await page.getByLabel('Search commands').fill('>ssh');
  await expect(page.getByTestId('command-palette-result')).toHaveCount(1);
  await expect(page.getByTestId('command-palette-result')).toContainText('Project: Add SSH Remote');
  await page.getByTestId('command-palette-result').click();
  const dialog = page.getByRole('dialog', { name: 'Connect over SSH' });
  await expect(dialog).toBeVisible();
  await page.getByTestId('ssh-host-search').fill('feather');
  await expect(page.getByTestId('ssh-host-option')).toHaveCount(1);
  await page.getByTestId('ssh-host-option').click();
  await page.getByTestId('ssh-remote-path').fill('/srv/quill');
  await page.evaluate(() => { (window as any).__quillCodeFailNextSSHProbe = true; });
  await page.getByTestId('ssh-connection-submit').click();
  await expect(page.getByTestId('ssh-connection-error')).toContainText('Permission denied');
  await page.getByTestId('ssh-connection-submit').click();
  await expect(dialog).toBeHidden();

  const remoteProject = page.getByTestId('project-row').first();
  await expect(remoteProject.getByTestId('project-item')).toContainText('feather.local · quill');
  await expect(remoteProject.getByTestId('project-item')).toHaveAttribute(
    'title',
    'ssh://feather.local/srv/quill'
  );
  await expect(remoteProject.getByTestId('project-connection-kind')).toHaveText('SSH');
  await expect(page.getByTestId('top-bar-subtitle')).toContainText('feather.local · quill');
  await expect(page.getByTestId('message').last()).toContainText('Added SSH Remote');

  await clickProjectAction(remoteProject, 'Refresh context');
  await expect(page.getByTestId('message').last()).toContainText('Refreshed project context for feather.local · quill.');

  await clickSidebarTool(page, 'terminal-button');
  await expect(page.getByTestId('terminal-pane')).toBeVisible();
  await expect(page.getByTestId('terminal-cwd')).toHaveText('ssh://feather.local/srv/quill');
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
  await expect(page.getByTestId('tool-card-output').last()).toContainText('ssh://feather.local/srv/quill');

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

test('SSH connection is available from Settings and validates manual addresses', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByTestId('settings-button').click();
  await expect(page.getByTestId('ssh-connections-settings')).toBeVisible();
  await page.getByTestId('ssh-settings-open').click();
  await expect(page.getByTestId('settings-panel')).toBeHidden();
  await expect(page.getByRole('dialog', { name: 'Connect over SSH' })).toBeVisible();

  await page.getByTestId('ssh-connection-mode').selectOption('manual');
  await page.getByTestId('ssh-manual-address').fill('not an address');
  await page.getByTestId('ssh-remote-path').fill('relative/path');
  await expect(page.getByTestId('ssh-connection-submit')).toBeDisabled();

  await page.getByTestId('ssh-manual-address').fill('deploy@build.example:2202');
  await page.getByTestId('ssh-remote-path').fill('/srv/build');
  await page.getByTestId('ssh-project-name').fill('Build Host');
  await expect(page.getByTestId('ssh-connection-submit')).toBeEnabled();
  await page.getByTestId('ssh-connection-submit').click();

  const remoteProject = page.getByTestId('project-row').first();
  await expect(remoteProject.getByTestId('project-item')).toContainText('Build Host');
  await expect(remoteProject.getByTestId('project-item')).toHaveAttribute(
    'title',
    'ssh://deploy@build.example:2202/srv/build'
  );
});

test('closing the SSH dialog cancels an in-flight remote probe', async ({ page }) => {
  await page.goto(harnessURL());
  const initialProjectCount = await page.getByTestId('project-row').count();

  await page.evaluate(() => { (window as any).__quillCodeSSHProbeDelayMS = 300; });
  await clickSidebarTool(page, 'add-ssh-project-button');
  await page.getByTestId('ssh-remote-path').fill('/srv/cancelled');
  await page.getByTestId('ssh-connection-submit').click();
  await expect(page.getByTestId('ssh-connection-submit')).toHaveText('Connecting...');
  await page.getByTestId('ssh-connection-close').click();
  await expect(page.getByRole('dialog', { name: 'Connect over SSH' })).toBeHidden();

  await page.waitForTimeout(400);
  await expect(page.getByTestId('project-row')).toHaveCount(initialProjectCount);
  await expect(page.getByText(/Added SSH Remote/)).toHaveCount(0);
});
