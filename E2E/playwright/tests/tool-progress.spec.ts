import { test, expect } from '@playwright/test';
import { harnessURL, sendComposerPrompt } from './harness-helpers';

test('MCP calls surface live progress and clear it at the terminal result', async ({ page }) => {
  await page.goto(harnessURL());
  await page.evaluate(() => {
    (window as typeof window & { __quillCodeMCPProgressDelayMS?: number })
      .__quillCodeMCPProgressDelayMS = 2_000;
  });

  await sendComposerPrompt(page, 'stream MCP progress');

  const card = page.getByTestId('tool-card').filter({ hasText: 'host.mcp.call' });
  await expect(card).toHaveAttribute('data-status', 'running');
  await expect(card.getByTestId('tool-card-subtitle')).toHaveText('Indexing documentation');
  const progress = card.getByTestId('tool-card-progress');
  await expect(progress).toHaveAttribute('role', 'progressbar');
  await expect(progress).toHaveAttribute('aria-label', 'Indexing documentation');
  await expect(progress).toHaveAttribute('aria-valuenow', '42');
  await expect(card.getByTestId('tool-card-progress-percent')).toHaveText('42%');

  await expect(card).toHaveAttribute('data-status', 'done', { timeout: 4_000 });
  await expect(card.getByTestId('tool-card-progress')).toHaveCount(0);
  await expect(card.getByTestId('tool-card-output')).toContainText('Indexed 12 documents.');
  await expect(page.getByTestId('message').last()).toContainText('Indexed 12 documents');
});

test('indeterminate MCP progress remains accessible without a fabricated percentage', async ({ page }) => {
  await page.goto(harnessURL());

  await page.evaluate(() => {
    const harness = window as typeof window & {
      addToolCard: (card: Record<string, unknown>) => Record<string, unknown>;
      updateToolCardProgress: (
        card: Record<string, unknown>,
        progress: Record<string, unknown>
      ) => boolean;
      render: () => void;
    };
    const card = harness.addToolCard({
      title: 'host.mcp.call',
      subtitle: 'Running',
      status: 'running',
      inputJSON: JSON.stringify({ serverID: 'docs', toolName: 'connect' })
    });
    harness.updateToolCardProgress(card, { completed: 1, message: 'Connecting to docs' });
    harness.render();
  });

  const progress = page.getByTestId('tool-card-progress');
  await expect(progress).toHaveClass(/indeterminate/);
  await expect(progress).toHaveAttribute('aria-label', 'Connecting to docs');
  await expect(progress).not.toHaveAttribute('aria-valuenow', /.+/);
  await expect(page.getByTestId('tool-card-progress-percent')).toHaveCount(0);
});
