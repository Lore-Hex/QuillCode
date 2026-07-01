import { expect, type Locator, type Page } from '@playwright/test';

import {
  EXPECTED_ACTION_BY_KIND,
  EXPECTED_KIND_BY_CLASS,
  MINIMUM_HIT_TARGET,
  MINIMUM_TARGET_CLEARANCE,
  SHARED_HIT_TARGET_CLASSES,
  TARGET_EDGE_SAMPLE_FRACTIONS,
  TARGET_INTERIOR_SAMPLE_FRACTIONS,
  type CriticalTargetProbe,
  type CriticalTargetSurface
} from './interaction-audit-contracts';
import { interactionAuditReport } from './interaction-audit-report';

export async function expectAllVisibleInteractiveTargets(page: Page, label: string) {
  const { targetIssues } = await interactionAuditReport(page);
  expect(targetIssues, `${label} should keep every visible interactive target at least ${MINIMUM_HIT_TARGET}px`).toEqual([]);
}

export async function expectNoOverlappingInteractiveTargets(page: Page, label: string) {
  const { overlapIssues } = await interactionAuditReport(page);
  expect(overlapIssues, `${label} should not have overlapping peer interactive targets`).toEqual([]);
}

export async function expectNoAmbiguousAdjacentInteractiveTargets(page: Page, label: string) {
  const { clearanceIssues } = await interactionAuditReport(page);
  expect(
    clearanceIssues,
    `${label} should keep adjacent peer interactive targets at least ${MINIMUM_TARGET_CLEARANCE}px apart unless they are intentional list/menu rows`
  ).toEqual([]);
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
  const clickableInteriorIssues = await target.evaluate((element, { edgeSampleFractions, expectedActionByKind, expectedKindByClass, interiorSampleFractions, minimumHitTarget, sharedHitTargetClasses }) => {
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

    function classDerivedHitTargetKind(targetElement: Element) {
      for (const [className, kind] of Object.entries(expectedKindByClass)) {
        if (targetElement.classList.contains(className)) return kind;
      }
      return '';
    }

    function isRangeInput(targetElement: Element) {
      return targetElement instanceof HTMLInputElement
        && (targetElement.type || '').toLowerCase() === 'range';
    }

    function isTextEntryLikeElement(targetElement: Element) {
      if (targetElement instanceof HTMLTextAreaElement || targetElement instanceof HTMLSelectElement) return true;
      if (!(targetElement instanceof HTMLInputElement)) return false;
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
      ].includes((targetElement.type || 'text').toLowerCase());
    }

    function expectedElementAction(targetElement: Element) {
      if (isTextEntryLikeElement(targetElement)) return 'text-input';
      if (isRangeInput(targetElement)) return 'adjust';
      if (targetElement.matches('a[href]')) return 'link';
      if (
        targetElement.matches([
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

    function requiresTactileFeedbackContract(targetElement: Element) {
      if (targetElement.matches(':disabled,[aria-disabled="true"]') || isTextEntryLikeElement(targetElement)) return false;
      return ['adjust', 'link', 'owned-gesture', 'press'].includes(targetElement.getAttribute('data-hit-target-action') || '');
    }

    function hasTransformTransition(targetStyle: CSSStyleDeclaration) {
      const properties = targetStyle.transitionProperty
        .split(',')
        .map(value => value.trim());
      return properties.includes('all') || properties.includes('transform');
    }

    const isDisabled = element.matches(':disabled,[aria-disabled="true"]');
    const declaredKind = element.getAttribute('data-hit-target-kind') || '';
    const derivedKind = classDerivedHitTargetKind(element);
    const declaredAction = element.getAttribute('data-hit-target-action') || '';
    const expectedKindAction = expectedActionByKind[declaredKind];
    const nativeElementAction = expectedElementAction(element);
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
    const samplePoints = [...interiorGrid, ...edgeMidlines].filter(([x, y]) => (
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
    if (
      (element.getAttribute('data-hit-target-source') || '') === 'auto'
      || (element.getAttribute('data-hit-target-kind') || '').startsWith('auto-')
    ) {
      issues.push('missing_shared_hit_target_contract');
    }
    if (
      !(element.getAttribute('data-hit-target-action') || '')
      || (element.getAttribute('data-hit-target-action') || '').startsWith('auto-')
    ) {
      issues.push('missing_hit_target_action');
    }
    if (!isDisabled && declaredKind && derivedKind && declaredKind !== derivedKind) {
      issues.push('hit_target_kind_class_mismatch');
    }
    if (!isDisabled && expectedKindAction && declaredAction && declaredAction !== expectedKindAction) {
      issues.push('hit_target_action_mismatch');
    }
    if (!isDisabled && nativeElementAction && declaredAction && declaredAction !== nativeElementAction) {
      issues.push('element_action_mismatch');
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
    if (requiresTactileFeedbackContract(element) && style.touchAction !== 'manipulation') {
      issues.push('missing_touch_action_manipulation');
    }
    if (requiresTactileFeedbackContract(element) && style.userSelect !== 'none') {
      issues.push('click_target_allows_text_selection');
    }
    if (requiresTactileFeedbackContract(element) && !hasTransformTransition(style)) {
      issues.push('missing_press_feedback_transition');
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
    edgeSampleFractions: TARGET_EDGE_SAMPLE_FRACTIONS,
    expectedActionByKind: EXPECTED_ACTION_BY_KIND,
    expectedKindByClass: EXPECTED_KIND_BY_CLASS,
    interiorSampleFractions: TARGET_INTERIOR_SAMPLE_FRACTIONS,
    minimumHitTarget: MINIMUM_HIT_TARGET,
    sharedHitTargetClasses: SHARED_HIT_TARGET_CLASSES
  });
  expect(clickableInteriorIssues, `${label} should have a named, unblocked clickable interior`).toEqual([]);
}

export async function expectCriticalTargetRegistry(label: string, probes: CriticalTargetProbe[]) {
  expect(probes.length, `${label} should declare at least one critical click target`).toBeGreaterThan(0);
  for (const probe of probes) {
    expect(
      Boolean(probe.expectedKind || probe.expectedClass),
      `${label}: ${probe.label} should declare semantic click-target intent`
    ).toBe(true);
    await expectHitTarget(probe.locator, `${label}: ${probe.label}`);
    if (probe.expectedKind) {
      const expectedClass = Object.entries(EXPECTED_KIND_BY_CLASS)
        .find(([, kind]) => kind === probe.expectedKind)?.[0];
      expect(
        expectedClass,
        `${label}: ${probe.label} should have a known class for semantic click-target kind ${probe.expectedKind}`
      ).toBeTruthy();
      const classList = await probe.locator.first().evaluate((element) => [...element.classList]);
      expect(
        classList,
        `${label}: ${probe.label} should use the class for semantic click-target kind ${probe.expectedKind}`
      ).toContain(expectedClass);
      const hitTargetKind = await probe.locator.first().getAttribute('data-hit-target-kind');
      expect(
        hitTargetKind,
        `${label}: ${probe.label} should declare semantic click-target kind ${probe.expectedKind}`
      ).toBe(probe.expectedKind);
      const hitTargetAction = await probe.locator.first().getAttribute('data-hit-target-action');
      expect(
        hitTargetAction,
        `${label}: ${probe.label} should declare semantic click-target action ${EXPECTED_ACTION_BY_KIND[probe.expectedKind]}`
      ).toBe(EXPECTED_ACTION_BY_KIND[probe.expectedKind]);
    }
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
        const hitTargetAction = await probe.locator.first().getAttribute('data-hit-target-action');
        expect(
          hitTargetAction,
          `${label}: ${probe.label} should declare the expected semantic click-target action`
        ).toBe(EXPECTED_ACTION_BY_KIND[expectedKind]);
      }
    }
    if (probe.expectedAction) {
      await expect(probe.locator.first(), `${label}: ${probe.label} should declare action ${probe.expectedAction}`)
        .toHaveAttribute('data-hit-target-action', probe.expectedAction);
    }
    await expect(probe.locator.first(), `${label}: ${probe.label} should not rely on auto-inferred hit-target semantics`)
      .not.toHaveAttribute('data-hit-target-source', 'auto');
  }
}

export async function expectCriticalTargetSurfaceRegistry(label: string, surfaces: CriticalTargetSurface[]) {
  expect(surfaces.length, `${label} should declare at least one interaction surface`).toBeGreaterThan(0);

  for (const surface of surfaces) {
    await expectCriticalTargetRegistry(`${label}: ${surface.label}`, surface.probes);

    const declaredKinds = new Set(surface.probes.map((probe) => {
      if (probe.expectedKind) return probe.expectedKind;
      if (probe.expectedClass) return EXPECTED_KIND_BY_CLASS[probe.expectedClass];
      return '';
    }).filter(Boolean));

    for (const requiredKind of surface.requiredKinds) {
      expect(
        declaredKinds.has(requiredKind),
        `${label}: ${surface.label} should include a ${requiredKind} target`
      ).toBe(true);
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
