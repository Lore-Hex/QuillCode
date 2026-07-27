# Office Coworker Task Tracker

Canonical catalog:
https://docs.google.com/spreadsheets/d/1uq8uYGwoAxdwPcVn11nysjoozZjKY4acYZNVw-Hu5LM/edit?gid=0#gid=0

The sheet is the product-facing catalog for office coworker tasks QuillCode should handle. Keep it
grounded in verified QuillCode evidence, not intention.

## Sheet Tracking Columns

On 2026-07-27 the sheet gained formula-backed QuillCode tracking columns:

| Column | Header | Purpose |
| --- | --- | --- |
| K | QuillCode coverage | Current QuillCode coverage/gap classification derived from the row status. |
| L | QuillCode evidence | Existing analogue evidence for covered rows, or the repo evidence requirement for gaps. |
| M | Next QuillCode gap | Next implementation/smoke category derived from `Capability needed`. |
| N | Last QuillCode review | Last date this automated tracking view was refreshed. |

Do not mark a row as covered until a current QuillCode source, unit test, functional test, E2E
scenario, smoke result, or documented runtime proof covers that row's full user-facing task.

## Current Gap Buckets

The catalog currently maps to these implementation buckets:

| Bucket | QuillCode proof expected |
| --- | --- |
| One-turn shell/file execution smoke | The agent emits a tool action immediately, with non-empty canonical arguments, and verifies requested files. |
| Multi-file artifact/read-write smoke | The agent reads multiple source files, writes the requested deliverable, and renders or previews the artifact. |
| Browser pane + Computer Use live SaaS smoke | The browser/computer-use path can inspect or act on a signed-in SaaS surface and preserve evidence. |
| Capability-specific QuillCode smoke | A row-specific tool path exists and is verified before the row moves to covered. |

## First Implementation Slice

This branch hardens the immediate-action path for office wording from the catalog:

- Compact prompt guidance treats inventory, cleanup, summary, conversion, merge, drafting,
  extraction, charting, standardization, highlighting, and SaaS maintenance as real work requests.
- The promised-work guard now recognizes office verbs such as `inventory`, `standardize`, `chart`,
  `draft`, `pull`, and `highlight`, so a bare "I'll do it" answer is corrected into a tool action.
- Tests cover representative office-coworker future-tense failures.

Next slices should turn the spreadsheet's `Browser pane` rows into focused Playwright/native smoke
cases using mock browser/Computer Use backends, then graduate rows by updating the sheet's Status and
Evidence columns only after those smokes pass.
