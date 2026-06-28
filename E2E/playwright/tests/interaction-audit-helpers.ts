import { expect, type Locator, type Page } from '@playwright/test';

export const MINIMUM_HIT_TARGET = 44;
export const TARGET_SAMPLE_FRACTIONS = [0.2, 0.5, 0.8];
export const SHARED_HIT_TARGET_CLASSES = [
  'hit-target-owned',
  'interactive-hit-target',
  'hit-target-icon',
  'hit-target-text',
  'hit-target-text-entry',
  'hit-target-row',
  'hit-target-capsule',
  'hit-target-form-action'
];

const EXPECTED_KIND_BY_CLASS: Record<string, string> = {
  'hit-target-owned': 'owned',
  'interactive-hit-target': 'link',
  'hit-target-icon': 'icon',
  'hit-target-text': 'text',
  'hit-target-text-entry': 'text-entry',
  'hit-target-row': 'row',
  'hit-target-capsule': 'capsule',
  'hit-target-form-action': 'form-action'
};

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
  'label',
  'select',
  'textarea'
].join(',');

const ACTIVE_LAYER_SELECTOR = [
  'dialog[open]',
  '[role="dialog"]',
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

type TargetNestedIssue = {
  child: string;
  parent: string;
};

type InteractionAuditReport = {
  nestedIssues: TargetNestedIssue[];
  overlapIssues: TargetOverlapIssue[];
  targetIssues: TargetAuditIssue[];
};

export type CriticalTargetProbe = {
  expectedClass?: string;
  label: string;
  locator: Locator;
};

export async function interactionAuditReport(page: Page): Promise<InteractionAuditReport> {
  return page.evaluate(({ activeLayerSelector, minimumHitTarget, selector, sharedHitTargetClasses, targetSampleFractions }) => {
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

    function associatedLabelControl(element: Element) {
      if (!(element instanceof HTMLLabelElement)) return null;
      if (element.control) return element.control;
      if (!element.htmlFor) return null;
      return document.getElementById(element.htmlFor);
    }

    function isLabelHitTargetClass(element: Element) {
      return hasSharedHitTargetClass(element);
    }

    function hasSharedHitTargetClass(element: Element) {
      return sharedHitTargetClasses.some(className => element.classList.contains(className));
    }

    function isAuditableInteractiveElement(element: Element) {
      if (!(element instanceof HTMLLabelElement)) return true;
      const control = associatedLabelControl(element);
      if (control?.matches(':disabled,[aria-disabled="true"]')) return false;
      if (control instanceof HTMLInputElement && ['checkbox', 'radio'].includes(control.type)) {
        return true;
      }
      return isLabelHitTargetClass(element);
    }

    function isSemanticallyDisabled(element: Element) {
      const labelledControl = associatedLabelControl(element);
      if (labelledControl?.matches(':disabled,[aria-disabled="true"]')) return true;
      return element.matches(':disabled,[aria-disabled="true"]');
    }

    function isTextEntryLikeElement(element: Element) {
      if (element instanceof HTMLTextAreaElement || element instanceof HTMLSelectElement) return true;
      if (!(element instanceof HTMLInputElement)) return false;
      return ![
        'button',
        'checkbox',
        'color',
        'file',
        'image',
        'radio',
        'range',
        'reset',
        'submit'
      ].includes((element.type || 'text').toLowerCase());
    }

    function requiresPointerAffordance(element: Element) {
      if (isSemanticallyDisabled(element) || isTextEntryLikeElement(element)) return false;
      if (element instanceof HTMLLabelElement) return isAuditableInteractiveElement(element);
      if (element instanceof HTMLInputElement) return true;
      return true;
    }

    function isVisible(element: Element, rect: DOMRect) {
      const style = window.getComputedStyle(element);
      const closedDetails = element.closest('details:not([open])');
      if (closedDetails && element.tagName.toLowerCase() !== 'summary') return false;
      return rect.width > 0
        && rect.height > 0
        && style.display !== 'none'
        && style.visibility !== 'hidden'
        && !element.closest('.visually-hidden,.composer-sr-only')
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

    function targetInteriorSamplePoints(rect: RectLike) {
      if (rect.width <= 0 || rect.height <= 0) return [];
      return targetSampleFractions.flatMap((yFraction) => (
        targetSampleFractions.map((xFraction) => [
          rect.left + rect.width * xFraction,
          rect.top + rect.height * yFraction
        ])
      )).filter(([x, y]) => (
        x >= 0
          && y >= 0
          && x <= document.documentElement.clientWidth
          && y <= document.documentElement.clientHeight
      ));
    }

    function isTopMostAtCenter(element: Element, rect: RectLike) {
      const x = rect.left + rect.width / 2;
      const y = rect.top + rect.height / 2;
      if (
        x < 0
        || y < 0
        || x > document.documentElement.clientWidth
        || y > document.documentElement.clientHeight
      ) {
        return false;
      }
      return isPointOwnedBy(element, x, y);
    }

    function hasReliableClickableInterior(element: Element, rect: RectLike) {
      const points = targetInteriorSamplePoints(rect);
      if (!points.length) return false;
      return points.every(([x, y]) => isPointOwnedBy(element, x, y));
    }

    function labelledByText(element: Element) {
      const labelledBy = element.getAttribute('aria-labelledby');
      if (!labelledBy) return '';
      return labelledBy
        .split(/\s+/)
        .map((id) => document.getElementById(id)?.textContent || '')
        .join(' ');
    }

    function placeholderText(element: Element) {
      if (
        element instanceof HTMLInputElement
        || element instanceof HTMLTextAreaElement
        || element instanceof HTMLSelectElement
      ) {
        return element.getAttribute('placeholder') || element.getAttribute('aria-placeholder') || '';
      }
      return '';
    }

    function accessibleName(element: Element) {
      const explicitLabel = element.getAttribute('aria-label') || '';
      const labelledText = labelledByText(element);
      const title = element.getAttribute('title') || '';
      const placeholder = placeholderText(element);
      const visibleText = element.textContent || '';
      return [explicitLabel, labelledText, title, placeholder, visibleText]
        .join(' ')
        .replace(/\s+/g, ' ')
        .trim();
    }

    function auditReason(element: Element, rect: DOMRect, clipped: VisibleRectResult) {
      const style = window.getComputedStyle(element);
      const isDisabled = isSemanticallyDisabled(element);
      const reasons = [];
      if (!accessibleName(element)) {
        reasons.push('missing_accessible_name');
      }
      if (!isDisabled && !hasSharedHitTargetClass(element)) {
        reasons.push('missing_shared_hit_target_contract');
      }
      if (style.pointerEvents === 'none' && !isDisabled) {
        reasons.push('pointer_events_none');
      }
      if (requiresPointerAffordance(element) && style.cursor !== 'pointer') {
        reasons.push('missing_click_affordance');
      }
      if (Math.round(rect.width) < minimumHitTarget || Math.round(rect.height) < minimumHitTarget) {
        reasons.push('too_small');
      }
      if (
        (clipped.hardClipped || !clipped.scrollClipped)
        && (Math.round(clipped.rect.width) < minimumHitTarget || Math.round(clipped.rect.height) < minimumHitTarget)
      ) {
        reasons.push('visible_area_too_small_or_clipped');
      }
      if (!isDisabled && !isTopMostAtCenter(element, clipped.rect)) {
        reasons.push('center_blocked_or_clipped');
      }
      if (!isDisabled && !hasReliableClickableInterior(element, clipped.rect)) {
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

    function closestInteractiveAncestor(element: Element) {
      let ancestor = element.parentElement;
      while (ancestor) {
        if (ancestor.matches(selector)) return ancestor;
        ancestor = ancestor.parentElement;
      }
      return null;
    }

    function isAssociatedLabelPair(child: Element, parent: Element) {
      return parent instanceof HTMLLabelElement
        && associatedLabelControl(parent) === child;
    }

    const visibleTargets: VisibleTarget[] = [...document.querySelectorAll(selector)]
      .map((element) => {
        const rect = element.getBoundingClientRect();
        const clipped = visibleRect(element, rect);
        return { clipped, element, rect };
      })
      .filter(({ clipped, element, rect }) => (
        isAuditableInteractiveElement(element)
          && isVisible(element, rect)
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

    const visibleTargetElements = new Set(visibleTargets.map(({ element }) => element));
    const nestedIssues: TargetNestedIssue[] = visibleTargets
      .map(({ element }) => {
        const parent = closestInteractiveAncestor(element);
        if (!parent || !visibleTargetElements.has(parent)) return null;
        if (isAssociatedLabelPair(element, parent)) return null;
        return {
          child: labelFor(element),
          parent: labelFor(parent)
        };
      })
      .filter((issue): issue is TargetNestedIssue => Boolean(issue));

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

    return { nestedIssues, overlapIssues, targetIssues };
  }, {
    activeLayerSelector: ACTIVE_LAYER_SELECTOR,
    minimumHitTarget: MINIMUM_HIT_TARGET,
    selector: INTERACTIVE_SELECTOR,
    sharedHitTargetClasses: SHARED_HIT_TARGET_CLASSES,
    targetSampleFractions: TARGET_SAMPLE_FRACTIONS
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

export async function expectNoNestedInteractiveTargets(page: Page, label: string) {
  const { nestedIssues } = await interactionAuditReport(page);
  expect(nestedIssues, `${label} should not nest one interactive target inside another`).toEqual([]);
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
  const clickableInteriorIssues = await target.evaluate((element, { minimumHitTarget, sharedHitTargetClasses, targetSampleFractions }) => {
    const rect = element.getBoundingClientRect();
    const style = window.getComputedStyle(element);
    const issues: string[] = [];

    function accessibleName(targetElement: Element) {
      const labelledBy = targetElement.getAttribute('aria-labelledby') || '';
      const labelledText = labelledBy
        .split(/\s+/)
        .map((id) => document.getElementById(id)?.textContent || '')
        .join(' ');
      const placeholder = (
        targetElement instanceof HTMLInputElement
        || targetElement instanceof HTMLTextAreaElement
        || targetElement instanceof HTMLSelectElement
      ) ? targetElement.getAttribute('placeholder') || targetElement.getAttribute('aria-placeholder') || '' : '';
      return [
        targetElement.getAttribute('aria-label') || '',
        labelledText,
        targetElement.getAttribute('title') || '',
        placeholder,
        targetElement.textContent || ''
      ]
        .join(' ')
        .replace(/\s+/g, ' ')
        .trim();
    }

    function isPointOwnedByTarget(x: number, y: number) {
      const topElement = document.elementFromPoint(x, y);
      return topElement === element || Boolean(topElement && element.contains(topElement));
    }

    const isDisabled = element.matches(':disabled,[aria-disabled="true"]');
    const samplePoints = targetSampleFractions.flatMap((yFraction) => (
      targetSampleFractions.map((xFraction) => [
        rect.left + rect.width * xFraction,
        rect.top + rect.height * yFraction
      ])
    )).filter(([x, y]) => (
      x >= 0
        && y >= 0
        && x <= document.documentElement.clientWidth
        && y <= document.documentElement.clientHeight
    ));

    if (!accessibleName(element)) {
      issues.push('missing_accessible_name');
    }
    if (!sharedHitTargetClasses.some(className => element.classList.contains(className))) {
      issues.push('missing_shared_hit_target_contract');
    }
    if (style.pointerEvents === 'none' && !isDisabled) {
      issues.push('pointer_events_none');
    }
    if (!isDisabled && ![
      'input',
      'select',
      'textarea'
    ].includes(element.tagName.toLowerCase()) && style.cursor !== 'pointer') {
      issues.push('missing_click_affordance');
    }
    if (Math.round(rect.width) < minimumHitTarget || Math.round(rect.height) < minimumHitTarget) {
      issues.push('too_small');
    }
    if (!isDisabled && samplePoints.length === 0) {
      issues.push('no_visible_sample_points');
    }
    if (!isDisabled && samplePoints.some(([x, y]) => !isPointOwnedByTarget(x, y))) {
      issues.push('clickable_interior_blocked');
    }
    return issues;
  }, {
    minimumHitTarget: MINIMUM_HIT_TARGET,
    sharedHitTargetClasses: SHARED_HIT_TARGET_CLASSES,
    targetSampleFractions: TARGET_SAMPLE_FRACTIONS
  });
  expect(clickableInteriorIssues, `${label} should have a named, unblocked clickable interior`).toEqual([]);
}

export async function expectCriticalTargetRegistry(label: string, probes: CriticalTargetProbe[]) {
  expect(probes.length, `${label} should declare at least one critical click target`).toBeGreaterThan(0);
  for (const probe of probes) {
    await expectHitTarget(probe.locator, `${label}: ${probe.label}`);
    if (probe.expectedClass) {
      const classList = await probe.locator.first().evaluate((element) => [...element.classList]);
      expect(
        classList,
        `${label}: ${probe.label} should use the expected semantic click-target class`
      ).toContain(probe.expectedClass);
      const expectedKind = EXPECTED_KIND_BY_CLASS[probe.expectedClass];
      if (expectedKind) {
        const hitTargetKind = await probe.locator.first().getAttribute('data-hit-target-kind');
        expect(
          hitTargetKind,
          `${label}: ${probe.label} should declare the expected semantic click-target kind`
        ).toBe(expectedKind);
      }
    }
  }
}

export async function clickTargetInteriorPoint(
  locator: Locator,
  label: string,
  xFraction: number,
  yFraction: number
) {
  const target = locator.first();
  await expectHitTarget(target, label);
  const box = await target.boundingBox();
  if (!box) throw new Error(`${label} should have layout bounds`);
  const clamp = (value: number, max: number) => Math.max(1, Math.min(max - 1, value));
  await target.click({
    position: {
      x: clamp(box.width * xFraction, box.width),
      y: clamp(box.height * yFraction, box.height)
    }
  });
}

export async function expectTextEntryFocusFromInteriorPoint(
  locator: Locator,
  label: string,
  xFraction: number,
  yFraction: number
) {
  const target = locator.first();
  await clickTargetInteriorPoint(target, label, xFraction, yFraction);
  await expect(target, `${label} should focus after clicking inside its hit target`).toBeFocused();
}
