import { expect, type Page } from '@playwright/test';

export type ElementRect = {
  height: number;
  left: number;
  right: number;
  top: number;
  width: number;
};

export function harnessURL(): string {
  return 'file://' + process.cwd() + '/../harness/index.html';
}

export async function computedStyleProperties(page: Page, selector: string, properties: string[]) {
  return page.locator(selector).first().evaluate((element, styleProperties) => {
    const style = getComputedStyle(element);
    return Object.fromEntries(
      styleProperties.map(property => [property, style.getPropertyValue(property)])
    );
  }, properties);
}

export async function elementRect(page: Page, selector: string): Promise<ElementRect> {
  return page.locator(selector).first().evaluate(element => {
    const rect = element.getBoundingClientRect();
    return {
      height: rect.height,
      left: rect.left,
      right: rect.right,
      top: rect.top,
      width: rect.width
    };
  });
}

export async function openSidebarTools(page: Page) {
  await page.getByTestId('sidebar-tools-button').click();
  await expect(page.getByTestId('sidebar-tools-menu')).toHaveAttribute('open', '');
}

export async function clickSidebarTool(page: Page, testID: string) {
  const visibleSidebarTarget = page.getByTestId(testID).first();
  if (await visibleSidebarTarget.isVisible().catch(() => false)) {
    await visibleSidebarTarget.click();
    return;
  }

  await openSidebarTools(page);
  await page.getByTestId(testID).click();
}

export async function openCommandPalette(page: Page) {
  await clickSidebarTool(page, 'command-palette-button');
  await expect(page.getByTestId('command-palette-panel')).toBeVisible();
}

export async function expectCommandPaletteClosed(page: Page) {
  await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);
}

export function commandPaletteResult(page: Page, commandID: string) {
  return page.locator(`[data-testid="command-palette-result"][data-command-id="${commandID}"]`);
}

export function selectedCommandPaletteResult(page: Page) {
  return page.locator('[data-testid="command-palette-result"][data-selected="true"]');
}

export async function expectSelectedCommandPaletteResult(page: Page, label: string) {
  await expect(selectedCommandPaletteResult(page)).toContainText(label);
}

export async function fillCommandPalette(page: Page, query: string) {
  const input = page.getByTestId('command-palette-input');
  await expect(input).toBeVisible();
  await expect(input).toBeFocused();
  await input.fill(query);
  await expect(input).toHaveValue(query);
}

export async function fillComposer(page: Page, text: string) {
  const message = page.getByLabel('Message');
  await expect(message).toBeVisible();
  await expect(message).toBeEnabled();

  for (let attempt = 0; attempt < 2; attempt += 1) {
    await message.click();
    await expect(message).toBeFocused();
    await message.fill('');
    await message.fill(text);
    if ((await message.inputValue()) === text) {
      await expect(message).toHaveValue(text);
      return;
    }
  }

  await expect(message).toHaveValue(text);
}

export async function sendComposerPrompt(page: Page, text: string) {
  await fillComposer(page, text);
  const sendButton = page.getByRole('button', { name: 'Send' });
  await expect(sendButton).toBeEnabled();
  await sendButton.click();
}

export async function clickCommandPaletteCommand(page: Page, query: string, commandID: string) {
  await fillCommandPalette(page, query);
  const result = commandPaletteResult(page, commandID);
  await expect(result).toBeVisible();
  await result.click();
}

export async function expectWorktreeChoicesLoaded(page: Page, labels: string[]) {
  await expect(page.getByTestId('worktree-choice')).toContainText(labels);
  await expect(page.getByTestId('worktree-choices-loading')).toHaveCount(0);
}

export async function openTopBarOverflow(page: Page) {
  await page.getByTestId('top-bar-overflow-button').click();
  await expect(page.getByTestId('top-bar-overflow-menu')).toHaveAttribute('open', '');
}

export async function openSettings(page: Page) {
  await openTopBarOverflow(page);
  await page.getByTestId('top-bar-overflow-settings').click();
}
