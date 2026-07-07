import { expect, type Locator, type Page } from '@playwright/test';
import { sendComposerPrompt } from './harness-helpers';

export async function clickProjectAction(row: Locator, name: string) {
  await row.getByLabel(/^Actions for project /).click();
  await row.getByRole('button', { name }).click();
}

export async function clickThreadAction(row: Locator, name: string) {
  await row.getByLabel(/^Actions for /).click();
  await row.getByTestId('sidebar-thread-action').filter({ hasText: new RegExp(`^${name}$`) }).click();
}

export function sidebarSection(page: Page, title: string) {
  return page.getByTestId('sidebar-section').filter({
    has: page.getByTestId('sidebar-section-title').filter({ hasText: new RegExp(`^${title}$`) })
  });
}

export async function sendSidebarPrompt(page: Page, prompt: string) {
  await sendComposerPrompt(page, prompt);
}

export async function sendSidebarPromptThenNewChat(page: Page, prompt: string) {
  await sendSidebarPrompt(page, prompt);
  await page.getByTestId('new-chat-button').click();
}

export async function expectThreadCount(page: Page, count: number) {
  await expect(page.getByTestId('sidebar-thread-row')).toHaveCount(count);
}
