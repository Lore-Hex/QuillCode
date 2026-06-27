import { test, expect } from '@playwright/test';
import { elementRect, harnessURL } from './harness-helpers';

test('mock harness exposes actionable approval buttons on review cards', async ({ page }) => {
  await page.goto(harnessURL());

  await page.evaluate(() => {
    const harness = window as typeof window & {
      addToolCard: (card: Record<string, unknown>) => void;
      render: () => void;
    };
    harness.addToolCard({
      id: 'shell-review',
      title: 'host.shell.run',
      subtitle: 'Ready to run · whoami',
      status: 'review',
      reviewState: 'ready',
      density: 'peek',
      inputJSON: JSON.stringify({ cmd: 'whoami' }, null, 2),
      isExpanded: false,
      actions: [
        {
          id: 'tool-card-action-approve-approval-1',
          title: 'Run',
          kind: 'approve',
          requestID: 'approval-1',
          style: 'primary'
        },
        {
          id: 'tool-card-action-deny-approval-1',
          title: 'Skip',
          kind: 'deny',
          requestID: 'approval-1',
          style: 'secondary'
        }
      ]
    });
    harness.render();
  });

  await expect(page.getByTestId('tool-card')).toHaveCount(1);
  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-status', 'review');
  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-review-state', 'ready');
  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-density', 'peek');
  await expect(page.getByTestId('tool-card-status')).toHaveText('Ready');
  await expect(page.getByTestId('tool-card-actions')).toBeVisible();
  await expect(page.getByTestId('tool-card-input')).not.toBeVisible();
  await expect(page.getByTestId('tool-card-copy')).not.toBeVisible();
  await expect(page.getByTestId('tool-card-action').filter({ hasText: 'Run' })).toBeVisible();
  await expect(page.getByTestId('tool-card-action').filter({ hasText: 'Skip' })).toBeVisible();
  const runBounds = await elementRect(page, '[data-testid="tool-card-action"]:has-text("Run")');
  const skipBounds = await elementRect(page, '[data-testid="tool-card-action"]:has-text("Skip")');
  expect(runBounds.width).toBeGreaterThan(skipBounds.width);
  await page.getByTestId('tool-card-details').locator('summary').click();
  await expect(page.getByTestId('tool-card-input')).toBeVisible();
  await expect(page.getByTestId('tool-card-copy')).toBeVisible();
  await expect(page.getByTestId('tool-card-copy')).toHaveText('Copy input');

  await page.getByTestId('tool-card-action').filter({ hasText: 'Run' }).click();

  await expect(page.getByTestId('tool-card')).toHaveCount(2);
  await expect(page.getByTestId('tool-card').first()).toHaveAttribute('data-status', 'done');
  await expect(page.getByTestId('tool-card-subtitle').first()).toHaveText('Approved · whoami');
  await expect(page.getByTestId('tool-card-actions')).toHaveCount(0);
  await expect(page.getByTestId('tool-card').nth(1)).toHaveAttribute('data-status', 'done');
  await expect(page.getByTestId('tool-card-output').last()).toContainText('mock-user');
  await expect(page.getByTestId('message').last()).toContainText('Approved and ran the tool.');
});

test('mock harness shows denied review cards as needs review without actions', async ({ page }) => {
  await page.goto(harnessURL());

  await page.evaluate(() => {
    const harness = window as typeof window & {
      addToolCard: (card: Record<string, unknown>) => void;
      render: () => void;
    };
    harness.addToolCard({
      id: 'shell-blocked-review',
      title: 'host.shell.run',
      subtitle: 'Blocked · rm -rf /',
      status: 'review',
      reviewState: 'needsReview',
      density: 'expanded',
      inputJSON: JSON.stringify({ cmd: 'rm -rf /' }, null, 2),
      isExpanded: true,
      actions: []
    });
    harness.render();
  });

  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-status', 'review');
  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-review-state', 'needsReview');
  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-status-label', 'Needs review');
  await expect(page.getByTestId('tool-card-status')).toHaveText('Needs review');
  await expect(page.getByTestId('tool-card-action')).toHaveCount(0);
});

test('mock harness shows git review summary for diff flow', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('git diff');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('review-pane')).toBeVisible();
  await expect(page.getByTestId('review-summary')).toHaveText('1 file changed, +1 -0');
  await expect(page.getByTestId('review-file')).toContainText('Sources/App.swift');
  await expect(page.getByTestId('review-line')).toHaveCount(2);
  await expect(page.getByTestId('review-line').first()).toContainText('let title = "QuillCode"');
  await expect(page.getByTestId('tool-card-title')).toHaveText('host.git.diff');
  await expect(page.getByTestId('tool-card-output')).toContainText('diff --git');

  await page.getByLabel('Review note for Sources/App.swift').fill('Check the exported symbol name');
  await page.getByRole('button', { name: 'Add note' }).click();
  await expect(page.getByTestId('review-comment')).toContainText('Check the exported symbol name');

  await page.getByLabel('Line note for Sources/App.swift:1').fill('This is a useful exported constant');
  await page.getByTestId('review-line-comment-form').first().getByRole('button', { name: 'Add' }).click();
  await expect(page.getByTestId('review-line-comment')).toContainText('This is a useful exported constant');

  await page.getByLabel('Range note for Sources/App.swift').fill('Keep the title adjacent to the import');
  await page.getByTestId('review-range-comment-form').getByRole('button', { name: 'Add range note' }).click();
  const rangeComment = page.getByTestId('review-line-comment').filter({ hasText: 'Lines 1-2' });
  await expect(rangeComment).toContainText('Keep the title adjacent to the import');
});

test('mock harness flows apply patch into review diff', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('apply patch to edit file');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('review-pane')).toBeVisible();
  await expect(page.getByTestId('review-summary')).toHaveText('1 file changed, +1 -0');
  await expect(page.getByTestId('review-line').first()).toContainText('let title = "QuillCode"');
  await expect(page.getByTestId('tool-card-title')).toHaveText([
    'host.apply_patch',
    'host.git.diff'
  ]);
  await expect(page.getByText('Patch applied. Review the resulting diff below.')).toBeVisible();
});

test('mock harness stages a changed file from the review pane', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('git diff');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('review-pane')).toBeVisible();
  await expect(page.getByTestId('review-action')).toHaveCount(4);

  await page.getByRole('button', { name: 'Stage', exact: true }).click();

  await expect(page.getByTestId('review-pane')).toHaveCount(0);
  await expect(page.getByTestId('agent-status')).toHaveText('Idle');
  await expect(page.getByTestId('tool-card-title')).toHaveText([
    'host.git.diff',
    'host.git.stage',
    'host.git.diff'
  ]);
  await expect(page.getByTestId('tool-card-input').nth(1)).toContainText('Sources/App.swift');
});

test('mock harness stages a single hunk from the review pane', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('git diff');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('review-hunk')).toBeVisible();
  await expect(page.getByTestId('review-hunk-header')).toContainText('@@ -1 +1,2 @@');

  await page.getByRole('button', { name: 'Stage hunk' }).click();

  await expect(page.getByTestId('review-pane')).toHaveCount(0);
  await expect(page.getByTestId('tool-card-title')).toHaveText([
    'host.git.diff',
    'host.git.stage_hunk',
    'host.git.diff'
  ]);
  await expect(page.getByTestId('tool-card-input').nth(1)).toContainText('Sources/App.swift');
});

test('mock harness browses and resolves pull request review threads', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('/pr review-threads 123');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('review-pane')).toBeVisible();
  await expect(page.getByTestId('review-summary')).toHaveText('2 review threads, 1 unresolved, 1 resolved');
  await expect(page.getByTestId('review-badge')).toHaveText('2 threads');
  await expect(page.getByTestId('pr-review-threads')).toBeVisible();
  await expect(page.getByTestId('pr-review-thread')).toHaveCount(2);
  await expect(page.getByTestId('pr-review-thread').first()).toContainText('Sources/App.swift:42');
  await expect(page.getByTestId('pr-review-thread-comment').first()).toContainText('Please extract this branch');
  await expect(page.getByTestId('pr-review-thread-reply').first()).toHaveText('Reply');
  await expect(page.getByTestId('pr-review-thread-action').first()).toHaveText('Resolve');

  const replyBounds = await elementRect(page, '[data-testid="pr-review-thread-reply"]:has-text("Reply")');
  expect(replyBounds.width).toBeGreaterThanOrEqual(40);
  expect(replyBounds.height).toBeGreaterThanOrEqual(40);
  const resolveBounds = await elementRect(page, '[data-testid="pr-review-thread-action"]:has-text("Resolve")');
  expect(resolveBounds.width).toBeGreaterThanOrEqual(40);
  expect(resolveBounds.height).toBeGreaterThanOrEqual(40);

  await page.getByTestId('pr-review-thread-reply').first().click();
  await expect(page.getByTestId('pr-review-thread-reply-form').first()).toBeVisible();
  await expect(page.getByTestId('pr-review-thread-reply-input').first()).toBeFocused();

  const replyInputBounds = await elementRect(page, '[data-testid="pr-review-thread-reply-input"]');
  expect(replyInputBounds.height).toBeGreaterThanOrEqual(40);
  const cancelBounds = await elementRect(page, '[data-testid="pr-review-thread-reply-cancel"]');
  expect(cancelBounds.width).toBeGreaterThanOrEqual(40);
  expect(cancelBounds.height).toBeGreaterThanOrEqual(40);
  const postBounds = await elementRect(page, '[data-testid="pr-review-thread-reply-submit"]');
  expect(postBounds.width).toBeGreaterThanOrEqual(40);
  expect(postBounds.height).toBeGreaterThanOrEqual(40);

  await page.getByTestId('pr-review-thread-reply-input').first().fill('Thanks, fixed in the follow-up.');
  await page.getByTestId('pr-review-thread-reply-submit').first().click();

  await expect(page.getByTestId('tool-card-title')).toContainText([
    'host.git.pr.review_threads',
    'host.git.pr.review_reply',
    'host.git.pr.review_threads'
  ]);
  await expect(page.getByTestId('tool-card-input').nth(1)).toContainText('"commentId": 171');
  await expect(page.getByTestId('tool-card-input').nth(1)).toContainText('Thanks, fixed in the follow-up.');
  await expect(page.getByText('Replied to review comment 171.')).toBeVisible();

  await page.getByTestId('pr-review-thread-action').first().click();

  await expect(page.getByTestId('tool-card-title')).toContainText([
    'host.git.pr.review_threads',
    'host.git.pr.review_reply',
    'host.git.pr.review_threads',
    'host.git.pr.review_thread',
    'host.git.pr.review_threads'
  ]);
  await expect(page.getByTestId('tool-card-input').nth(3)).toContainText('PRRT_kwDOExample001');
  await expect(page.getByTestId('pr-review-thread-status').first()).toContainText('Resolved');
  await expect(page.getByTestId('pr-review-thread-action').first()).toHaveText('Unresolve');
  await expect(page.getByText('Resolved review thread PRRT_kwDOExample001.')).toBeVisible();
});

test('mock harness commits staged changes in one turn', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('commit these changes with message Add hello file');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.git.commit');
  await expect(page.getByTestId('tool-card-input')).toContainText('Add hello file');
  await expect(page.getByTestId('tool-card-output')).toContainText('[main abc1234] Add hello file');
  await expect(page.getByText('Output:\n[main abc1234] Add hello file')).toBeVisible();
});
