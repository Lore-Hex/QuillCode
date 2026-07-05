import { test, expect } from '@playwright/test';
import {
  clickCommandPaletteCommand,
  clickSidebarTool,
  commandPaletteResult,
  fillCommandPalette,
  harnessURL,
  openSettings,
  openTopBarOverflow
} from './harness-helpers';
import {
  expectCriticalTargetRegistry,
  expectCriticalTargetSurfaceRegistry,
  expectHitTarget,
  interactionAuditReport,
  clickTargetInteriorPoint,
  expectTextEntryFocusFromInteriorPoint
} from './interaction-audit-helpers';
import {
  expectCommandTargetsRoutable,
  expectInteractionTargetsClean
} from './interaction-audit-routability';

test('critical click-target registry covers primary workspace surfaces', async ({ page }) => {
  await page.goto(harnessURL());

  await expectCriticalTargetSurfaceRegistry('primary workspace chrome', [
    {
      label: 'sidebar primary actions',
      requiredKinds: ['row'],
      probes: [
        { label: 'new chat', locator: page.getByTestId('new-chat-button'), expectedKind: 'row' },
        { label: 'sidebar search', locator: page.getByTestId('sidebar-search-button'), expectedKind: 'row' },
        { label: 'sidebar tools', locator: page.getByTestId('sidebar-tools-button'), expectedKind: 'row' }
      ]
    },
    {
      label: 'project list',
      requiredKinds: ['icon', 'row'],
      probes: [
        { label: 'open project', locator: page.getByTestId('add-project-button'), expectedKind: 'icon' },
        { label: 'first project row', locator: page.getByTestId('project-item').first(), expectedKind: 'row' }
      ]
    },
    {
      label: 'top bar actions',
      requiredKinds: ['capsule', 'icon'],
      probes: [
        { label: 'model picker', locator: page.getByTestId('model-picker-button'), expectedKind: 'capsule' },
        { label: 'top-bar overflow', locator: page.getByTestId('top-bar-overflow-button'), expectedKind: 'icon' }
      ]
    },
    {
      label: 'composer',
      requiredKinds: ['text-entry', 'text'],
      probes: [
        { label: 'composer text entry', locator: page.getByLabel('Message'), expectedKind: 'text-entry' },
        { label: 'composer send', locator: page.getByRole('button', { name: 'Send' }), expectedKind: 'text' }
      ]
    }
  ]);

  await openTopBarOverflow(page);
  await expectCriticalTargetSurfaceRegistry('top-bar overflow menu', [
    {
      label: 'menu rows',
      requiredKinds: ['row'],
      probes: [
        { label: 'search', locator: page.getByTestId('top-bar-overflow-search'), expectedKind: 'row' },
        { label: 'command palette', locator: page.getByTestId('top-bar-overflow-command-palette'), expectedKind: 'row' },
        { label: 'keyboard shortcuts', locator: page.getByTestId('top-bar-overflow-keyboard-shortcuts'), expectedKind: 'row' },
        { label: 'settings', locator: page.getByTestId('top-bar-overflow-settings'), expectedKind: 'row' }
      ]
    }
  ]);
  await page.getByTestId('top-bar-overflow-button').click();

  await page.getByTestId('model-picker-button').click();
  await expect(page.getByTestId('model-browser')).toBeVisible();
  await expectCriticalTargetRegistry('model picker', [
    { label: 'model search', locator: page.getByTestId('model-search'), expectedKind: 'text-entry' },
    { label: 'first model option', locator: page.getByTestId('model-option').first(), expectedKind: 'row' },
    { label: 'first model details', locator: page.getByTestId('model-detail-button').first(), expectedKind: 'icon' },
    { label: 'first model favorite', locator: page.getByTestId('model-favorite-button').first(), expectedKind: 'icon' }
  ]);
  await page.getByTestId('model-picker-button').click();

  await openTopBarOverflow(page);
  await page.getByTestId('top-bar-overflow-command-palette').click();
  await expect(page.getByTestId('command-palette-panel')).toBeVisible();
  await fillCommandPalette(page, '>git');
  await expectCriticalTargetRegistry('command palette', [
    { label: 'command search', locator: page.getByTestId('command-palette-input'), expectedKind: 'text-entry' },
    { label: 'close command palette', locator: page.getByTestId('command-palette-close'), expectedKind: 'text' },
    { label: 'first command result', locator: page.getByTestId('command-palette-result').first(), expectedKind: 'row' }
  ]);
  await page.getByTestId('command-palette-close').click();

  await openSettings(page);
  await expect(page.getByTestId('settings-panel')).toBeVisible();
  await expectCriticalTargetRegistry('settings panel', [
    { label: 'API base URL', locator: page.getByLabel('TrustedRouter API base URL'), expectedKind: 'text-entry' },
    { label: 'authentication selector', locator: page.getByLabel('Authentication'), expectedKind: 'text-entry' },
    { label: 'TrustedRouter sign in', locator: page.getByTestId('settings-sign-in'), expectedKind: 'text' },
    { label: 'cancel', locator: page.getByTestId('settings-cancel'), expectedKind: 'text' },
    { label: 'save', locator: page.getByTestId('settings-save'), expectedKind: 'text' }
  ]);
  await page.getByTestId('settings-cancel').click();

  await clickSidebarTool(page, 'terminal-button');
  await expect(page.getByTestId('terminal-pane')).toBeVisible();
  await expectCriticalTargetRegistry('terminal pane', [
    { label: 'clear', locator: page.getByTestId('terminal-clear'), expectedKind: 'text' },
    { label: 'command input', locator: page.getByTestId('terminal-input'), expectedKind: 'text-entry' },
    { label: 'run', locator: page.getByTestId('terminal-run'), expectedKind: 'text' }
  ]);

  await clickSidebarTool(page, 'activity-button');
  await expect(page.getByTestId('activity-pane')).toBeVisible();
  await expectCriticalTargetRegistry('activity pane', [
    { label: 'plan section toggle', locator: page.getByTestId('activity-plan-section').getByTestId('activity-section-toggle'), expectedKind: 'row' },
    { label: 'source open', locator: page.getByTestId('activity-source-action').filter({ hasText: 'Open' }), expectedKind: 'form-action' },
    { label: 'source edit', locator: page.getByTestId('activity-source-action').filter({ hasText: 'Edit' }), expectedKind: 'form-action' }
  ]);

  await clickSidebarTool(page, 'browser-button');
  await expect(page.getByTestId('browser-pane')).toBeVisible();
  await expectCriticalTargetRegistry('browser pane', [
    { label: 'active browser tab', locator: page.getByTestId('browser-tab').first(), expectedKind: 'capsule' },
    { label: 'back', locator: page.getByTestId('browser-back'), expectedKind: 'icon' },
    { label: 'forward', locator: page.getByTestId('browser-forward'), expectedKind: 'icon' },
    { label: 'reload', locator: page.getByTestId('browser-reload'), expectedKind: 'icon' },
    { label: 'address', locator: page.getByTestId('browser-address'), expectedKind: 'text-entry' },
    { label: 'open', locator: page.getByTestId('browser-open'), expectedKind: 'text' },
    { label: 'comment input', locator: page.getByTestId('browser-comment-input'), expectedKind: 'text-entry' },
    { label: 'add comment', locator: page.getByTestId('browser-add-comment'), expectedKind: 'text' }
  ]);

  await page.getByTestId('extensions-button').click();
  await expect(page.getByTestId('extensions-pane')).toBeVisible();
  await page.getByTestId('extension-start').click();
  await expect(page.getByTestId('extension-item').nth(3)).toContainText('Ready');
  await expectCriticalTargetRegistry('extensions pane', [
    { label: 'install extension', locator: page.getByTestId('extension-install'), expectedKind: 'form-action' },
    { label: 'stop MCP server', locator: page.getByTestId('extension-stop'), expectedKind: 'form-action' },
    { label: 'read MCP resource', locator: page.getByTestId('extension-mcp-resource-action').first(), expectedKind: 'capsule' },
    { label: 'use MCP prompt', locator: page.getByTestId('extension-mcp-prompt-action'), expectedKind: 'capsule' }
  ]);

  await clickSidebarTool(page, 'memories-button');
  await expect(page.getByTestId('memories-pane')).toBeVisible();
  await expectCriticalTargetRegistry('memories pane', [
    { label: 'add memory', locator: page.getByTestId('memories-add'), expectedKind: 'text' },
    { label: 'edit memory', locator: page.getByTestId('memory-edit').first(), expectedKind: 'form-action' },
    { label: 'forget memory', locator: page.getByTestId('memory-delete').first(), expectedKind: 'form-action' }
  ]);

  await page.getByTestId('automations-button').click();
  await expect(page.getByTestId('automations-pane')).toBeVisible();
  await page.getByTestId('automation-create-workspace-schedule').click();
  await expect(page.getByTestId('automation-card')).toBeVisible();
  await expectCriticalTargetRegistry('automations pane', [
    { label: 'schedule follow-up', locator: page.getByTestId('automation-schedule-follow-up').first(), expectedKind: 'text' },
    { label: 'create workspace schedule', locator: page.getByTestId('automation-create-workspace-schedule'), expectedKind: 'text' },
    { label: 'run automation', locator: page.getByTestId('automation-run'), expectedKind: 'text' },
    { label: 'pause automation', locator: page.getByTestId('automation-primary-action'), expectedKind: 'text' },
    { label: 'delete automation', locator: page.getByTestId('automation-delete'), expectedKind: 'text' }
  ]);

  await page.getByLabel('Message').fill('run whoami');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('tool-card').last()).toHaveAttribute('data-status', 'done');
  await expectCriticalTargetRegistry('transcript tool card', [
    { label: 'tool disclosure', locator: page.getByTestId('tool-card-details').last().locator('summary'), expectedKind: 'row' },
    { label: 'message composer', locator: page.getByLabel('Message'), expectedKind: 'text-entry' },
    { label: 'send after transcript update', locator: page.getByRole('button', { name: 'Send' }), expectedKind: 'text' }
  ]);
});
