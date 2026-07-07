import { test, expect } from '@playwright/test';
import { clickSidebarTool, harnessURL } from './harness-helpers';

test('mock harness opens browser preview and records comments', async ({ page }) => {
  await page.goto(harnessURL());

  await clickSidebarTool(page, 'command-palette-button');
  await page.getByLabel('Search commands').fill('>browser');
  await page.getByTestId('command-palette-result').first().click();

  await expect(page.getByTestId('browser-pane')).toBeVisible();
  await expect(page.getByTestId('browser-empty')).toBeVisible();
  await expect(page.getByTestId('browser-session')).toBeDisabled();

  await page.getByLabel('Browser address').fill('localhost:5173');
  await expect(page.getByTestId('browser-open')).toBeEnabled();
  await expect(page.getByTestId('browser-session')).toBeEnabled();
  await page.getByTestId('browser-session').click();

  await expect(page.getByTestId('browser-current-url')).toHaveText('http://localhost:5173');
  await expect(page.getByTestId('browser-status-label')).toHaveText('Session open');
  await expect(page.getByTestId('browser-session-status')).toContainText('Visible session 1:');
  await expect(page.getByTestId('browser-session-url')).toHaveText('http://localhost:5173');

  await page.getByTestId('browser-open').click();

  await expect(page.getByTestId('browser-current-url')).toHaveText('http://localhost:5173');
  await expect(page.getByTestId('browser-status-label')).toHaveText('Preview ready');
  await expect(page.getByTestId('browser-back')).toBeDisabled();
  await expect(page.getByTestId('browser-forward')).toBeDisabled();
  await expect(page.getByTestId('browser-reload')).toBeEnabled();
  await expect(page.getByTestId('browser-source')).toHaveText('Local web app');
  await expect(page.getByTestId('browser-inspection-depth')).toHaveText('Network HTML snapshot');
  await expect(page.getByTestId('browser-inspection-depth')).toHaveAttribute('data-depth', 'network_html_snapshot');
  await expect(page.getByTestId('browser-snapshot-summary')).toHaveText(
    'Fetched a network HTML snapshot for this local page.'
  );
  await expect(page.getByTestId('browser-snapshot-detail')).toContainText([
    'Host: localhost',
    'Scheme: HTTP',
    'Path: /',
    'HTTP: 200',
    'Title: Vite Preview',
    'Heading: QuillCode Browser Preview'
  ]);
  await expect(page.getByTestId('browser-snapshot-outline-item')).toContainText([
    'H1: QuillCode Browser Preview',
    'Link: Dashboard -> /dashboard',
    'Button: Launch',
    'Input: Search workspace'
  ]);
  const outlineStyle = await page.getByTestId('browser-snapshot-outline-item').first().evaluate((element) => {
    const style = getComputedStyle(element);
    return {
      backgroundColor: style.backgroundColor,
      borderRadius: style.borderRadius
    };
  });
  expect(outlineStyle.backgroundColor).toBe('rgba(0, 0, 0, 0)');
  expect(outlineStyle.borderRadius).toBe('0px');

  await expect(page.getByTestId('browser-tab')).toHaveCount(1);
  await expect(page.getByTestId('browser-close-tab')).toBeDisabled();
  await page.getByTestId('browser-new-tab').click();
  await expect(page.getByTestId('browser-tab')).toHaveCount(2);
  await expect(page.getByTestId('browser-empty')).toBeVisible();
  await expect(page.getByTestId('browser-close-tab')).toBeEnabled();

  await page.getByLabel('Browser address').fill('example.com/docs');
  await page.getByTestId('browser-open').click();
  await expect(page.getByTestId('browser-current-url')).toHaveText('https://example.com/docs');
  await page.getByTestId('browser-tab').first().click();
  await expect(page.getByTestId('browser-current-url')).toHaveText('http://localhost:5173');
  await page.getByTestId('browser-tab').nth(1).click();
  await expect(page.getByTestId('browser-current-url')).toHaveText('https://example.com/docs');
  await page.getByTestId('browser-close-tab').click();
  await expect(page.getByTestId('browser-tab')).toHaveCount(1);
  await expect(page.getByTestId('browser-current-url')).toHaveText('http://localhost:5173');

  await page.getByLabel('Browser address').fill('example.com/docs');
  await page.getByTestId('browser-open').click();
  await expect(page.getByTestId('browser-current-url')).toHaveText('https://example.com/docs');
  await expect(page.getByTestId('browser-back')).toBeEnabled();
  await expect(page.getByTestId('browser-forward')).toBeDisabled();

  await page.getByLabel('Browser address').fill('localhost:5173/dashboard');
  await clickSidebarTool(page, 'command-palette-button');
  await page.getByLabel('Search commands').fill('>session');
  await page.locator('[data-testid="command-palette-result"][data-command-id="open-browser-session"]').click();
  await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);
  await expect(page.getByTestId('browser-current-url')).toHaveText('http://localhost:5173/dashboard');
  await expect(page.getByTestId('browser-status-label')).toHaveText('Session open');
  await expect(page.getByTestId('browser-session-status')).toContainText('Visible session 2:');
  await expect(page.getByTestId('browser-session-url')).toHaveText('http://localhost:5173/dashboard');

  await page.getByTestId('browser-back').click();
  await expect(page.getByTestId('browser-current-url')).toHaveText('https://example.com/docs');
  await page.getByTestId('browser-back').click();
  await expect(page.getByTestId('browser-current-url')).toHaveText('http://localhost:5173');
  await expect(page.getByTestId('browser-back')).toBeDisabled();
  await expect(page.getByTestId('browser-forward')).toBeEnabled();

  await page.getByTestId('browser-forward').click();
  await expect(page.getByTestId('browser-current-url')).toHaveText('https://example.com/docs');
  await page.getByTestId('browser-reload').click();
  await expect(page.getByTestId('browser-status-label')).toHaveText('Reloaded');

  await page.getByLabel('Browser comment').fill('Check hero spacing');
  await expect(page.getByTestId('browser-add-comment')).toBeEnabled();
  await page.getByTestId('browser-add-comment').click();

  await expect(page.getByTestId('browser-comment')).toContainText('Check hero spacing');
  await expect(page.getByTestId('browser-status-label')).toHaveText('Comment added');
});

test('mock harness opens browser preview from chat', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('open localhost:5173 in the browser');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.browser.open');
  await expect(page.getByTestId('tool-card-input').last()).toContainText('localhost:5173');
  await expect(page.getByText('Opened `Vite Preview` at http://localhost:5173.')).toBeVisible();
  await expect(page.getByTestId('browser-pane')).toBeVisible();
  await expect(page.getByTestId('browser-current-url')).toHaveText('http://localhost:5173');
  await expect(page.getByTestId('browser-inspection-depth')).toHaveText('Network HTML snapshot');
});

test('mock harness opens browser preview from slash target', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('/browser docs/index.html');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByText('Opened browser preview for index.html at file:///workspace/docs/index.html.')).toBeVisible();
  await expect(page.getByTestId('browser-pane')).toBeVisible();
  await expect(page.getByTestId('browser-current-url')).toHaveText('file:///workspace/docs/index.html');
  await expect(page.getByTestId('browser-source')).toHaveText('Local HTML');

  await page.getByLabel('Message').fill('/preview not-a-browser-target');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByText('Enter an http, https, file, localhost, or project file URL.')).toBeVisible();
  await expect(page.getByTestId('browser-status-label')).toHaveText('Invalid address');
});

test('mock harness opens visible browser session from slash target', async ({ page }) => {
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('/session localhost:5173/dashboard');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByText('Opened browser session for http://localhost:5173/dashboard.')).toBeVisible();
  await expect(page.getByTestId('browser-pane')).toBeVisible();
  await expect(page.getByTestId('browser-current-url')).toHaveText('http://localhost:5173/dashboard');
  await expect(page.getByTestId('browser-status-label')).toHaveText('Session open');
  await expect(page.getByTestId('browser-session-status')).toContainText('Visible session 1:');
  await expect(page.getByTestId('browser-session-url')).toHaveText('http://localhost:5173/dashboard');

  await page.getByLabel('Message').fill('/browser-session');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByText('Opened browser session for http://localhost:5173/dashboard.')).toHaveCount(2);
  await expect(page.getByTestId('browser-session-status')).toContainText('Visible session 2:');
});
