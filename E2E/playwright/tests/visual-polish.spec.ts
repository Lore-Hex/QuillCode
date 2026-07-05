import { test, expect } from '@playwright/test';
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
import { expectNoHorizontalOverflow } from './visual-polish-helpers';

test('mock harness avoids horizontal clipping in key desktop and mobile flows', async ({ browser }) => {
  const viewports = [
    { name: 'desktop', width: 1440, height: 1000 },
    { name: 'mobile', width: 390, height: 844 }
  ];

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

test('mock harness keeps sidebar saved filters fully visible', async ({ page }) => {
  await page.goto(harnessURL());
  await page.getByLabel('Message').fill('run whoami');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('sidebar-item')).toContainText('run whoami');

  const filterBar = page.getByTestId('sidebar-filter-bar');
  await expect(filterBar).toBeVisible();

  const metrics = await filterBar.evaluate((element) => {
    const style = window.getComputedStyle(element);
    const barRect = element.getBoundingClientRect();
    const filters = [...element.querySelectorAll<HTMLElement>('[data-testid="sidebar-filter"]')].map((filter) => {
      const rect = filter.getBoundingClientRect();
      return {
        text: filter.textContent?.trim() ?? '',
        left: rect.left,
        right: rect.right,
        top: rect.top,
        bottom: rect.bottom
      };
    });
    return {
      className: element.className,
      clientWidth: element.clientWidth,
      scrollWidth: element.scrollWidth,
      flexWrap: style.getPropertyValue('flex-wrap') || style.flexWrap,
      overflowX: style.overflowX,
      left: barRect.left,
      right: barRect.right,
      top: barRect.top,
      bottom: barRect.bottom,
      filters
    };
  });

  expect(metrics.className).toContain('sidebar-filter-bar');
  if (metrics.flexWrap) expect(metrics.flexWrap).toBe('wrap');
  if (metrics.overflowX) expect(metrics.overflowX).toBe('visible');
  expect(metrics.scrollWidth).toBeLessThanOrEqual(metrics.clientWidth + 1);
  for (const filter of metrics.filters) {
    expect(filter.left, `${filter.text} should not clip left`).toBeGreaterThanOrEqual(metrics.left - 1);
    expect(filter.right, `${filter.text} should not clip right`).toBeLessThanOrEqual(metrics.right + 1);
    expect(filter.top, `${filter.text} should not clip top`).toBeGreaterThanOrEqual(metrics.top - 1);
    expect(filter.bottom, `${filter.text} should not clip bottom`).toBeLessThanOrEqual(metrics.bottom + 1);
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
    computedStyleProperties(page, '[data-testid="sidebar"]', ['border-radius', 'padding-left', 'padding-right']),
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
    sidebarPaddingLeft: parseFloat(sidebarStyle['padding-left']),
    sidebarPaddingRight: parseFloat(sidebarStyle['padding-right']),
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
  expect(polish.sidebarPaddingLeft).toBe(16);
  expect(polish.sidebarPaddingRight).toBe(16);
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
  await expectHitTarget(page.getByTestId('browser-tab'), 'browser tab button');
  await expectHitTarget(page.getByTestId('browser-new-tab'), 'browser new tab button');
  await expectHitTarget(page.getByTestId('browser-close-tab'), 'browser close tab button');

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
    sidebarMenuRect,
    sidebarFilterStyle,
    sidebarFilterVisualStyle,
    tokenBudgetLabelStyle,
    tokenBudgetPrimaryStyle,
    tokenBudgetSecondaryStyle
  ] = await Promise.all([
    computedStyleProperties(page, '[data-testid="tool-card"]', ['min-height']),
    elementRect(page, '[data-testid="tool-card"]'),
    computedStyleProperties(page, '[data-testid="tool-card-status"]', ['font-variant-numeric']),
    computedStyleProperties(page, '[data-testid="tool-card-copy"]', ['min-height']),
    computedStyleProperties(page, '[data-testid="message-copy"]', ['min-height']),
    elementRect(page, '[data-testid="sidebar-item-actions"] summary'),
    computedStyleProperties(page, '[data-testid="sidebar-filter"]', ['min-height', 'padding-left', 'padding-right']),
    page.getByTestId('sidebar-filter').first().evaluate(element => {
      const style = getComputedStyle(element, '::before');
      return {
        top: style.top,
        bottom: style.bottom,
        borderRadius: style.borderRadius
      };
    }),
    computedStyleProperties(page, '.topbar-token-budget-label', ['font-size']),
    computedStyleProperties(page, '[data-testid="top-bar-token-budget-primary"]', ['font-size', 'font-variant-numeric']),
    computedStyleProperties(page, '[data-testid="top-bar-token-budget-secondary"]', ['font-size'])
  ]);

  const transcriptPolish = {
    toolCardMinHeight: parseFloat(toolCardStyle['min-height']),
    toolCardRenderedHeight: toolCardRect.height,
    toolStatusNumbers: toolStatusStyle['font-variant-numeric'],
    toolCopyMinHeight: parseFloat(toolCopyButtonStyle['min-height']),
    messageCopyMinHeight: parseFloat(messageCopyButtonStyle['min-height']),
    sidebarMenuWidth: sidebarMenuRect.width,
    sidebarMenuHeight: sidebarMenuRect.height,
    sidebarFilterMinHeight: parseFloat(sidebarFilterStyle['min-height']),
    sidebarFilterPaddingLeft: parseFloat(sidebarFilterStyle['padding-left']),
    sidebarFilterPaddingRight: parseFloat(sidebarFilterStyle['padding-right']),
    sidebarFilterVisualTop: parseFloat(sidebarFilterVisualStyle.top),
    sidebarFilterVisualBottom: parseFloat(sidebarFilterVisualStyle.bottom),
    sidebarFilterVisualRadius: parseFloat(sidebarFilterVisualStyle.borderRadius),
    tokenBudgetLabelFontSize: parseFloat(tokenBudgetLabelStyle['font-size']),
    tokenBudgetPrimaryFontSize: parseFloat(tokenBudgetPrimaryStyle['font-size']),
    tokenBudgetPrimaryNumbers: tokenBudgetPrimaryStyle['font-variant-numeric'],
    tokenBudgetSecondaryFontSize: parseFloat(tokenBudgetSecondaryStyle['font-size'])
  };

  expect(transcriptPolish.toolCardMinHeight).toBeGreaterThanOrEqual(58);
  expect(transcriptPolish.toolCardRenderedHeight).toBeGreaterThanOrEqual(58);
  expect(transcriptPolish.toolStatusNumbers).toContain('tabular-nums');
  expect(transcriptPolish.toolCopyMinHeight).toBeGreaterThanOrEqual(MINIMUM_HIT_TARGET);
  expect(transcriptPolish.messageCopyMinHeight).toBeGreaterThanOrEqual(MINIMUM_HIT_TARGET);
  expect(transcriptPolish.sidebarMenuWidth).toBeGreaterThanOrEqual(MINIMUM_HIT_TARGET);
  expect(transcriptPolish.sidebarMenuHeight).toBeGreaterThanOrEqual(MINIMUM_HIT_TARGET);
  expect(transcriptPolish.sidebarFilterMinHeight).toBeGreaterThanOrEqual(MINIMUM_HIT_TARGET);
  expect(transcriptPolish.sidebarFilterPaddingLeft).toBe(10);
  expect(transcriptPolish.sidebarFilterPaddingRight).toBe(10);
  expect(transcriptPolish.sidebarFilterVisualTop).toBe(5);
  expect(transcriptPolish.sidebarFilterVisualBottom).toBe(5);
  expect(transcriptPolish.sidebarFilterVisualRadius).toBeGreaterThanOrEqual(999);
  expect(transcriptPolish.tokenBudgetLabelFontSize).toBeGreaterThanOrEqual(14);
  expect(transcriptPolish.tokenBudgetPrimaryFontSize).toBeGreaterThanOrEqual(16.5);
  expect(transcriptPolish.tokenBudgetPrimaryNumbers).toContain('tabular-nums');
  expect(transcriptPolish.tokenBudgetSecondaryFontSize).toBeGreaterThanOrEqual(14);
  await expectHitTarget(page.locator('[data-testid="tool-card-details"] summary'), 'tool details disclosure');
});

test('mock harness honors reduced motion for press and thinking states', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.goto(harnessURL());

  await page.getByLabel('Message').fill('run whoami');
  const sendButton = page.getByTestId('send-button');
  await expect(sendButton).toBeEnabled();

  const box = await sendButton.boundingBox();
  expect(box, 'send button should be visible for active-state probing').not.toBeNull();
  if (!box) {
    throw new Error('send button should be visible for active-state probing');
  }
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.down();
  const activeStyle = await sendButton.evaluate(element => {
    const style = getComputedStyle(element);
    return {
      transform: style.transform,
      transitionDuration: style.transitionDuration
    };
  });
  await page.mouse.up();

  const transitionDurations = activeStyle.transitionDuration
    .split(',')
    .map(value => Number.parseFloat(value.trim()))
    .filter(value => Number.isFinite(value));
  expect(
    activeStyle.transform,
    'press feedback should not scale controls when the user asks for reduced motion'
  ).toMatch(/^(none|matrix\(1, 0, 0, 1, 0, 0\))$/);
  expect(
    transitionDurations.every(value => value <= 0.001),
    `reduced-motion transitions should resolve immediately, got ${activeStyle.transitionDuration}`
  ).toBe(true);

  await page.evaluate(() => {
    const probe = document.createElement('span');
    probe.className = 'thinking-dot';
    probe.setAttribute('data-testid', 'reduced-motion-thinking-dot');
    document.body.appendChild(probe);
  });
  const thinkingDotStyle = await computedStyleProperties(page, '[data-testid="reduced-motion-thinking-dot"]', [
    'animation-name',
    'opacity',
    'transform'
  ]);

  expect(thinkingDotStyle['animation-name']).toBe('none');
  expect(thinkingDotStyle.opacity).toBe('0.72');
  expect(thinkingDotStyle.transform).toMatch(/^(none|matrix\(1, 0, 0, 1, 0, 0\))$/);
});

test('mock harness renders labeled composer controls without clipping their text', async ({ page }) => {
  await page.goto(harnessURL());

  // A labeled control must size to its text. A fixed icon-sized (44px square)
  // hit target clips a word like "Send" inside the square, so labeled controls
  // use text/capsule hit targets that grow with their content.
  await page.getByLabel('Message').fill('check');

  const labeledControls = ['send-button', 'model-picker-button', 'mode-picker-button'];
  for (const testID of labeledControls) {
    const metrics = await page.getByTestId(testID).evaluate(element => ({
      scrollWidth: element.scrollWidth,
      clientWidth: element.clientWidth,
      kind: element.dataset.hitTargetKind || '',
      text: (element.textContent || '').replace(/\s+/g, ' ').trim()
    }));
    expect(metrics.text.length, `${testID} should render a visible label`).toBeGreaterThan(0);
    expect(metrics.kind, `${testID} should not use a fixed icon hit target for a text label`).not.toBe('icon');
    expect(
      metrics.scrollWidth,
      `${testID} ("${metrics.text}") must not clip its label`
    ).toBeLessThanOrEqual(metrics.clientWidth + 1);
  }
});

test('mock harness stacks empty-starter title above its subtitle', async ({ page }) => {
  // The starter actions match the native VStack: a bold title on top and a
  // muted subtitle below it. A shared text hit target centers its children in a
  // row by default, which collapsed the two into one line with no separating
  // space (e.g. "Review changesFind risks..."), so the card overrides the
  // layout to a left-aligned vertical stack.
  for (const width of [1440, 390]) {
    await page.setViewportSize({ width, height: 900 });
    await page.goto(harnessURL());
    await expect(page.getByTestId('empty-starter-action').first()).toBeVisible();

    const layout = await page.getByTestId('empty-starter-action').first().evaluate(button => {
      const title = button.querySelector('strong')?.getBoundingClientRect();
      const subtitle = button.querySelector('span')?.getBoundingClientRect();
      if (!title || !subtitle) return null;
      return {
        titleBottom: title.bottom,
        titleLeft: title.left,
        subtitleTop: subtitle.top,
        subtitleLeft: subtitle.left
      };
    });

    expect(layout, `starter action at ${width}px should expose a title and subtitle`).not.toBeNull();
    expect(
      layout.subtitleTop,
      `starter subtitle should sit below its title at ${width}px, not beside it`
    ).toBeGreaterThanOrEqual(layout.titleBottom - 1);
    expect(
      Math.abs(layout.subtitleLeft - layout.titleLeft),
      `starter title and subtitle should share a left edge at ${width}px`
    ).toBeLessThanOrEqual(1);
  }
});

test('mock harness keeps secondary-pane action labels unclipped at tablet width', async ({ page }) => {
  // Header action buttons carry a shared text hit target whose 44px min-width
  // lets a flex row shrink them below their own label, clipping words like
  // "Add memory" at constrained widths. Sweep the secondary panes at a tablet
  // width and require every visible labeled button to fit its text.
  await page.setViewportSize({ width: 768, height: 900 });
  await page.goto(harnessURL());

  // The Activity pane claims right-side width, narrowing the main column where
  // the secondary panes live and squeezing their header action buttons.
  await clickSidebarTool(page, 'activity-button');
  await expect(page.getByTestId('activity-pane')).toBeVisible();
  await clickSidebarTool(page, 'memories-button');
  await expect(page.getByTestId('memories-pane')).toBeVisible();
  await page.getByTestId('extensions-button').click();
  await expect(page.getByTestId('extensions-pane')).toBeVisible();
  await page.getByTestId('automations-button').click();
  await expect(page.getByTestId('automations-pane')).toBeVisible();

  const clipped = await page.evaluate(() => {
    const offenders: Array<{ testID: string; text: string; scrollWidth: number; clientWidth: number }> = [];
    for (const button of Array.from(document.querySelectorAll('button'))) {
      const rect = button.getBoundingClientRect();
      if (rect.width < 2 || rect.height < 2) continue;
      const style = getComputedStyle(button);
      if (style.visibility === 'hidden' || style.display === 'none') continue;
      // Skip controls that intentionally scroll or ellipsize their content.
      if (style.overflowX !== 'visible' || style.textOverflow === 'ellipsis') continue;
      if (button.scrollWidth > button.clientWidth + 1) {
        offenders.push({
          testID: button.getAttribute('data-testid') || '',
          text: (button.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 40),
          scrollWidth: button.scrollWidth,
          clientWidth: button.clientWidth
        });
      }
    }
    return offenders;
  });

  expect(
    clipped,
    `secondary-pane buttons must fit their labels at 768px: ${JSON.stringify(clipped)}`
  ).toEqual([]);
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
    titleGroupStyle,
    contextStyle,
    titleRect,
    transcriptRect,
    metadataRect,
    topBarRect,
    actionRect
  ] = await Promise.all([
    page.evaluate(() => ({
      scrollWidth: document.documentElement.scrollWidth,
      viewportWidth: document.documentElement.clientWidth
    })),
    computedStyleProperties(page, '[data-testid="top-bar-clusters"]', ['display', 'grid-template-columns']),
    computedStyleProperties(page, '[data-testid="top-bar-title-group"]', ['display', 'text-align']),
    computedStyleProperties(page, '[data-testid="top-bar-subtitle"]', ['overflow', 'text-overflow']),
    elementRect(page, '[data-testid="top-bar-title-group"]'),
    elementRect(page, '[data-testid="transcript"]'),
    elementRect(page, '[data-testid="top-bar-status-metadata"]'),
    elementRect(page, '[data-testid="top-bar"]'),
    elementRect(page, '[data-testid="top-bar-action-cluster"]')
  ]);

  const metrics = {
    viewportWidth: viewportMetrics.viewportWidth,
    scrollWidth: viewportMetrics.scrollWidth,
    clustersDisplay: clustersStyle.display,
    clustersColumns: clustersStyle['grid-template-columns'],
    titleGroupDisplay: titleGroupStyle.display,
    titleTextAlign: titleGroupStyle['text-align'],
    titleLeft: titleRect.left,
    transcriptLeft: transcriptRect.left,
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
  expect(metrics.titleGroupDisplay).toBe('flex');
  expect(metrics.titleTextAlign).toBe('left');
  expect(
    Math.abs(metrics.titleLeft - metrics.transcriptLeft),
    'top-bar identity should align with the main workspace column, not the full window center'
  ).toBeLessThanOrEqual(16);
  expect(metrics.contextOverflow).toBe('hidden');
  expect(metrics.contextTextOverflow).toBe('ellipsis');
  expect(metrics.metadataWidth).toBeLessThanOrEqual(1);
  expect(metrics.metadataHeight).toBeLessThanOrEqual(1);
  expect(metrics.topBarHeight).toBeLessThanOrEqual(MINIMUM_HIT_TARGET + 1);
  expect(metrics.actionRight).toBeLessThanOrEqual(metrics.topBarRight);
});
