import { expect, type Page } from '@playwright/test';

const HORIZONTAL_OVERFLOW_TOLERANCE = 1;

type HorizontalOverflowIssue = {
  className: string;
  left: number;
  right: number;
  tag: string;
  testid: string | null;
  text: string;
  width: number;
};

export async function expectNoHorizontalOverflow(page: Page, label: string) {
  const overflow = await horizontalOverflowIssues(page);

  expect(overflow, `${label} should not clip horizontally`).toEqual([]);
}

async function horizontalOverflowIssues(page: Page): Promise<HorizontalOverflowIssue[]> {
  return page.evaluate((tolerance) => {
    const viewportWidth = document.documentElement.clientWidth;
    return Array.from(document.querySelectorAll('body *'))
      .map((element) => {
        const rect = element.getBoundingClientRect();
        return {
          tag: element.tagName,
          testid: element.getAttribute('data-testid'),
          className: String(element.className || ''),
          left: rect.left,
          right: rect.right,
          width: rect.width,
          text: (element.textContent || '').trim().slice(0, 80)
        };
      })
      .filter((rect) => (
        rect.width > 0
        && (rect.left < -tolerance || rect.right > viewportWidth + tolerance)
      ));
  }, HORIZONTAL_OVERFLOW_TOLERANCE);
}
