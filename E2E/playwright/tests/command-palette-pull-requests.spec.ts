import { test, expect } from '@playwright/test';
import {
  clickCommandPaletteCommand,
  clickSidebarTool,
  commandPaletteResult,
  fillCommandPalette,
  harnessURL
} from './harness-helpers';

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
  await expect(page.getByTestId('message').last()).toContainText(
    'Opened a pull request for the current branch'
  );
});

test('mock harness views pull request details, checks, and diff from the command palette', async ({ page }) => {
  await page.goto(harnessURL());

  await clickSidebarTool(page, 'command-palette-button');
  await fillCommandPalette(page, '>view pull request');
  await expect(commandPaletteResult(page, 'git-pr-view')).toBeVisible();
  await commandPaletteResult(page, 'git-pr-view').click();

  await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);
  await expect(page.getByTestId('tool-card-title')).toHaveText('host.git.pr.view');
  await expect(page.getByTestId('message').last()).toContainText('Current pull request');
  await expect(page.getByTestId('tool-card-artifact-label')).toContainText(
    'github.com/Lore-Hex/QuillCode/pull/42'
  );

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

test('mock harness covers the full pull request command family from the command palette', async ({ page }) => {
  await page.goto(harnessURL());

  const pullRequestCommandIDs = [
    'git-pr-create',
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
    'git-pr-merge'
  ];

  await clickSidebarTool(page, 'command-palette-button');
  await fillCommandPalette(page, '>pull request');
  for (const commandID of pullRequestCommandIDs) {
    await expect(
      commandPaletteResult(page, commandID),
      `${commandID} should be visible in the rendered command palette`
    ).toBeVisible();
  }
  await page.getByTestId('command-palette-close').click();

  const draftCommands = [
    { id: 'git-pr-checkout', query: '>checkout pull request', draft: 'Checkout pull request ' },
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
      id: 'git-pr-merge',
      query: '>merge pull request',
      draft: 'Merge the current pull request with squash'
    }
  ];

  for (const command of draftCommands) {
    await clickSidebarTool(page, 'command-palette-button');
    await clickCommandPaletteCommand(page, command.query, command.id);
    await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);
    await expect(page.getByLabel('Message'), `${command.id} should prepare a draft`).toHaveValue(
      command.draft
    );
    await expect(page.getByLabel('Message')).toBeFocused();
  }

  await clickSidebarTool(page, 'command-palette-button');
  await clickCommandPaletteCommand(page, '>review diff', 'git-diff');
  await expect(page.getByTestId('review-pane')).toBeVisible();

  const firstLineCommentForm = page.getByTestId('review-line-comment-form').first();
  await firstLineCommentForm.getByTestId('review-line-comment-input').fill('Cover this new line.');
  await firstLineCommentForm.getByRole('button', { name: 'Add' }).click();
  await expect(page.getByTestId('review-line-comment')).toContainText('Cover this new line.');

  const secondLineCommentForm = page.getByTestId('review-line-comment-form').nth(1);
  await secondLineCommentForm.getByTestId('review-line-comment-input').fill('Skip this draft note.');
  await secondLineCommentForm.getByRole('button', { name: 'Add' }).click();
  await expect(page.getByTestId('review-line-comment').nth(1)).toContainText('Skip this draft note.');

  await clickSidebarTool(page, 'command-palette-button');
  await clickCommandPaletteCommand(page, '>approve pr', 'git-pr-review');
  await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);
  await expect(page.getByTestId('review-pane')).toBeVisible();
  await expect(page.getByTestId('pr-review-draft')).toBeVisible();
  await expect(page.getByTestId('review-summary')).toHaveText('Submit approve review with 2 inline notes');
  await expect(page.getByTestId('pr-review-draft-summary')).toHaveAttribute('data-status', 'ready');
  await expect(page.getByTestId('pr-review-draft-summary-title')).toHaveText('Ready to submit');
  await expect(page.getByTestId('pr-review-draft-summary-detail')).toHaveText(
    'Approve review for current pull request'
  );
  await expect(page.getByTestId('pr-review-draft-summary')).toContainText('Inline notes: 2 selected');
  await expect(page.getByTestId('pr-review-draft-include-inline-comments')).toBeChecked();
  await expect(page.getByTestId('pr-review-draft-inline-comment')).toHaveCount(2);
  await expect(page.getByTestId('pr-review-draft-inline-comment').first()).toContainText(
    'Sources/App.swift:1'
  );
  await expect(page.getByTestId('pr-review-draft-inline-comment').first()).toContainText(
    'Cover this new line.'
  );
  await expect(page.getByTestId('pr-review-draft-inline-comment-move-up').first()).toBeDisabled();
  await page.getByTestId('pr-review-draft-inline-comment-move-down').first().click();
  await expect(page.getByTestId('pr-review-draft-inline-comment').first()).toContainText(
    'Skip this draft note.'
  );
  await expect(page.getByTestId('pr-review-draft-inline-comment-move-up').first()).toBeDisabled();
  await expect(page.getByTestId('pr-review-draft-inline-comment-move-down').first()).toBeEnabled();
  await page.getByTestId('pr-review-draft-inline-comment-body').first().fill('');
  await expect(page.getByTestId('pr-review-draft-inline-comment-warning').first()).toBeVisible();
  await expect(page.getByTestId('pr-review-draft-summary')).toHaveAttribute('data-status', 'blocked');
  await expect(page.getByTestId('pr-review-draft-summary-title')).toHaveText('Needs attention');
  await expect(page.getByTestId('pr-review-draft-summary')).toContainText(
    '1 selected inline note needs text'
  );
  await expect(page.getByTestId('pr-review-draft-submit')).toBeDisabled();
  await page.getByTestId('pr-review-draft-inline-comment-body').first().fill('Skip this edited line.');
  await page.getByTestId('pr-review-draft-inline-comment-toggle').nth(1).click();
  await expect(page.getByTestId('review-summary')).toHaveText(
    'Submit approve review with 1 of 2 inline notes'
  );
  await expect(page.getByTestId('pr-review-draft-summary')).toHaveAttribute('data-status', 'ready');
  await expect(page.getByTestId('pr-review-draft-summary')).toContainText(
    'Inline notes: 1 selected, 1 skipped'
  );
  await page.getByTestId('pr-review-draft-action').selectOption('request_changes');
  await page.getByTestId('pr-review-draft-selector').fill('123');
  await expect(page.getByTestId('pr-review-draft-submit')).toBeDisabled();
  await expect(page.getByTestId('pr-review-draft-summary')).toHaveAttribute('data-status', 'blocked');
  await expect(page.getByTestId('pr-review-draft-summary-detail')).toHaveText(
    'Resolve required fields before submitting'
  );
  await expect(page.getByTestId('pr-review-draft-summary')).toContainText('Body: required');
  await page.getByTestId('pr-review-draft-body').fill('Please add a regression test.');
  await expect(page.getByTestId('pr-review-draft-submit')).toBeEnabled();
  await expect(page.getByTestId('pr-review-draft-summary')).toHaveAttribute('data-status', 'ready');
  await expect(page.getByTestId('pr-review-draft-summary-detail')).toHaveText(
    'Request changes review for PR 123'
  );
  await expect(page.getByTestId('pr-review-draft-summary')).toContainText('Body: ready');
  await page.getByTestId('pr-review-draft-submit').click();
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.pr.review');

  const inlineReviewCommentCard = page
    .getByTestId('tool-card')
    .filter({ hasText: 'host.git.pr.review_comment' })
    .last();
  await expect(inlineReviewCommentCard).toContainText('"path": "Sources/App.swift"');
  await expect(inlineReviewCommentCard).toContainText('"body": "Skip this edited line."');
  await expect(page.getByTestId('tool-card').filter({ hasText: 'host.git.pr.review_comment' }))
    .toHaveCount(1);
  await expect(page.getByTestId('tool-card').last()).toContainText('"action": "request_changes"');
  await expect(page.getByTestId('tool-card').last()).toContainText('"selector": "123"');
  await expect(page.getByTestId('message').last()).toContainText(
    'Pull request review submitted: request changes with 1 inline note.'
  );

  await clickSidebarTool(page, 'command-palette-button');
  await clickCommandPaletteCommand(page, '>review threads', 'git-pr-review-threads');

  await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.pr.review_threads');
  await expect(page.getByTestId('review-pane')).toBeVisible();
  await expect(page.getByTestId('pr-review-thread')).toHaveCount(2);
  await expect(page.getByTestId('message').last()).toContainText(
    'Found 2 review threads: 1 unresolved, 1 resolved.'
  );
});
