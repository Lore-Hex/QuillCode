import { test, expect } from '@playwright/test';
import { clickSidebarTool, harnessURL } from './harness-helpers';

test('mock harness shows project extension manifests from sidebar and command palette', async ({ page }) => {
  await page.goto(harnessURL());

  await clickSidebarTool(page, 'extensions-button');

  await expect(page.getByTestId('extensions-pane')).toBeVisible();
  await expect(page.getByTestId('extensions-subtitle')).toHaveText('1 plugin · 1 skill · 1 MCP server');
  await expect(page.getByTestId('extensions-count')).toContainText(['1 plugin', '1 skill', '1 MCP server']);
  await expect(page.getByTestId('extension-item')).toHaveCount(3);
  await expect(page.getByTestId('extension-item').first()).toContainText('GitHub');
  await expect(page.getByTestId('extension-version')).toHaveText('v1.2.0');
  await expect(page.getByTestId('extension-source')).toHaveText('https://github.com/Lore-Hex/quillcode-github');
  await expect(page.getByTestId('extension-update-command')).toHaveText('git -C .quillcode/plugins/github pull --ff-only');
  await expect(page.getByTestId('extension-update')).toBeVisible();
  await page.getByTestId('extension-update').click();
  await expect(page.getByTestId('message').last()).toContainText('GitHub update finished.');
  await expect(page.getByTestId('extension-item').nth(1)).toContainText('Code Review');
  await expect(page.getByTestId('extension-item').nth(2)).toContainText('Stopped');
  await expect(page.getByTestId('extension-transport')).toHaveText('STDIO');
  await expect(page.getByTestId('extension-command')).toHaveText('quill-mcp-filesystem --root .');
  await expect(page.getByTestId('extension-start')).toBeVisible();
  await page.getByTestId('extension-start').click();
  await expect(page.getByTestId('extension-item').nth(2)).toContainText('Ready');
  await expect(page.getByTestId('extension-mcp-server')).toHaveText('Fixture MCP 1.0.0');
  await expect(page.getByTestId('extension-mcp-tools-count')).toHaveText('2 tools');
  await expect(page.getByTestId('extension-mcp-group-label')).toContainText(['Tools', 'Resources', 'Prompts']);
  await expect(page.getByTestId('extension-mcp-tool')).toContainText(['read_file', 'write_file']);
  await expect(page.getByTestId('extension-mcp-tool-schema')).toContainText([
    'required: path:string',
    'required: content:string, path:string; optional: overwrite:boolean'
  ]);
  await expect(page.getByTestId('extension-mcp-resources-count')).toHaveText('2 resources');
  await expect(page.getByTestId('extension-mcp-resource')).toContainText(['README', 'Project config']);
  await expect(page.getByTestId('extension-mcp-prompts-count')).toHaveText('1 prompt');
  await expect(page.getByTestId('extension-mcp-prompt')).toContainText(['summarize_project']);
  await expect(page.getByTestId('extension-stop')).toBeVisible();
  await page.getByTestId('extension-stop').click();
  await expect(page.getByTestId('extension-item').nth(2)).toContainText('Stopped');

  await clickSidebarTool(page, 'extensions-button');
  await expect(page.getByTestId('extensions-pane')).toHaveCount(0);

  await clickSidebarTool(page, 'command-palette-button');
  const commandSearch = page.getByLabel('Search commands');
  await expect(page.getByTestId('command-palette-panel')).toBeVisible();
  await expect(commandSearch).toBeFocused();
  await commandSearch.fill('>update github');
  await expect(page.locator('[data-testid="command-palette-result"][data-command-id="extension-update:plugin:github"]')).toContainText('Update GitHub');
  await commandSearch.fill('>extensions');
  await page.locator('[data-testid="command-palette-result"][data-command-id="toggle-extensions"]').click();
  await expect(page.getByTestId('extensions-pane')).toBeVisible();
});
