import { test, expect } from '@playwright/test';
import { harnessURL } from './harness-helpers';

test('mock harness reverts a turn from its user message', async ({ page }) => {
  await page.goto(harnessURL());

  // A turn that applies a patch becomes revertable.
  await page.getByLabel('Message').fill('apply patch to fix the bug');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('tool-card-title').filter({ hasText: 'host.apply_patch' })).toBeVisible();

  // The user message that started the turn gets a truthful "Revert this turn's edits" button.
  const revert = page.getByTestId('message-revert-turn');
  await expect(revert).toBeVisible();
  await expect(revert).toHaveText("Revert this turn's edits");
  await expect(revert).toHaveAttribute('title', /does not undo your own earlier edits/);

  // Clicking it runs the revert as a recorded tool run.
  await revert.click();
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.revert_turn');
});

test('mock harness revert scope copy matches the Swift TurnRevertCopy byte-for-byte', async ({ page }) => {
  await page.goto(harnessURL());
  // Drives the JS revertScopeCopy against the SAME two literals asserted in
  // WorkspaceTurnRevertSurfaceTests, so the truthful copy can't drift across Swift and JS.
  const copies = await page.evaluate(() => {
    const scope = (window as Window & { revertScopeCopy?: (b: boolean) => string }).revertScopeCopy;
    return { clean: scope?.(false), disclosed: scope?.(true) };
  });
  expect(copies.clean).toBe(
    'Reverses the file edits this turn applied, including files it created. It does not undo your own earlier edits, shell commands the turn ran, or git commits.'
  );
  expect(copies.disclosed).toBe(
    "Reverses the file edits this turn applied, including files it created. It does not undo your own earlier edits, shell commands the turn ran, or git commits. This turn also changed files outside apply_patch, which can't be reverted automatically."
  );
});

test('mock harness shows no revert button on a turn that applied no patch', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('what does this project do?');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('message').first()).toContainText('what does this project do?');

  await expect(page.getByTestId('message-revert-turn')).toHaveCount(0);
});
