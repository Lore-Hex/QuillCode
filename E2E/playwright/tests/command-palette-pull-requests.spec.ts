import { test, expect } from '@playwright/test';
import {
  clickCommandPaletteCommand,
  clickSidebarTool,
  commandPaletteResult,
  fillCommandPalette,
  harnessURL
} from './harness-helpers';

const pullRequestCommandIDs = [
  'git-pr-create',
  'git-pr-list',
  'git-pr-view',
  'git-pr-checks',
  'git-pr-diff',
  'git-pr-checkout',
  'git-pr-reviewers',
  'git-pr-comment',
  'git-pr-review',
  'git-pr-review-comment',
  'git-pr-review-reply',
  'git-pr-review-threads',
  'git-pr-review-thread',
  'git-pr-labels',
  'git-pr-lifecycle',
  'git-pr-merge'
];

const draftCommands = [
  {
    id: 'git-pr-checkout',
    query: '>checkout pull request',
    draft: 'Checkout pull request '
  },
  {
    id: 'git-pr-reviewers',
    query: '>request reviewers',
    draft: 'Request reviewers for the current pull request: '
  },
  {
    id: 'git-pr-comment',
    query: '>comment on pull request',
    draft: 'Comment on the current pull request: '
  },
  {
    id: 'git-pr-review-comment',
    query: '>line comment',
    draft: 'Comment on a pull request line: '
  },
  {
    id: 'git-pr-review-reply',
    query: '>inline reply',
    draft: 'Reply to pull request review comment: '
  },
  {
    id: 'git-pr-review-thread',
    query: '>resolve review thread',
    draft: 'Resolve pull request review thread: '
  },
  {
    id: 'git-pr-labels',
    query: '>label pull request',
    draft: 'Label the current pull request: '
  },
  {
    id: 'git-pr-lifecycle',
    query: '>close pull request',
    draft: 'Close or reopen the current pull request: '
  },
  {
    id: 'git-pr-merge',
    query: '>merge pull request',
    draft: 'Merge the current pull request with squash'
  }
];

test('mock harness prepares pull request creation from the command palette', async ({ page }) => {
  await page.goto(harnessURL());

  await clickSidebarTool(page, 'command-palette-button');
  await fillCommandPalette(page, '>create pull request');
  await expect(commandPaletteResult(page, 'git-pr-create')).toBeVisible();
  await expect(commandPaletteResult(page, 'git-pr-fill')).toBeVisible();
  await commandPaletteResult(page, 'git-pr-create').click();

  await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);
  await expect(page.getByLabel('Message')).toHaveValue('Create a pull request titled ');
});

test('mock harness opens a pull request from commits via the command palette', async ({ page }) => {
  await page.goto(harnessURL());

  await clickSidebarTool(page, 'command-palette-button');
  await fillCommandPalette(page, '>pull request from commits');
  await expect(commandPaletteResult(page, 'git-pr-fill')).toBeVisible();
  await commandPaletteResult(page, 'git-pr-fill').click();

  await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.pr.create');
  await expect(page.getByTestId('tool-card-input').last()).toContainText('"fill": true');
  await expect(page.getByTestId('message').last())
    .toContainText('Opened a pull request for the current branch');
});

test('mock harness lists, views, checks, and diffs pull requests from the palette', async ({ page }) => {
  await page.goto(harnessURL());

  await clickSidebarTool(page, 'command-palette-button');
  await fillCommandPalette(page, '>list pull requests');
  await expect(commandPaletteResult(page, 'git-pr-list')).toBeVisible();
  await commandPaletteResult(page, 'git-pr-list').click();

  await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);
  await expect(page.getByTestId('tool-card-title')).toHaveText('host.git.pr.list');
  await expect(page.getByTestId('message').last()).toContainText('Open pull requests');
  await expect(page.getByTestId('tool-card-artifact-label').filter({
    hasText: 'github.com/Lore-Hex/QuillCode/pull/77'
  })).toBeVisible();

  await clickSidebarTool(page, 'command-palette-button');
  await fillCommandPalette(page, '>view pull request');
  await expect(commandPaletteResult(page, 'git-pr-view')).toBeVisible();
  await commandPaletteResult(page, 'git-pr-view').click();

  await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.pr.view');
  await expect(page.getByTestId('message').last()).toContainText('Current pull request');
  await expect(page.getByTestId('tool-card-artifact-label').filter({
    hasText: 'github.com/Lore-Hex/QuillCode/pull/42'
  }).last()).toBeVisible();

  await clickSidebarTool(page, 'command-palette-button');
  await fillCommandPalette(page, '>pr checks');
  await expect(commandPaletteResult(page, 'git-pr-checks')).toBeVisible();
  await commandPaletteResult(page, 'git-pr-checks').click();

  await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.pr.checks');
  await expect(page.getByTestId('message').last()).toContainText('QuillCode Tests');

  await clickSidebarTool(page, 'command-palette-button');
  await fillCommandPalette(page, '>pr diff');
  await expect(commandPaletteResult(page, 'git-pr-diff')).toBeVisible();
  await commandPaletteResult(page, 'git-pr-diff').click();

  await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.pr.diff');
  await expect(page.getByTestId('message').last()).toContainText('PR diff preview from GitHub CLI');
});

test('mock harness covers pull request command visibility and draft actions', async ({ page }) => {
  await page.goto(harnessURL());

  await clickSidebarTool(page, 'command-palette-button');
  await fillCommandPalette(page, '>pull request');
  for (const commandID of pullRequestCommandIDs) {
    await expect(
      commandPaletteResult(page, commandID),
      `${commandID} should be visible in the rendered command palette`
    ).toBeVisible();
  }
  await page.getByTestId('command-palette-close').click();

  for (const command of draftCommands) {
    await clickSidebarTool(page, 'command-palette-button');
    await clickCommandPaletteCommand(page, command.query, command.id);
    await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);
    await expect(
      page.getByLabel('Message'),
      `${command.id} should prepare a focused composer draft`
    ).toHaveValue(command.draft);
    await expect(page.getByLabel('Message')).toBeFocused();
  }
});
