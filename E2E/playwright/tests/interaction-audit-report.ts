import type { Page } from '@playwright/test';

import {
  ACTIVE_LAYER_SELECTOR,
  EXPECTED_ACTION_BY_KIND,
  EXPECTED_KIND_BY_CLASS,
  INTERACTIVE_SELECTOR,
  MINIMUM_HIT_TARGET,
  MINIMUM_TARGET_CLEARANCE,
  SHARED_HIT_TARGET_CLASSES,
  TARGET_EDGE_SAMPLE_FRACTIONS,
  TARGET_INTERIOR_SAMPLE_FRACTIONS,
  type InteractionAuditReport
} from './interaction-audit-contracts';

export async function interactionAuditReport(page: Page): Promise<InteractionAuditReport> {
  return page.evaluate(({
    activeLayerSelector,
    edgeSampleFractions,
    expectedActionByKind,
    expectedKindByClass,
    interiorSampleFractions,
    minimumHitTarget,
    minimumTargetClearance,
    selector,
    sharedHitTargetClasses
  }) => {
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

    function hasExplicitHitTargetContract(element: Element) {
      const source = element.getAttribute('data-hit-target-source') || '';
      const kind = element.getAttribute('data-hit-target-kind') || '';
      return source !== 'auto' && !kind.startsWith('auto-');
    }

    function hasHitTargetAction(element: Element) {
      const action = element.getAttribute('data-hit-target-action') || '';
      return Boolean(action) && !action.startsWith('auto-');
    }

    function declaredHitTargetKind(element: Element) {
      return element.getAttribute('data-hit-target-kind') || '';
    }

    function declaredHitTargetAction(element: Element) {
      return element.getAttribute('data-hit-target-action') || '';
    }

    function classDerivedHitTargetKind(element: Element) {
      for (const [className, kind] of Object.entries(expectedKindByClass)) {
        if (element.classList.contains(className)) return kind;
      }
      return '';
    }

    function isRangeInput(element: Element) {
      return element instanceof HTMLInputElement
        && (element.type || '').toLowerCase() === 'range';
    }

    function spanOverlap(startA: number, endA: number, startB: number, endB: number) {
      return Math.min(endA, endB) - Math.max(startA, startB);
    }

    function spanGap(startA: number, endA: number, startB: number, endB: number) {
      return Math.max(startA, startB) - Math.min(endA, endB);
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

    function expectedElementAction(element: Element) {
      if (isTextEntryLikeElement(element)) return 'text-input';
      if (isRangeInput(element)) return 'adjust';
      if (element.matches('a[href]')) return 'link';
      if (element instanceof HTMLLabelElement && isAuditableInteractiveElement(element)) return 'press';
      if (
        element.matches([
          'button',
          'summary',
          '[role="button"]',
          '[role="checkbox"]',
          '[role="menuitem"]',
          '[role="option"]',
          '[role="switch"]',
          '[role="tab"]',
          'input[type="checkbox"]',
          'input[type="radio"]'
        ].join(','))
      ) {
        return 'press';
      }
      return null;
    }

    function requiresPointerAffordance(element: Element) {
      if (isSemanticallyDisabled(element) || isTextEntryLikeElement(element)) return false;
      if (element instanceof HTMLLabelElement) return isAuditableInteractiveElement(element);
      if (element instanceof HTMLInputElement) return true;
      return true;
    }

    function requiresTactileFeedbackContract(element: Element) {
      if (isSemanticallyDisabled(element) || isTextEntryLikeElement(element)) return false;
      return ['adjust', 'link', 'owned-gesture', 'press'].includes(declaredHitTargetAction(element));
    }

    function hasTransformTransition(style: CSSStyleDeclaration) {
      const properties = style.transitionProperty
        .split(',')
        .map(value => value.trim());
      return properties.includes('all') || properties.includes('transform');
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
      const interiorGrid = interiorSampleFractions.flatMap((yFraction) => (
        interiorSampleFractions.map((xFraction) => [
          rect.left + rect.width * xFraction,
          rect.top + rect.height * yFraction
        ])
      ));
      const edgeMidlines = edgeSampleFractions.flatMap((edgeFraction) => [
        [rect.left + rect.width * edgeFraction, rect.top + rect.height * 0.5],
        [rect.left + rect.width * 0.5, rect.top + rect.height * edgeFraction]
      ]);
      return [...interiorGrid, ...edgeMidlines].filter(([x, y]) => (
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
      if (!isDisabled && (!hasSharedHitTargetClass(element) || !hasExplicitHitTargetContract(element))) {
        reasons.push('missing_shared_hit_target_contract');
      }
      if (!isDisabled && !hasHitTargetAction(element)) {
        reasons.push('missing_hit_target_action');
      }
      const declaredKind = declaredHitTargetKind(element);
      const derivedKind = classDerivedHitTargetKind(element);
      const declaredAction = declaredHitTargetAction(element);
      const expectedKindAction = expectedActionByKind[declaredKind];
      const nativeElementAction = expectedElementAction(element);
      if (!isDisabled && declaredKind && derivedKind && declaredKind !== derivedKind) {
        reasons.push('hit_target_kind_class_mismatch');
      }
      if (!isDisabled && expectedKindAction && declaredAction && declaredAction !== expectedKindAction) {
        reasons.push('hit_target_action_mismatch');
      }
      if (!isDisabled && nativeElementAction && declaredAction && declaredAction !== nativeElementAction) {
        reasons.push('element_action_mismatch');
      }
      if (style.pointerEvents === 'none' && !isDisabled) {
        reasons.push('pointer_events_none');
      }
      if (requiresPointerAffordance(element) && style.cursor !== 'pointer') {
        reasons.push('missing_click_affordance');
      }
      if (requiresTactileFeedbackContract(element) && style.touchAction !== 'manipulation') {
        reasons.push('missing_touch_action_manipulation');
      }
      if (requiresTactileFeedbackContract(element) && style.userSelect !== 'none') {
        reasons.push('click_target_allows_text_selection');
      }
      if (requiresTactileFeedbackContract(element) && !hasTransformTransition(style)) {
        reasons.push('missing_press_feedback_transition');
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

    function targetKind(element: Element) {
      const declared = declaredHitTargetKind(element);
      if (declared) return declared.replace(/^auto-/, '');
      return classDerivedHitTargetKind(element);
    }

    function isRowLikeTarget(element: Element) {
      const kind = targetKind(element);
      return kind === 'row' || kind === 'switch-row';
    }

    function isMenuOrListRow(element: Element) {
      return isRowLikeTarget(element)
        && Boolean(element.closest([
          '.topbar-overflow-popover',
          '.sidebar-tools-popover',
          '.sidebar-thread-menu-popover',
          '[data-testid="sidebar-compose-zone"]',
          '[data-testid="sidebar-threads-zone"]',
          '[data-testid="project-list"]',
          '[data-testid="search-results"]',
          '[data-testid="command-palette-results"]',
          '[data-testid="model-list"]',
          '[data-testid="worktree-choices"]'
        ].join(',')));
    }

    function allowsTightClearance(first: Element, second: Element, axis: 'x' | 'y') {
      if (axis === 'y' && isMenuOrListRow(first) && isMenuOrListRow(second)) {
        return true;
      }
      if (targetKind(first) === 'segmented' || targetKind(second) === 'segmented') {
        return true;
      }
      return false;
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
    const clearanceIssues: TargetClearanceIssue[] = [];

    for (let i = 0; i < overlapTargets.length; i += 1) {
      for (let j = i + 1; j < overlapTargets.length; j += 1) {
        const first = overlapTargets[i];
        const second = overlapTargets[j];
        if (first.layer !== second.layer) continue;
        if (first.element.contains(second.element) || second.element.contains(first.element)) continue;

        const overlapWidth = spanOverlap(
          first.visibleRect.left,
          first.visibleRect.right,
          second.visibleRect.left,
          second.visibleRect.right
        );
        const overlapHeight = spanOverlap(
          first.visibleRect.top,
          first.visibleRect.bottom,
          second.visibleRect.top,
          second.visibleRect.bottom
        );
        if (overlapWidth > 1 && overlapHeight > 1) {
          overlapIssues.push({
            a: labelFor(first.element),
            b: labelFor(second.element),
            overlapHeight: Math.round(overlapHeight),
            overlapWidth: Math.round(overlapWidth)
          });
          continue;
        }

        const verticalOverlap = spanOverlap(
          first.visibleRect.top,
          first.visibleRect.bottom,
          second.visibleRect.top,
          second.visibleRect.bottom
        );
        const horizontalOverlap = spanOverlap(
          first.visibleRect.left,
          first.visibleRect.right,
          second.visibleRect.left,
          second.visibleRect.right
        );
        const horizontalGap = spanGap(
          first.visibleRect.left,
          first.visibleRect.right,
          second.visibleRect.left,
          second.visibleRect.right
        );
        const verticalGap = spanGap(
          first.visibleRect.top,
          first.visibleRect.bottom,
          second.visibleRect.top,
          second.visibleRect.bottom
        );
        if (
          verticalOverlap > 1
          && horizontalGap >= 0
          && horizontalGap < minimumTargetClearance
          && !allowsTightClearance(first.element, second.element, 'x')
        ) {
          clearanceIssues.push({
            a: labelFor(first.element),
            axis: 'x',
            b: labelFor(second.element),
            gap: Math.round(horizontalGap)
          });
        }
        if (
          horizontalOverlap > 1
          && verticalGap >= 0
          && verticalGap < minimumTargetClearance
          && !allowsTightClearance(first.element, second.element, 'y')
        ) {
          clearanceIssues.push({
            a: labelFor(first.element),
            axis: 'y',
            b: labelFor(second.element),
            gap: Math.round(verticalGap)
          });
        }
      }
    }

    return { clearanceIssues, nestedIssues, overlapIssues, targetIssues };
  }, {
    activeLayerSelector: ACTIVE_LAYER_SELECTOR,
    edgeSampleFractions: TARGET_EDGE_SAMPLE_FRACTIONS,
    expectedActionByKind: EXPECTED_ACTION_BY_KIND,
    expectedKindByClass: EXPECTED_KIND_BY_CLASS,
    interiorSampleFractions: TARGET_INTERIOR_SAMPLE_FRACTIONS,
    minimumHitTarget: MINIMUM_HIT_TARGET,
    minimumTargetClearance: MINIMUM_TARGET_CLEARANCE,
    selector: INTERACTIVE_SELECTOR,
    sharedHitTargetClasses: SHARED_HIT_TARGET_CLASSES
  });
}
