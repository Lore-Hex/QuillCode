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

test('mock harness shows model-authored subagent progress in Activity', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('show subagent progress for parallel validation');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.subagents.update');
  await expect(page.getByText('Updated subagent progress.')).toBeVisible();

  await clickSidebarTool(page, 'activity-button');
  await expect(page.getByTestId('activity-pane')).toBeVisible();
  await expect(page.getByTestId('activity-subagent')).toHaveCount(2);
  await expect(page.getByTestId('activity-subagent').nth(0)).toContainText('Explorer');
  await expect(page.getByTestId('activity-subagent').nth(0)).toContainText('Done');
  await expect(page.getByTestId('activity-subagent').nth(1)).toContainText('Verifier');
  await expect(page.getByTestId('activity-subagent').nth(1)).toContainText('Running');
  await expect(page.getByTestId('activity-subagent-section')).toContainText('2 items');

  const explorerTranscript = page.getByTestId('activity-subagent').nth(0)
    .getByTestId('activity-subagent-transcript');
  await explorerTranscript.getByText('Transcript').click();
  await expect(explorerTranscript.getByTestId('activity-subagent-transcript-entry')).toHaveCount(2);
  await expect(explorerTranscript).toContainText('Search files');
  await expect(explorerTranscript).toContainText('Found the Activity surface and tool routing seams.');
});

test('mock harness parses slash subagents into named activity rows', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('/subagents validate release | Explorer: inspect scope | Verifier after Explorer: run smoke');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.subagents.update');
  await expect(page.getByTestId('tool-card-input')).toContainText('"objective": "validate release"');
  await expect(page.getByTestId('tool-card-input')).toContainText('"name": "Explorer"');
  await expect(page.getByTestId('tool-card-input')).toContainText('"name": "Verifier"');
  await expect(page.getByTestId('tool-card-input')).toContainText('"dependsOn"');
  await expect(page.getByText('Updated subagent progress.')).toBeVisible();

  await clickSidebarTool(page, 'activity-button');
  await expect(page.getByTestId('activity-subagent')).toHaveCount(2);
  await expect(page.getByTestId('activity-subagent').nth(0)).toContainText('Explorer');
  await expect(page.getByTestId('activity-subagent').nth(0)).toContainText('Done');
  await expect(page.getByTestId('activity-subagent').nth(1)).toContainText('Verifier');
  await expect(page.getByTestId('activity-subagent').nth(1)).toContainText('Done');
});

test('mock harness dismisses instruction diagnostics from Activity review and sources', async ({ page }) => {
  await page.goto(harnessURL());

  await page.evaluate(() => {
    const harness = window as unknown as { __quillCodeTestAddInstructionConflict: () => void };
    harness.__quillCodeTestAddInstructionConflict();
  });

  await expect(page.getByTestId('activity-pane')).toBeVisible();
  await expect(page.getByTestId('activity-instruction-conflict')).toHaveCount(1);
  await expect(page.getByTestId('activity-instruction-conflict-section')).toContainText('1 issue');
  await expect(page.getByTestId('activity-instruction-conflict')).toContainText('Conflicting instruction intent');
  await expect(page.getByTestId('activity-source-section')).toContainText('Conflicting instruction intent');

  await page.getByTestId('activity-instruction-conflict').getByTestId('activity-source-action').filter({ hasText: 'Dismiss' }).click();

  await expect(page.getByTestId('activity-instruction-conflict')).toHaveCount(0);
  await expect(page.getByTestId('activity-source-section')).not.toContainText('Conflicting instruction intent');
});

test('mock harness applies instruction quick fixes from Activity review', async ({ page }) => {
  await page.goto(harnessURL());

  await page.evaluate(() => {
    const harness = window as unknown as { __quillCodeTestAddInstructionConflict: () => void };
    harness.__quillCodeTestAddInstructionConflict();
  });

  const conflict = page.getByTestId('activity-instruction-conflict');
  await expect(conflict).toContainText('Keep requires tests');
  await expect(conflict).toContainText('Keep avoids tests');

  await conflict.getByTestId('activity-source-action').filter({ hasText: 'Keep requires tests' }).click();

  await expect(page.getByTestId('tool-card-title').filter({ hasText: 'host.apply_patch' })).toBeVisible();
  await expect(page.getByTestId('tool-card-title').filter({ hasText: 'host.git.diff' })).toBeVisible();
  await expect(page.getByTestId('message').filter({ hasText: 'Applied the instruction quick fix.' })).toBeVisible();
  await expect(page.getByTestId('activity-instruction-conflict')).toHaveCount(0);
  await expect(page.getByTestId('activity-source-section')).not.toContainText('Conflicting instruction intent');
});

test('mock harness shows context pressure banner and compacts or forks from latest turn', async ({ page }) => {
  test.setTimeout(60000);
  await page.goto(harnessURL());

  const showActivity = async () => {
    if (await page.getByTestId('activity-pane').count() === 0) {
      await clickSidebarTool(page, 'activity-button');
    }
    await expect(page.getByTestId('activity-pane')).toBeVisible();
  };

  const createContextPressure = async (label: string) => {
    await page.getByRole('textbox', { name: 'Message' }).fill(`${label} ${'word '.repeat(22000)}`);
    await page.getByRole('button', { name: 'Send' }).click();
    await expect(page.getByTestId('context-banner')).toBeVisible();
    await expect(page.getByTestId('context-banner-title')).toContainText(/context limit/i);

    await page.getByRole('textbox', { name: 'Message' }).fill('run whoami');
    await page.getByRole('button', { name: 'Send' }).click();
    await expect(page.getByTestId('context-banner')).toBeVisible();
  };

  await createContextPressure('long context');

  await page.getByTestId('context-compact').click();

  await expect(page.getByTestId('context-banner-progress')).toBeVisible();
  await expect(page.getByTestId('context-banner-progress-title')).toContainText('Compacting context');
  await expect(page.getByTestId('context-compact')).toBeDisabled();
  await expect(page.getByTestId('context-fork-summary')).toBeDisabled();
  await expect(page.getByTestId('top-bar-title')).toContainText('Compact:');
  await expect(page.getByTestId('context-banner')).toHaveCount(0);
  await expect(page.getByTestId('message').first()).toContainText('Context compacted from');
  await expect(page.getByTestId('message').nth(1)).toContainText('run whoami');
  await showActivity();
  await expect(page.getByTestId('activity-context-section')).toContainText('Context');
  await expect(page.getByTestId('activity-context-section')).toContainText('1 item');
  await expect(page.getByTestId('activity-context')).toContainText('Context compacted');
  await expect(page.getByTestId('activity-context')).toContainText('Deterministic summary');

  await createContextPressure('long context again');

  await page.getByTestId('context-fork-last').click();

  await expect(page.getByTestId('top-bar-title')).toContainText('Fork:');
  await expect(page.getByTestId('context-banner')).toHaveCount(0);
  await expect(page.getByTestId('message').first()).toContainText('run whoami');
  await expect(page.getByTestId('timeline').getByText('You are `mock-user` in this workspace.')).toBeVisible();

  await createContextPressure('summary fork pressure');

  await page.getByTestId('context-fork-summary').click();

  await expect(page.getByTestId('context-banner-progress')).toBeVisible();
  await expect(page.getByTestId('context-banner-progress-title')).toContainText('Summarizing fork');
  await expect(page.getByTestId('context-fork-last')).toBeDisabled();
  await expect(page.getByTestId('context-fork-full')).toBeDisabled();
  await expect(page.getByTestId('top-bar-title')).toContainText('Fork summary:');
  await expect(page.getByTestId('context-banner')).toHaveCount(0);
  await expect(page.getByTestId('message').first()).toContainText('Context forked from');
  await expect(page.getByTestId('message').nth(1)).toContainText('run whoami');
  await showActivity();
  await expect(page.getByTestId('activity-context-section')).toContainText('1 item');
  await expect(page.getByTestId('activity-context')).toContainText('Fork summary ready');
  await expect(page.getByTestId('activity-context')).toContainText('Deterministic summary');

  await createContextPressure('full fork pressure');

  await page.getByTestId('context-fork-full').click();

  await expect(page.getByTestId('top-bar-title')).toContainText('Fork full:');
  await expect(page.getByTestId('context-banner')).toBeVisible();
  await expect(page.getByTestId('message').first()).toContainText('Context forked from');
  await expect(page.getByTestId('timeline').getByText('full fork pressure')).toBeVisible();
});
