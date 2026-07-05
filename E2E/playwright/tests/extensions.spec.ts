import { test, expect } from '@playwright/test';
import {
  clickCommandPaletteCommand,
  clickSidebarTool,
  commandPaletteResult,
  fillCommandPalette,
  harnessURL
} from './harness-helpers';

test('mock harness shows project extension manifests from sidebar and command palette', async ({ page }) => {
  await page.goto(harnessURL());

  await clickSidebarTool(page, 'extensions-button');

  await expect(page.getByTestId('extensions-pane')).toBeVisible();
  await expect(page.getByTestId('extensions-subtitle')).toHaveText(
    '1 plugin · 5 skills · 1 MCP server · 4 available extensions'
  );
  await expect(page.getByTestId('extensions-count')).toContainText(['1 plugin', '5 skills', '1 MCP server']);
  await expect(page.getByTestId('extension-item')).toHaveCount(7);

  const githubItem = page.getByTestId('extension-item').first();
  await expect(githubItem).toContainText('GitHub');
  await expect(githubItem.getByTestId('extension-version')).toHaveText('v1.2.0');
  await expect(githubItem.getByTestId('extension-source')).toHaveText('https://github.com/Lore-Hex/quillcode-github');
  await expect(githubItem.getByTestId('extension-install-command')).toHaveText('git clone https://github.com/Lore-Hex/quillcode-github .quillcode/plugins/github');
  await expect(githubItem.getByTestId('extension-install')).toBeVisible();
  await githubItem.getByTestId('extension-install').click();
  await expect(page.getByTestId('message').last()).toContainText('GitHub install finished.');
  await expect(githubItem.getByTestId('extension-update-command')).toHaveText('git -C .quillcode/plugins/github pull --ff-only');
  await expect(githubItem.getByTestId('extension-update')).toBeVisible();
  await githubItem.getByTestId('extension-update').click();
  await expect(page.getByTestId('message').last()).toContainText('GitHub update finished.');
  await expect(page.getByTestId('extension-item').nth(1)).toContainText('Code Review');

  const advisorSkill = page.getByTestId('extension-item').filter({ hasText: 'LLM Advisor' });
  await expect(advisorSkill).toContainText('Available');
  await expect(advisorSkill.getByTestId('extension-source')).toHaveText('https://github.com/Lore-Hex/LLM-advisor');
  const browserSkill = page.getByTestId('extension-item').filter({ hasText: 'Browser Use' });
  await expect(browserSkill).toContainText('https://github.com/browser-use/browser-use/tree/main/skills');
  await browserSkill.getByTestId('extension-install').click();
  await expect(page.getByTestId('message').last()).toContainText('Browser Use install finished.');
  await expect(page.getByTestId('extension-item').nth(4)).toContainText('OpenClaw Video Toolkit');
  await expect(page.getByTestId('extension-item').nth(5)).toContainText('BurstyRouter');
  await expect(page.getByTestId('extension-item').nth(5)).toContainText('Available');
  await expect(page.getByTestId('extension-item').nth(5)).toContainText('https://github.com/Lore-Hex/BurstyRouter');

  const filesystemMCP = page.getByTestId('extension-item').filter({ hasText: 'Filesystem MCP' });
  await expect(filesystemMCP).toContainText('Stopped');
  await expect(filesystemMCP.getByTestId('extension-transport')).toHaveText('STDIO');
  await expect(filesystemMCP.getByTestId('extension-command')).toHaveText('quill-mcp-filesystem --root .');
  await expect(filesystemMCP.getByTestId('extension-start')).toBeVisible();
  await filesystemMCP.getByTestId('extension-start').click();
  await expect(filesystemMCP).toContainText('Ready');
  await expect(filesystemMCP.getByTestId('extension-mcp-server')).toHaveText('Fixture MCP 1.0.0');
  await expect(filesystemMCP.getByTestId('extension-mcp-tools-count')).toHaveText('2 tools');
  await expect(filesystemMCP.getByTestId('extension-mcp-group-label')).toContainText(['Tools', 'Resources', 'Prompts']);
  await expect(filesystemMCP.getByTestId('extension-mcp-tool')).toContainText(['read_file', 'write_file']);
  await expect(filesystemMCP.getByTestId('extension-mcp-tool-schema')).toContainText([
    'required: path:string',
    'required: content:string, path:string; optional: overwrite:boolean'
  ]);
  await expect(filesystemMCP.getByTestId('extension-mcp-resources-count')).toHaveText('2 resources');
  await expect(filesystemMCP.getByTestId('extension-mcp-resource')).toContainText(['README', 'Project config']);
  await expect(filesystemMCP.getByTestId('extension-mcp-prompts-count')).toHaveText('1 prompt');
  await expect(filesystemMCP.getByTestId('extension-mcp-prompt')).toContainText(['summarize_project']);
  await expect(filesystemMCP.getByTestId('extension-mcp-resource-action')).toContainText(['Read README', 'Read Project config']);
  await expect(filesystemMCP.getByTestId('extension-mcp-prompt-action')).toContainText(['Use summarize_project']);
  await filesystemMCP.getByTestId('extension-mcp-resource-action').first().click();
  await expect(page.getByTestId('tool-card').last()).toContainText('host.mcp.resource.read');
  await expect(page.getByTestId('message').last()).toContainText('MCP resource contents:');
  await filesystemMCP.getByTestId('extension-mcp-prompt-action').click();
  await expect(page.getByTestId('tool-card').last()).toContainText('host.mcp.prompt.get');
  await expect(page.getByTestId('message').last()).toContainText('Prompt: summarize_project');
  await expect(filesystemMCP.getByTestId('extension-stop')).toBeVisible();
  await filesystemMCP.getByTestId('extension-stop').click();
  await expect(filesystemMCP).toContainText('Stopped');
  await expect(filesystemMCP.getByTestId('extension-mcp-resource-action')).toHaveCount(0);
  await expect(filesystemMCP.getByTestId('extension-mcp-prompt-action')).toHaveCount(0);

  await clickSidebarTool(page, 'extensions-button');
  await expect(page.getByTestId('extensions-pane')).toHaveCount(0);

  await clickSidebarTool(page, 'command-palette-button');
  await expect(page.getByTestId('command-palette-panel')).toBeVisible();
  await expect(page.getByTestId('command-palette-input')).toBeFocused();
  await fillCommandPalette(page, '>install github');
  await expect(commandPaletteResult(page, 'extension-install:plugin:github')).toContainText('Install GitHub');
  await fillCommandPalette(page, '>install browser use');
  await expect(commandPaletteResult(page, 'extension-install:skill:browser-use')).toContainText('Install Browser Use');
  await fillCommandPalette(page, '>update github');
  await expect(commandPaletteResult(page, 'extension-update:plugin:github')).toContainText('Update GitHub');
  await fillCommandPalette(page, '>read readme');
  await expect(commandPaletteResult(page, 'mcp-resource:mcp_server:filesystem:0')).toBeDisabled();
  await clickCommandPaletteCommand(page, '>extensions', 'toggle-extensions');
  await expect(page.getByTestId('extensions-pane')).toBeVisible();
});
