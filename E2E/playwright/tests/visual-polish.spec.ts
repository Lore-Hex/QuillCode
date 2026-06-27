import { test, expect, type Page } from '@playwright/test';
import {
  clickSidebarTool,
  computedStyleProperties,
  elementRect,
  harnessURL,
  openSettings
} from './harness-helpers';
import {
  expectHitTarget,
  MINIMUM_HIT_TARGET
} from './interaction-audit-helpers';

test('mock harness avoids horizontal clipping in key desktop and mobile flows', async ({ browser }) => {
  const viewports = [
    { name: 'desktop', width: 1440, height: 1000 },
    { name: 'mobile', width: 390, height: 844 }
  ];

  const expectNoHorizontalOverflow = async (page: Page, label: string) => {
    const overflow = await page.evaluate(() => {
      const viewportWidth = document.documentElement.clientWidth;
      return [...document.querySelectorAll('body *')]
        .map((element) => {
          const rect = element.getBoundingClientRect();
          return {
            tag: element.tagName,
            testid: element.getAttribute('data-testid'),
            className: String(element.className || ''),
            left: rect.left,
            right: rect.right,
            width: rect.width,
            text: (element.textContent || '').trim().slice(0, 80)
          };
        })
        .filter((rect) => rect.width > 0 && (rect.left < -1 || rect.right > viewportWidth + 1));
    });

    expect(overflow, `${label} should not clip horizontally`).toEqual([]);
  };

  for (const viewport of viewports) {
    const page = await browser.newPage({
      viewport: { width: viewport.width, height: viewport.height },
      deviceScaleFactor: 1
    });
    await page.goto(harnessURL());

    await openSettings(page);
    await expect(page.getByTestId('settings-panel')).toBeVisible();
    await expectNoHorizontalOverflow(page, `${viewport.name} settings`);

    await page.getByTestId('settings-save').click();
    await page.getByLabel('Message').fill('run whoami');
    await page.getByRole('button', { name: 'Send' }).click();
    await expect(page.getByTestId('tool-card')).toHaveAttribute('data-status', 'done');
    await expectNoHorizontalOverflow(page, `${viewport.name} tool flow`);

    await page.close();
  }
});

test('mock harness applies interface polish primitives', async ({ page }) => {
  await page.goto(harnessURL());

  const [
    rootStyle,
    sendButtonStyle,
    addProjectButtonStyle,
    sidebarActionStyle,
    messageInputStyle,
    titleStyle,
    agentStatusStyle,
    sidebarStyle,
    sidebarToolsButtonStyle,
    sidebarToolActionStyle,
    sidebarSettingsButtonStyle,
    emptyStarterStyle
  ] = await Promise.all([
    computedStyleProperties(page, 'html', ['-webkit-font-smoothing']),
    computedStyleProperties(page, '[data-testid="send-button"]', [
      'min-height',
      'transition-property',
      'opacity',
      'background-color',
      'color',
      'cursor'
    ]),
    computedStyleProperties(page, '[data-testid="add-project-button"]', ['width', 'height']),
    computedStyleProperties(page, '[data-testid="new-chat-button"]', ['min-height', 'transition-property']),
    computedStyleProperties(page, '#message', ['transition-property']),
    computedStyleProperties(page, '[data-testid="top-bar-title"]', ['text-wrap']),
    computedStyleProperties(page, '[data-testid="agent-status"]', ['font-variant-numeric']),
    computedStyleProperties(page, '[data-testid="sidebar"]', ['border-radius']),
    computedStyleProperties(page, '[data-testid="sidebar-tools-button"]', ['min-height', 'transition-property']),
    computedStyleProperties(page, '[data-testid="sidebar-search-button"]', ['min-height', 'transition-property']),
    computedStyleProperties(page, '[data-testid="settings-button"]', ['width', 'min-height']),
    computedStyleProperties(page, '[data-testid="empty-starter-action"]', ['min-height', 'transition-property', 'border-radius'])
  ]);

  const polish = {
    rootFontSmoothing: rootStyle['-webkit-font-smoothing'],
    sendMinHeight: parseFloat(sendButtonStyle['min-height']),
    sendTransitionProperty: sendButtonStyle['transition-property'],
    sendDisabledOpacity: sendButtonStyle.opacity,
    sendDisabledBackgroundColor: sendButtonStyle['background-color'],
    sendDisabledColor: sendButtonStyle.color,
    sendDisabledCursor: sendButtonStyle.cursor,
    inputTransitionProperty: messageInputStyle['transition-property'],
    sidebarActionTransitionProperty: sidebarActionStyle['transition-property'],
    sidebarActionMinHeight: parseFloat(sidebarActionStyle['min-height']),
    titleTextWrap: titleStyle['text-wrap'],
    agentStatusNumbers: agentStatusStyle['font-variant-numeric'],
    addProjectWidth: parseFloat(addProjectButtonStyle.width),
    addProjectHeight: parseFloat(addProjectButtonStyle.height),
    sidebarToolsMinHeight: parseFloat(sidebarToolsButtonStyle['min-height']),
    sidebarToolsTransitionProperty: sidebarToolsButtonStyle['transition-property'],
    sidebarToolActionMinHeight: parseFloat(sidebarToolActionStyle['min-height']),
    sidebarToolActionTransitionProperty: sidebarToolActionStyle['transition-property'],
    sidebarSettingsWidth: parseFloat(sidebarSettingsButtonStyle.width),
    sidebarSettingsMinHeight: parseFloat(sidebarSettingsButtonStyle['min-height']),
    sidebarRadius: parseFloat(sidebarStyle['border-radius']),
    emptyStarterMinHeight: parseFloat(emptyStarterStyle['min-height']),
    emptyStarterTransitionProperty: emptyStarterStyle['transition-property'],
    emptyStarterRadius: parseFloat(emptyStarterStyle['border-radius'])
  };

  expect(polish.rootFontSmoothing).toBe('antialiased');
  expect(polish.sendMinHeight).toBeGreaterThanOrEqual(MINIMUM_HIT_TARGET);
  expect(polish.sendDisabledOpacity).toBe('1');
  expect(polish.sendDisabledBackgroundColor).toBe('rgba(255, 255, 255, 0.055)');
  expect(polish.sendDisabledColor).toBe('rgba(235, 250, 255, 0.42)');
  expect(polish.sendDisabledCursor).toBe('not-allowed');
  expect(polish.addProjectWidth).toBeGreaterThanOrEqual(MINIMUM_HIT_TARGET);
  expect(polish.addProjectHeight).toBeGreaterThanOrEqual(MINIMUM_HIT_TARGET);
  expect(polish.sendTransitionProperty).toContain('transform');
  expect(polish.sendTransitionProperty).not.toContain('all');
  expect(polish.inputTransitionProperty).toContain('box-shadow');
  expect(polish.sidebarActionTransitionProperty).toContain('transform');
  expect(polish.sidebarActionTransitionProperty).toContain('box-shadow');
  expect(polish.sidebarActionTransitionProperty).not.toContain('all');
  expect(polish.sidebarActionMinHeight).toBeGreaterThanOrEqual(MINIMUM_HIT_TARGET);
  expect(polish.sidebarToolsMinHeight).toBeGreaterThanOrEqual(MINIMUM_HIT_TARGET);
  expect(polish.sidebarToolsTransitionProperty).toContain('transform');
  expect(polish.sidebarToolsTransitionProperty).not.toContain('all');
  expect(polish.sidebarToolActionMinHeight).toBeGreaterThanOrEqual(MINIMUM_HIT_TARGET);
  expect(polish.sidebarToolActionTransitionProperty).toContain('transform');
  expect(polish.sidebarToolActionTransitionProperty).not.toContain('all');
  expect(polish.sidebarSettingsWidth).toBeGreaterThanOrEqual(MINIMUM_HIT_TARGET);
  expect(polish.sidebarSettingsMinHeight).toBeGreaterThanOrEqual(MINIMUM_HIT_TARGET);
  expect(polish.titleTextWrap).toContain('balance');
  expect(polish.agentStatusNumbers).toContain('tabular-nums');
  expect(polish.sidebarRadius).toBeLessThanOrEqual(4);
  expect(polish.emptyStarterMinHeight).toBeGreaterThanOrEqual(MINIMUM_HIT_TARGET);
  expect(polish.emptyStarterTransitionProperty).toContain('transform');
  expect(polish.emptyStarterTransitionProperty).toContain('box-shadow');
  expect(polish.emptyStarterTransitionProperty).not.toContain('all');
  expect(polish.emptyStarterRadius).toBe(14);

  await expectHitTarget(page.getByTestId('top-bar-overflow-button'), 'top-bar overflow button');
  await expectHitTarget(page.getByTestId('empty-starter-action'), 'empty starter action');
  await expectHitTarget(page.getByTestId('new-chat-button'), 'new chat button');
  await expectHitTarget(page.getByTestId('sidebar-search-button'), 'sidebar search button');
  await expectHitTarget(page.getByTestId('extensions-button'), 'plugins button');
  await expectHitTarget(page.getByTestId('automations-button'), 'automations button');
  await expectHitTarget(page.getByTestId('add-project-button'), 'add project button');
  await expectHitTarget(page.getByTestId('sidebar-tools-button'), 'sidebar tools button');
  await expectHitTarget(page.getByTestId('settings-button'), 'settings button');
  await expectHitTarget(page.getByTestId('model-picker-button'), 'model picker button');
  await expectHitTarget(page.getByTestId('mode-picker-button'), 'mode picker button');

  await page.getByTestId('model-picker-button').click();
  await expectHitTarget(page.getByTestId('model-option'), 'model picker row');
  await expectHitTarget(page.getByTestId('model-detail-button'), 'model detail button');
  await expectHitTarget(page.getByTestId('model-favorite-button'), 'model favorite button');
  await page.getByTestId('model-picker-button').click();

  await clickSidebarTool(page, 'browser-button');
  await expect(page.getByTestId('browser-pane')).toBeVisible();
  await expectHitTarget(page.getByTestId('browser-back'), 'browser back button');
  await expectHitTarget(page.getByTestId('browser-forward'), 'browser forward button');
  await expectHitTarget(page.getByTestId('browser-reload'), 'browser reload button');
  await expectHitTarget(page.getByTestId('browser-session'), 'browser session button');
  await expectHitTarget(page.getByTestId('browser-open'), 'browser open button');
  await expectHitTarget(page.getByTestId('browser-add-comment'), 'browser comment button');

  await clickSidebarTool(page, 'terminal-button');
  await expect(page.getByTestId('terminal-pane')).toBeVisible();
  await expectHitTarget(page.getByTestId('terminal-clear'), 'terminal clear button');
  await expectHitTarget(page.getByTestId('terminal-run'), 'terminal run button');

  await clickSidebarTool(page, 'activity-button');
  await expect(page.getByTestId('activity-pane')).toBeVisible();
  await expectHitTarget(page.getByTestId('activity-section-toggle'), 'activity section toggle');

  await page.getByTestId('extensions-button').click();
  await expect(page.getByTestId('extensions-pane')).toBeVisible();
  await expectHitTarget(page.getByTestId('extension-install'), 'extension install button');

  await page.getByTestId('automations-button').click();
  await expect(page.getByTestId('automations-pane')).toBeVisible();
  await expectHitTarget(page.getByTestId('automation-create-workspace-schedule'), 'automation create button');

  await clickSidebarTool(page, 'memories-button');
  await expect(page.getByTestId('memories-pane')).toBeVisible();
  await expectHitTarget(page.getByTestId('memory-edit'), 'memory edit button');
  await expectHitTarget(page.getByTestId('memory-delete'), 'memory delete button');

  await page.getByLabel('Message').fill('run whoami');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('tool-card').last()).toHaveAttribute('data-status', 'done');
  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-density', 'collapsed');

  const [
    toolCardStyle,
    toolCardRect,
    toolStatusStyle,
    toolCopyButtonStyle,
    messageCopyButtonStyle,
    sidebarMenuRect
  ] = await Promise.all([
    computedStyleProperties(page, '[data-testid="tool-card"]', ['min-height']),
    elementRect(page, '[data-testid="tool-card"]'),
    computedStyleProperties(page, '[data-testid="tool-card-status"]', ['font-variant-numeric']),
    computedStyleProperties(page, '[data-testid="tool-card-copy"]', ['min-height']),
    computedStyleProperties(page, '[data-testid="message-copy"]', ['min-height']),
    elementRect(page, '[data-testid="sidebar-item-actions"] summary')
  ]);

  const transcriptPolish = {
    toolCardMinHeight: parseFloat(toolCardStyle['min-height']),
    toolCardRenderedHeight: toolCardRect.height,
    toolStatusNumbers: toolStatusStyle['font-variant-numeric'],
    toolCopyMinHeight: parseFloat(toolCopyButtonStyle['min-height']),
    messageCopyMinHeight: parseFloat(messageCopyButtonStyle['min-height']),
    sidebarMenuWidth: sidebarMenuRect.width,
    sidebarMenuHeight: sidebarMenuRect.height
  };

  expect(transcriptPolish.toolCardMinHeight).toBeGreaterThanOrEqual(58);
  expect(transcriptPolish.toolCardRenderedHeight).toBeGreaterThanOrEqual(58);
  expect(transcriptPolish.toolStatusNumbers).toContain('tabular-nums');
  expect(transcriptPolish.toolCopyMinHeight).toBeGreaterThanOrEqual(MINIMUM_HIT_TARGET);
  expect(transcriptPolish.messageCopyMinHeight).toBeGreaterThanOrEqual(MINIMUM_HIT_TARGET);
  expect(transcriptPolish.sidebarMenuWidth).toBeGreaterThanOrEqual(MINIMUM_HIT_TARGET);
  expect(transcriptPolish.sidebarMenuHeight).toBeGreaterThanOrEqual(MINIMUM_HIT_TARGET);
  await expectHitTarget(page.locator('[data-testid="tool-card-details"] summary'), 'tool details disclosure');
});

test('mock harness keeps quiet top bar stable under long status metadata', async ({ page }) => {
  await page.setViewportSize({ width: 900, height: 760 });
  await page.goto(harnessURL());

  await page.getByTestId('project-instructions-status').evaluate(element => {
    element.textContent = '12 instruction files loaded from deeply nested project rule sources';
  });
  await page.getByTestId('project-memories-status').evaluate(element => {
    element.textContent = '29 memories from this project and global profile';
  });
  await page.getByTestId('computer-use-status').evaluate(element => {
    element.textContent = 'Needs Screen Recording + Accessibility';
  });
  await page.getByTestId('agent-status').evaluate(element => {
    element.textContent = 'Idle';
  });

  const [
    viewportMetrics,
    clustersStyle,
    contextStyle,
    metadataRect,
    topBarRect,
    actionRect
  ] = await Promise.all([
    page.evaluate(() => ({
      scrollWidth: document.documentElement.scrollWidth,
      viewportWidth: document.documentElement.clientWidth
    })),
    computedStyleProperties(page, '[data-testid="top-bar-clusters"]', ['display', 'grid-template-columns']),
    computedStyleProperties(page, '[data-testid="top-bar-subtitle"]', ['overflow', 'text-overflow']),
    elementRect(page, '[data-testid="top-bar-status-metadata"]'),
    elementRect(page, '[data-testid="top-bar"]'),
    elementRect(page, '[data-testid="top-bar-action-cluster"]')
  ]);

  const metrics = {
    viewportWidth: viewportMetrics.viewportWidth,
    scrollWidth: viewportMetrics.scrollWidth,
    clustersDisplay: clustersStyle.display,
    clustersColumns: clustersStyle['grid-template-columns'],
    contextOverflow: contextStyle.overflow,
    contextTextOverflow: contextStyle['text-overflow'],
    metadataWidth: metadataRect.width,
    metadataHeight: metadataRect.height,
    topBarHeight: topBarRect.height,
    actionRight: actionRect.right,
    topBarRight: topBarRect.right
  };

  await expect(page.getByTestId('top-bar-status-button')).toHaveCount(0);
  await expect(page.getByTestId('top-bar-status-menu')).toHaveCount(0);
  await expect(page.getByTestId('top-bar-status-popover')).toHaveCount(0);
  await expect(page.getByTestId('top-bar-status-metadata')).toHaveAttribute('aria-hidden', 'true');
  await expect(page.getByTestId('top-bar-status-metadata')).not.toBeVisible();
  await expect(page.getByTestId('agent-status')).toHaveText('Idle');
  expect(metrics.scrollWidth).toBeLessThanOrEqual(metrics.viewportWidth);
  expect(metrics.clustersDisplay).toBe('flex');
  expect(metrics.clustersColumns).toBe('none');
  expect(metrics.contextOverflow).toBe('hidden');
  expect(metrics.contextTextOverflow).toBe('ellipsis');
  expect(metrics.metadataWidth).toBeLessThanOrEqual(1);
  expect(metrics.metadataHeight).toBeLessThanOrEqual(1);
  expect(metrics.topBarHeight).toBeLessThanOrEqual(MINIMUM_HIT_TARGET + 1);
  expect(metrics.actionRight).toBeLessThanOrEqual(metrics.topBarRight);
});
