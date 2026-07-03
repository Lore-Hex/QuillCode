import { test, expect } from '@playwright/test';
import { harnessURL } from './harness-helpers';

// The follow-up queue: a composer submission DURING a live run enqueues as a visible chip
// (the composer never locks) and drains at the next turn boundary.

test('submitting during a live run enqueues a follow-up chip instead of locking', async ({ page }) => {
  await page.goto(harnessURL());

  // Start a long-running turn so the composer stays "sending".
  await page.getByLabel('Message').fill('slow task');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('agent-status')).toHaveText('Running');

  // The composer is NOT locked: type a follow-up and press Enter — it queues rather than starting.
  await page.getByLabel('Message').fill('follow-up one');
  await page.getByLabel('Message').press('Enter');

  await expect(page.getByTestId('composer-followup-queue')).toBeVisible();
  await expect(page.getByTestId('composer-followup-chip')).toHaveCount(1);
  await expect(page.getByTestId('composer-followup-text').first()).toHaveText('follow-up one');
  // The queued submission did not start a new user turn and the draft cleared.
  await expect(page.getByLabel('Message')).toHaveValue('');
  await expect(page.getByTestId('agent-status')).toHaveText('Running');
});

test('queued follow-ups can be deleted before they drain', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('slow task');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('agent-status')).toHaveText('Running');

  await page.getByLabel('Message').fill('keep me');
  await page.getByLabel('Message').press('Enter');
  await page.getByLabel('Message').fill('delete me');
  await page.getByLabel('Message').press('Enter');
  await expect(page.getByTestId('composer-followup-chip')).toHaveCount(2);

  // Delete the second chip via its delete affordance.
  await page.getByTestId('composer-followup-chip')
    .filter({ hasText: 'delete me' })
    .getByTestId('composer-followup-delete')
    .click();

  await expect(page.getByTestId('composer-followup-chip')).toHaveCount(1);
  await expect(page.getByTestId('composer-followup-text').first()).toHaveText('keep me');
});

test('a queued follow-up drains as the next turn when the run completes', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('slow task');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('agent-status')).toHaveText('Running');

  await page.getByLabel('Message').fill('drained follow-up');
  await page.getByLabel('Message').press('Enter');
  await expect(page.getByTestId('composer-followup-chip')).toHaveCount(1);

  // When the slow task finishes, the queued item becomes the next user turn and the chip clears.
  await expect(page.getByTestId('message').filter({ hasText: 'drained follow-up' })).toHaveCount(1, {
    timeout: 5000
  });
  await expect(page.getByTestId('composer-followup-queue')).toHaveCount(0);
});

test('a deleted follow-up is never sent as a turn', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('slow task');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('agent-status')).toHaveText('Running');

  await page.getByLabel('Message').fill('doomed follow-up');
  await page.getByLabel('Message').press('Enter');
  await expect(page.getByTestId('composer-followup-chip')).toHaveCount(1);

  await page.getByTestId('composer-followup-delete').click();
  await expect(page.getByTestId('composer-followup-chip')).toHaveCount(0);

  // Let the run finish; the deleted item must not have become a user turn.
  await expect(page.getByText('Long-running task completed.')).toBeVisible({ timeout: 5000 });
  await expect(page.getByTestId('message').filter({ hasText: 'doomed follow-up' })).toHaveCount(0);
});
