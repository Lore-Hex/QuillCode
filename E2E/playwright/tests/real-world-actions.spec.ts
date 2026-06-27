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
