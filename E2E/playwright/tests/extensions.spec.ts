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
    '1 plugin · 5 skills · 1 MCP server · 2 hooks · 4 available extensions'
  );
  await expect(page.getByTestId('extensions-count')).toContainText([
    '1 plugin',
    '5 skills',
    '1 MCP server',
    '2 hooks'
  ]);
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
  await expect(page.getByTestId('extensions-subtitle')).toHaveText(
    '1 plugin · 5 skills · 1 MCP server · 2 hooks · 4 available extensions'
  );
  await clickSidebarTool(page, 'command-palette-button');
  await expect(page.getByTestId('command-palette-input')).toBeFocused();
  await clickCommandPaletteCommand(page, '>skills', 'show-skills');
  await expect(page.getByTestId('extensions-subtitle')).toHaveText('5 skills · 4 available skills');
  await expect(page.getByTestId('extension-item')).toHaveCount(5);

  await clickSidebarTool(page, 'command-palette-button');
  await clickCommandPaletteCommand(page, '>hooks', 'show-hooks');
  await expect(page.getByTestId('extensions-subtitle')).toHaveText('2 hooks');
  await expect(page.getByTestId('extension-item')).toHaveCount(0);
  await expect(page.getByTestId('hook-item')).toHaveCount(2);

  const reviewHook = page.getByTestId('hook-item').filter({ hasText: 'Prepare workspace context' });
  const unsupportedHook = page.getByTestId('hook-item').filter({ hasText: 'PreToolUse' });
  await expect(reviewHook.getByTestId('hook-status')).toHaveText('Review required');
  await expect(reviewHook.getByTestId('hook-source')).toHaveText(
    'Project config hooks · UserPromptSubmit'
  );
  await expect(reviewHook.getByTestId('hook-command')).toHaveText('printf ready');
  await expect(reviewHook.getByTestId('hook-path')).toHaveText(
    '.quillcode/config.toml#UserPromptSubmit/0/0'
  );
  await expect(reviewHook.getByTestId('hook-trust')).toHaveText('Trust');
  await expect(unsupportedHook.getByTestId('hook-status')).toHaveText('Unsupported');
  await expect(unsupportedHook.getByTestId('hook-support')).toContainText('not executable');
  await expect(unsupportedHook.locator('[data-command-id]')).toHaveCount(0);

  await reviewHook.getByTestId('hook-trust').click();
  await expect(reviewHook.getByTestId('hook-status')).toHaveText('Trusted');
  await expect(reviewHook.getByTestId('hook-disable')).toHaveText('Disable');
  await expect(page.getByTestId('message').last()).toContainText('is now trusted');
  await reviewHook.getByTestId('hook-disable').click();
  await expect(reviewHook.getByTestId('hook-status')).toHaveText('Disabled');
  await expect(reviewHook.getByTestId('hook-trust')).toHaveText('Enable');
});

test('record and replay requires consent and creates a reusable skill in one stopped workflow', async ({ page }) => {
  await page.goto(harnessURL());
  await clickSidebarTool(page, 'extensions-button');

  const startButton = page.getByTestId('workflow-recording-start');
  await expect(startButton).toBeVisible();
  await startButton.click();

  const composer = page.getByLabel('Message');
  await expect(composer).toBeFocused();
  await expect(composer).toHaveValue('Create a reusable skill by recording this workflow: ');
  await composer.fill('Create a reusable skill by recording this workflow: Publish a release to staging');
  await page.getByTestId('send-button').click();

  const consentCard = page.getByTestId('tool-card').filter({ hasText: 'host.workflow.record.start' }).first();
  await expect(consentCard).toHaveAttribute('data-status', 'review');
  await expect(consentCard).toContainText('Confirmation required');
  await expect(consentCard).toContainText('sent to TrustedRouter');
  await expect(consentCard.getByRole('button', { name: 'Start recording' })).toBeVisible();
  await expect(consentCard.getByRole('button', { name: 'Cancel' })).toBeVisible();
  await expect(page.getByTestId('workflow-recording-status')).toHaveCount(0);

  await consentCard.getByRole('button', { name: 'Start recording' }).click();
  const recording = page.getByTestId('workflow-recording-status');
  await expect(recording).toBeVisible();
  await expect(recording.getByTestId('workflow-recording-goal')).toHaveText('Publish a release to staging');
  await expect(page.getByTestId('workflow-recording-start')).toHaveCount(0);
  await expect(page.getByTestId('message').last()).toContainText('Demonstrate the workflow');

  await recording.getByTestId('workflow-recording-stop').click();

  await expect(page.getByTestId('workflow-recording-status')).toHaveCount(0);
  await expect(page.getByTestId('workflow-recording-start')).toBeVisible();
  await expect(page.getByTestId('tool-card-title').filter({ hasText: 'host.workflow.record.stop' })).toHaveCount(1);
  const skillWrite = page.getByTestId('tool-card').filter({ hasText: 'host.file.write' }).last();
  await expect(skillWrite.getByTestId('tool-card-input')).toContainText(
    '.quillcode/skills/publish-a-release-to-staging/SKILL.md'
  );
  await expect(skillWrite.getByTestId('tool-card-input')).toContainText('## Verification');
  await expect(page.getByTestId('message').last()).toContainText(
    'Created a reusable skill at .quillcode/skills/publish-a-release-to-staging/SKILL.md'
  );
  await expect(page.getByTestId('message').filter({ hasText: 'recording-start.png' })).toHaveCount(0);
});

test('cancelling record and replay captures nothing and creates no skill', async ({ page }) => {
  await page.goto(harnessURL());
  await clickSidebarTool(page, 'extensions-button');
  await page.getByTestId('workflow-recording-start').click();
  await page.getByLabel('Message').fill(
    'Create a reusable skill by recording this workflow: Update an issue label'
  );
  await page.getByTestId('send-button').click();

  const consentCard = page.getByTestId('tool-card').filter({ hasText: 'host.workflow.record.start' }).first();
  await consentCard.getByRole('button', { name: 'Cancel' }).click();

  await expect(page.getByTestId('workflow-recording-status')).toHaveCount(0);
  await expect(page.getByTestId('workflow-recording-start')).toBeVisible();
  await expect(page.getByTestId('tool-card-title').filter({ hasText: 'host.workflow.record.stop' })).toHaveCount(0);
  await expect(page.getByTestId('tool-card-title').filter({ hasText: 'host.file.write' })).toHaveCount(0);
  await expect(page.getByTestId('message').last()).toContainText(
    'Recording cancelled. No workflow activity was captured.'
  );
});
