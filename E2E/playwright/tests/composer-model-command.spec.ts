import { test, expect } from '@playwright/test';
import { harnessURL } from './harness-helpers';

test('mock harness browses the model catalog with pricing from the /model popup', async ({ page }) => {
  await page.goto(harnessURL());

  const message = page.getByLabel('Message');

  // A bare `/model` stays a top-level slash command row — the sub-search is NOT active yet.
  await message.fill('/model');
  await expect(page.getByTestId('model-command-suggestions')).toHaveCount(0);
  await expect(page.getByTestId('slash-suggestion').first()).toContainText('/model name');

  // `/model ` (trailing space) opens the catalog sub-search; the top-level slash list is suppressed.
  await message.fill('/model ');
  await expect(page.getByTestId('model-command-suggestions')).toBeVisible();
  await expect(page.getByTestId('slash-suggestions')).toHaveCount(0);
  // Empty query lists the catalog head in catalog order (Nike first).
  const rows = page.getByTestId('model-command-suggestion');
  await expect(rows.first()).toContainText('Nike 1.0');
  await expect(page.getByTestId('model-command-price').first()).toContainText('$0.8 in / $4 out per 1M');
  // The current (default) model is flagged with a Current badge and shows its price.
  const current = page.locator('[data-testid="model-command-suggestion"][data-current="true"]');
  await expect(current).toContainText('Nike 1.0');
  await expect(current).toContainText('Current');
  await expect(current.getByTestId('model-command-price')).toContainText('$0.8 in / $4 out per 1M');

  // Filtering narrows to a single model by a multi-term query (mirrors the picker search).
  await message.fill('/model moon kimi');
  await expect(rows).toHaveCount(1);
  await expect(rows.first()).toContainText('Kimi K2.6');
  // The unpriced model renders gracefully with an empty price line (no crash, no NaN).
  await expect(page.getByTestId('model-command-price').first()).toHaveText('');

  // A query with no match hides the popup entirely.
  await message.fill('/model zzznope');
  await expect(page.getByTestId('model-command-suggestions')).toHaveCount(0);
});

test('mock harness keyboard-navigates and selects a model from the /model popup', async ({ page }) => {
  await page.goto(harnessURL());

  const message = page.getByLabel('Message');
  await message.fill('/model deep research');
  const rows = page.getByTestId('model-command-suggestion');
  await expect(rows).toHaveCount(2); // Zeus + Prometheus
  await expect(page.locator('[data-testid="model-command-suggestion"][data-selected="true"]')).toContainText('Zeus 1.0');

  await page.keyboard.press('ArrowDown');
  await expect(page.locator('[data-testid="model-command-suggestion"][data-selected="true"]')).toContainText('Prometheus 1.0');

  // Clamp at the bottom: another ArrowDown does not wrap past the last row's index via keyboard.
  await page.keyboard.press('ArrowUp');
  await expect(page.locator('[data-testid="model-command-suggestion"][data-selected="true"]')).toContainText('Zeus 1.0');

  // Enter selects: the model switches (picker label updates) and the composer clears — the command
  // never sends as a message.
  await page.keyboard.press('Enter');
  await expect(page.getByTestId('model-picker-button')).toHaveText('Zeus 1.0');
  await expect(message).toHaveValue('');
  await expect(page.getByTestId('model-command-suggestions')).toHaveCount(0);
  // No user message was sent for the /model command.
  await expect(page.getByTestId('message')).toHaveCount(0);
});

test('mock harness selects a model by clicking a /model popup row', async ({ page }) => {
  await page.goto(harnessURL());

  const message = page.getByLabel('Message');
  await message.fill('/model kimi');
  const row = page.getByTestId('model-command-suggestion').first();
  await expect(row).toContainText('Kimi K2.6');
  await row.click();
  await expect(page.getByTestId('model-picker-button')).toHaveText('moonshotai/Kimi K2.6');
  await expect(message).toHaveValue('');
});

test('mock harness does not trigger the /model popup mid-text', async ({ page }) => {
  await page.goto(harnessURL());

  const message = page.getByLabel('Message');
  // `/model` appearing mid-sentence must not fire the popup (command-start rule).
  await message.fill('please run /model fast for me');
  await expect(page.getByTestId('model-command-suggestions')).toHaveCount(0);
  // `/modelfoo` is a different token, not the command.
  await message.fill('/modelfoo');
  await expect(page.getByTestId('model-command-suggestions')).toHaveCount(0);
});

test('mock harness registers /skill as a one-line command in the / popup', async ({ page }) => {
  await page.goto(harnessURL());

  const message = page.getByLabel('Message');
  await message.fill('/skill');
  await expect(page.getByTestId('slash-suggestion').first()).toContainText('/skill name');
  await page.keyboard.press('Tab');
  await expect(message).toHaveValue('/skill ');
});

test('mock harness SUBMITS /skill code-review on Enter and runs the skill', async ({ page }) => {
  await page.goto(harnessURL());

  const message = page.getByLabel('Message');
  // The command's OWN documented example must submit on Enter — not re-complete to a bare `/skill `.
  await message.fill('/skill code-review');
  // Once a full argument is typed the slash popup must be gone (so Enter submits, not re-accepts).
  await expect(page.getByTestId('slash-suggestions')).toHaveCount(0);
  await page.keyboard.press('Enter');

  // The turn ran: the composer cleared, and the skill was loaded + followed.
  await expect(message).toHaveValue('');
  await expect(page.getByTestId('tool-card-title').last()).toHaveText('host.skill.load');
  await expect(page.getByTestId('tool-card-input').last()).toContainText('"name": "code-review"');
  await expect(page.getByTestId('message').last()).toContainText('Loaded the code-review skill');
});
