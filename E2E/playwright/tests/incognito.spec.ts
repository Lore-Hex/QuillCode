import { test, expect, type Page } from '@playwright/test';
import { harnessURL, sendComposerPrompt } from './harness-helpers';

// Incognito mode contract, mirrored from the native implementation: /incognito (or the palette
// command) opens a session-only chat that (1) shows a persistent banner, (2) pins + locks the model
// to the E2E-encrypted route, (3) never appears in the sidebar, and (4) is destroyed — with the
// prior model selection restored — the moment the user starts a new chat or selects another thread.

async function openIncognito(page: Page) {
  const message = page.getByLabel('Message');
  await message.fill('/incognito');
  await message.press('Enter');
  await expect(page.getByTestId('incognito-banner')).toBeVisible();
}

test('incognito: /incognito shows the banner, pins + locks the E2E model, and hides from the sidebar', async ({ page }) => {
  await page.goto(harnessURL());

  // Seed a normal thread so there is a sidebar row + a model label to restore later.
  await sendComposerPrompt(page, 'regular question before going private');
  await expect(page.getByTestId('sidebar-thread-row')).toHaveCount(1);
  const modelBefore = (await page.getByTestId('model-picker-button').textContent())?.trim() || '';
  expect(modelBefore.length).toBeGreaterThan(0);

  await openIncognito(page);

  // Banner + pinned/locked model.
  await expect(page.getByTestId('incognito-banner-title')).toHaveText('Incognito chat');
  await expect(page.getByTestId('incognito-banner-detail')).toHaveText('Not saved · E2E encrypted');
  await expect(page.getByTestId('model-picker-button')).toBeDisabled();
  await expect(page.getByTestId('model-picker-button')).toContainText('E2E Encrypted');

  // The incognito thread never appears in the sidebar — only the seeded regular thread.
  await expect(page.getByTestId('sidebar-thread-row')).toHaveCount(1);
  await expect(page.getByTestId('sidebar-thread-row').filter({ hasText: 'Incognito' })).toHaveCount(0);

  // Chatting works normally inside incognito.
  await sendComposerPrompt(page, 'answer privately please');
  await expect(page.getByTestId('message').filter({ hasText: 'answer privately please' })).toBeVisible();
});

test('incognito: starting a new chat destroys the incognito thread and restores the model', async ({ page }) => {
  await page.goto(harnessURL());
  await sendComposerPrompt(page, 'seed thread');
  const modelBefore = (await page.getByTestId('model-picker-button').textContent())?.trim() || '';

  await openIncognito(page);
  await sendComposerPrompt(page, 'ephemeral words');

  // New chat exits incognito: banner gone, model restored, picker unlocked, and the incognito
  // thread is gone for good (still exactly one durable sidebar row).
  const message = page.getByLabel('Message');
  await message.fill('/new');
  await message.press('Enter');

  await expect(page.getByTestId('incognito-banner')).toHaveCount(0);
  await expect(page.getByTestId('model-picker-button')).toBeEnabled();
  await expect(page.getByTestId('model-picker-button')).toHaveText(modelBefore);
  await expect(page.getByTestId('sidebar-thread-row').filter({ hasText: 'Incognito' })).toHaveCount(0);
});

test('incognito: opening incognito twice replaces the session and still restores the original model', async ({ page }) => {
  await page.goto(harnessURL());
  await sendComposerPrompt(page, 'seed thread');
  const modelBefore = (await page.getByTestId('model-picker-button').textContent())?.trim() || '';

  await openIncognito(page);
  await openIncognito(page);

  // Leaving the SECOND incognito session must restore the pre-incognito model — not the pinned
  // E2E label the first session's exit state was overwritten with.
  const message = page.getByLabel('Message');
  await message.fill('/new');
  await message.press('Enter');
  await expect(page.getByTestId('incognito-banner')).toHaveCount(0);
  await expect(page.getByTestId('model-picker-button')).toHaveText(modelBefore);
});

test('incognito: the palette command opens it and selecting another thread discards it', async ({ page }) => {
  await page.goto(harnessURL());
  await sendComposerPrompt(page, 'durable work item');

  // Open via the command palette (the native command id new-incognito-chat).
  await page.getByTestId('top-bar-overflow-button').click();
  await page.getByTestId('top-bar-overflow-command-palette').click();
  await page.getByTestId('command-palette-input').fill('incognito');
  await page.locator('[data-testid="command-palette-result"][data-command-id="new-incognito-chat"]').first().click();
  await expect(page.getByTestId('incognito-banner')).toBeVisible();

  // Selecting the durable thread from the sidebar discards the incognito chat entirely.
  await page.getByTestId('sidebar-thread-row').filter({ hasText: 'durable work item' }).first().click();
  await expect(page.getByTestId('incognito-banner')).toHaveCount(0);
  await expect(page.getByTestId('message').filter({ hasText: 'durable work item' })).toBeVisible();
});
