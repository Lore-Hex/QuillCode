import { test, expect, type Page } from '@playwright/test';
import { harnessURL, sendComposerPrompt } from './harness-helpers';

// Confidential mode contract, mirrored from the native implementation: /confidential (or the palette
// command) opens a session-only chat that (1) shows a persistent banner, (2) pins + locks the model
// to the E2E-encrypted route, (3) never appears in the sidebar, and (4) is destroyed — with the
// prior model selection restored — the moment the user starts a new chat or selects another thread.

async function openConfidential(page: Page) {
  const message = page.getByLabel('Message');
  await message.fill('/confidential');
  await message.press('Enter');
  await expect(page.getByTestId('confidential-banner')).toBeVisible();
}

test('confidential: /confidential shows the banner, pins + locks the E2E model, and hides from the sidebar', async ({ page }) => {
  await page.goto(harnessURL());

  // Seed a normal thread so there is a sidebar row + a model label to restore later.
  await sendComposerPrompt(page, 'regular question before going private');
  await expect(page.getByTestId('sidebar-thread-row')).toHaveCount(1);
  const modelBefore = (await page.getByTestId('model-picker-button').textContent())?.trim() || '';
  expect(modelBefore.length).toBeGreaterThan(0);

  await openConfidential(page);

  // Banner + pinned/locked model.
  await expect(page.getByTestId('confidential-banner-title')).toHaveText('Confidential chat');
  await expect(page.getByTestId('confidential-banner-detail')).toHaveText('Not saved · E2E encrypted');
  await expect(page.getByTestId('model-picker-button')).toBeDisabled();
  await expect(page.getByTestId('model-picker-button')).toContainText('E2E Encrypted');

  // The confidential thread never appears in the sidebar — only the seeded regular thread.
  await expect(page.getByTestId('sidebar-thread-row')).toHaveCount(1);
  await expect(page.getByTestId('sidebar-thread-row').filter({ hasText: 'Confidential' })).toHaveCount(0);

  // Chatting works normally inside a confidential chat.
  await sendComposerPrompt(page, 'answer privately please');
  await expect(page.getByTestId('message').filter({ hasText: 'answer privately please' })).toBeVisible();
});

test('confidential: the legacy /incognito alias still starts a confidential chat', async ({ page }) => {
  await page.goto(harnessURL());

  // The pre-rename command must keep working, mirroring native exactly: the alias surfaces the
  // /confidential suggestion, the first Enter COMPLETES it into the composer, and the second Enter
  // dispatches it — never sending the text as a prompt into a durable thread.
  const message = page.getByLabel('Message');
  await message.fill('/incognito');
  await message.press('Enter');
  await expect(message).toHaveValue('/confidential');
  await message.press('Enter');

  await expect(page.getByTestId('confidential-banner')).toBeVisible();
  await expect(page.getByTestId('model-picker-button')).toContainText('E2E Encrypted');
  await expect(page.getByTestId('message').filter({ hasText: '/incognito' })).toHaveCount(0);
});

test('confidential: starting a new chat destroys the confidential thread and restores the model', async ({ page }) => {
  await page.goto(harnessURL());
  await sendComposerPrompt(page, 'seed thread');
  const modelBefore = (await page.getByTestId('model-picker-button').textContent())?.trim() || '';

  await openConfidential(page);
  await sendComposerPrompt(page, 'ephemeral words');

  // New chat exits confidential: banner gone, model restored, picker unlocked, and the confidential
  // thread is gone for good (still exactly one durable sidebar row).
  const message = page.getByLabel('Message');
  await message.fill('/new');
  await message.press('Enter');

  await expect(page.getByTestId('confidential-banner')).toHaveCount(0);
  await expect(page.getByTestId('model-picker-button')).toBeEnabled();
  await expect(page.getByTestId('model-picker-button')).toHaveText(modelBefore);
  await expect(page.getByTestId('sidebar-thread-row').filter({ hasText: 'Confidential' })).toHaveCount(0);
});

test('confidential: opening confidential twice replaces the session and still restores the original model', async ({ page }) => {
  await page.goto(harnessURL());
  await sendComposerPrompt(page, 'seed thread');
  const modelBefore = (await page.getByTestId('model-picker-button').textContent())?.trim() || '';

  await openConfidential(page);
  await openConfidential(page);

  // Leaving the SECOND confidential session must restore the pre-confidential model — not the pinned
  // E2E label the first session's exit state was overwritten with.
  const message = page.getByLabel('Message');
  await message.fill('/new');
  await message.press('Enter');
  await expect(page.getByTestId('confidential-banner')).toHaveCount(0);
  await expect(page.getByTestId('model-picker-button')).toHaveText(modelBefore);
});

test('confidential: the palette command opens it and selecting another thread discards it', async ({ page }) => {
  await page.goto(harnessURL());
  await sendComposerPrompt(page, 'durable work item');

  // Open via the command palette (the native command id new-confidential-chat).
  await page.getByTestId('top-bar-overflow-button').click();
  await page.getByTestId('top-bar-overflow-command-palette').click();
  await page.getByTestId('command-palette-input').fill('confidential');
  await page.locator('[data-testid="command-palette-result"][data-command-id="new-confidential-chat"]').first().click();
  await expect(page.getByTestId('confidential-banner')).toBeVisible();

  // Selecting the durable thread from the sidebar discards the confidential chat entirely.
  await page.getByTestId('sidebar-thread-row').filter({ hasText: 'durable work item' }).first().click();
  await expect(page.getByTestId('confidential-banner')).toHaveCount(0);
  await expect(page.getByTestId('message').filter({ hasText: 'durable work item' })).toBeVisible();
});
