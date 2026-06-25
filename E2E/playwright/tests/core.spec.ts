import { test, expect, type Locator, type Page } from '@playwright/test';
import { clickSidebarTool, openSettings, openSidebarTools, openTopBarOverflow } from './harness-helpers';

async function clickProjectAction(row: Locator, name: string) {
  await row.getByLabel(/^Actions for project /).click();
  await row.getByRole('button', { name }).click();
}

async function replaceFocusedText(page: Page, text: string) {
  await page.keyboard.press('ControlOrMeta+A');
  await page.keyboard.type(text);
}

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

test('mock harness composer supports multiline editing and Enter-to-send', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  const message = page.getByLabel('Message');
  await expect(message).toHaveJSProperty('tagName', 'TEXTAREA');
  await message.fill('first line');
  const initialHeight = await message.evaluate((element: HTMLTextAreaElement) => element.clientHeight);

  await message.press('Shift+Enter');
  await page.keyboard.type('second line');

  await expect(message).toHaveValue('first line\nsecond line');
  const expandedHeight = await message.evaluate((element: HTMLTextAreaElement) => element.clientHeight);
  expect(expandedHeight).toBeGreaterThan(initialHeight);
  await expect(page.getByTestId('message')).toHaveCount(0);

  await message.press('Enter');

  await expect(message).toHaveValue('');
  await expect(page.getByTestId('message').first()).toContainText('first line');
  await expect(page.getByTestId('message').first()).toContainText('second line');
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

test('mock harness stops an active composer run from the composer', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await page.getByLabel('Message').fill('slow task');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('agent-status')).toHaveText('Running');
  await expect(page.getByTestId('top-bar-stop-button')).toBeVisible();
  await expect(page.getByTestId('stop-button')).toBeVisible();
  await expect(page.getByTestId('send-button')).toHaveCount(0);
  await expect(page.getByLabel('Message')).toBeDisabled();
  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-status', 'running');

  await page.getByTestId('top-bar-stop-button').click();

  await expect(page.getByTestId('agent-status')).toHaveText('Stopped');
  await expect(page.getByTestId('top-bar-stop-button')).toHaveCount(0);
  await expect(page.getByTestId('stop-button')).toHaveCount(0);
  await expect(page.getByTestId('send-button')).toBeDisabled();
  await expect(page.getByLabel('Message')).toBeEnabled();
  await expect(page.getByTestId('tool-card')).toHaveAttribute('data-status', 'failed');
  await expect(page.getByTestId('tool-card')).toContainText('Stopped');

  await page.waitForTimeout(2200);
  await expect(page.getByText('Long-running task completed.')).toHaveCount(0);
  await expect(page.getByTestId('agent-status')).toHaveText('Stopped');
});

test('mock harness surfaces file artifacts from tool cards', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await page.getByLabel('Message').fill('Can you write a file that says hello world');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.file.write');
  await expect(page.getByTestId('tool-card-artifacts')).toBeVisible();
  await expect(page.getByTestId('tool-card-artifact-label')).toHaveText('hello.txt');
  await expect(page.getByTestId('tool-card-artifact-detail')).toHaveText('/mock/QuillCode');
  await expect(page.getByTestId('tool-card-artifact')).toHaveAttribute('data-kind', 'file');
  await expect(page.getByTestId('tool-card-artifact')).toHaveAttribute('href', 'file:///mock/QuillCode/hello.txt');
  await expect(page.getByTestId('tool-card-text-previews')).toBeVisible();
  await expect(page.getByTestId('tool-card-text-preview-label')).toHaveText('hello.txt');
  await expect(page.getByTestId('tool-card-text-preview-content')).toHaveText('hello world');
  await expect.poll(() => page.getByTestId('tool-card-details').evaluate(element => (element as HTMLDetailsElement).open)).toBe(false);
  await page.getByTestId('tool-card-details').locator('summary').click();
  await expect.poll(() => page.getByTestId('tool-card-details').evaluate(element => (element as HTMLDetailsElement).open)).toBe(true);
  await expect(page.getByTestId('tool-card-output')).toContainText('/mock/QuillCode/hello.txt');
  await expect(page.getByText('Wrote `hello.txt`.')).toBeVisible();

  await clickSidebarTool(page, 'activity-button');
  await expect(page.getByTestId('activity-pane')).toBeVisible();
  await expect(page.getByTestId('activity-task-title')).toContainText('Can you write a file');
  await expect(page.getByTestId('activity-tool')).toContainText('host.file.write');
  await expect(page.getByTestId('activity-artifact')).toContainText('hello.txt');
  await expect(page.getByTestId('activity-artifact')).toContainText('/mock/QuillCode');
  await expect(page.getByTestId('activity-artifact')).not.toContainText('undefined');
  await expect(page.getByTestId('activity-source').first()).toContainText('AGENTS.md');
  await expect(page.getByTestId('activity-plan')).toHaveCount(5);
  await expect(page.getByTestId('activity-plan').nth(0)).toContainText('Understand request');
  await expect(page.getByTestId('activity-plan').nth(2)).toContainText('Use tools');
  await expect(page.getByTestId('activity-plan').nth(2)).toContainText('Done');
  await expect(page.getByTestId('activity-plan').nth(4)).toContainText('Answer user');
  await expect(page.getByTestId('activity-handoff')).toContainText('Thread: Can you write a file');
  await expect(page.getByTestId('activity-handoff')).toContainText('Tools: 1 tool (host.file.write)');
  await expect(page.getByTestId('activity-handoff')).toContainText('Artifacts: 1 artifact (hello.txt)');
  await expect(page.getByTestId('activity-handoff')).not.toContainText('\\n');
  await expect(page.getByTestId('activity-final-answer')).toContainText('Wrote `hello.txt`.');

  await page.getByTestId('activity-handoff-section').getByTestId('activity-section-toggle').click();
  await expect(page.getByTestId('activity-handoff-section')).toHaveAttribute('data-collapsed', 'true');
  await expect(page.getByTestId('activity-handoff')).toHaveCount(0);
  await page.getByTestId('activity-handoff-section').getByTestId('activity-section-toggle').click();
  await expect(page.getByTestId('activity-handoff')).toContainText('Latest answer: Wrote `hello.txt`.');

  await page.getByTestId('activity-plan-section').getByTestId('activity-section-toggle').click();
  await expect(page.getByTestId('activity-plan-section')).toHaveAttribute('data-collapsed', 'true');
  await expect(page.getByTestId('activity-plan')).toHaveCount(0);
  await page.getByTestId('activity-plan-section').getByTestId('activity-section-toggle').click();
  await expect(page.getByTestId('activity-plan')).toHaveCount(5);

  await page.getByTestId('activity-tool-section').getByTestId('activity-section-toggle').click();
  await expect(page.getByTestId('activity-tool-section')).toHaveAttribute('data-collapsed', 'true');
  await expect(page.getByTestId('activity-tool')).toHaveCount(0);
  await page.getByTestId('activity-tool-section').getByTestId('activity-section-toggle').click();
  await expect(page.getByTestId('activity-tool-section')).toHaveAttribute('data-collapsed', 'false');
  await expect(page.getByTestId('activity-tool')).toContainText('host.file.write');
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

test('mock harness renders image artifact previews from tool cards', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await page.getByLabel('Message').fill('take a screenshot');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.computer.screenshot');
  await expect(page.getByTestId('tool-card-artifact-label')).toHaveText('screenshot.png');
  await expect(page.getByTestId('tool-card-image-previews')).toBeVisible();
  await expect(page.getByTestId('tool-card-image-preview')).toBeVisible();
  await expect(page.getByTestId('tool-card-image-preview')).toHaveAttribute('data-kind', 'image');
  await expect(page.getByTestId('tool-card-image-preview-type')).toHaveText('Image · PNG');
  await expect(page.getByTestId('tool-card-image-preview-label')).toHaveText('screenshot.png');
  await expect(page.getByTestId('tool-card-image-preview-detail')).toHaveText('/mock/QuillCode/screenshots');
  await expect(page.getByTestId('tool-card-image-preview').locator('img')).toHaveAttribute('src', 'file:///mock/QuillCode/screenshots/screenshot.png');
  const imageSurface = await page.getByTestId('tool-card-image-preview').evaluate((element) => {
    const cardStyle = getComputedStyle(element);
    const imageStyle = getComputedStyle(element.querySelector('img')!);
    return {
      cardRadius: cardStyle.borderRadius,
      imageRadius: imageStyle.borderRadius,
      imageOutlineColor: imageStyle.outlineColor,
      imageOutlineWidth: imageStyle.outlineWidth,
      imageOutlineOffset: imageStyle.outlineOffset
    };
  });
  expect(imageSurface.cardRadius).toBe('18px');
  expect(imageSurface.imageRadius).toBe('10px');
  expect(imageSurface.imageOutlineColor).toBe('rgba(255, 255, 255, 0.1)');
  expect(imageSurface.imageOutlineWidth).toBe('1px');
  expect(imageSurface.imageOutlineOffset).toBe('-1px');
  await expect(page.getByText('Captured a screenshot (1280 x 720).')).toBeVisible();
});

test('mock harness renders document artifact previews from tool cards', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await page.getByLabel('Message').fill('make a pdf artifact');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.file.write');
  await expect(page.getByTestId('tool-card-artifact-label')).toHaveText('briefing.pdf');
  await expect(page.getByTestId('tool-card-document-previews')).toBeVisible();
  await expect(page.getByTestId('tool-card-document-preview')).toBeVisible();
  await expect(page.getByTestId('tool-card-document-preview')).toHaveAttribute('data-kind', 'pdf');
  await expect(page.getByTestId('tool-card-document-preview-type')).toHaveText('PDF · PDF');
  await expect(page.getByTestId('tool-card-document-preview-label')).toHaveText('briefing.pdf');
  await expect(page.getByTestId('tool-card-document-preview-detail')).toHaveText('/mock/QuillCode/reports');
  await expect(page.getByTestId('tool-card-document-preview-open')).toHaveAttribute('href', 'file:///mock/QuillCode/reports/briefing.pdf');
  const documentSurface = await page.getByTestId('tool-card-document-preview').evaluate((element) => {
    const cardStyle = getComputedStyle(element);
    const iconStyle = getComputedStyle(element.querySelector('.artifact-document-icon')!);
    return {
      cardRadius: cardStyle.borderRadius,
      cardMinHeight: cardStyle.minHeight,
      iconRadius: iconStyle.borderRadius,
      transitionProperty: cardStyle.transitionProperty
    };
  });
  expect(documentSurface.cardRadius).toBe('18px');
  expect(documentSurface.cardMinHeight).toBe('74px');
  expect(documentSurface.iconRadius).toBe('10px');
  expect(documentSurface.transitionProperty).toBe('transform, box-shadow');
  await expect(page.getByText('Created `briefing.pdf`.')).toBeVisible();
});

test('mock harness renders appshot artifact previews from tool cards', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await page.getByLabel('Message').fill('make an appshot artifact');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('tool-card-title')).toHaveText('host.appshot.capture');
  await expect(page.getByTestId('tool-card-artifact-label')).toHaveText('checkout.appshot.json');
  await expect(page.getByTestId('tool-card-document-previews')).toBeVisible();
  await expect(page.getByTestId('tool-card-document-preview')).toHaveAttribute('data-kind', 'appshot');
  await expect(page.getByTestId('tool-card-document-preview-type')).toHaveText('Appshot · APPSHOT');
  await expect(page.getByTestId('tool-card-document-preview-label')).toHaveText('checkout.appshot.json');
  await expect(page.getByTestId('tool-card-document-preview-detail')).toHaveText('/mock/QuillCode/appshots');
  await expect(page.getByTestId('tool-card-document-preview-open')).toHaveAttribute('href', 'file:///mock/QuillCode/appshots/checkout.appshot.json');
  await expect(page.getByTestId('tool-card-text-previews')).toHaveCount(0);
  await expect(page.getByText('Captured appshot `checkout.appshot.json`.')).toBeVisible();
});

test('mock harness searches and reopens an existing chat', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await page.getByLabel('Message').fill('run whoami');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('sidebar-item')).toContainText('run whoami');

  await clickSidebarTool(page, 'sidebar-search-button');
  await expect(page.getByTestId('search-panel')).toBeVisible();
  await expect(page.getByTestId('search-input')).toBeFocused();
  await expect(page.getByTestId('search-result')).toContainText('run whoami');

  await page.keyboard.type('whoami');
  await expect(page.getByTestId('search-input')).toHaveValue('whoami');
  await expect(page.getByTestId('search-result')).toHaveCount(1);
  await expect(page.getByTestId('search-result')).toContainText('Nike 1.0');

  await replaceFocusedText(page, 'mock-user');
  await expect(page.getByTestId('search-input')).toHaveValue('mock-user');
  await expect(page.getByTestId('search-result')).toHaveCount(1);
  await expect(page.getByTestId('search-result')).toContainText('run whoami');

  await page.getByTestId('search-result').click();

  await expect(page.getByTestId('search-panel')).toHaveCount(0);
  await expect(page.getByTestId('top-bar-title')).toHaveText('run whoami');
  await expect(page.getByTestId('sidebar-item')).toHaveAttribute('aria-current', 'true');
});

test('mock harness starts a new chat from the sidebar action', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await page.getByLabel('Message').fill('run whoami');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('sidebar-item')).toContainText('run whoami');

  await page.getByTestId('new-chat-button').click();

  await expect(page.getByTestId('top-bar-title')).toHaveText('QuillCode');
  await expect(page.getByTestId('top-bar-subtitle')).toContainText('Not started');
  await expect(page.getByTestId('transcript-empty')).toBeVisible();
  await expect(page.getByTestId('sidebar-item')).toHaveAttribute('aria-current', 'false');
  await expect(page.getByTestId('sidebar-item')).toContainText('run whoami');
  await expect(page.getByLabel('Message')).toHaveValue('');
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

test('mock harness runs a command from the command palette', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await clickSidebarTool(page, 'command-palette-button');
  await expect(page.getByTestId('command-palette-panel')).toBeVisible();
  await expect(page.getByTestId('command-palette-input')).toBeFocused();
  await page.keyboard.type('>terminal');
  await expect(page.getByTestId('command-palette-input')).toHaveValue('>terminal');
  await page.locator('[data-testid="command-palette-result"][data-command-id="toggle-terminal"]').click();

  await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);
  await expect(page.getByTestId('terminal-pane')).toBeVisible();
});

test('mock harness command palette scopes actions and slash commands', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await clickSidebarTool(page, 'command-palette-button');
  await expect(page.getByTestId('command-palette-panel')).toBeVisible();
  await expect(page.getByText('> actions · / slash')).toBeVisible();

  await page.getByLabel('Search commands').fill('>shell');
  await expect(page.getByTestId('command-palette-scope')).toHaveText('Actions');
  await expect(page.getByTestId('command-palette-result').first()).toContainText('Terminal');

  await page.getByLabel('Search commands').fill('/mode');
  await expect(page.getByTestId('command-palette-scope')).toHaveText('Slash');
  await expect(page.getByTestId('command-palette-group')).toContainText('Slash Commands');
  await expect(page.getByTestId('command-palette-result').first()).toContainText('/mode auto|review|read-only');

  await page.keyboard.press('Enter');

  await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);
  await expect(page.getByLabel('Message')).toHaveValue('/mode ');
  await expect(page.getByLabel('Message')).toBeFocused();
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

test('mock harness ranks and navigates command palette with keyboard', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await clickSidebarTool(page, 'command-palette-button');
  await expect(page.getByTestId('command-palette-group').first()).toContainText('Thread');

  await page.getByLabel('Search commands').fill('>shell');
  await expect(page.locator('[data-testid="command-palette-result"][data-selected="true"]')).toContainText('Terminal');
  await page.keyboard.press('Enter');
  await expect(page.getByTestId('terminal-pane')).toBeVisible();

  await page.keyboard.press('Meta+Shift+P');
  await page.getByLabel('Search commands').fill('>shortcuts');
  await expect(page.locator('[data-testid="command-palette-result"][data-selected="true"]')).toContainText('Keyboard shortcuts');
  await page.keyboard.press('Enter');
  await expect(page.getByTestId('keyboard-shortcuts-panel')).toBeVisible();
  await expect(page.getByTestId('keyboard-shortcut-row').filter({ hasText: 'New chat' })).toContainText('Cmd+N');
  await expect(page.getByTestId('keyboard-shortcut-row').filter({ hasText: 'Search' })).toContainText('Cmd+K');
  await expect(page.getByTestId('keyboard-shortcut-row').filter({ hasText: 'Keyboard shortcuts' })).toContainText('Cmd+/');
  await page.getByTestId('keyboard-shortcuts-close').click();

  await page.keyboard.press('Meta+Shift+P');
  await page.getByLabel('Search commands').fill('>worktree');
  await expect(page.getByTestId('command-palette-group')).toHaveCount(1);
  await expect(page.getByTestId('command-palette-group')).toContainText('Git');
  await expect(page.locator('[data-testid="command-palette-result"][data-selected="true"]')).toContainText('List worktrees');

  await page.keyboard.press('ArrowDown');
  await expect(page.locator('[data-testid="command-palette-result"][data-selected="true"]')).toContainText('Create worktree');
  await page.keyboard.press('Enter');
  await expect(page.getByTestId('worktree-create-panel')).toBeVisible();
});

test('mock harness lists worktrees from the command palette', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await clickSidebarTool(page, 'command-palette-button');
  await page.getByLabel('Search commands').fill('>worktree');

  await expect(page.getByTestId('command-palette-result')).toHaveCount(3);
  await page.getByRole('button', { name: /List worktrees/ }).click();

  await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);
  await expect(page.getByTestId('tool-card-title')).toHaveText('host.git.worktree.list');
  await expect(page.getByTestId('tool-card-output')).toContainText('/mock/QuillCode-feature');
  await expect(page.getByTestId('message').last()).toContainText('worktree /mock/QuillCode');
});

test('mock harness prepares pull request creation from the command palette', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await clickSidebarTool(page, 'command-palette-button');
  await page.getByLabel('Search commands').fill('>create pull request');
  await expect(page.getByTestId('command-palette-result')).toHaveCount(1);
  await page.getByRole('button', { name: /Create pull request/ }).click();

  await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);
  await expect(page.getByLabel('Message')).toHaveValue('Create a pull request titled ');
});

test('mock harness views pull request details, checks, and diff from the command palette', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await clickSidebarTool(page, 'command-palette-button');
  await page.getByLabel('Search commands').fill('>view pull request');
  await expect(page.getByTestId('command-palette-result')).toHaveCount(1);
  await page.getByRole('button', { name: /View pull request/ }).click();

  await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);
  await expect(page.getByTestId('tool-card-title')).toHaveText('host.git.pr.view');
  await expect(page.getByTestId('message').last()).toContainText('Current pull request');
  await expect(page.getByTestId('tool-card-artifact-label')).toContainText('github.com/Lore-Hex/QuillCode/pull/42');

  await clickSidebarTool(page, 'command-palette-button');
  await page.getByLabel('Search commands').fill('>pr checks');
  await expect(page.getByTestId('command-palette-result')).toHaveCount(1);
  await page.getByRole('button', { name: /Pull request checks/ }).click();

  await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.pr.checks');
  await expect(page.getByTestId('message').last()).toContainText('QuillCode Tests');

  await clickSidebarTool(page, 'command-palette-button');
  await page.getByLabel('Search commands').fill('>pr diff');
  await expect(page.getByTestId('command-palette-result')).toHaveCount(1);
  await page.getByRole('button', { name: /Pull request diff/ }).click();

  await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.pr.diff');
  await expect(page.getByTestId('message').last()).toContainText('PR diff preview from GitHub CLI');
});

test('mock harness runs local environment action from the command palette', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await clickSidebarTool(page, 'command-palette-button');
  await page.getByLabel('Search commands').fill('>QUILL_ENV');
  await expect(page.getByTestId('command-palette-result')).toHaveCount(1);
  await page.getByLabel('Search commands').fill('>warm caches');
  await expect(page.getByTestId('command-palette-result')).toHaveCount(1);
  await expect(page.getByTestId('command-palette-result')).toContainText('Install dependencies and warm caches.');
  await page.getByRole('button', { name: /Run Bootstrap/ }).click();

  await expect(page.getByTestId('command-palette-panel')).toHaveCount(0);
  await expect(page.getByTestId('tool-card-title')).toHaveText('host.shell.run');
  await expect(page.getByTestId('tool-card-input')).toContainText(".quillcode/actions/bootstrap.sh");
  await expect(page.getByTestId('tool-card-input')).toContainText('QUILL_ENV');
  await expect(page.getByTestId('tool-card-input')).toContainText('<redacted>');
  await expect(page.getByTestId('tool-card-input')).not.toContainText('"dev"');
  await expect(page.getByTestId('message').last()).toContainText('Local environment action completed');
});

test('mock harness creates and removes worktrees from dialogs', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await clickSidebarTool(page, 'command-palette-button');
  await page.getByLabel('Search commands').fill('>create worktree');
  await page.getByRole('button', { name: /Create worktree/ }).click();
  await expect(page.getByTestId('worktree-create-panel')).toBeVisible();
  await expect(page.getByTestId('worktree-create-submit')).toBeDisabled();

  await page.getByLabel('Worktree folder').fill('quillcode-feature');
  await page.getByLabel('New branch').fill('feature/quillcode');
  await page.getByLabel('Base ref').fill('main');
  await expect(page.getByTestId('worktree-create-submit')).toBeEnabled();
  await page.getByTestId('worktree-create-submit').click();

  await expect(page.getByTestId('worktree-create-panel')).toHaveCount(0);
  await expect(page.getByTestId('project-item').first()).toContainText('quillcode-feature');
  await expect(page.getByTestId('project-item').first()).toContainText('/mock/quillcode-feature');
  await expect(page.getByTestId('top-bar-title')).toHaveText('Worktree: feature/quillcode');
  await expect(page.getByTestId('top-bar-subtitle')).toContainText('quillcode-feature - Auto - Nike 1.0');
  await expect(page.getByTestId('sidebar-item').first()).toContainText('Worktree: feature/quillcode');
  await expect(page.getByTestId('message').last()).toContainText('Opened worktree quillcode-feature at /mock/quillcode-feature.');

  await clickSidebarTool(page, 'command-palette-button');
  await page.getByLabel('Search commands').fill('>remove worktree');
  await page.getByRole('button', { name: /Remove worktree/ }).click();
  await expect(page.getByTestId('worktree-remove-panel')).toBeVisible();

  await page.getByLabel('Worktree folder').fill('quillcode-feature');
  await page.getByLabel('Force removal').check();
  await page.getByTestId('worktree-remove-submit').click();

  await expect(page.getByTestId('worktree-remove-panel')).toHaveCount(0);
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.worktree.remove');
  await expect(page.getByTestId('tool-card-input').last()).toContainText('"force": true');
  await expect(page.getByTestId('message').last()).toContainText('Removed worktree quillcode-feature.');
});

test('mock harness manages chat lifecycle from the sidebar', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');
  const clickThreadAction = async (row: Locator, name: string) => {
    await row.getByLabel(/^Actions for /).click();
    await row.getByRole('button', { name }).click();
  };

  await page.getByLabel('Message').fill('run whoami');
  await page.getByRole('button', { name: 'Send' }).click();
  await page.getByTestId('new-chat-button').click();
  await page.getByLabel('Message').fill('git diff');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('sidebar-thread-row')).toHaveCount(2);
  const whoamiRow = page.getByTestId('sidebar-thread-row').filter({ hasText: 'run whoami' });
  await clickThreadAction(whoamiRow, 'Pin');

  await expect(page.getByTestId('sidebar-section-title')).toContainText(['Pinned', 'Today']);
  await expect(page.getByTestId('sidebar-thread-row').first()).toContainText('run whoami');
  await expect(page.getByTestId('sidebar-thread-row').first()).toContainText('Nike 1.0');

  page.once('dialog', async dialog => {
    expect(dialog.message()).toContain('Rename chat');
    await dialog.accept('Renamed whoami');
  });
  await clickThreadAction(page.getByTestId('sidebar-thread-row').first(), 'Rename');
  await expect(page.getByTestId('sidebar-thread-row').first()).toContainText('Renamed whoami');

  await clickThreadAction(page.getByTestId('sidebar-thread-row').first(), 'Duplicate');
  await expect(page.getByTestId('top-bar-title')).toHaveText('Copy: Renamed whoami');
  const copiedRow = page.getByTestId('sidebar-thread-row').filter({ hasText: 'Copy: Renamed whoami' });
  await expect(copiedRow).toBeVisible();
  await expect(page.getByTestId('sidebar-thread-row')).toHaveCount(3);

  await clickThreadAction(copiedRow, 'Archive');

  await expect(page.getByTestId('sidebar-section-title')).toContainText(['Pinned', 'Today', 'Archived']);
  await expect(page.getByTestId('sidebar-thread-row')).toHaveCount(3);
  await expect(page.getByTestId('sidebar-thread-row').last()).toContainText('Copy: Renamed whoami');
  await expect(page.getByTestId('top-bar-title')).toHaveText('Renamed whoami');

  await clickThreadAction(page.getByTestId('sidebar-thread-row').last(), 'Unarchive');
  await expect(page.getByTestId('top-bar-title')).toHaveText('Copy: Renamed whoami');
  await expect(page.getByTestId('sidebar-section-title')).toContainText(['Pinned', 'Today']);

  await clickThreadAction(page.getByTestId('sidebar-thread-row').filter({ hasText: 'Copy: Renamed whoami' }), 'Delete');
  await expect(page.getByTestId('sidebar-thread-row')).toHaveCount(2);
  await expect(page.getByTestId('sidebar')).not.toContainText('Copy: Renamed whoami');
});

test('mock harness groups sidebar chats by recency bucket', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await page.evaluate(() => {
    const harness = window as unknown as {
      sendMessage: (value: string) => void;
      newChat: () => void;
      setSidebarItemUpdatedAt: (title: string, updatedAt: string) => void;
    };
    const localNoonDaysAgo = (days: number) => {
      const date = new Date();
      date.setHours(12, 0, 0, 0);
      date.setDate(date.getDate() - days);
      return date.toISOString();
    };

    harness.sendMessage('today chat');
    harness.setSidebarItemUpdatedAt('today chat', localNoonDaysAgo(0));
    harness.newChat();
    harness.sendMessage('yesterday chat');
    harness.setSidebarItemUpdatedAt('yesterday chat', localNoonDaysAgo(1));
    harness.newChat();
    harness.sendMessage('earlier week chat');
    harness.setSidebarItemUpdatedAt('earlier week chat', localNoonDaysAgo(3));
    harness.newChat();
    harness.sendMessage('older chat');
    harness.setSidebarItemUpdatedAt('older chat', localNoonDaysAgo(14));
  });

  await expect(page.getByTestId('sidebar-section-title')).toContainText([
    'Today',
    'Yesterday',
    'Previous 7 days',
    'Older'
  ]);
  const sidebarSection = (title: string) => page.getByTestId('sidebar-section').filter({
    has: page.getByTestId('sidebar-section-title').filter({ hasText: new RegExp(`^${title}$`) })
  });
  await expect(sidebarSection('Today').getByTestId('sidebar-thread-row')).toContainText('today chat');
  await expect(sidebarSection('Yesterday').getByTestId('sidebar-thread-row')).toContainText('yesterday chat');
  await expect(sidebarSection('Previous 7 days').getByTestId('sidebar-thread-row')).toContainText('earlier week chat');
  await expect(sidebarSection('Older').getByTestId('sidebar-thread-row')).toContainText('older chat');
});

test('mock harness bulk-selects chats from the sidebar', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  for (const prompt of ['run whoami', 'git diff', 'review tests']) {
    await page.getByLabel('Message').fill(prompt);
    await page.getByRole('button', { name: 'Send' }).click();
    await page.getByTestId('new-chat-button').click();
  }

  await expect(page.getByTestId('sidebar-thread-row')).toHaveCount(3);
  await page.getByTestId('sidebar-bulk-action').filter({ hasText: /^Select$/ }).click();
  await expect(page.getByTestId('sidebar-selection')).toHaveAttribute('data-active', 'true');

  await page.getByTestId('sidebar-thread-row').nth(0).getByTestId('sidebar-select-toggle').click();
  await page.getByTestId('sidebar-thread-row').nth(1).getByTestId('sidebar-select-toggle').click();
  await expect(page.getByTestId('sidebar-selection-label')).toHaveText('2 chats selected');

  await page.getByTestId('sidebar-bulk-action').filter({ hasText: /^Archive$/ }).click();
  await expect(page.getByTestId('sidebar-selection')).toHaveCount(0);
  const sidebarSection = (title: string) => page.getByTestId('sidebar-section').filter({
    has: page.getByTestId('sidebar-section-title').filter({ hasText: new RegExp(`^${title}$`) })
  });
  await expect(sidebarSection('Archived').getByTestId('sidebar-thread-row')).toHaveCount(2);
  await expect(sidebarSection('Today').getByTestId('sidebar-thread-row')).toHaveCount(1);

  await page.getByTestId('sidebar-bulk-action').filter({ hasText: /^Select$/ }).click();
  await page.getByTestId('sidebar-bulk-action').filter({ hasText: 'Select all' }).click();
  await expect(page.getByTestId('sidebar-selection-label')).toHaveText('3 chats selected');
  await page.getByTestId('sidebar-bulk-action').filter({ hasText: /^Delete$/ }).click();

  await expect(page.getByTestId('sidebar-thread-row')).toHaveCount(0);
  await expect(page.getByTestId('sidebar-title-row')).toHaveCount(0);
  await expect(page.getByTestId('sidebar-empty')).toHaveText('No chats yet');
});

test('mock harness manages projects from the sidebar', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await page.getByTestId('add-project-button').click();

  await expect(page.getByTestId('project-item')).toHaveCount(2);
  await expect(page.getByTestId('project-item').first()).toContainText('Example Project 2');
  await expect(page.getByTestId('project-item').first()).toContainText('/mock/example-2');
  await expect(page.getByTestId('project-item').first()).toHaveAttribute('aria-current', 'true');
  await expect(page.getByTestId('top-bar-subtitle')).toContainText('Example Project 2');

  await clickSidebarTool(page, 'terminal-button');
  await expect(page.getByTestId('terminal-cwd')).toHaveText('/mock/example-2');

  const activeProjectRow = page.getByTestId('project-row').first();
  page.once('dialog', async dialog => {
    expect(dialog.message()).toContain('Rename project');
    await dialog.accept('Renamed Project');
  });
  await clickProjectAction(activeProjectRow, 'Rename');
  await expect(page.getByTestId('project-item').first()).toContainText('Renamed Project');
  await expect(page.getByTestId('top-bar-subtitle')).toContainText('Renamed Project');

  await clickProjectAction(page.getByTestId('project-row').first(), 'Refresh context');
  await expect(page.getByTestId('message').last()).toContainText('Refreshed project context for Renamed Project.');

  await clickProjectAction(page.getByTestId('project-row').first(), 'New chat');
  await expect(page.getByTestId('top-bar-title')).toHaveText('New chat');
  await expect(page.getByTestId('sidebar-item').first()).toContainText('New chat');

  await clickProjectAction(page.getByTestId('project-row').first(), 'Remove from list');
  await expect(page.getByTestId('project-item')).toHaveCount(1);
  await expect(page.getByTestId('project-item').first()).toContainText('QuillCode');
});

test('mock harness adds an SSH remote project from command palette and slash command', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await clickSidebarTool(page, 'command-palette-button');
  await page.getByLabel('Search commands').fill('>ssh');
  await expect(page.getByTestId('command-palette-result')).toHaveCount(1);
  await expect(page.getByTestId('command-palette-result')).toContainText('Project: Add SSH Remote');
  await page.getByTestId('command-palette-result').click();
  await expect(page.getByLabel('Message')).toHaveValue('/ssh user@host:/absolute/path');

  await page.getByLabel('Message').fill('/ssh quill@feather.local:/srv/quill');
  await page.getByRole('button', { name: 'Send' }).click();

  const remoteProject = page.getByTestId('project-row').first();
  await expect(remoteProject.getByTestId('project-item')).toContainText('feather.local · quill');
  await expect(remoteProject.getByTestId('project-item')).toContainText('ssh://quill@feather.local/srv/quill');
  await expect(remoteProject.getByTestId('project-connection-kind')).toHaveText('SSH Remote');
  await expect(page.getByTestId('top-bar-subtitle')).toContainText('feather.local · quill');
  await expect(page.getByTestId('message').last()).toContainText('Added SSH Remote');

  await clickProjectAction(remoteProject, 'Refresh context');
  await expect(page.getByTestId('message').last()).toContainText('Refreshed project context for feather.local · quill.');

  await clickSidebarTool(page, 'terminal-button');
  await expect(page.getByTestId('terminal-pane')).toBeVisible();
  await expect(page.getByTestId('terminal-cwd')).toHaveText('ssh://quill@feather.local/srv/quill');
  await page.getByTestId('terminal-input').fill('pwd');
  await page.getByTestId('terminal-run').click();
  await expect(page.getByTestId('terminal-status')).toHaveText('Done · exit 0');
  await expect(page.getByTestId('terminal-stdout')).toHaveText('/srv/quill\n');
  await expect(page.getByTestId('terminal-entry')).toHaveAttribute('data-execution-context', 'ssh-remote');
  await expect(page.getByTestId('terminal-execution-context')).toHaveText('SSH Remote · feather.local');

  await page.getByLabel('Message').fill('whoami');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.shell.run');
  await expect(page.getByTestId('tool-card').last()).toHaveAttribute('data-execution-context', 'ssh-remote');
  await expect(page.getByTestId('tool-card-execution-context').last()).toHaveText('SSH Remote · feather.local');
  await expect(page.getByTestId('tool-card-output').last()).toContainText('quill');
  await expect(page.getByText('You are `quill` in this workspace.')).toBeVisible();

  await clickSidebarTool(page, 'command-palette-button');
  await page.getByLabel('Search commands').fill('>git status');
  await page.getByTestId('command-palette-result').filter({ hasText: 'Git status' }).click();
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.status');
  await expect(page.getByTestId('tool-card').last()).toHaveAttribute('data-execution-context', 'ssh-remote');
  await expect(page.getByTestId('tool-card-execution-context').last()).toHaveText('SSH Remote · feather.local');
  await expect(page.getByTestId('tool-card-output').last()).toContainText('ssh://quill@feather.local/srv/quill');

  await clickSidebarTool(page, 'command-palette-button');
  await page.getByLabel('Search commands').fill('>review diff');
  await page.getByTestId('command-palette-result').filter({ hasText: 'Review diff' }).click();
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.diff');
  await expect(page.getByTestId('tool-card').last()).toHaveAttribute('data-execution-context', 'ssh-remote');
  await expect(page.getByTestId('tool-card-execution-context').last()).toHaveText('SSH Remote · feather.local');
  await expect(page.getByTestId('review-pane')).toBeVisible();
  await expect(page.getByTestId('review-file')).toContainText('Sources/App.swift');

  await page.getByLabel('Message').fill('Can you write a file that says hello world');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.shell.run');
  await expect(page.getByTestId('tool-card-input').last()).toContainText('printf %s');
  await expect(page.getByText('Wrote `hello.txt` on feather.local · quill.')).toBeVisible();
});

test('mock harness handles slash mode locally', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await page.getByLabel('Message').fill('/mode review');
  await page.getByRole('button', { name: 'Send' }).click();

  await expect(page.getByTestId('mode-pill')).toHaveText('Review');
  await expect(page.getByTestId('mode-picker-button')).toContainText('Review');
  await expect(page.getByTestId('mode-picker-button')).toHaveAttribute('data-mode-tone', 'review');
  await expect(page.getByTestId('top-bar-subtitle')).toContainText('QuillCode - Review');
  await expect(page.getByText('Mode set to Review.')).toBeVisible();
  await expect(page.getByTestId('tool-card')).toHaveCount(0);
});

test('mock harness changes approval mode independently from model selection', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await expect(page.getByTestId('model-picker-button')).toHaveText('Nike 1.0');
  await expect(page.getByTestId('mode-pill')).toHaveText('Auto');

  await page.getByTestId('mode-picker-button').click();
  await expect(page.getByTestId('mode-pill')).toHaveText('Review');
  await expect(page.getByTestId('model-picker-button')).toHaveText('Nike 1.0');

  await page.getByTestId('mode-picker-button').click();
  await expect(page.getByTestId('mode-pill')).toHaveText('Read-only');
  await expect(page.getByTestId('mode-picker-button')).toHaveAttribute('data-mode-tone', 'read-only');
  await expect(page.getByTestId('model-picker-button')).not.toContainText('Read-only');
});

test('mock harness routes slash commands to workspace actions', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await page.getByLabel('Message').fill('/terminal');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('terminal-pane')).toBeVisible();
  await expect(page.getByText('Terminal opened.')).toBeVisible();

  await page.getByLabel('Message').fill('/browser');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('browser-pane')).toBeVisible();
  await expect(page.getByText('Browser opened.')).toBeVisible();

  await page.getByLabel('Message').fill('/worktrees');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.worktree.list');
  await expect(page.getByTestId('tool-card-output').last()).toContainText('/mock/QuillCode-feature');

  await page.getByLabel('Message').fill('/pr');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByLabel('Message')).toHaveValue('Create a pull request titled ');

  await page.getByLabel('Message').fill('/compact');
  await page.getByRole('button', { name: 'Send' }).click();
  await expect(page.getByTestId('top-bar-title')).toContainText('Compact:');
  await expect(page.getByTestId('message').first()).toContainText('Context compacted from');
});

test('mock harness suggests slash commands in the composer', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  const message = page.getByLabel('Message');
  await message.fill('/');
  await expect(page.getByTestId('slash-suggestions')).toBeVisible();
  await expect(page.getByTestId('slash-suggestion')).toHaveCount(6);
  await expect(page.getByTestId('slash-suggestion').first()).toContainText('/help');
  await expect(page.locator('[data-testid="slash-suggestion"][data-selected="true"]')).toContainText('/help');

  await page.keyboard.press('ArrowDown');
  await expect(page.locator('[data-testid="slash-suggestion"][data-selected="true"]')).toContainText('/status');

  await message.fill('/workt');
  await expect(page.getByTestId('slash-suggestion').first()).toContainText('/worktrees');
  await page.keyboard.press('Enter');
  await expect(message).toHaveValue('/worktrees');
  await expect(message).toBeFocused();

  await page.keyboard.press('Enter');
  await expect(page.getByTestId('slash-suggestions')).toHaveCount(0);
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.git.worktree.list');

  await message.fill('/project r');
  await page.keyboard.press('ArrowDown');
  await expect(page.locator('[data-testid="slash-suggestion"][data-selected="true"]')).toContainText('/project rename name');
  await page.keyboard.press('Tab');
  await expect(message).toHaveValue('/project rename ');

  await message.fill('/fol');
  await expect(page.getByTestId('slash-suggestion').first()).toContainText('/follow-up when');
  await page.keyboard.press('Enter');
  await expect(message).toHaveValue('/follow-up in ');

  await message.fill('/workspace-c');
  await expect(page.getByTestId('slash-suggestion').first()).toContainText('/workspace-check when');
  await page.keyboard.press('Enter');
  await expect(message).toHaveValue('/workspace-check in ');

  await message.fill('/workt');
  await page.getByTestId('slash-suggestion').first().click();
  await expect(message).toHaveValue('/worktrees');
  await expect(message).toBeFocused();
});

test('mock harness searches and selects models from the composer', async ({ page }) => {
  await page.goto('file://' + process.cwd() + '/../harness/index.html');

  await page.getByTestId('model-picker-button').click();
  await expect(page.getByTestId('model-browser')).toBeVisible();
  await expect(page.getByTestId('model-option-summary').first()).toContainText('Fast everyday agent');
  await expect(page.getByTestId('model-detail-button').first()).toHaveAttribute('aria-expanded', 'true');
  await expect(page.getByTestId('model-capability')).toContainText('Nike 1.0 is the fast default');
  await expect(page.getByTestId('model-metadata-row').filter({ hasText: 'trustedrouter/fast' })).toBeVisible();
  await expect(page.getByTestId('model-metadata-row').filter({ hasText: 'Current, Default, Recommended' })).toBeVisible();
  await expect(page.getByTestId('model-option')).toHaveCount(5);

  await page.getByTestId('model-detail-button').nth(1).click();
  await expect(page.getByTestId('model-detail-button').nth(1)).toHaveAttribute('aria-expanded', 'true');
  await expect(page.getByTestId('model-capability')).toContainText('Synth is the balanced model');
  await expect(page.getByTestId('model-metadata-row').filter({ hasText: 'tr/synth' })).toBeVisible();

  await page.getByTestId('model-detail-button').nth(2).click();
  await expect(page.getByTestId('model-detail-button').nth(2)).toHaveAttribute('aria-expanded', 'true');
  await expect(page.getByTestId('model-capability')).toContainText('Synth Code is the code-focused model');
  await expect(page.getByTestId('model-metadata-row').filter({ hasText: 'tr/synth-code' })).toBeVisible();

  await page.getByTestId('model-search').fill('default model');
  await expect(page.getByTestId('model-option')).toHaveCount(1);
  await expect(page.getByTestId('model-option')).toContainText('Nike 1.0');
  await page.getByTestId('model-search').fill('');

  await page.getByTestId('model-favorite-button').nth(1).click();
  await expect(page.getByTestId('model-browser')).toBeVisible();
  await expect(page.getByTestId('model-category').first()).toContainText('Favorites');
  await expect(page.getByTestId('model-option')).toHaveCount(6);
  await expect(page.getByTestId('model-favorite-button').first()).toHaveAttribute('aria-label', 'Remove favorite model');

  await page.getByTestId('model-search').fill('favorite');
  await expect(page.getByTestId('model-category')).toHaveCount(1);
  await expect(page.getByTestId('model-category')).toContainText('Favorites');
  await expect(page.getByTestId('model-option')).toHaveCount(1);

  await page.getByTestId('model-search').fill('moon k2');
  await expect(page.getByTestId('model-option')).toHaveCount(1);
  await expect(page.getByTestId('model-option')).toContainText('moonshotai/Kimi K2.6');

  await page.getByTestId('model-option').click();
  await expect(page.getByTestId('model-picker-button')).toHaveText('moonshotai/Kimi K2.6');
  await expect(page.getByTestId('mode-pill')).toHaveText('Auto');
  await expect(page.getByTestId('model-browser')).toHaveCount(0);

  await page.getByTestId('model-picker-button').click();
  await page.getByTestId('model-search').fill('not-a-model');
  await expect(page.getByTestId('model-empty')).toBeVisible();
});
