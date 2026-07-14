import { test, expect } from '@playwright/test';
import { harnessURL, openSettings } from './harness-helpers';

test('imports another agent through a reviewable additive flow', async ({ page }) => {
  await page.goto(harnessURL());
  await openSettings(page);

  const settings = page.getByTestId('settings-panel');
  await expect(settings.getByTestId('agent-import-settings')).toContainText('never replaced');
  await settings.getByTestId('agent-import-open').click();

  const dialog = page.getByTestId('agent-import-panel');
  await expect(dialog.getByTestId('agent-import-progress')).toContainText('Looking for supported setup');
  await expect(dialog.getByRole('dialog', { name: 'Review import' })).toBeVisible();
  await expect(dialog.getByTestId('agent-import-summary')).toHaveText('6 available · 1 previously imported');
  await expect(dialog.getByTestId('agent-import-project')).toHaveCount(2);
  await expect(dialog.getByTestId('agent-import-candidate')).toHaveCount(5);
  await expect(dialog.locator('[data-candidate-id="skill-imported"]')).toBeDisabled();
  await expect(dialog.getByText('Previously imported', { exact: true })).toBeVisible();
  await expect(dialog.getByText('Review later')).toHaveCount(2);
  await expect(dialog.getByTestId('agent-import-selection-count')).toHaveText('6 selected');

  const loreGamesProject = dialog.locator(
    '[data-testid="agent-import-project"][data-project-path="/Users/quill/Projects/LoreGames"]'
  );
  await loreGamesProject.uncheck();
  await expect(dialog.getByTestId('agent-import-selection-count')).toHaveText('5 selected');

  await dialog.getByTestId('agent-import-none').click();
  await expect(dialog.getByTestId('agent-import-submit')).toBeDisabled();
  await expect(dialog.getByTestId('agent-import-selection-count')).toHaveText('Choose at least one item');
  await dialog.getByTestId('agent-import-all').click();
  await expect(dialog.getByTestId('agent-import-selection-count')).toHaveText('5 selected');

  await dialog.getByTestId('agent-import-submit').click();
  await expect(dialog.getByTestId('agent-import-progress')).toContainText('Importing selected items');
  await expect(dialog.getByTestId('agent-import-result')).toBeVisible();
  await expect(dialog.getByTestId('agent-import-result-count')).toHaveText('5 items added · 0 skipped');
  await expect(dialog.getByTestId('agent-import-follow-ups')).toContainText('MCP servers');
  await expect(dialog.getByTestId('agent-import-follow-ups')).toContainText('hooks');

  await dialog.getByTestId('agent-import-done').click();
  await expect(dialog).toHaveCount(0);
});

test('cancelling discovery ignores its delayed result', async ({ page }) => {
  await page.goto(harnessURL());
  await openSettings(page);
  await page.getByTestId('agent-import-open').click();
  await expect(page.getByTestId('agent-import-progress')).toBeVisible();
  await page.getByTestId('agent-import-close').click();
  await expect(page.getByTestId('agent-import-panel')).toHaveCount(0);
  await page.waitForTimeout(120);
  await expect(page.getByTestId('agent-import-panel')).toHaveCount(0);
});
