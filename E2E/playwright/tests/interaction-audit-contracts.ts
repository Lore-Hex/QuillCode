import type { Locator } from '@playwright/test';

export const MINIMUM_HIT_TARGET = 44;
export const MINIMUM_TARGET_CLEARANCE = 8;
export const TARGET_INTERIOR_SAMPLE_FRACTIONS = [0.2, 0.5, 0.8];
export const TARGET_EDGE_SAMPLE_FRACTIONS = [0.08, 0.92];
export const SHARED_HIT_TARGET_CLASSES = [
  'hit-target-owned',
  'hit-target-link',
  'hit-target-icon',
  'hit-target-text',
  'hit-target-text-entry',
  'hit-target-segmented',
  'hit-target-row',
  'hit-target-switch-row',
  'hit-target-capsule',
  'hit-target-form-action',
  'hit-target-adjustable'
];

export const EXPECTED_KIND_BY_CLASS: Record<string, string> = {
  'hit-target-owned': 'owned',
  'hit-target-link': 'link',
  'hit-target-icon': 'icon',
  'hit-target-text': 'text',
  'hit-target-text-entry': 'text-entry',
  'hit-target-segmented': 'segmented',
  'hit-target-row': 'row',
  'hit-target-switch-row': 'switch-row',
  'hit-target-capsule': 'capsule',
  'hit-target-form-action': 'form-action',
  'hit-target-adjustable': 'adjustable'
};

export const EXPECTED_ACTION_BY_KIND: Record<string, string> = {
  adjustable: 'adjust',
  capsule: 'press',
  'form-action': 'press',
  icon: 'press',
  link: 'link',
  owned: 'owned-gesture',
  row: 'press',
  segmented: 'press',
  'switch-row': 'press',
  text: 'press',
  'text-entry': 'text-input'
};

export const INTERACTIVE_SELECTOR = [
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

export const ACTIVE_LAYER_SELECTOR = [
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

export type TargetAuditIssue = {
  className: string;
  height: number;
  label: string;
  reason: string;
  tag: string;
  testid: string | null;
  text: string;
  width: number;
};

export type TargetOverlapIssue = {
  a: string;
  b: string;
  overlapHeight: number;
  overlapWidth: number;
};

export type TargetClearanceIssue = {
  a: string;
  axis: 'x' | 'y';
  b: string;
  gap: number;
};

export type TargetNestedIssue = {
  child: string;
  parent: string;
};

export type InteractionAuditReport = {
  clearanceIssues: TargetClearanceIssue[];
  nestedIssues: TargetNestedIssue[];
  overlapIssues: TargetOverlapIssue[];
  targetIssues: TargetAuditIssue[];
};

export type CriticalTargetProbe = {
  expectedClass?: string;
  expectedAction?: string;
  expectedKind?: string;
  label: string;
  locator: Locator;
};

export type CriticalTargetSurface = {
  label: string;
  probes: CriticalTargetProbe[];
  requiredKinds: string[];
};
