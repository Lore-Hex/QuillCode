import { test, expect } from '@playwright/test';
import { harnessURL } from './harness-helpers';

test('runs natural shell requests immediately with nonempty arguments', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('whoami?');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card')).toHaveCount(1);
  await expect(page.getByTestId('tool-card-title')).toHaveText('host.shell.run');
  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-status', 'done');
  await expect(page.getByTestId('tool-card-input')).toContainText('"cmd": "whoami"');
  await expect(page.getByTestId('tool-card-input')).not.toContainText('{}');
  await expect(page.getByTestId('tool-card-input')).not.toContainText('whoami?');
  await expect(page.getByTestId('tool-card-output')).toContainText('mock-user');
  await expect(page.getByText('You are `mock-user` in this workspace.')).toBeVisible();
  await expect(page.getByText(/No shell command was specified/i)).toHaveCount(0);
  await expect(page.getByText(/I'?ll run|I'?ll check|should I|do you want me to/i)).toHaveCount(0);

  await page.getByLabel('Message').fill('Run `ls`');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card')).toHaveCount(2);
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.shell.run');
  await expect(page.getByTestId('tool-card-input').last()).toContainText('"cmd": "ls"');
  await expect(page.getByTestId('tool-card-input').last()).not.toContainText('{}');
  await expect(page.getByTestId('tool-card-output').last()).toContainText('ran: ls');
  await expect(page.getByText('Output:\nran: ls')).toBeVisible();
  await expect(page.getByText(/No shell command was specified/i)).toHaveCount(0);

  await page.getByLabel('Message').fill('Please run `printf quillcode_now_smoke` now and report the output.');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card')).toHaveCount(3);
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.shell.run');
  await expect(page.getByTestId('tool-card-input').last()).toContainText('"cmd": "printf quillcode_now_smoke"');
  await expect(page.getByTestId('tool-card-input').last()).not.toContainText('{}');
  await expect(page.getByTestId('tool-card-output').last()).toContainText('quillcode_now_smoke');
  await expect(page.getByText('Output:\nquillcode_now_smoke')).toBeVisible();
  await expect(page.getByText(/I'?ll run|I'?ll check|should I|do you want me to|ok\?/i)).toHaveCount(0);

  await page.getByLabel('Message').fill('Can you run printf quillcode_polite_smoke?');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card')).toHaveCount(4);
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.shell.run');
  await expect(page.getByTestId('tool-card-input').last()).toContainText('"cmd": "printf quillcode_polite_smoke"');
  await expect(page.getByTestId('tool-card-input').last()).not.toContainText('{}');
  await expect(page.getByTestId('tool-card-output').last()).toContainText('quillcode_polite_smoke');
  await expect(page.getByText('Output:\nquillcode_polite_smoke')).toBeVisible();
  await expect(page.getByText(/I'?ll run|I'?ll check|should I|do you want me to|ok\?/i)).toHaveCount(0);

  await page.getByLabel('Message').fill('Can you list the files here?');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card')).toHaveCount(5);
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.shell.run');
  await expect(page.getByTestId('tool-card-input').last()).toContainText('"cmd": "ls -la"');
  await expect(page.getByTestId('tool-card-input').last()).not.toContainText('{}');
  await expect(page.getByTestId('tool-card-output').last()).toContainText('ran: ls -la');
  await expect(page.getByText('Output:\nran: ls -la')).toBeVisible();
  await expect(page.getByText(/I'?ll list|should I|do you want me to|ok\?/i)).toHaveCount(0);

  await page.getByLabel('Message').fill('Can you show me the current directory?');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card')).toHaveCount(6);
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.shell.run');
  await expect(page.getByTestId('tool-card-input').last()).toContainText('"cmd": "pwd"');
  await expect(page.getByTestId('tool-card-input').last()).not.toContainText('{}');
  await expect(page.getByTestId('tool-card-output').last()).toContainText('/mock/QuillCode');
  await expect(page.getByText('Output:\n/mock/QuillCode')).toBeVisible();
  await expect(page.getByText(/I'?ll show|should I|do you want me to|ok\?/i)).toHaveCount(0);
});

test('writes requested file content immediately without a confirmation loop', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('Can you write a file that says "hello world"');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('message')).toHaveCount(2);
  await expect(page.getByTestId('tool-card')).toHaveCount(1);
  await expect(page.getByTestId('tool-card-title')).toHaveText('host.file.write');
  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-status', 'done');
  await expect(page.getByTestId('tool-card-input')).toContainText('"path": "hello.txt"');
  await expect(page.getByTestId('tool-card-input')).toContainText('hello world');
  await expect(page.getByTestId('tool-card-input')).not.toContainText('{}');
  await expect(page.getByTestId('tool-card-artifact-label')).toHaveText('hello.txt');
  await expect(page.getByTestId('tool-card-text-preview-content')).toHaveText('hello world');
  await expect(page.getByTestId('tool-card-output')).toContainText('/mock/QuillCode/hello.txt');
  await expect(page.getByText('Wrote `hello.txt`.')).toBeVisible();
  await expect(page.getByText(/I'?ll write|should I|do you want me to|ok\?/i)).toHaveCount(0);
});

test('answers device diagnostic prompts with concrete shell actions', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('How much hd?');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card')).toHaveCount(1);
  await expect(page.getByTestId('tool-card-title')).toHaveText('host.shell.run');
  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-status', 'done');
  await expect(page.getByTestId('tool-card-input')).toContainText('"cmd": "df -h / /Quill 2>/dev/null || df -h /"');
  await expect(page.getByTestId('tool-card-input')).not.toContainText('{}');
  await expect(page.getByTestId('tool-card-output')).toContainText('/mock/QuillCode');
  await expect(page.getByText('Workspace storage: 15% used.')).toBeVisible();
  await expect(page.getByText(/No shell command was specified/i)).toHaveCount(0);
  await expect(page.getByText(/I'?ll check|should I|do you want me to/i)).toHaveCount(0);

  await page.getByLabel('Message').fill('Do you have openclaw?');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card')).toHaveCount(2);
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.shell.run');
  await expect(page.getByTestId('tool-card').last()).toHaveAttribute('data-status', 'done');
  await expect(page.getByTestId('tool-card-input').last())
    .toContainText('"cmd": "command -v openclaw || which openclaw || echo \'not found\'"');
  await expect(page.getByTestId('tool-card-input').last()).not.toContainText('{}');
  await expect(page.getByTestId('tool-card-output').last()).toContainText('not found');
  await expect(page.getByText('OpenClaw is not installed.')).toBeVisible();
  await expect(page.getByText(/No shell command was specified/i)).toHaveCount(0);
  await expect(page.getByText(/I'?ll check|should I|do you want me to/i)).toHaveCount(0);
});

test('downloads requested domains with a bounded concrete shell action', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('Can you download LinkedIn.com?');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card')).toHaveCount(1);
  await expect(page.getByTestId('tool-card-title')).toHaveText('host.shell.run');
  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-status', 'done');
  await expect(page.getByTestId('tool-card-input')).toContainText('curl -L --fail --silent --show-error');
  await expect(page.getByTestId('tool-card-input')).toContainText("--output 'downloads/linkedin.com.html'");
  await expect(page.getByTestId('tool-card-input')).toContainText('https://www.linkedin.com');
  await expect(page.getByTestId('tool-card-input')).not.toContainText('{}');
  await expect(page.getByTestId('tool-card-output')).toContainText('downloads/linkedin.com.html');
  await expect(page.getByText('Downloaded to `downloads/linkedin.com.html`.')).toBeVisible();
  await expect(page.getByText(/No shell command was specified/i)).toHaveCount(0);
  await expect(page.getByText(/I'?ll download|should I|do you want me to|confirm user intent/i)).toHaveCount(0);
});
