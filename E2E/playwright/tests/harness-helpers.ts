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

export function commandPaletteResult(page: Page, commandID: string) {
  return page.locator(`[data-testid="command-palette-result"][data-command-id="${commandID}"]`);
}

export async function fillCommandPalette(page: Page, query: string) {
  const input = page.getByTestId('command-palette-input');
  await expect(input).toBeVisible();
  await input.fill(query);
  await expect(input).toHaveValue(query);
}

export async function clickCommandPaletteCommand(page: Page, query: string, commandID: string) {
  await fillCommandPalette(page, query);
  const result = commandPaletteResult(page, commandID);
  await expect(result).toBeVisible();
  await result.click();
}

export async function openTopBarOverflow(page: Page) {
  await page.getByTestId('top-bar-overflow-button').click();
  await expect(page.getByTestId('top-bar-overflow-menu')).toHaveAttribute('open', '');
}

export async function openSettings(page: Page) {
  await openTopBarOverflow(page);
  await page.getByTestId('top-bar-overflow-settings').click();
}
