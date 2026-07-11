import { test, expect } from '@playwright/test';
import { harnessURL } from './harness-helpers';

const onePixelPNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  'base64'
);

async function attachImage(page: import('@playwright/test').Page, name = 'screen.png') {
  await page.getByTestId('image-file-input').setInputFiles({
    name,
    mimeType: 'image/png',
    buffer: onePixelPNG
  });
}

test('image-only composer turn previews, sends, and clears the attachment', async ({ page }) => {
  await page.goto(harnessURL());

  await attachImage(page);

  await expect(page.getByTestId('composer-attachment')).toHaveCount(1);
  await expect(page.getByTestId('composer-attachment')).toContainText('screen.png');
  await expect(page.getByRole('button', { name: 'Send' })).toBeEnabled();
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('message-attachment')).toHaveCount(1);
  await expect(page.getByTestId('message-attachment')).toHaveAttribute('alt', 'screen.png');
  await expect(page.getByTestId('composer-attachment')).toHaveCount(0);
});

test('composer image can be removed without changing the typed draft', async ({ page }) => {
  await page.goto(harnessURL());
  await page.getByLabel('Message').fill('Explain this');
  await attachImage(page);

  await page.getByTestId('composer-attachment-remove').click();

  await expect(page.getByTestId('composer-attachment')).toHaveCount(0);
  await expect(page.getByLabel('Message')).toHaveValue('Explain this');
  await expect(page.getByRole('button', { name: 'Send' })).toBeEnabled();
});

test('image-only submission during a live run queues and drains with the image intact', async ({ page }) => {
  await page.goto(harnessURL());
  await page.getByLabel('Message').fill('slow task');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('agent-status')).toHaveText('Running');

  await attachImage(page, 'follow-up.png');
  await page.getByLabel('Message').press('Enter');

  await expect(page.getByTestId('composer-followup-text')).toHaveText('1 image');
  await expect(page.getByTestId('composer-attachment')).toHaveCount(0);
  await expect(page.getByTestId('message-attachment')).toHaveAttribute('alt', 'follow-up.png', {
    timeout: 5000
  });
  await expect(page.getByTestId('composer-followup-queue')).toHaveCount(0);
});
