import { test, expect } from '@playwright/test';
import { clickSidebarTool, harnessURL } from './harness-helpers';

test('mock harness runs a command in the integrated terminal', async ({ page }) => {
  await page.goto(harnessURL());

  await clickSidebarTool(page, 'terminal-button');
  await expect(page.getByTestId('terminal-pane')).toBeVisible();
  await expect(page.getByTestId('terminal-cwd')).toHaveText('/mock/QuillCode');
  await expect(page.getByTestId('terminal-empty')).toBeVisible();

  await page.getByLabel('Terminal command').fill('pwd');
  await expect(page.getByTestId('terminal-run')).toBeEnabled();
  await page.getByTestId('terminal-run').click();

  await expect(page.getByTestId('terminal-entry')).toContainText('$ pwd');
  await expect(page.getByTestId('terminal-status')).toHaveText('Running · running');
  await expect(page.getByTestId('terminal-status')).toHaveText('Done · exit 0');
  await expect(page.getByTestId('terminal-stdout')).toContainText('/mock/QuillCode');
  await expect(page.getByLabel('Terminal command')).toHaveValue('');

  await page.getByLabel('Terminal command').fill('stream-demo');
  await page.getByTestId('terminal-run').click();
  await expect(page.getByTestId('terminal-status').last()).toHaveText('Running · running');
  await expect(page.getByTestId('terminal-stdout').last()).toContainText('stream-start');
  await expect(page.getByTestId('terminal-status').last()).toHaveText('Done · exit 0');
  await expect(page.getByTestId('terminal-stdout').last()).toContainText('stream-end');

  await page.getByLabel('Terminal command').fill('ansi-demo');
  await page.getByTestId('terminal-run').click();
  const styledStdout = page.getByTestId('terminal-stdout').last();
  await expect(styledStdout).toHaveText('success warning');
  await expect(styledStdout.locator('.ansi-bold')).toHaveText('success');
  await expect(styledStdout.locator('.ansi-bold')).toHaveCSS('color', 'rgb(0, 205, 0)');
  await expect(styledStdout.locator('.ansi-italic.ansi-underline')).toHaveText('warning');
  const styledStderr = page.getByTestId('terminal-stderr').last();
  await expect(styledStderr.locator('.ansi-strikethrough')).toHaveText('failed');
  await expect(styledStderr.locator('.ansi-strikethrough')).toHaveCSS('color', 'rgb(205, 0, 0)');

  await page.getByLabel('Terminal command').fill('read-demo');
  await page.getByTestId('terminal-run').click();
  await expect(page.getByTestId('terminal-status').last()).toHaveText('Running · running');
  await expect(page.getByLabel('Terminal command')).toBeEnabled();
  await expect(page.getByLabel('Terminal command')).toHaveAttribute('placeholder', 'Send input');
  await expect(page.getByTestId('terminal-run')).toHaveText('Send');
  await expect(page.getByTestId('terminal-stdout').last()).toContainText('input?');
  await page.getByLabel('Terminal command').fill('quill');
  await expect(page.getByTestId('terminal-run')).toBeEnabled();
  await page.getByTestId('terminal-run').click();
  await expect(page.getByTestId('terminal-status').last()).toHaveText('Done · exit 0');
  await expect(page.getByTestId('terminal-stdout').last()).toContainText('hello:quill');

  await page.getByLabel('Terminal command').fill('cd Packages');
  await page.getByTestId('terminal-run').click();
  await expect(page.getByTestId('terminal-status').last()).toHaveText('Done · exit 0');
  await expect(page.getByTestId('terminal-cwd')).toHaveText('/mock/QuillCode/Packages');
  await page.getByLabel('Terminal command').fill('pwd');
  await page.getByTestId('terminal-run').click();
  await expect(page.getByTestId('terminal-stdout').last()).toContainText('/mock/QuillCode/Packages');

  await page.getByLabel('Terminal command').fill('export QUILL_TERMINAL_TEST=from-harness');
  await page.getByTestId('terminal-run').click();
  await expect(page.getByTestId('terminal-status').last()).toHaveText('Done · exit 0');
  await page.getByLabel('Terminal command').fill('printf \'%s\' "$QUILL_TERMINAL_TEST"');
  await page.getByTestId('terminal-run').click();
  await expect(page.getByTestId('terminal-stdout').last()).toHaveText('from-harness');
  await page.getByLabel('Terminal command').fill('unset QUILL_TERMINAL_TEST');
  await page.getByTestId('terminal-run').click();
  await expect(page.getByTestId('terminal-status').last()).toHaveText('Done · exit 0');
  await page.getByLabel('Terminal command').fill('printf \'%s\' "${QUILL_TERMINAL_TEST:-missing}"');
  await page.getByTestId('terminal-run').click();
  await expect(page.getByTestId('terminal-stdout').last()).toHaveText('missing');

  const terminalInput = page.getByLabel('Terminal command');
  await terminalInput.fill('git ');
  await terminalInput.press('ArrowUp');
  await expect(terminalInput).toHaveValue('printf \'%s\' "${QUILL_TERMINAL_TEST:-missing}"');
  await terminalInput.press('ArrowUp');
  await expect(terminalInput).toHaveValue('unset QUILL_TERMINAL_TEST');
  await terminalInput.press('ArrowDown');
  await expect(terminalInput).toHaveValue('printf \'%s\' "${QUILL_TERMINAL_TEST:-missing}"');
  await terminalInput.press('ArrowDown');
  await expect(terminalInput).toHaveValue('git ');

  await page.getByLabel('Terminal command').fill('sleep 5');
  await page.getByTestId('terminal-run').click();
  await expect(page.getByTestId('terminal-status').last()).toHaveText('Running · running');
  await page.getByTestId('terminal-stop').click();
  await expect(page.getByTestId('terminal-status').last()).toHaveText('Stopped · stopped');
  await expect(page.getByTestId('terminal-stderr').last()).toContainText('Command stopped.');

  await expect(page.getByTestId('terminal-clear')).toBeEnabled();
  await page.getByTestId('terminal-clear').click();
  await expect(page.getByTestId('terminal-entry')).toHaveCount(0);
  await expect(page.getByTestId('terminal-empty')).toBeVisible();
  await expect(page.getByTestId('terminal-clear')).toBeDisabled();
});

test('mock harness suspends and resumes a running terminal command', async ({ page }) => {
  await page.goto(harnessURL());
  await clickSidebarTool(page, 'terminal-button');

  // A command that keeps running (waits for input) so job control applies.
  await page.getByLabel('Terminal command').fill('read-demo');
  await page.getByTestId('terminal-run').click();
  await expect(page.getByTestId('terminal-status').last()).toHaveText('Running · running');

  // While running and not suspended: Suspend is offered, Resume is not.
  await expect(page.getByTestId('terminal-suspend')).toBeVisible();
  await expect(page.getByTestId('terminal-resume')).toHaveCount(0);

  // Suspend → Resume replaces Suspend; Stop stays available throughout.
  await page.getByTestId('terminal-suspend').click();
  await expect(page.getByTestId('terminal-resume')).toBeVisible();
  await expect(page.getByTestId('terminal-suspend')).toHaveCount(0);
  await expect(page.getByTestId('terminal-stop')).toBeVisible();

  // Resume → back to Suspend.
  await page.getByTestId('terminal-resume').click();
  await expect(page.getByTestId('terminal-suspend')).toBeVisible();
  await expect(page.getByTestId('terminal-resume')).toHaveCount(0);
});

test('mock harness reports pointer and wheel events to mouse-aware terminal apps', async ({ page }) => {
  await page.goto(harnessURL());
  await clickSidebarTool(page, 'terminal-button');

  await page.getByLabel('Terminal command').fill('mouse-demo');
  await page.getByTestId('terminal-run').click();

  await expect(page.getByTestId('terminal-status').last()).toHaveText('Running · running');
  await expect(page.getByTestId('terminal-mouse-mode')).toHaveText('Mouse · SGR');
  const output = page.getByTestId('terminal-stdout').last();
  await expect(output).toHaveAttribute('data-terminal-mouse-input', 'true');
  await expect(output).toHaveAttribute('data-terminal-mouse-encoding', 'sgr');

  const box = await output.boundingBox();
  if (!box) throw new Error('Mouse-aware terminal output has no visible bounds.');
  await page.mouse.move(box.x + 2, box.y + 9);
  await page.mouse.down();
  await page.mouse.move(box.x + 18, box.y + 9);
  await page.mouse.up();

  await expect(output).toHaveAttribute('data-terminal-mouse-event-count', '3');
  await expect(output).toHaveAttribute('data-last-terminal-mouse-sequence', 'ESC[<0;3;1m');

  await page.mouse.wheel(0, -120);
  await expect(output).toHaveAttribute('data-terminal-mouse-event-count', '4');
  await expect(output).toHaveAttribute('data-last-terminal-mouse-sequence', 'ESC[<64;3;1M');

  await page.keyboard.down('Shift');
  await page.mouse.click(box.x + 18, box.y + 9, { button: 'right' });
  await page.keyboard.up('Shift');
  await expect(output).toHaveAttribute('data-terminal-mouse-event-count', '6');
  await expect(output).toHaveAttribute('data-last-terminal-mouse-sequence', 'ESC[<6;3;1m');

  await page.getByTestId('terminal-stop').click();
  await expect(page.getByTestId('terminal-status').last()).toHaveText('Stopped · stopped');
  await expect(page.getByTestId('terminal-mouse-mode')).toHaveCount(0);
});
