import { expect, type Page } from '@playwright/test';

export function harnessURL(): string {
  return 'file://' + process.cwd() + '/../harness/index.html';
}

export async function openSidebarTools(page: Page) {
  await page.getByTestId('sidebar-tools-button').click();
  await expect(page.getByTestId('sidebar-tools-menu')).toHaveAttribute('open', '');
}

export async function clickSidebarTool(page: Page, testID: string) {
  await openSidebarTools(page);
  await page.getByTestId(testID).click();
}

export async function openTopBarOverflow(page: Page) {
  await page.getByTestId('top-bar-overflow-button').click();
  await expect(page.getByTestId('top-bar-overflow-menu')).toHaveAttribute('open', '');
}

export async function openSettings(page: Page) {
  await openTopBarOverflow(page);
  await page.getByTestId('top-bar-overflow-settings').click();
}
