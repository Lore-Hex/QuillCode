import { test, expect, type Page } from '@playwright/test';
import { harnessURL } from './harness-helpers';

// Belt-and-suspenders DOM smoke for the streaming follow-scroll contract fixed natively in PR #1251
// (QuillCodeTranscriptView + TranscriptScrollFollow). The native pure-function tests can't exercise
// live handler interleaving, so this drives the harness's real DOM: the transcript must keep
// following an at-bottom reader through rapid large chunks, and must surface a "Jump to latest" chip
// (never yank) once the reader has genuinely scrolled up. The harness follow logic mirrors the native
// geometric rule: content growth (scrollHeight change) never un-pins; only a user scroll move does.
//
// The harness scrolls the WINDOW (its workspace is min-height:100vh, so a tall transcript overflows
// the page), so the assertions read window scroll — the harness's actual scroll container.

const BOTTOM_SLACK = 24; // matches the harness TRANSCRIPT_BOTTOM_THRESHOLD

test.use({ viewport: { width: 1024, height: 600 } });

// One large assistant "chunk", injected via the harness test hook + a real render() so the follow
// decision is re-evaluated exactly as it would be on a streamed chunk.
async function appendChunk(page: Page, tag: string): Promise<void> {
  const text = `${tag} ` + 'lorem ipsum dolor sit amet consectetur adipiscing elit '.repeat(30);
  await page.evaluate(
    (t) => (window as unknown as { __harnessAppendAssistantChunk: (s: string) => void }).__harnessAppendAssistantChunk(t),
    text
  );
}

async function windowMetrics(page: Page) {
  return page.evaluate(() => ({
    scrollY: window.scrollY,
    maxScrollY: Math.max(0, document.documentElement.scrollHeight - window.innerHeight)
  }));
}

function isAtBottom(m: { scrollY: number; maxScrollY: number }): boolean {
  return m.scrollY >= m.maxScrollY - BOTTOM_SLACK;
}

async function seedTallTranscript(page: Page, chunks: number): Promise<void> {
  await page.goto(harnessURL());
  for (let i = 0; i < chunks; i++) await appendChunk(page, `seed-${i}`);
  const m = await windowMetrics(page);
  // The whole point requires an overflowing, scrollable transcript.
  expect(m.maxScrollY, 'seeded transcript should overflow the viewport').toBeGreaterThan(80);
}

test('follow-scroll: stays pinned to the bottom through rapid large chunks, no Jump chip', async ({ page }) => {
  await seedTallTranscript(page, 5);

  // Start at the bottom, no chip.
  expect(isAtBottom(await windowMetrics(page)), 'seeded transcript should rest at the bottom').toBe(true);
  await expect(page.getByTestId('jump-to-latest')).toHaveCount(0);

  // Two LARGE chunks in quick succession — the native follow-animation window where the sentinel gap
  // briefly exceeds the threshold. An at-bottom reader must keep being followed.
  await appendChunk(page, 'chunk-a');
  await appendChunk(page, 'chunk-b');

  expect(isAtBottom(await windowMetrics(page)), 'reader at the bottom must keep following large chunks').toBe(true);
  await expect(page.getByTestId('jump-to-latest')).toHaveCount(0);
});

test('follow-scroll: a user scroll-up surfaces the Jump chip and stops following; tapping re-pins', async ({ page }) => {
  await seedTallTranscript(page, 6);

  // No chip while pinned.
  await expect(page.getByTestId('jump-to-latest')).toHaveCount(0);

  // The reader scrolls up (a genuine scrollY move, distinct from content growth).
  await page.evaluate(() => {
    window.scrollTo(0, 0);
    window.dispatchEvent(new Event('scroll'));
  });
  const chip = page.getByTestId('jump-to-latest');
  await expect(chip, 'scrolling up during a run surfaces the Jump to latest chip').toBeVisible();

  // A chunk arrives mid-stream: the scrolled-up reader must NOT be yanked down, and the chip stays.
  await appendChunk(page, 'mid-stream');
  expect(isAtBottom(await windowMetrics(page)), 'a scrolled-up reader must not be followed to the bottom').toBe(false);
  await expect(chip, 'the chip stays while the reader is behind').toBeVisible();

  // Tapping the chip re-pins to the bottom and dismisses it.
  await chip.click();
  expect(isAtBottom(await windowMetrics(page)), 'tapping Jump to latest returns to the bottom').toBe(true);
  await expect(page.getByTestId('jump-to-latest')).toHaveCount(0);

  // Following resumes for the now-pinned reader.
  await appendChunk(page, 'after-jump');
  expect(isAtBottom(await windowMetrics(page)), 'following resumes after re-pinning').toBe(true);
});
