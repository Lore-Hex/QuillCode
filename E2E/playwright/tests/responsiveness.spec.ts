import { test, expect, type Page } from '@playwright/test';
import { harnessURL } from './harness-helpers';

async function now(page: Page) {
  return page.evaluate(() => performance.now());
}

test('workspace becomes interactive quickly on first load', async ({ page }) => {
  const start = Date.now();
  await page.goto(harnessURL());
  await expect(page.getByLabel('Message')).toBeEnabled();
  await expect(page.getByTestId('top-bar-title')).toBeVisible();
  await expect(page.getByTestId('sidebar')).toBeVisible();

  expect(Date.now() - start).toBeLessThan(1800);
});

test('simple one-turn shell action completes within the interaction budget', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('whoami?');
  const start = await now(page);
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByText('You are `mock-user` in this workspace.')).toBeVisible();
  const elapsed = (await now(page)) - start;

  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-status', 'done');
  expect(elapsed).toBeLessThan(700);
});

test('stop responds quickly while a slow tool is running', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('slow task');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('agent-status')).toHaveText('Running');
  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-status', 'running');

  const start = await now(page);
  await page.getByTestId('top-bar-stop-button').click();
  await expect(page.getByTestId('agent-status')).toHaveText('Stopped');
  const elapsed = (await now(page)) - start;

  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-status', 'failed');
  expect(elapsed).toBeLessThan(500);
});

test('tool-card expand and collapse keeps layout stable', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('Can you download LinkedIn.com?');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-status', 'done');

  const before = await page.evaluate(() => ({
    scrollX: window.scrollX,
    viewportWidth: document.documentElement.clientWidth,
    scrollWidth: document.documentElement.scrollWidth
  }));

  const details = page.getByTestId('tool-card-details');
  const start = await now(page);
  await details.locator('summary').click();
  await expect.poll(() => details.evaluate(element => (element as HTMLDetailsElement).open)).toBe(true);
  await details.locator('summary').click();
  await expect.poll(() => details.evaluate(element => (element as HTMLDetailsElement).open)).toBe(false);
  const elapsed = (await now(page)) - start;

  const after = await page.evaluate(() => ({
    scrollX: window.scrollX,
    viewportWidth: document.documentElement.clientWidth,
    scrollWidth: document.documentElement.scrollWidth
  }));
  expect(after.scrollX).toBe(before.scrollX);
  expect(after.scrollWidth).toBeLessThanOrEqual(after.viewportWidth + 1);
  expect(elapsed).toBeLessThan(700);
});
