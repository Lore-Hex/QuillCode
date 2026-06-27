import { expect, type Locator, type Page } from '@playwright/test';

export const MINIMUM_HIT_TARGET = 44;

const INTERACTIVE_SELECTOR = [
  'button',
  'summary',
  'a[href]',
  '[role="button"]',
  '[role="checkbox"]',
  '[role="menuitem"]',
  '[role="option"]',
  '[role="switch"]',
  '[role="tab"]',
  '[tabindex]:not([tabindex="-1"])',
  '[contenteditable="true"]',
  'input:not([type="hidden"])',
  'select',
  'textarea'
].join(',');

const ACTIVE_LAYER_SELECTOR = [
  '[data-testid="model-browser"]',
  '[data-testid="settings-panel"]',
  '[data-testid="search-panel"]',
  '[data-testid="command-palette-panel"]',
  '[data-testid="keyboard-shortcuts-panel"]',
  '[data-testid="find-bar"]',
  '[data-testid="worktree-create-panel"]',
  '[data-testid="worktree-open-panel"]',
  '[data-testid="worktree-remove-panel"]',
  '[data-testid="worktree-prune-panel"]',
  '.topbar-overflow-popover',
  '.sidebar-tools-popover',
  '.sidebar-thread-menu-popover'
].join(',');

export type ElementRect = {
  height: number;
  left: number;
  right: number;
  top: number;
  width: number;
};

type TargetAuditIssue = {
  className: string;
  height: number;
  label: string;
  reason: string;
  tag: string;
  testid: string | null;
  text: string;
  width: number;
};

type TargetOverlapIssue = {
  a: string;
  b: string;
  overlapHeight: number;
  overlapWidth: number;
};

async function targetAuditIssues(page: Page): Promise<TargetAuditIssue[]> {
  return page.evaluate(({ activeLayerSelector, minimumHitTarget, selector }) => {
    function isVisible(element: Element, rect: DOMRect) {
      const style = window.getComputedStyle(element);
      const closedDetails = element.closest('details:not([open])');
      if (closedDetails && element.tagName.toLowerCase() !== 'summary') return false;
      return rect.width > 0
        && rect.height > 0
        && style.display !== 'none'
        && style.visibility !== 'hidden'
        && style.pointerEvents !== 'none'
        && !element.closest('[hidden],[aria-hidden="true"]');
    }

    function activeInteractionLayer() {
      const layers = [...document.querySelectorAll(activeLayerSelector)].filter((element) => {
        const rect = element.getBoundingClientRect();
        return isVisible(element, rect);
      });
      return layers.at(-1) || null;
    }

    function isInActiveInteractionLayer(element: Element) {
      const layer = activeInteractionLayer();
      return !layer || layer === element || layer.contains(element);
    }

    function centerIsInViewport(rect: DOMRect) {
      const centerX = rect.left + rect.width / 2;
      const centerY = rect.top + rect.height / 2;
      return centerX >= 0
        && centerY >= 0
        && centerX <= document.documentElement.clientWidth
        && centerY <= document.documentElement.clientHeight;
    }

    function centerIsInsideClippingAncestors(element: Element, rect: DOMRect) {
      const centerX = rect.left + rect.width / 2;
      const centerY = rect.top + rect.height / 2;
      let ancestor = element.parentElement;
      while (ancestor) {
        const style = window.getComputedStyle(ancestor);
        const clips = ['auto', 'scroll', 'hidden', 'clip'].some(value => (
          style.overflow === value || style.overflowX === value || style.overflowY === value
        ));
        if (clips) {
          const ancestorRect = ancestor.getBoundingClientRect();
          if (
            centerX < ancestorRect.left
            || centerX > ancestorRect.right
            || centerY < ancestorRect.top
            || centerY > ancestorRect.bottom
          ) {
            return false;
          }
        }
        ancestor = ancestor.parentElement;
      }
      return true;
    }

    function isTopMostAtCenter(element: Element, rect: DOMRect) {
      if (!centerIsInViewport(rect) || !centerIsInsideClippingAncestors(element, rect)) return true;
      const centerX = rect.left + rect.width / 2;
      const centerY = rect.top + rect.height / 2;
      const topElement = document.elementFromPoint(centerX, centerY);
      return topElement === element || Boolean(topElement && element.contains(topElement));
    }

    function auditReason(element: Element, rect: DOMRect) {
      const reasons = [];
      if (Math.round(rect.width) < minimumHitTarget || Math.round(rect.height) < minimumHitTarget) {
        reasons.push('too_small');
      }
      if (!isTopMostAtCenter(element, rect)) {
        reasons.push('center_blocked_or_clipped');
      }
      return reasons.join(',');
    }

    return [...document.querySelectorAll(selector)]
      .map((element) => {
        const rect = element.getBoundingClientRect();
        return { element, rect };
      })
      .filter(({ element, rect }) => isVisible(element, rect) && isInActiveInteractionLayer(element))
      .map(({ element, rect }) => ({
        element,
        reason: auditReason(element, rect),
        rect
      }))
      .filter(({ reason }) => reason.length > 0)
      .map(({ element, reason, rect }) => ({
        className: String((element as HTMLElement).className || ''),
        height: Math.round(rect.height),
        label: element.getAttribute('aria-label') || '',
        reason,
        tag: element.tagName.toLowerCase(),
        testid: element.getAttribute('data-testid'),
        text: (element.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 80),
        width: Math.round(rect.width)
      }));
  }, {
    activeLayerSelector: ACTIVE_LAYER_SELECTOR,
    minimumHitTarget: MINIMUM_HIT_TARGET,
    selector: INTERACTIVE_SELECTOR
  });
}

export async function expectAllVisibleInteractiveTargets(page: Page, label: string) {
  const issues = await targetAuditIssues(page);
  expect(issues, `${label} should keep every visible interactive target at least ${MINIMUM_HIT_TARGET}px`).toEqual([]);
}

async function targetOverlapIssues(page: Page): Promise<TargetOverlapIssue[]> {
  return page.evaluate(({ activeLayerSelector, selector }) => {
    function isVisible(element: Element, rect: DOMRect) {
      const style = window.getComputedStyle(element);
      const closedDetails = element.closest('details:not([open])');
      if (closedDetails && element.tagName.toLowerCase() !== 'summary') return false;
      return rect.width > 0
        && rect.height > 0
        && style.display !== 'none'
        && style.visibility !== 'hidden'
        && style.pointerEvents !== 'none'
        && !element.closest('[hidden],[aria-hidden="true"]');
    }

    function activeInteractionLayer() {
      const layers = [...document.querySelectorAll(activeLayerSelector)].filter((element) => {
        const rect = element.getBoundingClientRect();
        return isVisible(element, rect);
      });
      return layers.at(-1) || null;
    }

    function isInActiveInteractionLayer(element: Element) {
      const layer = activeInteractionLayer();
      return !layer || layer === element || layer.contains(element);
    }

    function centerIsInViewport(rect: DOMRect) {
      const centerX = rect.left + rect.width / 2;
      const centerY = rect.top + rect.height / 2;
      return centerX >= 0
        && centerY >= 0
        && centerX <= document.documentElement.clientWidth
        && centerY <= document.documentElement.clientHeight;
    }

    function centerIsInsideClippingAncestors(element: Element, rect: DOMRect) {
      const centerX = rect.left + rect.width / 2;
      const centerY = rect.top + rect.height / 2;
      let ancestor = element.parentElement;
      while (ancestor) {
        const style = window.getComputedStyle(ancestor);
        const clips = ['auto', 'scroll', 'hidden', 'clip'].some(value => (
          style.overflow === value || style.overflowX === value || style.overflowY === value
        ));
        if (clips) {
          const ancestorRect = ancestor.getBoundingClientRect();
          if (
            centerX < ancestorRect.left
            || centerX > ancestorRect.right
            || centerY < ancestorRect.top
            || centerY > ancestorRect.bottom
          ) {
            return false;
          }
        }
        ancestor = ancestor.parentElement;
      }
      return true;
    }

    function isTopMostAtCenter(element: Element, rect: DOMRect) {
      if (!centerIsInViewport(rect) || !centerIsInsideClippingAncestors(element, rect)) return false;
      const centerX = rect.left + rect.width / 2;
      const centerY = rect.top + rect.height / 2;
      const topElement = document.elementFromPoint(centerX, centerY);
      return topElement === element || Boolean(topElement && element.contains(topElement));
    }

    function labelFor(element: Element) {
      const id = element.getAttribute('data-testid');
      const aria = element.getAttribute('aria-label');
      const text = (element.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 48);
      return [element.tagName.toLowerCase(), id, aria, text].filter(Boolean).join(':');
    }

    function interactionLayer(element: Element) {
      const layer = element.closest([
        '[data-testid="model-browser"]',
        '[data-testid="settings-panel"]',
        '[data-testid="search-panel"]',
        '[data-testid="command-palette-panel"]',
        '[data-testid="keyboard-shortcuts-panel"]',
        '[data-testid="find-bar"]',
        '.sidebar-tools-popover',
        '.sidebar-thread-menu-popover'
      ].join(','));
      if (!layer) return 'workspace';
      return layer.getAttribute('data-testid') || layer.className || layer.tagName.toLowerCase();
    }

    const targets = [...document.querySelectorAll(selector)]
      .map((element) => ({
        element,
        layer: interactionLayer(element),
        rect: element.getBoundingClientRect()
      }))
      .filter(({ element, rect }) => (
        isVisible(element, rect)
          && isInActiveInteractionLayer(element)
          && isTopMostAtCenter(element, rect)
      ));
    const issues: TargetOverlapIssue[] = [];

    for (let i = 0; i < targets.length; i += 1) {
      for (let j = i + 1; j < targets.length; j += 1) {
        const first = targets[i];
        const second = targets[j];
        if (first.layer !== second.layer) continue;
        if (first.element.contains(second.element) || second.element.contains(first.element)) continue;

        const overlapWidth = Math.min(first.rect.right, second.rect.right) - Math.max(first.rect.left, second.rect.left);
        const overlapHeight = Math.min(first.rect.bottom, second.rect.bottom) - Math.max(first.rect.top, second.rect.top);
        if (overlapWidth > 1 && overlapHeight > 1) {
          issues.push({
            a: labelFor(first.element),
            b: labelFor(second.element),
            overlapHeight: Math.round(overlapHeight),
            overlapWidth: Math.round(overlapWidth)
          });
        }
      }
    }
    return issues;
  }, {
    activeLayerSelector: ACTIVE_LAYER_SELECTOR,
    selector: INTERACTIVE_SELECTOR
  });
}

export async function expectNoOverlappingInteractiveTargets(page: Page, label: string) {
  const issues = await targetOverlapIssues(page);
  expect(issues, `${label} should not have overlapping peer interactive targets`).toEqual([]);
}

export async function expectHitTarget(locator: Locator, label: string) {
  const target = locator.first();
  await expect(target, `${label} should be visible`).toBeVisible();
  await target.scrollIntoViewIfNeeded();
  const box = await target.boundingBox();
  expect(box, `${label} should have layout bounds`).not.toBeNull();
  if (!box) throw new Error(`${label} should have layout bounds`);
  expect(Math.round(box.width), `${label} width`).toBeGreaterThanOrEqual(MINIMUM_HIT_TARGET);
  expect(Math.round(box.height), `${label} height`).toBeGreaterThanOrEqual(MINIMUM_HIT_TARGET);
}

export function harnessURL(): string {
  return 'file://' + process.cwd() + '/../harness/index.html';
}

export async function computedStyleProperties(page: Page, selector: string, properties: string[]) {
  return page.locator(selector).first().evaluate((element, styleProperties) => {
    const style = getComputedStyle(element);
    return Object.fromEntries(
      styleProperties.map(property => [property, style.getPropertyValue(property)])
    );
  }, properties);
}

export async function elementRect(page: Page, selector: string): Promise<ElementRect> {
  return page.locator(selector).first().evaluate(element => {
    const rect = element.getBoundingClientRect();
    return {
      height: rect.height,
      left: rect.left,
      right: rect.right,
      top: rect.top,
      width: rect.width
    };
  });
}

export async function openSidebarTools(page: Page) {
  await page.getByTestId('sidebar-tools-button').click();
  await expect(page.getByTestId('sidebar-tools-menu')).toHaveAttribute('open', '');
}

export async function clickSidebarTool(page: Page, testID: string) {
  await openSidebarTools(page);
  await page.getByTestId(testID).click();
}

export function commandPaletteResult(page: Page, commandID: string) {
  return page.locator(`[data-testid="command-palette-result"][data-command-id="${commandID}"]`);
}

export async function fillCommandPalette(page: Page, query: string) {
  const input = page.getByTestId('command-palette-input');
  await expect(input).toBeVisible();
  await input.evaluate((element, nextQuery) => {
    if (!(element instanceof HTMLInputElement)) return;
    element.value = nextQuery;
    element.dispatchEvent(new InputEvent('input', {
      bubbles: true,
      data: nextQuery,
      inputType: 'insertReplacementText'
    }));
  }, query);
  await expect(input).toHaveValue(query);
}

export async function clickCommandPaletteCommand(page: Page, query: string, commandID: string) {
  await fillCommandPalette(page, query);
  const result = commandPaletteResult(page, commandID);
  await expect(result).toBeVisible();
  await result.click();
}

export async function openTopBarOverflow(page: Page) {
  await page.getByTestId('top-bar-overflow-button').click();
  await expect(page.getByTestId('top-bar-overflow-menu')).toHaveAttribute('open', '');
}

export async function openSettings(page: Page) {
  await openTopBarOverflow(page);
  await page.getByTestId('top-bar-overflow-settings').click();
}
