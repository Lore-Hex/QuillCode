import { test, expect, type Page } from '@playwright/test';
import { harnessURL } from './harness-helpers';

async function send(page: Page, text: string) {
  await page.getByLabel('Message').fill(text);
  await page.getByRole('button', { name: 'Send' }).click();
}

test('incremental find highlights the active match and navigates next/prev', async ({ page }) => {
  await page.goto(harnessURL());

  // Plain prompts (no write/read/search keyword) get a fixed reply that does not echo the query,
  // so "zebra" appears in exactly the two user messages.
  await send(page, 'zebra note one');
  await expect(page.getByTestId('message').filter({ hasText: 'zebra note one' })).toBeVisible();
  await send(page, 'zebra note two');

  // Open the in-thread find bar via the command palette entry.
  await page.getByTestId('top-bar-overflow-button').click();
  await page.getByTestId('top-bar-overflow-command-palette').click();
  await page.getByTestId('command-palette-input').fill('find in chat');
  await page.locator('[data-testid="command-palette-result"][data-command-id="find-in-chat"]').first().click();

  await expect(page.getByTestId('find-bar')).toBeVisible();
  await page.getByTestId('find-input').fill('zebra');

  // Two user messages contain "zebra"; status reflects the match count.
  await expect(page.getByTestId('find-status')).toContainText('of 2');

  // Next / previous move the active match with wrap-around (no crash at the ends).
  await page.getByTestId('find-next').click();
  await expect(page.getByTestId('find-status')).toContainText('2 of 2');
  await page.getByTestId('find-next').click();
  await expect(page.getByTestId('find-status')).toContainText('1 of 2');
  await page.getByTestId('find-previous').click();
  await expect(page.getByTestId('find-status')).toContainText('2 of 2');

  // Empty / non-matching queries are handled gracefully.
  await page.getByTestId('find-input').fill('');
  await expect(page.getByTestId('find-status')).toContainText('Type to find');
  await page.getByTestId('find-input').fill('nonexistent-needle');
  await expect(page.getByTestId('find-status')).toContainText('No results');
  await expect(page.getByTestId('find-previous')).toBeDisabled();
  await expect(page.getByTestId('find-next')).toBeDisabled();
});

test('jump bar disables error/diff when absent and jumps to them when present', async ({ page }) => {
  await page.goto(harnessURL());

  // A plain message turn has neither an error nor a diff.
  await send(page, 'just chatting');
  await expect(page.getByTestId('transcript-jump-bar')).toBeVisible();
  await expect(page.getByTestId('transcript-jump-last-error')).toBeDisabled();
  await expect(page.getByTestId('transcript-jump-last-diff')).toBeDisabled();

  // Reading a nonexistent file creates a failed tool card => an error turn.
  await send(page, 'read missing.txt');
  // A file write creates a diff turn; the "Last diff" affordance enables.
  await send(page, 'write hello to a file');

  await expect(page.getByTestId('transcript-jump-last-error')).toBeEnabled();
  await expect(page.getByTestId('transcript-jump-last-diff')).toBeEnabled();

  // The jump targets the most recent matching turn and marks it as the jump target.
  const errorAnchor = await page.getByTestId('transcript-jump-last-error').getAttribute('data-anchor-id');
  expect(errorAnchor).toBeTruthy();
  await page.getByTestId('transcript-jump-last-error').click();
  await expect(page.locator(`[data-timeline-id="${errorAnchor}"]`)).toHaveAttribute('data-jump-target', 'true');

  const diffAnchor = await page.getByTestId('transcript-jump-last-diff').getAttribute('data-anchor-id');
  expect(diffAnchor).toBeTruthy();
  await page.getByTestId('transcript-jump-last-diff').click();
  await expect(page.locator(`[data-timeline-id="${diffAnchor}"]`)).toHaveAttribute('data-jump-target', 'true');
});

test('last diff ignores read-only file tools even though they emit path artifacts', async ({ page }) => {
  await page.goto(harnessURL());

  // Write a file (a real diff), then read it back SUCCESSFULLY. The successful read carries the
  // file's absolute path as an artifact (kind 'file'), but a read is not a diff.
  await send(page, 'write hello to a file');
  const diffAnchorAfterWrite = await page.getByTestId('transcript-jump-last-diff').getAttribute('data-anchor-id');
  expect(diffAnchorAfterWrite).toBeTruthy();

  await send(page, 'read hello.txt');
  // The read produced a tool card with a path artifact...
  await expect(page.getByTestId('tool-card').filter({ hasText: 'host.file.read' })).toBeVisible();

  // ...but "Last diff" must still point at the WRITE, not the later read.
  await expect(page.getByTestId('transcript-jump-last-diff')).toBeEnabled();
  expect(await page.getByTestId('transcript-jump-last-diff').getAttribute('data-anchor-id')).toBe(diffAnchorAfterWrite);
});

test('read-only session keeps the last-diff affordance disabled', async ({ page }) => {
  await page.goto(harnessURL());

  // A session that only reads/lists/searches — none of which are diffs — even though the reads
  // emit path artifacts.
  await send(page, 'list files here');
  await send(page, 'find whoami in the project');
  await send(page, 'read README.md');

  await expect(page.getByTestId('transcript-jump-bar')).toBeVisible();
  await expect(page.getByTestId('transcript-jump-last-diff')).toBeDisabled();
});

test('N new turns pill appears on return to a thread that grew and jumps to the first unseen turn', async ({ page }) => {
  await page.goto(harnessURL());

  // Thread A.
  await send(page, 'thread A first');
  await expect(page.getByTestId('top-bar-title')).toHaveText('thread A first');
  // No pill while actively viewing the current thread.
  await expect(page.getByTestId('transcript-new-turns-pill')).toHaveCount(0);

  // Create thread B and grow thread A in the background (A is now unselected + marked seen).
  await page.getByTestId('new-chat-button').click();
  await send(page, 'grow other thread please');
  await expect(page.getByTestId('top-bar-title')).toHaveText('grow other thread please');

  // Return to thread A: it grew by one turn since we last saw it, so the pill shows.
  await page.getByTestId('sidebar-item').filter({ hasText: 'thread A first' }).click();
  const pill = page.getByTestId('transcript-new-turns-pill');
  await expect(pill).toBeVisible();
  await expect(pill).toHaveText('1 new turn');

  const firstUnseen = await pill.getAttribute('data-first-unseen-id');
  expect(firstUnseen).toBeTruthy();

  // Tapping the pill jumps to the first unseen turn and clears the pill (caught up).
  await pill.click();
  await expect(page.locator(`[data-timeline-id="${firstUnseen}"]`)).toHaveAttribute('data-jump-target', 'true');
  await expect(page.getByTestId('transcript-new-turns-pill')).toHaveCount(0);
});
