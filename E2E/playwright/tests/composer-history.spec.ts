import { test, expect } from '@playwright/test';
import { harnessURL } from './harness-helpers';

test('mock harness preserves a separate composer draft per thread', async ({ page }) => {
  await page.goto(harnessURL());
  const message = page.getByLabel('Message');

  await message.fill('alpha topic');
  await message.press('Enter');
  // The composer never locks, so wait on the real turn-completion signal (status → Idle), not on
  // the composer re-enabling (which is now always-enabled and never a done-signal).
  await expect(page.getByTestId('agent-status')).toHaveText('Idle');
  await expect(page.getByTestId('sidebar-item').filter({ hasText: 'alpha topic' })).toBeVisible();

  await page.getByTestId('new-chat-button').click();
  await message.fill('beta topic');
  await message.press('Enter');
  await expect(page.getByTestId('agent-status')).toHaveText('Idle');
  await expect(page.getByTestId('sidebar-item').filter({ hasText: 'beta topic' })).toBeVisible();

  await message.fill('work in progress for beta');

  await page.getByTestId('sidebar-item').filter({ hasText: 'alpha topic' }).click();
  await expect(message).toHaveValue('');

  await page.getByTestId('sidebar-item').filter({ hasText: 'beta topic' }).click();
  await expect(message).toHaveValue('work in progress for beta');
});

test('mock harness recalls sent messages with Up and Down', async ({ page }) => {
  await page.goto(harnessURL());
  const message = page.getByLabel('Message');

  await message.fill('first prompt');
  await message.press('Enter');
  // Wait on the real turn-completion signal (status → Idle); the composer is always enabled now.
  await expect(page.getByTestId('agent-status')).toHaveText('Idle');
  await expect(message).toHaveValue('');

  await message.fill('second prompt');
  await message.press('Enter');
  await expect(page.getByTestId('agent-status')).toHaveText('Idle');
  await expect(message).toHaveValue('');

  await message.press('ArrowUp');
  await expect(message).toHaveValue('second prompt');
  await message.press('ArrowUp');
  await expect(message).toHaveValue('first prompt');
  await message.press('ArrowUp');
  await expect(message).toHaveValue('first prompt');

  await message.press('ArrowDown');
  await expect(message).toHaveValue('second prompt');
  await message.press('ArrowDown');
  await expect(message).toHaveValue('');

  await message.fill('half typed');
  await message.press('ArrowUp');
  await expect(message).toHaveValue('half typed');
});
