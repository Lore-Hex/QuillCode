# Office Coworker Task Tracker

Canonical catalog:
https://docs.google.com/spreadsheets/d/1uq8uYGwoAxdwPcVn11nysjoozZjKY4acYZNVw-Hu5LM/edit?gid=0#gid=0

The sheet is the product-facing catalog for office coworker tasks QuillCode should handle. Keep it
grounded in verified QuillCode evidence, not intention.

## 2026-08-06 Founder Workflow Expansion

The canonical sheet now contains 310 task rows. Rows #211 through #310 add 100 YC-style founder
workflows spanning customer discovery, founder sales, product and roadmap, launch and growth,
fundraising, finance and runway, hiring and team, investor and board updates, operations and
compliance, and pricing and competitive intelligence. The additions are reproducible from
`scripts/founder-task-catalog.py`; `--check` validates the exact IDs, required columns, unique task
prompts, and ten-task category balance before the rows are written to the sheet.

`docs/coworker-task-catalog.json` is the normalized, checked-in snapshot used by the evidence
validators. Regenerate it from a fresh CSV export with:

```sh
python3 scripts/sync-coworker-catalog.py <sheet.csv> docs/coworker-task-catalog.json \
  --review-date YYYY-MM-DD
```

The new rows remain `Proposed - not yet driven`: adding a realistic task to the catalog is not proof
that QuillCode completed it. The fail-closed row-linked evidence gates continue to decide coverage.

## 2026-08-05 Full Catalog Audit

The audit began with 210 task rows, including CRM rows #207 through #210.

The catalog rollup is fail-closed. Source-sheet statuses such as `Verified end-to-end`, and
QuillCode labels based on capability analogues, are context only. A task is proven only when a
row-linked packaged, live SaaS, live app Computer Use, or notification-observation manifest passes
its validator. The Markdown audit lists every current row, including the exact next gap for every
pending row, rather than rendering only the rows that already passed.

### Five Whys: Catalog Count Drift

1. Why did rows #207 through #210 fail validation? The validators rejected every ID above 206.
2. Why did they reject valid sheet rows? The maximum catalog ID was a Python constant.
3. Why was the constant stale? The sheet was the only task source of truth and had no checked-in,
   machine-readable counterpart.
4. Why did tests not catch the drift? A regression test explicitly asserted that row #207 was
   invalid, so the stale behavior looked correct.
5. Why could documentation and code disagree? The release gate had no catalog-sync boundary or
   content hash.

Root fixes: normalize the live export into `docs/coworker-task-catalog.json`, derive bounds and row
metadata from that snapshot, validate contiguous IDs and row count, preserve the source SHA-256,
accept rows #207 through #210, and reject the next unknown row (#211).

### Five Whys: Analogue Coverage Looked Like Task Proof

1. Why did many sheet rows look covered without executable evidence? Coverage labels included core
   tool analogues.
2. Why were analogues easy to mistake for task completion? The rollup output only listed proven
   rows and did not show the untested catalog rows beside them.
3. Why did row-specific UI evidence stop at #73? New examples were hand-coded in the desktop mock
   runner and each required a matching mock-model branch.
4. Why did that not scale to the whole catalog? The catalog was not data-driven and external-account
   prerequisites were not represented in one audit.
5. Why is it unsafe to auto-green the remaining rows? Browser/SaaS, confidential-data, and native
   notification tasks require signed-in accounts, supplied fixtures, or visible OS evidence that a
   deterministic mock cannot honestly provide.

Root fixes: emit a full-catalog audit with `proven` or `pending` per task; keep source status separate from
QuillCode evidence; show the row's exact next gate; and continue rejecting credentialed or
consequential claims without before/after evidence. Packaged row-linked evidence currently proves
rows #15 through #73. Remaining rows are explicit work, not implied coverage.

### Five Whys: First-Run UI Exposed an Internal Callback

1. Why did onboarding show `http://localhost:3000/callback`? The view rendered the OAuth callback
   value stored for sign-in plumbing.
2. Why was plumbing treated as user copy? The prompt model did not distinguish action state from
   presentation.
3. Why was office-coworker positioning unclear? The copy still said `start coding`.
4. Why did UI smoke pass anyway? Pixel and accessibility checks proved a usable, nonblank window,
   not product-language quality.
5. Why could the issue reach the packaged app? There was no copy guard against coding language or
   localhost details on the first-run surface.

Root fixes: retain the callback only as action state, remove it from the rendered view, add a secure
browser-sign-in caption, describe files/research/office tools, update the three-step onboarding flow,
and test that first-run copy contains neither `coding` nor `localhost`.

### Five Whys: Doctor Reported a False Provider Failure

1. Why did `quill-code doctor` report HTTP 404 while the native UI could complete a live request?
   The reachability probe called the inference base URL's `/models` route.
2. Why did that route return 404? The inference plane intentionally does not expose the model
   catalog at that path.
3. Why did the catalog UI still work? Model discovery uses a separate public control-plane catalog
   and fallback data, while `doctor` evolved independently.
4. Why did tests not catch the wrong request? They stubbed status classifications without asserting
   the live probe's URL and authorization header.
5. Why could two provider contracts drift? Reachability was described as model discovery instead of
   the gateway availability check it actually needed to perform.

Root fixes: probe the gateway's credential-free `/attestation` contract, add an exact request-shape
regression test proving no authorization header or URL secret is sent, and keep gateway reachability,
configured-credential presence, and paid inference validation as separate facts. The corrected key
was verified through the packaged native UI with an exact-reply live model turn; `doctor` stays
non-billable and no longer claims to validate credentials through an unsupported endpoint.

### Five Whys: Search Opened Without Owning Keyboard Focus

1. Why did packaged native smoke see Search but no focused search input? A preceding focus-owning
   surface could finish its AppKit dismissal after Search made its initial focus request.
2. Why could the earlier surface win after Search was visible? Internal Search routes changed the
   presentation binding before synchronously revoking the underlying composer's `FocusState`.
3. Why did Search's 50 ms retry not settle the race? The overlay transition and AppKit popover
   dismissal can outlive that fixed delay under a loaded packaged run.
4. Why did the issue reproduce only in the full interaction sequence? Opening Search manually from a
   settled window omitted the prior popover/modal teardown that the complete activation suite creates.
5. Why did source tests miss it? They checked for a focus request and eventual composer release, but
   not pre-presentation focus ownership or a cancellable request spanning transition completion.

Root fixes: internal routes now revoke composer focus before presenting Search; external
menu/controller bindings retain the presentation-change safety release; model-driven composer-focus
tokens remain suppressed while Search is open; and Search owns a bounded, cancellable focus task that
reasserts focus after the overlay/popover transition window. The source gate covers both ownership
rules, while packaged native smoke proves the field is focused, accepts a reversible AXValue edit, and
clears it before continuing through the remaining workflows.

### Five Whys: Launch Services Stalled Before Render Smoke

1. Why did the packaged Launch Services smoke produce no report? App initialization blocked before
   the smoke runner task was scheduled.
2. Why did initialization block? It constructed the normal desktop controller and synchronously
   refreshed the selected project's file-mention index.
3. Why was that index scanning a huge filesystem tree? The controller used the process working
   directory as its default project, and Launch Services can start GUI apps at `/`.
4. Why was a normal controller constructed for an isolated render smoke? Render-smoke arguments
   were parsed only after `QuillCodeDesktopController()` had completed, unlike window smoke.
5. Why did existing tests not catch the startup ordering defect? They tested request parsing and the
   smoke runner independently, but never asserted the controller root chosen before runner startup.

Root fixes: parse render-smoke arguments before constructing any normal controller, initialize its
placeholder UI from the smoke request's isolated state and workspace roots, and resolve normal GUI
startup away from `/` or the user's entire home into a dedicated `Documents/QuillCode Workspace`
directory. Regression tests now prove both smoke isolation and safe Launch Services root resolution.

### Five Whys: Signed-In App Stalled Before Its First Window

1. Why did Computer Use time out while inspecting the normally launched app? The first window never
   completed initialization.
2. Why did window initialization not complete? The main actor was synchronously scanning the
   persisted selected project to build file-mention suggestions.
3. Why is that unsafe even though the current package root normally indexes in under 100 ms?
   Directory enumeration is filesystem I/O with unbounded per-entry latency; a slow volume, provider,
   permission check, or unavailable path can block the UI regardless of the usual repository timing.
4. Why did packaged Launch Services smoke pass after the isolated-smoke fix? That smoke uses isolated
   app state and a controlled workspace, so it does not exercise the user's persisted selected project.
5. Why did existing file-index tests not catch the responsiveness defect? They asserted traversal,
   exclusions, ordering, and caps, but not main-actor responsiveness, cancellation, or stale-result
   handling when a project changes during a scan.

Root fixes: file-mention indexing now runs in a cancellable utility-priority task, superseded scans are
cancelled, and generation plus active-root guards prevent stale results from replacing the current
project's index. Completion notifies the desktop controller to refresh the UI. Regression coverage
injects a deliberately slow 250 ms index builder and requires project selection to return in under
100 ms, then verifies the eventual result; a package-root timing check separately guards pathological
traversal regressions without treating normal filesystem speed as a UI-thread guarantee.

### Five Whys: Project Context Still Stalled Startup After File Indexing Moved

1. Why did the signed-in app still fail to expose a window after file-mention indexing became
   asynchronous? A second filesystem scan began later in the same main-actor initialization path.
2. Why was there a second scan? `QuillCodeWorkspaceBootstrap.makeModel()` synchronously refreshed
   the persisted project's instructions, local actions, hooks, plugins, extensions, and memories.
3. Why could that refresh block indefinitely? Instruction discovery recursively enumerates as many
   as 400 directories, and any filesystem entry can wait on a slow or unavailable volume even though
   the scan has count and byte bounds.
4. Why did the file-indexing fix not solve this scan too? File mentions and project context have
   separate loaders and lifecycle ownership; removing one synchronous traversal merely exposed the
   next blocked frame in the sampled startup stack.
5. Why did tests and packaged smoke miss the layered defect? Tests used small temporary projects and
   asserted metadata correctness, while packaged smoke used isolated state; neither injected slow
   project metadata nor required normal persisted-state bootstrap to return promptly.

Root fixes: bootstrap no longer performs project-context freshness work before returning the model.
The desktop schedules a cancellable detached utility task after initial state is publishable, and
generation, selected-project, remote/local, and standardized-root guards reject stale results.
Instruction and metadata loaders observe cancellation between bounded operations. A deliberately slow
250 ms loader must return control to the main actor in under 100 ms and eventually publish its result;
a second regression switches projects mid-scan and proves the late old result is discarded. Explicit
user-requested context refresh remains synchronous so its completion semantics do not silently change.

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

- Due-run reports for scheduled coworker tasks use "Quill Cowork scheduled task ready" instead of the
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
notifier boundary. `scripts/scheduled-notification-observation-template.sh <output.json>
<catalog-task-id> [catalog-task-id ...]` writes the row-linked capture skeleton, and
`scripts/scheduled-notification-observation-smoke.sh <evidence.json> [manifest.json]` validates the
completed redacted native observation capture. The evidence links back to the packaged
scheduled-coworker manifest, proves the `Quill Cowork scheduled task ready` notification was visible,
proves the original task text was visible, proves the Open follow-up action was observed and opened
the scheduled thread, carries exact `catalogTaskIDs`, and rejects raw prompts or captured secrets.
`scripts/native-click-probe-contracts.py coworker-catalog ... --output coworker-coverage.json`
accepts these manifests alongside live SaaS manifests, so scheduling rows can graduate only when a
real captured observation manifest is tied to the corresponding spreadsheet row IDs.

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

## Packaged Multi-File Coworker Evidence Slice

Packaged macOS smoke now preserves row-linked multi-file coworker evidence:

- `multiFileArtifactSmoke.catalogCases` includes catalog row #69, All-Hands Email, row #70,
  Analyst Synthesis, row #71, Bulk Rename, row #72, Capacity Planning, and row #73,
  Compliance Audit.
- The row #69 smoke creates `org-changes.pptx` plus `reorg-qa/hardest-questions.md`, asks QuillCode
  to draft the CEO all-hands email from those sources, and requires the desktop agent/tool loop to
  dispatch `host.file.read`, `host.file.read`, and `host.file.write` in order.
- The smoke verifies `ceo-reorg-all-hands-email.md` preserves the reorg announcement, transition
  dates, and answers to all eight hard questions before the row can count as covered.
- The row #70 smoke creates three analyst-report sources under `analyst-reports`, asks QuillCode to
  pull key Gartner and Forrester claims and flag contradictions, and requires the desktop agent/tool
  loop to dispatch three `host.file.read` calls followed by `host.file.write`.
- The smoke verifies `analyst-claims-contradictions.md` preserves Gartner claims, Forrester claims,
  contradictions across the reports, and recommended positioning before the row can count as covered.
- The row #71 smoke creates invoice PDF fixtures under `Documents/Invoices`, asks QuillCode to
  rename every PDF to `YYYY-MM-DD_Vendor_Amount.pdf` based on invoice contents and leave an undo
  log, and requires the desktop agent/tool loop to dispatch two `host.file.read` calls followed by
  `host.shell.run`.
- The smoke verifies the original invoice PDFs were renamed to
  `2026-07-03_Acme_1542.10.pdf` and `2026-07-09_Northwind_880.00.pdf`, and that
  `Documents/Invoices/invoice-rename-undo.csv` maps each old path to the new path before the row can
  count as covered.
- The row #72 smoke creates `allocations.csv` plus three project plans under `project-plans`, asks
  QuillCode to find anyone booked over 100% and propose named swaps, and requires the desktop
  agent/tool loop to dispatch four `host.file.read` calls followed by `host.file.write`.
- The smoke verifies `capacity-rebalance.md` identifies Ana and Dev as overbooked, proposes named
  swaps to Eli and Bo, preserves the Atlas launch-critical constraint, and brings the plan to
  at-or-under-capacity before the row can count as covered.
- The row #73 smoke creates subcontractor COI fixtures under `coi-pdfs`, asks QuillCode to pull
  carrier, policy number, limits, and expiry, and requires the desktop agent/tool loop to dispatch
  three `host.file.read` calls followed by `host.file.write`.
- The smoke verifies `coi-compliance-audit.csv` extracts carrier and policy data, preserves limits
  and expiry dates, flags Northwind Plumbing as under the $1M limit, and flags Zenith Roofing as
  expiring within 60 days before the row can count as covered.
- `packaged-multi-file-artifact.json` now carries the canonical spreadsheet URL and exact
  `catalogTaskIDs: [69, 70, 71, 72, 73]`, and the coworker coverage rollup accepts it beside packaged
  one-turn, live SaaS, live app Computer Use, and scheduled notification evidence.

## Packaged One-Turn Coworker Evidence Slice

Packaged macOS smoke now preserves task-specific one-turn office coworker evidence:

- `oneTurnCoworkerSmoke` drives representative catalog rows #15, #16, #17, #18, #19, #20, #21, #22, #23, #24, #25, #26, #27, #28, #29, #30, #31, #32, #33, #34, #35, #36, #37, #38, #39, #40, #41, #42, #43, #44, #45, #46, #47, #48, #49, #50, #51, #52, #53, #54, #55, #56, #57, #58, #59, #60, #61, #62, #63, #64, #65, #66, #67, and #68 through the actual
  desktop agent/tool loop. `multiFileArtifactSmoke.catalogCases` drives rows #69 and #70 through the
  same desktop agent/tool loop.
- Row #15 proves a clear file-write request creates `launch-announcement.md` with the requested
  customer-comms text through `host.file.write`.
- Row #16 proves an analysis-style shell task runs with non-empty `host.shell.run` arguments and
  creates `signup-slice.csv`.
- Row #17 proves a file-archiving request moves an old client file into a quarterly archive folder
  and writes `archive-readme.md` with an audit trail through `host.shell.run`.
- Row #18 proves a benefits-plan comparison request creates `benefits-plan-matrix.csv` with
  premium, deductible, out-of-pocket max, specialist copay, and RX tier columns through
  `host.shell.run`.
- Row #19 proves a marketing budget model request creates `marketing-budget-model.csv` with
  assumptions, monthly channel spend, and quarterly roll-up rows through `host.shell.run`.
- Row #20 proves a chart-generation request creates a valid 320x200 PNG artifact,
  `regional-revenue-chart.png`, through `host.shell.run`.
- Row #21 proves cohort-retention date math creates `cohort-retention.csv` with retained-after-first-month
  and fastest-decay evidence through `host.shell.run`.
- Row #22 proves a collections drafting request creates `collections-chase-emails.md` with
  aging-bucket-specific chase email rows through `host.shell.run`.
- Row #23 proves column-splitting and parse-error flagging creates `donors-split.csv` with
  `needs_review` evidence through `host.shell.run`.
- Row #24 proves support-reply drafting creates separate ticket reply files under `support-replies/`
  with tone-specific answer text through `host.shell.run`.
- Row #25 proves data validation creates both `newsletter-clean.csv` with E.164 phone normalization
  and `newsletter-bad-rows.csv` with rejected invalid rows through `host.shell.run`.
- Row #26 proves mixed-format membership date normalization creates `members-normalized.csv` with
  ISO `YYYY-MM-DD` date evidence through `host.shell.run`.
- Row #27 proves a customer delay notice creates `delay-notice.md` with the promised new delivery
  date through `host.file.write`.
- Row #28 proves a dependency-mapping request creates a Mermaid diagram artifact through
  `host.file.write`.
- Row #29 proves a document-splitting request creates separate exhibit files plus an exhibit index
  through `host.shell.run`.
- Row #30 proves expense categorization creates a GL-coded CSV plus a review file for uncertain
  rows through `host.shell.run`.
- Row #31 proves finance variance analysis creates `june-variance-pack.csv` with variance
  percentages, over/under status, and explanation text through `host.shell.run`.
- Row #32 proves folder organization creates categorized Downloads folders and a junk review report
  without deleting files through `host.shell.run`.
- Row #33 proves prospect follow-up sequencing creates personalized day-1/day-3/day-7 email files
  under `prospect-followups/` through `host.shell.run`.
- Row #34 proves forecast review creates `forecast-review.md` with optimistic-assumption flags
  against historical close-rate evidence through `host.shell.run`.
- Row #35 proves funnel analysis creates `q2-funnel-summary.md` plus conversion-rate evidence
  with the biggest drop-off and median days per stage through `host.shell.run`.
- Row #36 proves fuzzy vendor deduplication creates a raw-to-standard mapping table and
  standardized vendor master that collapses Acme variants through `host.shell.run`.
- Row #37 proves recruiting drafting creates a Senior Customer Success Manager job description
  with must-haves plus five screening questions through `host.shell.run`.
- Row #38 proves interview scorecard drafting creates a Sales Ops Analyst scorecard with anchored
  ratings and sample questions through `host.shell.run`.
- Row #39 proves newsletter image preparation creates caption-named ready images while preserving
  originals and recording size/width constraints through `host.shell.run`.
- Row #40 proves a KPI dashboard request creates a single-file HTML dashboard,
  `finance-kpi-dashboard.html`, with revenue, churn, headcount, and sparkline evidence through
  `host.shell.run`.
- Row #41 proves launch checklist generation creates a March pricing go-live checklist with legal,
  support, docs, and comms owners and due dates through `host.shell.run`.
- Row #42 proves localization creates Spanish and Portuguese safety-guide files while preserving
  the original heading, warning-box marker, and numbered-step structure through `host.shell.run`.
- Row #43 proves a Q3 content-calendar spreadsheet request creates `q3-content-calendar.csv`
  with campaign theme, content type, title, and owner columns through `host.shell.run`.
- Row #44 proves Zoom transcript cleanup creates `zoom-meeting-notes.md` with a five-bullet
  summary, decisions, owners, and due dates while retaining the raw `zoom-0714.txt` source through
  `host.shell.run`.
- Row #45 proves a meeting recap request creates `board-prep-recap-email.md` with every
  transcript commitment, owner, and due date while retaining the raw `board-prep-call.txt` source
  through `host.shell.run`.
- Row #46 proves a multi-audience maintenance notice request creates enterprise-admin, end-user,
  and status-page versions under the original `maintenance-window-notice.md` source through
  `host.shell.run`.
- Row #47 proves SOW obligation tracking creates `acme-sow-obligations.csv` with chronological
  deliverables, due dates, 14-day reminder dates, and owners while retaining the `Acme-SOW.pdf`
  source through `host.shell.run`.
- Row #48 proves a pivot-style sales summary request creates `sales-pivot-summary.csv`
  with revenue grouped by rep, region, quarter, and top-deal evidence through `host.shell.run`.
- Row #49 proves an ERP migration RACI request creates `erp-migration-raci.csv` from
  `stakeholders.csv` and `phase-plan.md`, preserving responsible, accountable, consulted, and
  informed assignments through `host.shell.run`.
- Row #50 proves invoice reconciliation creates `invoice-reconciliation.csv` from
  `open_invoices.csv` and `november-bank.csv`, preserving unpaid and duplicate-paid invoice evidence
  through `host.shell.run`.
- Row #51 proves redline analysis creates `amendment-redline-impact.csv` from an executed MSA and
  vendor amendment source, preserving changed clauses and plain-English business impact through
  `host.shell.run`.
- Row #52 proves a customer-facing release-notes request creates `release-notes-2026-08.md`
  with grouped feature-area prose through `host.shell.run`.
- Row #53 proves an RFP response request creates `rfp-compliance-matrix.csv` from
  `RFP-2026-DOT.pdf`, preserving shall/must requirements, section numbers, blank owners, and
  workstreams through `host.shell.run`.
- Row #54 proves risk-register generation creates `project-risk-register.csv` from
  `project-charter.pdf`, preserving likelihood, impact, mitigation, and owner columns through
  `host.shell.run`.
- Row #55 proves roadmap drafting creates `roadmap.md` from `Q3-OKRs.docx`, preserving a quarterly
  theme plus dated onboarding, reporting, permissions, and audit-trail milestones through
  `host.shell.run`.
- Row #56 proves sales-proposal drafting creates `northwind-logistics-proposal.md` from
  `discovery-call-notes.md` and `pricing-sheet.xlsx`, preserving scope, timeline, three pricing
  tiers, and assumptions through `host.shell.run`.
- Row #57 proves sales one-pager drafting creates `customer-leave-behind.md` from
  `product-deck-20-slides.pptx` and `approved-pricing.csv`, preserving three proof points, pricing
  tiers, and a short call to action through `host.shell.run`.
- Row #58 proves scanned-document extraction creates `pension-vesting-retirement-table.csv` from
  `pension-plan-1994-scanned.pdf`, preserving the vesting schedule and early-retirement reduction
  factors through `host.shell.run`.
- Row #59 proves support ticket triage creates `zendesk-theme-triage.csv` from `zendesk-export.csv`,
  preserving eight issue themes, ticket volume, average first response time, and ticket examples
  through `host.shell.run`.
- Row #60 proves billing support macro drafting creates `billing-support-macros.md` from
  `existing-macros.md`, preserving six macros with standard and apology variants that follow the
  source tone sample through `host.shell.run`.
- Row #61 proves NPS survey analysis creates `nps-plan-tier-summary.csv` from
  `customer-survey-q2.csv`, preserving plan-tier NPS scores and the five most common detractor
  complaints in `nps-detractor-complaints.md` through `host.shell.run`.
- Row #62 proves task-breakdown planning creates `wbs.xlsx` from `team-roster.csv`, preserving
  phases, owners, and effort estimates for launching self-serve onboarding by October through
  `host.shell.run`.
- Row #63 proves timeline building creates `timeline.xlsx` from `milestones.csv`, preserving
  Gantt-style start dates, end dates, durations, dependencies, and the November 3 launch milestone
  through `host.shell.run`.
- Row #64 proves tone rewriting creates `draft-price-increase-email-rewrite.docx` from
  `draft-price-increase-email.docx`, preserving the exact effective date and grandfathering clause
  while shortening and softening the pricing-change copy through `host.shell.run`.
- Row #65 proves variance analysis creates `variance-analysis.csv` from `budget-fy26.xlsx` and
  `actuals-june.csv`, preserving every over-ten-percent line item with variance percentages and
  plain-English explanation text through `host.shell.run`.
- Row #66 proves version cleanup creates `shared-cleanup-plan.md` plus `Shared/cleanup-audit.csv`,
  deletes generated `.DS_Store` and empty-folder clutter, removes older duplicate-cluster members,
  and preserves the newest retained file through `host.shell.run`.
- Row #67 proves weekly reporting creates `weekly-sales-summary.md` from
  `weekly-sales-2026-W29.csv`, preserving week-over-week change, top-five mover evidence, and an
  anomaly callout through `host.shell.run`.
- Row #68 proves a weekly-review shell task runs with non-empty `host.shell.run` arguments and
  creates `weekly-review.csv`.
- Row #69 proves all-hands reorg email drafting creates `ceo-reorg-all-hands-email.md` from
  `org-changes.pptx` and `reorg-qa/hardest-questions.md`, preserving the reorg details, transition
  dates, and answers to the eight hardest questions through `host.file.read`, `host.file.read`, and
  `host.file.write`.
- Row #70 proves analyst synthesis creates `analyst-claims-contradictions.md` from three reports
  under `analyst-reports`, preserving Gartner claims, Forrester claims, contradictions, and
  recommended framing through three `host.file.read` calls followed by `host.file.write`.
- Row #71 proves bulk invoice renaming reads invoice PDFs under `Documents/Invoices`, renames them
  to date/vendor/amount filenames, removes the original names, and writes
  `Documents/Invoices/invoice-rename-undo.csv` through two `host.file.read` calls followed by
  `host.shell.run`.
- Row #72 proves capacity planning reads `allocations.csv` and three project plans, identifies Ana
  and Dev as overbooked, proposes named swaps to Eli and Bo, and writes `capacity-rebalance.md`
  through four `host.file.read` calls followed by `host.file.write`.
- Row #73 proves compliance auditing reads subcontractor COI PDFs under `coi-pdfs`, extracts carrier,
  policy number, limits, and expiry, flags under-limit and expiring-soon certificates, and writes
  `coi-compliance-audit.csv` through three `host.file.read` calls followed by `host.file.write`.
- `packaged-one-turn-coworker.json` compares direct packaged executable and Launch Services launches,
  recording task IDs, tool sequence, artifact suffixes, artifact assertions, and final answers.
- The manifest carries the canonical spreadsheet URL and exact `catalogTaskIDs`, and
  `scripts/native-click-probe-contracts.py coworker-catalog ... --output coworker-coverage.json`
  accepts it beside live SaaS and scheduled-notification evidence.

Together with packaged one-turn evidence, this moves deterministic row-linked coverage through row
#73. Similar local rows can graduate only when their row ID appears in current smoke or coverage
evidence, or when a stricter row-specific test proves the same tool path. The next multi-file gap is
row #74 from the coworker catalog.

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

- `scripts/live-saas-template.sh <output.json> <catalog-task-id> [catalog-task-id ...]` writes a
  row-linked evidence skeleton with the exact catalog row IDs, required browser evidence,
  optional Computer Use evidence, and the validation command. Optional environment variables
  `QUILLCODE_LIVE_SAAS_SERVICE_NAME`, `QUILLCODE_LIVE_SAAS_TASK_NAME`, and
  `QUILLCODE_LIVE_SAAS_URL` prefill the service/task/URL fields. The generated file is intentionally
  not valid evidence until every `TODO` is replaced by a real signed-in capture.
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

## Optional Live App Computer Use Evidence Slice

QuillCode now also has a fail-closed manual evidence gate for real local app control:

- `scripts/live-app-computer-use-template.sh <output.json> <catalog-task-id> [catalog-task-id ...]`
  writes a row-linked evidence skeleton for arbitrary foreground app tasks. Optional environment
  variables `QUILLCODE_LIVE_APP_NAME` and `QUILLCODE_LIVE_APP_TASK_NAME` prefill the app/task fields.
- `scripts/live-app-computer-use-smoke.sh <evidence.json> [manifest.json]` validates captured
  local-app Computer Use evidence through `native-click-probe-contracts.py live-app-computer-use`.
- The evidence must include exact `catalogTaskIDs`, matching `appName` and `foregroundApplication`,
  `host.computer.screenshot`, at least one click/type/scroll/move/key action, an existing screenshot
  or appshot artifact, visible before/after state evidence, and a completed result visible in the
  after-state or observed elements.
- The validator rejects raw prompts/messages and common captured secrets before writing
  `live-app-computer-use-manifest.json`.
- `scripts/native-click-probe-contracts.py coworker-catalog ... --output coworker-coverage.json`
  accepts these manifests beside live SaaS, scheduled-notification, and packaged one-turn evidence.

This is the acceptance path for local app coworker rows such as spreadsheet cleanup, desktop document
editing, or signed-in native business tools. Rows still remain gated until a row-specific captured
manifest exists; deterministic packaged Computer Use action smoke alone is not enough.

Example capture setup:

```bash
QUILLCODE_LIVE_SAAS_SERVICE_NAME=Salesforce \
QUILLCODE_LIVE_SAAS_TASK_NAME="Update CRM lead status" \
QUILLCODE_LIVE_SAAS_URL=https://example.salesforce.com/lightning/o/Lead/list \
  scripts/live-saas-template.sh /tmp/salesforce-evidence.json 199
```

Multiple validated live SaaS manifests can be rolled up with:

```bash
scripts/native-click-probe-contracts.py coworker-catalog \
  path/to/live-saas-manifest-1.json \
  path/to/live-saas-manifest-2.json \
  path/to/live-app-computer-use-manifest.json \
  --output path/to/coworker-coverage.json \
  --markdown-output path/to/coworker-coverage.md
```

The coverage summary records `provenTaskIDs`, `pendingTaskIDs`, and `evidenceByTaskID` for the full
snapshot-defined catalog range (currently 1-310). The optional Markdown report lists every row,
its proven/pending result, evidence or exact next gap, category, and canonical task,
and source manifest, so spreadsheet updates can be reviewed from row-linked evidence rather than
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
