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

## Browser/SaaS Routing Slice

The next immediate-action gap is browser/SaaS coworker work:

- Terse requests such as "check the Salesforce pipeline at https://..." or "open app.hubspot.com"
  now route directly to `host.browser.open` with the canonical `url` argument instead of waiting for
  a model turn that may say "I'll check..." without acting.
- Simple SaaS navigation prompts without URLs now open the canonical app/login surface for common
  office tools in the catalog, including Salesforce, HubSpot, Google Ads, LinkedIn Campaign Manager,
  Mailchimp, Google Drive/Sheets, Notion, Asana, Concur, Jira/Confluence, Zendesk, and Google
  Analytics.
- Actionful catalog workflows such as adding HubSpot tasks, filling Google Sheets, renaming Drive
  files, merging rows, or correcting stages deliberately stay out of the one-shot preflight path so
  the model can continue with browser/Computer Use tools instead of stopping after a single open.
- Download/save/fetch requests keep the existing bounded `curl` download path, so "download
  LinkedIn.com" still creates a workspace artifact instead of merely opening a browser tab.
- Multi-step browser workflows still go to the model; the preflight only handles a first obvious
  page-open action. Follow-up slices should add focused browser/Computer Use smoke cases for logged-in
  SaaS interaction and only then graduate spreadsheet rows to covered.

## Browser Workflow Smoke Slice

The native desktop smoke now leaves deterministic browser-workflow evidence for a SaaS-like page:

- `browserSmoke` still proves local HTML preview, browser comments, and `host.browser.inspect`
  final-answer rendering.
- `browserWorkflowSmoke` opens a mock CRM page through the visible browser-session path, dispatches
  `host.browser.type`, `host.browser.click`, `host.browser.script`, and `host.browser.inspect`, and
  records the typed status, clicked save selector, script value, live-DOM inspection depth, outline,
  and text snippet in the smoke report.
- `browserSpreadsheetWorkflowSmoke` repeats the same real browser-tool override path on a
  spreadsheet-like launch tracker: it types a launch date into a cell-style input, clicks Mark done,
  and proves the edited row state survives through script output and live DOM inspection. This maps
  more directly to shared-sheet cleanup and tracker-maintenance coworker tasks.
- The smoke presenter only exposes a visible session after `openBrowserSession()`, so ordinary preview
  inspection still exercises the snapshot fallback path and the workflow smoke exercises the explicit
  visible-session path.
- This upgrades browser/SaaS evidence from first-open routing to stateful browser action routing across
  CRM-like and shared-sheet-like page shapes. Keep real SaaS rows gated until a signed-in packaged-app
  smoke proves equivalent interaction on a live SaaS surface.

## Scheduling Coworker Slice

Plain recurring coworker prompts now create real workspace automations without requiring slash syntax:

- Requests such as "Every Monday at 8am, check competitor pricing pages and notify me with a diff"
  parse into a recurring workspace automation when the schedule is explicit and the remaining task
  contains a concrete work verb.
- The task text is persisted on the automation and replayed into the due-run thread, so the scheduled
  run performs the original coworker task instead of a generic workspace check.
- Unsupported or ambiguous schedules fall through to the normal agent path rather than creating a bad
  automation.

This improves the scheduling rows in the coworker catalog. Keep those rows as not fully covered until
there is end-to-end evidence for due-run execution, notification delivery, and visible automation
management in the packaged app.

## Scheduling Notification Proof Slice

Scheduled coworker due-runs now carry task-specific notification evidence:

- Due-run reports for scheduled coworker tasks use "QuillCode scheduled task ready" instead of the
  generic workspace-check title.
- The notification body includes the original task text, so the desktop notification path proves which
  recurring coworker task produced the follow-up thread.
- Tests cover the app-level due-run report and the desktop automation coordinator delivering that
  report through the notifier when automation notifications are enabled.

The remaining scheduling evidence gap is packaged-app smoke that observes the native notification and
visible automation management surface together.
