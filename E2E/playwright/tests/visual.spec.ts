import { test, expect, type Page } from '@playwright/test';
import { clickSidebarTool, harnessURL } from './harness-helpers';
import * as fs from 'fs';
import * as path from 'path';

// Faithful visual smoke: captures REAL-DOM screenshots of the harness UI at key flow states so the
// rendered UI is actually looked at on every change. (The native ImageRenderer PNG smoke cannot
// faithfully snapshot a TextField or a ScrollView's lazy content, so it is unusable for judging visual
// quality - this captures the real browser DOM instead.) Each test also asserts the state it shoots,
// so it doubles as a regression gate. Screenshots land in QUILLCODE_VISUAL_SMOKE_ARTIFACT_DIR (default
// ./visual-artifacts) for CI upload / PR inspection.

const artifactDir =
  process.env.QUILLCODE_VISUAL_SMOKE_ARTIFACT_DIR || path.join(process.cwd(), 'visual-artifacts');

test.use({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 2 });

async function capture(page: Page, name: string): Promise<void> {
  fs.mkdirSync(artifactDir, { recursive: true });
  await page.screenshot({ path: path.join(artifactDir, `${name}.png`) });
}

test('visual: empty workspace with starter actions', async ({ page }) => {
  await page.goto(harnessURL());
  await expect(page.getByTestId('workspace')).toBeVisible();
  await expect(page.getByTestId('transcript-empty')).toBeVisible();
  await expect(page.getByTestId('empty-starter-action')).toHaveCount(3);
  await capture(page, '01-empty-workspace');
});

test('visual: populated conversation', async ({ page }) => {
  await page.goto(harnessURL());
  const message = page.getByLabel('Message');
  await message.fill('Refactor the auth module and add unit tests for the login flow');
  await message.press('Enter');
  await expect(page.getByTestId('message').first()).toBeVisible();
  // Let the mock assistant reply + the sidebar thread row settle before the shot.
  await expect(page.getByTestId('timeline')).toBeVisible();
  await capture(page, '02-conversation');
});

test('visual: command palette', async ({ page }) => {
  await page.goto(harnessURL());
  await clickSidebarTool(page, 'command-palette-button');
  await expect(page.getByTestId('command-palette-input')).toBeVisible();
  await capture(page, '03-command-palette');
});

test('visual: settings', async ({ page }) => {
  await page.goto(harnessURL());
  await page.getByTestId('settings-button').click();
  await expect(page.getByTestId('settings-panel')).toBeVisible();
  await capture(page, '04-settings');
});

test('visual: terminal pane', async ({ page }) => {
  await page.goto(harnessURL());
  await clickSidebarTool(page, 'terminal-button');
  await capture(page, '05-terminal');
});

test('visual: active workflow recording', async ({ page }) => {
  await page.goto(harnessURL());
  await clickSidebarTool(page, 'extensions-button');
  await page.getByTestId('workflow-recording-start').click();
  await page.getByLabel('Message').pressSequentially('Publish a release to staging');
  await page.getByTestId('send-button').click();

  const consentCard = page.getByTestId('tool-card').filter({ hasText: 'host.workflow.record.start' }).first();
  await consentCard.getByRole('button', { name: 'Start recording' }).click();
  const recordingStatus = page.getByTestId('workflow-recording-status');
  await expect(recordingStatus).toBeVisible();
  await recordingStatus.scrollIntoViewIfNeeded();
  await capture(page, '06-active-workflow-recording');
});
