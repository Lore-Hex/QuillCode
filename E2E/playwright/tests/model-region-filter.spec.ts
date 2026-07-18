import { test, expect, type Page } from '@playwright/test';
import { harnessURL } from './harness-helpers';

// Region enforcement in the model picker search: "us-only" / "eu-only" / "china-only" restrict the
// list to models whose residency claim is entirely within that region. Unknown residency fails
// closed, and a multi-region model is excluded from single-region enforcement. Mirrors the native
// ModelCategorySearchFilter semantics against the harness's mock regions
// (fast/zeus = us, fusion = us+eu, plato = eu, glm-5.2/minimax = cn, kimi = unknown).

async function searchModels(page: Page, query: string): Promise<string[]> {
  await page.getByTestId('model-search').fill(query);
  return page.getByTestId('model-option').evaluateAll(
    options => options.map(option => option.getAttribute('data-model-id') || '').sort()
  );
}

test('model search enforces us-only, eu-only, and china-only region constraints', async ({ page }) => {
  await page.goto(harnessURL());
  await page.getByTestId('model-picker-button').click();
  await expect(page.getByTestId('model-browser')).toBeVisible();

  expect(await searchModels(page, 'us-only'), 'us-only: exclusively-US models; us+eu fusion excluded')
    .toEqual(['trustedrouter/fast', 'trustedrouter/zeus']);
  expect(await searchModels(page, 'eu-only')).toEqual(['trustedrouter/plato']);
  expect(await searchModels(page, 'china-only'), 'kimi has no residency claim — fails closed')
    .toEqual(['minimax/minimax-m3', 'z-ai/glm-5.2']);

  // Combined with ordinary text the constraint still applies.
  expect(await searchModels(page, 'us-only nike')).toEqual(['trustedrouter/fast']);
  expect(await searchModels(page, 'us-only plato')).toEqual([]);

  // The hint advertises the option, and the inspector shows the region claim.
  await expect(page.getByText('us-only / eu-only / china-only')).toBeVisible();
  await searchModels(page, 'china-only');
  await page.locator('[data-testid="model-detail-button"][data-model-id="z-ai/glm-5.2"]').click();
  await expect(
    page.getByTestId('model-metadata-row').filter({ hasText: 'CN' })
  ).toBeVisible();
});
