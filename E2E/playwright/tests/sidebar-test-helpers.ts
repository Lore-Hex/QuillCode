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

export async function openSidebarFilterMenu(page: Page) {
  const menu = page.getByTestId('sidebar-filter-menu');
  if (await menu.getAttribute('open') === null) {
    await page.getByTestId('sidebar-filter-menu-button').click();
  }
  await expect(menu).toHaveAttribute('open', '');
}

export async function clickSidebarFilter(page: Page, id: string) {
  await openSidebarFilterMenu(page);
  await page.locator(`[data-testid="sidebar-filter"][data-filter-id="${id}"]`).click();
}

export async function beginSidebarSelection(page: Page) {
  await openSidebarFilterMenu(page);
  await page.locator('[data-sidebar-select-chats="true"]').click();
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
