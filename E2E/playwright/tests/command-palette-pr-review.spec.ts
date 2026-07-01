import { test, expect, type Page } from '@playwright/test';
import {
  clickCommandPaletteCommand,
  expectCommandPaletteClosed,
  harnessURL,
  openCommandPalette
} from './harness-helpers';

test.beforeEach(async ({ page }) => {
  await page.goto(harnessURL());
});

async function openReviewCommand(page: Page, query: string, commandID: string) {
  await openCommandPalette(page);
  await clickCommandPaletteCommand(page, query, commandID);
}

async function addLineComment(page: Page, index: number, body: string) {
  const lineCommentForm = page.getByTestId('review-line-comment-form').nth(index);
  await lineCommentForm.getByTestId('review-line-comment-input').fill(body);
  await lineCommentForm.getByRole('button', { name: 'Add' }).click();
  await expect(page.getByTestId('review-line-comment').nth(index)).toContainText(body);
}

async function expectDraftSummary(page: Page, status: string, title: string, detail?: string) {
  const summary = page.getByTestId('pr-review-draft-summary');
  await expect(summary).toHaveAttribute('data-status', status);
  await expect(page.getByTestId('pr-review-draft-summary-title')).toHaveText(title);
  if (detail) {
    await expect(page.getByTestId('pr-review-draft-summary-detail')).toHaveText(detail);
  }
}

test('mock harness submits pull request review with inline notes from the palette', async ({ page }) => {
  await openReviewCommand(page, '>review diff', 'git-diff');
  await expect(page.getByTestId('review-pane')).toBeVisible();

  await addLineComment(page, 0, 'Cover this new line.');
  await addLineComment(page, 1, 'Skip this draft note.');

  await openReviewCommand(page, '>approve pr', 'git-pr-review');
  await expectCommandPaletteClosed(page);
  await expect(page.getByTestId('review-pane')).toBeVisible();
  await expect(page.getByTestId('pr-review-draft')).toBeVisible();
  await expect(page.getByTestId('review-summary')).toHaveText('Submit approve review with 2 inline notes');
  await expectDraftSummary(page, 'ready', 'Ready to submit', 'Approve review for current pull request');
  await expect(page.getByTestId('pr-review-draft-summary')).toContainText('Inline notes: 2 selected');
  await expect(page.getByTestId('pr-review-draft-include-inline-comments')).toBeChecked();
  await expect(page.getByTestId('pr-review-draft-inline-comment')).toHaveCount(2);
  await expect(page.getByTestId('pr-review-draft-inline-comment').first())
    .toContainText('Sources/App.swift:1');
  await expect(page.getByTestId('pr-review-draft-inline-comment').first())
    .toContainText('Cover this new line.');
  await expect(page.getByTestId('pr-review-draft-inline-comment-move-up').first()).toBeDisabled();

  await page.getByTestId('pr-review-draft-inline-comment-move-down').first().click();
  await expect(page.getByTestId('pr-review-draft-inline-comment').first())
    .toContainText('Skip this draft note.');
  await expect(page.getByTestId('pr-review-draft-inline-comment-move-up').first()).toBeDisabled();
  await expect(page.getByTestId('pr-review-draft-inline-comment-move-down').first()).toBeEnabled();

  await page.getByTestId('pr-review-draft-inline-comment-body').first().fill('');
  await expect(page.getByTestId('pr-review-draft-inline-comment-warning').first()).toBeVisible();
  await expectDraftSummary(page, 'blocked', 'Needs attention');
  await expect(page.getByTestId('pr-review-draft-summary')).toContainText('1 selected inline note needs text');
  await expect(page.getByTestId('pr-review-draft-submit')).toBeDisabled();

  await page.getByTestId('pr-review-draft-inline-comment-body').first().fill('Skip this edited line.');
  await page.getByTestId('pr-review-draft-inline-comment-toggle').nth(1).click();
  await expect(page.getByTestId('review-summary')).toHaveText('Submit approve review with 1 of 2 inline notes');
  await expect(page.getByTestId('pr-review-draft-summary')).toHaveAttribute('data-status', 'ready');
  await expect(page.getByTestId('pr-review-draft-summary')).toContainText('Inline notes: 1 selected, 1 skipped');

  await page.getByTestId('pr-review-draft-action').selectOption('request_changes');
  await page.getByTestId('pr-review-draft-selector').fill('123');
  await expect(page.getByTestId('pr-review-draft-submit')).toBeDisabled();
  await expectDraftSummary(page, 'blocked', 'Needs attention', 'Resolve required fields before submitting');
  await expect(page.getByTestId('pr-review-draft-summary')).toContainText('Body: required');

  await page.getByTestId('pr-review-draft-body').fill('Please add a regression test.');
  await expect(page.getByTestId('pr-review-draft-submit')).toBeEnabled();
  await expectDraftSummary(page, 'ready', 'Ready to submit', 'Request changes review for PR 123');
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
  await expect(page.getByTestId('message').last())
    .toContainText('Pull request review submitted: request changes with 1 inline note.');
});

test('mock harness lists pull request review threads from the command palette', async ({ page }) => {
  await openReviewCommand(page, '>review threads', 'git-pr-review-threads');

  await expectCommandPaletteClosed(page);
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.pr.review_threads');
  await expect(page.getByTestId('review-pane')).toBeVisible();
  await expect(page.getByTestId('pr-review-thread')).toHaveCount(2);
  await expect(page.getByTestId('message').last()).toContainText('Found 2 review threads: 1 unresolved, 1 resolved.');
});
