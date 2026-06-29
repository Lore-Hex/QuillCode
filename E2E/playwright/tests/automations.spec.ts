import { test, expect } from '@playwright/test';
import { clickSidebarTool, harnessURL } from './harness-helpers';

test('mock harness separates Automations from Activity in the sidebar', async ({ page }) => {
  await page.goto(harnessURL());

  await clickSidebarTool(page, 'automations-button');
  await expect(page.getByTestId('automations-pane')).toBeVisible();
  await expect(page.getByTestId('automations-title')).toHaveText('Automations');
  await expect(page.getByTestId('automation-card')).toHaveCount(3);
  await expect(page.getByTestId('automation-card').first()).toContainText('Thread follow-ups');
  await expect(page.getByTestId('activity-pane')).toHaveCount(0);

  await clickSidebarTool(page, 'activity-button');
  await expect(page.getByTestId('activity-pane')).toBeVisible();
  await expect(page.getByTestId('automations-pane')).toBeVisible();
  await expect(page.getByTestId('activity-title')).toHaveText('Activity');
});

test('mock harness creates and manages a thread follow-up automation', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByTestId('new-chat-button').click();
  await page.getByLabel('Message').fill('plan the launch');
  await page.getByRole('button', { name: 'Send' }).click();
  await clickSidebarTool(page, 'automations-button');
  await page.getByTestId('automation-create-follow-up').click();

  await expect(page.getByTestId('automations-status')).toHaveText('1 active');
  await expect(page.getByTestId('automation-card')).toHaveCount(1);
  await expect(page.getByTestId('automation-card')).toContainText('Follow up: plan the launch');
  await expect(page.getByTestId('automation-run')).toHaveText('Run now');
  await expect(page.getByTestId('automation-primary-action')).toHaveText('Pause');

  await page.getByTestId('automation-run').click();
  await expect(page.getByTestId('sidebar-item').first()).toContainText('Follow-up: plan the launch');
  await expect(page.getByTestId('automation-card')).toContainText('Ran');
  await expect(page.getByTestId('automations-status')).toHaveText('1 active');

  await page.getByTestId('automation-primary-action').click();
  await expect(page.getByTestId('automations-status')).toHaveText('1 paused');
  await expect(page.getByTestId('automation-primary-action')).toHaveText('Resume');

  await page.getByTestId('automation-primary-action').click();
  await expect(page.getByTestId('automations-status')).toHaveText('1 active');
  await expect(page.getByTestId('automation-primary-action')).toHaveText('Pause');

  await page.getByTestId('automation-delete').click();
  await expect(page.getByTestId('automations-status')).toHaveText('3 planned');
  await expect(page.getByTestId('automation-card')).toHaveCount(3);
});

test('mock harness creates and runs a workspace schedule automation', async ({ page }) => {
  await page.goto(harnessURL());

  await clickSidebarTool(page, 'automations-button');
  await page.getByTestId('automation-create-workspace-schedule').click();

  await expect(page.getByTestId('automations-status')).toHaveText('1 active');
  await expect(page.getByTestId('automation-card')).toHaveCount(1);
  await expect(page.getByTestId('automation-card')).toContainText('Workspace check: QuillCode');
  await expect(page.getByTestId('automation-card')).toContainText('Manual workspace check');
  await expect(page.getByTestId('automation-run')).toHaveText('Run now');

  await page.getByTestId('automation-run').click();
  await expect(page.getByTestId('sidebar-item').first()).toContainText('Scheduled check: QuillCode');
  await expect(page.getByTestId('message').first()).toContainText('Run the scheduled workspace check for QuillCode.');
  await expect(page.getByTestId('automation-card')).toContainText('Ran');
  await expect(page.getByTestId('automations-status')).toHaveText('1 active');
});

test('mock harness runs a configured monitor automation', async ({ page }) => {
  await page.goto(harnessURL());

  await page.evaluate(() => {
    const harness = window as typeof window & {
      __quillCodeTestCreateMonitorAutomation?: (
        scheduleLabel?: string,
        options?: { title?: string; detail?: string }
      ) => void
    };
    harness.__quillCodeTestCreateMonitorAutomation?.(
      'PR check events',
      {
        title: 'Watch CI',
        detail: 'Watch pull request checks and summarize new failures.'
      }
    );
  });

  await expect(page.getByTestId('automations-pane')).toBeVisible();
  await expect(page.getByTestId('automations-status')).toHaveText('1 active');
  await expect(page.getByTestId('automation-card')).toHaveCount(1);
  await expect(page.getByTestId('automation-card')).toContainText('Watch CI');
  await expect(page.getByTestId('automation-run')).toHaveText('Run now');

  await page.getByTestId('automation-run').click();

  await expect(page.getByTestId('sidebar-item').first()).toContainText('Monitor: Watch CI');
  await expect(page.getByTestId('message').first()).toContainText('Run the monitor "Watch CI".');
  await expect(page.getByTestId('message').first()).toContainText('Watch condition: Watch pull request checks and summarize new failures.');
  await expect(page.getByTestId('automation-card')).toContainText('Ran');
  await expect(page.getByTestId('automations-status')).toHaveText('1 active');
});

test('mock harness schedules a thread follow-up from quick actions', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByTestId('new-chat-button').click();
  await page.getByLabel('Message').fill('check tomorrow');
  await page.getByRole('button', { name: 'Send' }).click();
  await clickSidebarTool(page, 'automations-button');
  await page.getByTestId('automation-schedule-follow-up').filter({ hasText: 'In 10 minutes' }).click();

  await expect(page.getByTestId('automations-status')).toHaveText('1 active');
  await expect(page.getByTestId('automation-card')).toHaveCount(1);
  await expect(page.getByTestId('automation-card')).toContainText('Follow up: check tomorrow');
  await expect(page.getByTestId('automation-card')).toContainText('In 10 minutes');
});

test('mock harness schedules a workspace check from quick actions', async ({ page }) => {
  await page.goto(harnessURL());

  await clickSidebarTool(page, 'automations-button');
  await page.getByTestId('automation-schedule-workspace').filter({ hasText: 'Check in 10 minutes' }).click();

  await expect(page.getByTestId('automations-status')).toHaveText('1 active');
  await expect(page.getByTestId('automation-card')).toHaveCount(1);
  await expect(page.getByTestId('automation-card')).toContainText('Workspace check: QuillCode');
  await expect(page.getByTestId('automation-card')).toContainText('In 10 minutes');
});

test('mock harness keeps recurring workspace schedules active after running', async ({ page }) => {
  await page.goto(harnessURL());

  await clickSidebarTool(page, 'automations-button');
  await page.getByTestId('automation-schedule-workspace').filter({ hasText: 'Check daily' }).click();

  await expect(page.getByTestId('automations-status')).toHaveText('1 active');
  await expect(page.getByTestId('automation-card')).toHaveCount(1);
  await expect(page.getByTestId('automation-card')).toContainText('Workspace check: QuillCode');
  await expect(page.getByTestId('automation-card')).toContainText('Every day');

  await page.getByTestId('automation-run').click();

  await expect(page.getByTestId('sidebar-item').first()).toContainText('Scheduled check: QuillCode');
  await expect(page.getByTestId('automation-card')).toContainText('Active');
  await expect(page.getByTestId('automation-card')).toContainText('Every day');
});

test('mock harness schedules a thread follow-up from slash text', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByTestId('new-chat-button').click();
  await page.getByLabel('Message').fill('review the launch notes');
  await page.getByRole('button', { name: 'Send' }).click();

  await page.getByLabel('Message').fill('/follow-up tomorrow at 9:30 PM');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('automations-pane')).toBeVisible();
  await expect(page.getByTestId('automations-status')).toHaveText('1 active');
  await expect(page.getByTestId('automation-card')).toHaveCount(1);
  await expect(page.getByTestId('automation-card')).toContainText('Follow up: review the launch notes');
  await expect(page.getByTestId('automation-card')).toContainText('Tomorrow at 9:30 PM');
  await expect(page.getByText('Scheduled a thread follow-up for Tomorrow at 9:30 PM.')).toBeVisible();
});

test('mock harness schedules a thread follow-up from weekday slash text', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByTestId('new-chat-button').click();
  await page.getByLabel('Message').fill('review the launch notes');
  await page.getByRole('button', { name: 'Send' }).click();

  await page.getByLabel('Message').fill('/follow-up friday afternoon');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('automations-pane')).toBeVisible();
  await expect(page.getByTestId('automations-status')).toHaveText('1 active');
  await expect(page.getByTestId('automation-card')).toContainText('Follow up: review the launch notes');
  await expect(page.getByTestId('automation-card')).toContainText('Friday at 1:00 PM');
  await expect(page.getByText('Scheduled a thread follow-up for Friday at 1:00 PM.')).toBeVisible();
});

test('mock harness schedules a workspace check from slash text', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('/workspace-check tomorrow at 8:15 AM');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('automations-pane')).toBeVisible();
  await expect(page.getByTestId('automations-status')).toHaveText('1 active');
  await expect(page.getByTestId('automation-card')).toHaveCount(1);
  await expect(page.getByTestId('automation-card')).toContainText('Workspace check: QuillCode');
  await expect(page.getByTestId('automation-card')).toContainText('Tomorrow at 8:15 AM');
  await expect(page.getByText('Scheduled a workspace check for Tomorrow at 8:15 AM.')).toBeVisible();
});

test('mock harness schedules a workspace check from next-weekday slash text', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('/workspace-check next monday at noon');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('automations-pane')).toBeVisible();
  await expect(page.getByTestId('automations-status')).toHaveText('1 active');
  await expect(page.getByTestId('automation-card')).toContainText('Workspace check: QuillCode');
  await expect(page.getByTestId('automation-card')).toContainText('Next Monday at 12:00 PM');
  await expect(page.getByText('Scheduled a workspace check for Next Monday at 12:00 PM.')).toBeVisible();
});

test('mock harness schedules a recurring workspace check from slash text', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('/workspace-check every 2 hours');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('automations-pane')).toBeVisible();
  await expect(page.getByTestId('automations-status')).toHaveText('1 active');
  await expect(page.getByTestId('automation-card')).toHaveCount(1);
  await expect(page.getByTestId('automation-card')).toContainText('Workspace check: QuillCode');
  await expect(page.getByTestId('automation-card')).toContainText('Every 2 hours');
  await expect(page.getByText('Scheduled a workspace check for Every 2 hours.')).toBeVisible();
});
