import { test, expect } from '@playwright/test';
import {
  clickCommandPaletteCommand,
  clickSidebarTool,
  commandPaletteResult,
  fillCommandPalette,
  harnessURL,
  openSettings,
  openTopBarOverflow
} from './harness-helpers';
import {
  expectCriticalTargetRegistry,
  expectCriticalTargetSurfaceRegistry,
  expectHitTarget,
  interactionAuditReport,
  clickTargetInteriorPoint,
  expectTextEntryFocusFromInteriorPoint
} from './interaction-audit-helpers';
import {
  expectCommandTargetsRoutable,
  expectInteractionTargetsClean
} from './interaction-audit-routability';

test('interaction audit catches dead and edge-blocked visible controls', async ({ page }) => {
  await page.goto(harnessURL());

  await page.evaluate(() => {
    const fixture = document.createElement('div');
    fixture.setAttribute('data-testid', 'interaction-audit-fixture');
    fixture.innerHTML = `
      <button
        type="button"
        data-testid="bad-pointer-target"
        style="position: fixed; left: 24px; top: 24px; z-index: 1000; width: 96px; height: 48px; pointer-events: none;"
      >Dead target</button>
      <button
        type="button"
        disabled
        data-testid="disabled-pointer-target"
        style="position: fixed; left: 24px; top: 84px; z-index: 1000; width: 96px; height: 48px; pointer-events: none;"
      >Disabled target</button>
      <button
        type="button"
        data-testid="edge-blocked-target"
        style="position: fixed; left: 24px; top: 144px; z-index: 1000; width: 96px; height: 64px;"
      >Edge blocked</button>
      <button
        type="button"
        data-testid="near-edge-blocked-target"
        style="position: fixed; left: 24px; top: 408px; z-index: 1000; width: 120px; height: 48px;"
      >Near edge blocked</button>
      <button
        type="button"
        data-testid="missing-affordance-target"
        style="position: fixed; left: 24px; top: 220px; z-index: 1000; width: 96px; height: 48px; cursor: default;"
      >Looks dead</button>
      <button
        type="button"
        data-testid="missing-contract-target"
        style="position: fixed; left: 24px; top: 348px; z-index: 1000; width: 112px; height: 48px; cursor: pointer;"
      >No contract</button>
      <button
        type="button"
        class="hit-target-text-entry"
        data-testid="button-declared-as-text-entry-target"
        data-hit-target-kind="text-entry"
        data-hit-target-action="text-input"
        data-hit-target-source="explicit"
        style="position: fixed; left: 164px; top: 24px; z-index: 1000; width: 156px; height: 48px; cursor: pointer;"
      >Wrong kind</button>
      <button
        type="button"
        class="hit-target-text"
        data-testid="button-declared-as-link-action"
        data-hit-target-kind="text"
        data-hit-target-action="link"
        data-hit-target-source="explicit"
        style="position: fixed; left: 164px; top: 84px; z-index: 1000; width: 156px; height: 48px; cursor: pointer;"
      >Wrong action</button>
      <a
        href="#"
        class="hit-target-text"
        data-testid="link-declared-as-press-target"
        data-hit-target-kind="text"
        data-hit-target-action="press"
        data-hit-target-source="explicit"
        style="position: fixed; left: 164px; top: 144px; z-index: 1000; width: 156px; height: 48px; cursor: pointer;"
      >Wrong link</a>
      <button
        type="button"
        class="hit-target-row"
        data-testid="kind-class-mismatch-target"
        data-hit-target-kind="icon"
        data-hit-target-action="press"
        data-hit-target-source="explicit"
        style="position: fixed; left: 164px; top: 204px; z-index: 1000; width: 156px; height: 48px; cursor: pointer;"
      >Mismatch</button>
      <button
        type="button"
        class="hit-target-text"
        data-testid="missing-tactile-contract-target"
        data-hit-target-kind="text"
        data-hit-target-action="press"
        data-hit-target-source="explicit"
        style="position: fixed; left: 340px; top: 24px; z-index: 1000; width: 184px; height: 48px; cursor: pointer; touch-action: auto; user-select: text; transition-property: background-color;"
      >No tactile contract</button>
      <button
        type="button"
        class="hit-target-text"
        data-testid="too-close-a"
        data-hit-target-kind="text"
        data-hit-target-action="press"
        data-hit-target-source="explicit"
        style="position: fixed; left: 164px; top: 264px; z-index: 1000; width: 80px; height: 48px; cursor: pointer;"
      >Close A</button>
      <button
        type="button"
        class="hit-target-text"
        data-testid="too-close-b"
        data-hit-target-kind="text"
        data-hit-target-action="press"
        data-hit-target-source="explicit"
        style="position: fixed; left: 246px; top: 264px; z-index: 1000; width: 80px; height: 48px; cursor: pointer;"
      >Close B</button>
      <span
        aria-hidden="true"
        style="position: fixed; left: 24px; top: 144px; z-index: 1001; width: 28px; height: 28px; background: rgba(255, 93, 82, 0.85);"
      ></span>
      <span
        aria-hidden="true"
        style="position: fixed; left: 132px; top: 408px; z-index: 1001; width: 12px; height: 48px; background: rgba(255, 93, 82, 0.85);"
      ></span>
      <input
        type="checkbox"
        id="tiny-checkbox"
        data-testid="tiny-checkbox"
        style="position: fixed; left: -1000px; top: -1000px; width: 1px; height: 1px;"
      >
      <label
        for="tiny-checkbox"
        data-testid="tiny-checkbox-label"
        style="position: fixed; left: 24px; top: 280px; z-index: 1000; width: 22px; height: 22px;"
      >Tiny</label>
      <input
        type="checkbox"
        id="disabled-checkbox"
        disabled
        data-testid="disabled-checkbox"
        style="position: fixed; left: -1000px; top: -1000px; width: 1px; height: 1px;"
      >
      <label
        for="disabled-checkbox"
        data-testid="disabled-checkbox-label"
        style="position: fixed; left: 24px; top: 312px; z-index: 1000; width: 22px; height: 22px;"
      >Disabled</label>
      <label
        class="hit-target-switch-row"
        data-testid="owned-checkbox-label"
        data-hit-target-kind="switch-row"
        data-hit-target-action="press"
        data-hit-target-source="explicit"
        style="position: fixed; left: 360px; top: 280px; z-index: 1000; width: 220px; height: 44px;"
      >
        <input
          type="checkbox"
          data-testid="owned-checkbox"
          aria-label="Owned checkbox"
          style="width: 20px; min-width: 20px; height: 20px; min-height: 20px;"
        >
        <span>Owned checkbox</span>
      </label>
    `;
    document.body.appendChild(fixture);
  });

  const report = await interactionAuditReport(page);
  const issueFor = (testid: string) => report.targetIssues.find((issue) => issue.testid === testid);

  expect(issueFor('bad-pointer-target')?.reason).toContain('pointer_events_none');
  expect(issueFor('edge-blocked-target')?.reason).toContain('interior_click_area_blocked');
  expect(issueFor('near-edge-blocked-target')?.reason).toContain('interior_click_area_blocked');
  expect(issueFor('missing-affordance-target')?.reason).toContain('missing_click_affordance');
  expect(issueFor('missing-contract-target')?.reason).toContain('missing_shared_hit_target_contract');
  expect(issueFor('button-declared-as-text-entry-target')?.reason).toContain('element_action_mismatch');
  expect(issueFor('button-declared-as-link-action')?.reason).toContain('hit_target_action_mismatch');
  expect(issueFor('button-declared-as-link-action')?.reason).toContain('element_action_mismatch');
  expect(issueFor('link-declared-as-press-target')?.reason).toContain('element_action_mismatch');
  expect(issueFor('kind-class-mismatch-target')?.reason).toContain('hit_target_kind_class_mismatch');
  expect(issueFor('missing-tactile-contract-target')?.reason).toContain('missing_touch_action_manipulation');
  expect(issueFor('missing-tactile-contract-target')?.reason).toContain('click_target_allows_text_selection');
  expect(issueFor('missing-tactile-contract-target')?.reason).toContain('missing_press_feedback_transition');
  expect(issueFor('tiny-checkbox-label')?.reason).toContain('too_small');
  expect(issueFor('owned-checkbox')).toBeUndefined();
  expect(issueFor('owned-checkbox-label')).toBeUndefined();
  expect(issueFor('disabled-pointer-target')).toBeUndefined();
  expect(issueFor('disabled-checkbox-label')).toBeUndefined();

  expect(report.clearanceIssues).toContainEqual(
    expect.objectContaining({
      a: expect.stringContaining('too-close-a'),
      axis: 'x',
      b: expect.stringContaining('too-close-b'),
      gap: 2
    })
  );
});

test('command routing audit catches visible dead command targets', async ({ page }) => {
  await page.goto(harnessURL());

  await expectCommandTargetsRoutable(page, 'initial workspace');
  await page.evaluate(() => {
    const fixture = document.createElement('button');
    fixture.type = 'button';
    fixture.textContent = 'Dead command';
    fixture.setAttribute('data-testid', 'dead-command-target');
    fixture.setAttribute('data-command-id', 'definitely-not-routable');
    fixture.style.position = 'fixed';
    fixture.style.left = '24px';
    fixture.style.top = '24px';
    fixture.style.zIndex = '1000';
    fixture.style.width = '160px';
    fixture.style.height = '48px';
    document.body.appendChild(fixture);
  });

  const report = await page.evaluate(() => {
    const harness = window as typeof window & {
      __quillCodeCommandRoutingAudit: () => {
        unroutableTargets: Array<{ commandID: string; testid: string; text: string }>;
      };
    };
    return harness.__quillCodeCommandRoutingAudit();
  });

  expect(report.unroutableTargets).toContainEqual({
    commandID: 'definitely-not-routable',
    testid: 'dead-command-target',
    text: 'Dead command'
  });
});

test('critical controls respond from the full interior click target, not only the center', async ({ page }) => {
  await page.goto(harnessURL());

  const initialProjectCount = await page.getByTestId('project-item').count();
  await clickTargetInteriorPoint(page.getByTestId('add-project-button'), 'add project bottom interior', 0.5, 0.82);
  await expect(page.getByTestId('project-item')).toHaveCount(initialProjectCount + 1);

  await clickTargetInteriorPoint(page.getByTestId('top-bar-overflow-button'), 'top-bar overflow leading interior', 0.2, 0.5);
  await expect(page.getByTestId('top-bar-overflow-menu')).toHaveAttribute('open', '');
  await clickTargetInteriorPoint(page.getByTestId('top-bar-overflow-button'), 'top-bar overflow trailing interior', 0.8, 0.5);
  await expect(page.getByTestId('top-bar-overflow-menu')).not.toHaveAttribute('open', '');

  await clickTargetInteriorPoint(page.getByTestId('model-picker-button'), 'model picker leading interior', 0.2, 0.5);
  await expect(page.getByTestId('model-browser')).toBeVisible();
  await clickTargetInteriorPoint(page.getByTestId('model-picker-button'), 'model picker trailing interior', 0.8, 0.5);
  await expect(page.getByTestId('model-browser')).not.toBeVisible();

  await clickTargetInteriorPoint(page.getByTestId('sidebar-tools-button'), 'sidebar tools leading interior', 0.2, 0.5);
  await expect(page.getByTestId('sidebar-tools-menu')).toHaveAttribute('open', '');
  await clickTargetInteriorPoint(page.getByTestId('browser-button'), 'browser tool row trailing interior', 0.85, 0.5);
  await expect(page.getByTestId('browser-pane')).toBeVisible();

  await page.getByLabel('Message').fill('run whoami');
  await clickTargetInteriorPoint(page.getByRole('button', { name: 'Send' }), 'composer send button leading interior', 0.2, 0.5);
  await expect(page.getByTestId('tool-card').last()).toHaveAttribute('data-status', 'done');
  await clickTargetInteriorPoint(page.getByTestId('tool-card-details').last().locator('summary'), 'tool details disclosure leading interior', 0.2, 0.5);
  await expect(page.getByTestId('tool-card-details').last()).toHaveAttribute('open', '');
});
