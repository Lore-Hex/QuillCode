import { test, expect } from '@playwright/test';
import { harnessURL } from './harness-helpers';

test('mock harness searches and selects models from the composer', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByTestId('model-picker-button').click();
  await expect(page.getByTestId('model-browser')).toBeVisible();
  await expect(page.getByTestId('model-result-count')).toHaveText('6 models available');
  await expect(page.getByTestId('model-option').first()).toContainText('Socrates 1.1');
  await expect(page.getByTestId('model-option-summary').first()).toContainText('Leading frontier model');
  await expect(page.getByTestId('model-detail-button').nth(1)).toHaveAttribute('aria-expanded', 'true');
  await expect(page.getByTestId('model-capability')).toContainText('Nike 1.0 is the fast default');
  await expect(page.getByTestId('model-metadata-row').filter({ hasText: 'trustedrouter/fast' })).toBeVisible();
  await expect(page.getByTestId('model-metadata-row').filter({ hasText: 'Current, Default, Recommended' }))
    .toBeVisible();
  await expect(page.getByTestId('model-option')).toHaveCount(6);

  await page.getByTestId('model-detail-button').nth(0).click();
  await expect(page.getByTestId('model-detail-button').nth(0)).toHaveAttribute('aria-expanded', 'true');
  await expect(page.getByTestId('model-capability')).toContainText('Socrates 1.1 is the leading model');
  await expect(page.getByTestId('model-metadata-row').filter({ hasText: 'tr/socrates' })).toBeVisible();

  await page.getByTestId('model-detail-button').nth(2).click();
  await expect(page.getByTestId('model-detail-button').nth(2)).toHaveAttribute('aria-expanded', 'true');
  await expect(page.getByTestId('model-capability')).toContainText('Synth is the balanced model');
  await expect(page.getByTestId('model-metadata-row').filter({ hasText: 'tr/synth' })).toBeVisible();

  await page.getByTestId('model-search').fill('socrates');
  await expect(page.getByTestId('model-result-count')).toHaveText('1 model for "socrates"');
  await expect(page.getByTestId('model-option')).toHaveCount(1);
  await expect(page.getByTestId('model-option')).toContainText('Socrates 1.1');
  await page.getByTestId('model-search').fill('');

  await page.getByTestId('model-favorite-button').nth(1).click();
  await expect(page.getByTestId('model-browser')).toBeVisible();
  await expect(page.getByTestId('model-category').first()).toContainText('Favorites');
  await expect(page.getByTestId('model-option')).toHaveCount(7);
  await expect(page.getByTestId('model-favorite-button').first())
    .toHaveAttribute('aria-label', 'Remove favorite model');

  await page.getByTestId('model-search').fill('favorite');
  await expect(page.getByTestId('model-category')).toHaveCount(1);
  await expect(page.getByTestId('model-category')).toContainText('Favorites');
  await expect(page.getByTestId('model-option')).toHaveCount(1);

  await page.getByTestId('model-search').fill('moon k2');
  await expect(page.getByTestId('model-option')).toHaveCount(1);
  await expect(page.getByTestId('model-option')).toContainText('moonshotai/Kimi K2.6');

  await page.getByTestId('model-option').click();
  await expect(page.getByTestId('model-picker-button')).toHaveText('moonshotai/Kimi K2.6');
  await expect(page.getByTestId('mode-pill')).toHaveText('Auto');
  await expect(page.getByTestId('model-browser')).toHaveCount(0);

  await page.getByTestId('model-picker-button').click();
  await page.getByTestId('model-search').fill('not-a-model');
  await expect(page.getByTestId('model-result-count')).toHaveText('0 models for "not-a-model"');
  await expect(page.getByTestId('model-empty')).toBeVisible();
  await page.getByTestId('model-clear-search').first().click();
  await expect(page.getByTestId('model-search')).toBeFocused();
  await expect(page.getByTestId('model-result-count')).toHaveText('7 models available');
});

test('mock harness supports keyboard navigation in the model picker', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByTestId('model-picker-button').click();
  await expect(page.getByTestId('model-search')).toBeFocused();
  await page.getByTestId('model-search').fill('synth');

  await expect(page.getByTestId('model-option')).toHaveCount(2);
  await expect(page.getByTestId('model-option').nth(0)).toHaveAttribute('data-highlighted', 'true');

  await page.keyboard.press('ArrowDown');
  await expect(page.getByTestId('model-option').nth(1)).toHaveAttribute('data-highlighted', 'true');

  await page.keyboard.press('Enter');
  await expect(page.getByTestId('model-picker-button')).toHaveText('Synth Code');
  await expect(page.getByTestId('model-browser')).toHaveCount(0);
});
