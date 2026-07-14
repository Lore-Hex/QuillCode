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

test('mock harness summarizes opened URL and reviewed file path in tool-card subtitles', async ({ page }) => {
  await page.goto(harnessURL());

  await page.evaluate(() => {
    const harness = window as typeof window & {
      addToolCard: (card: Record<string, unknown>) => void;
      render: () => void;
    };
    // host.browser.open carries the URL it opened; the subtitle should surface it.
    harness.addToolCard({
      title: 'host.browser.open',
      status: 'done',
      inputJSON: JSON.stringify({ url: 'https://example.com/docs' })
    });
    // host.git.pr.review_comment carries the changed file path, like other path tools.
    harness.addToolCard({
      title: 'host.git.pr.review_comment',
      status: 'done',
      inputJSON: JSON.stringify({ path: 'Sources/App.swift', line: 12, body: 'nit' })
    });
    harness.render();
  });

  const subtitles = page.getByTestId('tool-card-subtitle');
  await expect(subtitles.nth(0)).toContainText('https://example.com/docs');
  await expect(subtitles.nth(1)).toContainText('Sources/App.swift');
});

test('mock harness summarizes MCP and Computer Use arguments in tool-card subtitles', async ({ page }) => {
  await page.goto(harnessURL());

  await page.evaluate(() => {
    const harness = window as typeof window & {
      addToolCard: (card: Record<string, unknown>) => void;
      render: () => void;
    };
    harness.addToolCard({
      title: 'host.mcp.call',
      status: 'done',
      inputJSON: JSON.stringify({ serverID: 'fs', toolName: 'list_dir' })
    });
    harness.addToolCard({
      title: 'host.mcp.resource.read',
      status: 'done',
      inputJSON: JSON.stringify({ serverID: 'fs', resourceName: 'README' })
    });
    harness.addToolCard({
      title: 'host.computer.click',
      status: 'done',
      inputJSON: JSON.stringify({ x: 120, y: 340 })
    });
    harness.addToolCard({
      title: 'host.computer.type',
      status: 'done',
      inputJSON: JSON.stringify({ text: 'hello world' })
    });
    harness.render();
  });

  const subtitles = page.getByTestId('tool-card-subtitle');
  await expect(subtitles.nth(0)).toContainText('list_dir');
  await expect(subtitles.nth(1)).toContainText('README');
  await expect(subtitles.nth(2)).toContainText('120, 340');
  await expect(subtitles.nth(3)).toContainText('hello world');
});

test('mock harness shows git review summary for diff flow', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('git diff');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('review-pane')).toBeVisible();
  await expect(page.getByTestId('review-scope')).toHaveCount(5);
  await expect(page.getByTestId('review-scope').filter({ hasText: 'Unstaged' })).toHaveAttribute('aria-pressed', 'true');
  const scopeTops = await page.getByTestId('review-scope').evaluateAll(buttons =>
    buttons.map(button => Math.round(button.getBoundingClientRect().top))
  );
  expect(new Set(scopeTops).size).toBe(1);
  const scopeBounds = await elementRect(page, '[data-testid="review-scope"]:has-text("Unstaged")');
  expect(scopeBounds.width).toBeGreaterThanOrEqual(40);
  expect(scopeBounds.height).toBeGreaterThanOrEqual(40);
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

test('mock harness compares one exact commit with a focused read-only review', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('git diff');
  await page.getByRole('button', { name: 'Send' }).click();
  await page.getByRole('button', { name: 'Commit', exact: true }).click();

  const referenceInput = page.getByTestId('review-reference-input');
  await expect(referenceInput).toBeFocused();
  await expect(referenceInput).toHaveValue('HEAD');
  await expect(page.getByTestId('review-reference-compare')).toBeEnabled();
  const inputBounds = await elementRect(page, '[data-testid="review-reference-input"]');
  const compareBounds = await elementRect(page, '[data-testid="review-reference-compare"]');
  expect(inputBounds.height).toBeGreaterThanOrEqual(40);
  expect(compareBounds.width).toBeGreaterThanOrEqual(40);
  expect(compareBounds.height).toBeGreaterThanOrEqual(40);

  await referenceInput.fill('abc123');
  await page.getByTestId('review-reference-compare').click();

  await expect(page.getByRole('button', { name: 'Commit', exact: true })).toHaveAttribute('aria-pressed', 'true');
  await expect(page.getByTestId('review-reference-input')).toHaveValue('abc123');
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.diff');
  await expect(page.getByTestId('tool-card-input').last()).toContainText('"commit": "abc123"');
  await expect(page.getByTestId('review-file')).toContainText('Sources/App.swift');
  await expect(page.getByTestId('review-action')).toHaveCount(1);
  await expect(page.getByRole('button', { name: 'Open', exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Stage', exact: true })).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Restore', exact: true })).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Stage hunk' })).toHaveCount(0);
});

test('mock harness requires a base branch and dispatches a merge-base comparison', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('git diff');
  await page.getByRole('button', { name: 'Send' }).click();
  await page.getByRole('button', { name: 'Branch', exact: true }).click();

  const referenceInput = page.getByTestId('review-reference-input');
  await expect(referenceInput).toBeFocused();
  await expect(referenceInput).toHaveValue('');
  await expect(page.getByTestId('review-reference-compare')).toBeDisabled();
  await referenceInput.fill('origin/main');
  await expect(page.getByTestId('review-reference-compare')).toBeEnabled();
  await referenceInput.press('Enter');

  await expect(page.getByRole('button', { name: 'Branch', exact: true })).toHaveAttribute('aria-pressed', 'true');
  await expect(page.getByTestId('review-reference-input')).toHaveValue('origin/main');
  await expect(page.getByTestId('tool-card-input').last()).toContainText('"baseBranch": "origin/main"');
  await expect(page.getByTestId('review-file')).toContainText('Sources/App.swift');
  await expect(page.getByTestId('review-action')).toHaveCount(1);
  await expect(page.getByRole('button', { name: 'Unstage', exact: true })).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Unstage hunk' })).toHaveCount(0);
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
  await expect(page.getByTestId('review-action')).toHaveCount(7);

  await page.getByRole('button', { name: 'Stage', exact: true }).click();

  await expect(page.getByTestId('review-pane')).toBeVisible();
  await expect(page.getByTestId('review-empty')).toHaveText('No unstaged changes');
  await expect(page.getByTestId('review-file')).toHaveCount(0);
  await expect(page.getByTestId('agent-status')).toHaveText('Idle');
  await expect(page.getByTestId('tool-card-title')).toHaveText([
    'host.git.diff',
    'host.git.stage',
    'host.git.diff'
  ]);
  await expect(page.getByTestId('tool-card-input').nth(1)).toContainText('Sources/App.swift');
});

test('mock harness switches staged review scope and unstages without discarding the change', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('git diff');
  await page.getByRole('button', { name: 'Send' }).click();
  await page.getByRole('button', { name: 'Stage', exact: true }).click();

  await page.getByRole('button', { name: 'Staged', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Staged', exact: true })).toHaveAttribute('aria-pressed', 'true');
  await expect(page.getByTestId('review-file')).toContainText('Sources/App.swift');
  await expect(page.getByRole('button', { name: 'Unstage', exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Restore', exact: true })).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Unstage hunk' })).toBeVisible();

  await page.getByRole('button', { name: 'Unstage', exact: true }).click();
  await expect(page.getByTestId('review-empty')).toHaveText('No staged changes');
  await expect(page.getByTestId('tool-card-title')).toContainText([
    'host.git.diff',
    'host.git.stage',
    'host.git.diff',
    'host.git.diff',
    'host.git.restore',
    'host.git.diff'
  ]);
  await expect(page.getByTestId('tool-card-input').nth(4)).toContainText('"staged": true');

  await page.getByRole('button', { name: 'Unstaged', exact: true }).click();
  await expect(page.getByTestId('review-file')).toContainText('Sources/App.swift');
});

test('mock harness stages and unstages the whole visible diff with explicit path lists', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('git diff');
  await page.getByRole('button', { name: 'Send' }).click();
  await page.getByRole('button', { name: 'Stage all', exact: true }).click();

  await expect(page.getByTestId('review-empty')).toHaveText('No unstaged changes');
  await expect(page.getByTestId('tool-card-title')).toHaveText([
    'host.git.diff',
    'host.git.stage',
    'host.git.diff'
  ]);
  const stageInput = page.getByTestId('tool-card-input').nth(1);
  await expect(stageInput).toContainText('"paths"');
  await expect(stageInput).toContainText('Sources/App.swift');
  await expect(stageInput).not.toContainText('"path": "."');

  await page.getByRole('button', { name: 'Staged', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Unstage all', exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Unstage all', exact: true }).click();

  await expect(page.getByTestId('review-empty')).toHaveText('No staged changes');
  const unstageInput = page.getByTestId('tool-card-input').nth(4);
  await expect(unstageInput).toContainText('"paths"');
  await expect(unstageInput).toContainText('Sources/App.swift');
  await expect(unstageInput).toContainText('"staged": true');
});

test('mock harness reverts the whole visible unstaged diff without broadening its path set', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('git diff');
  await page.getByRole('button', { name: 'Send' }).click();
  await page.getByRole('button', { name: 'Revert all', exact: true }).click();

  await expect(page.getByTestId('review-empty')).toHaveText('No unstaged changes');
  await expect(page.getByTestId('tool-card-title')).toHaveText([
    'host.git.diff',
    'host.git.restore',
    'host.git.diff'
  ]);
  const restoreInput = page.getByTestId('tool-card-input').nth(1);
  await expect(restoreInput).toContainText('"paths"');
  await expect(restoreInput).toContainText('Sources/App.swift');
  await expect(restoreInput).not.toContainText('"path": "."');
});

test('mock harness reviews and reverts only the latest turn provenance', async ({ page }) => {
  await page.goto(harnessURL());
  await page.evaluate(() => {
    const harness = window as typeof window & {
      __quillCodeTestSetLastTurnPartialProvenance: (enabled: boolean) => void;
    };
    harness.__quillCodeTestSetLastTurnPartialProvenance(true);
  });

  await page.getByLabel('Message').fill('git diff');
  await page.getByRole('button', { name: 'Send' }).click();
  await page.getByRole('button', { name: 'Last turn', exact: true }).click();

  await expect(page.getByRole('button', { name: 'Last turn', exact: true })).toHaveAttribute('aria-pressed', 'true');
  await expect(page.getByTestId('review-reference-form')).toHaveCount(0);
  await expect(page.getByTestId('review-scope-notice')).toContainText('not shown here');
  await expect(page.getByTestId('review-file')).toContainText('Sources/App.swift');
  await expect(page.getByRole('button', { name: 'Open', exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Stage', exact: true })).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Restore', exact: true })).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Revert all', exact: true })).toBeVisible();

  await page.getByRole('button', { name: 'Revert all', exact: true }).click();
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.diff');
  await expect(page.getByTestId('tool-card-title').nth(-2)).toHaveText('host.git.revert_turn');
  await expect(page.getByTestId('agent-status')).toHaveText('Idle');
});

test('mock harness opens a changed file from the review pane without clearing it', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('git diff');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('review-pane')).toBeVisible();

  await page.locator('[data-testid="review-action"][data-action="open"]').first().click();

  // Open SUCCESSFULLY reads the changed file (a completed host.file.read card) ...
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.file.read');
  await expect(page.getByTestId('tool-card-subtitle').last()).toContainText('Completed');
  await expect(page.getByTestId('tool-card-subtitle').last()).toContainText('Sources/App.swift');
  // ... adds no diff refresh ...
  await expect(page.getByTestId('tool-card-title').filter({ hasText: 'host.git.diff' })).toHaveCount(1);
  // ... and the review pane stays open (unlike Stage/Restore which clear it).
  await expect(page.getByTestId('review-pane')).toBeVisible();
});

test('mock harness stages and unstages a single hunk without discarding it', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('git diff');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('review-hunk')).toBeVisible();
  await expect(page.getByTestId('review-hunk-header')).toContainText('@@ -1 +1,2 @@');

  await page.getByRole('button', { name: 'Stage hunk' }).click();

  await expect(page.getByTestId('review-pane')).toBeVisible();
  await expect(page.getByTestId('review-empty')).toHaveText('No unstaged changes');
  await expect(page.getByTestId('tool-card-title')).toHaveText([
    'host.git.diff',
    'host.git.stage_hunk',
    'host.git.diff'
  ]);
  await expect(page.getByTestId('tool-card-input').nth(1)).toContainText('Sources/App.swift');

  await page.getByRole('button', { name: 'Staged', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Unstage hunk' })).toBeVisible();
  await page.getByRole('button', { name: 'Unstage hunk' }).click();

  await expect(page.getByTestId('review-empty')).toHaveText('No staged changes');
  await expect(page.getByTestId('tool-card-title')).toHaveText([
    'host.git.diff',
    'host.git.stage_hunk',
    'host.git.diff',
    'host.git.diff',
    'host.git.unstage_hunk',
    'host.git.diff'
  ]);
  await expect(page.getByTestId('tool-card-input').nth(4)).toContainText('Sources/App.swift');

  await page.getByRole('button', { name: 'Unstaged', exact: true }).click();
  await expect(page.getByTestId('review-hunk')).toBeVisible();
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
