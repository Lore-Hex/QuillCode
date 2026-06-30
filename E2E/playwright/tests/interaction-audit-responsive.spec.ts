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

test('mock harness keeps banner and recovery actions at least 44px', async ({ page }) => {
  test.setTimeout(60000);
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('long context ' + 'word '.repeat(22000));
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('context-banner')).toBeVisible();
  await expectHitTarget(page.getByTestId('context-compact'), 'context compact button');
  await expectHitTarget(page.getByTestId('context-new-thread'), 'context new thread button');
  await expectHitTarget(page.getByTestId('context-fork-last'), 'context fork button');
  await expectHitTarget(page.getByTestId('context-fork-summary'), 'context summary fork button');
  await expectHitTarget(page.getByTestId('context-fork-full'), 'context full fork button');

  await page.getByLabel('Message').fill('trigger network failure');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('runtime-issue')).toBeVisible();
  await expectHitTarget(page.getByTestId('runtime-issue-action'), 'runtime recovery button');
});

test('mock harness keeps secondary pane actions at least 44px', async ({ page }) => {
  await page.goto(harnessURL());

  await clickSidebarTool(page, 'terminal-button');
  await expect(page.getByTestId('terminal-pane')).toBeVisible();
  await expectHitTarget(page.getByTestId('terminal-clear'), 'terminal clear button');
  await expectHitTarget(page.getByTestId('terminal-run'), 'terminal run button');

  await clickSidebarTool(page, 'browser-button');
  await expect(page.getByTestId('browser-pane')).toBeVisible();
  await expectHitTarget(page.getByTestId('browser-back'), 'browser back button');
  await expectHitTarget(page.getByTestId('browser-forward'), 'browser forward button');
  await expectHitTarget(page.getByTestId('browser-reload'), 'browser reload button');
  await expectHitTarget(page.getByTestId('browser-session'), 'browser session button');
  await expectHitTarget(page.getByTestId('browser-open'), 'browser open button');
  await expectHitTarget(page.getByTestId('browser-add-comment'), 'browser comment button');
  await expectHitTarget(page.getByTestId('browser-tab'), 'browser tab button');
  await expectHitTarget(page.getByTestId('browser-new-tab'), 'browser new tab button');
  await expectHitTarget(page.getByTestId('browser-close-tab'), 'browser close tab button');
  await page.getByTestId('browser-new-tab').click();
  await expect(page.getByTestId('browser-tab')).toHaveCount(2);
  await expectHitTarget(page.getByTestId('browser-close-tab'), 'enabled browser close tab button');
  await expectInteractionTargetsClean(page, 'browser pane with multiple tabs');

  await page.getByTestId('extensions-button').click();
  await expect(page.getByTestId('extensions-pane')).toBeVisible();
  await expectHitTarget(page.getByTestId('extension-install'), 'extension install button');
  await expectHitTarget(page.getByTestId('extension-start'), 'extension start button');

  await clickSidebarTool(page, 'memories-button');
  await expect(page.getByTestId('memories-pane')).toBeVisible();
  await expectHitTarget(page.getByTestId('memories-add'), 'memory add button');
  await expectHitTarget(page.getByTestId('memory-edit'), 'memory edit button');
  await expectHitTarget(page.getByTestId('memory-delete'), 'memory delete button');

  await page.getByTestId('automations-button').click();
  await expect(page.getByTestId('automations-pane')).toBeVisible();
  await expectHitTarget(page.getByTestId('automation-create-follow-up'), 'automation follow-up button');
  await expectHitTarget(page.getByTestId('automation-create-workspace-schedule'), 'automation workspace button');
  await page.getByTestId('automation-create-workspace-schedule').click();
  await expectHitTarget(page.getByTestId('automation-run'), 'automation run button');
  await expectHitTarget(page.getByTestId('automation-primary-action'), 'automation primary action button');
  await expectHitTarget(page.getByTestId('automation-delete'), 'automation delete button');
});

test('mock harness audits compact viewport click targets across primary states', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(harnessURL());

  await expectInteractionTargetsClean(page, 'compact initial workspace');

  await openTopBarOverflow(page);
  await expect(page.getByTestId('top-bar-overflow-menu')).toHaveAttribute('open', '');
  await expectInteractionTargetsClean(page, 'compact top-bar overflow menu');
  await page.getByTestId('top-bar-overflow-button').click();

  await page.getByTestId('model-picker-button').click();
  await expect(page.getByTestId('model-browser')).toBeVisible();
  await expectInteractionTargetsClean(page, 'compact model picker');
  await page.getByTestId('model-picker-button').click();

  await openTopBarOverflow(page);
  await page.getByTestId('top-bar-overflow-search').click();
  await expect(page.getByTestId('search-panel')).toBeVisible();
  await expectInteractionTargetsClean(page, 'compact search panel');
  await page.getByTestId('search-close').click();

  await openSettings(page);
  await expect(page.getByTestId('settings-panel')).toBeVisible();
  await expectInteractionTargetsClean(page, 'compact settings panel');
  await page.getByTestId('settings-cancel').click();

  await page.getByLabel('Message').fill('run whoami');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('tool-card').last()).toHaveAttribute('data-status', 'done');
  await expectInteractionTargetsClean(page, 'compact tool-card transcript');

  await openTopBarOverflow(page);
  await page.getByTestId('top-bar-overflow-command-palette').click();
  await expect(page.getByTestId('command-palette-panel')).toBeVisible();
  await expectInteractionTargetsClean(page, 'compact command palette');
  await clickCommandPaletteCommand(page, '>terminal', 'toggle-terminal');
  await expect(page.getByTestId('terminal-pane')).toBeVisible();
  await expectInteractionTargetsClean(page, 'compact terminal pane');

  await openTopBarOverflow(page);
  await page.getByTestId('top-bar-overflow-command-palette').click();
  await clickCommandPaletteCommand(page, '>browser', 'toggle-browser');
  await expect(page.getByTestId('browser-pane')).toBeVisible();
  await expectInteractionTargetsClean(page, 'compact browser pane');

  await page.getByLabel('Message').fill('/git');
  await expect(page.getByTestId('slash-suggestions')).toBeVisible();
  await expectInteractionTargetsClean(page, 'compact slash suggestion menu');
  await page.keyboard.press('Escape');
  await page.getByLabel('Message').fill('');

  await page.keyboard.press('Meta+F');
  await expect(page.getByTestId('find-bar')).toBeVisible();
  await expectInteractionTargetsClean(page, 'compact find bar');
  await page.getByTestId('find-close').click();
});

test('mock harness audits narrow viewport click targets across squeezed states', async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 720 });
  await page.goto(harnessURL());

  await expectInteractionTargetsClean(page, 'narrow initial workspace');

  await openTopBarOverflow(page);
  await expect(page.getByTestId('top-bar-overflow-menu')).toHaveAttribute('open', '');
  await expectInteractionTargetsClean(page, 'narrow top-bar overflow menu');
  await page.getByTestId('top-bar-overflow-button').click();

  await page.getByTestId('model-picker-button').click();
  await expect(page.getByTestId('model-browser')).toBeVisible();
  await expectInteractionTargetsClean(page, 'narrow model picker');
  await page.getByTestId('model-picker-button').click();

  await openTopBarOverflow(page);
  await page.getByTestId('top-bar-overflow-command-palette').click();
  await expect(page.getByTestId('command-palette-panel')).toBeVisible();
  await expectInteractionTargetsClean(page, 'narrow command palette');
  await clickCommandPaletteCommand(page, '>browser', 'toggle-browser');
  await expect(page.getByTestId('browser-pane')).toBeVisible();
  await expectInteractionTargetsClean(page, 'narrow browser pane');

  await openSettings(page);
  await expect(page.getByTestId('settings-panel')).toBeVisible();
  await expectInteractionTargetsClean(page, 'narrow settings panel');
  await page.getByTestId('settings-cancel').click();

  await page.getByLabel('Message').fill('run whoami');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('tool-card').last()).toHaveAttribute('data-status', 'done');
  await expectInteractionTargetsClean(page, 'narrow transcript with tool card');

  await page.keyboard.press('Meta+F');
  await expect(page.getByTestId('find-bar')).toBeVisible();
  await expectInteractionTargetsClean(page, 'narrow find bar');
  await page.getByTestId('find-close').click();
});
