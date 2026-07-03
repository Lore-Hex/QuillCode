import { test, expect, type Page } from '@playwright/test';
import { harnessURL } from './harness-helpers';

// Morning-triage inbox (issue #877): the Attention section + j/k/Enter/a/d triage + return digest.
// The harness has no external state injection, so we seed threads with verdict stamps through the
// dedicated test hook, then drive the section entirely through real keyboard + click interactions.

type Spec = {
  id: string;
  title: string;
  verdict: 'red' | 'unverified' | 'verified';
  summary?: string;
  unseenCount?: number;
  reasons?: string[];
  outcome?: string;
  triageState?: 'pending' | 'acknowledged' | 'dismissed';
};

async function seedAttention(page: Page, specs: Spec[]) {
  await page.evaluate(specs => {
    (window as unknown as { __quillCodeTestSeedAttentionThreads: (s: Spec[]) => void })
      .__quillCodeTestSeedAttentionThreads(specs);
  }, specs);
}

function attentionRow(page: Page, threadID: string) {
  return page.locator(`[data-testid="attention-row"][data-thread-id="${threadID}"]`);
}

test('Attention section ranks by severity and shows verdict + unseen count', async ({ page }) => {
  await page.goto(harnessURL());
  await seedAttention(page, [
    { id: 't-yellow', title: 'unverified run', verdict: 'unverified', unseenCount: 1 },
    { id: 't-red', title: 'red run', verdict: 'red', unseenCount: 3 },
    { id: 't-clean', title: 'clean run', verdict: 'verified' }
  ]);

  const section = page.getByTestId('attention-section');
  await expect(section).toBeVisible();
  // Only the RED and UNVERIFIED threads appear; verified is excluded.
  const rows = page.getByTestId('attention-row');
  await expect(rows).toHaveCount(2);
  // RED is ranked first.
  await expect(rows.nth(0)).toHaveAttribute('data-verdict', 'red');
  await expect(rows.nth(1)).toHaveAttribute('data-verdict', 'unverified');
  await expect(attentionRow(page, 't-red').getByTestId('attention-verdict')).toHaveText('RED');
  await expect(attentionRow(page, 't-red').getByTestId('attention-unseen')).toHaveText('3 new');
  await expect(attentionRow(page, 't-yellow').getByTestId('attention-unseen')).toHaveText('1 new');
});

test('j/k move the triage cursor and clamp at the ends', async ({ page }) => {
  await page.goto(harnessURL());
  await seedAttention(page, [
    { id: 't-red-a', title: 'red a', verdict: 'red' },
    { id: 't-red-b', title: 'red b', verdict: 'red' },
    { id: 't-yellow', title: 'yellow', verdict: 'unverified' }
  ]);

  // First row is the cursor initially.
  await expect(attentionRow(page, 't-red-a')).toHaveAttribute('data-cursor', 'true');

  await page.keyboard.press('j');
  await expect(attentionRow(page, 't-red-b')).toHaveAttribute('data-cursor', 'true');
  await page.keyboard.press('j');
  await expect(attentionRow(page, 't-yellow')).toHaveAttribute('data-cursor', 'true');
  // Clamp at the last row — no wrap.
  await page.keyboard.press('j');
  await expect(attentionRow(page, 't-yellow')).toHaveAttribute('data-cursor', 'true');

  await page.keyboard.press('k');
  await expect(attentionRow(page, 't-red-b')).toHaveAttribute('data-cursor', 'true');
  await page.keyboard.press('k');
  await expect(attentionRow(page, 't-red-a')).toHaveAttribute('data-cursor', 'true');
  // Clamp at the first row.
  await page.keyboard.press('k');
  await expect(attentionRow(page, 't-red-a')).toHaveAttribute('data-cursor', 'true');
});

// Regression (fail-on-revert) for the "cursoring zeroes passed-over badges" MAJOR: moving the j/k
// preview cursor across threads must NOT advance any thread's watermark, so their unseen-turn badges
// survive. The badge must clear ONLY when the thread is genuinely opened (and then left). The harness
// unseen count is watermark-derived, so a regression here (cursor → selectThread → mark-seen) would zero
// the badge and fail this test.
test('moving the j/k cursor never clears the passed-over threads unseen badges', async ({ page }) => {
  await page.goto(harnessURL());
  await seedAttention(page, [
    { id: 't-a', title: 'red a', verdict: 'red', unseenCount: 2 },
    { id: 't-b', title: 'red b', verdict: 'red', unseenCount: 3 },
    { id: 't-c', title: 'red c', verdict: 'red', unseenCount: 4 }
  ]);
  // All three show their seeded unseen badges.
  await expect(attentionRow(page, 't-a').getByTestId('attention-unseen')).toHaveText('2 new');
  await expect(attentionRow(page, 't-b').getByTestId('attention-unseen')).toHaveText('3 new');
  await expect(attentionRow(page, 't-c').getByTestId('attention-unseen')).toHaveText('4 new');

  // Scroll the cursor all the way down and back up — pure preview, nothing read.
  await page.keyboard.press('j'); // a -> b
  await page.keyboard.press('j'); // b -> c
  await page.keyboard.press('k'); // c -> b
  await page.keyboard.press('k'); // b -> a
  await expect(attentionRow(page, 't-a')).toHaveAttribute('data-cursor', 'true');

  // Every badge is UNCHANGED — cursoring read nothing.
  await expect(attentionRow(page, 't-a').getByTestId('attention-unseen')).toHaveText('2 new');
  await expect(attentionRow(page, 't-b').getByTestId('attention-unseen')).toHaveText('3 new');
  await expect(attentionRow(page, 't-c').getByTestId('attention-unseen')).toHaveText('4 new');
});

test('opening a thread then leaving it clears only that thread badge', async ({ page }) => {
  await page.goto(harnessURL());
  await seedAttention(page, [
    { id: 't-a', title: 'red a', verdict: 'red', unseenCount: 2 },
    { id: 't-b', title: 'red b', verdict: 'red', unseenCount: 3 }
  ]);
  // Open A's digest (a genuine read of A). Its own badge stays until we leave it; B is untouched.
  await attentionRow(page, 't-a').click();
  await expect(page.getByTestId('attention-digest')).toBeVisible();
  await page.getByTestId('attention-digest-close').click();
  await expect(attentionRow(page, 't-b').getByTestId('attention-unseen')).toHaveText('3 new');

  // Now open B — this LEAVES A (a real thread switch), so A's watermark advances and A's badge clears.
  await attentionRow(page, 't-b').click();
  await page.getByTestId('attention-digest-close').click();
  await expect(attentionRow(page, 't-a').getByTestId('attention-unseen')).toHaveCount(0);
  // B keeps its badge (we're on it, haven't left it).
  await expect(attentionRow(page, 't-b').getByTestId('attention-unseen')).toHaveText('3 new');
});

test('Enter opens the return digest with verdict, reasons, and the unseen seam', async ({ page }) => {
  await page.goto(harnessURL());
  await seedAttention(page, [
    {
      id: 't-red',
      title: 'fix the parser',
      verdict: 'red',
      summary: 'make test exited 1',
      unseenCount: 2,
      reasons: ['make test exited 1', 'no successful re-run'],
      outcome: 'Left a failing test.'
    }
  ]);

  await page.keyboard.press('Enter');
  const digest = page.getByTestId('attention-digest');
  await expect(digest).toBeVisible();
  await expect(page.getByTestId('attention-digest-title')).toHaveText('fix the parser');
  await expect(page.getByTestId('attention-digest-verdict')).toHaveText('RED');
  await expect(page.getByTestId('attention-digest-verdict')).toHaveAttribute('data-verdict', 'red');
  await expect(page.getByTestId('attention-digest-seam')).toHaveText('2 unseen turns');
  await expect(page.getByTestId('attention-digest-outcome')).toHaveText('Left a failing test.');
  await expect(page.getByTestId('attention-digest-reasons').locator('li')).toHaveCount(2);

  await page.getByTestId('attention-digest-close').click();
  await expect(page.getByTestId('attention-digest')).toHaveCount(0);
});

test('a acknowledges the selected row and removes it from Attention', async ({ page }) => {
  await page.goto(harnessURL());
  await seedAttention(page, [
    { id: 't-red-a', title: 'red a', verdict: 'red' },
    { id: 't-red-b', title: 'red b', verdict: 'red' }
  ]);
  await expect(page.getByTestId('attention-row')).toHaveCount(2);

  // Acknowledge the first (selected) row.
  await page.keyboard.press('a');
  await expect(page.getByTestId('attention-row')).toHaveCount(1);
  await expect(attentionRow(page, 't-red-a')).toHaveCount(0);
  // The cursor advanced to the remaining row.
  await expect(attentionRow(page, 't-red-b')).toHaveAttribute('data-cursor', 'true');
});

test('d dismisses the selected row and empties the section when last', async ({ page }) => {
  await page.goto(harnessURL());
  await seedAttention(page, [{ id: 't-only', title: 'only', verdict: 'unverified' }]);
  await expect(page.getByTestId('attention-row')).toHaveCount(1);

  await page.keyboard.press('d');
  await expect(page.getByTestId('attention-section')).toHaveCount(0);
});

test('clicking an Attention row opens its digest; digest actions triage it', async ({ page }) => {
  await page.goto(harnessURL());
  await seedAttention(page, [
    { id: 't-red', title: 'red run', verdict: 'red', outcome: 'done', reasons: ['boom'] },
    { id: 't-yellow', title: 'yellow run', verdict: 'unverified' }
  ]);

  await attentionRow(page, 't-yellow').click();
  await expect(page.getByTestId('attention-digest')).toBeVisible();
  await expect(page.getByTestId('attention-digest-title')).toHaveText('yellow run');

  // Dismiss from the digest — the thread leaves Attention and the digest closes.
  await page.getByTestId('attention-digest-dismiss').click();
  await expect(page.getByTestId('attention-digest')).toHaveCount(0);
  await expect(attentionRow(page, 't-yellow')).toHaveCount(0);
  await expect(attentionRow(page, 't-red')).toBeVisible();
});

// BLOCKER-3 fail-on-revert: with the composer focused, real j/k/a/d/Enter keystrokes must land as TEXT
// and must NOT triage/open — the bare triage keys are section-scoped, never composer shortcuts. Uses
// keyboard.type (which dispatches real keydown events) rather than fill() so the guard is exercised.
test('triage keys land as composer text and never triage while typing', async ({ page }) => {
  await page.goto(harnessURL());
  await seedAttention(page, [
    { id: 't-red-a', title: 'red a', verdict: 'red' },
    { id: 't-red-b', title: 'red b', verdict: 'red' }
  ]);

  const composer = page.getByLabel('Message');
  await composer.click();
  await expect(composer).toBeFocused();

  // Real keystrokes: every triage letter must be typed into the composer, not eaten.
  await page.keyboard.type('adjkd');
  await expect(composer).toHaveValue('adjkd');
  // Nothing was triaged, no digest opened, the cursor did not move.
  await expect(page.getByTestId('attention-row')).toHaveCount(2);
  await expect(page.getByTestId('attention-digest')).toHaveCount(0);
  await expect(attentionRow(page, 't-red-a')).toHaveAttribute('data-cursor', 'true');

  // Enter in the composer must not open the digest either (it submits / newlines per the composer).
  await composer.fill('');
  await composer.click();
  await page.keyboard.press('Enter');
  await expect(page.getByTestId('attention-digest')).toHaveCount(0);
});

// And the positive half: with focus NOT in an editable field, the keys DO drive the section.
test('triage keys drive the section when focus is not in an editable field', async ({ page }) => {
  await page.goto(harnessURL());
  await seedAttention(page, [
    { id: 't-red-a', title: 'red a', verdict: 'red' },
    { id: 't-red-b', title: 'red b', verdict: 'red' }
  ]);
  // Move focus out of any input onto the body.
  await page.locator('body').click({ position: { x: 2, y: 2 } });
  await page.keyboard.press('j');
  await expect(attentionRow(page, 't-red-b')).toHaveAttribute('data-cursor', 'true');
  await page.keyboard.press('a');
  await expect(page.getByTestId('attention-row')).toHaveCount(1);
});
