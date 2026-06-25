import { test, expect, type Page } from '@playwright/test';
import {
  computedStyleProperties,
  elementRect,
  harnessURL,
  openSettings,
  openTopBarOverflow
} from './harness-helpers';

test('mock harness opens utilities from the top-bar overflow', async ({ page }) => {
  await page.goto(harnessURL());

  await openTopBarOverflow(page);
  await page.getByTestId('top-bar-overflow-keyboard-shortcuts').click();
  await expect(page.getByTestId('keyboard-shortcuts-panel')).toBeVisible();
  await page.getByTestId('keyboard-shortcuts-close').click();

  await openTopBarOverflow(page);
  await page.getByTestId('top-bar-overflow-search').click();
  await expect(page.getByTestId('search-panel')).toBeVisible();
  await expect(page.getByTestId('search-input')).toBeFocused();
  await page.keyboard.type('Nike');
  await expect(page.getByTestId('search-input')).toHaveValue('Nike');
  await page.getByTestId('search-close').click();

  await openTopBarOverflow(page);
  await page.getByTestId('top-bar-overflow-command-palette').click();
  await expect(page.getByTestId('command-palette-panel')).toBeVisible();
  await expect(page.getByTestId('command-palette-input')).toBeFocused();
  await page.keyboard.type('>search');
  await expect(page.getByTestId('command-palette-input')).toHaveValue('>search');
  await page.getByTestId('command-palette-close').click();

  await openTopBarOverflow(page);
  await expect(page.getByTestId('top-bar-overflow-stop-all')).toHaveCount(0);
  await expect(page.getByTestId('top-bar-stop-button')).toHaveCount(0);
});

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
    sidebarSettingsButtonStyle
  ] = await Promise.all([
    computedStyleProperties(page, 'html', ['-webkit-font-smoothing']),
    computedStyleProperties(page, '[data-testid="send-button"]', ['min-height', 'transition-property']),
    computedStyleProperties(page, '[data-testid="add-project-button"]', ['width', 'height']),
    computedStyleProperties(page, '[data-testid="new-chat-button"]', ['min-height', 'transition-property']),
    computedStyleProperties(page, '#message', ['transition-property']),
    computedStyleProperties(page, '[data-testid="top-bar-title"]', ['text-wrap']),
    computedStyleProperties(page, '[data-testid="agent-status"]', ['font-variant-numeric']),
    computedStyleProperties(page, '[data-testid="sidebar"]', ['border-radius']),
    computedStyleProperties(page, '[data-testid="sidebar-tools-button"]', ['min-height', 'transition-property']),
    computedStyleProperties(page, '[data-testid="sidebar-search-button"]', ['min-height', 'transition-property']),
    computedStyleProperties(page, '[data-testid="settings-button"]', ['width', 'min-height'])
  ]);

  const polish = {
    rootFontSmoothing: rootStyle['-webkit-font-smoothing'],
    sendMinHeight: parseFloat(sendButtonStyle['min-height']),
    sendTransitionProperty: sendButtonStyle['transition-property'],
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
    sidebarRadius: parseFloat(sidebarStyle['border-radius'])
  };

  expect(polish.rootFontSmoothing).toBe('antialiased');
  expect(polish.sendMinHeight).toBeGreaterThanOrEqual(40);
  expect(polish.addProjectWidth).toBeGreaterThanOrEqual(40);
  expect(polish.addProjectHeight).toBeGreaterThanOrEqual(40);
  expect(polish.sendTransitionProperty).toContain('transform');
  expect(polish.sendTransitionProperty).not.toContain('all');
  expect(polish.inputTransitionProperty).toContain('box-shadow');
  expect(polish.sidebarActionTransitionProperty).toContain('transform');
  expect(polish.sidebarActionTransitionProperty).toContain('box-shadow');
  expect(polish.sidebarActionTransitionProperty).not.toContain('all');
  expect(polish.sidebarActionMinHeight).toBeGreaterThanOrEqual(40);
  expect(polish.sidebarToolsMinHeight).toBeGreaterThanOrEqual(40);
  expect(polish.sidebarToolsTransitionProperty).toContain('transform');
  expect(polish.sidebarToolsTransitionProperty).not.toContain('all');
  expect(polish.sidebarToolActionMinHeight).toBeGreaterThanOrEqual(40);
  expect(polish.sidebarToolActionTransitionProperty).toContain('transform');
  expect(polish.sidebarToolActionTransitionProperty).not.toContain('all');
  expect(polish.sidebarSettingsWidth).toBeGreaterThanOrEqual(40);
  expect(polish.sidebarSettingsMinHeight).toBeGreaterThanOrEqual(40);
  expect(polish.titleTextWrap).toContain('balance');
  expect(polish.agentStatusNumbers).toContain('tabular-nums');
  expect(polish.sidebarRadius).toBeLessThanOrEqual(4);

  await page.getByLabel('Message').fill('run whoami');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-status', 'done');
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
  expect(transcriptPolish.toolCopyMinHeight).toBeGreaterThanOrEqual(40);
  expect(transcriptPolish.messageCopyMinHeight).toBeGreaterThanOrEqual(40);
  expect(transcriptPolish.sidebarMenuWidth).toBeGreaterThanOrEqual(40);
  expect(transcriptPolish.sidebarMenuHeight).toBeGreaterThanOrEqual(40);
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
  expect(metrics.topBarHeight).toBeLessThanOrEqual(44);
  expect(metrics.actionRight).toBeLessThanOrEqual(metrics.topBarRight);
});
