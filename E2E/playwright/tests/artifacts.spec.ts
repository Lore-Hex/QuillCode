import { test, expect } from '@playwright/test';
import { clickSidebarTool, computedStyleProperties, harnessURL } from './harness-helpers';

test('mock harness surfaces file artifacts from tool cards', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('Can you write a file that says hello world');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.file.write');
  await expect(page.getByTestId('tool-card-artifacts')).toBeVisible();
  await expect(page.getByTestId('tool-card-artifact-label')).toHaveText('hello.txt');
  await expect(page.getByTestId('tool-card-artifact-detail')).toHaveText('/mock/QuillCode');
  await expect(page.getByTestId('tool-card-artifact')).toHaveAttribute('data-kind', 'file');
  await expect(page.getByTestId('tool-card-artifact')).toHaveAttribute('href', 'file:///mock/QuillCode/hello.txt');
  await expect(page.getByTestId('tool-card-text-previews')).toBeVisible();
  await expect(page.getByTestId('tool-card-text-preview-label')).toHaveText('hello.txt');
  await expect(page.getByTestId('tool-card-text-preview-content')).toHaveText('hello world');
  await expect.poll(() => page.getByTestId('tool-card-details').evaluate(element => (element as HTMLDetailsElement).open)).toBe(false);
  await page.getByTestId('tool-card-details').locator('summary').click();
  await expect.poll(() => page.getByTestId('tool-card-details').evaluate(element => (element as HTMLDetailsElement).open)).toBe(true);
  await expect(page.getByTestId('tool-card-output')).toContainText('/mock/QuillCode/hello.txt');
  await expect(page.getByText('Wrote `hello.txt`.')).toBeVisible();

  await clickSidebarTool(page, 'activity-button');
  await expect(page.getByTestId('activity-pane')).toBeVisible();
  await expect(page.getByTestId('activity-task-title')).toContainText('Can you write a file');
  await expect(page.getByTestId('activity-tool')).toContainText('host.file.write');
  await expect(page.getByTestId('activity-artifact')).toContainText('hello.txt');
  await expect(page.getByTestId('activity-artifact')).toContainText('/mock/QuillCode');
  await expect(page.getByTestId('activity-artifact')).not.toContainText('undefined');
  await expect(page.getByTestId('activity-source').first()).toContainText('AGENTS.md');
  await expect(page.getByTestId('activity-source-action')).toHaveCount(2);
  await expect(page.getByTestId('activity-source-action').nth(0)).toHaveText('Open');
  await expect(page.getByTestId('activity-source-action').nth(1)).toHaveText('Edit');
  await expect(page.getByTestId('activity-plan')).toHaveCount(5);
  await expect(page.getByTestId('activity-plan').nth(0)).toContainText('Understand request');
  await expect(page.getByTestId('activity-plan').nth(2)).toContainText('Use tools');
  await expect(page.getByTestId('activity-plan').nth(2)).toContainText('Done');
  await expect(page.getByTestId('activity-plan').nth(4)).toContainText('Answer user');
  await expect(page.getByTestId('activity-handoff')).toContainText('Thread: Can you write a file');
  await expect(page.getByTestId('activity-handoff')).toContainText('Tools: 1 tool (host.file.write)');
  await expect(page.getByTestId('activity-handoff')).toContainText('Artifacts: 1 artifact (hello.txt)');
  await expect(page.getByTestId('activity-handoff')).not.toContainText('\\n');
  await expect(page.getByTestId('activity-final-answer')).toContainText('Wrote `hello.txt`.');

  await page.getByTestId('activity-handoff-section').getByTestId('activity-section-toggle').click();
  await expect(page.getByTestId('activity-handoff-section')).toHaveAttribute('data-collapsed', 'true');
  await expect(page.getByTestId('activity-handoff')).toHaveCount(0);
  await page.getByTestId('activity-handoff-section').getByTestId('activity-section-toggle').click();
  await expect(page.getByTestId('activity-handoff')).toContainText('Latest answer: Wrote `hello.txt`.');

  await page.getByTestId('activity-plan-section').getByTestId('activity-section-toggle').click();
  await expect(page.getByTestId('activity-plan-section')).toHaveAttribute('data-collapsed', 'true');
  await expect(page.getByTestId('activity-plan')).toHaveCount(0);
  await page.getByTestId('activity-plan-section').getByTestId('activity-section-toggle').click();
  await expect(page.getByTestId('activity-plan')).toHaveCount(5);

  await page.getByTestId('activity-tool-section').getByTestId('activity-section-toggle').click();
  await expect(page.getByTestId('activity-tool-section')).toHaveAttribute('data-collapsed', 'true');
  await expect(page.getByTestId('activity-tool')).toHaveCount(0);
  await page.getByTestId('activity-tool-section').getByTestId('activity-section-toggle').click();
  await expect(page.getByTestId('activity-tool-section')).toHaveAttribute('data-collapsed', 'false');
  await expect(page.getByTestId('activity-tool')).toContainText('host.file.write');

  await page.getByTestId('activity-source-action').filter({ hasText: 'Open' }).click();
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.file.read');
  await expect(page.getByTestId('activity-final-answer')).toContainText('Instruction source AGENTS.md:');
  await expect(page.getByTestId('activity-final-answer')).toContainText('Use Swift patterns and keep changes reviewable.');

  await page.getByTestId('activity-source-action').filter({ hasText: 'Edit' }).click();
  await expect(page.getByLabel('Message')).toHaveValue('Edit instruction source AGENTS.md: ');
});

test('mock harness renders image artifact previews from tool cards', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('take a screenshot');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.computer.screenshot');
  await expect(page.getByTestId('tool-card-artifact-label')).toHaveText('screenshot.png');
  await expect(page.getByTestId('tool-card-image-previews')).toBeVisible();
  await expect(page.getByTestId('tool-card-image-preview')).toBeVisible();
  await expect(page.getByTestId('tool-card-image-preview')).toHaveAttribute('data-kind', 'image');
  await expect(page.getByTestId('tool-card-image-preview-type')).toHaveText('Image · PNG');
  await expect(page.getByTestId('tool-card-image-preview-label')).toHaveText('screenshot.png');
  await expect(page.getByTestId('tool-card-image-preview-detail')).toHaveText('/mock/QuillCode/screenshots');
  await expect(page.getByTestId('tool-card-image-preview').locator('img')).toHaveAttribute('src', 'file:///mock/QuillCode/screenshots/screenshot.png');
  const [imageCardStyle, imageStyle] = await Promise.all([
    computedStyleProperties(page, '[data-testid="tool-card-image-preview"]', ['border-radius']),
    computedStyleProperties(page, '[data-testid="tool-card-image-preview"] img', [
      'border-radius',
      'outline-color',
      'outline-width',
      'outline-offset'
    ])
  ]);
  const imageSurface = {
    cardRadius: imageCardStyle['border-radius'],
    imageRadius: imageStyle['border-radius'],
    imageOutlineColor: imageStyle['outline-color'],
    imageOutlineWidth: imageStyle['outline-width'],
    imageOutlineOffset: imageStyle['outline-offset']
  };
  expect(imageSurface.cardRadius).toBe('10px');
  expect(imageSurface.imageRadius).toBe('10px');
  expect(imageSurface.imageOutlineColor).toBe('rgba(255, 255, 255, 0.1)');
  expect(imageSurface.imageOutlineWidth).toBe('1px');
  expect(imageSurface.imageOutlineOffset).toBe('-1px');
  await expect(page.getByText('Captured a screenshot of Terminal (1280 x 720).')).toBeVisible();
});

test('mock harness renders SVG artifacts as image previews', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('make an svg artifact');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.file.write');
  await expect(page.getByTestId('tool-card-artifact-label')).toHaveText('logo.svg');
  await expect(page.getByTestId('tool-card-image-previews')).toBeVisible();
  await expect(page.getByTestId('tool-card-image-preview')).toHaveAttribute('data-kind', 'image');
  await expect(page.getByTestId('tool-card-image-preview-type')).toHaveText('Image · SVG · 320 x 180 px');
  await expect(page.getByTestId('tool-card-image-preview-label')).toHaveText('logo.svg');
  await expect(page.getByTestId('tool-card-image-preview-detail')).toHaveText('/mock/QuillCode/artifacts');
  await expect(page.getByTestId('tool-card-image-preview').locator('img')).toHaveAttribute(
    'src',
    'file:///mock/QuillCode/artifacts/logo.svg'
  );
  await expect(page.getByTestId('tool-card-text-previews')).toHaveCount(0);
  await expect(page.getByText('Created `logo.svg`.')).toBeVisible();
});

test('mock harness renders BMP, WebP, TIFF, and ICO artifact dimensions', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('make bitmap artifacts');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.file.write');
  await expect(page.getByTestId('tool-card-artifact-label')).toHaveText(['diagram.bmp', 'preview.webp', 'scan.tiff', 'app.ico']);
  await expect(page.getByTestId('tool-card-image-previews')).toBeVisible();
  await expect(page.getByTestId('tool-card-image-preview')).toHaveCount(4);
  await expect(page.getByTestId('tool-card-image-preview-type')).toHaveText([
    'Image · BMP · 640 x 360 px',
    'Image · WEBP · 512 x 288 px',
    'Image · TIFF · 300 x 200 px',
    'Image · ICO · 256 x 256 px'
  ]);
  await expect(page.getByTestId('tool-card-image-preview-label')).toHaveText(['diagram.bmp', 'preview.webp', 'scan.tiff', 'app.ico']);
  await expect(page.getByText('Created bitmap image artifacts.')).toBeVisible();
});

test('mock harness renders document artifact previews from tool cards', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('make a pdf artifact');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.file.write');
  await expect(page.getByTestId('tool-card-artifact-label')).toHaveText('briefing.pdf');
  await expect(page.getByTestId('tool-card-document-previews')).toBeVisible();
  await expect(page.getByTestId('tool-card-document-preview')).toBeVisible();
  await expect(page.getByTestId('tool-card-document-preview')).toHaveAttribute('data-kind', 'pdf');
  await expect(page.getByTestId('tool-card-document-preview-type')).toHaveText('PDF · PDF');
  await expect(page.getByTestId('tool-card-document-preview-label')).toHaveText('briefing.pdf');
  await expect(page.getByTestId('tool-card-document-preview-detail')).toHaveText('/mock/QuillCode/reports');
  await expect(page.getByTestId('tool-card-document-preview-open')).toHaveAttribute('href', 'file:///mock/QuillCode/reports/briefing.pdf');
  await expect(page.getByTestId('tool-card-pdf-preview')).toBeVisible();
  await expect(page.getByTestId('tool-card-pdf-preview-title')).toHaveText('Quarterly Plan');
  await expect(page.getByTestId('tool-card-pdf-preview-meta')).toContainText([
    'Version: PDF 1.7',
    '2 pages',
    /Size: \d+ bytes/
  ]);
  const [documentCardStyle, documentIconStyle] = await Promise.all([
    computedStyleProperties(page, '[data-testid="tool-card-document-preview"]', [
      'border-radius',
      'min-height',
      'transition-property'
    ]),
    computedStyleProperties(page, '[data-testid="tool-card-document-preview"] .artifact-document-icon', ['border-radius'])
  ]);
  const documentSurface = {
    cardRadius: documentCardStyle['border-radius'],
    cardMinHeight: documentCardStyle['min-height'],
    iconRadius: documentIconStyle['border-radius'],
    transitionProperty: documentCardStyle['transition-property']
  };
  expect(documentSurface.cardRadius).toBe('10px');
  expect(documentSurface.cardMinHeight).toBe('74px');
  expect(documentSurface.iconRadius).toBe('10px');
  expect(documentSurface.transitionProperty).toBe('transform, box-shadow');
  await expect(page.getByText('Created `briefing.pdf`.')).toBeVisible();
});

test('mock harness renders office artifact metadata previews from tool cards', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('make a spreadsheet artifact');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.file.write');
  await expect(page.getByTestId('tool-card-artifact-label')).toHaveText('budget.xlsx');
  await expect(page.getByTestId('tool-card-document-previews')).toBeVisible();
  await expect(page.getByTestId('tool-card-document-preview')).toHaveAttribute('data-kind', 'spreadsheet');
  await expect(page.getByTestId('tool-card-document-preview-type')).toHaveText('Spreadsheet · XLSX');
  await expect(page.getByTestId('tool-card-document-preview-label')).toHaveText('budget.xlsx');
  await expect(page.getByTestId('tool-card-document-preview-detail')).toHaveText('/mock/QuillCode/reports');
  await expect(page.getByTestId('tool-card-document-preview-open')).toHaveAttribute('href', 'file:///mock/QuillCode/reports/budget.xlsx');
  await expect(page.getByTestId('tool-card-office-preview')).toBeVisible();
  await expect(page.getByTestId('tool-card-office-preview-meta')).toHaveText([
    'Format: Office Open XML',
    '7 package entries',
    '2 sheets',
    'Size: 4 KB'
  ]);
  await expect(page.getByText('Created `budget.xlsx`.')).toBeVisible();
});

test('mock harness renders media artifact previews from tool cards', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('make media artifacts');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.file.write');
  await expect(page.getByTestId('tool-card-artifact-label')).toHaveText(['voice-note.mp3', 'demo.mp4']);
  await expect(page.getByTestId('tool-card-document-previews')).toBeVisible();
  await expect(page.getByTestId('tool-card-document-preview')).toHaveCount(2);
  await expect(page.getByTestId('tool-card-document-preview').nth(0)).toHaveAttribute('data-kind', 'audio');
  await expect(page.getByTestId('tool-card-document-preview').nth(1)).toHaveAttribute('data-kind', 'video');
  await expect(page.getByTestId('tool-card-document-preview-type')).toHaveText(['Audio · MP3', 'Video · MP4']);
  await expect(page.getByTestId('tool-card-document-preview-label')).toHaveText(['voice-note.mp3', 'demo.mp4']);
  await expect(page.getByTestId('tool-card-document-preview-detail')).toHaveText([
    '/mock/QuillCode/media',
    '/mock/QuillCode/media'
  ]);
  await expect(page.getByTestId('tool-card-document-preview-open').nth(0)).toHaveAttribute(
    'href',
    'file:///mock/QuillCode/media/voice-note.mp3'
  );
  await expect(page.getByTestId('tool-card-document-preview-open').nth(1)).toHaveAttribute(
    'href',
    'file:///mock/QuillCode/media/demo.mp4'
  );
  await expect(page.getByText('Created media artifacts.')).toBeVisible();
});

test('mock harness renders archive artifact previews from tool cards', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('make archive artifacts');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.file.write');
  await expect(page.getByTestId('tool-card-artifact-label')).toHaveText(['source.zip', 'logs.tar.gz']);
  await expect(page.getByTestId('tool-card-document-previews')).toBeVisible();
  await expect(page.getByTestId('tool-card-document-preview')).toHaveCount(2);
  await expect(page.getByTestId('tool-card-document-preview').nth(0)).toHaveAttribute('data-kind', 'archive');
  await expect(page.getByTestId('tool-card-document-preview').nth(1)).toHaveAttribute('data-kind', 'archive');
  await expect(page.getByTestId('tool-card-document-preview-type')).toHaveText(['Archive · ZIP', 'Archive · TAR.GZ']);
  await expect(page.getByTestId('tool-card-document-preview-label')).toHaveText(['source.zip', 'logs.tar.gz']);
  await expect(page.getByTestId('tool-card-document-preview-detail')).toHaveText([
    '/mock/QuillCode/packages',
    '/mock/QuillCode/packages'
  ]);
  await expect(page.getByTestId('tool-card-archive-preview')).toBeVisible();
  await expect(page.getByTestId('tool-card-archive-preview-meta')).toHaveText([
    'Format: ZIP',
    '4 entries',
    '3 top-level items',
    'Size: 4 KB'
  ]);
  await expect(page.getByTestId('tool-card-document-preview-open').nth(0)).toHaveAttribute(
    'href',
    'file:///mock/QuillCode/packages/source.zip'
  );
  await expect(page.getByTestId('tool-card-document-preview-open').nth(1)).toHaveAttribute(
    'href',
    'file:///mock/QuillCode/packages/logs.tar.gz'
  );
  await expect(page.getByText('Created archive artifacts.')).toBeVisible();
});

test('mock harness renders delimited table artifact previews from tool cards', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('make a csv table artifact');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.file.write');
  await expect(page.getByTestId('tool-card-artifact-label')).toHaveText('revenue.csv');
  await expect(page.getByTestId('tool-card-document-preview')).toHaveAttribute('data-kind', 'spreadsheet');
  await expect(page.getByTestId('tool-card-document-preview-type')).toHaveText('Spreadsheet · CSV');
  await expect(page.getByTestId('tool-card-table-preview')).toBeVisible();
  await expect(page.getByTestId('tool-card-table-preview-meta')).toHaveText([
    'Format: CSV',
    '4 rows, 3 columns'
  ]);
  await expect(page.getByTestId('tool-card-table-preview-header')).toHaveText(['Quarter', 'Revenue', 'Notes']);
  await expect(page.getByTestId('tool-card-table-preview-cell').filter({ hasText: 'Expansion, EU' })).toBeVisible();
  await expect(page.getByText('Created `revenue.csv`.')).toBeVisible();
});

test('mock harness renders appshot artifact previews from tool cards', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('make an appshot artifact');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.appshot.capture');
  await expect(page.getByTestId('tool-card-artifact-label')).toHaveText('checkout.appshot.json');
  await expect(page.getByTestId('tool-card-document-previews')).toBeVisible();
  await expect(page.getByTestId('tool-card-document-preview')).toHaveAttribute('data-kind', 'appshot');
  await expect(page.getByTestId('tool-card-document-preview-type')).toHaveText('Appshot · APPSHOT');
  await expect(page.getByTestId('tool-card-document-preview-label')).toHaveText('checkout.appshot.json');
  await expect(page.getByTestId('tool-card-document-preview-detail')).toHaveText('/mock/QuillCode/appshots');
  await expect(page.getByTestId('tool-card-appshot-preview')).toBeVisible();
  await expect(page.getByTestId('tool-card-appshot-preview-title')).toHaveText('Checkout flow');
  await expect(page.getByTestId('tool-card-appshot-preview-summary')).toHaveText(
    'Captured checkout page after payment details were entered.'
  );
  await expect(page.getByTestId('tool-card-appshot-preview-meta')).toHaveText([
    'App: QuillCode',
    'Viewport: 1440 x 1000',
    '1 window',
    '2 actions',
    '2 frames',
    '3 events',
    'Captured: 2026-06-21T12:00:00Z'
  ]);
  await expect(page.getByTestId('tool-card-appshot-preview-image')).toHaveAttribute(
    'src',
    'file:///mock/QuillCode/appshots/checkout.png'
  );
  await expect(page.getByTestId('tool-card-document-preview-open')).toHaveAttribute('href', 'file:///mock/QuillCode/appshots/checkout.appshot.json');
  await expect(page.getByTestId('tool-card-text-previews')).toHaveCount(0);
  await expect(page.getByText('Captured appshot `checkout.appshot.json`.')).toBeVisible();
});
