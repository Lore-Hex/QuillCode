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

type InteractionAuditReport = {
  overlapIssues: TargetOverlapIssue[];
  targetIssues: TargetAuditIssue[];
};

async function interactionAuditReport(page: Page): Promise<InteractionAuditReport> {
  return page.evaluate(({ activeLayerSelector, minimumHitTarget, selector }) => {
    type VisibleTarget = {
      clipped: VisibleRectResult;
      element: Element;
      rect: DOMRect;
    };

    type OverlapTarget = VisibleTarget & {
      layer: string;
      visibleRect: RectLike;
    };

    type RectLike = {
      bottom: number;
      height: number;
      left: number;
      right: number;
      top: number;
      width: number;
    };

    type VisibleRectResult = {
      hardClipped: boolean;
      rect: RectLike;
      scrollClipped: boolean;
    };

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

    const activeInteractionLayer = (() => {
      const layers = [...document.querySelectorAll(activeLayerSelector)].filter((element) => {
        const rect = element.getBoundingClientRect();
        return isVisible(element, rect);
      });
      return layers.at(-1) || null;
    })();

    function isInActiveInteractionLayer(element: Element) {
      return !activeInteractionLayer
        || activeInteractionLayer === element
        || activeInteractionLayer.contains(element);
    }

    function rectFromEdges(left: number, top: number, right: number, bottom: number): RectLike {
      return {
        bottom,
        height: Math.max(0, bottom - top),
        left,
        right,
        top,
        width: Math.max(0, right - left)
      };
    }

    function visibleRect(element: Element, rect: DOMRect): VisibleRectResult {
      let visible = rectFromEdges(
        Math.max(0, rect.left),
        Math.max(0, rect.top),
        Math.min(document.documentElement.clientWidth, rect.right),
        Math.min(document.documentElement.clientHeight, rect.bottom)
      );
      let scrollClipped = visible.width < rect.width || visible.height < rect.height;
      let hardClipped = false;
      let ancestor = element.parentElement;
      while (ancestor) {
        const style = window.getComputedStyle(ancestor);
        const overflowValues = [style.overflow, style.overflowX, style.overflowY];
        const clips = ['auto', 'scroll', 'hidden', 'clip'].some(value => overflowValues.includes(value));
        if (clips) {
          const ancestorRect = ancestor.getBoundingClientRect();
          const before = visible;
          visible = rectFromEdges(
            Math.max(visible.left, ancestorRect.left),
            Math.max(visible.top, ancestorRect.top),
            Math.min(visible.right, ancestorRect.right),
            Math.min(visible.bottom, ancestorRect.bottom)
          );
          if (
            (visible.width < before.width || visible.height < before.height)
            && ['auto', 'scroll'].some(value => overflowValues.includes(value))
          ) {
            scrollClipped = true;
          }
          if (
            (visible.width < before.width || visible.height < before.height)
            && ['hidden', 'clip'].some(value => overflowValues.includes(value))
          ) {
            hardClipped = true;
          }
        }
        ancestor = ancestor.parentElement;
      }
      return { hardClipped, rect: visible, scrollClipped };
    }

    function isPointOwnedBy(element: Element, x: number, y: number) {
      const topElement = document.elementFromPoint(x, y);
      return topElement === element || Boolean(topElement && element.contains(topElement));
    }

    function auditSamplePoints(rect: RectLike) {
      if (rect.width <= 0 || rect.height <= 0) return [];
      const insetX = Math.min(10, rect.width / 4);
      const insetY = Math.min(10, rect.height / 4);
      return [
        [rect.left + rect.width / 2, rect.top + rect.height / 2],
        [rect.left + insetX, rect.top + insetY],
        [rect.right - insetX, rect.top + insetY],
        [rect.left + insetX, rect.bottom - insetY],
        [rect.right - insetX, rect.bottom - insetY]
      ].filter(([x, y]) => (
        x >= 0
          && y >= 0
          && x <= document.documentElement.clientWidth
          && y <= document.documentElement.clientHeight
      ));
    }

    function isTopMostAtCenter(element: Element, rect: RectLike) {
      const points = auditSamplePoints(rect);
      const center = points[0];
      return Boolean(center && isPointOwnedBy(element, center[0], center[1]));
    }

    function hasReliableClickableInterior(element: Element, rect: RectLike) {
      const points = auditSamplePoints(rect);
      if (!points.length) return false;
      return points.every(([x, y]) => isPointOwnedBy(element, x, y));
    }

    function auditReason(element: Element, rect: DOMRect, clipped: VisibleRectResult) {
      const reasons = [];
      if (Math.round(rect.width) < minimumHitTarget || Math.round(rect.height) < minimumHitTarget) {
        reasons.push('too_small');
      }
      if (
        (clipped.hardClipped || !clipped.scrollClipped)
        && (Math.round(clipped.rect.width) < minimumHitTarget || Math.round(clipped.rect.height) < minimumHitTarget)
      ) {
        reasons.push('visible_area_too_small_or_clipped');
      }
      if (!isTopMostAtCenter(element, clipped.rect)) {
        reasons.push('center_blocked_or_clipped');
      }
      if (!hasReliableClickableInterior(element, clipped.rect)) {
        reasons.push('interior_click_area_blocked');
      }
      return reasons.join(',');
    }

    function isScrollBoundarySliver(clipped: VisibleRectResult) {
      return clipped.scrollClipped
        && !clipped.hardClipped
        && (
          Math.round(clipped.rect.width) < minimumHitTarget
          || Math.round(clipped.rect.height) < minimumHitTarget
        );
    }

    function associatedLabel(element: Element) {
      if (!(element instanceof HTMLInputElement)) return null;
      if (!['checkbox', 'radio'].includes(element.type)) return null;
      if (element.closest('label')) return element.closest('label');
      if (!element.id) return null;
      return document.querySelector(`label[for="${CSS.escape(element.id)}"]`);
    }

    function hasAuditedLabelHitTarget(element: Element) {
      const label = associatedLabel(element);
      if (!label) return false;
      const rect = label.getBoundingClientRect();
      const clipped = visibleRect(label, rect);
      return isVisible(label, rect)
        && Math.round(rect.width) >= minimumHitTarget
        && Math.round(rect.height) >= minimumHitTarget
        && Math.round(clipped.rect.width) >= minimumHitTarget
        && Math.round(clipped.rect.height) >= minimumHitTarget
        && hasReliableClickableInterior(label, clipped.rect);
    }

    function labelFor(element: Element) {
      const id = element.getAttribute('data-testid');
      const aria = element.getAttribute('aria-label');
      const text = (element.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 48);
      return [element.tagName.toLowerCase(), id, aria, text].filter(Boolean).join(':');
    }

    function interactionLayer(element: Element) {
      const layer = element.closest(activeLayerSelector);
      if (!layer) return 'workspace';
      return layer.getAttribute('data-testid')
        || String((layer as HTMLElement).className || '')
        || layer.tagName.toLowerCase();
    }

    const visibleTargets: VisibleTarget[] = [...document.querySelectorAll(selector)]
      .map((element) => {
        const rect = element.getBoundingClientRect();
        const clipped = visibleRect(element, rect);
        return { clipped, element, rect };
      })
      .filter(({ clipped, element, rect }) => (
        isVisible(element, rect)
          && clipped.rect.width > 0
          && clipped.rect.height > 0
          && !isScrollBoundarySliver(clipped)
          && isInActiveInteractionLayer(element)
      ));

    const targetIssues: TargetAuditIssue[] = visibleTargets
      .map(({ clipped, element, rect }) => ({
        clipped,
        element,
        reason: hasAuditedLabelHitTarget(element) ? '' : auditReason(element, rect, clipped),
        rect
      }))
      .filter(({ reason }) => reason.length > 0)
      .map(({ clipped, element, reason }) => ({
        className: String((element as HTMLElement).className || ''),
        height: Math.round(clipped.rect.height),
        label: element.getAttribute('aria-label') || '',
        reason,
        tag: element.tagName.toLowerCase(),
        testid: element.getAttribute('data-testid'),
        text: (element.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 80),
        width: Math.round(clipped.rect.width)
      }));

    const overlapTargets: OverlapTarget[] = visibleTargets
      .map(({ clipped, element, rect }) => ({
        clipped,
        element,
        layer: interactionLayer(element),
        rect,
        visibleRect: clipped.rect
      }))
      .filter(({ element, visibleRect }) => (
        isTopMostAtCenter(element, visibleRect)
      ));
    const overlapIssues: TargetOverlapIssue[] = [];

    for (let i = 0; i < overlapTargets.length; i += 1) {
      for (let j = i + 1; j < overlapTargets.length; j += 1) {
        const first = overlapTargets[i];
        const second = overlapTargets[j];
        if (first.layer !== second.layer) continue;
        if (first.element.contains(second.element) || second.element.contains(first.element)) continue;

        const overlapWidth = Math.min(first.visibleRect.right, second.visibleRect.right) - Math.max(first.visibleRect.left, second.visibleRect.left);
        const overlapHeight = Math.min(first.visibleRect.bottom, second.visibleRect.bottom) - Math.max(first.visibleRect.top, second.visibleRect.top);
        if (overlapWidth > 1 && overlapHeight > 1) {
          overlapIssues.push({
            a: labelFor(first.element),
            b: labelFor(second.element),
            overlapHeight: Math.round(overlapHeight),
            overlapWidth: Math.round(overlapWidth)
          });
        }
      }
    }

    return { overlapIssues, targetIssues };
  }, {
    activeLayerSelector: ACTIVE_LAYER_SELECTOR,
    minimumHitTarget: MINIMUM_HIT_TARGET,
    selector: INTERACTIVE_SELECTOR
  });
}

export async function expectAllVisibleInteractiveTargets(page: Page, label: string) {
  const { targetIssues } = await interactionAuditReport(page);
  expect(targetIssues, `${label} should keep every visible interactive target at least ${MINIMUM_HIT_TARGET}px`).toEqual([]);
}

export async function expectNoOverlappingInteractiveTargets(page: Page, label: string) {
  const { overlapIssues } = await interactionAuditReport(page);
  expect(overlapIssues, `${label} should not have overlapping peer interactive targets`).toEqual([]);
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
