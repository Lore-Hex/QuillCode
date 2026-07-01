import { test, expect } from '@playwright/test';
import {
  clickSidebarTool,
  commandPaletteResult,
  fillCommandPalette,
  harnessURL
} from './harness-helpers';

test('mock harness runs local environment action from the command palette', async ({ page }) => {
  await page.goto(harnessURL());

  await clickSidebarTool(page, 'command-palette-button');
  await fillCommandPalette(page, '>QUILL_ENV');
  await expect(page.getByTestId('command-palette-result')).toHaveCount(1);
  await fillCommandPalette(page, '>warm caches');
  await expect(page.getByTestId('command-palette-result')).toHaveCount(1);
  await expect(page.getByTestId('command-palette-result')).toContainText(
    'Install dependencies and warm caches.'
  );
  await commandPaletteResult(page, 'local-env:.quillcode/actions/bootstrap.sh').click();

  await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);
  await expect(page.getByTestId('tool-card-title')).toHaveText('host.shell.run');
  await expect(page.getByTestId('tool-card-input')).toContainText('.quillcode/actions/bootstrap.sh');
  await expect(page.getByTestId('tool-card-input')).toContainText('QUILL_ENV');
  await expect(page.getByTestId('tool-card-input')).toContainText('<redacted>');
  await expect(page.getByTestId('tool-card-input')).not.toContainText('"dev"');
  await expect(page.getByTestId('message').last()).toContainText('Local environment action completed');
});
