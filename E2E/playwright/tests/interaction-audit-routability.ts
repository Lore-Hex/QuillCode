import { expect, type Page } from '@playwright/test';
import {
  expectAllVisibleInteractiveTargets,
  expectNoAmbiguousAdjacentInteractiveTargets,
  expectNoNestedInteractiveTargets,
  expectNoOverlappingInteractiveTargets
} from './interaction-audit-helpers';

export async function expectInteractionTargetsClean(page: Page, label: string) {
  await expectAllVisibleInteractiveTargets(page, label);
  await expectNoNestedInteractiveTargets(page, label);
  await expectNoOverlappingInteractiveTargets(page, label);
  await expectNoAmbiguousAdjacentInteractiveTargets(page, label);
  await expectCommandTargetsRoutable(page, label);
}

export async function expectCommandTargetsRoutable(page: Page, label: string) {
  const report = await page.evaluate(() => {
    const harness = window as typeof window & {
      __quillCodeCommandRoutingAudit?: () => {
        unroutableCommands: Array<{ commandID: string; title: string; enabled: boolean }>;
        unroutableTargets: Array<{ commandID: string; testid: string; text: string }>;
      };
    };
    return harness.__quillCodeCommandRoutingAudit?.() ?? {
      unroutableCommands: [{ commandID: 'missing-audit-hook', title: 'Missing audit hook', enabled: true }],
      unroutableTargets: []
    };
  });

  expect(
    report.unroutableCommands,
    `${label} should not publish command IDs the harness cannot route`
  ).toEqual([]);
  expect(
    report.unroutableTargets,
    `${label} should not render visible enabled command targets with unroutable command IDs`
  ).toEqual([]);
}
