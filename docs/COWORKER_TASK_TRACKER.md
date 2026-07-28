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
- `browserAuthenticatedWorkflowSmoke` runs a login-like workspace page through the visible
  browser-session path: it types a workspace key, clicks Sign in, and proves script output plus live
  DOM inspection preserve the signed-in workspace state.
- The smoke presenter only exposes a visible session after `openBrowserSession()`, so ordinary preview
  inspection still exercises the snapshot fallback path and the workflow smoke exercises the explicit
  visible-session path.
- This upgrades browser/SaaS evidence from first-open routing to stateful browser action routing across
  CRM-like, shared-sheet-like, and authenticated-session page shapes. Keep real SaaS rows gated until
  a signed-in packaged-app smoke proves equivalent interaction on a live SaaS surface.

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
- The native desktop smoke now records `scheduledCoworkerSmoke`, installing a due recurring coworker
  automation, running it through `QuillCodeDesktopAutomationCoordinator`, verifying the follow-up
  scheduled thread contains the original task, checking recurrence run state, and confirming the
  desktop automation notifier receives exactly one task-specific report.

The remaining scheduling evidence gap is packaged-app smoke that observes the real OS notification
banner/action and visible automation management surface together.

## Packaged Scheduling Evidence Slice

Packaged macOS smoke now preserves explicit scheduled-coworker release evidence:

- The packaged direct-executable smoke and the Launch Services smoke must both include identical
  `scheduledCoworkerSmoke` reports.
- `packaged-scheduled-coworker.json` records the recurring task, schedule, notification report title,
  one delivered automation report, follow-up scheduled thread evidence, recurrence state, and visible
  Automations surface.
- This makes the `.app` packaging boundary fail CI if scheduled coworker automation evidence is lost
  in either packaged launch path.

The remaining scheduling evidence gap is narrower: observing the real OS notification banner/action
from the packaged app, rather than only the app-level notification report delivered to the desktop
notifier boundary.

## Multi-File Artifact Smoke Slice

The native desktop smoke now records deterministic multi-file deliverable evidence:

- `multiFileArtifactSmoke` creates two source notes, asks QuillCode to create a team action brief
  from both files, and requires the actual agent/tool loop to dispatch
  `host.file.read`, `host.file.read`, and `host.file.write` in order.
- The smoke verifies `team-action-brief.md` exists in the workspace and contains facts from both
  source files plus a concrete next action, so artifact-generation rows are no longer backed only by
  the older single-file `hello.txt` write/read proof.
- `scripts/native-desktop-smoke.sh` fails if the report loses the source paths, deliverable path,
  exact tool sequence, final answer, or rendered HTML transcript evidence.
- Packaged macOS smoke also preserves `packaged-multi-file-artifact.json`, proving the same
  multi-file artifact evidence survives both direct packaged executable launch and Launch Services
  launch.

This covers the deterministic local-artifact version of multi-file coworker deliverables. Rows that
depend on live SaaS data, proprietary document formats, or a logged-in browser session should remain
gated until a row-specific live or packaged smoke proves the same workflow on that surface.

## Packaged Browser Workflow Evidence Slice

Packaged macOS smoke now preserves browser coworker workflow evidence at the `.app` boundary:

- `packaged-browser-workflow.json` validates both `browserWorkflowSmoke` and
  `browserSpreadsheetWorkflowSmoke` plus `browserAuthenticatedWorkflowSmoke` from the direct
  packaged executable and Launch Services runs.
- The manifest proves canonical browser tools keep non-empty arguments through packaging:
  `host.browser.type`, `host.browser.click`, `host.browser.script`, and `host.browser.inspect`.
- The CRM-like smoke proves typed status, save click state, script-read state, and live-DOM inspection.
- The shared-sheet-like smoke proves cell editing, done-state click, script-read state, and live-DOM
  inspection.
- The authenticated-session smoke proves typed sign-in state, account-state click state, script-read
  state, and live-DOM inspection.
- The validator compares semantic evidence rather than absolute temp paths, so it fails on workflow
  drift without being brittle across packaged launch roots.

This moves the browser/SaaS coworker bucket from native-only evidence to packaged-app release
evidence. The live SaaS rows still stay gated until QuillCode proves the same path against a signed-in
SaaS surface with Computer Use/browser session evidence.

## Optional Live SaaS Evidence Slice

QuillCode now has a fail-closed manual evidence gate for real signed-in SaaS sessions:

- `scripts/live-saas-smoke.sh <evidence.json> [manifest.json]` validates captured live SaaS evidence
  through `native-click-probe-contracts.py live-saas`.
- The evidence must include `catalogTaskIDs`, the exact spreadsheet row IDs this run proves, so a
  manifest can graduate only specific coworker rows instead of a vague capability bucket.
- The evidence must prove `accountState: signed-in`, use an HTTPS SaaS URL, include
  `host.browser.open` plus `host.browser.inspect`, include at least one browser action or Computer Use
  action, and report a `Live DOM snapshot`.
- If Computer Use is included, the evidence must include `host.computer.screenshot`, a foreground app,
  and an existing screenshot artifact flag.
- The validator rejects common captured secrets such as TrustedRouter/QuillCloud keys, private keys,
  and `password`/`token`/`secret` fields before writing a manifest.

This does not make live SaaS rows covered by itself; it gives those rows a durable acceptance contract.
When a signed-in Salesforce/HubSpot/Google Sheets/etc. workflow is run manually or in a secure
credentialed environment, the resulting `live-saas-manifest.json` is the evidence to attach before
graduating each listed `catalogTaskIDs` row.

Multiple validated live SaaS manifests can be rolled up with:

```bash
scripts/native-click-probe-contracts.py coworker-catalog \
  path/to/live-saas-manifest-1.json \
  path/to/live-saas-manifest-2.json \
  --output path/to/coworker-coverage.json
```

The coverage summary records `provenTaskIDs`, `pendingTaskIDs`, and `evidenceByTaskID` for the full
1-206 catalog range, so spreadsheet updates can be reviewed from row-linked evidence rather than
manual memory.

## Packaged Computer Use Evidence Slice

Packaged macOS smoke now preserves explicit Computer Use setup/status evidence:

- `packaged-computer-use.json` validates that the direct packaged executable and Launch Services
  smoke each expose a recognized top-bar Computer Use status label. The labels may differ because
  macOS grants Screen Recording and Accessibility permissions per app identity.
- The packaged window surface must expose Computer Use setup, Screen Recording settings,
  Accessibility settings, and refresh commands.
- The packaged click-probe manifest and Accessibility frame manifest must contain command contracts
  for those Computer Use commands, so the release artifact proves they are visible/routable at the
  package boundary.

This is not yet a live SaaS or arbitrary-app-control proof. It makes the Computer Use entry points
explicit in release artifacts and leaves action dispatch plus real signed-in SaaS control as the next
validation layers for those catalog rows.

## Packaged Computer Use Action Smoke Slice

Packaged macOS smoke now preserves deterministic Computer Use action evidence:

- `computerUseActionSmoke` runs the real `ComputerUseToolExecutor` against the permission-granted
  backend path and records `host.computer.screenshot`, `host.computer.click`,
  `host.computer.type`, `host.computer.scroll`, `host.computer.move`, and `host.computer.key`.
- The smoke requires non-empty canonical arguments for every input action, verifies the recorded
  click/type/scroll/move/key sequence, writes a screenshot artifact, and preserves foreground-app
  plus accessibility-summary metadata from the screenshot result.
- `packaged-computer-use-action.json` validates that direct packaged executable launch and Launch
  Services launch have identical semantic action evidence, while allowing temporary screenshot
  artifact paths to differ.

This proves Computer Use action routing survives the packaged app boundary. The live SaaS rows still
stay gated until QuillCode drives a signed-in browser/app surface with equivalent preserved evidence.
