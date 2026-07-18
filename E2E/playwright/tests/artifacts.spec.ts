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
  await expect(page.getByTestId('tool-card-text-preview-metadata')).toBeVisible();
  await expect(page.getByTestId('tool-card-text-preview-meta')).toHaveText([
    'Type: Text',
    '1 line',
    'Size: 12 bytes'
  ]);
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

test('mock harness renders common coding source artifacts as text previews', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('make a vue artifact');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.file.write');
  await expect(page.getByTestId('tool-card-artifact-label')).toHaveText(['Dashboard.vue', 'go.mod']);
  await expect(page.getByTestId('tool-card-text-preview-label')).toHaveText(['Dashboard.vue', 'go.mod']);
  await expect(page.getByTestId('tool-card-text-preview').nth(0).getByTestId('tool-card-text-preview-meta').first()).toHaveText('Type: Vue');
  await expect(page.getByTestId('tool-card-text-preview').nth(1).getByTestId('tool-card-text-preview-meta').first()).toHaveText('Type: Go module');
  await expect(page.getByTestId('tool-card-text-preview-content').nth(0)).toContainText('<template>');
  await expect(page.getByTestId('tool-card-text-preview-content').nth(1)).toContainText('module example.com/quillcode');
  await expect(page.getByText('Created `Dashboard.vue` and `go.mod`.')).toBeVisible();
});

test('mock harness renders common project manifest artifacts with specific source labels', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('make project manifests');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.file.write');
  await expect(page.getByTestId('tool-card-artifact-label')).toHaveText([
    'package.json',
    'tsconfig.json',
    'Cargo.toml'
  ]);
  await expect(page.getByTestId('tool-card-text-preview-label')).toHaveText([
    'package.json',
    'tsconfig.json',
    'Cargo.toml'
  ]);
  await expect(page.getByTestId('tool-card-text-preview').nth(0).getByTestId('tool-card-text-preview-meta').first()).toHaveText('Type: npm package');
  await expect(page.getByTestId('tool-card-text-preview').nth(1).getByTestId('tool-card-text-preview-meta').first()).toHaveText('Type: TypeScript config');
  await expect(page.getByTestId('tool-card-text-preview').nth(2).getByTestId('tool-card-text-preview-meta').first()).toHaveText('Type: Cargo manifest');
  await expect(page.getByTestId('tool-card-text-preview-content').nth(0)).toContainText('"name": "quillcode"');
  await expect(page.getByTestId('tool-card-text-preview-content').nth(1)).toContainText('"strict": true');
  await expect(page.getByTestId('tool-card-text-preview-content').nth(2)).toContainText('[package]');
  await expect(page.getByText('Created project manifest artifacts.')).toBeVisible();
});

test('mock harness renders build control artifacts with specific source labels', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('make build control artifacts');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.file.write');
  await expect(page.getByTestId('tool-card-artifact-label')).toHaveText([
    '.dockerignore',
    'Justfile',
    'WORKSPACE',
    'flake.nix'
  ]);
  await expect(page.getByTestId('tool-card-text-preview-label')).toHaveText([
    '.dockerignore',
    'Justfile',
    'WORKSPACE',
    'flake.nix'
  ]);
  await expect(page.getByTestId('tool-card-text-preview').nth(0).getByTestId('tool-card-text-preview-meta').first()).toHaveText('Type: Docker ignore');
  await expect(page.getByTestId('tool-card-text-preview').nth(1).getByTestId('tool-card-text-preview-meta').first()).toHaveText('Type: Justfile');
  await expect(page.getByTestId('tool-card-text-preview').nth(2).getByTestId('tool-card-text-preview-meta').first()).toHaveText('Type: Bazel workspace');
  await expect(page.getByTestId('tool-card-text-preview').nth(3).getByTestId('tool-card-text-preview-meta').first()).toHaveText('Type: Nix flake');
  await expect(page.getByTestId('tool-card-text-preview-content').nth(0)).toContainText('DerivedData');
  await expect(page.getByTestId('tool-card-text-preview-content').nth(1)).toContainText('swift test');
  await expect(page.getByTestId('tool-card-text-preview-content').nth(2)).toContainText('workspace(name = "quillcode")');
  await expect(page.getByTestId('tool-card-text-preview-content').nth(3)).toContainText('description = "QuillCode"');
  await expect(page.getByText('Created build control artifacts.')).toBeVisible();
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
  await expect(page.getByTestId('tool-card-image-preview-sequence')).toHaveCount(0);
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
  await expect(page.getByTestId('tool-card-image-preview-sequence')).toHaveText([
    'Image 1 of 4',
    'Image 2 of 4',
    'Image 3 of 4',
    'Image 4 of 4'
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
  await expect(page.getByTestId('tool-card-pdf-page-preview')).toHaveAttribute('type', 'application/pdf');
  await expect(page.getByTestId('tool-card-pdf-page-preview')).toHaveAttribute(
    'data',
    'file:///mock/QuillCode/reports/briefing.pdf#page=1'
  );
  await expect(page.getByTestId('tool-card-pdf-page-preview-fallback')).toHaveAttribute(
    'href',
    'file:///mock/QuillCode/reports/briefing.pdf'
  );
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

test('mock harness renders markdown artifact metadata previews from tool cards', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('make a markdown artifact');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.file.write');
  await expect(page.getByTestId('tool-card-artifact-label')).toHaveText('setup.md');
  await expect(page.getByTestId('tool-card-artifact-detail')).toHaveText('/mock/QuillCode/docs');
  await expect(page.getByTestId('tool-card-document-previews')).toBeVisible();
  await expect(page.getByTestId('tool-card-document-preview')).toHaveAttribute('data-kind', 'markdown');
  await expect(page.getByTestId('tool-card-document-preview-type')).toHaveText('Markdown · MD');
  await expect(page.getByTestId('tool-card-document-preview-label')).toHaveText('setup.md');
  await expect(page.getByTestId('tool-card-document-preview-detail')).toHaveText('/mock/QuillCode/docs');
  await expect(page.getByTestId('tool-card-document-preview-open')).toHaveAttribute('href', 'file:///mock/QuillCode/docs/setup.md');
  await expect(page.getByTestId('tool-card-markdown-preview')).toBeVisible();
  await expect(page.getByTestId('tool-card-markdown-preview-title')).toHaveText('Setup Guide');
  await expect(page.getByTestId('tool-card-markdown-preview-meta')).toHaveText([
    '2 headings',
    /Size: \d+ bytes/
  ]);
  await expect(page.getByTestId('tool-card-text-preview-label')).toHaveText('setup.md');
  await expect(page.getByTestId('tool-card-text-preview-content')).toContainText('# Setup Guide');
  await expect(page.getByText('Created `setup.md`.')).toBeVisible();
});

test('mock harness renders MDX artifact metadata previews from tool cards', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('make an mdx artifact');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.file.write');
  await expect(page.getByTestId('tool-card-artifact-label')).toHaveText('component.mdx');
  await expect(page.getByTestId('tool-card-artifact-detail')).toHaveText('/mock/QuillCode/docs');
  await expect(page.getByTestId('tool-card-document-previews')).toBeVisible();
  await expect(page.getByTestId('tool-card-document-preview')).toHaveAttribute('data-kind', 'markdown');
  await expect(page.getByTestId('tool-card-document-preview-type')).toHaveText('Markdown · MDX');
  await expect(page.getByTestId('tool-card-document-preview-label')).toHaveText('component.mdx');
  await expect(page.getByTestId('tool-card-document-preview-open')).toHaveAttribute('href', 'file:///mock/QuillCode/docs/component.mdx');
  await expect(page.getByTestId('tool-card-markdown-preview-title')).toHaveText('Component Guide');
  await expect(page.getByTestId('tool-card-markdown-preview-meta')).toHaveText([
    '2 headings',
    /Size: \d+ bytes/
  ]);
  await expect(page.getByTestId('tool-card-text-preview-label')).toHaveText('component.mdx');
  await expect(page.getByTestId('tool-card-text-preview-meta').first()).toHaveText('Type: MDX');
  await expect(page.getByTestId('tool-card-text-preview-content')).toContainText('<Callout tone="info">Ship the preview.</Callout>');
  await expect(page.getByText('Created `component.mdx`.')).toBeVisible();
});

test('mock harness renders RTF artifact metadata previews from tool cards', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('make an rtf artifact');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.file.write');
  await expect(page.getByTestId('tool-card-artifact-label')).toHaveText('summary.rtf');
  await expect(page.getByTestId('tool-card-artifact-detail')).toHaveText('/mock/QuillCode/docs');
  await expect(page.getByTestId('tool-card-document-previews')).toBeVisible();
  await expect(page.getByTestId('tool-card-document-preview')).toHaveAttribute('data-kind', 'document');
  await expect(page.getByTestId('tool-card-document-preview-type')).toHaveText('Document · RTF');
  await expect(page.getByTestId('tool-card-document-preview-label')).toHaveText('summary.rtf');
  await expect(page.getByTestId('tool-card-document-preview-detail')).toHaveText('/mock/QuillCode/docs');
  await expect(page.getByTestId('tool-card-document-preview-open')).toHaveAttribute('href', 'file:///mock/QuillCode/docs/summary.rtf');
  await expect(page.getByTestId('tool-card-rtf-preview')).toBeVisible();
  await expect(page.getByTestId('tool-card-rtf-preview-title')).toHaveText('Launch Notes');
  await expect(page.getByTestId('tool-card-rtf-preview-meta')).toHaveText([
    'Format: RTF',
    'Encoding: ANSI',
    /Size: \d+ bytes/
  ]);
  await expect(page.getByTestId('tool-card-text-previews')).toHaveCount(0);
  await expect(page.getByText('Created `summary.rtf`.')).toBeVisible();
});

test('mock harness renders HTML artifact metadata previews from tool cards', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('make an html artifact');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.file.write');
  await expect(page.getByTestId('tool-card-artifact-label')).toHaveText('dashboard.html');
  await expect(page.getByTestId('tool-card-artifact-detail')).toHaveText('/mock/QuillCode/docs');
  await expect(page.getByTestId('tool-card-document-previews')).toBeVisible();
  await expect(page.getByTestId('tool-card-document-preview')).toHaveAttribute('data-kind', 'document');
  await expect(page.getByTestId('tool-card-document-preview-type')).toHaveText('Document · HTML');
  await expect(page.getByTestId('tool-card-document-preview-label')).toHaveText('dashboard.html');
  await expect(page.getByTestId('tool-card-document-preview-detail')).toHaveText('/mock/QuillCode/docs');
  await expect(page.getByTestId('tool-card-document-preview-open')).toHaveAttribute('href', 'file:///mock/QuillCode/docs/dashboard.html');
  await expect(page.getByTestId('tool-card-html-preview')).toBeVisible();
  await expect(page.getByTestId('tool-card-html-preview-title')).toHaveText('Quill Dashboard & Metrics');
  await expect(page.getByTestId('tool-card-html-preview-meta')).toHaveText([
    'Format: HTML',
    '2 links',
    '1 script',
    '1 style block',
    /Size: \d+ bytes/
  ]);
  await expect(page.getByTestId('tool-card-text-preview-label')).toHaveText('dashboard.html');
  await expect(page.getByTestId('tool-card-text-preview-content')).toContainText('<!doctype html>');
  await expect(page.getByText('Created `dashboard.html`.')).toBeVisible();
});

test('mock harness renders diff artifact metadata previews from tool cards', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('make a diff artifact');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.file.write');
  await expect(page.getByTestId('tool-card-artifact-label')).toHaveText('refactor.diff');
  await expect(page.getByTestId('tool-card-artifact-detail')).toHaveText('/mock/QuillCode/changes');
  await expect(page.getByTestId('tool-card-document-previews')).toBeVisible();
  await expect(page.getByTestId('tool-card-document-preview')).toHaveAttribute('data-kind', 'data');
  await expect(page.getByTestId('tool-card-document-preview-type')).toHaveText('Data · DIFF');
  await expect(page.getByTestId('tool-card-document-preview-label')).toHaveText('refactor.diff');
  await expect(page.getByTestId('tool-card-diff-preview')).toBeVisible();
  await expect(page.getByTestId('tool-card-diff-preview-meta')).toHaveText([
    'Format: Unified diff',
    '2 files',
    '3 hunks',
    '+4 / -2',
    /Size: \d+ bytes/
  ]);
  await expect(page.getByTestId('tool-card-diff-preview-file-item')).toHaveText([
    'Sources/App.swift',
    'Tests/AppTests.swift'
  ]);
  await expect(page.getByTestId('tool-card-text-preview-label')).toHaveText('refactor.diff');
  await expect(page.getByTestId('tool-card-text-preview-content')).toContainText('diff --git');
  await expect(page.getByText('Created `refactor.diff`.')).toBeVisible();
});

test('mock harness renders JSON artifact metadata previews from tool cards', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('make a json artifact');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.file.write');
  await expect(page.getByTestId('tool-card-artifact-label')).toHaveText('build-report.json');
  await expect(page.getByTestId('tool-card-artifact-detail')).toHaveText('/mock/QuillCode/reports');
  await expect(page.getByTestId('tool-card-document-previews')).toBeVisible();
  await expect(page.getByTestId('tool-card-document-preview')).toHaveAttribute('data-kind', 'data');
  await expect(page.getByTestId('tool-card-document-preview-type')).toHaveText('Data · JSON');
  await expect(page.getByTestId('tool-card-document-preview-label')).toHaveText('build-report.json');
  await expect(page.getByTestId('tool-card-document-preview-detail')).toHaveText('/mock/QuillCode/reports');
  await expect(page.getByTestId('tool-card-document-preview-open')).toHaveAttribute(
    'href',
    'file:///mock/QuillCode/reports/build-report.json'
  );
  await expect(page.getByTestId('tool-card-json-preview')).toBeVisible();
  await expect(page.getByTestId('tool-card-json-preview-meta')).toHaveText([
    'Root: Object',
    '7 keys',
    'Keys: artifacts, commit, durationMs, generatedAt, platform, status, +1 more',
    /Size: \d+ bytes/
  ]);
  await expect(page.getByTestId('tool-card-json-preview-key-title')).toHaveText('Top keys');
  await expect(page.getByTestId('tool-card-json-preview-key-item')).toHaveText([
    'artifacts',
    'commit',
    'durationMs',
    'generatedAt',
    'platform',
    'status'
  ]);
  await expect(page.getByTestId('tool-card-text-preview-label')).toHaveText('build-report.json');
  await expect(page.getByTestId('tool-card-text-preview-content')).toContainText('"status": "passed"');
  await expect(page.getByText('Created `build-report.json`.')).toBeVisible();
});

test('mock harness renders JSON Lines artifact metadata previews from tool cards', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('make a jsonl artifact');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.file.write');
  await expect(page.getByTestId('tool-card-artifact-label')).toHaveText('events.jsonl');
  await expect(page.getByTestId('tool-card-artifact-detail')).toHaveText('/mock/QuillCode/logs');
  await expect(page.getByTestId('tool-card-document-previews')).toBeVisible();
  await expect(page.getByTestId('tool-card-document-preview')).toHaveAttribute('data-kind', 'data');
  await expect(page.getByTestId('tool-card-document-preview-type')).toHaveText('Data · JSONL');
  await expect(page.getByTestId('tool-card-document-preview-label')).toHaveText('events.jsonl');
  await expect(page.getByTestId('tool-card-document-preview-detail')).toHaveText('/mock/QuillCode/logs');
  await expect(page.getByTestId('tool-card-document-preview-open')).toHaveAttribute(
    'href',
    'file:///mock/QuillCode/logs/events.jsonl'
  );
  await expect(page.getByTestId('tool-card-json-lines-preview')).toBeVisible();
  await expect(page.getByTestId('tool-card-json-lines-preview-meta')).toHaveText([
    'Format: JSONL',
    '3 records',
    'Keys: durationMs, event, level, runId, tool',
    /Size: \d+ bytes/
  ]);
  await expect(page.getByTestId('tool-card-json-lines-preview-key-title')).toHaveText('Observed keys');
  await expect(page.getByTestId('tool-card-json-lines-preview-key-item')).toHaveText([
    'durationMs',
    'event',
    'level',
    'runId',
    'tool'
  ]);
  await expect(page.getByTestId('tool-card-text-preview-label')).toHaveText('events.jsonl');
  await expect(page.getByTestId('tool-card-text-preview-content')).toContainText('"event":"started"');
  await expect(page.getByText('Created `events.jsonl`.')).toBeVisible();
});

test('mock harness renders TOML artifact metadata previews from tool cards', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('make a toml artifact');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.file.write');
  await expect(page.getByTestId('tool-card-artifact-label')).toHaveText('config.toml');
  await expect(page.getByTestId('tool-card-artifact-detail')).toHaveText('/mock/QuillCode/.quillcode');
  await expect(page.getByTestId('tool-card-document-previews')).toBeVisible();
  await expect(page.getByTestId('tool-card-document-preview')).toHaveAttribute('data-kind', 'data');
  await expect(page.getByTestId('tool-card-document-preview-type')).toHaveText('Data · TOML');
  await expect(page.getByTestId('tool-card-document-preview-label')).toHaveText('config.toml');
  await expect(page.getByTestId('tool-card-toml-preview')).toBeVisible();
  await expect(page.getByTestId('tool-card-toml-preview-meta')).toHaveText([
    'Format: TOML',
    '6 top-level keys',
    '4 tables',
    '2 arrays',
    '8 values',
    'Keys: approval_policy, disabled, extra_roots, mcp_servers, model, tools',
    /Size: \d+ bytes/
  ]);
  await expect(page.getByTestId('tool-card-toml-preview-key-title')).toHaveText('Top-level keys');
  await expect(page.getByTestId('tool-card-toml-preview-key-item')).toHaveText([
    'approval_policy',
    'disabled',
    'extra_roots',
    'mcp_servers',
    'model',
    'tools'
  ]);
  await expect(page.getByTestId('tool-card-text-preview-label')).toHaveText('config.toml');
  await expect(page.getByTestId('tool-card-text-preview-content')).toContainText('model = "trustedrouter/fast"');
  await expect(page.getByText('Created `config.toml`.')).toBeVisible();
});

test('mock harness renders INI artifact metadata previews from tool cards', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('make a config artifact');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.file.write');
  await expect(page.getByTestId('tool-card-artifact-label')).toHaveText('quillcode.ini');
  await expect(page.getByTestId('tool-card-artifact-detail')).toHaveText('/mock/QuillCode/config');
  await expect(page.getByTestId('tool-card-document-previews')).toBeVisible();
  await expect(page.getByTestId('tool-card-document-preview')).toHaveAttribute('data-kind', 'data');
  await expect(page.getByTestId('tool-card-document-preview-type')).toHaveText('Data · INI');
  await expect(page.getByTestId('tool-card-document-preview-label')).toHaveText('quillcode.ini');
  await expect(page.getByTestId('tool-card-ini-preview')).toBeVisible();
  await expect(page.getByTestId('tool-card-ini-preview-meta')).toHaveText([
    'Format: INI',
    '3 sections',
    '9 keys',
    'Sections: trustedrouter, workspace, tools',
    /Size: \d+ bytes/
  ]);
  await expect(page.getByTestId('tool-card-ini-preview-section-title')).toHaveText('Sections');
  await expect(page.getByTestId('tool-card-ini-preview-section-item')).toHaveText([
    'trustedrouter',
    'workspace',
    'tools'
  ]);
  await expect(page.getByText('Created `quillcode.ini`.')).toBeVisible();
});

test('mock harness renders dotenv artifact metadata previews without values', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('make a dotenv artifact');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.file.write');
  await expect(page.getByTestId('tool-card-artifact-label')).toHaveText('.env.local');
  await expect(page.getByTestId('tool-card-artifact-detail')).toHaveText('/mock/QuillCode');
  await expect(page.getByTestId('tool-card-document-previews')).toBeVisible();
  await expect(page.getByTestId('tool-card-document-preview')).toHaveAttribute('data-kind', 'data');
  await expect(page.getByTestId('tool-card-document-preview-type')).toHaveText('Data · ENV');
  await expect(page.getByTestId('tool-card-document-preview-label')).toHaveText('.env.local');
  await expect(page.getByTestId('tool-card-dotenv-preview')).toBeVisible();
  await expect(page.getByTestId('tool-card-dotenv-preview-meta')).toHaveText([
    'Format: DOTENV',
    '4 variables',
    '1 exported',
    'Keys: TRUSTEDROUTER_API_KEY, QUILLCODE_MODEL, QUILLCODE_DEBUG, EMPTY_VALUE',
    /Size: \d+ bytes/
  ]);
  await expect(page.getByTestId('tool-card-dotenv-preview-key-title')).toHaveText('Variable names');
  await expect(page.getByTestId('tool-card-dotenv-preview-key-item')).toHaveText([
    'TRUSTEDROUTER_API_KEY',
    'QUILLCODE_MODEL',
    'QUILLCODE_DEBUG',
    'EMPTY_VALUE'
  ]);
  await expect(page.getByText('sk-secret-value')).toHaveCount(0);
  await expect(page.getByText('Created `.env.local`.')).toBeVisible();
});

test('mock harness renders YAML artifact metadata previews from tool cards', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('make a yaml artifact');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.file.write');
  await expect(page.getByTestId('tool-card-artifact-label')).toHaveText('ci.yml');
  await expect(page.getByTestId('tool-card-artifact-detail')).toHaveText('/mock/QuillCode/.github/workflows');
  await expect(page.getByTestId('tool-card-document-previews')).toBeVisible();
  await expect(page.getByTestId('tool-card-document-preview')).toHaveAttribute('data-kind', 'data');
  await expect(page.getByTestId('tool-card-document-preview-type')).toHaveText('Data · YML');
  await expect(page.getByTestId('tool-card-document-preview-label')).toHaveText('ci.yml');
  await expect(page.getByTestId('tool-card-yaml-preview')).toBeVisible();
  await expect(page.getByTestId('tool-card-yaml-preview-meta')).toHaveText([
    'Format: YML',
    'Root: Mapping',
    '3 keys',
    '5 mappings',
    '2 sequences',
    '6 values',
    'Keys: jobs, name, on',
    /Size: \d+ bytes/
  ]);
  await expect(page.getByTestId('tool-card-yaml-preview-key-title')).toHaveText('Top-level keys');
  await expect(page.getByTestId('tool-card-yaml-preview-key-item')).toHaveText(['jobs', 'name', 'on']);
  await expect(page.getByTestId('tool-card-text-preview-label')).toHaveText('ci.yml');
  await expect(page.getByTestId('tool-card-text-preview-content')).toContainText('name: CI');
  await expect(page.getByText('Created `ci.yml`.')).toBeVisible();
});

test('mock harness renders property list artifact metadata previews from tool cards', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('make a plist artifact');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.file.write');
  await expect(page.getByTestId('tool-card-artifact-label')).toHaveText('Info.plist');
  await expect(page.getByTestId('tool-card-artifact-detail')).toHaveText('/mock/QuillCode');
  await expect(page.getByTestId('tool-card-document-previews')).toBeVisible();
  await expect(page.getByTestId('tool-card-document-preview')).toHaveAttribute('data-kind', 'data');
  await expect(page.getByTestId('tool-card-document-preview-type')).toHaveText('Data · PLIST');
  await expect(page.getByTestId('tool-card-document-preview-label')).toHaveText('Info.plist');
  await expect(page.getByTestId('tool-card-plist-preview')).toBeVisible();
  await expect(page.getByTestId('tool-card-plist-preview-meta')).toHaveText([
    'Format: XML PLIST',
    'Root: Dictionary',
    '5 keys',
    '2 dictionaries',
    '2 arrays',
    '6 values',
    'Keys: CFBundleIdentifier, CFBundleName, CFBundleURLTypes, LSMinimumSystemVersion, NSPrincipalClass',
    /Size: \d+ bytes/
  ]);
  await expect(page.getByTestId('tool-card-plist-preview-key-title')).toHaveText('Top-level keys');
  await expect(page.getByTestId('tool-card-plist-preview-key-item')).toHaveText([
    'CFBundleIdentifier',
    'CFBundleName',
    'CFBundleURLTypes',
    'LSMinimumSystemVersion',
    'NSPrincipalClass'
  ]);
  await expect(page.getByText('Created `Info.plist`.')).toBeVisible();
});

test('mock harness renders SQLite artifact metadata previews from tool cards', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('make a sqlite artifact');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.file.write');
  await expect(page.getByTestId('tool-card-artifact-label')).toHaveText('cache.sqlite3');
  await expect(page.getByTestId('tool-card-artifact-detail')).toHaveText('/mock/QuillCode/data');
  await expect(page.getByTestId('tool-card-document-previews')).toBeVisible();
  await expect(page.getByTestId('tool-card-document-preview')).toHaveAttribute('data-kind', 'data');
  await expect(page.getByTestId('tool-card-document-preview-type')).toHaveText('Data · SQLITE3');
  await expect(page.getByTestId('tool-card-document-preview-label')).toHaveText('cache.sqlite3');
  await expect(page.getByTestId('tool-card-document-preview-open')).toHaveAttribute(
    'href',
    'file:///mock/QuillCode/data/cache.sqlite3'
  );
  await expect(page.getByTestId('tool-card-sqlite-preview')).toBeVisible();
  await expect(page.getByTestId('tool-card-sqlite-preview-meta')).toHaveText([
    'Format: SQLite',
    'Page size: 4096 bytes',
    '3 pages',
    'Size: 12 KB'
  ]);
  await expect(page.getByText('Created `cache.sqlite3`.')).toBeVisible();
});

test('mock harness renders WebAssembly artifact metadata previews from tool cards', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('make a wasm artifact');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.file.write');
  await expect(page.getByTestId('tool-card-artifact-label')).toHaveText('module.wasm');
  await expect(page.getByTestId('tool-card-artifact-detail')).toHaveText('/mock/QuillCode/build');
  await expect(page.getByTestId('tool-card-document-previews')).toBeVisible();
  await expect(page.getByTestId('tool-card-document-preview')).toHaveAttribute('data-kind', 'data');
  await expect(page.getByTestId('tool-card-document-preview-type')).toHaveText('Data · WASM');
  await expect(page.getByTestId('tool-card-document-preview-label')).toHaveText('module.wasm');
  await expect(page.getByTestId('tool-card-document-preview-open')).toHaveAttribute(
    'href',
    'file:///mock/QuillCode/build/module.wasm'
  );
  await expect(page.getByTestId('tool-card-wasm-preview')).toBeVisible();
  await expect(page.getByTestId('tool-card-wasm-preview-meta')).toHaveText([
    'Format: WebAssembly',
    'Version: 1',
    'Size: 8 bytes'
  ]);
  await expect(page.getByText('Created `module.wasm`.')).toBeVisible();
});

test('mock harness renders font artifact metadata previews from tool cards', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('make a font artifact');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.file.write');
  await expect(page.getByTestId('tool-card-artifact-label')).toHaveText('Inter.woff2');
  await expect(page.getByTestId('tool-card-artifact-detail')).toHaveText('/mock/QuillCode/assets');
  await expect(page.getByTestId('tool-card-document-previews')).toBeVisible();
  await expect(page.getByTestId('tool-card-document-preview')).toHaveAttribute('data-kind', 'data');
  await expect(page.getByTestId('tool-card-document-preview-type')).toHaveText('Data · WOFF2');
  await expect(page.getByTestId('tool-card-document-preview-label')).toHaveText('Inter.woff2');
  await expect(page.getByTestId('tool-card-document-preview-open')).toHaveAttribute(
    'href',
    'file:///mock/QuillCode/assets/Inter.woff2'
  );
  await expect(page.getByTestId('tool-card-font-preview')).toBeVisible();
  await expect(page.getByTestId('tool-card-font-preview-meta')).toHaveText([
    'Format: WOFF2',
    'Flavor: OpenType CFF',
    '7 tables',
    'Declared size: 32 bytes',
    'Size: 16 bytes'
  ]);
  await expect(page.getByText('Created `Inter.woff2`.')).toBeVisible();
});

test('mock harness renders XML artifact metadata previews from tool cards', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('make an xml artifact');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.file.write');
  await expect(page.getByTestId('tool-card-artifact-label')).toHaveText('manifest.xml');
  await expect(page.getByTestId('tool-card-artifact-detail')).toHaveText('/mock/QuillCode');
  await expect(page.getByTestId('tool-card-document-previews')).toBeVisible();
  await expect(page.getByTestId('tool-card-document-preview')).toHaveAttribute('data-kind', 'data');
  await expect(page.getByTestId('tool-card-document-preview-type')).toHaveText('Data · XML');
  await expect(page.getByTestId('tool-card-document-preview-label')).toHaveText('manifest.xml');
  await expect(page.getByTestId('tool-card-xml-preview')).toBeVisible();
  await expect(page.getByTestId('tool-card-xml-preview-meta')).toHaveText([
    'Format: XML',
    'Root: project',
    '8 elements',
    '8 attributes',
    '1 namespace',
    'Children: dependencies, module, settings',
    /Size: \d+ bytes/
  ]);
  await expect(page.getByTestId('tool-card-xml-preview-child-title')).toHaveText('Root children');
  await expect(page.getByTestId('tool-card-xml-preview-child-item')).toHaveText([
    'dependencies',
    'module',
    'settings'
  ]);
  await expect(page.getByText('Created `manifest.xml`.')).toBeVisible();
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
  await expect(page.getByTestId('tool-card-office-preview-content-title')).toHaveText('Contents');
  await expect(page.getByTestId('tool-card-office-preview-content-item')).toHaveText([
    'Sheet 1',
    'Sheet 2'
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
  await expect(page.getByTestId('tool-card-media-preview')).toHaveCount(2);
  await expect(page.getByTestId('tool-card-media-preview-title')).toHaveText('Morning Notes');
  await expect(page.getByTestId('tool-card-media-preview-meta')).toHaveText([
    'Format: MP3',
    'Artist: Quill',
    'Size: 4 KB',
    'Format: MP4',
    'Size: 8 KB'
  ]);
  await expect(page.getByTestId('tool-card-media-player')).toHaveCount(2);
  await expect(page.getByTestId('tool-card-media-player').nth(0)).toHaveJSProperty('tagName', 'AUDIO');
  await expect(page.getByTestId('tool-card-media-player').nth(0)).toHaveAttribute(
    'src',
    'file:///mock/QuillCode/media/voice-note.mp3'
  );
  await expect(page.getByTestId('tool-card-media-player').nth(1)).toHaveJSProperty('tagName', 'VIDEO');
  await expect(page.getByTestId('tool-card-media-player').nth(1)).toHaveAttribute(
    'src',
    'file:///mock/QuillCode/media/demo.mp4'
  );
  await expect(page.getByText('Created media artifacts.')).toBeVisible();
});

test('mock harness renders archive artifact previews from tool cards', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('make archive artifacts');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.file.write');
  await expect(page.getByTestId('tool-card-artifact-label')).toHaveText([
    'source.zip',
    'app.jar',
    'webapp.war',
    'suite.ear',
    'mobile.apk',
    'ios.ipa',
    'manual.epub',
    'quillcode-1.0.0-py3-none-any.whl',
    'quillcode.vsix',
    'quillcode.xpi',
    'QuillCode.1.0.0.nupkg',
    'sources.7z',
    'sources.rar',
    'sources.tar',
    'report.txt.gz',
    'logs.tar.gz',
    'report.txt.xz',
    'logs.tar.xz',
    'report.txt.bz2',
    'logs.tar.bz2',
    'report.txt.zst',
    'logs.tar.zst'
  ]);
  await expect(page.getByTestId('tool-card-document-previews')).toBeVisible();
  await expect(page.getByTestId('tool-card-document-preview')).toHaveCount(22);
  for (let index = 0; index < 22; index += 1) {
    await expect(page.getByTestId('tool-card-document-preview').nth(index)).toHaveAttribute('data-kind', 'archive');
  }
  await expect(page.getByTestId('tool-card-document-preview-type')).toHaveText([
    'Archive · ZIP',
    'Archive · JAR',
    'Archive · WAR',
    'Archive · EAR',
    'Archive · APK',
    'Archive · IPA',
    'Archive · EPUB',
    'Archive · WHL',
    'Archive · VSIX',
    'Archive · XPI',
    'Archive · NUPKG',
    'Archive · 7Z',
    'Archive · RAR',
    'Archive · TAR',
    'Archive · GZ',
    'Archive · TAR.GZ',
    'Archive · XZ',
    'Archive · TAR.XZ',
    'Archive · BZ2',
    'Archive · TAR.BZ2',
    'Archive · ZST',
    'Archive · TAR.ZST'
  ]);
  await expect(page.getByTestId('tool-card-document-preview-label')).toHaveText([
    'source.zip',
    'app.jar',
    'webapp.war',
    'suite.ear',
    'mobile.apk',
    'ios.ipa',
    'manual.epub',
    'quillcode-1.0.0-py3-none-any.whl',
    'quillcode.vsix',
    'quillcode.xpi',
    'QuillCode.1.0.0.nupkg',
    'sources.7z',
    'sources.rar',
    'sources.tar',
    'report.txt.gz',
    'logs.tar.gz',
    'report.txt.xz',
    'logs.tar.xz',
    'report.txt.bz2',
    'logs.tar.bz2',
    'report.txt.zst',
    'logs.tar.zst'
  ]);
  await expect(page.getByTestId('tool-card-document-preview-detail')).toHaveText([
    '/mock/QuillCode/packages',
    '/mock/QuillCode/packages',
    '/mock/QuillCode/packages',
    '/mock/QuillCode/packages',
    '/mock/QuillCode/packages',
    '/mock/QuillCode/packages',
    '/mock/QuillCode/packages',
    '/mock/QuillCode/packages',
    '/mock/QuillCode/packages',
    '/mock/QuillCode/packages',
    '/mock/QuillCode/packages',
    '/mock/QuillCode/packages',
    '/mock/QuillCode/packages',
    '/mock/QuillCode/packages',
    '/mock/QuillCode/packages',
    '/mock/QuillCode/packages',
    '/mock/QuillCode/packages',
    '/mock/QuillCode/packages',
    '/mock/QuillCode/packages',
    '/mock/QuillCode/packages',
    '/mock/QuillCode/packages',
    '/mock/QuillCode/packages'
  ]);
  await expect(page.getByTestId('tool-card-archive-preview')).toHaveCount(22);
  await expect(page.getByTestId('tool-card-archive-preview-meta')).toHaveText([
    'Format: ZIP',
    '4 entries',
    '3 top-level items',
    'Entries: Sources/App.swift, Sources/Model.swift, Tests/AppTests.swift, +1 more',
    'Size: 4 KB',
    'Format: JAR',
    '3 entries',
    '3 top-level items',
    'Entries: META-INF/MANIFEST.MF, com/example/App.class, assets/config.json',
    'Size: 3 KB',
    'Format: WAR',
    '3 entries',
    '3 top-level items',
    'Entries: META-INF/MANIFEST.MF, com/example/App.class, assets/config.json',
    'Size: 4 KB',
    'Format: EAR',
    '3 entries',
    '3 top-level items',
    'Entries: META-INF/MANIFEST.MF, com/example/App.class, assets/config.json',
    'Size: 5 KB',
    'Format: APK',
    '3 entries',
    '3 top-level items',
    'Entries: META-INF/MANIFEST.MF, com/example/App.class, assets/config.json',
    'Size: 6 KB',
    'Format: IPA',
    '3 entries',
    '3 top-level items',
    'Entries: META-INF/MANIFEST.MF, com/example/App.class, assets/config.json',
    'Size: 7 KB',
    'Format: EPUB',
    '3 entries',
    '3 top-level items',
    'Entries: META-INF/MANIFEST.MF, com/example/App.class, assets/config.json',
    'Size: 8 KB',
    'Format: WHL',
    '3 entries',
    '3 top-level items',
    'Entries: META-INF/MANIFEST.MF, com/example/App.class, assets/config.json',
    'Size: 9 KB',
    'Format: VSIX',
    '3 entries',
    '3 top-level items',
    'Entries: META-INF/MANIFEST.MF, com/example/App.class, assets/config.json',
    'Size: 10 KB',
    'Format: XPI',
    '3 entries',
    '3 top-level items',
    'Entries: META-INF/MANIFEST.MF, com/example/App.class, assets/config.json',
    'Size: 11 KB',
    'Format: NUPKG',
    '3 entries',
    '3 top-level items',
    'Entries: META-INF/MANIFEST.MF, com/example/App.class, assets/config.json',
    'Size: 12 KB',
    'Format: 7Z',
    'Size: 72 bytes',
    'Format: RAR',
    'Size: 80 bytes',
    'Format: TAR',
    '3 entries',
    '2 top-level items',
    'Entries: Sources/App.swift, Sources/Model.swift, Tests/AppTests.swift',
    'Size: 5 KB',
    'Format: GZIP',
    '1 entry',
    '1 top-level item',
    'Entries: report.txt',
    'Uncompressed: 2 KB',
    'Size: 36 bytes',
    'Format: TAR.GZ',
    'Entries: logs.tar',
    'Uncompressed: 8 KB',
    'Size: 44 bytes',
    'Format: XZ',
    '1 entry',
    '1 top-level item',
    'Entries: report.txt',
    'Size: 48 bytes',
    'Format: TAR.XZ',
    'Entries: logs.tar',
    'Size: 56 bytes',
    'Format: BZIP2',
    '1 entry',
    '1 top-level item',
    'Entries: report.txt',
    'Size: 52 bytes',
    'Format: TAR.BZ2',
    'Entries: logs.tar',
    'Size: 60 bytes',
    'Format: ZSTD',
    '1 entry',
    '1 top-level item',
    'Entries: report.txt',
    'Size: 40 bytes',
    'Format: TAR.ZST',
    'Entries: logs.tar',
    'Size: 64 bytes',
  ]);
  await expect(page.getByTestId('tool-card-archive-preview-entry-title')).toHaveText([
    'Contents',
    'Contents',
    'Contents',
    'Contents',
    'Contents',
    'Contents',
    'Contents',
    'Contents',
    'Contents',
    'Contents',
    'Contents',
    'Contents',
    'Contents',
    'Contents',
    'Contents',
    'Contents',
    'Contents',
    'Contents',
    'Contents',
    'Contents'
  ]);
  await expect(page.getByTestId('tool-card-archive-preview-entry-item')).toHaveText([
    'Sources/App.swift',
    'Sources/Model.swift',
    'Tests/AppTests.swift',
    'META-INF/MANIFEST.MF',
    'com/example/App.class',
    'assets/config.json',
    'META-INF/MANIFEST.MF',
    'com/example/App.class',
    'assets/config.json',
    'META-INF/MANIFEST.MF',
    'com/example/App.class',
    'assets/config.json',
    'META-INF/MANIFEST.MF',
    'com/example/App.class',
    'assets/config.json',
    'META-INF/MANIFEST.MF',
    'com/example/App.class',
    'assets/config.json',
    'META-INF/MANIFEST.MF',
    'com/example/App.class',
    'assets/config.json',
    'META-INF/MANIFEST.MF',
    'com/example/App.class',
    'assets/config.json',
    'META-INF/MANIFEST.MF',
    'com/example/App.class',
    'assets/config.json',
    'META-INF/MANIFEST.MF',
    'com/example/App.class',
    'assets/config.json',
    'META-INF/MANIFEST.MF',
    'com/example/App.class',
    'assets/config.json',
    'Sources/App.swift',
    'Sources/Model.swift',
    'Tests/AppTests.swift',
    'report.txt',
    'logs.tar',
    'report.txt',
    'logs.tar',
    'report.txt',
    'logs.tar',
    'report.txt',
    'logs.tar'
  ]);
  await expect(page.getByTestId('tool-card-document-preview-open').nth(0)).toHaveAttribute(
    'href',
    'file:///mock/QuillCode/packages/source.zip'
  );
  await expect(page.getByTestId('tool-card-document-preview-open').nth(1)).toHaveAttribute(
    'href',
    'file:///mock/QuillCode/packages/app.jar'
  );
  await expect(page.getByTestId('tool-card-document-preview-open').nth(2)).toHaveAttribute(
    'href',
    'file:///mock/QuillCode/packages/webapp.war'
  );
  await expect(page.getByTestId('tool-card-document-preview-open').nth(3)).toHaveAttribute(
    'href',
    'file:///mock/QuillCode/packages/suite.ear'
  );
  await expect(page.getByTestId('tool-card-document-preview-open').nth(4)).toHaveAttribute(
    'href',
    'file:///mock/QuillCode/packages/mobile.apk'
  );
  await expect(page.getByTestId('tool-card-document-preview-open').nth(5)).toHaveAttribute(
    'href',
    'file:///mock/QuillCode/packages/ios.ipa'
  );
  await expect(page.getByTestId('tool-card-document-preview-open').nth(6)).toHaveAttribute(
    'href',
    'file:///mock/QuillCode/packages/manual.epub'
  );
  await expect(page.getByTestId('tool-card-document-preview-open').nth(7)).toHaveAttribute(
    'href',
    'file:///mock/QuillCode/packages/quillcode-1.0.0-py3-none-any.whl'
  );
  await expect(page.getByTestId('tool-card-document-preview-open').nth(8)).toHaveAttribute(
    'href',
    'file:///mock/QuillCode/packages/quillcode.vsix'
  );
  await expect(page.getByTestId('tool-card-document-preview-open').nth(9)).toHaveAttribute(
    'href',
    'file:///mock/QuillCode/packages/quillcode.xpi'
  );
  await expect(page.getByTestId('tool-card-document-preview-open').nth(10)).toHaveAttribute(
    'href',
    'file:///mock/QuillCode/packages/QuillCode.1.0.0.nupkg'
  );
  await expect(page.getByTestId('tool-card-document-preview-open').nth(11)).toHaveAttribute(
    'href',
    'file:///mock/QuillCode/packages/sources.7z'
  );
  await expect(page.getByTestId('tool-card-document-preview-open').nth(12)).toHaveAttribute(
    'href',
    'file:///mock/QuillCode/packages/sources.rar'
  );
  await expect(page.getByTestId('tool-card-document-preview-open').nth(13)).toHaveAttribute(
    'href',
    'file:///mock/QuillCode/packages/sources.tar'
  );
  await expect(page.getByTestId('tool-card-document-preview-open').nth(14)).toHaveAttribute(
    'href',
    'file:///mock/QuillCode/packages/report.txt.gz'
  );
  await expect(page.getByTestId('tool-card-document-preview-open').nth(15)).toHaveAttribute(
    'href',
    'file:///mock/QuillCode/packages/logs.tar.gz'
  );
  await expect(page.getByTestId('tool-card-document-preview-open').nth(16)).toHaveAttribute(
    'href',
    'file:///mock/QuillCode/packages/report.txt.xz'
  );
  await expect(page.getByTestId('tool-card-document-preview-open').nth(17)).toHaveAttribute(
    'href',
    'file:///mock/QuillCode/packages/logs.tar.xz'
  );
  await expect(page.getByTestId('tool-card-document-preview-open').nth(18)).toHaveAttribute(
    'href',
    'file:///mock/QuillCode/packages/report.txt.bz2'
  );
  await expect(page.getByTestId('tool-card-document-preview-open').nth(19)).toHaveAttribute(
    'href',
    'file:///mock/QuillCode/packages/logs.tar.bz2'
  );
  await expect(page.getByTestId('tool-card-document-preview-open').nth(20)).toHaveAttribute(
    'href',
    'file:///mock/QuillCode/packages/report.txt.zst'
  );
  await expect(page.getByTestId('tool-card-document-preview-open').nth(21)).toHaveAttribute(
    'href',
    'file:///mock/QuillCode/packages/logs.tar.zst'
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
  await expect(page.getByTestId('tool-card-appshot-replay-title')).toHaveText(['Actions', 'Frames', 'Events']);
  await expect(page.getByTestId('tool-card-appshot-replay-item')).toHaveText([
    '1click: Email',
    '2type: user@example.com',
    '1checkout-start.png',
    '2checkout.png',
    '1navigation',
    '2form-fill',
    '3capture'
  ]);
  await expect(page.getByTestId('tool-card-document-preview-open')).toHaveAttribute('href', 'file:///mock/QuillCode/appshots/checkout.appshot.json');
  await expect(page.getByTestId('tool-card-text-previews')).toHaveCount(0);
  await expect(page.getByText('Captured appshot `checkout.appshot.json`.')).toBeVisible();
});
