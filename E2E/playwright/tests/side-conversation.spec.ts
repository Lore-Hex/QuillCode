import { test, expect } from '@playwright/test';
import { harnessURL } from './harness-helpers';

test('side conversation inherits context, stays out of the sidebar, and returns without polluting the parent', async ({ page }) => {
  await page.goto(harnessURL());

  const composer = page.getByLabel('Message');
  await composer.fill('Explain the main implementation');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('message').filter({ hasText: 'Explain the main implementation' })).toHaveCount(1);
  await expect(page.getByTestId('sidebar-item')).toHaveCount(1);

  await composer.fill('/side What is the smallest safe next step?');
  await page.getByRole('button', { name: 'Send' }).click();

  const banner = page.getByTestId('side-conversation');
  await expect(banner).toBeVisible();
  await expect(banner).toContainText('Side conversation');
  await expect(banner).toContainText('Main chat is ready');
  await expect(page.getByTestId('sidebar-item')).toHaveCount(1);
  await expect(page.getByTestId('message').filter({ hasText: 'Explain the main implementation' })).toHaveCount(1);
  await expect(page.getByTestId('message').filter({ hasText: 'What is the smallest safe next step?' })).toHaveCount(1);

  await page.getByTestId('side-conversation-return').click();

  await expect(banner).toHaveCount(0);
  await expect(page.getByTestId('sidebar-item')).toHaveCount(1);
  await expect(page.getByTestId('message').filter({ hasText: 'Explain the main implementation' })).toHaveCount(1);
  await expect(page.getByTestId('message').filter({ hasText: 'What is the smallest safe next step?' })).toHaveCount(0);
});

test('bare btw opens a side conversation and command palette exposes Return only while active', async ({ page }) => {
  await page.goto(harnessURL());
  const composer = page.getByLabel('Message');

  await composer.fill('Create a main task');
  await page.getByRole('button', { name: 'Send' }).click();
  await composer.fill('/btw');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('side-conversation')).toBeVisible();
  await expect(composer).toHaveValue('');
  await page.getByTestId('side-conversation-return').click();
  await expect(page.getByTestId('side-conversation')).toHaveCount(0);
});
