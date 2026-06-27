import { test, expect } from '@playwright/test';
import { clickSidebarTool, harnessURL } from './harness-helpers';

test('mock harness preserves transcript scroll intent as new events append', async ({ page }) => {
  await page.goto(harnessURL());

  await page.evaluate(() => {
    const harness = window as unknown as { sendMessage: (value: string) => void };
    for (let index = 0; index < 24; index += 1) {
      harness.sendMessage(`run whoami ${index}`);
    }
  });

  const timeline = page.getByTestId('timeline');
  await expect(timeline).toBeVisible();
  const scrollable = await page.evaluate(() => document.documentElement.scrollHeight > window.innerHeight);
  expect(scrollable).toBe(true);

  const midScroll = await page.evaluate(() => {
    const nextScrollY = Math.floor((document.documentElement.scrollHeight - window.innerHeight) / 2);
    window.scrollTo(0, nextScrollY);
    return window.scrollY;
  });
  await page.evaluate(() => {
    const harness = window as unknown as { sendMessage: (value: string) => void };
    harness.sendMessage('run whoami while reading history');
  });
  const afterMidAppend = await page.evaluate(() => window.scrollY);
  expect(Math.abs(afterMidAppend - midScroll)).toBeLessThanOrEqual(1);

  await page.evaluate(() => {
    window.scrollTo(0, document.documentElement.scrollHeight);
  });
  await page.evaluate(() => {
    const harness = window as unknown as { sendMessage: (value: string) => void };
    harness.sendMessage('run whoami at bottom');
  });
  const bottomDistance = await page.evaluate(() =>
    Math.max(0, document.documentElement.scrollHeight - window.innerHeight - window.scrollY)
  );
  expect(bottomDistance).toBeLessThanOrEqual(1);
});

test('mock harness shows model-authored task plan in Activity', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('plan the QuillCode work');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.plan.update');
  await expect(page.getByText('Updated the task plan.')).toBeVisible();

  await clickSidebarTool(page, 'activity-button');
  await expect(page.getByTestId('activity-pane')).toBeVisible();
  await expect(page.getByTestId('activity-plan')).toHaveCount(3);
  await expect(page.getByTestId('activity-plan').nth(0)).toContainText('Inspect current state');
  await expect(page.getByTestId('activity-plan').nth(0)).toContainText('Done');
  await expect(page.getByTestId('activity-plan').nth(1)).toContainText('Implement requested change');
  await expect(page.getByTestId('activity-plan').nth(1)).toContainText('Running');
  await expect(page.getByTestId('activity-plan').nth(1)).toContainText('Keep the slice reviewable.');
  await expect(page.getByTestId('activity-plan').nth(2)).toContainText('Validate and summarize');
  await expect(page.getByTestId('activity-plan').nth(2)).toContainText('Pending');
  await expect(page.getByTestId('activity-plan-section')).toContainText('3 items');
});

test('mock harness shows model-authored handoff summary in Activity', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('write a handoff summary');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.handoff.update');
  await expect(page.getByText('Updated the handoff summary.')).toBeVisible();

  await clickSidebarTool(page, 'activity-button');
  await expect(page.getByTestId('activity-pane')).toBeVisible();
  await expect(page.getByTestId('activity-handoff')).toContainText('Current task state is ready for continuation.');
  await expect(page.getByTestId('activity-handoff')).toContainText('Next steps:');
  await expect(page.getByTestId('activity-handoff')).toContainText('1. Review the latest tool output');
  await expect(page.getByTestId('activity-handoff')).toContainText('2. Continue from the Activity pane');
  await expect(page.getByTestId('activity-handoff-section')).toContainText('1 summary');
});

test('mock harness shows context pressure banner and compacts or forks from latest turn', async ({ page }) => {
  test.setTimeout(60000);
  await page.goto(harnessURL());

  const longPrompt = 'long context ' + 'word '.repeat(22000);
  await page.getByLabel('Message').fill(longPrompt);
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('context-banner')).toBeVisible();
  await expect(page.getByTestId('context-banner-title')).toContainText(/context limit/i);

  await page.getByLabel('Message').fill('run whoami');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('context-banner')).toBeVisible();

  await page.getByTestId('context-compact').click();

  await expect(page.getByTestId('top-bar-title')).toContainText('Compact:');
  await expect(page.getByTestId('context-banner')).toHaveCount(0);
  await expect(page.getByTestId('message').first()).toContainText('Context compacted from');
  await expect(page.getByTestId('message').nth(1)).toContainText('run whoami');

  await page.getByRole('textbox', { name: 'Message' }).fill('long context again ' + 'word '.repeat(22000));
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('context-banner')).toBeVisible();
  await page.getByRole('textbox', { name: 'Message' }).fill('run whoami');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('context-banner')).toBeVisible();

  await page.getByTestId('context-fork-last').click();

  await expect(page.getByTestId('top-bar-title')).toContainText('Fork:');
  await expect(page.getByTestId('context-banner')).toHaveCount(0);
  await expect(page.getByTestId('message').first()).toContainText('run whoami');
  await expect(page.getByText('You are `mock-user` in this workspace.')).toBeVisible();
});
