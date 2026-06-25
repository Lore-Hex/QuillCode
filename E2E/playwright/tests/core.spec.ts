import { test, expect, type Page } from '@playwright/test';
import { clickSidebarTool, openSettings, openSidebarTools, openTopBarOverflow } from './harness-helpers';

test('mock harness executes simple command flow', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');
  await expect(page.getByTestId('workspace')).toBeVisible();
  await expect(page.getByTestId('top-bar')).toBeVisible();
  await expect(page.getByTestId('sidebar')).toBeVisible();
  await expect(page.getByTestId('project-item')).toContainText('QuillCode');
  await expect(page.getByTestId('project-item')).toHaveAttribute('aria-current', 'true');
  await expect(page.getByTestId('transcript-empty')).toBeVisible();
  await expect(page.locator('[data-testid="top-bar"] [data-testid="model-picker-button"]')).toHaveCount(0);
  await expect(page.getByTestId('composer-surface')).toBeVisible();
  await expect(page.getByTestId('composer-controls')).toBeVisible();
  await expect(page.locator('[data-testid="composer"] [data-testid="model-picker-button"]')).toBeVisible();
  await expect(page.getByTestId('model-picker-button')).toHaveText('Nike 1.0');
  await expect(page.getByTestId('model-picker-button')).not.toContainText('Auto');
  await expect(page.getByTestId('mode-picker-button')).toBeVisible();
  await expect(page.getByTestId('mode-picker-button')).not.toContainText('Mode');
  await expect(page.getByTestId('mode-pill')).toHaveText('Auto');
  await expect(page.locator('[data-testid="mode-picker-button"] .mode-dot')).toHaveCount(1);
  await expect(page.getByTestId('composer-agent-status')).toHaveCount(0);
  const modelButtonBox = await page.getByTestId('model-picker-button').boundingBox();
  const modeButtonBox = await page.getByTestId('mode-picker-button').boundingBox();
  expect(modelButtonBox).not.toBeNull();
  expect(modeButtonBox).not.toBeNull();
  expect(modeButtonBox!.x - (modelButtonBox!.x + modelButtonBox!.width)).toBeGreaterThanOrEqual(8);
  await page.getByTestId('model-picker-button').click();
  await expect(page.getByTestId('model-category')).toHaveCount(2);
  await page.getByTestId('model-picker-button').click();
  await expect(page.getByTestId('send-button')).toBeDisabled();

  await expect(page.getByTestId('new-chat-button')).toBeVisible();
  await expect(page.getByTestId('sidebar-search-button')).toBeVisible();
  await expect(page.getByTestId('extensions-button')).toBeVisible();
  await expect(page.getByTestId('automations-button')).toBeVisible();
  await openSidebarTools(page);
  await expect(page.getByTestId('sidebar-tools-section-title')).toHaveText([
    'Navigate',
    'Workspace',
    'Context'
  ]);
  await expect(page.locator('[data-testid="sidebar-tools-section"][data-command-group="navigate"]')).toContainText('Command palette');
  await expect(page.locator('[data-testid="sidebar-tools-section"][data-command-group="workspace"]')).toContainText('Terminal');
  await page.getByTestId('sidebar-tools-button').click();
  await expect(page.getByTestId('sidebar-tools-menu')).not.toHaveAttribute('open', '');

  await openTopBarOverflow(page);
  await expect(page.getByTestId('top-bar-overflow-command-palette')).toBeVisible();
  await expect(page.getByTestId('top-bar-overflow-search')).toBeVisible();
  await expect(page.getByTestId('top-bar-overflow-computer-use')).toBeVisible();
  await expect(page.getByTestId('top-bar-overflow-settings')).toBeVisible();
  await expect(page.getByTestId('top-bar-overflow-keyboard-shortcuts')).toBeVisible();
  await expect(page.getByTestId('top-bar-overflow-stop-all')).toHaveCount(0);
  await expect(page.getByTestId('top-bar-stop-button')).toHaveCount(0);
  await page.getByTestId('top-bar-overflow-settings').click();
  await expect(page.getByTestId('settings-panel')).toBeVisible();
  await expect(page.getByTestId('settings-key-status')).toHaveText('Not signed in');
  await page.getByTestId('settings-sign-in').click();
  await expect(page.getByTestId('last-opened-url')).toHaveText('http://localhost:3000/callback');
  await page.getByLabel('TrustedRouter API base URL').fill('https://api.trustedrouter.test/v1');
  await page.getByLabel('Authentication').selectOption('developer-override');
  await page.getByLabel('Replace API key').fill('sk-tr-v1-test');
  await page.getByTestId('settings-save').click();
  await expect(page.getByTestId('settings-panel')).toBeHidden();
  await expect(page.getByTestId('agent-status')).toHaveText('TrustedRouter ready');

  await page.getByTestId('model-picker-button').click();
  await page.getByTestId('model-search').fill('glm');
  await page.getByTestId('model-option').click();
  await expect(page.getByTestId('model-picker-button')).toHaveText('z-ai/GLM 5.2');
  await expect(page.getByTestId('mode-pill')).toHaveText('Auto');

  await page.getByLabel('Message').fill('run whoami');
  await expect(page.getByTestId('send-button')).toBeEnabled();
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('sidebar-item')).toContainText('run whoami');
  await expect(page.getByTestId('sidebar-item')).toContainText('z-ai/GLM 5.2');
  await expect(page.getByTestId('top-bar-title')).toHaveText('run whoami');
  await expect(page.getByTestId('top-bar-subtitle')).toContainText('QuillCode - Auto');
  await expect(page.getByTestId('tool-card-title')).toHaveText('host.shell.run');
  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-status', 'done');
  await expect(page.getByTestId('tool-card-subtitle')).toHaveText('Completed · whoami');
  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-density', 'collapsed');
  await expect(page.getByTestId('tool-card-input')).toContainText('whoami');
  await expect(page.getByTestId('tool-card-output')).toContainText('mock-user');
  await expect(page.getByTestId('tool-card-details')).not.toHaveAttribute('open', '');
  await expect(page.getByTestId('tool-card-details')).toContainText('Show details');
  await expect(page.getByText('You are `mock-user` in this workspace.')).toBeVisible();
  await expect(page.getByTestId('message-copy').first()).toHaveText('Copy');
  await page.getByTestId('message-copy').first().click();
  await expect(page.getByTestId('message-copy').first()).toHaveText('Copied');
  await expect(page.getByTestId('message-copy').first()).toHaveAttribute('data-copied', 'true');
  await expect(page.getByTestId('tool-card-copy')).toHaveText('Copy output');
  await page.getByTestId('tool-card-copy').click();
  await expect(page.getByTestId('tool-card-copy')).toHaveText('Copied');
  await expect(page.getByTestId('tool-card-copy')).toHaveAttribute('data-copied', 'true');
  await expect(page.getByTestId('message-use-as-draft')).toHaveCount(1);
  await page.getByTestId('message-use-as-draft').click();
  await expect(page.getByLabel('Message')).toHaveValue('run whoami');
  await expect(page.getByTestId('send-button')).toBeEnabled();
  await expect(page.getByTestId('message-feedback-up')).toHaveCount(1);
  await expect(page.getByTestId('message-feedback-down')).toHaveCount(1);
  await page.getByTestId('message-feedback-up').click();
  await expect(page.getByTestId('message-feedback-up')).toHaveAttribute('data-selected', 'true');
  await expect(page.getByTestId('message-feedback-down')).toHaveAttribute('data-selected', 'false');
  await page.getByTestId('message-feedback-down').click();
  await expect(page.getByTestId('message-feedback-up')).toHaveAttribute('data-selected', 'false');
  await expect(page.getByTestId('message-feedback-down')).toHaveAttribute('data-selected', 'true');

  const transcriptItems = page.locator('[data-testid="message"], [data-testid="tool-card"]');
  await expect(transcriptItems.nth(0)).toContainText('run whoami');
  await expect(transcriptItems.nth(1)).toContainText('host.shell.run');
  await expect(transcriptItems.nth(2)).toContainText('You are `mock-user` in this workspace.');
  await expect(page.getByTestId('message-retry')).toHaveCount(1);
  await page.getByTestId('message-retry').click();
  await expect(page.getByTestId('tool-card')).toHaveCount(2);
  await expect(page.getByTestId('message').filter({ hasText: 'You are `mock-user` in this workspace.' })).toHaveCount(2);
  await expect(page.getByTestId('message-retry')).toHaveCount(1);
  await expect(page.getByTestId('message-use-as-draft')).toHaveCount(2);
});

test('mock harness exposes actionable approval buttons on review cards', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await page.evaluate(() => {
    const harness = window as typeof window & {
      addToolCard: (card: Record<string, unknown>) => void;
      render: () => void;
    };
    harness.addToolCard({
      id: 'shell-review',
      title: 'host.shell.run',
      subtitle: 'Ready to run · whoami',
      status: 'review',
      reviewState: 'ready',
      density: 'expanded',
      inputJSON: JSON.stringify({ cmd: 'whoami' }, null, 2),
      isExpanded: true,
      actions: [
        {
          id: 'tool-card-action-approve-approval-1',
          title: 'Run',
          kind: 'approve',
          requestID: 'approval-1',
          style: 'primary'
        },
        {
          id: 'tool-card-action-deny-approval-1',
          title: 'Skip',
          kind: 'deny',
          requestID: 'approval-1',
          style: 'secondary'
        }
      ]
    });
    harness.render();
  });

  await expect(page.getByTestId('tool-card')).toHaveCount(1);
  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-status', 'review');
  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-review-state', 'ready');
  await expect(page.getByTestId('tool-card-status')).toHaveText('Ready');
  await expect(page.getByTestId('tool-card-actions')).toBeVisible();
  await expect(page.getByTestId('tool-card-action').filter({ hasText: 'Run' })).toBeVisible();
  await expect(page.getByTestId('tool-card-action').filter({ hasText: 'Skip' })).toBeVisible();
  const runBox = await page.getByTestId('tool-card-action').filter({ hasText: 'Run' }).boundingBox();
  const skipBox = await page.getByTestId('tool-card-action').filter({ hasText: 'Skip' }).boundingBox();
  expect(runBox).not.toBeNull();
  expect(skipBox).not.toBeNull();
  expect(runBox!.width).toBeGreaterThan(skipBox!.width);

  await page.getByTestId('tool-card-action').filter({ hasText: 'Run' }).click();

  await expect(page.getByTestId('tool-card')).toHaveCount(2);
  await expect(page.getByTestId('tool-card').first()).toHaveAttribute('data-status', 'done');
  await expect(page.getByTestId('tool-card-subtitle').first()).toHaveText('Approved · whoami');
  await expect(page.getByTestId('tool-card-actions')).toHaveCount(0);
  await expect(page.getByTestId('tool-card').nth(1)).toHaveAttribute('data-status', 'done');
  await expect(page.getByTestId('tool-card-output').last()).toContainText('mock-user');
  await expect(page.getByTestId('message').last()).toContainText('Approved and ran the tool.');
});

test('mock harness shows denied review cards as needs review without actions', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await page.evaluate(() => {
    const harness = window as typeof window & {
      addToolCard: (card: Record<string, unknown>) => void;
      render: () => void;
    };
    harness.addToolCard({
      id: 'shell-blocked-review',
      title: 'host.shell.run',
      subtitle: 'Blocked · rm -rf /',
      status: 'review',
      reviewState: 'needsReview',
      density: 'expanded',
      inputJSON: JSON.stringify({ cmd: 'rm -rf /' }, null, 2),
      isExpanded: true,
      actions: []
    });
    harness.render();
  });

  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-status', 'review');
  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-review-state', 'needsReview');
  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-status-label', 'Needs review');
  await expect(page.getByTestId('tool-card-status')).toHaveText('Needs review');
  await expect(page.getByTestId('tool-card-action')).toHaveCount(0);
});

test('mock harness opens utilities from the top-bar overflow', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

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
    await page.goto('file://' + process.cwd() + '/../harness/index.html');

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
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  const polish = await page.evaluate(() => {
    const styleFor = (selector: string) => getComputedStyle(document.querySelector(selector)!);
    const sendButton = styleFor('[data-testid="send-button"]');
    const addProjectButton = styleFor('[data-testid="add-project-button"]');
    const sidebarAction = styleFor('[data-testid="new-chat-button"]');
    const messageInput = styleFor('#message');
    const title = styleFor('[data-testid="top-bar-title"]');
    const agentStatus = styleFor('[data-testid="agent-status"]');
    const sidebar = styleFor('[data-testid="sidebar"]');
    const sidebarToolsButton = styleFor('[data-testid="sidebar-tools-button"]');
    const sidebarToolAction = styleFor('[data-testid="sidebar-search-button"]');
    const sidebarSettingsButton = styleFor('[data-testid="settings-button"]');

    return {
      rootFontSmoothing: getComputedStyle(document.documentElement).webkitFontSmoothing,
      sendMinHeight: parseFloat(sendButton.minHeight),
      sendTransitionProperty: sendButton.transitionProperty,
      inputTransitionProperty: messageInput.transitionProperty,
      sidebarActionTransitionProperty: sidebarAction.transitionProperty,
      sidebarActionMinHeight: parseFloat(sidebarAction.minHeight),
      titleTextWrap: title.getPropertyValue('text-wrap'),
      agentStatusNumbers: agentStatus.fontVariantNumeric,
      addProjectWidth: parseFloat(addProjectButton.width),
      addProjectHeight: parseFloat(addProjectButton.height),
      sidebarToolsMinHeight: parseFloat(sidebarToolsButton.minHeight),
      sidebarToolsTransitionProperty: sidebarToolsButton.transitionProperty,
      sidebarToolActionMinHeight: parseFloat(sidebarToolAction.minHeight),
      sidebarToolActionTransitionProperty: sidebarToolAction.transitionProperty,
      sidebarSettingsWidth: parseFloat(sidebarSettingsButton.width),
      sidebarSettingsMinHeight: parseFloat(sidebarSettingsButton.minHeight),
      sidebarRadius: parseFloat(sidebar.borderRadius)
    };
  });

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

  const transcriptPolish = await page.evaluate(() => {
    const styleFor = (selector: string) => getComputedStyle(document.querySelector(selector)!);
    const toolCard = styleFor('[data-testid="tool-card"]');
    const toolCardRect = document.querySelector('[data-testid="tool-card"]')!.getBoundingClientRect();
    const toolStatus = styleFor('[data-testid="tool-card-status"]');
    const toolCopyButton = styleFor('[data-testid="tool-card-copy"]');
    const messageCopyButton = styleFor('[data-testid="message-copy"]');
    const sidebarMenuRect = document.querySelector('[data-testid="sidebar-item-actions"] summary')!.getBoundingClientRect();

    return {
      toolCardMinHeight: parseFloat(toolCard.minHeight),
      toolCardRenderedHeight: toolCardRect.height,
      toolStatusNumbers: toolStatus.fontVariantNumeric,
      toolCopyMinHeight: parseFloat(toolCopyButton.minHeight),
      messageCopyMinHeight: parseFloat(messageCopyButton.minHeight),
      sidebarMenuWidth: sidebarMenuRect.width,
      sidebarMenuHeight: sidebarMenuRect.height
    };
  });

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
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

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

  const metrics = await page.evaluate(() => {
    const styleFor = (selector: string) => getComputedStyle(document.querySelector(selector)!);
    const rectFor = (selector: string) => document.querySelector(selector)!.getBoundingClientRect();
    const topBarRect = rectFor('[data-testid="top-bar"]');
    const actionRect = rectFor('[data-testid="top-bar-action-cluster"]');
    const metadataRect = rectFor('[data-testid="top-bar-status-metadata"]');
    return {
      viewportWidth: document.documentElement.clientWidth,
      scrollWidth: document.documentElement.scrollWidth,
      clustersDisplay: styleFor('[data-testid="top-bar-clusters"]').display,
      clustersColumns: styleFor('[data-testid="top-bar-clusters"]').gridTemplateColumns,
      contextOverflow: styleFor('[data-testid="top-bar-subtitle"]').overflow,
      contextTextOverflow: styleFor('[data-testid="top-bar-subtitle"]').textOverflow,
      metadataWidth: metadataRect.width,
      metadataHeight: metadataRect.height,
      topBarHeight: topBarRect.height,
      actionRight: actionRect.right,
      topBarRight: topBarRect.right
    };
  });

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

test('mock harness preserves transcript scroll intent as new events append', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await page.evaluate(() => {
    const harness = window as unknown as { sendMessage: (value: string) => void };
    for (let index = 0; index < 24; index += 1) {
      harness.sendMessage(`run whoami ${index}`);
    }
  });

  const timeline = page.getByTestId('timeline');
  await expect(timeline).toBeVisible();
  const scrollable = await page.evaluate(() => document.documentElement.scrollHeight > window.innerHeight);
  expect(scrollable).toBe(true);

  const midScroll = await page.evaluate(() => {
    const nextScrollY = Math.floor((document.documentElement.scrollHeight - window.innerHeight) / 2);
    window.scrollTo(0, nextScrollY);
    return window.scrollY;
  });
  await page.evaluate(() => {
    const harness = window as unknown as { sendMessage: (value: string) => void };
    harness.sendMessage('run whoami while reading history');
  });
  const afterMidAppend = await page.evaluate(() => window.scrollY);
  expect(Math.abs(afterMidAppend - midScroll)).toBeLessThanOrEqual(1);

  await page.evaluate(() => {
    window.scrollTo(0, document.documentElement.scrollHeight);
  });
  await page.evaluate(() => {
    const harness = window as unknown as { sendMessage: (value: string) => void };
    harness.sendMessage('run whoami at bottom');
  });
  const bottomDistance = await page.evaluate(() =>
    Math.max(0, document.documentElement.scrollHeight - window.innerHeight - window.scrollY)
  );
  expect(bottomDistance).toBeLessThanOrEqual(1);
});

test('mock harness shows model-authored task plan in Activity', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await page.getByLabel('Message').fill('plan the QuillCode work');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.plan.update');
  await expect(page.getByText('Updated the task plan.')).toBeVisible();

  await clickSidebarTool(page, 'activity-button');
  await expect(page.getByTestId('activity-pane')).toBeVisible();
  await expect(page.getByTestId('activity-plan')).toHaveCount(3);
  await expect(page.getByTestId('activity-plan').nth(0)).toContainText('Inspect current state');
  await expect(page.getByTestId('activity-plan').nth(0)).toContainText('Done');
  await expect(page.getByTestId('activity-plan').nth(1)).toContainText('Implement requested change');
  await expect(page.getByTestId('activity-plan').nth(1)).toContainText('Running');
  await expect(page.getByTestId('activity-plan').nth(1)).toContainText('Keep the slice reviewable.');
  await expect(page.getByTestId('activity-plan').nth(2)).toContainText('Validate and summarize');
  await expect(page.getByTestId('activity-plan').nth(2)).toContainText('Pending');
  await expect(page.getByTestId('activity-plan-section')).toContainText('3 items');
});

test('mock harness shows context pressure banner and compacts or forks from latest turn', async ({ page }) => {
  test.setTimeout(60000);
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  const longPrompt = 'long context ' + 'word '.repeat(22000);
  await page.getByLabel('Message').fill(longPrompt);
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('context-banner')).toBeVisible();
  await expect(page.getByTestId('context-banner-title')).toContainText(/context limit/i);

  await page.getByLabel('Message').fill('run whoami');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('context-banner')).toBeVisible();

  await page.getByTestId('context-compact').click();

  await expect(page.getByTestId('top-bar-title')).toContainText('Compact:');
  await expect(page.getByTestId('context-banner')).toHaveCount(0);
  await expect(page.getByTestId('message').first()).toContainText('Context compacted from');
  await expect(page.getByTestId('message').nth(1)).toContainText('run whoami');

  await page.getByRole('textbox', { name: 'Message' }).fill('long context again ' + 'word '.repeat(22000));
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('context-banner')).toBeVisible();
  await page.getByRole('textbox', { name: 'Message' }).fill('run whoami');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('context-banner')).toBeVisible();

  await page.getByTestId('context-fork-last').click();

  await expect(page.getByTestId('top-bar-title')).toContainText('Fork:');
  await expect(page.getByTestId('context-banner')).toHaveCount(0);
  await expect(page.getByTestId('message').first()).toContainText('run whoami');
  await expect(page.getByText('You are `mock-user` in this workspace.')).toBeVisible();
});
test('mock harness shows memories from sidebar and command palette', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await expect(page.getByTestId('project-memories-status')).toHaveText('2 memories');
  await clickSidebarTool(page, 'memories-button');

  await expect(page.getByTestId('memories-pane')).toBeVisible();
  await expect(page.getByTestId('memories-subtitle')).toHaveText('1 global memory · 1 project memory');
  await expect(page.getByTestId('memory-item')).toHaveCount(2);
  await expect(page.getByTestId('memory-title').first()).toHaveText('Preferences');
  await expect(page.getByTestId('memory-path').first()).toHaveText('memories/preferences.md');
  await expect(page.getByTestId('memory-delete')).toHaveCount(1);
  await expect(page.getByTestId('memories-add')).toBeVisible();

  await clickSidebarTool(page, 'command-palette-button');
  await page.getByLabel('Search commands').fill('>memories');
  await page.getByTestId('command-palette-result').filter({ hasText: 'Memories' }).click();

  await expect(page.getByTestId('memories-pane')).toHaveCount(0);

  await clickSidebarTool(page, 'command-palette-button');
  await page.getByLabel('Search commands').fill('>save');
  await expect(page.getByTestId('command-palette-result')).toHaveCount(1);
  await expect(page.getByTestId('command-palette-result')).toContainText('Add memory');
  await page.getByTestId('command-palette-result').click();

  await expect(page.getByLabel('Message')).toHaveValue('/remember ');
  await page.getByLabel('Message').fill('/remember Prefer small reviewable commits');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByText('Saved memory: Prefer Small Reviewable Commits. It will be included as background context in future turns.')).toBeVisible();
  await expect(page.getByTestId('project-memories-status')).toHaveText('3 memories');
  await expect(page.getByTestId('top-bar-title')).toHaveText('Memory: Prefer Small Reviewable Commits');

  await clickSidebarTool(page, 'memories-button');
  await expect(page.getByTestId('memories-pane')).toBeVisible();
  await expect(page.getByTestId('memories-subtitle')).toHaveText('2 global memories · 1 project memory');
  await expect(page.getByTestId('memory-item')).toHaveCount(3);
  await expect(page.getByTestId('memory-title').first()).toHaveText('Prefer Small Reviewable Commits');
  await expect(page.getByTestId('memory-path').first()).toContainText('memories/manual-');
  await expect(page.getByTestId('memory-delete')).toHaveCount(2);

  await page.getByTestId('memory-delete').first().click();

  await expect(page.getByText('Forgot memory: Prefer Small Reviewable Commits. It will no longer be included as background context.')).toBeVisible();
  await expect(page.getByTestId('project-memories-status')).toHaveText('2 memories');
  await expect(page.getByTestId('top-bar-title')).toHaveText('Forgot memory: Prefer Small Reviewable Commits');
  await expect(page.getByTestId('memories-subtitle')).toHaveText('1 global memory · 1 project memory');
  await expect(page.getByTestId('memory-item')).toHaveCount(2);
  await expect(page.getByTestId('memory-title').first()).toHaveText('Preferences');
  await expect(page.getByTestId('memory-delete')).toHaveCount(1);
});

test('mock harness dispatches workspace keyboard shortcuts', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await page.keyboard.press('Meta+K');
  await expect(page.getByTestId('search-panel')).toBeVisible();
  await page.getByTestId('search-close').click();

  await page.keyboard.press('Meta+Shift+P');
  await expect(page.getByTestId('command-palette-panel')).toBeVisible();
  await page.getByTestId('command-palette-close').click();

  await page.keyboard.press('Meta+/');
  await expect(page.getByTestId('keyboard-shortcuts-panel')).toBeVisible();
  await expect(page.getByTestId('keyboard-shortcut-row').filter({ hasText: 'Keyboard shortcuts' })).toContainText('Cmd+/');
  await page.getByTestId('keyboard-shortcuts-close').click();

  await page.keyboard.press('Control+Backquote');
  await expect(page.getByTestId('terminal-pane')).toBeVisible();

  await page.keyboard.press('Meta+Shift+B');
  await expect(page.getByTestId('browser-pane')).toBeVisible();

  await page.getByLabel('Message').fill('run whoami');
  await page.getByRole('button', { name: 'Send' }).click();

  await page.keyboard.press('Meta+F');
  await expect(page.getByTestId('find-bar')).toBeVisible();
  await expect(page.getByTestId('find-input')).toBeFocused();
  await page.getByTestId('find-input').fill('host.shell.run');
  await expect(page.getByTestId('find-status')).toHaveText('1 of 1');
  await expect(page.locator('.find-active')).toContainText('host.shell.run');

  await page.getByTestId('find-input').fill('mock-user');
  await expect(page.getByTestId('find-status')).toHaveText('1 of 2');
  await page.getByTestId('find-next').click();
  await expect(page.getByTestId('find-status')).toHaveText('2 of 2');
  await page.getByTestId('find-close').click();
  await expect(page.getByTestId('find-bar')).toHaveCount(0);

  await page.keyboard.press('Meta+N');

  await expect(page.getByTestId('transcript-empty')).toBeVisible();
});
