import { test, expect } from '@playwright/test';
import { harnessURL } from './harness-helpers';

// The always-visible plan-progress strip above the composer. The harness renders the pre-computed
// state.composer.planProgress (mirroring the Swift ComposerSurface field), so we drive that struct
// directly — the same shape the Swift builder produces.

const runningProgress = {
  totalCount: 7,
  completedCount: 2,
  currentStepIndex: 3,
  currentStepTitle: 'Running the test suite',
  isRunning: true,
  isComplete: false,
  fraction: 0.5,
  stepCounterLabel: '3/7',
};

async function setPlanProgress(page: import('@playwright/test').Page, progress: unknown) {
  await page.evaluate((p) => {
    // @ts-expect-error harness globals
    state.composer.planProgress = p;
    // @ts-expect-error harness globals
    render();
  }, progress);
}

test('no strip when there is no plan', async ({ page }) => {
  await page.goto(harnessURL());
  await expect(page.getByTestId('composer-plan-progress')).toHaveCount(0);
});

test('running plan shows the bar, counter, and current step', async ({ page }) => {
  await page.goto(harnessURL());
  await setPlanProgress(page, runningProgress);

  const strip = page.getByTestId('composer-plan-progress');
  await expect(strip).toBeVisible();
  await expect(strip).toHaveAttribute('data-state', 'running');
  await expect(page.getByTestId('plan-progress-count')).toHaveText('3/7');
  await expect(page.getByTestId('plan-progress-step')).toHaveText('Running the test suite');

  // The fill width tracks the fraction.
  const fillWidth = await page.locator('.plan-progress-fill').evaluate((el) => el.style.width);
  expect(fillWidth).toBe('50%');
});

test('completed plan is full and marked complete', async ({ page }) => {
  await page.goto(harnessURL());
  await setPlanProgress(page, {
    totalCount: 4, completedCount: 4, currentStepIndex: 4, currentStepTitle: 'Wrap up',
    isRunning: false, isComplete: true, fraction: 1.0, stepCounterLabel: '4/4',
  });
  const strip = page.getByTestId('composer-plan-progress');
  await expect(strip).toHaveAttribute('data-state', 'complete');
  const fillWidth = await page.locator('.plan-progress-fill').evaluate((el) => el.style.width);
  expect(fillWidth).toBe('100%');
});

test('a stopped run ghosts the strip at the reached step', async ({ page }) => {
  await page.goto(harnessURL());
  await setPlanProgress(page, {
    totalCount: 5, completedCount: 1, currentStepIndex: 2, currentStepTitle: 'Investigate the migration',
    isRunning: false, isComplete: false, fraction: 0.3, stepCounterLabel: '2/5',
  });
  const strip = page.getByTestId('composer-plan-progress');
  await expect(strip).toHaveAttribute('data-state', 'idle');
  // Ghosted (dimmed) but still readable — you can see where it stalled.
  const opacity = await strip.evaluate((el) => Number(getComputedStyle(el).opacity));
  expect(opacity).toBeLessThan(0.5);
  await expect(page.getByTestId('plan-progress-step')).toHaveText('Investigate the migration');
});

test('the strip sits above the composer input in DOM order', async ({ page }) => {
  await page.goto(harnessURL());
  await setPlanProgress(page, runningProgress);
  // Within the composer form, the strip precedes the input surface.
  const order = await page.locator('form.composer').evaluate((form) => {
    const strip = form.querySelector('[data-testid="composer-plan-progress"]');
    const surface = form.querySelector('[data-testid="composer-surface"]');
    if (!strip || !surface) return 'missing';
    return strip.compareDocumentPosition(surface) & Node.DOCUMENT_POSITION_FOLLOWING ? 'strip-first' : 'surface-first';
  });
  expect(order).toBe('strip-first');
});
