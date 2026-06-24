# Code Quality Audit

## 2026-06-22 Pass

Overall grade: **A- foundation, B+ product surface maturity**.

The architecture is moving in the right direction: core state is value typed, persistence and runtime adapters are separated, tools use explicit schemas, and SwiftUI plus the Playwright harness render from the same surface contract. The main drag on the grade is file size and feature density in the workspace layer, not a broken abstraction boundary.

## Component Grades

| Component | Grade | Notes |
| --- | --- | --- |
| `QuillCodeCore` | A | Stable value models, focused app-config ownership, focused TrustedRouter default/catalog ownership, canonical IDs, branded display names, and compatibility decoding. Keep future provider/settings behavior out of the general domain model file. |
| `QuillCodeAgent` | A- | Runtime/tool loop is well covered and keeps tool feedback hidden from user transcript surfaces. Next grade step is richer retry/cancellation telemetry. |
| `QuillCodeTools` | A- | Shell/file/git/MCP executors are bounded and testable. Git and MCP files are necessarily dense; keep extracting parsers/policies when behavior grows. |
| `QuillCodeSafety` | A- | Small, explicit policy layer. Needs more production prompt telemetry once live Auto reviewer tuning begins. |
| `QuillCodePersistence` | A | Focused stores, compatibility tests, and clear path ownership. |
| `QuillComputerUseKit` | B+ | Protocol shape is good and macOS adapter is isolated. Linux adapter, app approvals, and visual feedback loops are still parity gaps. |
| `QuillCodeApp` surface contracts | A- | Strong shared surface model and broad tests. Settings, runtime issue, model catalog, top-bar/model contracts, navigation assembly, sidebar/project contracts, command, command palette, review, review-comment planning, tool override composition, remote-project tool execution, context banner, transcript projection, execution-context enrichment, browser location/state transitions, MCP launch/session creation, thread seeding, thread lifecycle transitions, sidebar selection transitions, sidebar bulk action planning, and automation pane assembly now have focused builders; the main remaining risk is `WorkspaceModel`, `WorkspaceSurface`, and `WorkspaceSwiftUIView` continuing to absorb too many responsibilities. |
| Playwright harness | B+ | Valuable parity harness with broad coverage. It intentionally duplicates rendering behavior, so keep it thin and derived from stable surface concepts. |

## File Hotspots

| File | Grade | Next Improvement |
| --- | --- | --- |
| `Sources/QuillCodeApp/WorkspaceModel.swift` | A- | Command parsing, automation records/run drafts, terminal session construction, project registry transitions, context/action lookup, review-comment planning, tool override composition, SSH Remote tool execution, browser location/state transitions, MCP surface state, MCP request parsing, MCP runtime/catalog/launch work, tool-card surface types, execution-context enrichment, thread seeding, thread lifecycle transitions, thread persistence, local command transcript mutation, thread notice mutation, sidebar selection transitions, sidebar bulk action planning, project context refresh, `/status` context assembly, and top-bar state assembly now live in focused helpers; keep extracting pure surface/workflow builders before adding more parity commands. |
| `Sources/QuillCodeApp/WorkspaceSwiftUIView.swift` | A | The shell is now top-bar/sidebar chrome, state, and routing; center-pane layout and workspace sheet presentation live in focused files. Keep future modal families and command workflow rules out of the root shell. |
| `Sources/QuillCodeApp/QuillCodeWorkspaceMainPaneView.swift` | A- | Center-pane layout owns transcript/browser/extensions/memories/terminal/composer/activity composition and runtime issue recovery wiring. Keep workflow decisions in planners and avoid growing this into a second root shell. |
| `Sources/QuillCodeApp/QuillCodeToolCardView.swift` | A- | Native tool-card composition is now separate from reusable controls, artifact previews, and raw detail blocks. Keep future status/action chrome in `QuillCodeToolCardControls.swift` and artifact rendering in `QuillCodeToolArtifactViews.swift`. |
| `Sources/QuillCodeApp/WorkspaceSurface.swift` | A- | Surface assembly is now mostly aggregate payload plus runtime/execution context records. Settings copy/compatibility, runtime issue classification, active context-source selection, model catalog presentation, top-bar/model presentation contracts, project/sidebar navigation assembly, sidebar/project contracts, browser state/presentation contracts, terminal presentation contracts, review presentation contracts, transcript/composer/context presentation contracts, secondary-pane presentation contracts, automation pane command wiring, command construction, command palette ranking, review diff construction, context banner estimation, and transcript message projection are extracted into focused files. Next step is extracting runtime/execution context contracts if their presentation behavior grows. |
| `Sources/QuillCodeApp/WorkspaceHTMLRenderer.swift` | A- | Static HTML harness rendering is still broad, but top-bar HTML delegates to `WorkspaceHTMLTopBarRenderer`, sidebar HTML delegates to `WorkspaceHTMLSidebarRenderer`, tool-card/artifact preview HTML delegates to `WorkspaceHTMLToolCardRenderer`, review pane HTML delegates to `WorkspaceHTMLReviewRenderer`, secondary pane HTML delegates to `WorkspaceHTMLSecondaryPaneRenderer`, browser pane HTML delegates to `WorkspaceHTMLBrowserRenderer`, terminal pane HTML delegates to `WorkspaceHTMLTerminalRenderer`, and shared escaping/context chips live in `WorkspaceHTMLPrimitives`. Next step is extracting another transcript/composer family only when renderer drift appears. |
| `Sources/QuillCodeApp/QuillCodeSidebarView.swift` | A | The native sidebar shell now owns only rail composition, top-level thread header state, primary actions, utility footer, and project/thread component placement. Keep row rendering, row action payloads, and presentation maps in focused sidebar files. |
| `Sources/QuillCodeApp/QuillCodeSidebarThreadListView.swift` | A- | Thread empty state, pinned/recent/archived sections, bulk selection toolbar, row rendering, and selection toggles live together. Split only if row menus or bulk controls grow into independent workflow state. |
| `Sources/QuillCodeApp/QuillCodeProjectListView.swift` | A | Project list, header controls, remote badges, and row action menus live together without leaking into the sidebar shell. |
| `Sources/QuillCodeApp/QuillCodeReviewPaneView.swift` | A | The native review pane shell now owns only review header, file-list placement, and pane chrome. Keep diff row rendering and comment controls in focused review row files. |
| `Sources/QuillCodeApp/QuillCodeReviewFileRowView.swift` | A- | File rows, hunk rows, range-note controls, file/hunk actions, and hunk-to-line composition live together. Split hunk controls only if review workflows grow beyond compact stage/restore/comment actions. |
| `Sources/QuillCodeApp/QuillCodeReviewLineRowView.swift` | A | Line content, marker/background styling, inline comments, and line-note composer live together without expanding the review pane shell. |
| `Sources/quill-code-desktop/QuillCodeDesktopApp.swift` | A- | App scene composition is now small and declarative. Keep it limited to window/menu-bar wiring and root-view routing. |
| `Sources/quill-code-desktop/QuillCodeDesktopController.swift` | A- | Desktop controller is now mostly UI/workspace routing. Pasteboard feedback and project-import resolution now live in focused coordinators; keep future desktop protocol/workflow details out of the controller. |
| `Sources/QuillCodeAgent/Agent.swift` | A- | Good test coverage; keep tool continuation limits and transcript filtering explicit. |
| `Sources/QuillCodeCore/Models.swift` | A | General chat/thread/memory domain models only; app config, automation scheduling, project/workspace records, tool payloads, and TrustedRouter defaults/catalog records now live in focused core files. Watch for persistence, workflow, tool, or provider-specific behavior trying to drift back in. |
| `Sources/QuillCodeCore/AppConfig.swift` | A | App settings, auth mode compatibility, signed-in account metadata, and favorite model normalization live together without pulling UI/runtime dependencies into core. |
| `Sources/QuillCodeCore/AutomationModels.swift` | A | Automation kind/status/schedule records, recurrence semantics, next-run calculation, and display sorting live together without pulling app-layer automation execution into core. |
| `Sources/QuillCodeCore/ProjectModels.swift` | A | Local/SSH project connection parsing, project refs, instructions, local environment actions, and extension manifests live together without pulling chat/thread runtime state into the project model boundary. |
| `Sources/QuillCodeCore/ToolModels.swift` | A | Tool schema records, tool-call redaction, built-in core tool definitions, tool results, and browser/memory tool-output compatibility live together without pulling router/runtime dependencies into core. |
| `Sources/QuillCodeCore/TrustedRouterDefaults.swift` | A | Central source of truth for TrustedRouter IDs, aliases, branded model names, fallback catalog rows, and catalog normalization. |
| `Sources/QuillCodeCore/ModelInfo.swift` | A | Small catalog value records and sort-key semantics with no app/runtime dependency. |

## Changes From This Pass

- Kept `trustedrouter/fast` stable and moved the fallback model to preferred `/synth`/`tr/synth` while preserving `trustedrouter/fusion`, `tr/fusion`, `/fusion`, `fusion-code`, and `/fusion-code` legacy aliases. User-facing model surfaces brand the defaults as **Nike 1.0** and **Prometheus 1.0**.
- Promoted Synth Code (`/synth-code`, `tr/synth-code`) into the bundled Recommended catalog so the preferred code model is visible offline instead of only working as a hidden alias.
- Added explicit catalog-normalization regression coverage so live or persisted legacy Fusion rows dedupe into Prometheus 1.0/Synth Code and do not reappear as user-facing picker rows.
- Centralized the branded default names in `TrustedRouterDefaults`, with tests proving canonical IDs and display names separately.
- Removed dead provider plumbing from model metadata summary generation.
- Refactored model-category construction to compute favorite IDs once and pass a `Set` through option building instead of recomputing favorites for every model.
- Updated the Playwright harness to preserve branded labels after model selection.
- Fixed stale decisions documentation that still described recurring automation as deferred.

## 2026-06-24 Top-Bar State Builder Pass

Overall grade after this slice: **A top-bar state boundary, A behavior preservation, A regression guard**.

`WorkspaceModel` was still assembling live top-bar state inline while also coordinating threads, projects, tools, automations, persistence, and runtime status. The logic was small, but selected-thread/project precedence is central to Codex parity and easy to regress when status or remote-context features grow.

Code quality changes:

- Added `WorkspaceTopBarStateBuilder` for top-bar state derivation from root state.
- Preserved selected-thread model/mode/title precedence, selected-thread project precedence over selected project, and existing Computer Use status.
- Simplified `WorkspaceModel.refreshTopBar` to delegate the state transition.
- Added focused tests for thread-backed state and no-thread project/config fallback state.
- Added a parity gate preventing inline `TopBarState` assembly from returning to `WorkspaceModel`.

Remaining risk:

- `WorkspaceModel` is still large because it is the app coordinator. The next A+ slices should keep extracting project/context refresh, slash-command dispatch, and tool-run orchestration into directly testable helpers.

## 2026-06-24 Native Review Hunk And Action Split

Overall grade after this slice: **A review hunk boundary, A action-button ownership, A regression coverage**.

After the native review row split, `QuillCodeReviewFileRowView.swift` still owned hunk rows, range comment composer state, hunk-to-line composition, and the shared action button. That was a reasonable first extraction, but hunk controls are the next place likely to grow as Codex-style review workflows add richer range notes, hunk staging, keyboard navigation, and action affordances.

What changed:

- Kept `QuillCodeReviewFileRowView.swift` focused on file-level header, hunk-list placement, file notes, and file comments.
- Added focused native files for review hunk rows and review action buttons.
- Preserved existing minimum hit targets, monospaced diff text, tabular numeric labels, and comment composers.
- Strengthened the parity gate so hunk rendering and action-button controls stay out of the root review pane and file-row shell.

Remaining risk:

- Line and range comment composers are still local `@State` views. That is acceptable while comments are lightweight, but richer Codex-style draft persistence or keyboard navigation should move composer state into a focused reducer instead of expanding the row views.

## 2026-06-24 Thread Persistence Helper Pass

Overall grade after this slice: **A thread-persistence boundary, A non-fatal persistence semantics, A regression guard**.

`WorkspaceModel` still directly called `JSONThreadStore` in many workflows and owned the timestamped “mutate thread, update updatedAt, persist” routine. That scattered persistence mechanics through unrelated flows like approvals, review comments, slash commands, tool runs, and lifecycle actions.

Code quality changes:

- Added `WorkspaceThreadPersistence` for best-effort save/delete, one explicit throwing save path, batch save, and timestamped mutation.
- Kept the public `QuillCodeWorkspaceModel` initializer unchanged while bridging its optional `JSONThreadStore` into the helper.
- Replaced direct `threadStore?.save` and `threadStore?.delete` calls with the helper while preserving the existing throwing final-save behavior in `submitComposer`.
- Added focused tests for deterministic mutation timestamps, batch save/delete, and nil-store no-op behavior.
- Added a parity gate preventing direct `JSONThreadStore` save/delete calls from returning to `WorkspaceModel`.

Remaining risk:

- `WorkspaceModel` still explicitly decides when thread persistence should happen. That is acceptable for now because each workflow owns its persistence boundary, but command dispatch and tool-run orchestration remain the next places to extract before calling the app coordinator A+.

## 2026-06-24 Local Command Transcript Appender Pass

Overall grade after this slice: **A local transcript mutation boundary, A slash-command behavior coverage, A regression guard**.

Slash-command transcript copy already lived in focused planners, but `WorkspaceModel` still owned the mutation details for applying those transcripts to a thread: setting the default title, appending the user command message, appending the assistant result, and relying on selected-thread persistence side effects.

Code quality changes:

- Added `WorkspaceLocalCommandTranscriptAppender` for applying local command transcripts to a `ChatThread`.
- Simplified `WorkspaceModel.appendLocalCommandTranscript` so it only ensures a thread exists and delegates the thread mutation.
- Added focused tests proving new-chat title promotion and existing-thread preservation.
- Extended the slash-command parity gate so inline transcript message mutation does not drift back into the coordinator.

Remaining risk:

- Slash-command dispatch itself is still a switch in `WorkspaceModel`. That is acceptable while the branches mostly call focused planners/engines, but a future slice should extract the command-effect dispatcher once more slash commands share workflow mechanics.

## 2026-06-24 Thread Notice Appender Pass

Overall grade after this slice: **A notice mutation boundary, A transcript event coverage, A regression guard**.

`WorkspaceModel` still directly appended lightweight notice events and assistant notice messages. These are small operations, but they affect transcript rendering, activity state, and persistence through `mutateSelectedThread`, so keeping the mutation shape outside the coordinator reduces drift.

Code quality changes:

- Added `WorkspaceThreadNoticeAppender` for notice-only events and assistant notice message/event pairs.
- Simplified `WorkspaceModel.appendNotice` and `appendAssistantNotice` to delegate thread mutation.
- Added focused tests proving notice-only events do not create messages and assistant notices create both message and event records.
- Added a parity gate preventing inline notice/message event mutation from returning to `WorkspaceModel`.

Remaining risk:

- Some specialized event appends still belong to their domain planners (`WorkspaceComposerCancellationPlanner`, memory context updates, tool events). Keep them there; only shared primitive transcript mutation should use this appender.

## 2026-06-24 Status Context Builder Pass

Overall grade after this slice: **A `/status` context boundary, A behavior preservation, A regression guard**.

`WorkspaceModel` still assembled the `/status` command context inline: project label fallback, selected-thread title fallback, selected project/thread instruction precedence, selected-thread versus fallback memory precedence, and top-bar mode/model/status. That made a user-facing diagnostic command depend on coordinator internals instead of a named, testable policy.

Code quality changes:

- Added `WorkspaceStatusContextBuilder` for `/status` context assembly.
- Preserved existing project/thread/top-bar/fallback precedence exactly.
- Simplified `WorkspaceModel.statusText` so it delegates context assembly and formatting separately.
- Added focused tests for selected project/thread state and no-thread fallback state.
- Strengthened the parity gate so inline `/status` context construction does not return to `WorkspaceModel`.

Remaining risk:

- Slash-command dispatch still chooses when `/status` runs inside `WorkspaceModel`. That is acceptable while command branches mostly delegate to focused planners; extract command-effect dispatch only when shared command workflow mechanics grow.

## 2026-06-24 Workspace Main Pane Split

Overall grade after this slice: **A root-shell boundary, A center-pane composition, A regression guard**.

`WorkspaceSwiftUIView` still owned the entire center-pane layout: transcript, browser, extensions, memories, terminal, composer, activity, stop fallback, message-as-draft focus, and runtime issue recovery wiring. That made the root shell harder to scan because it mixed app chrome, sheet state, sidebar row routing, and the live workspace pane stack.

Code quality changes:

- Added `QuillCodeWorkspaceMainPaneView` for transcript/browser/extensions/memories/terminal/composer/activity composition.
- Reduced `WorkspaceSwiftUIView` from 404 lines to 288 lines so it primarily owns top-bar/sidebar chrome, state, sheets, and routing.
- Moved stop fallback, message-as-draft focus, command-ID lookup, and runtime issue recovery wiring into the center-pane view where those controls are rendered.
- Updated parity gates so root shell composition, transcript placement, and runtime issue recovery boundaries stay explicit.

Remaining risk:

- `QuillCodeWorkspaceMainPaneView` is intentionally a composition view. If pane-specific behavior grows, split those rules into focused planners or pane views instead of adding more branching to the main pane.

## 2026-06-24 Native Sidebar Component Split

Overall grade after this slice: **A sidebar shell boundary, A thread-list boundary, A project-list boundary**.

`QuillCodeSidebarView.swift` still combined the left-rail shell with thread list sections, thread rows, bulk-selection controls, project list rows, project row menus, primary navigation, and utility commands. The behavior was correct, but a 456-line file made the native sidebar too easy to regress while tuning Codex-like left-nav density.

Code quality changes:

- Added `QuillCodeSidebarThreadListView` for empty state, pinned/recent/archived sections, bulk-selection controls, thread rows, row menus, and selection-toggle wiring.
- Added `QuillCodeProjectListView` for project header controls, selected project rows, remote badges, and project row menus.
- Reduced `QuillCodeSidebarView.swift` from 456 lines to 171 lines so it mostly owns sidebar rail composition and top-level header/footer placement.
- Updated parity gates so native row rendering and selection-toggle command wiring stay in focused sidebar files while shared command presentation remains consumed by both native SwiftUI and HTML.

Remaining risk:

- `QuillCodeSidebarThreadListView` is the richer of the two new files because it owns both bulk-selection controls and row rendering. Keep it that way while those controls remain compact; split bulk-selection chrome into its own file only if more selection workflows are added.

## 2026-06-24 Native Review Row Split

Overall grade after this slice: **A review pane shell, A file/hunk row boundary, A line-row boundary**.

`QuillCodeReviewPaneView.swift` still owned every native review UI level: pane chrome, file rows, hunk rows, range-note state, diff line rendering, inline comment lists, line-note composer state, and action buttons. It was cohesive by feature, but dense enough that future diff-review work could easily make the shell harder to reason about.

Code quality changes:

- Added `QuillCodeReviewFileRowView` for file rows, hunk rows, file/hunk actions, range-note controls, and hunk-to-line composition.
- Added `QuillCodeReviewLineRowView` for line content, marker/background styling, existing inline comments, and line-note composer state.
- Reduced `QuillCodeReviewPaneView.swift` to review header, file-list placement, and pane chrome.
- Added a native review parity gate so hunk/line/action rendering does not drift back into the pane shell.

Remaining risk:

- `QuillCodeReviewFileRowView` intentionally still owns both file and hunk rows because their action and comment workflows are coupled. If hunk-level review grows more controls, split `QuillCodeReviewHunkView` into its own file next.

## 2026-06-24 Parity Gate Suite Split

Overall grade after this slice: **A parity support boundary, A tool/router gate ownership, A desktop gate ownership**.

`ParityGateTests.swift` had become a 2,800-line mixed architectural rule registry. The coverage was valuable, but the suite mixed general app boundaries, tool/router rules, desktop app rules, and shared source-reading helpers in one class, which made new gates harder to place and increased merge-conflict risk for parallel agents.

Code quality changes:

- Added `ParityTestSupport.swift` as the shared base test case for package-root and source-reading helpers.
- Added `ParityToolGateTests.swift` for tool argument, slash catalog, remote execution, git, and router boundary gates.
- Added `ParityDesktopGateTests.swift` for native menu-bar, OAuth, task, settings, copy/feedback, import, and automation notification gates.
- Added a parity gate that keeps shared helpers, tool gates, and desktop gates from drifting back into the broad suite.

Remaining risk:

- `ParityGateTests.swift` is still large because it owns many app-surface and workspace-model boundary checks. Continue splitting by surface domain, especially workspace surface/HTML rendering gates, as those areas stabilize.

## 2026-06-24 Sidebar Command Grouping Pass

Overall grade after this slice: **A sidebar command presentation boundary, A renderer parity, A menu scanability**.

The sidebar tool menu had shared labels/icons, but it still exposed utility commands as one flat list. That made the native sidebar and HTML harness easy to keep in order but harder to scan as more Codex parity tools were added.

Code quality changes:

- Added explicit sidebar utility command groups in `QuillCodeSidebarCommandPresentation`.
- Kept the old flat `utilityCommandIDs` as a derived compatibility view so existing ordering tests and callers stay stable.
- Moved visible-group filtering into the shared presentation helper so native SwiftUI and the HTML harness omit empty groups identically.
- Rendered native utility commands as titled menu sections and HTML utility commands as matching section markup.
- Added focused tests for group order, flattened order, labels/icons/test IDs, and missing-command filtering.

Remaining risk:

- The native menu is now grouped, but the visual balance still depends on the surrounding sidebar chrome. The next UI pass should look at the whole left rail hierarchy with screenshots rather than adding more command-level structure.

## 2026-06-24 Automations Surface Builder Pass

Overall grade after this slice: **A automation-pane boundary, A command availability coverage, A regression guard**.

`WorkspaceSurface` still assembled the Automations pane inline, including create-command availability and every quick schedule command variant. That made the aggregate surface the owner of automation pane policy even though automation state mutation and automation display rows already lived in focused files.

Code quality changes:

- Added `WorkspaceAutomationsSurfaceBuilder` for automation pane assembly.
- Moved thread follow-up and workspace schedule command availability into the focused builder.
- Kept thread and workspace command availability independent so a selected thread can enable follow-ups without requiring a selected project, and vice versa.
- Simplified `WorkspaceSurface.surface()` to delegate automation pane construction.
- Added focused builder tests for empty/planned state, independent command availability, configured automation action rows, and a parity gate keeping automation command wiring out of `WorkspaceSurface`.

Remaining risk:

- `WorkspaceAutomationsSurface` still owns workflow row projection and status labels beside its Codable contract. That is acceptable while the logic is compact and directly tested; split row projection only if automation display behavior grows.

## 2026-06-24 Active Context Source Pass

Overall grade after this slice: **A context-source boundary, A behavior preservation, A regression guard**.

`WorkspaceSurface` still chose active instruction and memory sources inline. The rules are subtle because thread instructions and thread memories override project/global fallbacks independently, so the aggregate surface method was carrying business policy that should be directly tested.

Code quality changes:

- Added `WorkspaceActiveContextSources` beside `WorkspaceContextResolver`.
- Moved active instruction selection and active memory selection into `WorkspaceContextResolver.activeSources(for:)`.
- Preserved independent fallback behavior: thread instructions can override project instructions while memories still fall back to global/project notes, and vice versa.
- Simplified `WorkspaceSurface.surface()` so top bar, memories pane, and activity pane share one resolved active context source record.
- Added focused resolver tests and a parity gate keeping active context-source selection out of `WorkspaceSurface`.

Remaining risk:

- `WorkspaceSurface.surface()` still coordinates many independent panes. Continue extracting only when pane-specific policy appears there; avoid replacing a readable aggregate with an oversized god builder.

## 2026-06-24 Top-Bar Surface Builder Pass

Overall grade after this slice: **A top-bar boundary, A behavior preservation, A regression guard**.

`WorkspaceSurface` still assembled the whole top-bar payload inline, including status labels, source lists, runtime issue copy, Computer Use copy, model catalog projection, and recent-model projection. Those are top-bar presentation rules, not aggregate workspace assembly, and they made unrelated surface edits riskier than they needed to be.

Code quality changes:

- Added `WorkspaceTopBarSurfaceBuilder` for `TopBarSurface` assembly.
- Moved top-bar title/subtitle labels, instruction and memory source lists, runtime issue status, Computer Use setup state, model catalog projection, and recent-model filtering into the focused builder.
- Simplified `WorkspaceSurface.surface()` to compute shared workspace context once and delegate top-bar construction.
- Added focused builder tests for thread-backed top bars, empty-project fallback state, model favorites, and unarchived recent-model projection.
- Added parity gates keeping direct top-bar construction, status-label plumbing, and model-catalog builder ownership out of `WorkspaceSurface`.

Remaining risk:

- `WorkspaceSurface.surface()` still computes active instructions and memories for multiple panes. If those context inputs grow, extract a shared workspace context/source builder instead of pushing more raw state through the surface extension.

## 2026-06-24 Navigation Surface Builder Pass

Overall grade after this slice: **A navigation boundary, A behavior preservation, A regression guard**.

`WorkspaceSurface` still owned project sorting, project row projection, sidebar row construction, and sidebar bulk-action availability. Those rules are presentation policy rather than aggregate workspace assembly, and they were easy to accidentally change while editing unrelated transcript, settings, or command surface code.

Code quality changes:

- Added `WorkspaceNavigationSurfaceBuilder` for `ProjectListSurface` and `SidebarSurface` assembly.
- Moved project row sorting, sidebar row construction, inactive selection handling, and bulk-action availability into the focused builder.
- Simplified `WorkspaceSurface.surface()` to resolve selected sidebar IDs once and delegate navigation presentation to the builder.
- Added focused tests for project ordering, active/inactive selection projection, destructive delete marking, and empty-sidebar select availability.
- Added a parity gate keeping direct project/sidebar construction out of `WorkspaceSurface`.

Remaining risk:

- `WorkspaceSurface.surface()` still coordinates many independent surface builders. If aggregate assembly grows again, introduce a higher-level `WorkspaceSurfaceBuilder` context object instead of passing more raw model state through the extension.

## 2026-06-24 Approval Action Planner Pass

Overall grade after this slice: **A approval-card boundary, A behavior preservation, A regression guard**.

Approval-card action handling in `WorkspaceModel` still owned request lookup, decision event construction, approval/skip rationale copy, and tool execution. The side effects belong in the model, but the pure planning rules made the method harder to reason about and harder to test without constructing a full workspace.

Code quality changes:

- Added `WorkspaceApprovalActionPlanner` for approval request lookup, approval/deny decision event construction, run-versus-skip planning, and skip notice copy.
- Simplified `WorkspaceModel.runToolCardAction` to apply the planner output, then execute the approved tool or append the skip notice.
- Added focused planner tests for latest-request lookup, malformed payload tolerance, approve decisions, deny decisions, and missing-request failure.
- Added a parity gate keeping approval request lookup and decision event construction out of `WorkspaceModel`.

Remaining risk:

- Review action execution still performs side effects in `WorkspaceModel`, but run sequencing and status derivation now live in the review action planner pass below. If review workflows grow toward multi-step PR publication, add a dedicated workflow coordinator instead of expanding the model.

## 2026-06-24 Review Action Run Planner Pass

Overall grade after this slice: **A review-run boundary, A behavior preservation, A regression guard**.

Review actions already delegated file/hunk tool-call construction to `WorkspaceReviewActionToolCallPlanner`, but `WorkspaceModel` still knew that every review mutation must be followed by `host.git.diff` and that the top-bar status depends on both the action and diff refresh succeeding. That made the model the implicit owner of review-run policy.

Code quality changes:

- Added `WorkspaceReviewActionRunPlan` beside the existing review action planner.
- Moved review action sequencing, mandatory diff refresh call construction, and final status derivation into the planner.
- Simplified `WorkspaceModel.runReviewAction` to execute the planned calls, append tool cards, persist the selected thread, and apply the planned status.
- Added focused planner tests for action-plus-diff ordering and success/failure status rules.
- Strengthened the parity gate so diff-refresh construction and status derivation stay out of `WorkspaceModel`.

Remaining risk:

- `WorkspaceModel` still performs review-run side effects because it owns thread mutation and persistence. Richer review sessions, PR comment publication, or multi-step review batches should move those side effects into a dedicated review workflow coordinator.

## 2026-06-24 Focused Test Fixture DRY Pass

Overall grade after this slice: **A fixture DRYness, A teardown hygiene, A regression guard**.

Several focused workspace unit suites still carried private temporary-directory helpers or inline UUID temp paths even though the repo already has a shared teardown-backed test directory helper. The behavior was correct, but each private helper made cleanup and future fixture changes easier to miss.

Code quality changes:

- Replaced private temporary-directory helpers in agent run-context, agent send-session, memory engine, terminal engine, and tool-call executor tests with `makeQuillCodeTestDirectory()`.
- Reused the shared git initialization/runner helpers in `WorkspaceToolCallExecutorTests` instead of carrying a second private git process runner.
- Added a parity gate requiring these focused suites to keep using shared temporary-directory support.

Remaining risk:

- Some broader integration suites still use older cross-domain fixture helpers. Those should be converted only when each suite's shared SSH/GitHub/git fixtures are either moved behind teardown-backed support or split into domain-owned helpers.

## 2026-06-24 Workspace Worktree Integration Test Pass

Overall grade after this slice: **A feature grouping, A fixture DRYness, A regression guard**.

Worktree integration tests moved from `WorkspaceModelTests.swift` into `WorkspaceWorktreeIntegrationTests`. The model test file no longer owns local/SSH Remote worktree listing, worktree command prefill, local worktree create/remove, or remote SSH worktree project/thread creation.

Code quality changes:

- Added `WorkspaceWorktreeIntegrationTests` for worktree flows crossing workspace model, git tools, SSH Remote execution, tool cards, transcript events, project selection, and top-bar state.
- Centralized repeated SSH Remote worktree fixture setup inside the focused worktree suite.
- Kept pull-request command prefill in the PR/workspace model tests instead of hiding it in a worktree-named test.
- Added a parity gate that keeps model-level worktree integration method names out of `WorkspaceModelTests.swift`.
- Reduced `WorkspaceModelTests.swift` again without weakening worktree behavior coverage.

Remaining risk:

- `WorkspaceModelTests.swift` is still broad. Approval-card behavior, feedback, and artifact-state coverage remain future extraction candidates.

## 2026-06-24 Workspace Pull Request Integration Test Pass

Overall grade after this slice: **A feature grouping, A fixture DRYness, A regression guard**.

Pull request workflow tests moved from `WorkspaceModelTests.swift` into `WorkspacePullRequestIntegrationTests`. The model test file no longer owns SSH Remote PR workspace commands, slash-command PR workflow dispatch, or PR command prefill coverage.

Code quality changes:

- Added `WorkspacePullRequestIntegrationTests` for PR workflows crossing workspace commands, slash routing, SSH Remote execution, fake GitHub CLI behavior, tool cards, PR URL artifacts, and execution-context chips.
- Centralized repeated fake GitHub CLI plus fake SSH setup inside a `makeRemotePullRequestFixture` helper.
- Kept primitive GitHub PR command construction, validation, and execution in the existing focused tool and remote-planner tests.
- Added a parity gate that keeps PR workflow integration method names and fixtures out of `WorkspaceModelTests.swift`.
- Kept `WorkspaceModelTests.swift` focused at 363 lines after the thread lifecycle, worktree, PR workflow, and terminal SSH extractions.

Remaining risk:

- `WorkspaceModelTests.swift` is still broad. Approval-card behavior and plan-update integration are the next extraction candidates.

## 2026-06-24 Workspace Configuration Integration Test Pass

Overall grade after this slice: **A feature grouping, A persistence-boundary clarity, A regression guard**.

Configuration and bootstrap integration tests moved from `WorkspaceModelTests.swift` into `WorkspaceConfigurationIntegrationTests`. The model test file no longer owns mode/model top-bar propagation, favorite model config/surface projection, apply-settings thread/surface sync, persisted bootstrap loading, or TrustedRouter API key persistence. The lone project registry persistence test moved into `WorkspaceProjectIntegrationTests`, where it sits beside project instruction integration.

Code quality changes:

- Added `WorkspaceConfigurationIntegrationTests` for config flows crossing workspace model orchestration, surface projection, persisted config/thread/project/automation stores, bootstrap construction, and TrustedRouter key storage.
- Moved project registry persistence into `WorkspaceProjectIntegrationTests` instead of keeping a project-owned store assertion in the model monolith.
- Added parity gates that keep configuration/bootstrap integration test names out of `WorkspaceModelTests.swift` and require project registry persistence to remain with project integration coverage.
- Removed the duplicate private temporary-directory helper from `WorkspaceModelTests.swift` so focused integration suites use the shared fixture support.

Remaining risk:

- Handled by the workspace model test retirement pass below.

## 2026-06-24 Workspace Model Test Retirement Pass

Overall grade after this slice: **A test ownership, A regression guard, A monolith retirement**.

The historical catch-all `WorkspaceModelTests.swift` no longer owns active test cases. The final approval-card and plan-update integration tests moved into focused feature suites: `WorkspaceToolCardIntegrationTests` and `WorkspaceActivityIntegrationTests`. The old file remains only as an explicit retirement marker so parity gates can keep new workspace behavior from drifting back into a generic model test bucket.

Code quality changes:

- Added `WorkspaceToolCardIntegrationTests` for actionable approval-card projection, approval execution, transcript events, tool execution audit, and stopped-tool card projection.
- Added `WorkspaceActivityIntegrationTests` for plan-update tool execution, normalized activity surface projection, transcript event recording, and multiple-running-step rejection.
- Kept all behavior assertions from the retired model suite while giving each remaining flow a named feature owner.
- Added parity gates that require those focused suites to own the moved tests and assert `WorkspaceModelTests.swift` stays intentionally empty.

Remaining risk:

- New workspace integration coverage needs discipline: add it to the focused feature suite matching the behavior, or create a new named suite before adding another catch-all file.

## 2026-06-23 Core Model Catalog Ownership Pass

Overall grade after this slice: **A core cohesion, A model-default ownership**.

`Models.swift` was still carrying provider-specific TrustedRouter defaults, catalog records, and sort policy beside general thread/config/domain models. The behavior was correct, but the file mixed broad app domain state with one provider's catalog policy, making future provider/model-picker work easier to scatter.

Code quality changes:

- Moved `ModelInfo` and `ModelSortKey` into `ModelInfo.swift`.
- Moved `TrustedRouterDefaults` into `TrustedRouterDefaults.swift`, keeping Nike 1.0, Prometheus 1.0, aliases, fallback catalog rows, and catalog normalization together.
- Reduced `Models.swift` by keeping it focused on general domain models and app config/auth records.
- Added a parity gate that prevents model catalog records, sort keys, TrustedRouter defaults, and model branding copy from drifting back into `Models.swift`.

## 2026-06-23 Core App Config Ownership Pass

Overall grade after this slice: **A core cohesion, A config ownership**.

`Models.swift` also owned app settings, TrustedRouter auth mode, and signed-in account metadata. Those are core records, but they form a cohesive configuration boundary with compatibility rules that should not be hidden among chat/thread/domain models.

Code quality changes:

- Moved `AppConfig`, `TrustedRouterAuthMode`, and `TrustedRouterAccountProfile` into `AppConfig.swift`.
- Kept developer-override compatibility, OAuth account metadata trimming, and favorite-model normalization in the focused config file.
- Reduced `Models.swift` again so general domain records, JSON helpers, and config/auth concerns are easier to scan independently.
- Added a parity gate that prevents config/auth records and settings compatibility rules from drifting back into `Models.swift`.

## 2026-06-23 Core Tool Model Ownership Pass

Overall grade after this slice: **A core cohesion, A tool schema ownership**.

`Models.swift` still owned tool schemas, tool-call redaction, tool results, built-in core tool definitions, and browser/memory tool-output compatibility. Those records are core API contracts, but they form a tool payload boundary that should be scanable without reading chat/thread/project domain models.

Code quality changes:

- Moved `ToolHost`, `ToolRiskClass`, `ToolDefinition`, `ToolCall`, `ToolResult`, browser inspection output records, memory output records, and built-in core tool definitions into `ToolModels.swift`.
- Kept tool-call environment redaction beside `ToolCall`, where transcript privacy behavior is easiest to audit.
- Reduced `Models.swift` so chat/thread/project records and JSON helpers are easier to scan without tool-specific compatibility rules.
- Added a parity gate that prevents tool schemas, redaction, tool results, and tool-specific output compatibility from drifting back into `Models.swift`.

## 2026-06-23 Core Automation Model Ownership Pass

Overall grade after this slice: **A core cohesion, A automation model ownership**.

`Models.swift` still owned automation enums, recurrence semantics, next-run calculation, persisted automation records, and display sorting. Those are core value contracts, but they form a scheduling/workflow boundary that should be inspectable without reading unrelated chat, project, or memory records.

Code quality changes:

- Moved `QuillAutomationKind`, `QuillAutomationStatus`, `QuillAutomationScheduleKind`, `QuillAutomationRecurrenceUnit`, `QuillAutomationRecurrence`, and `QuillAutomation` into `AutomationModels.swift`.
- Kept recurrence interval clamping, seconds conversion, schedule descriptions, next-run calculation, and display sorting beside the automation records.
- Reduced `Models.swift` again so general chat/thread/project records are easier to audit independently.
- Added a parity gate that prevents automation scheduling and display-sort rules from drifting back into `Models.swift`.

## 2026-06-23 Core Project Model Ownership Pass

Overall grade after this slice: **A core cohesion, A project/workspace ownership**.

`Models.swift` still owned project connection parsing, SSH display, project refs, instructions, local environment actions, and extension manifests. Those are core workspace records, but they form a project boundary that should be inspectable without reading unrelated chat, approval, memory, or thread records.

Code quality changes:

- Moved `ProjectConnectionKind`, `ProjectConnection`, `ProjectRef`, `ProjectInstruction`, `LocalEnvironmentAction`, `ProjectExtensionKind`, `ProjectExtensionTransport`, and `ProjectExtensionManifest` into `ProjectModels.swift`.
- Kept SSH URL/scp-style parsing, display labels, project compatibility decoding, and extension launch metadata beside the project value records.
- Reduced `Models.swift` again so thread/message/memory records are easier to audit independently.
- Added a parity gate that prevents project connection, SSH parsing, local action, and extension manifest records from drifting back into `Models.swift`.

## Current Refactor Priority

1. Keep `QuillCodeDesktopController.swift` to UI/workspace routing; split future desktop protocol/workflow details before they grow into controller branches.
2. Continue pulling pure workflow planning and surface builders out of `WorkspaceModel` before adding new Codex-parity commands.
3. Keep splitting remaining workspace surface assembly into single-purpose builders when behavior grows; avoid adding new transcript or tool-card projection rules outside the transcript builder.
4. If MCP transports expand beyond stdio, add new launch/session implementations behind `WorkspaceMCPServerLaunching` instead of adding transport-specific branches to the runtime.
5. Keep the parity matrix updated whenever a feature moves from planned to implemented.

## 2026-06-23 Workspace Context Resolver Pass

Overall grade after this slice: **A- foundation, B+ product surface maturity**.

Workspace context lookup moved out of `WorkspaceModel.swift` into `WorkspaceContextResolver.swift`. The model still owns refresh side effects and persistence, but project instruction lookup, global-plus-project memory merging, selected local-action ID lookup, and local-action alias matching are now pure and directly tested.

Code quality changes:

- Added `WorkspaceContextResolver` as the focused source of truth for active project instructions, merged memory notes, and selected-project local environment actions.
- Removed private instruction, memory, local-action, and action-normalization helpers from `WorkspaceModel`.
- Added focused resolver tests for known/unknown project IDs, global memory ordering, project memory merging, exact local-action IDs, case-insensitive titles, relative paths, punctuation-insensitive aliases, and no-selected-project behavior.
- Added a parity gate that prevents context/action lookup from drifting back into `WorkspaceModel`.

## 2026-06-23 Tool Router Git Dispatch Pass

Overall grade after this slice: **A- foundation, B+ product surface maturity**.

The shared `ToolRouter` was carrying every local git, GitHub pull request, and git worktree route in its main switch. That kept behavior correct, but it made the central router too easy to grow into another feature-specific branch sink as the Codex parity tool surface expands.

Code quality changes:

- Added `GitToolCallDispatcher` as the focused owner for git-family tool definitions and argument-to-executor dispatch.
- Reduced `ToolRouter` to shell/file/patch primitives plus early delegation to the git dispatcher.
- Kept the existing `GitToolExecutor` facade intact, so shell/file/patch routing, tool schemas, and git command behavior stay API-compatible.
- Added focused dispatcher coverage and a parity gate that prevents local git, GitHub PR, or worktree route branches from drifting back into `ToolRouter`.

## 2026-06-23 Tool Router Shell Dispatch Pass

Overall grade after this slice: **A- foundation, B+ product surface maturity**.

Shell routing had the same drift risk as git routing: the shared router still owned cwd resolution, timeout parsing, environment override validation, and shell request construction. Those policies are important enough to be directly owned and guarded by a focused shell dispatcher.

Code quality changes:

- Added `ShellToolCallDispatcher` as the focused owner for `host.shell.run` definitions and request construction.
- Moved shell cwd, timeout, and environment override policy out of `ToolRouter`.
- Reduced `ToolRouter` to tool-family delegation plus file read/write and apply-patch primitives.
- Added focused dispatcher coverage and a parity gate that prevents shell validation policy from drifting back into `ToolRouter`.

## 2026-06-22 Workspace Project Engine Refactor Pass

Overall grade after this slice: **A- foundation, B+ product surface maturity**.

Project registry transitions moved out of `WorkspaceModel.swift` into `WorkspaceProjectEngine.swift`. The workspace model still owns filesystem/SSH context loading, persistence, terminal sync, and top-bar refresh, but local/SSH project upsert, selected-project thread choice, thread cleanup after project removal, metadata application, touch timestamps, and default project naming are now directly testable pure helpers.

Code quality changes:

- Extracted local project upsert so existing project refresh and new-project insertion share one state transition.
- Extracted SSH Remote project validation, default naming, creation, and same-connection update logic.
- Extracted selected-project thread choice and post-thread-removal fallback selection.
- Extracted project removal cleanup so affected thread IDs are explicit and persistence can stay in the model.
- Extracted metadata application for local and remote context refresh, including the rule that SSH Remote refresh clears local actions and extension manifests.
- Removed an unused project-instructions-only refresh helper.
- Added focused project engine tests for default names, local/SSH upserts, selection, removal cleanup, touch timestamps, and metadata application.

## 2026-06-22 Workspace Terminal Engine Refactor Pass

Overall grade after this slice: **A- foundation, B+ product surface maturity**.

Terminal state, command-entry mutation, local shell wrapping, SSH Remote terminal wrapping, cwd marker parsing, and environment-delta parsing moved out of `WorkspaceModel.swift` into `WorkspaceTerminalEngine.swift`. The workspace model still owns async shell streaming, top-bar status, and selected-project orchestration, but the pure terminal session rules are now directly testable without booting the full workspace model.

Code quality changes:

- Moved `TerminalCommandState`, `TerminalCommandStatus`, and `TerminalState` beside the terminal engine boundary.
- Extracted session sync, clear-history refusal, output appends, finish/stop transitions, and execution-context assignment into focused terminal state helpers.
- Extracted local terminal marker wrapping and SSH Remote terminal marker wrapping into pure helpers.
- Extracted local marker cleanup, remote marker stripping, cwd persistence, and environment delta calculation into directly tested helpers.
- Added focused terminal engine tests for project switching, stale project cwd fallback, stopped-entry protection, stop-all mutation, local wrapping, SSH cwd mapping, shell environment quoting, remote metadata parsing, and marker cleanup.

## 2026-06-22 Workspace Automation Engine Refactor Pass

Overall grade after this slice: **A- foundation, B+ product surface maturity**.

Automation creation and run planning moved out of `WorkspaceModel.swift` into `WorkspaceAutomationEngine.swift`. The workspace model still owns UI selection, project refresh, persistence, and notification-facing reports, but automation records, relative date helpers, due-job selection, run metadata advancement, and follow-up/workspace-check draft construction now live behind focused pure helpers.

Code quality changes:

- Moved `AutomationsState` and `AutomationRunReport` beside the automation engine boundary.
- Extracted thread-follow-up and workspace-schedule record construction into `WorkspaceAutomationFactory`.
- Extracted due-job filtering, recurring run advancement, and generated follow-up/workspace-check thread drafts into `WorkspaceAutomationRunner`.
- Reduced `WorkspaceModel` automation execution to validation, project context refresh, and applying a `WorkspaceAutomationRunDraft`.
- Added focused automation engine tests for schedule construction, tomorrow helpers, due-job filtering, recurrence advancement, draft contents, copied instructions, memories, and reports.

## 2026-06-22 Workspace Command Planner Refactor Pass

Overall grade after this slice: **A- foundation, B+ product surface maturity**.

Workspace command parsing moved out of `WorkspaceModel.swift` into `WorkspaceCommandPlan.swift`. The model still owns side effects, but command IDs now reduce through a pure `WorkspaceCommandPlan` enum before the model mutates state, dispatches tools, or pre-fills the composer. This makes command routing easier to test and lowers the risk of command-palette, slash-template, automation, MCP, memory, and git command IDs drifting apart as Codex-parity commands expand.

Code quality changes:

- Removed the inline prefix parser and static command switch from `WorkspaceModel.runWorkspaceCommand`.
- Centralized canonical git command ID to `ToolDefinition` name mapping in `WorkspaceCommandPlan`.
- Centralized draft-prefill command mapping for memory, SSH project, pull request, and worktree commands.
- Moved quick automation recurrence parsing beside the automation command-plan parser.
- Added focused planner tests for tool mapping, draft mapping, prefix validation, recurrence parsing, slash insert mapping, static action mapping, and invalid command IDs.

## 2026-06-23 Slash Command Transcript Planner Pass

Overall grade after this slice: **A- foundation, B+ product surface maturity**.

Slash-command local transcript copy moved out of `WorkspaceModel.swift` into `WorkspaceSlashCommandTranscriptPlanner.swift`. The workspace model still owns the side effects and dispatch decisions, but success/failure transcript wording is now a pure, directly tested contract.

| Surface | Before | After |
| --- | --- | --- |
| Slash command copy | Scattered string literals inside the main command switch. | One planner emits typed `WorkspaceLocalCommandTranscript` records. |
| UX consistency | Rename, SSH, schedule, and generic slash failure copy could drift as commands changed. | Focused planner tests cover titles, fallbacks, trimming, schedule descriptions, and unknown-command copy. |
| Model responsibility | `WorkspaceModel` mixed command side effects with local transcript presentation text. | `WorkspaceModel` mutates state and delegates transcript copy. |

Code quality changes:

- Added a typed `WorkspaceLocalCommandTranscript` record for local slash-command transcript entries.
- Extracted `/help`, `/status`, `/mode`, `/model`, `/rename`, `/project rename`, `/ssh`, `/follow-up`, `/workspace-check`, `/env`, invalid-command, unknown-command, and workspace-command failure transcript construction.
- Kept command side effects in `WorkspaceModel` so this pass stays behavior-preserving.
- Added parity gates that prevent slash-command local copy from drifting back into `WorkspaceModel`.

## 2026-06-23 Remote Git Request Planner Pass

Overall grade after this slice: **A- foundation, B+ product surface maturity**.

SSH Remote project tool execution now has clearer seams: the executor owns routing and SSH execution, remote path normalization lives in `WorkspaceRemoteProjectPath`, and Git/GitHub/worktree command construction lives in `WorkspaceRemoteGitToolRequestPlanner`. This reduces `WorkspaceRemoteProjectToolExecutor.swift` from a broad 815-line command-builder/executor mix to a focused execution boundary while preserving behavior.

Code quality changes:

- Extracted remote file/worktree path normalization and artifact URL construction into `WorkspaceRemoteProjectPath`.
- Extracted remote Git, GitHub PR, hunk, push, and worktree command planning into `WorkspaceRemoteGitToolRequestPlanner`.
- Added a typed `WorkspaceRemoteGitToolRequest` contract so URL extraction and artifact propagation are explicit planner output instead of executor-local side effects.
- Added focused planner tests for pull-request command planning, worktree artifact planning, and unsafe worktree path rejection.
- Updated parity gates so future refactors keep remote Git command construction and remote path normalization out of `WorkspaceModel` and the remote executor.

## 2026-06-22 Composer Refactor Pass

Overall grade after this slice: **A- foundation, B+ product surface maturity**.

This pass improves one of the highest-traffic surfaces without changing behavior: the native composer and slash-command suggestions moved out of `WorkspaceSwiftUIView.swift` into `QuillCodeComposerView.swift`. The extracted file keeps focus handling, keyboard navigation, send/stop affordances, and slash suggestion presentation together, which makes future composer work easier to reason about and test.

Interface polish changes:

- Slash suggestion rows now guarantee the shared 40 pt hit target.
- Suggestion rows use the shared `QuillCodePressableButtonStyle` for consistent `0.96` press feedback.
- The command usage chip no longer relies on a fixed 230 pt row column; long command names truncate in the chip instead of squeezing row detail text first.
- The panel includes a quiet keyboard hint for Up/Down and Tab so command discovery feels more self-explanatory.
- Composer input and send/stop controls use matching 15 pt continuous radii and 46 pt minimum height for a more concentric, tactile bottom bar.

## 2026-06-22 Model Picker Refactor Pass

Overall grade after this slice: **A- foundation, B+ product surface maturity**.

The native model picker moved out of `WorkspaceSwiftUIView.swift` into `QuillCodeModelPickerView.swift`. Model picking now has named subviews for the trigger, popover body, category sections, rows, action buttons, and expanded metadata, which keeps future model-catalog and provider-capability work away from the already-large workspace shell.

Interface polish changes:

- The model trigger now uses the shared `0.96` press feedback instead of a borderless static button.
- Model search controls keep the shared 40 pt minimum hit target.
- Model rows now guarantee a 40 pt selectable summary area and use the shared press style for tactile feedback.
- Info and favorite controls now use the same press style as other high-frequency icon buttons while preserving 40 pt hit areas.
- Long provider/model metadata truncates in the middle instead of pushing row actions off-screen.
- The empty state keeps the same 12 pt inner radius and wraps explanatory copy without clipping.

## 2026-06-22 Top Bar Refactor Pass

Overall grade after this slice: **A- foundation, B+ product surface maturity**.

The native top bar moved out of `WorkspaceSwiftUIView.swift` into `QuillCodeTopBarView.swift`. This keeps workspace shell layout separate from the Codex-like chrome contract: thread identity, model/mode picker, status, and overflow actions now live together in one focused control.

Interface polish changes:

- The overflow menu uses the shared `0.96` press feedback instead of a static borderless icon.
- The overflow menu keeps the shared 40 pt hit target while adding a quiet selected-surface background and 10 pt continuous radius.
- Runtime issue pills stay inside the top-bar file because they are specific to top-bar status density and use tabular caption numerals for stable changing labels.
- The identity cluster is a single bounded accessibility element, so long project/thread metadata remains available without visually crowding the bar.

## 2026-06-23 Top Bar Model/Mode Split Pass

Overall grade after this slice: **A- foundation, B+ product surface maturity**.

Claude CLI's design review called out the model/mode pill as the highest-impact interaction ambiguity: model choice is a preference, while approval mode is a safety posture. This pass separates those concepts in both native SwiftUI and the Playwright harness.

Interface and architecture changes:

- `QuillCodeModelPickerView` no longer owns `AgentMode` mutation or renders `modeLabel`.
- `QuillCodeTopBarView` owns a dedicated `QuillCodeModePickerButton` with Auto, Review, and Read-only choices.
- The model trigger renders only the selected model and keeps the model browser focused on provider/category/model search.
- The mode control uses a compact safety capsule with a colored dot, distinct from the quieter model text button.
- Playwright tests now assert that model and mode are visible, separated controls and that changing mode does not mutate the model selection.
- A parity gate prevents future regressions that merge model and approval mode into one top-bar label again.

## 2026-06-22 Sidebar Refactor Pass

Overall grade after this slice: **A- foundation, B+ product surface maturity**.

The native sidebar moved out of `WorkspaceSwiftUIView.swift` into `QuillCodeSidebarView.swift`. The new file owns primary navigation actions, thread grouping, bulk selection, project rows, and the compact tools/settings footer together, which keeps the Codex-like left rail away from transcript, review, and sheet code.

Interface polish changes:

- Primary sidebar actions now use the shared `0.96` press feedback and a guaranteed 40 pt hit target.
- Thread rows use a shared selection-toggle helper instead of duplicating command construction in two button handlers.
- Thread and project row buttons keep 40 pt minimum interactive height while preserving the compact left-rail density.
- Bulk action buttons, project header icons, row overflow menus, Tools, and Settings now use the same press feedback contract as the composer/model/top-bar controls.

## 2026-06-22 Review Pane Refactor Pass

Overall grade after this slice: **A- foundation, B+ product surface maturity**.

The native git review pane moved out of `WorkspaceSwiftUIView.swift` into `QuillCodeReviewPaneView.swift`. Review summary, file rows, hunk rows, inline comments, range notes, and review action buttons now live beside each other in one focused component, which keeps future diff-review work away from the transcript shell.

Interface polish changes:

- Review action icon buttons now use the shared `0.96` press feedback and a guaranteed 40 pt hit target.
- File-level, hunk-level, and line-level note actions use the same press feedback contract instead of borderless static controls.
- Range and line note inputs keep a 40 pt minimum height, so text entry does not feel cramped beside the action buttons.
- The review hunk count uses tabular numerals, preventing subtle width shifts as review data changes.

## 2026-06-22 Design System Refactor Pass

Overall grade after this slice: **A- foundation, B+ product surface maturity**.

Shared visual primitives moved out of `WorkspaceSwiftUIView.swift` into `QuillCodeDesignSystem.swift`. The workspace shell no longer owns palette constants, hit-target metrics, press feedback, surface styling, or image outlines. That keeps the monolithic file shrinking and gives extracted native controls one stable place to pull UI primitives from.

Interface polish changes:

- The shared 40 pt hit-target metrics now have design-system ownership instead of workspace-shell ownership.
- The shared `0.96` press feedback lives beside the metrics it depends on, making tactile button behavior harder to fork.
- Surface and image-outline modifiers are reusable outside the workspace file while preserving the pure-white dark-mode outline and existing continuous radii.

## 2026-06-22 Transcript Message Refactor Pass

Overall grade after this slice: **A- foundation, B+ product surface maturity**.

Transcript message bubbles moved out of `WorkspaceSwiftUIView.swift` into `QuillCodeTranscriptMessageView.swift`. User and assistant message rendering, retry/use-as-draft controls, feedback controls, and the shared transcript copy button now live beside each other instead of being embedded between terminal and tool-card code.

Interface polish changes:

- Message action controls keep the shared 40 pt minimum hit target and `0.96` press feedback in one focused file.
- The transcript copy button is now shared from the transcript-message component file, so message bubbles and tool cards do not need separate copy affordance implementations.
- The workspace shell shrank by another focused chunk, reducing the risk that future transcript edits accidentally touch terminal, settings, or browser panes.

## 2026-06-22 Tool Card Refactor Pass

Overall grade after this slice: **A- foundation, B+ product surface maturity**.

Tool cards and artifact previews moved out of `WorkspaceSwiftUIView.swift` into `QuillCodeToolCardView.swift`. Tool status badges, execution-context chips and rails, artifact chips, document/image/text previews, and raw JSON detail blocks now live beside the tool-card renderer. The workspace shell places transcript timeline items and wires copy actions, but it no longer owns the tool-card rendering family.

Interface polish changes:

- Tool-card header density, status rails, and bounded raw details preserve the existing rhythm while making future polish safer to localize.
- Artifact chips and previews preserve 40 pt minimum hit areas, pure-white image outline behavior through the design system, and bounded raw JSON/details.
- The shared transcript copy button is reused from transcript message controls so message and tool-card copy affordances stay consistent.

## 2026-06-22 Settings Refactor Pass

Overall grade after this slice: **A- foundation, B+ product surface maturity**.

Settings, runtime issue callouts, Computer Use permission onboarding, and settings draft state moved out of `WorkspaceSwiftUIView.swift` into `QuillCodeSettingsView.swift`. The workspace shell now opens the sheet and applies settings updates, while the settings file owns authentication mode controls, developer override fields, permission rows, diagnostics, and the reusable runtime issue callout used in the transcript.

Interface polish changes:

- Settings now has named subviews for header, authentication picker, API base URL field, OAuth/developer override sections, and footer, reducing body density without changing the visible flow.
- Computer Use setup keeps its permission/status rows together and uses named subviews for header, requirements, next action, restart hint, and refresh action.
- Permission action rows preserve the shared 40 pt minimum hit target through `QuillCodeMetrics.minimumHitTarget`.
- Runtime issue callouts remain reusable from transcript and settings surfaces, with diagnostics bounded in the same component.

## 2026-06-22 Terminal And Browser Pane Refactor Pass

Overall grade after this slice: **A- foundation, B+ product surface maturity**.

The native terminal and browser panes moved out of `WorkspaceSwiftUIView.swift` into `QuillCodeTerminalBrowserPaneView.swift`. Terminal command entry rendering, execution-context chips/rails, browser navigation, page snapshots, outline metadata, and browser comments now live beside the controls they support instead of being embedded in the workspace shell.

Interface polish changes:

- Terminal and browser panes now use named header, content, and input subviews, making future parity work safer to localize.
- Browser snapshot rendering keeps bounded detail chips, page outline truncation, and comments in one focused component.
- Terminal entries keep execution-context accessibility labels and status coloring in the same file as the terminal pane.

## 2026-06-24 Terminal And Browser Pane File Split

Overall grade after this slice: **A terminal-pane ownership, A browser-pane ownership, A terminal-row ownership**.

`QuillCodeTerminalBrowserPaneView.swift` was a useful first extraction from the workspace shell, but it still coupled two independent Codex parity areas: the integrated terminal and browser preview/commenting pane. That made terminal session polish and browser inspection work likely to collide in one file.

Code quality changes:

- Added `QuillCodeTerminalPaneView.swift` for terminal header, entries, and command-line controls.
- Added `QuillCodeTerminalEntryView.swift` for execution-context chips/rails, terminal output, status color, and accessibility labels.
- Added `QuillCodeBrowserPaneView.swift` for browser navigation, snapshot summaries, page outline, comments, and browser badges.
- Removed the combined terminal/browser file and added a parity gate so the split remains stable.

Remaining risk:

- `QuillCodeBrowserPaneView.swift` is still larger than the terminal pane because it owns navigation, snapshots, outline, badges, and comments. Split snapshot summary/comment rows if browser inspection gains richer previews or signed-in browser controls.

## 2026-06-22 Secondary Utility Pane Refactor Pass

Overall grade after this slice: **A- foundation, B+ product surface maturity**.

Extensions, Memories, and Automations moved out of `WorkspaceSwiftUIView.swift` into `QuillCodeSecondaryPanesView.swift`. These panes share the same secondary utility shape: a compact header, count/status pills, empty state, and bounded cards. Keeping them together makes plugin/MCP, memory, and automation UX work easier to evolve without expanding the workspace shell again.

Interface polish changes:

- Extensions, Memories, and Automations now use named header/content/card/action subviews instead of one long nested body per pane.
- Extensions and Memories share a single count-pill component, preserving tabular numbers while removing duplicated visual code.
- All three panes share one empty-state component, keeping secondary-pane copy density, padding, and inner radius consistent.
- WorkspaceSwiftUIView now only decides pane placement and action routing; pane-specific draft, row, and card rendering is isolated.

## 2026-06-22 Workspace Dialog Refactor Pass

Overall grade after this slice: **A- foundation, B+ product surface maturity**.

Command palette, keyboard shortcuts, search, rename sheets, and worktree sheets moved out of `WorkspaceSwiftUIView.swift` into `QuillCodeWorkspaceDialogs.swift`. These surfaces are command-heavy and modal by nature, so keeping their row rendering, draft types, icon mapping, and keyboard focus behavior together makes future command-palette and worktree UX work easier to evolve without growing the workspace shell again.

Interface polish changes:

- Command palette rows now use the shared `0.96` press feedback and guaranteed 40 pt minimum hit target.
- Search result rows now use the shared press feedback and 40 pt minimum hit target instead of plain static buttons.
- Command palette, search, and keyboard shortcut sheets share header, section-title, and empty-state helpers so copy density and spacing stay consistent.
- Worktree and rename dialogs share labeled-field and frame helpers, keeping field labels, helper text, and text-field hit targets consistent.
- WorkspaceSwiftUIView now only presents dialogs and routes their completed actions; dialog-specific draft, row, icon, and empty-state rendering is isolated.

## 2026-06-24 Workspace Dialog Ownership Pass

Overall grade after this slice: **A- foundation, A- dialog architecture**.

`QuillCodeWorkspaceDialogs.swift` had become another bucket file after the first extraction from `WorkspaceSwiftUIView.swift`: it mixed rename sheets, command palette rendering, keyboard shortcut rows, chat search rows, worktree drafts, worktree sheets, shared dialog fields, and command icon mapping. The behavior was solid, but the file-level ownership was B/B+ because a future command-palette change could collide with unrelated worktree or search edits.

Ownership changes:

- `QuillCodeCommandPaletteDialog.swift` now owns command palette focus, keyboard navigation, grouped command rows, and command icon mapping.
- `QuillCodeSearchAndShortcutDialogs.swift` now owns chat search and keyboard shortcut rendering.
- `QuillCodeWorktreeDialogs.swift` now owns worktree create/remove drafts and sheets.
- `QuillCodeDialogChrome.swift` now owns shared dialog header, section title, empty state, and labeled text-field primitives.
- `QuillCodeWorkspaceDialogs.swift` is now a small rename-sheet file, keeping rename state separate from broader command and worktree workflows.

Validation:

- `ParityGateTests/testWorkspaceSwiftUIViewDelegatesSheetPresentation` now asserts sheet wiring remains outside the workspace shell and each dialog family remains in its focused owner file.

## 2026-06-24 Native Tool Card Ownership Pass

Overall grade after this slice: **A- foundation, A- native tool-card architecture**.

`QuillCodeToolCardView.swift` was a B+ hotspot after the initial extraction from the workspace shell. It owned the main card, review actions, status badges, execution context chips/rails, artifact chips, document/image/text previews, and raw JSON code blocks in one 758-line file. The behavior was covered, but the file was too broad for parallel work on long-output UX, artifact previews, execution-context visual polish, and approval controls.

Ownership changes:

- `QuillCodeToolCardView.swift` now owns card composition, header status color/icon decisions, disclosure state, and copy-label routing.
- `QuillCodeToolCardControls.swift` now owns action rows, status badges, and shared execution-context chip/rail controls used by both tool cards and terminal entries.
- `QuillCodeToolArtifactViews.swift` now owns artifact chips plus text, document, and image preview rendering.
- `QuillCodeToolCardDetailsView.swift` now owns raw JSON detail blocks.

Validation:

- Focused Swift tests: `QuillCodeToolCardSurfaceTests`, `QuillCodeTranscriptSurfaceTests`, and `ParityGateTests/testActionableReviewCardsStayWiredThroughSurfaces`.
- Parity gates now assert native tool-card composition delegates controls, artifacts, and raw details to focused files.

## 2026-06-22 Desktop Bootstrap Split Pass

Overall grade after this slice: **A- foundation, B+ product surface maturity**.

The desktop executable no longer keeps app scene setup, menu commands, menu-bar rendering, OAuth loopback handling, browser fetching, notification delivery, and workspace task coordination in one monolithic `main.swift`. `QuillCodeDesktopApp.swift` now owns only scene composition and root-view wiring, while focused desktop files own command registration, menu-bar UI, browser fetches, automation notifications, OAuth callback capture, and controller orchestration.

Code quality changes:

- Deleted the 1,145-line desktop `main.swift` and replaced it with small, named Swift files with clear ownership.
- Moved native command menu registration into `DesktopCommands.swift`, preserving shortcut registry reuse.
- Moved menu-bar UI into `QuillCodeMenuBarView.swift`, keeping the app scene free of menu layout details.
- Moved bounded browser HTML fetching into `DesktopBrowserPageFetcher.swift`.
- Moved macOS notification delivery behind `QuillCodeAutomationNotifying` in `DesktopAutomationNotifier.swift`.
- Moved TrustedRouter localhost OAuth callback capture into `TrustedRouterLoopbackCallbackServer.swift`.
- Updated parity gates to scan the whole desktop source folder so future extraction does not force regressions back into app bootstrap.
- Removed unnecessary SwiftUI type erasure from native shortcut registration.

Remaining risk:

- `QuillCodeDesktopController.swift` is now the intentional desktop hotspot. Its next split should separate settings application and macOS System Settings routing into focused helpers before more desktop parity features land.

## 2026-06-22 Desktop Controller Split Pass

Overall grade after this slice: **A- foundation, B+ product surface maturity**.

The desktop controller no longer owns raw task slots, task identity bookkeeping, OAuth exchange steps, loopback callback capture, token persistence, or TrustedRouter account-profile assembly. It now delegates cancellable work to `QuillCodeDesktopTaskCoordinator` and OAuth sign-in to `QuillCodeDesktopSignInCoordinator`, leaving the controller focused on workspace routing, UI sheet state, and applying model/runtime updates.

Code quality changes:

- Replaced manual `sendTask`, `terminalTask`, `browserPreviewTask`, and task-ID fields with `QuillCodeDesktopTaskCoordinator` slots.
- Routed composer send, retry, terminal command, browser preview, Stop All, and automation ticker through one cancellable-task helper.
- Moved TrustedRouter OAuth client construction, PKCE authorization, loopback callback waiting, code exchange, token persistence, and account-profile fetches into `QuillCodeDesktopSignInCoordinator`.
- Added parity gates that keep OAuth exchange and raw cancellable task slots out of `QuillCodeDesktopController.swift`.
- Removed the controller's dependency on `QuillCodeAgent`; only the sign-in coordinator imports the OAuth client.

Remaining risk:

- Settings persistence and macOS System Settings URL actions still live in the controller. The next desktop quality slice should move settings application and platform settings opening into focused helpers.

## 2026-06-22 Desktop Settings Coordinator Pass

Overall grade after this slice: **A- foundation, A- desktop controller boundary**.

Settings persistence, TrustedRouter key replacement/clear rules, and OAuth-account reset rules moved out of `QuillCodeDesktopController.swift` into `QuillCodeDesktopSettingsCoordinator`. macOS Computer Use System Settings URLs moved into `MacSystemSettingsOpener`. The controller now applies returned settings/runtime state and refreshes the model catalog, but it no longer owns secret-store operations or platform settings URLs.

Code quality changes:

- Added `QuillCodeDesktopSettingsCoordinator` to own settings saves, secret-key replacement/clear rules, and persisted config updates.
- Added `MacSystemSettingsOpener` so Screen Recording and Accessibility URLs are named platform actions instead of inline strings.
- Reduced `QuillCodeDesktopController.saveSettings` to applying the coordinator result and rebuilding runtime state.
- Added parity gates that keep secret persistence, auth-account reset rules, and macOS System Settings URLs out of the controller.

Remaining risk:

- The controller still owns project-import sheet presentation because it is UI state. Project import result resolution and directory validation now belong in the import coordinator.

## 2026-06-22 Tool Card Surface Split Pass

Overall grade after this slice: **A- foundation, B+ workspace model boundary**.

Tool-card status/density, artifact kind/preview metadata, artifact text-preview construction, and `ToolCardState` moved out of `WorkspaceModel.swift` into `QuillCodeToolCardSurface.swift`. The workspace model still constructs tool cards from thread events, but the pure presentation models now live beside other surface definitions instead of expanding the already-large orchestration file.

Code quality changes:

- Moved tool-card and artifact surface types into `QuillCodeToolCardSurface.swift`.
- Kept artifact text-preview construction beside artifact state, with module-internal access for `WorkspaceModel` to request previews.
- Reduced `WorkspaceModel.swift` by roughly 550 lines without changing the tool-card API used by SwiftUI, HTML rendering, Activity surfaces, or tests.
- Added a parity gate that keeps tool-card surface state out of `WorkspaceModel.swift`.

Remaining risk:

- `WorkspaceModel.swift` still owns several pure browser/MCP request-state structs and tool-card event assembly. Those are good next extraction candidates once the current boundary is stable.

## 2026-06-23 Browser Surface Split Pass

Browser preview state moved out of `WorkspaceModel.swift` into `QuillCodeBrowserSurface.swift`. The workspace model still owns URL normalization, browser history mutation, snapshot refreshing, and comment insertion, but the pure browser comment/snapshot/browser-state records now live beside other presentation contracts.

Code quality changes:

- Moved `BrowserCommentState`, `BrowserSnapshotState`, and `BrowserState` out of the workspace orchestration file.
- Kept browser navigation behavior unchanged while making the snapshot/comment state reusable by SwiftUI, static HTML, Playwright, and browser-tool tests without importing model implementation details.
- Added a parity gate that keeps browser surface state out of `WorkspaceModel.swift`.
- Reduced `WorkspaceModel.swift` by another focused chunk before adding more browser parity work.

Remaining risk:

- `WorkspaceModel.swift` still owns MCP process handles and lifecycle orchestration. A future MCP coordinator can move process startup/probe/termination once the current request/surface boundary is stable.

## 2026-06-23 MCP Support Split Pass

MCP extension surface state and MCP JSON request parsing moved out of `WorkspaceModel.swift`. The workspace model still owns process handles, manifest lookup, start/stop orchestration, and tool execution routing, but lifecycle labels, probe summary compatibility, and tool/resource/prompt request parsing now live in focused helpers with direct tests.

Code quality changes:

- Moved `ExtensionsState`, `MCPServerLifecycleStatus`, and `MCPServerProbeSummary` into `QuillCodeMCPSurface.swift`.
- Moved `MCPToolCallRequest`, `MCPResourceReadRequest`, and `MCPPromptGetRequest` into `WorkspaceMCPRequests.swift`.
- Replaced repeated JSON-object parsing and nested `arguments` normalization with one small request helper.
- Added focused tests for lifecycle labels, probe-summary descriptor compatibility, probe-result bridging, request aliases, explicit `argumentsJSON`, default `{}` arguments, and user-facing parse errors.
- Added a parity gate that keeps MCP surface and request parser types out of `WorkspaceModel.swift`.

Remaining risk:

- MCP process lifecycle remains in `WorkspaceModel.swift`. That logic touches selected-project manifests, async process probes, top-bar status, notices, and tool routing, so it should move only with a focused coordinator and lifecycle tests.

## 2026-06-23 MCP Runtime And Catalog Split Pass

Overall grade after this slice: **A- foundation, A- MCP boundary**.

MCP process lifecycle moved behind `WorkspaceMCPRuntime`, and dynamic MCP tool/resource/prompt catalog generation moved into `WorkspaceMCPToolCatalog`. `WorkspaceModel.swift` now does manifest lookup and UI side effects, then delegates process startup/probe/stop/cancel and tool routing to the runtime. The runtime owns subprocess handles and session routing, while the catalog owns pure Ready-server filtering and prompt/tool description construction.

Code quality changes:

- Moved MCP subprocess handles, start/probe/stop/finish/cancel behavior, and execution override construction out of `WorkspaceModel.swift`.
- Kept MCP process handles private to `WorkspaceMCPRuntime`, preventing process lifecycle details from leaking back into workspace orchestration.
- Extracted Ready MCP tool/resource/prompt catalog construction into `WorkspaceMCPToolCatalog`.
- Added focused catalog tests for Ready/running filtering, omitted capability groups, resource URI fallback formatting, and runtime delegation.
- Extended parity gates so `WorkspaceModel.swift` cannot regain MCP process spawning or catalog formatting, and `WorkspaceMCPRuntime.swift` cannot absorb catalog description formatting.

Remaining risk:

- `WorkspaceMCPRuntime` should not regain concrete launch/prober construction. If MCP transport support expands beyond stdio, add transport-specific launchers behind the launch/session seam rather than branching lifecycle logic inside the runtime.

## 2026-06-23 MCP Launch Factory Pass

Overall grade after this slice: **A- foundation, A- MCP runtime boundary**.

Concrete MCP process construction and stdio prober creation moved out of `WorkspaceMCPRuntime.swift` into `WorkspaceMCPServerLauncher.swift`. Manifest launch validation now creates a `WorkspaceMCPLaunchRequest`, while the runtime owns lifecycle status changes, probe result recording, stop/cancel behavior, and dynamic tool routing. Server startup passes through a focused `WorkspaceMCPServerLaunching` seam with protocol-backed process and session handles.

Code quality changes:

- Added `WorkspaceMCPServerLaunching`, `WorkspaceMCPProcessControlling`, and `WorkspaceMCPSession` protocols so MCP lifecycle tests do not require real subprocesses.
- Moved disabled/missing-command validation into `WorkspaceMCPLaunchRequest.make` so launch inputs are canonical before the runtime sees them.
- Isolated `/usr/bin/env`, absolute executable, and workspace-relative executable resolution in `WorkspaceMCPProcessLaunchConfiguration`.
- Moved concrete `Process`, pipe, termination-handler, and `MCPStdioProber` construction into `DefaultWorkspaceMCPServerLauncher`.
- Kept stderr draining and readability cleanup behind the process controller so the runtime no longer reaches into Foundation pipe details.
- Added focused tests for command resolution, injected-launcher ready probes, launch failures, and probe-failure cleanup.
- Fixed singular MCP ready notices so one advertised tool is reported as `1 tool`.
- Extended parity gates so `WorkspaceMCPRuntime.swift` cannot regain direct `Process()`, stdio prober, or launch-command construction.

Remaining risk:

- `WorkspaceMCPRuntime` still owns lifecycle status mutation and dynamic tool routing because those policies are coupled to extension state. If remote MCP transports, SSE, or persistent marketplace servers arrive, add specialized launcher/session implementations first, then split routing only if per-transport execution policy actually diverges.

## 2026-06-23 Runtime Issue Builder Split Pass

Overall grade after this slice: **A- foundation, B+ surface boundary**.

TrustedRouter runtime failure classification, diagnostics, rate-limit metadata parsing, and secret redaction moved out of `WorkspaceSurface.swift` into `WorkspaceRuntimeIssueBuilder`. The workspace surface now delegates runtime issue construction to one pure helper, while `RuntimeIssueSurface` remains the shared renderer contract consumed by the top bar, settings, HTML renderer, and Playwright harness.

Code quality changes:

- Extracted sign-in/developer-key status issues, runtime error classification, and diagnostic construction into `WorkspaceRuntimeIssueBuilder`.
- Kept API base URL, auth mode, key state, model, agent status, rate-limit metadata, and redacted last-error snippets in one testable path.
- Added focused tests for status-derived issues, developer override diagnostics, rate-limit parsing, secret redaction, network issue messages, and malformed model-action fallback guidance.
- Reduced `WorkspaceSurface.swift` by roughly 540 lines while keeping the surface contract unchanged.

Remaining risk:

- `WorkspaceSurface.swift` still owns model category construction and command palette assembly. Those are pure, user-facing presentation builders and should be extracted before adding more Codex-parity actions.

## 2026-06-23 Model Catalog Surface Builder Pass

Overall grade after this slice: **A- foundation, A- surface boundary**.

Model picker label, category, favorite, recent, current-model fallback, and badge construction moved out of `WorkspaceSurface.swift` into `WorkspaceModelCatalogSurfaceBuilder`. The workspace surface now passes raw catalog/config/thread-history inputs to one pure builder and consumes only the resulting model label and category records.

Code quality changes:

- Extracted model label formatting and picker category construction into a focused builder.
- Kept catalog entries, selected/default IDs, ordered favorites, and recents at the builder boundary so picker ordering and badges can be tested without building a full workspace surface.
- Kept favorite and recent sections ordered, deduplicated, and directly testable outside the full workspace surface.
- Added focused tests for branded labels, favorite-before-recent ordering, deduplication, default/recommended/current badges, and unknown selected/favorite-model fallback.
- Extended parity gates so `WorkspaceSurface.swift` cannot regain model option and model category construction helpers.

Remaining risk:

- `WorkspaceSurface.swift` still owned command palette assembly and review-surface assembly after this slice. Those pure presentation paths should move before adding much more Codex-parity command or review UI.

## 2026-06-23 Command Surface Builder Pass

Overall grade after this slice: **A- foundation, A- surface boundary**.

Command palette row construction moved out of `WorkspaceSurface.swift` into `WorkspaceCommandSurfaceBuilder`. The workspace surface now supplies selected thread/project/sidebar/runtime inputs, while the builder owns command categories, availability, local environment action keywords, MCP lifecycle rows, extension update rows, Git commands, Stop All state, and Computer Use command gating.

Code quality changes:

- Extracted the formerly large command catalog into a focused pure builder with grouped helper sections.
- Kept command availability derived from value inputs so command behavior can be tested without booting the full workspace model.
- Added direct tests for conservative defaults, selected-thread and bulk-selection commands, local environment action search keywords, MCP start/stop gating, extension update rows, Git enablement, browser/terminal state, Stop All, and Computer Use permission commands.
- Extended parity gates so `WorkspaceSurface.swift` cannot regain command catalog, local-action, MCP lifecycle, or extension-update construction.

Remaining risk:

- `WorkspaceSurface.swift` still assembled review surfaces and context estimates after this slice. Review should move before richer diff-review parity grows.

## 2026-06-23 Review Surface Builder Pass

Overall grade after this slice: **A- foundation, A- surface boundary**.

Review diff construction moved out of `WorkspaceSurface.swift` into `WorkspaceReviewSurfaceBuilder`. The workspace surface now supplies tool cards and thread events, while the builder owns latest successful `host.git.diff` selection, `ToolResult` decoding, diff parsing, review-comment bucketing, timestamp ordering, and line-kind filtering.

Code quality changes:

- Extracted latest git-diff review assembly into a focused pure builder.
- Kept `WorkspaceReviewSurface` and related Codable surface records unchanged for compatibility.
- Added direct tests for hidden empty/failed reviews, successful diff summaries, stale latest-diff hiding, file comments, line comments, timestamp ordering, line-kind filtering, stale comments, and invalid payload tolerance.
- Extended parity gates so `WorkspaceSurface.swift` cannot regain review construction, comment bucketing, or direct git-diff parsing.

Remaining risk:

- `WorkspaceSurface.swift` still owned context-token estimation for warning banners after this slice. That should move before context/rate telemetry grows.

## 2026-06-23 Context Banner Builder Pass

Overall grade after this slice: **A- foundation, A- surface boundary**.

Context warning construction moved out of `WorkspaceSurface.swift` into `WorkspaceContextBannerBuilder`. The workspace surface now supplies only the selected thread, while the builder owns empty-thread hiding, context-token estimation, usage percent calculation, warning/full titles, threshold gating, and the New/Fork/Compact command surface.

Code quality changes:

- Extracted context pressure estimation and banner construction into a focused pure builder.
- Kept `ContextBannerSurface` Codable compatibility unchanged.
- Added direct tests for warning threshold behavior, full-context titles, hidden nil/empty/short threads, message/event/instruction contribution to estimates, and deterministic custom-budget checks.
- Extended parity gates so `WorkspaceSurface.swift` cannot regain context banner construction, usage calculation, or context token estimation.

Remaining risk:

- `WorkspaceSurface.swift` is now mostly orchestration over surface builders. Keep future transcript and tool-card projection behavior out of the model/surface orchestrators.

## 2026-06-23 Transcript Surface Builder Pass

Overall grade after this slice: **A- foundation, A- surface boundary**.

Transcript message, tool-card, feedback, and timeline projection moved out of `WorkspaceModel.swift` into `WorkspaceTranscriptSurfaceBuilder`. The workspace model now asks the builder for selected-thread cards and timeline items, then applies only project execution-context enrichment. The workspace surface asks the same builder for visible message rows, keeping transcript projection behavior in one pure helper.

Code quality changes:

- Extracted visible message projection, including hidden tool-message filtering and assistant feedback reduction.
- Extracted tool-card projection for queued/running/completed/failed tool events and safety-review cards.
- Extracted timeline interleaving so message events, tool cards, orphan tool completions, and eventless fallback threads are directly testable.
- Kept artifact text-preview construction routed through the focused artifact preview helper.
- Updated model tests to exercise the transcript builder directly and added focused builder tests for feedback, message/tool interleaving, fallback timelines, orphan failures, and safety-review expansion.
- Extended parity gates so `WorkspaceModel.swift` cannot regain tool-card, message, timeline, or feedback projection helpers.

Remaining risk:

- `WorkspaceModel.swift` is still the largest app file. The next A-level step should keep moving pure workflow planning or state transitions out of the model before adding more Codex-parity commands.

## 2026-06-23 Execution Context Surface Builder Pass

Overall grade after this slice: **A- foundation, A- surface boundary**.

Tool-card execution-context enrichment moved out of `WorkspaceModel.swift` into `WorkspaceExecutionContextSurfaceBuilder`. The workspace model still owns selected-thread/project state, but the builder now owns thread-project fallback, selected-project fallback, project-execution tool classification, and preserving existing card contexts.

Code quality changes:

- Extracted execution-context enrichment for standalone tool-card lists and chronological transcript timeline items.
- Centralized project-execution tool classification into a `Set` instead of a long inline boolean chain in the model.
- Kept non-project tools such as memories, MCP calls, and safety cards context-free so the UI does not imply they ran in a workspace.
- Added focused tests for thread-project precedence, selected-project fallback, missing-project handling, timeline enrichment, existing-context preservation, and excluded tool kinds.
- Extended parity gates so `WorkspaceModel.swift` cannot regain execution-context enrichment or project-execution tool classification.

Remaining risk:

- `WorkspaceModel.swift` still owns broad command side-effect orchestration. The next A-level step should target another pure planning/state transition path, not renderer-specific behavior.

## 2026-06-23 Thread Seed Builder Pass

Overall grade after this slice: **A- foundation, A- workflow boundary**.

Fork, compact-context, automation follow-up, and cancelled-send title seeding moved out of `WorkspaceModel.swift` into `WorkspaceThreadSeedBuilder`. The workspace model still owns thread creation, UI selection, persistence, and top-bar refresh, but the pure rules for visible-message filtering, latest-turn seed selection, compact summary text, and prompt-title derivation now live behind a focused builder.

Code quality changes:

- Extracted fork seed selection into a focused helper that starts at the latest user turn and hides internal tool feedback.
- Extracted compact-context seed construction, including bounded summary text and hidden tool-message filtering.
- Fixed prompt title seeding to split on all whitespace instead of spaces only, preventing invisible titles for cancelled whitespace-only prompts.
- Added focused tests for first-prompt titles, latest-turn forks, no-user fallback forks, compact summaries, truncation, and no-dropped-context summaries.
- Extended parity gates so `WorkspaceModel.swift` cannot regain fork seed, compact seed, or compact summary formatting.

Remaining risk:

- `WorkspaceModel.swift` still owns broad thread lifecycle side effects such as creation, selection fallback, persistence, and top-bar refresh. Future thread lifecycle growth should move through a pure reducer before adding more side-effect paths.

## 2026-06-23 Thread Lifecycle Engine Pass

Overall grade after this slice: **A- foundation, A- workflow boundary**.

Thread rename, duplicate, pin, archive, unarchive, and delete transitions moved out of `WorkspaceModel.swift` into `WorkspaceThreadLifecycleEngine`. The workspace model still owns persistence, selected-project validation, project touch timestamps, terminal sync, and top-bar refresh, but the pure thread mutations and fallback selection rules are now directly testable.

Code quality changes:

- Extracted title trimming and empty-title rejection for renames.
- Extracted duplicate-thread construction, including unpinned/unarchived defaults and duplicate audit notice.
- Extracted pin toggles plus single and bulk archive/unarchive state mutation with explicit changed-thread results for persistence.
- Extracted delete removal and newest-unarchived-thread fallback selection for selected-thread deletion.
- Added focused tests for rename trimming, duplicate shape, selected/non-selected archive behavior, bulk archive/unarchive behavior, unarchive project context, and selected/non-selected delete behavior.
- Extended parity gates so `WorkspaceModel.swift` cannot regain inline thread lifecycle mutation rules.

Remaining risk:

- Sidebar bulk actions still combine command dispatch, thread persistence, and project fallback in `WorkspaceModel`. Thread mutations now route through the lifecycle engine, and sidebar selection planning now routes through a dedicated reducer.

## 2026-06-23 Browser Location Resolver Pass

Overall grade after this slice: **A- foundation, A- browser workflow boundary**.

Browser address normalization, workspace-relative file resolution, snapshot-fetch eligibility, and browser-fetch error copy moved out of `WorkspaceModel.swift` into `WorkspaceBrowserLocationResolver`. The workspace model still owns browser visibility, history mutation, snapshot refresh, and transcript-side comments, but address parsing and fetch policy are now directly testable without booting the full workspace model.

Code quality changes:

- Extracted browser address trimming and explicit `http`/`https`/`file` URL acceptance.
- Extracted localhost shorthand handling for `localhost`, `127.0.0.1`, and `[::1]` development targets.
- Extracted conservative project-relative file resolution that requires existing files inside the workspace root.
- Extracted absolute existing-file and domain-shorthand handling.
- Extracted the rule that only `http` and `https` pages receive bounded HTML fetch upgrades.
- Added focused tests for explicit URLs, localhost shorthand, workspace-relative files, absolute files, domain shorthand, snapshot eligibility, and fetch error copy.
- Extended parity gates so `WorkspaceModel.swift` cannot regain inline browser URL normalization or fetch-policy helpers.

Remaining risk:

- Browser history, fetch refresh, and comment creation still live together in `WorkspaceModel`. If browser interaction grows toward live DOM sessions or signed-in browser profiles, those side effects should move behind a browser workflow coordinator before adding more state branches.

## 2026-06-23 Tool Override Combiner Pass

Overall grade after this slice: **A- foundation, A tool-dispatch composition boundary**.

Agent tool override composition moved out of `WorkspaceModel.swift` into `WorkspaceToolExecutionOverrideCombiner`. The workspace model still creates the optional Plan, Remote Project, Browser, Computer Use, Memory, and MCP executors, but their precedence and nil-fallthrough rules are now directly tested without constructing the full workspace model.

Code quality changes:

- Moved the override precedence chain into `WorkspaceToolExecutionOverrideCombiner.combine`.
- Preserved the dispatch order: Plan, Remote Project, Browser, Computer Use, Memory, MCP.
- Added focused tests for empty composition, first-result precedence, nil fallthrough, and no-result fallthrough.
- Extended parity gates so `WorkspaceModel.swift` cannot regain the inline precedence chain.

Remaining risk:

- Remote-project tool execution was the next extraction target after this pass and now lives in `WorkspaceRemoteProjectToolExecutor`.

## 2026-06-23 Review Comment Planner Pass

Overall grade after this slice: **A- foundation, A review-comment boundary**.

Review comment payload state, path/text trimming, visible-diff-file validation, line-range normalization, range existence checks, summary formatting, and `ThreadEvent` payload encoding moved out of `WorkspaceModel.swift` into `WorkspaceReviewCommentPlanner`. The workspace model still owns the selected-thread guard, event append, thread persistence, and top-bar refresh, but the review-comment rules are now directly tested without constructing the full workspace model.

Code quality changes:

- Moved `WorkspaceReviewCommentState` out of the workspace model and beside the planner that creates it.
- Added direct planner tests for file comments, line comments, reversed ranges, line-kind checks, stale files, blank input, invalid zero-line comments, partial ranges, and missing range lines.
- Tightened review-comment behavior so invalid supplied line ranges are rejected instead of silently becoming file-level comments.
- Extended parity gates so `WorkspaceModel.swift` cannot regain review-comment payload state, range normalization, range validation, or JSON payload encoding.

Remaining risk:

- Review action dispatch still lives in `WorkspaceModel` because it executes git tools, appends tool cards, refreshes diffs, and persists selected-thread state. If review workflows grow into staged review sessions or PR comment publication, add a review workflow coordinator instead of expanding the model.

## 2026-06-23 Browser Engine Pass

Overall grade after this slice: **A- foundation, A browser workflow boundary**.

Browser page state, history navigation, reload status, fetched-page replacement, fetch-failure annotation, and browser comments moved out of `WorkspaceModel.swift` into `WorkspaceBrowserEngine`. The workspace model still owns address resolution, async page fetching, `lastError`, and top-bar refreshes, but the pure `BrowserState` transitions are now directly tested.

Code quality changes:

- Added `WorkspaceBrowserEngine.openPage` to centralize preview-ready page state and history insertion.
- Added directly tested back/forward/reload transitions, including forward-history pruning when opening a new page after going back.
- Added fetched-page replacement logic that updates the current URL, address draft, current history entry, snapshot, title, and status together.
- Added fetch-failure annotation logic that preserves the metadata snapshot and appends readable diagnostics.
- Added browser comment trimming and current-page validation outside the workspace model.
- Extended parity gates so `WorkspaceModel.swift` cannot regain browser history mutation, comment construction, or fetch-failure annotation copy.

Remaining risk:

- Browser fetch orchestration still lives in `WorkspaceModel` because it coordinates async fetches, stale-current-URL protection, top-bar refresh, and runtime error clearing. If browser work grows toward live DOM sessions, move those async workflows behind a browser coordinator while keeping pure state transitions in this engine.

## 2026-06-23 Sidebar Selection Engine Pass

Overall grade after this slice: **A- foundation, A- sidebar workflow boundary**.

Sidebar bulk-selection state moved out of `WorkspaceModel.swift` into `WorkspaceSidebarSelectionEngine`. The workspace model still owns command dispatch, thread persistence, project fallback selection, and top-bar refresh, but the pure selection transitions now live in one directly tested reducer.

Code quality changes:

- Moved `SidebarSelectionState` beside the reducer that owns its transitions.
- Extracted start-selection behavior, including optional valid-thread selection and invalid-thread ignoring.
- Extracted clear and select-all behavior, including the empty-sidebar fallback to inactive selection mode.
- Extracted toggle behavior with explicit unknown-thread rejection.
- Extracted stale-ID pruning and sidebar-order resolution so selection order follows the visible sidebar rather than hash-set ordering.
- Added focused tests for start, select-all, toggle, stale pruning, ordering, and all-stale active selection behavior.
- Extended parity gates so `WorkspaceModel.swift` cannot regain direct sidebar-selection set mutation.

Remaining risk:

- Bulk action persistence and top-bar refresh still live in `WorkspaceModel`, but target resolution and follow-up selection policy now route through a dedicated planner.

## 2026-06-23 Sidebar Bulk Action Planner Pass

Overall grade after this slice: **A- foundation, A- sidebar workflow boundary**.

Sidebar bulk action planning moved out of `WorkspaceModel.swift` into `WorkspaceSidebarBulkActionPlanner`. The model still owns thread persistence, project fallback application, terminal sync, and top-bar refresh, but the pure rules for selection-only commands, visible-order target resolution, stale-selection pruning, and post-mutation selection intent are now directly tested.

Code quality changes:

- Added a focused planner that maps `SidebarBulkActionKind` into either selection-state changes or mutation plans.
- Centralized bulk pin/unpin/archive/unarchive/delete target resolution using the same visible sidebar order as the selection engine.
- Made archive/delete fallback behavior explicit through `FollowUpSelection.selectBestAfterRemoving`.
- Made unarchive behavior explicit through `FollowUpSelection.select`, keeping "select the first visible unarchived target" out of the model.
- Added direct tests for selection-only actions, stale-ID pruning, visible ordering, empty-selection rejection, archive fallback, unarchive selection, and delete reconciliation.
- Extended parity gates so `WorkspaceModel.swift` cannot regain inline bulk selected-ID planning.

Remaining risk:

- `WorkspaceModel` still applies the planner's effects because persistence, selected-project validation, terminal sync, and top-bar refresh remain side effects. If bulk actions grow into undoable operations or previewable destructive actions, add a side-effect executor layer rather than expanding `performSidebarBulkAction` again.

## 2026-06-23 Sidebar Command Presentation Pass

Overall grade after this slice: **A- foundation, A sidebar presentation boundary**.

Sidebar rail command labels, icon choices, primary command ordering, utility command ordering, HTML icon tokens, and Playwright test IDs moved into `QuillCodeSidebarCommandPresentation`. SwiftUI and static HTML now consume the same sidebar command contract instead of carrying separate hard-coded maps.

Code quality changes:

- Centralized the Codex-like primary rail order: New chat, Search, Plugins, Automations.
- Centralized the compact utility menu order: Terminal, Browser, Memories, Activity, Command palette.
- Removed duplicated sidebar `displayTitle` and `systemImage` switch statements from the native SwiftUI view.
- Made the HTML harness render primary sidebar actions from real `WorkspaceCommandSurface` values instead of static markup.
- Added focused tests for primary labels, SF Symbols, HTML icon tokens, test IDs, utility labels, and settings presentation.

Remaining risk:

- This keeps the sidebar presentation contract DRY, but broader rail information architecture still needs user-facing visual review as more Codex parity surfaces land.

## 2026-06-23 Desktop Copy Coordinator Pass

Overall grade after this slice: **A- foundation, A desktop boundary**.

Transcript copy behavior moved out of `QuillCodeDesktopController.swift` into `QuillCodeDesktopCopyCoordinator`. The controller still owns visible copied-item state because that is UI state, but blank-copy rejection, pasteboard mutation, and the transient feedback duration now live in one focused desktop helper behind a pasteboard-writing protocol.

Code quality changes:

- Added `QuillCodeDesktopCopyFeedback` so copy feedback state is an explicit value.
- Added `QuillCodePasteboardWriting` and `MacPasteboardWriter` so concrete AppKit pasteboard access stays out of UI routing.
- Removed direct `NSPasteboard` mutation and the copy-feedback timing literal from the desktop controller.
- Removed the controller's `AppKit` import now that platform pasteboard access is delegated.
- Extended parity gates so the controller cannot regain pasteboard mutation or copy-feedback timing details.

Remaining risk:

- Project import remains simple enough to stay in the controller today. If import handling grows into recent locations, validation, or error recovery, move it behind a focused desktop project-import coordinator instead of expanding the controller.

## 2026-06-23 Desktop Project Import Coordinator Pass

Overall grade after this slice: **A- foundation, A desktop boundary**.

Desktop project import result handling moved out of `QuillCodeDesktopController.swift` into `QuillCodeDesktopProjectImportCoordinator`. The controller still owns the SwiftUI importer presentation flag because that is sheet state, but result parsing, selected URL normalization, and directory validation now live in one focused coordinator.

Code quality changes:

- Added `QuillCodeDesktopProjectImportSelection` so a successful import is explicit value data.
- Added `QuillCodeDesktopProjectImportCoordinator` to resolve `fileImporter` results into a validated project directory.
- Validates imported URLs with `FileManager.fileExists(..., isDirectory:)` instead of assuming the first returned URL is usable.
- Reduced `QuillCodeDesktopController.handleProjectImport` to coordinator delegation plus the existing project-add path.
- Extended parity gates so the controller cannot regain raw file-import result parsing or directory validation.

Remaining risk:

- Project-import errors are intentionally quiet today because cancelled import and invalid import both no-op. If the app starts surfacing import errors, add a small user-visible import status model to this coordinator rather than expanding controller state.

## 2026-06-23 Remote Project Tool Executor Pass

Overall grade after this slice: **A- foundation, A SSH Remote tool boundary**.

SSH Remote shell, file, patch, git, PR, and worktree tool execution moved out of `WorkspaceModel.swift` into `WorkspaceRemoteProjectToolExecutor`. The workspace model still owns selected-project orchestration, transcript event append, persistence, review diff refresh, and top-bar side effects, but the remote-safe tool catalog, override construction, command construction, path normalization, artifact labeling, and unsupported-tool behavior are now directly tested.

Code quality changes:

- Added a focused executor for the SSH Remote base tool catalog and remote-agent override construction.
- Collapsed manual, agent, review, and post-patch remote execution paths through the same executor.
- Kept local-only tools from falling back into remote projects by returning clear unsupported-tool errors for manual calls and nil fallthrough for agent overrides.
- Added focused tests for the remote tool catalog, remote-only override eligibility, SSH shell command wrapping, file-write artifact labeling, and unsupported-tool errors.
- Extended parity gates so `WorkspaceModel.swift` cannot regain remote git/shell routing or remote path normalization.

Remaining risk:

- Review workflow orchestration still lives in `WorkspaceModel` because it appends tool cards, refreshes diffs, and persists selected-thread state. If review sessions grow into multi-step PR publication or staged remote review state, add a review workflow coordinator that consumes `WorkspaceRemoteProjectToolExecutor` instead of expanding the model again.

## 2026-06-23 Command Palette Surface Pass

Overall grade after this slice: **A- foundation, A command surface boundary**.

Command surface records, top-bar overflow projection, automation/Computer Use command factories, command grouping, palette query scoping, and ranking/scoring moved out of `WorkspaceSurface.swift` into `WorkspaceCommandPaletteSurface.swift`. `WorkspaceSurface.swift` still owns the aggregate `WorkspaceSurface` payload and simple surface records, but command-palette behavior now lives beside the command contract that SwiftUI, static HTML, Playwright, menu bar, slash suggestions, and keyboard shortcut surfaces consume.

Code quality changes:

- Moved `WorkspaceCommandSurface`, `TopBarOverflowCommandCatalog`, `WorkspaceCommandGroupSurface`, and `WorkspaceCommandPalette` into a focused surface file.
- Kept command ranking, `/` slash scoping, `>` action scoping, category ordering, and compact shortcut matching together.
- Removed roughly 400 lines of command-palette code from the aggregate workspace surface file.
- Added a parity gate so command records, overflow projection, palette ranking, and query scoping do not drift back into `WorkspaceSurface.swift`.

Remaining risk:

- `WorkspaceSurface.swift` still carries many value surface records. That is acceptable while they are small Codable contracts, but any surface record that grows behavioral helpers should move to a focused surface-family file before adding more Codex-parity UI.

## 2026-06-23 Settings Surface Contract Pass

Overall grade after this slice: **A- foundation, A settings surface boundary**.

Settings surface records, settings updates, Computer Use requirement rows, TrustedRouter sign-in copy, Computer Use permission copy, and backwards-compatible decoding moved out of `WorkspaceSurface.swift` into `QuillCodeSettingsSurface.swift`. `WorkspaceSurface.swift` still owns the aggregate `settings` slot and passes runtime state into `WorkspaceSettingsSurface`, while settings-specific labels and compatibility fallbacks stay beside the settings contract consumed by SwiftUI, static HTML, Playwright, and desktop persistence.

Code quality changes:

- Moved `WorkspaceSettingsSurface`, `WorkspaceSettingsUpdate`, and `ComputerUseRequirementSurface` into a focused settings surface file.
- Kept Computer Use status labels, setup summaries, next-action copy, and legacy payload decoding with the settings contract instead of the aggregate workspace surface.
- Removed roughly 240 lines of settings-specific behavior from `WorkspaceSurface.swift`.
- Added a parity gate so settings records, Computer Use requirement rows, TrustedRouter loopback sign-in copy, and Computer Use status copy do not drift back into `WorkspaceSurface.swift`.

Remaining risk:

- `WorkspaceSurface.swift` still carries many small value records. That remains acceptable while those records are plain Codable data, but any record with compatibility decoding or presentation helpers should move into a focused surface-family file before new Codex-parity behaviors land.

## 2026-06-23 HTML Tool Card Renderer Pass

Overall grade after this slice: **A- foundation, A static HTML tool-card boundary**.

Static HTML tool-card rendering, artifact chips, text previews, document previews, image previews, raw details, copy labels, and document icon labels moved out of `WorkspaceHTMLRenderer.swift` into `WorkspaceHTMLToolCardRenderer.swift`. Shared HTML escaping and execution-context chip rendering moved into `WorkspaceHTMLPrimitives.swift`, so tool cards and terminal rows no longer maintain separate context-chip markup.

Code quality changes:

- Added `WorkspaceHTMLToolCardRenderer` as the focused owner for tool-card HTML.
- Added `WorkspaceHTMLPrimitives` for shared escaping and execution-context chip markup.
- Reduced the static HTML renderer by roughly 190 lines while keeping the public `WorkspaceHTMLRenderer.render(_:)` contract unchanged.
- Added a parity gate so artifact, preview, details, document-icon, escaping, and execution-context chip markup do not drift back into the monolithic renderer.

Remaining risk:

- `WorkspaceHTMLRenderer.swift` still owns several pane renderers because it is the static harness composition point. Keep extracting whole pane families only when they gain enough behavior to risk drifting from SwiftUI.

## 2026-06-23 HTML Terminal Renderer Pass

Overall grade after this slice: **A- foundation, A static HTML terminal boundary**.

Static HTML terminal pane rendering, terminal entry rendering, execution-context chip placement, stdout/stderr previews, and terminal status CSS mapping moved out of `WorkspaceHTMLRenderer.swift` into `WorkspaceHTMLTerminalRenderer.swift`. The static harness still composes the whole workspace document, but terminal-specific HTML now has a focused owner like tool cards.

Code quality changes:

- Added `WorkspaceHTMLTerminalRenderer` as the focused owner for terminal pane HTML.
- Reused `WorkspaceHTMLPrimitives` for terminal escaping and execution-context chip markup.
- Reduced `WorkspaceHTMLRenderer.swift` by another terminal-pane block while preserving the same `terminal-*` test IDs used by Playwright and surface tests.
- Added a parity gate so terminal pane rendering and status-class mapping do not drift back into the monolithic HTML renderer.

Remaining risk:

- Browser was the next pane-family extraction candidate after this terminal slice. Keep extracting whole pane families only when they gain enough behavior to justify their own renderer.

## 2026-06-23 HTML Browser Renderer Pass

Overall grade after this slice: **A- foundation, A static HTML browser boundary**.

Static HTML browser pane rendering, preview/empty-state rendering, snapshot metadata rendering, outline/text snippet rendering, and browser comment rendering moved out of `WorkspaceHTMLRenderer.swift` into `WorkspaceHTMLBrowserRenderer.swift`. This matches the existing browser state, browser location, and browser engine boundaries by keeping browser-specific presentation code beside the browser harness renderer instead of the workspace document composer.

Code quality changes:

- Added `WorkspaceHTMLBrowserRenderer` as the focused owner for browser pane HTML.
- Kept snapshot preview, outline, text snippet, comments, navigation controls, and empty-state markup in one file.
- Reused `WorkspaceHTMLPrimitives` for escaping so browser harness rendering shares the same HTML escaping path as terminal and tool-card rendering.
- Added a parity gate so browser preview, snapshot, and comment markup do not drift back into `WorkspaceHTMLRenderer.swift`.

Remaining risk:

- Extensions, memories, automations, and activity pane rendering were the next pane-family extraction candidates after this browser slice. Review pane rendering still lives in `WorkspaceHTMLRenderer.swift`; extract it when diff/comment markup grows further.

## 2026-06-23 HTML Secondary Pane Renderer Pass

Overall grade after this slice: **A- foundation, A static HTML secondary pane boundary**.

Static HTML Extensions, Memories, Activity, and Automations rendering moved out of `WorkspaceHTMLRenderer.swift` into `WorkspaceHTMLSecondaryPaneRenderer.swift`. This mirrors the native `QuillCodeSecondaryPanesView` boundary and keeps MCP extension metadata, memory card markup, automation action buttons, activity sections, and secondary-pane pluralization helpers away from the whole-workspace HTML composer.

Code quality changes:

- Added `WorkspaceHTMLSecondaryPaneRenderer` as the focused owner for secondary utility pane HTML.
- Kept MCP metadata/tool/resource/prompt chip rendering beside Extensions HTML.
- Kept automation create/schedule/run/resume/pause/delete buttons beside Automations HTML.
- Kept activity section empty/body/artifact/item rendering beside Activity HTML.
- Reused `WorkspaceHTMLPrimitives` for escaping so secondary panes share the same HTML escaping path as terminal, browser, and tool-card rendering.
- Added a parity gate so secondary pane markup and count-label helpers do not drift back into `WorkspaceHTMLRenderer.swift`.

Remaining risk:

- Transcript message, context banner, runtime issue, and composer rendering still live in `WorkspaceHTMLRenderer.swift`. Extract another whole transcript family only when behavior grows enough to justify the extra file.

## 2026-06-23 HTML Review Renderer Pass

Overall grade after this slice: **A- foundation, A static HTML review boundary**.

Static HTML review pane rendering, file rows, hunk rows, diff lines, inline review comments, and review action buttons moved out of `WorkspaceHTMLRenderer.swift` into `WorkspaceHTMLReviewRenderer.swift`. This mirrors the native `QuillCodeReviewPaneView` boundary and keeps diff-specific markup away from the transcript/document composer.

Code quality changes:

- Added `WorkspaceHTMLReviewRenderer` as the focused owner for Git review pane HTML.
- Kept review file, hunk, line, inline comment, and action markup in one file.
- Reused `WorkspaceHTMLPrimitives` for escaping so review HTML shares the same escaping path as tool-card, terminal, browser, and secondary-pane rendering.
- Added a parity gate so review hunk/line/action markup does not drift back into `WorkspaceHTMLRenderer.swift`.

Remaining risk:

- `WorkspaceHTMLRenderer.swift` still owns transcript message, context banner, runtime issue, and composer rendering. Those are now transcript-level concerns; extract them only when they begin to grow or diverge from the SwiftUI shell.

## 2026-06-23 HTML Sidebar Renderer Pass

Overall grade after this slice: **A- foundation, A static HTML sidebar boundary**.

Static HTML sidebar rendering, project rows, pinned/recent/archived thread sections, bulk-selection controls, primary sidebar actions, thread row actions, and the tools/settings footer moved out of `WorkspaceHTMLRenderer.swift` into `WorkspaceHTMLSidebarRenderer.swift`. This mirrors the native sidebar as a first-class shell region and keeps navigation/project markup out of transcript composition.

Code quality changes:

- Added `WorkspaceHTMLSidebarRenderer` as the focused owner for static sidebar HTML.
- Kept project rendering, thread section rendering, bulk-selection rendering, and footer action rendering together.
- Preserved shared primary-action labels/icons through `QuillCodeSidebarCommandPresentation`.
- Reused `WorkspaceHTMLPrimitives` for escaping so sidebar HTML shares the same escaping path as the other static renderers.
- Added parity gates so sidebar project/thread/bulk/footer markup does not drift back into `WorkspaceHTMLRenderer.swift`.

Remaining risk:

- `WorkspaceHTMLRenderer.swift` still owns transcript message, context banner, runtime issue, and composer rendering. Those are the remaining transcript concerns; extract only when the behavior grows enough to justify another file.

## 2026-06-23 HTML Top-Bar Renderer Pass

Overall grade after this slice: **A- foundation, A static HTML top-bar boundary**.

Static HTML top-bar rendering, project instruction and memory status, Computer Use status, runtime issue pill, and overflow command buttons moved out of `WorkspaceHTMLRenderer.swift` into `WorkspaceHTMLTopBarRenderer.swift`. Model/mode display later moved to composer rendering, keeping shell identity/status rendering beside the top-bar contract instead of mixing it into transcript composition.

Code quality changes:

- Added `WorkspaceHTMLTopBarRenderer` as the focused owner for static top-bar HTML.
- Kept primary, context, and action cluster rendering together.
- Preserved shared overflow command projection through `TopBarOverflowCommandCatalog`.
- Reused `WorkspaceHTMLPrimitives` for escaping so top-bar HTML shares the same escaping path as the other static renderers.
- Added a parity gate so top-bar cluster, runtime issue, and overflow markup do not drift back into `WorkspaceHTMLRenderer.swift`.

Remaining risk:

- `WorkspaceHTMLRenderer.swift` still owns transcript message, context banner, runtime issue panel, and composer rendering. Those are the remaining transcript-level concerns; extract them only when behavior grows enough to justify another focused renderer.

## 2026-06-23 Browser Surface Contract Pass

Overall grade after this slice: **A- foundation, A browser surface boundary**.

Browser presentation records moved out of `WorkspaceSurface.swift` into `QuillCodeBrowserSurface.swift`, beside the existing browser state records. This keeps browser state, snapshot state, comment state, and the corresponding UI-facing surface contracts in one focused browser file instead of splitting the feature family between the aggregate workspace payload and the browser state file.

Code quality changes:

- Moved `BrowserSurface`, `BrowserSnapshotSurface`, and `BrowserCommentSurface` beside `BrowserState`, `BrowserSnapshotState`, and `BrowserCommentState`.
- Kept browser snapshot compatibility decoding beside the snapshot state it represents.
- Left `WorkspaceSurface.swift` responsible only for carrying the aggregate `browser` slot and constructing it from `BrowserState`.
- Added parity gates so browser presentation records do not drift back into `WorkspaceSurface.swift`.

Remaining risk:

- The aggregate `WorkspaceSurface.swift` still carries foundational value records such as project list, top bar, and sidebar surfaces. That is acceptable while they stay compact; extract each family when its presentation helpers or compatibility decoding grows.

## 2026-06-23 Secondary Pane Surface Contract Pass

Overall grade after this slice: **A- foundation, A secondary-pane surface boundary**.

Extensions, Memories, and Automations presentation records moved out of `WorkspaceSurface.swift` into `QuillCodeSecondaryPaneSurface.swift`, matching the existing native `QuillCodeSecondaryPanesView` and static `WorkspaceHTMLSecondaryPaneRenderer` boundaries. The aggregate workspace surface still carries `extensions`, `memories`, and `automations` slots, but the count labels, MCP probe compatibility, memory previews, delete command IDs, automation row actions, and configured/planned workflow status rules live beside the secondary-pane contract.

Code quality changes:

- Moved `WorkspaceExtensionsSurface`, `WorkspaceMemoriesSurface`, `WorkspaceAutomationsSurface`, `ProjectExtensionManifestSurface`, `MemoryNoteSurface`, and `AutomationWorkflowSurface` into one focused secondary-pane surface file.
- Kept MCP descriptor compatibility decoding beside extension row presentation.
- Added direct surface tests for extension counts/MCP actions, memory preview/delete rules, and automation status/action mapping.
- Added a parity gate so secondary-pane records do not drift back into `WorkspaceSurface.swift`.

Remaining risk:

- Project/sidebar/top-bar records still live in `WorkspaceSurface.swift`; extract those families when their presentation logic grows beyond compact Codable contracts.

## 2026-06-23 Terminal Surface Contract Pass

Overall grade after this slice: **A- foundation, A terminal surface boundary**.

Terminal presentation records moved out of `WorkspaceSurface.swift` into `QuillCodeTerminalSurface.swift`, matching the existing native `QuillCodeTerminalBrowserPaneView`, static `WorkspaceHTMLTerminalRenderer`, and terminal engine boundaries. The aggregate workspace surface still carries the `terminal` slot, but run/clear availability, cwd label fallback, terminal command lifecycle labels, and execution-context preservation now live beside the terminal contract.

Code quality changes:

- Moved `TerminalSurface` and `TerminalCommandSurface` into one focused terminal surface file.
- Kept terminal engine state mapping close to the native/static terminal pane boundary.
- Added direct terminal surface tests for cwd fallback, run/clear availability, command status labels, stopped/running state, and execution-context propagation.
- Added a parity gate so terminal surface records do not drift back into `WorkspaceSurface.swift`.

Remaining risk:

- Project/sidebar/top-bar records still live in `WorkspaceSurface.swift`; extract those families when their presentation logic grows beyond compact Codable contracts.

## 2026-06-23 Review Surface Contract Pass

Overall grade after this slice: **A- foundation, A review surface boundary**.

Git review presentation records moved out of `WorkspaceSurface.swift` into `QuillCodeReviewSurface.swift`, matching the existing native `QuillCodeReviewPaneView`, static `WorkspaceHTMLReviewRenderer`, and `WorkspaceReviewSurfaceBuilder` boundaries. The aggregate workspace surface still carries the `review` slot, but review summary totals, file/hunk/line labels, review comment line-range copy, and stage/restore action presentation now live beside the review-pane contract.

Code quality changes:

- Moved `WorkspaceReviewSurface`, file/hunk/line/comment rows, review line/action enums, and review action records into one focused review surface file.
- Kept review action IDs, labels, and symbols with the review-pane contract instead of the workspace aggregate payload.
- Added direct review surface tests for totals, visibility, file/hunk labels, stage/restore action IDs, line markers/labels, and comment range labels.
- Added a parity gate so review presentation records do not drift back into `WorkspaceSurface.swift`.

Remaining risk:

- `WorkspaceSurface.swift` still owns project/sidebar/top-bar value records. Those are the next clean extraction candidates when their presentation behavior or compatibility decoding grows.

## 2026-06-23 Transcript Surface Contract Pass

Overall grade after this slice: **A- foundation, A transcript surface boundary**.

Transcript, context-banner, message, and composer presentation records moved out of `WorkspaceSurface.swift` into `QuillCodeTranscriptSurface.swift`, matching the existing `WorkspaceTranscriptSurfaceBuilder`, `WorkspaceContextBannerBuilder`, native transcript/composer/context-banner views, and static HTML transcript renderer boundaries. The aggregate workspace surface still carries transcript, context, and composer slots, but timeline IDs, empty-state copy, context-banner compatibility, message accessibility labels, sendability, and slash suggestion projection now live beside the transcript contract.

Code quality changes:

- Moved `TranscriptSurface`, `TranscriptTimelineItemKind`, `TranscriptTimelineItemSurface`, `ContextBannerSurface`, `MessageSurface`, and `ComposerSurface` into one focused transcript surface file.
- Kept context-banner backwards-compatible decoding with the transcript-level surface contract instead of the aggregate workspace payload.
- Added direct transcript surface tests for timeline construction, message accessibility/feedback mapping, composer sendability/slash suggestions, and context-banner compatibility.
- Added a parity gate so transcript/composer/context-banner records do not drift back into `WorkspaceSurface.swift`.

Remaining risk:

- `WorkspaceSurface.swift` still owns project and sidebar value records. They are the next extraction candidates when their presentation behavior or compatibility decoding grows.

## 2026-06-23 Top-Bar Model Surface Contract Pass

Overall grade after this slice: **A- foundation, A top-bar/model surface boundary**.

Top-bar and model-picker presentation records moved out of `WorkspaceSurface.swift` into `QuillCodeTopBarSurface.swift`, matching the existing native top-bar/composer model-picker views, static HTML renderers, and `WorkspaceModelCatalogSurfaceBuilder` boundary. The aggregate workspace surface still carries the `topBar` slot, but model option compatibility decoding, model detail copy, metadata rows, badge/state summaries, and searchable category filtering now live beside the top-bar/model-picker contract.

Code quality changes:

- Moved `TopBarSurface`, `ModelCategorySurface`, `ModelMetadataRowSurface`, and `ModelOptionSurface` into one focused top-bar surface file.
- Kept model picker filtering and backwards-compatible model option decoding with the model-picker surface contract instead of the aggregate workspace payload.
- Added direct top-bar surface tests for favorite/recent filtering, metadata search, TrustedRouter branded metadata, compatibility decoding, and stable row identifiers.
- Added a parity gate so top-bar/model-picker records and filtering do not drift back into `WorkspaceSurface.swift`.

Remaining risk:

- Project/sidebar contracts were the remaining extraction candidate after this slice and are addressed by the following sidebar surface pass.

## 2026-06-23 Sidebar Surface Contract Pass

Overall grade after this slice: **A- foundation, A sidebar surface boundary**.

Project and chat sidebar presentation records moved out of `WorkspaceSurface.swift` into `QuillCodeSidebarSurface.swift`, matching the existing native `QuillCodeSidebarView`, static `WorkspaceHTMLSidebarRenderer`, sidebar command presentation helper, selection reducer, and bulk action planner boundaries. The aggregate workspace surface still carries `projects` and `sidebar` slots, but project action defaults, thread action defaults, selection copy, bulk command IDs, pinned/recent/archived grouping, sidebar search, and backwards-compatible decoding now live beside the sidebar contract.

Code quality changes:

- Moved `ProjectListSurface`, `ProjectItemSurface`, `ProjectItemActionKind`, `ProjectItemActionSurface`, `SidebarSurface`, `SidebarItemSurface`, `SidebarBulkActionKind`, `SidebarBulkActionSurface`, `SidebarItemActionKind`, and `SidebarItemActionSurface` into one focused sidebar surface file.
- Kept thread/project action IDs and labels close to the UI boundary consumed by SwiftUI, static HTML, command palette routes, and slash routes.
- Added direct sidebar surface tests for project remote-state rows, older project payloads, sidebar filtering/grouping/selection copy, older sidebar payloads, active/pinned/archived thread actions, older thread payloads, and stable bulk command IDs.
- Added a parity gate so sidebar/project records, search filtering, and selection copy do not drift back into `WorkspaceSurface.swift`.

Remaining risk:

- `WorkspaceSurface.swift` still owns runtime/execution-context value records and aggregate assembly. Those are acceptable while compact, but runtime/execution context contracts should move if compatibility decoding or renderer-specific presentation grows.

## 2026-06-23 Thread Creation Engine Pass

Overall grade after this slice: **A- foundation, A- workspace thread boundary**.

Thread record construction moved out of `WorkspaceModel.swift` into `WorkspaceThreadCreationEngine.swift`. The model still owns persistence, selected-project validation, sidebar selection clearing, terminal sync, project touch timestamps, and top-bar refresh, but the value rules for new chats, forked chats, compacted chats, and duplicated chats now live behind focused pure helpers with direct tests.

Code quality changes:

- Added `WorkspaceThreadCreationContext` for new-chat project/mode/model/instruction/memory inputs.
- Moved fork, compact, and duplicate record construction beside the thread creation boundary instead of mixing it with lifecycle mutation rules.
- Kept visible-message filtering and compact-summary formatting in `WorkspaceThreadSeedBuilder`, so creation does not duplicate seed logic.
- Added a single model insertion helper for created threads, removing repeated insert/select/touch/save/top-bar code paths.
- Added focused creation-engine tests for context propagation, latest-visible-turn fork seeds, compact summaries, and duplicate pinned/archive reset behavior.

Remaining risk:

- `WorkspaceModel.swift` is still the largest file at roughly 2.6k lines. Continue extracting pure side-effect planning and state-reducer pockets before adding more Codex-parity commands.

## 2026-06-23 Workspace Configuration Engine Pass

Overall grade after this slice: **A- foundation, A workspace configuration boundary**.

Mode/model selection and TrustedRouter model-list configuration rules moved out of `WorkspaceModel.swift` into `WorkspaceConfigurationEngine.swift`. The model still owns UI orchestration and top-bar refresh timing, but pure state transitions for selected mode, selected model, favorite models, model catalog replacement, settings application, and selected-thread sync now live behind a focused engine with direct tests.

Code quality changes:

- Moved model ID normalization and fallback behavior into a single helper used by both config and selected-thread updates.
- Moved favorite toggle normalization into one path that canonicalizes aliases, rejects blank model IDs, and deduplicates through `AppConfig`.
- Moved catalog replacement behind a nil-returning normalization helper so empty API responses preserve the current catalog.
- Added focused tests for mode/model updates, blank-model fallback, favorites, catalog normalization, and settings/thread sync.
- Added a parity gate so configuration transitions do not drift back into `WorkspaceModel.swift`.

Remaining risk:

- `WorkspaceModel.swift` remains large and still owns mixed orchestration for tool dispatch, async browser fetches, and persistence. The next high-value extractions are side-effect planners around tool dispatch or settings/runtime command routing.

## 2026-06-23 Tool Event Recorder Pass

Overall grade after this slice: **A- foundation, A tool audit event boundary**.

Tool queued/running/completed/failed transcript event construction moved out of `WorkspaceModel.swift` into `WorkspaceToolEventRecorder.swift`. The workspace model still decides when to record tool runs, but call redaction, payload JSON construction, result status classification, and ordered event append behavior now live behind a focused helper with direct tests.

Code quality changes:

- Added `WorkspaceToolEventRecorder.events(call:result:)` for pure event construction.
- Added `WorkspaceToolEventRecorder.append(call:result:to:)` for thin thread mutation without repeating event ordering.
- Preserved redacted call payloads for queued events and full `ToolResult` payloads for completion/failure events.
- Added focused tests for successful tool runs, failed tool runs, environment redaction, and ordered append behavior.
- Added a parity gate so tool audit payload construction does not drift back into `WorkspaceModel.swift`.

Remaining risk:

- `WorkspaceModel.swift` still owns the broader tool dispatch sequence: context refresh, router selection, remote execution, follow-up diff collection, persistence, and top-bar status. Those are good candidates for a later orchestration planner once the public behavior is even more heavily covered.

## 2026-06-23 Worktree Open Engine Pass

Overall grade after this slice: **A- foundation, A worktree handoff boundary**.

Worktree request values and successful worktree handoff thread construction moved out of `WorkspaceModel.swift`. The model still owns the important side effects: running the git worktree tool, registering the resulting local or SSH Remote project, selecting the new project/thread, syncing the terminal session, persisting project/thread stores, and refreshing the top bar. The pure transcript contract for the new `Worktree: ...` thread now lives in `WorkspaceWorktreeOpenEngine` with direct tests.

Code quality changes:

- Moved `WorkspaceWorktreeCreateRequest` and `WorkspaceWorktreeRemoveRequest` into `WorkspaceWorktreeRequests.swift`.
- Added `WorkspaceWorktreeOpenContext` so mode, model, instructions, and memories are passed explicitly into worktree handoff records.
- Added focused local and SSH Remote thread builders for display labels, notice payloads, and assistant handoff messages.
- Added one shared `openCreatedWorktreeThread` path for selecting, touching, saving, and top-bar refreshing after local or remote worktree creation.
- Added direct engine tests plus a parity gate so worktree handoff copy and request structs do not drift back into `WorkspaceModel.swift`.

Remaining risk:

- Worktree tool argument construction still lives in the workspace model because it is tightly coupled to immediate tool dispatch. If create/remove flows gain more validation or preview UI, move request normalization into a separate planner rather than adding another branch to the model.

## 2026-06-23 Workspace Status Text Builder Pass

Overall grade after this slice: **A- foundation, A status-copy boundary**.

Status copy and context labels moved into `WorkspaceStatusTextBuilder`. Before this pass, `/status` copy lived in `WorkspaceModel` while top-bar mode/instruction/memory labels lived in `WorkspaceSurface`, which made small UX wording changes easy to apply in one surface and miss in another. The model now delegates slash status and slash mode confirmation labels, and the surface delegates top-bar subtitles plus instruction/memory/mode labels to the same focused helper.

Code quality changes:

- Added `WorkspaceStatusContext` as a compact value for project/thread/context/model/agent status copy.
- Added shared builders for `/status` transcript copy, top-bar subtitle copy, mode labels, instruction labels, and memory labels.
- Removed status label copy from `WorkspaceModel` and mode-label copy from `WorkspaceSurface`.
- Added direct tests for status text, plural/truncated instruction and memory labels, mode labels, and top-bar subtitles.
- Added a parity gate so status copy and labels do not drift back into `WorkspaceModel` or `WorkspaceSurface`.

Remaining risk:

- Slash command routing still lives in `WorkspaceModel`. A later pass should extract slash-command local transcript planning after the pure copy and label contracts have stabilized.

## 2026-06-23 Top-Bar Status Presentation Pass

Overall grade after this slice: **A- foundation, A status presentation boundary**.

Top-bar status classification moved out of `QuillCodeTopBarView`. Before this pass, the SwiftUI view decided whether an agent status deserved an indicator by matching status text fragments, and the HTML renderer had separate runtime issue fallback logic. That made small status wording changes risky because native UI and static UI snapshots could drift.

Code quality changes:

- Added `TopBarStatusPresentation` and `TopBarStatusTone` for agent status labels, tone, indicator visibility, and accessibility text.
- Added `TopBarRuntimeIssuePresentation` and `TopBarRuntimeIssueTone` for runtime issue pill tone.
- Routed the native top bar and HTML top-bar renderer through the shared presentation values.
- Added tests for idle/running/terminal/failed/stopped status classification and runtime issue tone fallback.
- Added a parity gate that prevents status string classification from returning to the native top-bar view or HTML renderer.

Interface polish:

| Before | After |
| --- | --- |
| `QuillCodeTopBarView` string-matched status text during rendering | Tested presentation values now drive indicator visibility and color mapping |
| Terminal/stopped statuses had no explicit top-bar tone | Terminal is treated as active, stopped/cancelled as neutral, and failures as red |
| Native and HTML top bars could classify runtime issues differently | Both now use the same warning/error presentation value |

## 2026-06-23 Runtime Surface Contract Pass

Overall grade after this slice: **A- foundation, A runtime surface boundary**.

Runtime issue and execution-context surface contracts moved out of `WorkspaceSurface.swift` into `QuillCodeRuntimeSurface.swift`. The aggregate workspace surface now stays focused on composed view payloads, while severity enums, diagnostic records, execution-context labels, and compatibility decoding live beside the runtime boundary they describe.

Code quality changes:

- Added a focused runtime surface contract file for `RuntimeIssueSeverity`, `RuntimeIssueSurface`, `RuntimeDiagnosticSurface`, `ExecutionContextKind`, and `ExecutionContextSurface`.
- Kept local and SSH Remote execution-context fallback copy directly testable.
- Preserved older runtime issue JSON compatibility by decoding missing diagnostics as an empty list.
- Added a parity gate that prevents runtime/remote context contracts from drifting back into `WorkspaceSurface.swift`.
- Kept future QuillCloud relay context expansion pointed at one contract file instead of renderer-local enums.

Remaining risk:

- Runtime execution contexts currently cover local and SSH Remote only. The next relay-related slice should add a QuillCloud/relay context through `QuillCodeRuntimeSurface.swift` first, then fan that through the existing builders and renderers.

## 2026-06-23 Runtime Issue Recovery Planner Pass

Overall grade after this slice: **A- foundation, A recovery-action boundary**.

Runtime issue recovery action routing moved out of `WorkspaceSwiftUIView` into `RuntimeIssueRecoveryPlanner`. The view still decides how to present Settings or the model picker, but it no longer owns the brittle string mapping from runtime issue labels to recovery intents.

Code quality changes:

- Added `RuntimeIssueRecoveryAction` so runtime recovery is represented as either a command or a model-picker presentation intent.
- Added `RuntimeIssueRecoveryPlanner` for `Open Settings`, `Add key`, `Fix key`, `Retry`, and `Switch model` routing.
- Guarded command-based recovery against disabled/missing command rows instead of letting a button trigger a no-op path.
- Added direct planner tests for every recovery label, disabled commands, nil issues, and unknown labels.
- Added a parity gate that keeps runtime recovery label routing out of `WorkspaceSwiftUIView`.

Remaining risk:

- Runtime recovery labels are still string values on `RuntimeIssueSurface` for renderer compatibility. A future compatibility layer could promote them to typed action IDs while continuing to decode older payloads.

## 2026-06-23 Workspace View Command Planner Pass

Overall grade after this slice: **A- foundation, A command-routing boundary**.

Workspace view command routing moved out of `WorkspaceSwiftUIView` into `WorkspaceViewCommandPlanner`. The workspace shell still owns presentation state, but the command-ID interpretation for Settings, Search, Find, Add Project, Command Palette, Keyboard Shortcuts, Rename, Worktree dialogs, and composer-focus dispatch now lives behind a focused, directly tested value planner.

Code quality changes:

- Added `WorkspaceViewCommandAction` as a typed boundary between command rows and SwiftUI state mutations.
- Added `WorkspaceViewCommandPlanner` for command-ID routing, selected thread/project rename lookup, worktree sheet intents, and composer focus rules.
- Preserved no-op behavior for rename commands when no selected thread/project row exists.
- Added direct planner tests for view-local actions, rename selection, missing-selection no-ops, and dispatch composer-focus behavior.
- Added a parity gate so command-ID routing and slash-template focus rules do not drift back into `WorkspaceSwiftUIView`.

Remaining risk:

- The workspace shell still executes typed actions through local `@State` mutations. If command-triggered sheets or focus behavior grows again, the next slice should split those state transitions into tiny executor helpers rather than adding more cases to the view body.

## 2026-06-23 Sidebar Bulk Action Executor Pass

Overall grade after this slice: **A- foundation, A sidebar bulk mutation boundary**.

Sidebar bulk action execution moved out of `WorkspaceModel` into `WorkspaceSidebarBulkActionExecutor`. The model still owns actor-bound persistence, terminal-session sync, project touches, and top-bar refresh, but it no longer switches over sidebar bulk mutations or calls archive/unarchive/delete bulk lifecycle helpers inline.

Code quality changes:

- Added `WorkspaceSidebarBulkActionExecutor.Result` as a value boundary for updated threads, selected thread/project, cleared selection, changed-thread saves, removed-thread deletes, project-save intent, terminal sync intent, and project-touch intent.
- Kept selection-only commands cheap: they update only sidebar selection and do not ask the model to save project state.
- Moved pin/unpin mutation application and archive/unarchive/delete bulk lifecycle calls behind one directly tested executor.
- Added direct executor tests for selection-only plans, pin/unpin persistence payloads, archive fallback selection, unarchive project touch, and delete project reconciliation.
- Extended the parity gate so `WorkspaceModel` delegates bulk execution and cannot drift back to inline pin/archive/delete logic.

Remaining risk:

- `WorkspaceModel` still owns several broad orchestration clusters around command execution, tool overrides, and local environment actions. The next quality pass should keep extracting one small actor-safe value boundary at a time instead of doing a large model rewrite.

## 2026-06-23 Workspace Command Action Planner Pass

Overall grade after this slice: **A- foundation, A command-action boundary**.

Workspace command action routing moved out of `WorkspaceModel` into `WorkspaceCommandActionPlanner`. The model still owns actor-bound side effects such as terminal/browser mutations, draft updates, persistence, project refresh, and thread lifecycle calls, but it no longer switches over selected project/thread preconditions or constructs rename drafts inline.

Code quality changes:

- Added `WorkspaceCommandActionEffect` as a typed boundary between command IDs and workspace mutations.
- Added `WorkspaceCommandActionPlanner` for context-free commands, selected project/thread action routing, rename draft copy, and sidebar bulk command mapping.
- Preserved no-op behavior when a command depends on missing selected project/thread context.
- Added direct planner tests for context-free commands, project actions, thread actions, and sidebar bulk effects.
- Added a parity gate so selected-state command routing and draft construction do not drift back into `WorkspaceModel`.

Remaining risk:

- `WorkspaceModel` still executes the typed effects directly because those effects are actor-bound and touch persistence, thread stores, top-bar refresh, terminal state, and browser state. If effect execution grows, split it into a tiny executor that returns persistence intents instead of moving planner logic back into the model.

## 2026-06-23 Sidebar Row Action Planner Pass

Overall grade after this slice: **A- foundation, A row-action boundary**.

Sidebar row action routing moved out of `WorkspaceSwiftUIView` and `QuillCodeDesktopController` into `WorkspaceSidebarRowActionPlanner` plus `WorkspaceSidebarRowMutationExecutor`. Before this pass, SwiftUI performed thread/project title lookups for rename sheets while the desktop controller separately switched duplicate, pin, archive, delete, new-chat, refresh, and remove actions into model calls.

Code quality changes:

- Added typed `WorkspaceThreadRowMutation` and `WorkspaceProjectRowMutation` values for non-rename row actions.
- Added `WorkspaceSidebarRowActionPlanner` for thread/project rename lookup and row-action-to-mutation mapping.
- Added `WorkspaceSidebarRowMutationExecutor` as the desktop/model boundary for applying typed row mutations.
- Updated the SwiftUI shell to open rename sheets or forward typed mutations without direct row-title lookups.
- Updated the desktop controller to delegate row mutations instead of switching over row action enums.
- Added direct planner/executor tests and a parity gate to keep row action routing out of the view and controller.

Remaining risk:

- `WorkspaceSidebarRowMutationExecutor` still calls high-level model methods directly. If row action mutations need richer previews or batched persistence, move them behind a pure mutation result boundary rather than adding UI-specific branches back to the controller.

## 2026-06-23 Workspace Agent Status Builder Pass

Overall grade after this slice: **A- foundation, A progress-status boundary**.

Agent progress status copy moved out of `WorkspaceModel` into `WorkspaceAgentStatusBuilder`. Before this pass, the model switched over the latest thread event kind and knew the `AgentRunner.streamingNotice` sentinel directly. The model now only applies progress and refreshes the top bar with the builder's result.

Code quality changes:

- Added `WorkspaceAgentStatusBuilder` for thread/event-to-top-bar status copy.
- Kept the streaming notice sentinel behind the focused builder.
- Added direct tests for queued, running, review, streaming, finishing, failed, conversation, generic notice, nil-event, and latest-thread-event behavior.
- Added a parity gate so event-kind status mapping and the streaming notice string do not drift back into `WorkspaceModel`.

Remaining risk:

- Side-effect timing markers such as idle, failed, stopped, and terminal are still emitted by model orchestration paths. The follow-up pass below centralizes their user-facing labels; if those transitions start gaining richer conditional logic, extract a broader workspace status transition helper.

## 2026-06-23 Top-Bar Status Label Pass

Overall grade after this slice: **A- foundation, A shared-status-label boundary**.

Top-bar lifecycle labels moved from repeated string literals into `TopBarAgentStatusLabel`. The root state default, workspace orchestration paths, agent progress builder, MCP runtime, and top-bar presentation fallback now share one label source while preserving the existing `String` surface contract for UI compatibility.

Code quality changes:

- Added `TopBarAgentStatusLabel` for stable user-facing lifecycle copy.
- Replaced raw `Idle`, `Running`, `Failed`, `Stopped`, and `Terminal` top-bar refresh strings in `WorkspaceModel`.
- Updated `WorkspaceAgentStatusBuilder` and `WorkspaceMCPRuntime` to return shared labels.
- Added tests that lock the label copy and use shared constants in status presentation/progress assertions.
- Added a parity gate preventing raw lifecycle status strings from returning to runtime paths.

Remaining risk:

- Runtime status labels such as TrustedRouter readiness and sign-in prompts are runtime/auth copy rather than lifecycle labels. The follow-up pass below centralizes them separately so they do not expand `TopBarAgentStatusLabel`.

## 2026-06-23 Runtime Status Label Pass

Overall grade after this slice: **A- foundation, A runtime-status-label boundary**.

Runtime/auth status labels moved from raw string sentinels into `QuillCodeRuntimeStatusLabel`. The runtime factory, runtime issue builder, desktop sign-in failure path, and tests now share one source of truth for mock, sign-in-needed, developer-key-needed, signed-in, ready, and sign-in-failed status copy.

Code quality changes:

- Added `QuillCodeRuntimeStatusLabel` for runtime/auth status copy.
- Replaced raw runtime status emissions in `RuntimeFactory`.
- Updated `WorkspaceRuntimeIssueBuilder` to branch on shared labels instead of repeated string literals.
- Updated desktop sign-in failure handling to use shared runtime failure copy.
- Added tests that lock stable runtime status labels and parity gates that prevent raw runtime sentinels from returning.

Remaining risk:

- Runtime issue title/message copy still lives in `WorkspaceRuntimeIssueBuilder`, which is the correct current boundary. If more auth statuses gain recovery actions, promote those statuses from strings into a typed runtime state while preserving the existing `TopBarSurface.agentStatus` compatibility layer.

## 2026-06-23 Agent Run Context Builder Pass

Overall grade after this slice: **A- foundation, A per-run tool-context boundary**.

Per-turn agent runner configuration moved out of `WorkspaceModel` into `WorkspaceAgentRunContextBuilder`. Before this pass, `submitComposer` assembled local/remote base tools, optional plan/browser/Computer Use/memory/MCP tool definitions, and the override chain inline before every send. The model now passes current workspace state to one builder and receives a configured `AgentRunner`.

Code quality changes:

- Added `WorkspaceAgentRunContextBuilder` for local versus SSH Remote base tools, optional tool definitions, and override composition.
- Moved memory tool execution and saved-memory event detection into `WorkspaceMemoryRememberToolExecutor`.
- Removed plan/browser/computer/memory/remote override helper methods from `WorkspaceModel`.
- Added direct builder tests for local base tools, remote base tools, optional tool definition ordering, plan/browser/memory override execution, and memory-save event detection.
- Added a parity gate so per-run tool assembly and memory-save parsing do not drift back into `WorkspaceModel`.

Remaining risk:

- `WorkspaceModel.submitComposer` still owns send lifecycle timing, progress application, persistence, cancellation, and final top-bar state. Those are actor-bound side effects and should move only behind a dedicated send coordinator once that coordinator can return clear persistence and UI intents.

## 2026-06-23 Transcript View Extraction Pass

Overall grade after this slice: **A- foundation, A native transcript layout boundary**.

Transcript pane layout moved out of `WorkspaceSwiftUIView` into `QuillCodeTranscriptView`. Before this pass, the workspace shell still owned Find bar placement, empty-state layout, context banner/runtime issue/review placement, message/tool-card row placement, active Find highlighting, scroll-to-match behavior, and tool-card copy fallback. The shell now composes the transcript view and routes callbacks, while transcript-specific presentation stays beside the Find and transcript-message/tool-card components.

Code quality changes:

- Added `QuillCodeTranscriptView` for transcript pane layout, Find bar placement, empty state, context/runtime/review placement, message/tool-card timeline rows, active Find highlighting, and scroll-to-match behavior.
- Kept the existing message and tool-card rendering files as focused row components; the transcript view decides timeline placement and copy wiring.
- Reduced `WorkspaceSwiftUIView.swift` by roughly 200 lines and kept it focused on chrome composition, modal presentation, and typed command routing.
- Updated the parity gate so runtime issue, review, and tool-card timeline placement cannot drift back into the workspace shell.

Remaining risk:

- `WorkspaceSwiftUIView` still owns several modal state bindings and command-action execution. That is acceptable while the shell is the only place that knows which sheets are open, but future modal families should keep their row/draft/rendering details in dialog-specific files.

## 2026-06-23 Static HTML Transcript Renderer Pass

Overall grade after this slice: **A- foundation, A static-harness composition boundary**.

Static HTML transcript, runtime issue, context banner, message action, tool-card handoff, review placement, and composer markup moved out of `WorkspaceHTMLRenderer` into `WorkspaceHTMLTranscriptRenderer`. This brings the Playwright/static harness in line with the native transcript boundary: the whole-workspace renderer composes shell regions, while transcript-specific markup has a focused owner.

Code quality changes:

- Added `WorkspaceHTMLTranscriptRenderer` for transcript empty state, context banner, runtime issue panel, timeline rows, message actions, tool-card row delegation, review pane placement, and composer markup.
- Reduced `WorkspaceHTMLRenderer.swift` to roughly 34 lines, making it a true static shell composer.
- Preserved existing `data-testid` contracts for messages, runtime issues, context banners, composer, send/stop controls, and tool cards.
- Added a parity gate so transcript/composer/runtime/context/message action markup cannot drift back into `WorkspaceHTMLRenderer`.

Remaining risk:

- `WorkspaceHTMLRenderer` now delegates all major shell families. Future static harness work should add new focused renderers beside the relevant surface contract rather than expanding the root renderer again.

## 2026-06-23 Workspace Sheet Presentation Pass

Overall grade after this slice: **A- foundation, A- root-shell presentation boundary**.

Workspace modal and sheet presentation moved out of `WorkspaceSwiftUIView` into `QuillCodeWorkspaceSheetsModifier`. Before this pass, the root workspace shell owned settings, search, keyboard shortcuts, command palette, worktree create/remove, and thread/project rename sheet presentation inline. The shell now composes one sheet presenter while keeping the state bindings and command routing where SwiftUI can still coordinate focus and chrome.

Code quality changes:

- Added `QuillCodeWorkspaceSheetsModifier` plus the `quillCodeWorkspaceSheets(...)` view extension for workspace modal presentation.
- Moved settings save/cancel, search selection, command-palette selection, worktree create/remove, and rename save/cancel sheet wiring into the sheet presenter.
- Reduced `WorkspaceSwiftUIView.swift` from 482 lines to roughly 399 lines after the transcript and sheet extraction passes.
- Added a parity gate so settings/search/palette/worktree/rename sheet wiring does not drift back into the root workspace shell.

Remaining risk:

- `WorkspaceSwiftUIView` still owns enough `@State` bindings to coordinate search, command palette, settings, worktree, rename, and composer focus. That is acceptable while the shell owns presentation state, but if more modal families land, promote them into a small presentation-state reducer instead of adding more root-shell booleans.

## 2026-06-23 Environment Slash Transcript Pass

Overall grade after this slice: **A- foundation, A slash-command copy boundary**.

The `/env` local-environment transcript copy moved out of `WorkspaceModel` and into `WorkspaceSlashCommandTranscriptPlanner`. Before this pass, the model formatted the local action list, cwd, timeout, detail suffixes, empty-state copy, and missing-action copy inline while also running the selected action. The model now refreshes metadata, chooses whether to list or run an action, and delegates user-facing `/env` transcript text to the same planner that owns the other slash-command responses.

Code quality changes:

- Added `environmentActions(userText:actions:)` to format available local environment actions.
- Added `environmentActionNotFound(userText:query:)` for the missing-action fallback.
- Added focused tests for populated, empty, and missing `/env` transcript copy.
- Extended the parity gate so `/env` list and missing-action strings do not drift back into `WorkspaceModel`.

Remaining risk:

- `WorkspaceModel.handleSlashCommand` still owns the side-effect switch for slash commands. That is acceptable while each branch calls high-level model methods, but a future slash-command executor could receive typed closures or command effects if the switch grows more workflow-specific logic.

## 2026-06-23 Remember Slash Transcript Pass

Overall grade after this slice: **A- foundation, A slash-command copy boundary**.

The `/remember` transcript copy and saved-memory summary moved out of `WorkspaceModel` and into `WorkspaceSlashCommandTranscriptPlanner`. Before this pass, the model owned the “Saved memory” chat text, “Memory not saved” title, and saved-memory event summary while also writing the memory file and refreshing thread memory context. The model now keeps the side effects and delegates user-facing transcript copy plus the event summary prefix to the slash transcript planner.

Code quality changes:

- Added `memorySaved(userText:noteTitle:)` for saved global-memory chat transcripts.
- Added `memoryNotSaved(userText:message:)` for write failures and unavailable runtime failures.
- Added `memorySavedSummary(noteTitle:)` so transcript copy and thread events share one summary string.
- Added focused planner tests and parity gates so `/remember` transcript strings do not drift back into `WorkspaceModel`.

Remaining risk:

- `/remember` still performs write/reload/thread mutation directly in `WorkspaceModel`. That is acceptable while the flow is small, but if memory editing, conflict resolution, or autonomous memory review grows, promote this into a dedicated memory command workflow coordinator.

## 2026-06-23 Memory Delete Transcript Pass

Overall grade after this slice: **A- foundation, A memory-command copy boundary**.

Memory delete transcript copy and the forgotten-memory event summary moved out of `WorkspaceModel` and into `WorkspaceMemoryCommandTranscriptPlanner`. Before this pass, the model owned the “Forgot memory” chat text, “Memory not deleted” failure title, and notice summary while also deleting the memory file, refreshing memory context, and saving the thread. The model now keeps the deletion side effects and delegates user-facing transcript copy plus the event summary prefix to a focused memory command planner.

Code quality changes:

- Added `WorkspaceMemoryCommandTranscriptPlanner` for memory delete success/failure transcripts.
- Added `memoryForgottenSummary(noteTitle:)` so chat copy and thread events share one summary string.
- Added `WorkspaceMemoryErrorMessageBuilder` so memory write and delete flows share one intentionally named user-facing error formatter instead of coupling delete behavior to the remember-tool executor.
- Added focused planner tests for success, summary, and failure copy.
- Added a parity gate so memory delete transcript strings do not drift back into `WorkspaceModel`.

Remaining risk:

- Memory write and delete flows still mutate global memory state directly in `WorkspaceModel`. That remains acceptable while the operations are small, but richer memory editing or conflict handling should move through a dedicated workflow coordinator instead of adding more side-effect branches to the model.

## 2026-06-23 Memory Transcript Consolidation Pass

Overall grade after this slice: **A- foundation, A memory transcript ownership**.

The `/remember` success/failure transcript copy moved from the generic slash-command transcript planner into `WorkspaceMemoryCommandTranscriptPlanner`, next to memory delete copy. This resolves the earlier split ownership where save and delete memory copy lived in different planners even though both are memory-domain transcript contracts.

Code quality changes:

- Moved `memorySaved(userText:noteTitle:)`, `memoryNotSaved(userText:message:)`, and `memorySavedSummary(noteTitle:)` to `WorkspaceMemoryCommandTranscriptPlanner`.
- Updated `WorkspaceModel` so memory write and delete paths delegate transcript and event summary copy to the same planner.
- Moved focused `/remember` transcript tests into `WorkspaceMemoryCommandTranscriptPlannerTests`.
- Tightened parity tests so `WorkspaceSlashCommandTranscriptPlanner` cannot regain memory save copy accidentally.

Remaining risk:

- Memory write/delete side effects still live in `WorkspaceModel`. The next architecture step should be a dedicated memory command workflow coordinator once memory editing grows beyond simple write/delete operations.

## 2026-06-23 Memory Context Refresh Pass

Overall grade after this slice: **A- foundation, A memory refresh boundary**.

The memory save/delete paths now share one selected-thread refresh path after global memory changes. Before this pass, `/remember` and memory delete both reloaded global memories, recomputed selected-thread memory context, and constructed identical notice events inline. `WorkspaceModel` now calls `applyGlobalMemoryChange(summary:relativePath:)`, while `WorkspaceMemoryContextUpdatePlanner` owns the structured memory update and event shape.

Code quality changes:

- Added `WorkspaceMemoryContextUpdatePlanner` and a value type for refreshed memories plus the corresponding notice event.
- Replaced duplicated save/delete memory refresh branches with a single `applyGlobalMemoryChange` helper.
- Added focused planner tests and a parity gate that keeps memory reloads centralized through `refreshGlobalMemories()`.

Remaining risk:

- Memory commands still live in `WorkspaceModel` as orchestration methods. The next worthwhile extraction is a dedicated memory command coordinator once memory edit/conflict flows appear; for now, the shared refresh boundary keeps the current behavior small and testable.

## 2026-06-23 Workspace Memory Engine Pass

Overall grade after this slice: **A memory workflow boundary, A behavior preservation, A focused regression coverage**.

Memory save/delete orchestration moved from `WorkspaceModel` into `WorkspaceMemoryEngine`. Before this pass, the model still owned global memory write/delete calls, global reloads, success/failure transcript construction, and selected-thread context update decisions. The model now applies a typed `WorkspaceMemoryMutation` to actor-isolated state while the memory engine owns the storage outcome and user-visible mutation intent.

Code quality changes:

- Added `WorkspaceMemoryEngine` and `WorkspaceMemoryMutation` as the single save/delete decision boundary for explicit global memories.
- Updated `/remember` and `memory-delete:*` paths so `WorkspaceModel` delegates memory storage, failure mapping, global reload, and notice intent construction.
- Kept thread mutation, persistence, and top-bar refresh in `WorkspaceModel`, where the actor-isolated workspace state lives.
- Added focused engine tests for save success, unavailable memory storage, delete success, and unknown-memory delete failure.

Remaining risk:

- Memory editing, conflict resolution, and autonomous memory proposals are still future Codex-parity work. Those features should extend `WorkspaceMemoryEngine` or add a narrow memory-review coordinator rather than growing `WorkspaceModel` again.

## 2026-06-23 Async Thread Selection Pass

Overall grade after this slice: **A- foundation, A async-thread update boundary**.

Agent runs now update their target thread without stealing the user's current selection. Before this pass, progress and completion updates used the generic thread replacement path, which could re-select the original thread if the user opened another chat while a run was still streaming or cancelling. `WorkspaceModel` now uses an explicit `updateThreadFromAgentRun(_:)` path for asynchronous run updates, keeping thread mutation and UI focus separate without hiding navigation semantics behind a boolean flag.

Code quality changes:

- Replaced the ambiguous `replaceThread(_:preservingSelection:)` call sites with `updateThreadFromAgentRun(_:)`, so progress and completion call sites document that late agent updates preserve the user's current focus.
- Added regression coverage for completed runs so late assistant output is saved to the original thread without moving focus away from the user's newly selected chat.
- Added a parity gate that rejects reintroducing the old boolean `preservingSelection` replacement path in `WorkspaceModel`.
- Stress-ran cancellation and completion selection tests locally to cover the timing-sensitive path that failed in CI.

Remaining risk:

- `WorkspaceModel.submitComposer` still owns async send orchestration. A future runner session coordinator could make captured thread identity, cancellation, and progress persistence even more explicit, but this fix removes the immediate race without widening the model API.

## 2026-06-23 Composer Cancellation Planner Pass

Overall grade after this slice: **A- foundation, A cancellation transcript boundary**.

Composer cancellation thread mutation moved from `WorkspaceModel` into `WorkspaceComposerCancellationPlanner`. Before this pass, `finishCancelledSend` reset UI state and also owned thread title seeding, user prompt backfill, pending-tool failure events, cancelled-result payload JSON, and duplicate notice suppression. The model now resets composer/top-bar state and delegates the pure transcript/event mutation.

Code quality changes:

- Added `WorkspaceComposerCancellationPlanner` for cancelled-send prompt, notice, and pending-tool failure event mutation.
- Added focused planner tests for empty-thread seeding, pending-tool failure conversion, and duplicate suppression.
- Added a parity gate so cancelled-send copy and payload JSON do not drift back into `WorkspaceModel`.

Remaining risk:

- `submitComposer` still manages send lifecycle state directly. The cancellation transcript boundary is now testable, but a larger runner-session coordinator would be the next step if cancellation, retries, or background runs gain more states.

## 2026-06-23 Agent Run Thread Update Engine Pass

Overall grade after this slice: **A- foundation, A agent-run thread update reducer**.

Agent-run thread upsert and fallback selection moved from `WorkspaceModel` into `WorkspaceThreadLifecycleEngine.applyAgentRunThreadUpdate`. The workspace model still owns side effects that are inherently UI/runtime-specific, such as terminal-session sync and project persistence after fallback selection, while the pure decision about which thread/project should remain selected is directly tested beside the other thread lifecycle rules.

Code quality changes:

- Added `WorkspaceThreadLifecycleEngine.AgentRunThreadUpdateResult` so the selection outcome and “did fallback-select the updated thread” signal are explicit values.
- Added lifecycle-engine tests for preserving the current selection, selecting the updated thread when the prior selection is stale, and dropping unknown project IDs during fallback selection.
- Extended the parity gate so generic thread upsert and agent-run fallback selection do not drift back into `WorkspaceModel`.

Remaining risk:

- `submitComposer` still owns the async send lifecycle and persistence timing. The next larger step is a runner-session coordinator that captures thread identity, cancellation, progress persistence, and retry semantics in one testable unit.

## 2026-06-23 Composer Submission Planner Pass

Overall grade after this slice: **A- foundation, A composer submission boundary**.

Composer draft normalization and first-step routing moved from `WorkspaceModel.submitComposer` into `WorkspaceComposerSubmissionPlanner`. Before this pass, the async send method trimmed raw input, decided whether to ignore it, classified slash commands, and then continued into agent run orchestration. The model now executes a typed submission plan, while the pure planner owns the “ignore vs slash command vs agent prompt” decision with focused tests.

Code quality changes:

- Added `WorkspaceComposerSubmissionPlanner` with explicit `.ignore`, `.slash`, and `.agent` plans.
- Updated `submitComposer` so prompt trimming and slash-command classification happen before agent orchestration through the planner.
- Added focused planner coverage for blank drafts, trimmed agent prompts, and slash-command original prompt preservation.
- Added a parity gate that prevents raw composer normalization and inline slash-command parsing from drifting back into `WorkspaceModel`.

Remaining risk:

- `submitComposer` still owns runner setup, completion persistence, and error status. The send call and memory-save detection are now extracted, but a future background-run coordinator should own retries, resumable runs, and persistence timing if those states become more complex.

## 2026-06-23 Agent Send Session Pass

Overall grade after this slice: **A- foundation, A send-session boundary**.

The per-turn `AgentRunner.send` call moved from `WorkspaceModel.submitComposer` into `WorkspaceAgentSendSession`. Before this pass, the workspace model owned prompt routing, UI state, runner context construction, cancellation checks, the raw send call, progress handoff, memory-save event detection, thread persistence, and error UI in one method. The model now still owns UI and persistence side effects, but delegates the actual agent send lifecycle and the saved-memory signal to a directly tested session object.

Code quality changes:

- Added `WorkspaceAgentSendSession` and `WorkspaceAgentSendSessionResult` as a small value boundary around prompt, captured thread, runner, workspace root, progress handler, and memory-save detection.
- Updated `submitComposer` so completion memory refresh keys off `result.savedMemory` instead of parsing tool events inline.
- Added focused session tests for ordinary assistant completion, progress callbacks staying tied to the captured thread ID, and successful memory-tool runs reporting `savedMemory`.
- Added a parity gate that prevents `activeRunner.send` and post-send memory event parsing from drifting back into `WorkspaceModel`.

Remaining risk:

- `WorkspaceModel.submitComposer` still constructs the run context and owns completion persistence. That is the right split for the current app because runner context depends on actor-isolated UI/runtime state, but background/resumable runs should promote persistence timing into a dedicated run coordinator.

## 2026-06-23 Core Tool Arguments Serialization Pass

Overall grade after this slice: **A- foundation, A shared argument serialization boundary**.

Mixed tool-argument JSON serialization moved into `ToolArguments` in `QuillCodeCore`. Before this pass, `WorkspaceModel` and `SlashCommand` each carried private `JSONSerialization` helpers, even though tool argument parsing and construction are a core contract shared by CLI, agent, app, and tests. The app now uses `ToolArguments.json(...)` for string, boolean, integer, and nested dictionary payloads.

Code quality changes:

- Added `ToolArguments.json(_ values: [String: Any])` beside the existing string-only helper.
- Removed private tool-argument JSON serializers from `WorkspaceModel` and `SlashCommand`.
- Added core coverage for stable mixed-value JSON output.
- Added a parity gate so app-layer files continue using the core serializer.

Remaining risk:

- The helper still accepts `[String: Any]` because current call sites build heterogeneous payloads before encoding. A future stronger model could introduce a typed `ToolArgumentValue` enum to remove `Any` entirely from tool argument construction.

## 2026-06-23 Tool Call Executor Pass

Overall grade after this slice: **A- foundation, A tool-routing boundary**.

Tool-call execution routing moved out of `WorkspaceModel` into `WorkspaceToolCallExecutor`. Before this pass, `runToolCall` directly branched on browser inspect, plan update, SSH Remote, local execution, and apply-patch follow-up diff behavior. Review actions had a second local/remote git helper with overlapping routing. The model now prepares context and records results, while the executor owns the routing order and returns primary plus follow-up tool results.

Code quality changes:

- Added `WorkspaceToolCallExecutor`, `WorkspaceToolCallExecution`, and `WorkspaceRecordedToolResult`.
- Moved browser inspect, plan update, SSH Remote, local router fallback, unsupported remote-tool errors, and apply-patch git-diff follow-up into the executor.
- Updated `runToolCall` and review actions to use the same executor instead of parallel routing helpers.
- Added focused executor tests for browser inspect routing, plan update routing, apply-patch review-diff follow-up, and unsupported remote tool rejection.
- Added a parity gate so tool-name routing and review-diff follow-up logic do not drift back into `WorkspaceModel`.

Remaining risk:

- `WorkspaceModel.runToolCall` still owns context refresh, transcript event recording, persistence, and top-bar status. Those are actor-bound side effects and should stay there until there is a broader command-run coordinator that can return explicit persistence/status intents.

## 2026-06-23 Automation State Reducer Pass

Overall grade after this slice: **A- foundation, A automation-state boundary**.

Automation list mutations moved into `WorkspaceAutomationStateReducer`. Before this pass, `WorkspaceModel` directly sorted automation records, appended newly created thread/workspace automations, updated status fields, deleted rows, and replaced run metadata. That made persistence and UI visibility side effects hard to distinguish from pure state transitions. The model now requests typed reducer mutations and applies the resulting `AutomationsState` through one persistence boundary.

Code quality changes:

- Added `WorkspaceAutomationStateReducer` and `WorkspaceAutomationStateMutation` beside the existing automation factory/runner.
- Moved set-items sorting, create-thread-follow-up, create-workspace-schedule, update-status, delete, and replace state transitions out of `WorkspaceModel`.
- Added direct reducer tests for sorting, visibility, create/update/delete/replace behavior, and missing-record no-ops.
- Added a parity gate so automation record mutation does not drift back into `WorkspaceModel`.

Remaining risk:

- Running automations still has actor-bound side effects in `WorkspaceModel`: project refresh, thread insertion, store writes, terminal sync, and top-bar refresh. That is currently the right split, but a future background automation coordinator should return explicit persistence and navigation intents.

## 2026-06-23 Shell Tool Call Planner Pass

Overall grade after this slice: **A- foundation, A local-action shell contract**.

Local environment actions and project extension updates now build `host.shell.run` calls through `WorkspaceShellToolCallPlanner`. Before this pass, `WorkspaceModel` manually assembled command, environment, and timeout dictionaries in two separate paths. That kept a tool-schema detail inside the actor model and made it easier for future changes to drift into empty or malformed shell calls.

Code quality changes:

- Added `WorkspaceShellToolCallPlanner` for local environment action and extension update shell tool calls.
- Updated `runLocalEnvironmentAction` and `runProjectExtensionUpdate` so `WorkspaceModel` delegates shell-call construction while still owning refresh, tool dispatch, notices, and persistence.
- Added focused planner tests for command, environment, timeout, optional metadata omission, and blank extension update rejection.
- Added a parity gate so local action and extension update argument assembly does not drift back into `WorkspaceModel`.

Remaining risk:

- Worktree and low-level file helper paths still construct a few tool calls inside `WorkspaceModel`. Those are narrower and currently tied to immediate UI side effects, but future growth should move each command family through its own typed request planner rather than adding more ad hoc dictionaries.

## 2026-06-23 Full-Code Architecture Grade And Worktree Tool Call Planner Pass

Overall grade after this slice: **A- architecture, A- implementation, B+ UX parity, B release completeness; A worktree tool-call contract**.

The repo is now a substantial, test-backed native coding-agent app rather than a prototype: SwiftPM builds, 700+ tests cover core tools and app state, Playwright exercises the static harness, and most Codex-parity surfaces have a focused boundary. The main architectural risk is concentration, not absence: `WorkspaceModel.swift`, `Agent.swift`, `Models.swift`, and a few broad surface files still carry enough behavior that new feature work can accidentally reintroduce duplication or malformed tool calls.

Worktree create/remove tool-call JSON moved into `WorkspaceWorktreeToolCallPlanner`. Before this pass, `WorkspaceModel` trimmed branch/base values, built the git worktree create argument dictionary, and manually assembled remove arguments inline. The model now owns only command dispatch plus the local/SSH project handoff after a successful create.

Code quality changes:

- Added `WorkspaceWorktreeToolCallPlanner` for `host.git.worktree.create` and `host.git.worktree.remove` calls.
- Updated `createWorktree` and `removeWorktree` so `WorkspaceModel` delegates worktree tool-call construction.
- Preserved the existing user-facing behavior: worktree paths pass through to the existing Git executor validation, optional branch/base refs are whitespace-trimmed and omitted when blank, and remove keeps an explicit `force` boolean for both destructive and non-destructive paths.
- Added focused planner tests for branch/base trimming, blank optional omission, forced removal, and default non-forced removal.
- Extended the parity gate so worktree request values, open-record construction, and tool-call JSON stay outside `WorkspaceModel`.

Remaining risk:

- `WorkspaceModel.swift` is still roughly 2.1k lines and remains the largest production app file. Continue extracting pure planning/state-transition seams before adding new Codex-parity commands.
- `ToolArguments.json(_ values: [String: Any])` is centralized, but the `Any` entry point is still weaker than a typed argument-value model. Future slices should introduce a typed argument builder once the current command families are fully moved behind focused planners.
- UX parity is broad but not done: the browser, PTY/TUI terminal, full GitHub review workflows, Linux Computer Use, and richer artifact renderers still need product-level passes before a public 1.0 claim.
- Review action orchestration still lives in `WorkspaceModel` because it executes git tools, refreshes the diff, appends tool cards, and persists selected-thread state. If review sessions grow into multi-step PR publication, add a review workflow coordinator instead of expanding the model again.

## 2026-06-23 Review Action Tool Call Planner Pass

Overall grade after this slice: **A- architecture, A review-action tool-call contract**.

Review action tool-call mapping moved out of the private `WorkspaceReviewActionSurface` extension at the bottom of `WorkspaceModel.swift` and into `WorkspaceReviewActionToolCallPlanner`. Before this pass, review-pane buttons for file stage/restore and hunk stage/restore relied on an otherwise UI-oriented surface value knowing exact `host.git.*` tool names and argument JSON. The workspace model now owns execution and diff refresh only.

Code quality changes:

- Added `WorkspaceReviewActionToolCallPlanner` for file and hunk stage/restore calls.
- Preserved existing behavior: file actions include only `path`; hunk actions include `path` plus `patch`, falling back to an empty patch string so existing executor-level validation still owns malformed hunk rejection.
- Added focused planner tests for stage, restore, stage hunk, restore hunk, and missing-patch hunk behavior.
- Added a parity gate so review action tool-call mapping and private review-surface extensions do not drift back into `WorkspaceModel`.

Remaining risk:

- Review action orchestration still lives in `WorkspaceModel` because it executes the selected action, appends tool cards, refreshes the diff, persists the selected thread, and updates top-bar status. That is acceptable now, but richer PR review sessions should introduce a review workflow coordinator rather than expanding the model again.

## 2026-06-23 Edge-Case Hardening Pass

Overall grade after this slice: **A- architecture, A security boundary, A- edge-case posture**.

The codebase now has no production-source `try!`, `as!`, or ordinary force-unwrap shapes. This is a meaningful quality bar for a public Swift app because app startup, OAuth sign-in, and local extension discovery should fail through typed errors or ignored unsafe inputs rather than crashing on malformed local state.

Code quality changes:

- Hardened project extension manifest directory validation so unsafe custom paths are skipped without preventing later safe directories from loading.
- Normalized accepted extension directories by path component, rejecting empty, absolute, `.`, and `..` components while preserving normal project-local folders like `.quillcode/plugins`.
- Kept symlinked manifest directories/files outside the project root rejected through resolved-path checks.
- Removed the manifest-name force unwrap by moving trimmed display-name handling into `ManifestPayload`.
- Replaced the desktop OAuth loopback callback URL force unwrap with typed URL parsing and a readable `TrustedRouterLoopbackError.invalidCallbackURL` failure.
- Added a parity gate that scans production Swift sources for force tries, force casts, and force unwraps.

Validation added:

- Unsafe custom extension directories are skipped without stopping later safe directory scans.
- Symlinked extension directories that resolve outside the project root are ignored.
- Blank or missing manifest names fall back to readable filename-derived names.
- Production source text stays free of `try!`, `as!`, and ordinary force unwraps.

Remaining risk:

- The desktop OAuth loopback server still lacks direct executable-target unit tests because it lives in the desktop executable target. The new parity gate prevents the force unwrap from returning, and existing desktop sign-in parity gates ensure the loopback server remains the sign-in boundary. If loopback behavior grows, move callback target parsing into a small testable library type.
- The scan is intentionally conservative and source-text based. If Swift syntax grows more complex around optional unwrapping, a future SwiftSyntax-based lint would be stronger.
- `WorkspaceModelTests.swift` is still very large. New edge-case tests should move into narrower test files when their target boundary is already extracted.
- `WorkspaceModel.swift` remains the primary architectural hotspot; keep extracting pure planners/reducers before adding more Codex-parity workflows.

## 2026-06-23 Agent Final Answer Builder Pass

Overall grade after this slice: **A- architecture, A final-answer contract, A compatibility posture**.

Agent tool-result final-answer formatting moved out of `AgentRunner` and into `AgentFinalAnswerBuilder`. Before this pass, `Agent.swift` mixed orchestration, streaming, tool execution, safety review, heuristic action planning, and user-visible post-tool response copy in one broad type. `AgentRunner.finalAnswer(...)` now remains as the stable compatibility entry point, but it delegates the actual shell/browser/file/patch/MCP/Computer Use copy rules to a focused builder with direct tests.

Code quality changes:

- Added `AgentFinalAnswerBuilder` for tool-result-to-chat copy.
- Preserved the existing public `AgentRunner.finalAnswer(...)` API so callers and older tests keep working.
- Kept special cases for `whoami`, OpenClaw discovery, disk usage, browser inspection, apply-patch review refresh failures, MCP reads/prompts, and Computer Use actions in one directly testable boundary.
- Added focused builder tests for shell identity copy, OpenClaw discovery copy, and long-output truncation.
- Added a parity gate so shell/browser final-answer formatting does not drift back into `AgentRunner`.

Remaining risk:

- `Agent.swift` is still the largest agent-layer file and still owns prompt planning, streaming action parsing, safety review sequencing, repeated-tool fallback, and execution orchestration. The next agent-layer quality passes should extract the heuristic action planner and streaming action decoder before adding richer Codex parity features.
- `AgentFinalAnswerBuilder` intentionally preserves existing copy, including concise shell special cases. Richer long-output UX, structured command result summaries, and tool-card expansion controls should evolve through this builder rather than adding response-copy branches back to `AgentRunner`.

## 2026-06-23 Mock LLM Client File Split

Overall grade after this slice: **A- architecture, A deterministic mock boundary**.

The deterministic `MockLLMClient` moved out of `Agent.swift` into `MockLLMClient.swift`. Before this pass, the main agent file looked like it owned hundreds of lines of mock-only command heuristics and PR parsing, even though that code exists to support local smoke tests, mock CLI mode, and deterministic UI harness behavior. The runner file now keeps agent contracts, streaming preview helpers, run orchestration, and result types; mock planning lives beside the agent module but outside the runner file.

Code quality changes:

- Moved `MockLLMClient` and its deterministic command/PR parsing helpers into a dedicated source file without changing the public `MockLLMClient` API.
- Preserved the mock feedback path through `AgentRunner.finalAnswer(...)` so mock tool loops still exercise the production final-answer contract.
- Added a parity gate so mock command heuristics and PR argument extraction do not drift back into `Agent.swift`.

Remaining risk:

- `MockLLMClient` is still a broad deterministic planner. It is acceptable as a mock/testing boundary, but if it grows further it should split into smaller intent planners, especially PR parsing versus shell/file/git convenience planning.
- `Agent.swift` remains broad after this pass. The next structural target should be streaming action decoding or repeated-tool fallback, both of which are production runner responsibilities rather than mock-only code.

## 2026-06-23 Agent Streaming Helper Split

Overall grade after this slice: **A- architecture, A streaming helper boundary**.

Streaming action collection and partial assistant-preview parsing moved out of `AgentRunner` and into `AgentActionStreaming.swift`. Before this pass, `Agent.swift` still owned the incremental stream parser used by both the runner and TrustedRouter streaming client, including partial JSON string decoding for visible draft text. The runner now delegates stream collection, raw stream accumulation, draft-preview extraction, and duplicate-draft suppression to focused helpers and keeps the agent run loop easier to audit.

Code quality changes:

- Added `AgentActionStreaming.swift` for `AgentActionStreamCollector` and `AgentActionStreamPreview`.
- Preserved the existing public helper names so `TrustedRouterLLMClient`, runner streaming, and existing tests keep working.
- Added direct collector coverage for visible assistant draft callbacks.
- Added a parity gate so stream collection, raw stream accumulation, and partial JSON preview parsing do not drift back into `Agent.swift`.

Remaining risk:

- `Agent.swift` still owns repeated-tool fallback and tool-step execution sequencing. Those are production runner responsibilities and should be extracted in later focused passes once the streaming boundary is stable on CI.
- The partial JSON preview parser is intentionally lightweight and tolerant because it runs on incomplete streamed action JSON. If model streaming schemas grow beyond string previews, evolve this helper rather than adding ad hoc preview parsing in the runner or UI.

## 2026-06-23 Agent Tool-Step Runner Split

Overall grade after this slice: **A architecture, A tool-step boundary, A regression coverage**.

Individual tool-step execution moved out of `Agent.swift` and into `AgentToolStepRunner.swift`. Before this pass, the main agent runner mixed the high-level model/tool loop with availability checks, safety-review blocking copy, queued/running/completed event emission, actual tool dispatch, apply-patch follow-up diff execution, and tool feedback serialization. `AgentRunner.send(...)` now stays focused on the orchestration loop, repeated-call fallback, and final-answer handoff, while the extracted runner owns one complete tool step.

Code quality changes:

- Added `AgentToolStepRunner.swift` for `AgentToolStep`, `AgentToolStepCompletion`, `runToolStep(...)`, and tool feedback serialization.
- Centralized queued/running/result transcript event emission for both primary tool calls and apply-patch follow-up diff calls.
- Preserved existing behavior for safety-review blocks, unavailable tools, patch diff refresh, repeated-tool fallback, and tool feedback messages.
- Added a parity gate so tool-step execution, lifecycle event emission, and unavailable-tool copy do not drift back into `Agent.swift`.

Remaining risk:

- `Agent.swift` still owns the repeated-tool fallback itself. That is now small enough to audit inline, but a later pass could extract a tiny `AgentToolStepHistory` if more loop policies are added.
- `AgentToolStepRunner` still performs both safety review and execution. That is the right boundary for now because the transcript event sequence depends on both, but if safety policy grows richer it should split into a pure review-copy planner plus the executor.

## 2026-06-23 Git Tool Definitions Split

Overall grade after this slice: **A architecture, A schema ownership, A regression coverage**.

Git tool schema declarations moved out of `GitToolExecutor.swift` and into `GitToolDefinitions.swift`. Before this pass, the executor mixed process execution, path validation, GitHub CLI request construction, worktree safety, patch helpers, and the entire `ToolDefinition` catalog. The executor now stays focused on running git/GitHub commands and validating inputs, while the catalog owns the user/model-facing tool names, descriptions, JSON schemas, host, and risk metadata.

Code quality changes:

- Added `GitToolDefinitions.swift` as the single QuillCodeTools source for local git, GitHub PR, and worktree `ToolDefinition` values.
- Removed JSON schema strings from `GitToolExecutor.swift`, reducing the chance that runtime execution code and tool-catalog text evolve in the same broad file.
- Added a parity gate so git tool schemas and `parametersJSON` definitions do not drift back into the executor.

Remaining risk:

- `GitToolExecutor.swift` is still broad because it owns both local git execution and GitHub CLI execution. A later pass should split GitHub PR command execution into a dedicated executor once the remote git planner work has stabilized on main.
- `ToolDefinition` declarations still use raw JSON schema strings across tool catalogs. That is acceptable for compatibility today, but a future A+ pass should consider a small schema builder or snapshot test if more tools are added.

## 2026-06-23 GitHub Pull Request Executor Split

Overall grade after this slice: **A architecture, A command boundary, A regression coverage**.

GitHub pull request command construction moved out of `GitToolExecutor.swift` and into `GitHubPullRequestToolExecutor.swift`, and raw git/gh process launching moved into `GitProcessRunner.swift`. Before this pass, the git executor still mixed local git operations, PR-specific `gh pr` argument construction, PR selector/reviewer/label validation, URL artifact extraction, and raw `Process` management. The executor is now a stable compatibility facade for tool-router and remote-planner call sites, while PR behavior and process execution have focused owners.

Code quality changes:

- Added `GitHubPullRequestToolExecutor` for create/view/checks/diff/checkout/edit/comment/review/merge PR operations.
- Moved PR selector, reviewer, label, review-action, merge-method, and URL artifact helpers beside the PR executor.
- Added `GitProcessRunner` as the shared git and GitHub CLI process boundary, preserving fake `gh` injection for tests.
- Kept the existing `GitToolExecutor` public API as delegating wrappers so tool routing and older tests do not need broad churn.
- Added a parity gate so GitHub PR command construction, URL artifacts, and raw process launching do not drift back into `GitToolExecutor.swift`.

Remaining risk:

- Local git, worktree, patch, and shared validation helpers still live in `GitToolExecutor.swift`. The next tools-layer quality pass should split worktree creation/removal or shared git input validation once this PR boundary is stable on main.
- `GitHubPullRequestToolExecutor` intentionally reuses shared trimming and git-name validation through `GitToolExecutor` for behavioral compatibility. A future cleanup can move those helpers into a smaller `GitInputValidator` without changing tool behavior.

## 2026-06-23 Git Worktree Executor Split

Overall grade after this slice: **A architecture, A worktree safety boundary, A regression coverage**.

Git worktree list/create/remove behavior moved out of `GitToolExecutor.swift` and into `GitWorktreeToolExecutor.swift`. Before this pass, the git facade still owned worktree path normalization, sibling-worktree policy, registered-worktree lookup, artifact construction, and `git worktree` argument construction. The facade now delegates to a focused worktree executor, keeping local git status/diff/stage/restore/commit/push and hunk patching easier to audit separately.

Code quality changes:

- Added `GitWorktreeToolExecutor` for `git worktree list --porcelain`, `git worktree add`, and `git worktree remove`.
- Moved worktree sibling path validation and registered-worktree lookup beside the worktree executor.
- Hardened worktree creation by validating optional branch and base refs with the same git-name guard used by push and PR checkout branch creation.
- Preserved the existing `GitToolExecutor` public API as thin delegates for tool-router compatibility.
- Added a focused worktree safety test plus a parity gate so worktree command construction and path validation do not drift back into `GitToolExecutor.swift`.

Remaining risk:

- `GitToolExecutor.swift` still owns local file path validation and hunk patch application. The next tools-layer cleanup should split hunk patch staging/restoring into a focused patch executor or move shared git input validation into a small validator type.
- Worktree base validation intentionally uses the existing git-name character policy. That covers common branches, remotes, and commit hashes; if users need richer refspec syntax later, expand the shared validator deliberately with tests rather than relaxing worktree creation only.

## 2026-06-23 Git Input Validator Split

Overall grade after this slice: **A architecture, A validation reuse, A local/remote parity**.

Shared git input validation moved out of `GitToolExecutor.swift` and into `GitInputValidator.swift`. Before this pass, the newer `GitHubPullRequestToolExecutor`, `GitWorktreeToolExecutor`, and SSH Remote git planner had to depend back on the broad git facade for trimming, git-name validation, and local path validation. That inverted the intended dependency direction after the PR and worktree executor splits. The focused executors now share a neutral validator, while `GitToolExecutor` keeps small compatibility wrappers for older tests and tool-router call sites.

Code quality changes:

- Added `GitInputValidator` for shared `trimmedNonEmpty`, `safeName`, and `safeRelativePath` behavior.
- Replaced focused executor and remote planner calls to `GitToolExecutor.safeGitName` / `trimmedNonEmpty` with `GitInputValidator`.
- Preserved `GitToolExecutor.safeGitName` and `trimmedNonEmpty` as delegating compatibility methods.
- Hardened SSH Remote worktree creation so branch and base refs use the same validation policy as local worktree creation.
- Added direct validator coverage, remote worktree validation coverage, and a parity gate that prevents focused executors from depending on the git facade for shared validation.

Remaining risk:

- PR-specific validators still live beside `GitHubPullRequestToolExecutor`, which is the right current boundary. If more GitHub issue/release tools appear, split those validators into a `GitHubInputValidator` rather than moving them back into the git facade.
- `GitToolExecutor.swift` is now a small compatibility facade over focused git executors plus local stage/restore/commit/push. The next tools-layer cleanup should either extract basic local git file actions or remove older facade compatibility wrappers once direct executor call sites are ready.

## 2026-06-23 Git Patch Executor Split

Overall grade after this slice: **A architecture, A patch safety boundary, A local/remote parity**.

Git hunk staging/restoring moved out of `GitToolExecutor.swift` and into `GitPatchToolExecutor.swift`, and shared git error cases moved into `GitToolError.swift`. Before this pass, the git facade still owned temporary patch-file creation, `git apply --check`, hunk application, diff metadata parsing, and patch-path mismatch validation. The facade now delegates hunk work to a focused patch executor, while SSH Remote hunk planning reuses the same patch-path validator.

Code quality changes:

- Added `GitPatchToolExecutor` for local hunk staging/restoring and patch-path mismatch validation.
- Added `GitToolError` as the shared git error boundary so focused executors do not depend on an enum hidden in the git facade.
- Rewired `GitToolExecutor.stageHunk` and `restoreHunk` to thin delegates.
- Rewired SSH Remote hunk planning to use `GitPatchToolExecutor.mismatchedPatchPath`, keeping local and remote patch safety aligned.
- Added coverage for quoted diff paths, remote stage-hunk command planning, and a parity gate so patch application and diff metadata parsing do not drift back into `GitToolExecutor.swift`.

Remaining risk:

- `PatchToolExecutor` has its own diff-path parser for generic apply-patch behavior. That is a separate tool boundary today; if parser behavior needs to converge, extract a neutral diff metadata parser rather than making either executor depend on the other.

## 2026-06-23 Calm Composer And Tool-Card Pass

Overall grade after this slice: **A- UI consistency, A regression coverage, B+ interaction depth**.

The top bar and composer now have clearer ownership: the top bar owns project/status context, while the composer owns send-time model and Auto-safety controls. Before this pass, the composer repeated the top-bar agent status and the Auto/Review/Read-only control tinted the entire pill, which made the send area feel busier than Codex. Tool cards also over-emphasized successful work with green rails and colored strokes that competed with real review/error states.

Code quality changes:

- Rendered the top-bar subtitle as visible secondary context in the native SwiftUI bar instead of hiding it in a tooltip.
- Promoted the top-bar agent status from a color-only dot to a compact text chip, preserving the dot for active/error states.
- Removed duplicate agent-status text from native and HTML composers.
- Renamed the mode affordance to "Auto safety" in help and accessibility copy.
- Made mode controls neutral except for the small mode dot, preserving the state signal without making the whole control shout.
- Reduced successful/queued/running tool-card chrome so review and failure states carry the visual emphasis.
- Replaced generic "Show raw details" copy with details labels that match what is available: input, output, or both.

Remaining risk:

- Review tool cards still need first-class Approve/Reject buttons wired to the approval decision path. That requires a model/action boundary, not just view styling.
- The top-bar overflow menu still duplicates some sidebar/tool-palette actions. It remains for compatibility in this slice; a later navigation pass should decide whether Settings and utility commands live in the sidebar, command palette, native menu bar, or top bar.

## 2026-06-23 Git Local Executor Split

Overall grade after this slice: **A architecture, A local-git boundary, A regression coverage**.

Basic local git execution moved out of `GitToolExecutor.swift` and into `GitLocalToolExecutor.swift`. Before this pass, the git facade still owned `status`, `diff`, `stage`, `restore`, `commit`, `push`, current-branch lookup, and local path validation after the GitHub PR, worktree, patch, and validator splits. The facade now delegates local git behavior to a focused executor, making the tool-router API stable while keeping local command construction directly testable.

Code quality changes:

- Added `GitLocalToolExecutor` for local status/diff/stage/restore/commit/push behavior.
- Moved local file path validation and current branch lookup beside the local executor.
- Kept `GitToolExecutor` as a thin compatibility facade over local, GitHub PR, worktree, and patch executors.
- Added direct local-executor behavior coverage and a parity gate that prevents local command construction from drifting back into the facade.

Remaining risk:

- `GitToolExecutor` still exposes older static compatibility wrappers for trimming, git-name validation, PR-specific validation, and URL extraction. They should remain while older tests and call sites use them, but new focused executors should depend on `GitInputValidator` or their own domain helpers instead.
- PR-specific validators are still correctly owned by `GitHubPullRequestToolExecutor`; if future GitHub issue/release tools arrive, split those into a focused GitHub validator rather than expanding the facade again.

## 2026-06-23 GitHub PR Input/Output Helper Split

Overall grade after this slice: **A architecture, A local/remote parity, A regression coverage**.

GitHub pull request validation and URL artifact parsing moved out of `GitHubPullRequestToolExecutor.swift`. Before this pass, the PR executor still owned selector validation, reviewer and label normalization, review-action and merge-method normalization, GitHub reviewer component parsing, and URL extraction in addition to building and running `gh pr` commands. The executor now delegates validation to `GitHubPullRequestInputValidator` and artifact URL parsing to `GitHubPullRequestOutputParser`, and SSH Remote PR planning uses the same helpers.

Code quality changes:

- Added `GitHubPullRequestInputValidator` for PR selector, reviewer, label, review-action, and merge-method validation.
- Added `GitHubPullRequestOutputParser` for PR URL artifact extraction.
- Updated local PR execution, SSH Remote PR planning, and the git facade compatibility wrappers to share the focused helpers.
- Added direct helper coverage plus parity gates that prevent PR validation and URL extraction from drifting back into command execution.

Remaining risk:

- `GitToolExecutor` still exposes compatibility wrappers for older call sites. They are now simple delegates, but new code should use `GitInputValidator`, `GitHubPullRequestInputValidator`, or `GitHubPullRequestOutputParser` directly.
- `GitHubPullRequestToolExecutor` still owns per-operation argument construction. That is the right boundary for now; if GitHub issue/release tools appear, add new focused executors rather than broadening this PR executor.

## 2026-06-23 SSH Remote GitHub PR Builder Split

Overall grade after this slice: **A architecture, A remote PR parity, A regression coverage**.

SSH Remote `gh pr` command construction moved out of `WorkspaceRemoteGitToolRequestPlanner.swift` and into `WorkspaceRemoteGitHubPullRequestCommandBuilder.swift`. Before this pass, the generic remote git planner owned local git commands, hunk patch transport, worktree commands, PR URL extraction intent, and every PR-specific `gh` argument assembly path. The planner now routes PR tools to a focused builder while keeping worktree/hunk planning local to the generic remote-git boundary.

Code quality changes:

- Added `WorkspaceRemoteGitHubPullRequestCommandBuilder` for SSH Remote PR create/view/checks/diff/checkout/reviewer/label/comment/review/merge commands.
- Kept PR URL artifact intent explicit in the builder, including the checks command remaining a PR tool without URL extraction.
- Reused `GitHubPullRequestInputValidator` and `GitInputValidator` from the remote builder so SSH Remote PR command safety matches local PR execution.
- Added direct remote PR builder coverage plus a parity gate that prevents `gh pr` argument assembly from drifting back into the generic remote git planner.

Remaining risk:

- `WorkspaceRemoteGitToolRequestPlanner.swift` still owns remote hunk and worktree command assembly. Those boundaries are stable for now, but future transport work should extract them if QuillCloud relay or non-SSH transports need the same command plans.

## 2026-06-23 SSH Remote Worktree Builder Split

Overall grade after this slice: **A architecture, A remote worktree boundary, A regression coverage**.

SSH Remote git worktree command construction moved out of `WorkspaceRemoteGitToolRequestPlanner.swift` and into `WorkspaceRemoteGitWorktreeCommandBuilder.swift`. Before this pass, the generic remote git planner still owned worktree list/create/remove command assembly, sibling path normalization orchestration, and create-artifact reporting. The planner now delegates worktree tools to a focused builder and remains responsible only for routing remote git command families plus hunk/push behavior that has not yet grown enough to split.

Code quality changes:

- Added `WorkspaceRemoteGitWorktreeCommandBuilder` and `WorkspaceRemoteGitWorktreePlan` for list/create/remove commands and artifact intent.
- Kept remote worktree path normalization and SSH artifact labels behind the builder boundary.
- Reduced `WorkspaceRemoteGitToolRequestPlanner` to routing plus remaining push/hunk planning.
- Added direct worktree-builder tests and parity gates that prevent worktree command assembly from drifting back into the generic remote git planner.

Remaining risk:

- Remote hunk patch transport and push-current-branch shell guards still live in `WorkspaceRemoteGitToolRequestPlanner.swift`. Those are smaller, stable seams today; extract them if future remote transports need to reuse the same plans.

## 2026-06-23 SSH Remote Hunk Builder Split

Overall grade after this slice: **A architecture, A patch-safety boundary, A regression coverage**.

SSH Remote git hunk command construction moved out of `WorkspaceRemoteGitToolRequestPlanner.swift` and into `WorkspaceRemoteGitHunkCommandBuilder.swift`. Before this pass, the generic remote git planner still owned stage/restore hunk argument selection, patch path validation orchestration, base64 patch transport, temp-file cleanup, and `git apply` check/apply command assembly. The planner now delegates hunk tools to a focused builder and remains responsible only for routing remote git command families plus push behavior.

Code quality changes:

- Added `WorkspaceRemoteGitHunkCommandBuilder` for stage/restore hunk command construction.
- Kept shared patch path validation through `GitPatchToolExecutor.mismatchedPatchPath`.
- Removed base64 patch transport and temp-file command details from the generic remote git planner.
- Added direct hunk-builder tests and parity gates that prevent hunk command assembly from drifting back into the planner.

Remaining risk:

- Remote push-current-branch shell guards still live in `WorkspaceRemoteGitToolRequestPlanner.swift`. That is now the last non-routing command seam in the file and should be extracted if push behavior grows or QuillCloud remote transports need a reusable plan.

## 2026-06-23 SSH Remote Push Builder Split

Overall grade after this slice: **A architecture, A push-safety boundary, A regression coverage**.

SSH Remote git push command construction moved out of `WorkspaceRemoteGitToolRequestPlanner.swift` and into `WorkspaceRemoteGitPushCommandBuilder.swift`. Before this pass, the generic remote git planner still owned explicit branch pushes, default remote selection, upstream flags, current-branch detection, current-branch safety guards, and branch/remote validation. The planner now delegates push tools to a focused builder and is left as a routing layer plus simple one-line git commands.

Code quality changes:

- Added `WorkspaceRemoteGitPushCommandBuilder` for explicit and current-branch push commands.
- Kept shared git name validation through `GitInputValidator.safeName`.
- Removed current-branch shell guards from the generic remote git planner.
- Added direct push-builder tests and parity gates that prevent push command assembly from drifting back into the planner.

Remaining risk:

- `WorkspaceRemoteGitToolRequestPlanner.swift` still owns simple status/diff/stage/restore/commit command routing. That is acceptable while those cases remain one-line commands; extract a basic-command builder only if those behaviors grow.

## 2026-06-23 SSH Remote Basic Git Builder Split

Overall grade after this slice: **A+ routing boundary, A command coverage, A regression gates**.

SSH Remote basic git command construction moved out of `WorkspaceRemoteGitToolRequestPlanner.swift` and into `WorkspaceRemoteGitBasicCommandBuilder.swift`. Before this pass, the generic planner still assembled status, diff, file stage/restore, and commit commands inline while delegating the larger hunk, push, PR, and worktree command families. The planner now acts as a pure router from tool names to focused builders, which makes remote execution easier to reuse for SSH and future QuillCloud transports.

Code quality changes:

- Added `WorkspaceRemoteGitBasicCommandBuilder` for status, diff, file stage/restore, and commit commands.
- Kept remote file path normalization through `WorkspaceRemoteProjectPath.relativePath`.
- Kept empty commit-message validation beside commit command construction.
- Added direct basic-builder tests and parity gates that prevent basic command strings from drifting back into the generic planner.

Remaining risk:

- The focused remote git builders still return shell strings because SSH execution currently accepts shell commands. If QuillCloud remote execution gains a structured command transport, introduce a shared command-plan type behind these builders rather than pushing structured execution back into the planner.

## 2026-06-23 Explicit Mode Control Pass

Overall grade after this slice: **A UI hierarchy, A regression coverage, B+ interaction depth**.

The composer mode control now reads as an explicit safety mode selector instead of a color-coded status dot. Before this pass, the Auto/Review/Read-only control used the same dot language as the top-bar agent status, which made health state and safety mode visually compete. The control now uses a neutral shield affordance and the label "Mode · Auto", while preserving the existing value hook for tests and automation.

Code quality changes:

- Replaced the native SwiftUI mode dot with a neutral shield icon and explicit "Mode" label.
- Removed native mode-specific color mapping so approval mode does not reuse health-status color semantics.
- Updated the HTML renderer and Playwright harness to emit the same explicit mode structure.
- Removed mode-dot CSS from the harness and kept the mode pill neutral across Auto, Review, and Read-only.
- Added parity and E2E coverage that prevents the mode control from drifting back to a color-dot-only affordance.

Remaining risk:

- The mode picker still cycles modes in the HTML harness instead of opening a menu like the native SwiftUI control. That is acceptable for fixture coverage today, but a future harness parity pass should model the menu if mode-specific explanations or warnings move into the picker.
- Review and Read-only modes still do not add an ambient composer cue. A later interaction pass should consider a subtle non-color-only indicator when the user is outside Auto.

## 2026-06-23 Tool Card Subtitle Builder Pass

Overall grade after this slice: **A- UI scanability, A presentation boundary, A regression coverage**.

Collapsed completed tool cards now preserve the concrete action in their subtitle, so users can scan a long transcript without expanding raw JSON. The behavior is presentation-only and lives behind one focused builder instead of spreading argument parsing through transcript projection.

| Surface | Before | After |
| --- | --- | --- |
| Completed tool cards | Collapsed to generic `Completed`, losing the command or file path. | Collapse to labels such as `Completed · whoami` and `Completed · hello.txt`. |
| Transcript projection | Lifecycle labels were hardcoded in both card and timeline paths. | Both paths call `WorkspaceToolCardSubtitleBuilder` through the transcript builder. |
| Mock harness | Demo cards repeated native subtitle drift manually. | Plain lifecycle subtitles are enriched with the same argument summary rules. |

Code quality changes:

- Added `WorkspaceToolCardSubtitleBuilder` as the single presenter for safe, compact tool-card action summaries.
- Kept summaries bounded and whitespace-normalized so long commands do not destabilize collapsed card layout.
- Added focused Swift coverage for known tool summaries, fallback behavior, and transcript lifecycle projection.
- Added Playwright coverage proving the mock command flow shows the command in the collapsed card subtitle.

## 2026-06-23 Actionable Review Card Pass

Overall grade after this slice: **A- interaction clarity, A surface wiring, A regression coverage**.

Claude CLI's interface review called out review cards as the highest-value interaction fix: the old flow could show a queued tool, then a separate safety/review card, leaving the user to infer what action was expected. Review now lives on the affected tool card itself with direct actions.

| Surface | Before | After |
| --- | --- | --- |
| Review cards | A separate warning-styled `Safety Check` card appeared after the queued tool. | The queued tool card becomes a neutral review card with `Run` and `Skip` actions. |
| Safety tone | Review states used a warning perimeter even when the model had not found danger. | Review states use neutral chrome; failure remains red and actual denial can still carry stronger copy. |
| Action path | Approval state was represented in transcript events but had no first-class card action. | `ToolCardActionSurface` flows from transcript projection through SwiftUI, HTML, desktop controller, and workspace model execution. |

Code quality changes:

- Added first-class `ToolCardActionSurface` state instead of embedding action affordances in view-only code.
- Updated transcript projection so `approvalRequested` replaces the active queued tool card, preserving context and avoiding duplicate cards.
- Added model execution for card actions: approve appends an `ApprovalDecision` and dispatches the original `ToolCall`; skip records the decision and adds a short assistant notice.
- Carried the reviewer verdict into `ApprovalRequest`, so hard-denied commands remain visible as blocked review cards without exposing an approval override.
- Added Swift and Playwright coverage for native projection, model dispatch, HTML rendering, and harness click behavior.

Remaining risk:

- The current approval action reruns from the serialized redacted tool call, which is correct for shell/file arguments covered today. If future tools need non-transcript-safe in-memory fields, the runner should retain a pending approval registry keyed by request ID.
- The review UI now handles approve/skip. A later pass should add a lightweight "edit command before running" path for commands where the user wants to fix arguments instead of approving or skipping.

## 2026-06-23 Agent Action Parser Hardening Pass

Overall grade after this slice: **A parser resilience, A safety boundary, A regression coverage**.

The TrustedRouter action parser now recovers from two common live-model formatting failures without moving command inference into the UI: an explicit prose response such as "I'll run `whoami`" and a `host.shell.run` JSON action with empty arguments beside an explicit backticked command. This closes the failure mode where QuillCode could show an empty shell card and then fail with "No shell command was specified" even though the model text already named the command.

| Case | Before | After |
| --- | --- | --- |
| Prose-only model action | Rejected as invalid action JSON. | Recovered only when the model explicitly says it will run/execute/check a backticked command. |
| Empty shell arguments | Threw or produced an empty command path depending on call shape. | Repairs `cmd` from an adjacent explicit command before validation. |
| Passive or negative prose | Risk of becoming future over-broad recovery if added casually. | Tests reject passive text and "I will not run `...`" negative intent. |

Code quality changes:

- Kept recovery in the model-output parser boundary, not in transcript UI, tool cards, or user-prompt heuristics.
- Added bounded inline-code extraction with execution-intent and negative-intent checks.
- Preserved hard validation for `host.shell.run`: a non-empty `cmd` is still required before any tool call is emitted.
- Added focused adapter tests covering recovered prose, repaired empty shell arguments, passive prose rejection, and negative-intent rejection.

Remaining risk:

- Recovery is intentionally conservative and only handles explicit backticked shell commands. Broader malformed tool output should be solved with stronger structured-response/tool-calling support rather than more natural-language inference.

## 2026-06-23 Agent Action Parser Extraction Pass

Overall grade after this slice: **A architecture boundary, A transport simplicity, A regression coverage**.

`TrustedRouterLLMClient.swift` now owns the TrustedRouter action transport only. The action parser moved into `AgentActionJSONParser.swift`, where JSON extraction, tool argument normalization, and conservative malformed-output recovery can evolve without bloating the network client.

Code quality changes:

- Moved `AgentActionJSONParser` into a focused file beside the agent streaming helpers.
- Removed the parser's Computer Use/tool imports from `TrustedRouterLLMClient.swift`.
- Added a parity gate that requires action parsing, argument normalization, and recovery logic to stay outside the TrustedRouter transport client.
- Preserved existing parser behavior and tests from the hardening pass.

## 2026-06-24 Agent Action Parser Helper Split

Overall grade after this slice: **A+ parser focus, A+ malformed shell recovery boundary, A+ JSON extraction ownership**.

`AgentActionJSONParser.swift` was already separate from TrustedRouter transport, but it still mixed four jobs: stripping fences and finding embedded JSON objects, routing action types, normalizing tool arguments, and recovering explicit shell commands from prose. That made the empty-shell-command reliability path harder to reason about because JSON scanning and natural-language recovery were interleaved with canonical tool argument rules.

Code quality changes:

- Added `AgentActionJSONExtractor.swift` for code-fence stripping and balanced JSON-object extraction from prose.
- Added `AgentShellCommandRecovery.swift` for conservative explicit shell-command recovery from model prose.
- Kept `AgentActionJSONParser.swift` focused on action routing, tool-name detection, argument normalization, and final non-empty argument validation.
- Tightened the parity gate so JSON scanning and prose shell-command recovery cannot drift back into the parser or TrustedRouter transport client.

Remaining risk:

- Tool argument normalization is still a large switch because it mirrors the current built-in tool catalog. If tool aliases grow substantially, split per-tool alias normalization into a small catalog keyed by `ToolDefinition.name`.

## 2026-06-23 TrustedRouter Prompt Builder Pass

Overall grade after this slice: **A transport boundary, A prompt contract clarity, A regression coverage**.

`TrustedRouterLLMClient.swift` no longer owns system-prompt construction or message-history projection. Prompt rendering, project instruction context, memory context, tool-output projection, current-user deduping, and the history window now live in `TrustedRouterPromptBuilder`.

Code quality changes:

- Added `TrustedRouterPromptBuilder` as a focused value type with an explicit `historyLimit`.
- Kept the strict action JSON and canonical tool-argument contract beside the prompt boundary that owns it.
- Reduced `TrustedRouterLLMClient` to API-key delegation, TrustedRouter SDK calls, and streamed action collection.
- Moved adapter tests for prompt text and message projection to the builder boundary.
- Added focused coverage proving the builder applies an explicit history window.

Remaining risk:

- Prompt copy is still a large literal because it is intentionally explicit. Future tool families should add concise schema examples or generated prompt fragments instead of expanding the literal indefinitely.

## 2026-06-23 TrustedRouter API Key Resolver Pass

Overall grade after this slice: **A auth boundary, A DRY transport clients, A regression coverage**.

TrustedRouter API-key resolution was duplicated between the action client and the safety-review client. Override precedence, whitespace trimming, session-store fallback, and the missing-key error now live in `TrustedRouterAPIKeyResolver`.

Code quality changes:

- Added `TrustedRouterAPIKeyResolver` as the single owner of developer override and stored-key resolution.
- Reused the resolver from both `TrustedRouterLLMClient` and `TrustedRouterSafetyModelClient`.
- Added focused tests for override precedence, stored-key fallback, trimming, and actionable missing-key errors.
- Added a parity gate preventing key trimming and session-store fallback from drifting back into the transport clients.

Remaining risk:

- Safety-review response framing is still intentionally minimal. If Auto-review needs richer telemetry or structured diagnostic events, add a dedicated response mapper beside the safety client rather than expanding the network method.

## 2026-06-23 TrustedRouter Safety Client File Pass

Overall grade after this slice: **A transport boundaries, A file ownership, A regression coverage**.

The TrustedRouter action client and Auto-review safety client are now separate transport files. `TrustedRouterLLMClient.swift` owns streaming action requests only, while `TrustedRouterSafetyModelClient.swift` owns reviewer-model JSON response calls.

Code quality changes:

- Moved `TrustedRouterSafetyModelClient` into `TrustedRouterSafetyModelClient.swift`.
- Removed the `QuillCodeSafety` import from the action transport file.
- Added a parity gate preventing the safety client from drifting back into `TrustedRouterLLMClient.swift`.
- Extended the API-key resolver parity gate so both action and safety transports must delegate key resolution.

Remaining risk:

- Safety-review transport is still intentionally thin. If reviewer calls start carrying additional telemetry, retries, or model-specific options, add those beside `TrustedRouterSafetyModelClient` rather than expanding the action transport.

## 2026-06-23 TrustedRouter Chat Parameters Pass

Overall grade after this slice: **A dependency direction, A request-parameter ownership, A regression coverage**.

Shared TrustedRouter JSON response parameters no longer live on the action client. Both action streaming and Auto-review transport now use `TrustedRouterChatParameters.jsonObjectResponse`, so `TrustedRouterSafetyModelClient` has no dependency on `TrustedRouterLLMClient`.

Code quality changes:

- Added `TrustedRouterChatParameters` as the single owner of the JSON-object response-format payload.
- Rewired action and safety transports to use the shared parameter catalog.
- Added a parity gate preventing raw response-format payloads from drifting back into either transport.
- Updated the decision log to document the dependency direction.

Remaining risk:

- If TrustedRouter adds native tool-calling parameters, those should become explicit parameter values here instead of adding one-off dictionaries in transport methods.

## 2026-06-23 Native Top Bar Simplification Pass

Overall grade after this slice: **A- visual hierarchy, A shared-state preservation, A regression coverage**.

Claude CLI's interface critique called out the native top bar as the largest visible gap from Codex: it was carrying title, subtitle, status, runtime issue, and overflow controls at the same weight. The native top bar now keeps the active thread as the visual center, leaves project/model context as quiet metadata, and demotes status/error state to an accessibility label plus a thin activity hairline.

| Surface | Before | After |
| --- | --- | --- |
| Native top bar | Visible status and runtime issue pills competed with the active thread title. | Three-slot chrome: quiet context, centered thread title, overflow menu. |
| Running/error state | Permanent pills added visual weight even when the transcript already showed the active work. | A one-point hairline appears only while an agent state or runtime issue needs attention. |
| Overflow button | Drew another outlined control in the top bar. | Keeps a 40-point hit target with a softer fill and no extra stroke. |

Code quality changes:

- Kept `TopBarStatusPresentation` and `TopBarRuntimeIssuePresentation` as shared semantics for native, HTML, and accessibility paths.
- Added `QuillCodeMetrics.topBarHeight` so compact top-bar height is a named design token.
- Added a parity gate that prevents permanent native status/runtime pills from creeping back into the main chrome.

Remaining risk:

- Model and mode controls still sit in a separate composer controls row. A follow-up UI slice should fold them into the composer itself, matching the Codex-style focused input.

## 2026-06-23 Terminal Lifecycle Extraction Pass

Overall grade after this slice: **A terminal state boundary, A orchestration readability, A regression coverage**.

The terminal command path previously mixed input normalization, run-entry creation, streaming event application, missing-context failure, cancellation cleanup, marker cleanup, environment/cwd persistence, and top-bar orchestration inside `WorkspaceModel.runTerminalCommand`. The model now reads as a high-level command runner, while `WorkspaceTerminalEngine` owns the terminal lifecycle transitions.

| Area | Before | After |
| --- | --- | --- |
| Workspace model | Manually mutated terminal entries for begin/stream/stop/finish. | Delegates lifecycle mutations to named engine helpers. |
| Terminal engine | Owned low-level state primitives but not the full run lifecycle. | Owns begin, streaming event application, missing-context failure, cancellation, stopped cleanup, and completed-run persistence. |
| Tests | Integration coverage caught behavior drift but lifecycle transitions were not individually guarded. | Focused unit coverage exercises lifecycle begin/reject, streaming, missing context, completion, cancellation, and marker cleanup. |

Remaining risk:

- `WorkspaceModel` still contains broader command and automation orchestration. Future slices should continue extracting by responsibility, but terminal execution is now a cleaner boundary for both local and SSH Remote terminal work.

## 2026-06-23 Composer Surface Consolidation Pass

Overall grade after this slice: **A interaction focus, A surface parity, A regression coverage**.

The composer now reads as one focused input surface instead of a panel with a separate controls band above the message field. Model selection and Auto/Review/Read-only approval mode remain separate controls, but they are now an accessory bar inside the composer surface where send-time choices belong. A Claude CLI design review called out that the first version still had too much label chrome, no ordinary focus response, and an over-explained mode chip; this pass folded those concrete fixes into the same slice.

| Surface | Before | After |
| --- | --- | --- |
| Native composer | Model and mode controls sat as their own row before the text input. | Input, send/stop, model, and mode are grouped inside one rounded composer surface. |
| HTML/Playwright harness | Mirrored the old two-band composer layout. | Mirrors the single-surface composer with `composer-surface`, `composer-input-row`, and `composer-controls`. |
| Message field | Had its own nested rounded field inside the panel. | Uses the composer surface as the outer boundary, reducing nested outlines and keeping the visible label out of the surface. |
| Focus feedback | The textarea cursor was the only ordinary focus cue. | The whole composer surface brightens on focus, while slash suggestions still get the stronger blue cue. |
| Safety mode control | Used a wordy `Mode · Auto` label that competed with the model picker. | Uses a compact tone dot plus `Auto`, with the full safety meaning preserved in accessibility labels. |
| Radius and separators | The first surface used softer 16 pt rounding and an extra outer divider. | Uses a tighter 12 pt composer radius and relies on the surface boundary instead of a double divider. |

Code quality changes:

- Preserved independent model and approval-mode controls so model selection does not own safety-mode mutation.
- Added static HTML and Playwright checks for the single-surface composer structure, compact mode cue, and accessible hidden label.
- Kept minimum hit targets for model, mode, send, and stop controls.

Remaining risk:

- The model and mode controls are still visually two controls inside the accessory bar. A later pass can design a single compact disclosure affordance if user testing shows that the current split still feels too busy.

## 2026-06-23 HTML Top Bar Quiet Chrome Pass

Overall grade after this slice: **A visual parity, A interaction restraint, A regression coverage**.

Claude CLI's follow-up design review reinforced the same Codex-style direction: the top bar should feel almost empty at rest, with status details living in transcript/tool surfaces and only a subtle activity cue in the chrome. The HTML harness now matches the native top-bar contract so Playwright screenshots test the same quiet workspace users see in SwiftUI.

| Surface | Before | After |
| --- | --- | --- |
| HTML top bar | Visible idle/running status menu, runtime issue pill, and metadata cluster crowded the top chrome. | Left context label, centered title, right overflow, and hidden status metadata for tests only. |
| Activity state | Status text carried the visual state. | A thin activity hairline appears only for running, stopped, failed, or runtime issue states. |
| Test hooks | Status details were interactive UI because tests needed selectors. | Metadata is `aria-hidden`, visually hidden, and guarded by Playwright so it cannot become visible chrome by accident. |
| Regression tests | Swift tests expected the old status menu/popover. | Swift and Playwright tests now reject visible status buttons, menus, and popovers in the top bar. |

Remaining risk:

- Claude suggested moving the final visible overflow control to a hover-revealed affordance. That should be a separate native+HTML pass because it changes keyboard discoverability and needs accessibility review.

## 2026-06-23 Sidebar Time Grouping Pass

Overall grade after this slice: **A- sidebar scanability, A surface ownership, A regression coverage**.

Claude CLI's sidebar review called out that a single "Recent" bucket makes active chats harder to scan once the project has history. The sidebar now groups non-pinned, non-archived chats by shared recency buckets while preserving explicit Pinned and Archived workflow sections.

| Surface | Before | After |
| --- | --- | --- |
| Sidebar sections | Active chats lived under one generic `Recent` section. | Active chats group into Today, Yesterday, Previous 7 days, and Older. |
| Shared contract | Native SwiftUI and HTML renderers could drift if each owned date bucketing. | `SidebarSurface.recentSections(now:calendar:)` owns section construction and native/static surfaces consume it. |
| Ordering | Bucket row order was inherited from caller order. | Rows sort newest-first inside each bucket. |
| Harness parity | New harness chats relied on fallback timestamps and sort only handled pinned/archived state. | Harness chat creation records `updatedAt`, refreshes recency on send, and sorts by archived/pinned/updated time. |
| Visual weight | Long section labels could wrap or compete with thread rows. | Headers stay small, muted, single-line, and truncated if the sidebar is narrow. |

Remaining risk:

- Sidebar search is currently a modal global search rather than an inline filtered list. If QuillCode adds inline sidebar filtering later, filtered results should collapse section headers to keep scanning fast.

## 2026-06-23 Command Action Executor Pass

Overall grade after this slice: **A command orchestration boundary, A behavior preservation, A regression coverage**.

| Area | Before | After |
| --- | --- | --- |
| `WorkspaceModel` | Owned command action planning delegation and the full typed effect execution switch. | Delegates command actions to `WorkspaceCommandActionExecutor`. |
| Command action code | Planning and effect execution were conceptually separate but not separated by file ownership. | `WorkspaceCommandActionPlanner` maps current context to typed effects; `WorkspaceCommandActionExecutor` applies those effects. |
| Regression guard | Existing behavior tests covered command outcomes but not ownership. | Parity gate keeps the planner setup and effect switch out of `WorkspaceModel.swift`. |

Remaining risk:

- `WorkspaceModel.runWorkspaceCommand` still owns broader command-plan execution for local environment actions, memory, automation, MCP, extension, activity, draft, tool, and action plans. Extract command-plan execution if those side effects keep growing.

## 2026-06-23 Calm Approval Card Presentation Pass

Overall grade after this slice: **A copy semantics, A safety preservation, A native/static parity**.

| Area | Before | After |
| --- | --- | --- |
| Approval-card copy | Routine approvals surfaced raw `Review` language and `Allow once`/`Skip` actions. | Routine approvals present as `Ready` / `Ready to run` with `Run` and `Skip`. |
| Blocked safety state | Normal approvals and denied reviews could look equally serious. | Policy-denied reviews keep a softer explicit `Needs review` label and warning tone. |
| Shared presentation | Native, static HTML, and Playwright harness could drift on status labels. | `ToolCardState` owns display and accessibility labels; renderers consume that contract. |
| Review substate | Denied review cards were inferred from subtitle copy. | `ToolCardReviewState` carries `ready` versus `needsReview` explicitly, with subtitle parsing only as legacy fallback. |

Remaining risk:

- The approval queue still appears inline per tool card. A future UX slice should explore a compact pending-actions rail for batches of approvals without weakening the underlying safety review.

## 2026-06-23 Project Metadata Loader Pass

Overall grade after this slice: **A project-context boundary, A behavior preservation, A regression coverage**.

Project metadata aggregation moved from `WorkspaceModel` into `WorkspaceProjectMetadataLoader`. Before this pass, the workspace model knew the exact list of project instruction, local environment action, extension manifest, project memory, and SSH Remote context loaders. The model now asks for local or remote metadata and stays focused on applying that metadata to project/thread state.

Code quality changes:

- Added `WorkspaceProjectMetadataLoader.loadLocal(from:)` for local instruction/action/extension/memory aggregation.
- Added `WorkspaceProjectMetadataLoader.loadRemote(connection:executor:)` and `metadata(from:)` so SSH Remote context becomes the same `WorkspaceProjectMetadata` contract with local-only fields cleared.
- Updated add-project and refresh-context paths to delegate metadata loading.
- Added focused loader tests and a parity gate that prevents direct project metadata loader calls from returning to `WorkspaceModel`.

Remaining risk:

- The low-level project instruction, action, extension, and memory loader tests still mostly live in `WorkspaceModelTests.swift`. Future quality passes should move those into focused loader test files to reduce the model test monolith without changing behavior.

## 2026-06-24 Project Loader Test Ownership Pass

Overall grade after this slice: **A test ownership, A behavior preservation, A regression guard**.

The previous project metadata pass left pure loader tests inside `WorkspaceModelTests.swift`, which kept the model test suite oversized and made ownership less clear. This pass moved direct loader coverage into focused test files and left workspace-model tests responsible for integration behavior only.

Code quality changes:

- Added `ProjectInstructionLoaderTests` for nested instruction ordering, truncation, and symlink escape rejection.
- Added `LocalEnvironmentActionLoaderTests` for sidecar metadata, command construction, unsafe working-directory rejection, timeout bounds, and symlink escape rejection.
- Added `ProjectExtensionManifestLoaderTests` for plugin/skill/MCP manifest parsing, unsafe directory handling, symlink escape rejection, and fallback display names.
- Added `MemoryNoteLoaderTests` for project-memory bounds, truncation, and symlink escape rejection.
- Added shared `makeQuillCodeTestDirectory()` test support and reused it from `WorkspaceProjectMetadataLoaderTests`.
- Added a parity gate that keeps direct project loader API calls out of `WorkspaceModelTests.swift`.

Remaining risk:

- `WorkspaceModelTests.swift` is still too large at roughly 5.2k lines. The next test-quality pass should continue moving feature-specific integration groups into files named after their owning workspace engine or surface.

## 2026-06-23 Command Plan Executor Pass

Overall grade after this slice: **A command-plan boundary, A behavior preservation, A regression coverage**.

`WorkspaceModel.runWorkspaceCommand` was still the broad command-plan execution switch even after command parsing and typed action planning had been extracted. The public command API now lives in `WorkspaceCommandPlanExecutor`, which parses command IDs through `WorkspaceCommandPlan` and executes parsed plans through a directly testable `runWorkspaceCommandPlan` entry point.

| Area | Before | After |
| --- | --- | --- |
| `WorkspaceModel.swift` | Owned the full `WorkspaceCommandPlan` switch for local environment, memory, automation, MCP, extension, activity, draft, tool, and typed action plans. | Keeps the underlying state helpers, while command-plan routing lives in `WorkspaceCommandPlanExecutor.swift`. |
| Command execution tests | Covered behavior through `runWorkspaceCommand` and command parsing tests, but not the parsed-plan executor boundary. | Added focused executor tests for parsed draft and static-action plans. |
| Regression guard | The audit documented command-plan execution as remaining model risk. | Parity gate now prevents command-ID parsing and command-plan switching from returning to `WorkspaceModel.swift`. |

Remaining risk:

- `WorkspaceModelTests.swift` is still the largest test file because it carries many historical integration cases. Future cleanup should move behavior clusters into focused test files as extraction boundaries stabilize.

## 2026-06-24 Workspace Memory Integration Test Pass

Overall grade after this slice: **A feature grouping, A behavior preservation, A regression guard**.

Memory integration tests moved from the workspace-model monolith into `WorkspaceMemoryIntegrationTests`. The model test file no longer owns global/project memory loading, slash remember, agent memory tool execution, credential-like memory rejection, memory deletion, or memory-add command coverage.

Code quality changes:

- Added `WorkspaceMemoryIntegrationTests` as the home for memory flows that cross workspace model, memory loaders, tool cards, transcript events, and surfaces.
- Reused shared temp-directory support so moved tests clean up after themselves.
- Added a parity gate that keeps memory integration method names out of `WorkspaceModelTests.swift`.
- Reduced `WorkspaceModelTests.swift` from roughly 5.2k lines to roughly 5.0k lines without weakening coverage.

Remaining risk:

- `WorkspaceModelTests.swift` is still the largest test file. MCP lifecycle and project extension command integration are now the clearest remaining feature groups to extract.

## 2026-06-24 Workspace MCP Integration Test Pass

Overall grade after this slice: **A feature grouping, A behavior preservation, A regression guard**.

MCP integration tests moved from the workspace-model monolith into `WorkspaceMCPIntegrationTests`. The model test file no longer owns MCP server lifecycle, Ready-server surface labels, dynamic MCP tool descriptions, tool/resource/prompt execution from agent turns, or unadvertised-tool rejection.

Code quality changes:

- Added `WorkspaceMCPIntegrationTests` as the home for MCP flows that cross workspace model, project extension manifests, MCP runtime, tool cards, transcript events, and surfaces.
- Moved the fixture MCP stdio server beside the MCP integration tests so the helper does not sit in the general model test file.
- Reused shared temp-directory support so moved tests clean up after themselves.
- Added a parity gate that keeps MCP integration method names out of `WorkspaceModelTests.swift`.
- Reduced `WorkspaceModelTests.swift` from roughly 5.0k lines to roughly 4.7k lines without weakening coverage.

Remaining risk:

- `WorkspaceModelTests.swift` is still the largest test file. Project extension command integration and older broad workspace flows are now the clearest remaining feature groups to extract.

## 2026-06-24 Workspace Project Integration Test Pass

Overall grade after this slice: **A feature grouping, A behavior preservation, A regression guard**.

Project instruction integration moved from the workspace-model monolith into `WorkspaceProjectIntegrationTests`. The model test file no longer owns project instruction loading into new threads or instruction refresh before agent submission.

Code quality changes:

- Added `WorkspaceProjectIntegrationTests` as the home for project instruction flows that cross workspace model, metadata loaders, thread context, agent submission, and surfaces.
- Reused shared temp-directory support so moved tests clean up after themselves.
- Added a parity gate that keeps project instruction integration method names out of `WorkspaceModelTests.swift`.
- Continued shrinking `WorkspaceModelTests.swift` without weakening coverage.

Remaining risk:

- `WorkspaceModelTests.swift` is still the largest test file. SSH Remote project integration, local environment integration, terminal integration, browser integration, review actions, and automation flows remain good candidates for focused extraction.

## 2026-06-24 Workspace Local Environment Integration Test Pass

Overall grade after this slice: **A feature grouping, A- duplication reduction, A regression guard**.

Local environment integration tests moved from the workspace-model monolith into `WorkspaceLocalEnvironmentIntegrationTests`. The moved tests now share a small setup helper and shell-result decoder instead of repeating project/action-directory setup and `ToolResult` decoding in each case.

Code quality changes:

- Added `WorkspaceLocalEnvironmentIntegrationTests` as the home for local environment flows that cross workspace model, metadata loading, command-palette execution, shell-call planning, tool cards, and slash transcripts.
- Removed command-palette execution, environment redaction, bounded working-directory, and timeout coverage from `WorkspaceModelTests.swift`; `/env` listing remains with the slash-command integration suite.
- Added a parity gate that keeps local environment integration method names out of `WorkspaceModelTests.swift`.
- Reused shared temp-directory support and local helper methods to make the extracted tests less repetitive than the original monolith section.

Remaining risk:

- `WorkspaceModelTests.swift` is still the largest test file. SSH Remote project integration, terminal integration, browser integration, review actions, and automation flows remain good candidates for focused extraction.

## 2026-06-24 Workspace Terminal Integration Test Pass

Overall grade after this slice: **A feature grouping, A behavior preservation, A regression guard**.

Local terminal integration tests moved from the workspace-model monolith into `WorkspaceTerminalIntegrationTests`. The moved tests cover behavior that crosses `WorkspaceModel`, `WorkspaceTerminalEngine`, shell execution, async task lifecycle, and the terminal surface, while the pure terminal reducer coverage remains in `WorkspaceTerminalEngineTests`.

Code quality changes:

- Added `WorkspaceTerminalIntegrationTests` as the home for local terminal execution, streaming output, cwd/environment persistence, clear-history behavior, selected-project resets, cancellation, and stop-all behavior.
- Removed the corresponding local terminal coverage from `WorkspaceModelTests.swift`.
- Reused shared temp-directory support so the extracted tests clean up after themselves.
- Added a parity gate that keeps local terminal integration method names out of `WorkspaceModelTests.swift`.
- Left SSH terminal integration in `WorkspaceModelTests.swift` for that slice because fake SSH support was still shared with the broader remote-project cluster; that follow-up is now complete in the SSH terminal extraction pass.

Remaining risk:

- `WorkspaceModelTests.swift` is still the largest test file. SSH Remote project integration, browser integration, review actions, and automation flows remain good candidates for focused extraction.
- Remote-project file/git/apply-patch flows remain broad, but terminal-specific SSH execution now lives with terminal integration coverage.

## 2026-06-24 Runtime Factory Test Ownership Pass

Overall grade after this slice: **A test ownership, A behavior preservation, A regression guard**.

Runtime factory tests were still embedded in `WorkspaceModelTests.swift` even though they exercised `QuillCodeRuntimeFactory` directly. This made the model test file look more responsible for auth/runtime construction than it really is. The factory tests now live in `WorkspaceRuntimeFactoryTests`, while `WorkspaceModelTests` keeps only model-facing runtime application and issue-surfacing coverage.

Code quality changes:

- Moved environment-key, stored-secret, deterministic mock override, and no-key model-catalog fallback tests into `WorkspaceRuntimeFactoryTests`.
- Reused the shared `makeQuillCodeTestDirectory()` helper so runtime factory tests clean up their temporary homes automatically.
- Added a parity gate that keeps direct `QuillCodeRuntimeFactory` construction out of `WorkspaceModelTests.swift`.

Remaining risk:

- `WorkspaceModelTests.swift` is still large because it contains broad integration coverage for remote projects, review actions, automations, terminal behavior, and composer runs. Continue moving feature-specific integration groups into focused files when the owning boundary is already extracted.

## 2026-06-24 Workspace Project Extension Integration Test Pass

Overall grade after this slice: **A feature grouping, A failure-path coverage, A regression guard**.

Project extension integration tests moved from `WorkspaceModelTests.swift` into `WorkspaceProjectExtensionIntegrationTests`. The model test file no longer owns project extension manifest loading into the workspace surface or extension update command execution.

Code quality changes:

- Added `WorkspaceProjectExtensionIntegrationTests` as the home for extension flows that cross manifest files, project metadata refresh, secondary-pane surfaces, command dispatch, tool execution, and transcript notices.
- Added explicit failure-path coverage for extension update commands so failed updates keep the manifest available and record a user-visible failure notice.
- Centralized repeated plugin manifest setup inside the focused integration test file.
- Added a parity gate that keeps project extension integration method names out of `WorkspaceModelTests.swift`.
- Reduced `WorkspaceModelTests.swift` without weakening project extension behavior coverage.

Remaining risk:

- `WorkspaceModelTests.swift` is still large. Older broad workspace flows around slash commands, automations, terminal behavior, and remote projects are now the clearest remaining extraction candidates.

## 2026-06-24 Workspace Slash Command Integration Test Pass

Overall grade after this slice: **A feature grouping, A behavior preservation, A regression guard**.

Core slash-command integration tests moved from `WorkspaceModelTests.swift` into `WorkspaceSlashCommandIntegrationTests`. The monolithic model test file no longer owns command-palette slash prefill, core slash dispatch, local environment slash execution, local mode/model/thread lifecycle slash commands, context compaction routing, or status transcript assertions.

Code quality changes:

- Added `WorkspaceSlashCommandIntegrationTests` as the home for slash flows that cross composer submission, workspace command dispatch, local environment action loading, workspace surfaces, tool-card output, and transcript creation.
- Centralized repeated local environment action setup in the focused test file.
- Kept pure slash transcript copy in `WorkspaceSlashCommandTranscriptPlannerTests`, preserving the split between copy planning and model-level side effects.
- Added a parity gate that keeps core slash integration method names out of `WorkspaceModelTests.swift`.
- Reduced `WorkspaceModelTests.swift` without weakening slash-command behavior coverage.

Remaining risk:

- Remote-project and automation-specific slash flows still live in `WorkspaceModelTests.swift` because they cross larger SSH and schedule orchestration boundaries. They are good candidates for future focused integration files once those ownership groups are split.

## 2026-06-24 Workspace Automation Integration Test Pass

Overall grade after this slice: **A feature grouping, A setup DRYness, A regression guard**.

Model-level automation integration tests moved from `WorkspaceModelTests.swift` into `WorkspaceAutomationIntegrationTests`. The model test file no longer owns automation persistence, create/pause/resume/delete command flows, scheduled and natural-language follow-ups/workspace checks, slash scheduling commands, due automation execution, recurrence advancement, or run reports.

Code quality changes:

- Added `WorkspaceAutomationIntegrationTests` for automation flows crossing stores, workspace model, command dispatch, surfaces, thread persistence, and transcripts.
- Centralized repeated automation workspace setup and common thread-follow-up automation construction.
- Kept pure reducer/factory tests in `WorkspaceAutomationEngineTests`.
- Added a parity gate that keeps model-level automation method names out of `WorkspaceModelTests.swift`.
- Reduced `WorkspaceModelTests.swift` substantially without weakening behavior coverage.

Remaining risk:

- `WorkspaceModelTests.swift` is still large. Remote project, review, browser, and composer integration groups remain future extraction candidates.

## 2026-06-24 Workspace Remote Project Integration Test Pass

Overall grade after this slice: **A feature grouping, A fixture ownership, A regression guard**.

SSH Remote project integration tests moved from `WorkspaceModelTests.swift` into `WorkspaceRemoteProjectIntegrationTests`. The model test file no longer owns SSH project setup, remote context refresh, remote-safe tool exposure, SSH-routed shell/file/git/GitHub/worktree agent execution, or remote path-safety flows.

Code quality changes:

- Added `WorkspaceRemoteProjectIntegrationTests` for remote flows crossing workspace model, SSH executor, tool cards, surfaces, transcript events, and fake GitHub CLI/SSH fixtures.
- Moved reusable fake SSH, executing SSH, fake GitHub CLI, git repository, and fixed/recording LLM helpers into `WorkspaceModelIntegrationTestSupport`.
- Kept low-level remote command builder and tool executor coverage in `WorkspaceRemoteProjectToolExecutorTests`.
- Added a parity gate that keeps remote project integration method names out of `WorkspaceModelTests.swift`.
- Reduced `WorkspaceModelTests.swift` again without weakening remote project behavior coverage.

Remaining risk:

- `WorkspaceModelTests.swift` is still large. Browser, review, and composer integration groups remain future extraction candidates.

## 2026-06-24 Workspace Integration Fixture Hardening

Overall grade after this slice: **A shared fixture hygiene, A reviewability, A concurrency discipline**.

The remote integration split made `WorkspaceModelIntegrationTestSupport` a shared test boundary for remote, git, GitHub CLI, and fixed-LLM flows. The fixture layer now needs the same care as production support code because many future Codex-parity slices will build on it.

Code quality changes:

- Centralized shell single-quote escaping for fake SSH and fake GitHub CLI scripts so path quoting does not drift between fixtures.
- Made fixed/recording LLM test doubles explicitly ignore unused parameters, keeping their behavior clear at call sites.
- Changed the recording LLM lock release to `defer`, matching the rest of the codebase's lock discipline and avoiding future early-return hazards.

Remaining risk:

- `WorkspaceModelIntegrationTestSupport` is now a useful common fixture boundary, but it should not grow into a second monolith. Future broad fixtures should move into domain-specific support files once two or more focused integration files need them.

## 2026-06-24 Workspace Browser Integration Test Pass

Overall grade after this slice: **A feature grouping, A behavior preservation, A regression guard**.

Browser integration tests moved from `WorkspaceModelTests.swift` into `WorkspaceBrowserIntegrationTests`. The model test file no longer owns browser preview normalization, local HTML snapshots, fetched web snapshots, browser comments, history/reload behavior, invalid-address errors, or composer-driven browser inspection flows.

Code quality changes:

- Added `WorkspaceBrowserIntegrationTests` for browser flows crossing workspace model, browser state, static/fetched page snapshots, comments, tool cards, and transcript messages.
- Moved the fake browser page fetcher into the focused integration suite that uses it.
- Kept pure browser reducer/location/surface coverage in `WorkspaceBrowserEngineTests`, `WorkspaceBrowserLocationResolverTests`, and `QuillCodeBrowserSurfaceTests`.
- Added a parity gate that keeps model-level browser integration method names out of `WorkspaceModelTests.swift`.
- Reduced `WorkspaceModelTests.swift` without weakening browser behavior coverage.

Remaining risk:

- `WorkspaceModelTests.swift` is still large. Review actions, composer send/cancel flows, bootstrap/config, and project/worktree command groups remain future extraction candidates.

## 2026-06-24 Workspace Browser Guardrail Hardening

Overall grade after this slice: **A+ test safety discipline, A+ ownership guard completeness**.

The browser integration split was merged, but two small quality gaps remained: one moved test still used a force unwrap for a static URL, and the parity gate checked only the broadest browser flows. This pass tightens both.

Code quality changes:

- Replaced the browser fetch test's force-unwrapped URL with `XCTUnwrap`, keeping the integration suite aligned with the production-source crash-avoidance standard.
- Expanded the browser ownership parity gate to cover history navigation and fetch-failure fallback tests, not only preview/comment/fetch/composer inspection flows.
- Updated the decision note so the guarded browser integration boundary is explicit about URL normalization, history, page comments, fetch fallback, and composer-driven inspection.

Remaining risk:

- Later passes moved review, composer/tool-card, runtime, and project lifecycle flows into focused suites. Remaining model coverage should keep shrinking around approval-card behavior, bootstrap/config, model settings, and plan-update integration.

## 2026-06-24 Workspace Review Integration Test Pass

Overall grade after this slice: **A feature grouping, A fixture DRYness, A regression guard**.

Review and diff integration tests moved from `WorkspaceModelTests.swift` into `WorkspaceReviewIntegrationTests`. The model test file no longer owns apply-patch review refresh, local/SSH Remote review stage and restore actions, hunk staging, or review comment event/surface integration.

Code quality changes:

- Added `WorkspaceReviewIntegrationTests` for review flows crossing workspace model, git tools, SSH Remote execution, tool cards, review surfaces, and transcript events.
- Centralized repeated local and SSH Remote git-review fixture setup inside the focused review suite.
- Kept pure review comment planning and lower-level git command construction in their existing focused unit tests.
- Added a parity gate that keeps model-level review integration method names out of `WorkspaceModelTests.swift`.
- Reduced `WorkspaceModelTests.swift` without weakening review behavior coverage.

Remaining risk:

- `WorkspaceModelTests.swift` is still large. Composer send/cancel flows, bootstrap/config, project/worktree command groups, and approval-card behavior remain future extraction candidates.

## 2026-06-24 Workspace Composer Integration Test Pass

Overall grade after this slice: **A feature grouping, A async-fixture ownership, A regression guard**.

Composer send/cancel integration tests moved from `WorkspaceModelTests.swift` into `WorkspaceComposerIntegrationTests`. The model test file no longer owns direct composer submit behavior, tool-card creation, tool artifact surfacing, Computer Use dispatch, queued-tool progress, streaming assistant drafts, cancellation notice routing, empty-draft no-ops, or selection-race behavior.

Code quality changes:

- Added `WorkspaceComposerIntegrationTests` for composer flows crossing workspace model, agent runner, safety review delay, Computer Use backend, tool cards, transcript events, artifacts, and top-bar status.
- Moved composer-only async wait helpers and streaming/slow LLM doubles beside the focused suite that uses them.
- Kept pure composer submission and cancellation planning in `WorkspaceComposerSubmissionPlannerTests` and `WorkspaceComposerCancellationPlannerTests`.
- Added a parity gate that keeps model-level composer integration method names out of `WorkspaceModelTests.swift`.
- Reduced `WorkspaceModelTests.swift` again without weakening composer behavior coverage.

Remaining risk:

- `WorkspaceModelTests.swift` is still large. Bootstrap/config, project/worktree command groups, approval-card behavior, feedback, and artifact-state coverage remain future extraction candidates.

## 2026-06-24 Feedback And Artifact Surface Test Pass

Overall grade after this slice: **A focused ownership, A+ surface isolation, A regression guard**.

Message feedback and artifact preview derivation coverage moved out of `WorkspaceModelTests.swift`. Feedback persistence remains model-level integration coverage in `WorkspaceFeedbackIntegrationTests`, while pure `ToolArtifactState` image/document preview derivation now lives in `QuillCodeToolCardSurfaceTests`.

Code quality changes:

- Added `WorkspaceFeedbackIntegrationTests` for `setMessageFeedback` flows that cross workspace model state, thread events, and transcript surfaces.
- Added `QuillCodeToolCardSurfaceTests` for artifact value-type behavior: file/URL/data image previews, document/appshot previews, text-preview handling, hrefs, labels, and details.
- Added a parity gate that keeps message feedback and artifact preview method names out of `WorkspaceModelTests.swift`.
- Reduced `WorkspaceModelTests.swift` again without changing product behavior.

Remaining risk:

- `WorkspaceModelTests.swift` is still large. Bootstrap/config, project/worktree command groups, approval-card behavior, runtime issue recovery, and thread lifecycle coverage remain future extraction candidates.

## 2026-06-24 Workspace Runtime Issue Integration Test Pass

Overall grade after this slice: **A boundary clarity, A dependency ownership, A+ regression guard**.

Runtime issue and retry recovery coverage moved from `WorkspaceModelTests.swift` into `WorkspaceRuntimeIssueIntegrationTests`. Pure runtime issue construction and recovery-action mapping remain in their focused builder/planner tests.

Code quality changes:

- Added `WorkspaceRuntimeIssueIntegrationTests` for flows crossing workspace runtime state, top-bar/settings surfaces, diagnostics, and retry composer mutation.
- Kept `QuillCodeAgent` in `WorkspaceModelTests.swift` because that suite still exercises model-catalog favorites through `TrustedRouterModelCatalog`; the runtime-specific `AgentRunner` dependency moved to the focused suite.
- Added a parity gate that keeps runtime status, issue surfacing, diagnostic redaction, and retry recovery method names out of `WorkspaceModelTests.swift`.
- Reduced `WorkspaceModelTests.swift` from 1,160 lines to 1,005 lines without changing runtime behavior.

Remaining risk:

- `WorkspaceModelTests.swift` is still large. Bootstrap/config, project/worktree command groups, approval-card behavior, and thread lifecycle coverage remain future extraction candidates.

## 2026-06-24 Workspace Thread Lifecycle Integration Test Pass

Overall grade after this slice: **A+ test ownership, A lifecycle boundary, A+ regression guard**.

Thread lifecycle and bounded-context coverage moved from `WorkspaceModelTests.swift` into `WorkspaceThreadLifecycleIntegrationTests`. Pure lifecycle mutation rules remain in `WorkspaceThreadLifecycleEngineTests`, while model/store/sidebar/top-bar interactions stay in the focused integration suite.

Code quality changes:

- Added `WorkspaceThreadLifecycleIntegrationTests` for new chat selection, unknown-project fallback, fork-from-last, compact-context, newest-project-thread selection, pinned ordering, archive fallback selection, persistence, rename, duplicate, unarchive, and delete flows.
- Removed those lifecycle cases from `WorkspaceModelTests.swift`, reducing it from 1,005 lines to 742 lines.
- Added a parity gate that keeps lifecycle integration method names out of `WorkspaceModelTests.swift`.
- Preserved the existing pure engine tests for lifecycle reducers instead of duplicating mutation-rule coverage.

Remaining risk:

- `WorkspaceModelTests.swift` is still broad. Bootstrap/config, project/worktree command groups, approval-card behavior, and plan-update tool coverage remain future extraction candidates.

## 2026-06-24 Workspace Pull Request Integration Test Pass

Overall grade after this slice: **A+ PR workflow ownership, A command boundary, A+ regression guard**.

Pull request command coverage moved from `WorkspaceModelTests.swift` into `WorkspacePullRequestIntegrationTests`. Tool-level GitHub CLI argument construction remains in `ToolTests`, and remote command construction remains in focused remote git builders; this suite owns only workspace command/slash integration through SSH and composer prefill behavior.

Code quality changes:

- Added `WorkspacePullRequestIntegrationTests` for remote PR view/checks/diff execution through SSH, slash `/pr` command dispatch, and PR command composer prefills.
- Removed those PR cases from `WorkspaceModelTests.swift`, reducing it from 598 lines to 442 lines.
- Added a parity gate that keeps PR integration method names out of `WorkspaceModelTests.swift`.
- Preserved existing tool-level PR executor/parser tests instead of duplicating GitHub CLI argument construction coverage.

Remaining risk:

- `WorkspaceModelTests.swift` still owns approval-card behavior, bootstrap/config, model settings, and plan-update integration coverage.

## 2026-06-24 Workspace Project Lifecycle Integration Test Pass

Overall grade after this slice: **A+ project ownership, A command boundary, A+ regression guard**.

Project selection and lifecycle command coverage moved from `WorkspaceModelTests.swift` into `WorkspaceProjectIntegrationTests`. Project integration now owns selection, next-chat workspace context, rename, refresh, project-new-chat, project-remove, and instruction snapshotting flows.

Code quality changes:

- Moved `testSelectingProjectControlsNextChatAndWorkspaceRoot` and `testProjectLifecycleActionsRenameRefreshNewChatAndRemove` into `WorkspaceProjectIntegrationTests`.
- Expanded the project parity gate to keep project selection and lifecycle method names out of `WorkspaceModelTests.swift`.
- Updated the project integration decision to describe lifecycle and command ownership, not only instruction loading.
- Reduced `WorkspaceModelTests.swift` from 363 lines to 317 lines.

Remaining risk:

- `WorkspaceModelTests.swift` still owns approval-card behavior, bootstrap/config, model settings, and plan-update integration coverage.

## 2026-06-24 SSH Terminal Integration Test Pass

Overall grade after this slice: **A+ terminal ownership, A+ remote execution boundary, A regression guard**.

SSH Remote terminal execution moved from `WorkspaceModelTests.swift` into `WorkspaceTerminalIntegrationTests`. Terminal coverage now owns both local and SSH execution paths, including remote cwd/environment persistence, while remote-project file/git/apply-patch flows remain in their own integration suite.

Code quality changes:

- Moved `testTerminalCommandRunsThroughSSHRemoteProject` and `testTerminalCommandPersistsSSHRemoteCWDAndEnvironment` into `WorkspaceTerminalIntegrationTests`.
- Added explicit terminal-suite imports for `QuillCodeCore` and `QuillCodeTools` so the moved SSH setup dependencies are visible at the feature boundary.
- Expanded the terminal parity gate to keep SSH Remote terminal integration method names out of `WorkspaceModelTests.swift`.
- Reduced `WorkspaceModelTests.swift` from 442 lines to 363 lines.

Remaining risk:

- `WorkspaceModelTests.swift` still owns approval-card behavior, bootstrap/config, model settings, and plan-update integration coverage.

## 2026-06-24 Workspace Activity Surface Architecture Pass

Overall grade after this slice: **A surface payload, A builder ownership, A+ regression guard**.

`WorkspaceActivitySurface.swift` was a 686-line mixed ownership file: the public activity payload, section/item DTOs, event/tool/source/artifact derivation, fallback plan construction, authored-plan projection, and handoff summary copy all lived together. It now keeps only the Codable root payload and delegates derivation to focused helpers.

Code quality changes:

- Added `WorkspaceActivitySurfaceBuilder` for subtitle, task title, recent steps, source rows, tool rows, artifact de-duplication, fallback/authored plan rows, handoff summary copy, and section assembly.
- Added `WorkspaceActivitySectionSurface.swift` for `ActivitySectionKind`, `ActivitySectionSurface`, and `ActivityItemSurface` so shared section contracts evolve independently from root-payload decoding.
- Reduced `WorkspaceActivitySurface.swift` from 686 lines to 165 lines without changing the public surface contract.
- Added a parity gate that keeps activity derivation and section DTO ownership out of the root surface file.

Remaining risk:

- Activity derivation now has a clean intermediate builder boundary. Split plan, event/source, and handoff ownership before adding richer Codex activity features.

## 2026-06-24 Activity Derivation Builder Split

Overall grade after this slice: **A activity composition, A focused derivation builders, A+ ownership guard**.

`WorkspaceActivitySurfaceBuilder.swift` had become the new 380+ line activity hotspot after the root payload split. It composed sections, formatted shared labels, projected thread events, projected source rows, built fallback and model-authored plans, and authored handoff-summary copy in one file. That was still correct behaviorally, but it made future Codex activity features likely to pile into the same file.

Code quality changes:

- Added `WorkspaceActivityPlanSurfaceBuilder` for fallback task-plan rows, model-authored plan rows, tool aggregate status, and review-state copy.
- Added `WorkspaceActivityEventSurfaceBuilder` for recent event rows plus event labels/status labels.
- Added `WorkspaceActivitySourceSurfaceBuilder` for instruction and memory source rows.
- Added `WorkspaceActivityHandoffSummaryBuilder` for handoff copy and summary construction.
- Added `WorkspaceActivityText` and `WorkspaceActivityStatusLabel` so shared row text/status formatting is reused instead of copied.
- Kept `WorkspaceActivitySurfaceBuilder` as a 149-line composition layer for subtitle/task-title, tool rows, artifact de-duplication, section assembly, and delegation.
- Expanded the parity gate so plan/event/source/handoff derivation cannot drift back into the root surface or top-level composition builder.

Validation:

- `swift test --filter WorkspaceSurfaceTests/testActivitySurface`

Remaining risk:

- Tool-row projection and artifact de-duplication still live in `WorkspaceActivitySurfaceBuilder`; if tool/activity metadata grows, split a small `WorkspaceActivityToolSurfaceBuilder`.

## 2026-06-24 Tool Artifact Surface Architecture Pass

Overall grade after this slice: **A card payload, A artifact ownership, A+ regression guard**.

`QuillCodeToolCardSurface.swift` mixed two contracts: card status/action/review state and artifact classification/preview derivation. The artifact contract now lives in its own focused file so card behavior can evolve without pulling URL/file/image/document/text-preview parsing along with it.

Code quality changes:

- Added `QuillCodeToolArtifactSurface.swift` for `ToolArtifactKind`, document/image preview contracts, and `ToolArtifactState`.
- Reduced `QuillCodeToolCardSurface.swift` to card-level state: status, review state, action surfaces, density defaults, and card-level artifact grouping.
- Updated the parity gate so artifact preview construction stays with artifact state, while `WorkspaceModel` and card state stay out of artifact parsing.

Remaining risk:

- Resolved in the artifact preview helper split below.

## 2026-06-24 Tool Artifact Preview Helper Split

Overall grade after this slice: **A+ artifact state focus, A+ preview helper ownership, A+ regression guard**.

`QuillCodeToolArtifactSurface.swift` kept the right public surface contracts, but it still owned value classification, image preview classification, document kind mapping, inline-image subtype normalization, href/detail derivation, and text-preview file IO. That made the artifact DTO file algorithm-heavy and likely to grow when adding richer artifact formats.

Code quality changes:

- Added `ToolArtifactValueClassifier` for kind, label, detail, href, path-extension, and inline-image data detection.
- Added `ToolArtifactImagePreviewBuilder` for image preview eligibility, preview URLs, image preview metadata, and image extension normalization.
- Added `ToolArtifactDocumentPreviewBuilder` for document/appshot extension mapping and document preview metadata.
- Added `ToolArtifactTextPreviewBuilder` for local text-file preview IO, text candidate filtering, truncation, and binary-file rejection.
- Reduced `QuillCodeToolArtifactSurface.swift` to the public artifact enums/preview DTOs plus `ToolArtifactState` delegation.
- Updated transcript projection to request text previews through `ToolArtifactTextPreviewBuilder`.
- Expanded focused tests for local text previews, file URLs, appshot exclusion, binary rejection, and remote URL exclusion.
- Expanded the parity gate so artifact state cannot regain image/document/text-preview algorithms and `WorkspaceModel` stays out of preview requests.

Validation:

- `swift test --filter QuillCodeToolCardSurfaceTests`
- `swift test --filter ParityGateTests/testWorkspaceModelDelegatesToolCardSurfaceTypes`

Remaining risk:

- Artifact preview helpers now have clear seams for richer formats. If PDF/appshot rendering becomes asynchronous, add a preview metadata service rather than making `ToolArtifactState` perform IO.

## 2026-06-24 Workspace Command Surface Catalog Pass

Overall grade after this slice: **A+ command composition, A+ family ownership, A+ regression guard**.

`WorkspaceCommandSurfaceBuilder.swift` was still a 597-line mixed catalog after earlier extraction from `WorkspaceSurface`: it composed command rows, owned static thread/navigation/workspace/git/control rows, and also derived project-specific rows for local actions, MCP lifecycle, and extension updates. The builder now acts as a composition layer and each command family owns its own rows and availability contract.

Code quality changes:

- Reduced `WorkspaceCommandSurfaceBuilder.swift` to a 107-line composer that derives selected context and calls focused command catalogs.
- Added `WorkspaceThreadCommandCatalog` and `WorkspaceThreadCommandAvailability` so thread/sidebar command enablement is a value boundary instead of scattered booleans.
- Added `WorkspaceGitCommandCatalog` for Git, PR, and worktree command rows.
- Added `WorkspaceProjectCommandCatalog` for project-derived local action, MCP lifecycle, and extension update rows plus their keyword derivation.
- Kept navigation/workspace/automation/memory/control/Computer Use rows in `WorkspaceCommandStaticCatalog`, which has no selected project or thread model dependency.
- Expanded the parity gate so new command families stay out of the aggregate workspace surface and out of the command builder.

Remaining risk:

- `WorkspaceCommandStaticCatalog.swift` is intentionally a small static catalog. If Browser, Automations, or Computer Use command sets grow richer, split those families into their own catalogs before adding runtime-specific branching there.

## 2026-06-24 Native Secondary Pane View Split

Overall grade after this slice: **A+ native pane ownership, A shared chrome, A+ regression guard**.

`QuillCodeSecondaryPanesView.swift` had grown into a 590-line mixed native UI file containing Extensions, Memories, Automations, shared count pills, empty states, MCP probe metadata, memory cards, and automation action routing. It now owns only shared secondary-pane chrome, while each pane family has a focused SwiftUI file.

Code quality changes:

- Added `QuillCodeExtensionsPaneView.swift` for Extensions cards, MCP probe metadata chips, status coloring, and extension lifecycle command routing.
- Added `QuillCodeMemoriesPaneView.swift` for memory counts, memory cards, and forget/add command routing.
- Added `QuillCodeAutomationsPaneView.swift` for automation status, create menu routing, workflow cards, and row actions.
- Reduced `QuillCodeSecondaryPanesView.swift` from 590 lines to shared count-pill and empty-state primitives only.
- Added a parity gate so native secondary panes remain focused files and the workspace shell remains a placement/router layer.

Remaining risk:

- `QuillCodeExtensionsPaneView.swift` is still the richest secondary pane because MCP probe metadata is visually dense. If MCP resource, prompt, or per-tool schema display grows further, split the probe metadata groups into a dedicated `QuillCodeExtensionProbeMetadataView`.

## 2026-06-24 Terminal State Contract Split

Overall grade after this slice: **A terminal contracts, A engine ownership, A+ regression guard**.

`WorkspaceTerminalEngine.swift` mixed terminal DTO contracts with lifecycle reducers, local shell wrapping, SSH Remote shell wrapping, cwd/environment marker parsing, and marker cleanup. The engine remains the behavior owner, but terminal state and session payload records now live in a focused contract file.

Code quality changes:

- Added `WorkspaceTerminalState.swift` for `TerminalCommandState`, `TerminalCommandStatus`, `TerminalState`, terminal execution context, session result, and environment delta records.
- Reduced `WorkspaceTerminalEngine.swift` so it starts directly with terminal lifecycle behavior instead of public DTO definitions.
- Updated the terminal decision record to distinguish state contracts from engine behavior.
- Added a parity gate that keeps terminal DTO definitions out of the engine while verifying shell wrapping stays there.

Remaining risk:

- Resolved in the terminal session adapter split below.

## 2026-06-24 Slash Command Catalog Split

Overall grade after this slice: **A slash catalog ownership, A parser focus, A+ regression guard**.

`SlashCommand.swift` mixed slash command metadata, command-palette insertion rows, suggestion ranking, help text, parser control flow, and structured tool-call construction. The parser now keeps command interpretation and tool-call payload construction, while discovery metadata and suggestion scoring live in a focused catalog file.

Code quality changes:

- Added `SlashCommandCatalog.swift` for `SlashCommandSuggestionSurface`, `SlashCommandDefinition`, slash definitions, `/help` text, command-palette template rows, insertion lookup, and suggestion ranking.
- Reduced `SlashCommand.swift` from 517 lines to parser and tool-call construction logic.
- Updated the slash discovery decision to call out catalog-vs-parser ownership.
- Added a parity gate that keeps slash metadata and ranking out of parser control flow.

Remaining risk:

- `SlashCommand.swift` still owns PR slash parsing and tool-call argument mapping. If pull request slash coverage grows further, split `/pr` parsing into a `SlashPullRequestCommandParser` while keeping shared `ToolArguments` serialization in core.

## 2026-06-24 Mock Pull Request Intent Planner Split

Overall grade after this slice: **A+ mock planner boundaries, A+ PR behavior guard, A helper reuse**.

`MockLLMClient.swift` still carried the deterministic PR intent classifier and argument extraction for create/view/checks/diff/checkout/comment/review/reviewer/label/merge requests. That kept smoke-test behavior correct, but it made the mock LLM file a broad command-heuristic bucket after the earlier extraction from `Agent.swift`. PR-specific mock planning now has one routing entrypoint back into the mock LLM, and argument extraction is separated from intent matching.

Code quality changes:

- Added `MockPullRequestIntentPlanner.swift` for PR request detection and PR `ToolCall` routing.
- Added `MockPullRequestArgumentExtractor.swift` for selector/title/body/reviewer/label parsing and merge/review/create argument mapping.
- Reduced `MockLLMClient.swift` to high-level deterministic planning while preserving the same public mock client API.
- Consolidated repeated PR helper logic inside the extracted PR helpers for tokenization, marker lookup, and backtick-quoted text extraction.
- Updated the parity gate so mock PR parsing cannot drift back into `MockLLMClient.swift` or `Agent.swift`, and so argument construction cannot drift into the PR intent router.

Remaining risk:

- `MockLLMClient.swift` still owns mixed non-PR heuristics for shell, file, memory, browser, git status/diff, commit, and push requests. The next mock-quality pass should split non-PR command intent into a `MockWorkspaceIntentPlanner` only if new mock flows make this file grow again.

## 2026-06-24 Terminal Session Adapter Split

Overall grade after this slice: **A+ terminal lifecycle boundary, A+ transport adapter ownership, A+ regression guard**.

`WorkspaceTerminalEngine.swift` still owned local shell wrapping, SSH Remote command wrapping, environment preambles, shell quoting, cwd/environment marker decoding, and marker cleanup after the state-contract split. That made the lifecycle reducer the likely landing zone for future relay transport behavior. The terminal engine now handles only terminal state transitions and delegates all command-session formatting and marker parsing to a focused adapter.

Code quality changes:

- Added `WorkspaceTerminalSessionAdapter.swift` for local execution context creation, SSH Remote connection path recovery, remote command wrapping, environment preambles, marker parsing, environment deltas, marker cleanup, and shared shell quoting.
- Reduced `WorkspaceTerminalEngine.swift` from 589 lines before the terminal refactor series to 268 lines focused on input normalization, run lifecycle, streaming events, cancellation, completion, and selected-project session sync.
- Moved adapter-specific tests into `WorkspaceTerminalSessionAdapterTests.swift` while keeping pure lifecycle coverage in `WorkspaceTerminalEngineTests.swift`.
- Updated remote Git and remote project command builders to use the shared adapter quoting helper instead of reaching back into the engine.
- Expanded the parity gate so local/remote shell wrapping and marker parsing cannot drift back into `WorkspaceTerminalEngine.swift`.

Remaining risk:

- `WorkspaceTerminalSessionAdapter.swift` still supports both local and SSH Remote transport in one file. If QuillCloud relay terminal execution adds distinct framing, split transport-specific implementations behind a small protocol while keeping `WorkspaceTerminalEngine` unchanged.

## 2026-06-24 MCP Stdio Codec And Result Mapper Split

Overall grade after this slice: **A+ MCP stdio prober focus, A+ codec boundary, A result mapping ownership**.

`MCPStdioProber.swift` owned session request/response orchestration, Content-Length frame parsing, tool schema summarization, resource and prompt list extraction, JSON argument parsing, and `ToolResult` conversion. The class was correct and well tested, but it made future MCP growth likely to pile protocol-framing and presentation mapping into the same file as locked stdio IO.

Code quality changes:

- Added `MCPStdioMessageCodec.swift` as the focused public owner for MCP Content-Length message encoding, incremental frame parsing, and JSON-object decoding.
- Added `MCPStdioResultMapper.swift` for tool descriptor/schema summaries, resource and prompt list flattening, JSON argument parsing, and tool/resource/prompt `ToolResult` conversion.
- Reduced `MCPStdioProber.swift` from 648 lines to 362 lines focused on locked request IDs, initialize/list/call/read/get flows, response matching, errors, and fd polling.
- Added a parity gate so frame parsing, schema summary generation, `ToolResult` conversion, and prompt content flattening stay out of the prober.

Remaining risk:

- `MCPStdioProber.swift` still includes public probe DTOs and MCP `ToolDefinition` declarations. If MCP model or tool-definition coverage grows, split those into `MCPStdioModels.swift` and `MCPToolDefinitions.swift` without changing the prober API.

## 2026-06-24 Terminal Session Adapter Edge Hardening

Overall grade after this slice: **A+ adapter behavior guard, A+ malformed marker coverage, A parity enforcement**.

After the terminal adapter split, the remaining quality risk was malformed SSH Remote marker envelopes: missing environment sections, unrelated marker text, or invalid hex payloads should fail closed without corrupting visible terminal output or session environment. The adapter now has explicit tests for these cases.

Code quality changes:

- Added adapter tests for remote output that has cwd metadata but no environment markers.
- Added adapter tests that reject unknown remote marker names instead of stripping unrelated output.
- Added adapter tests that reject malformed environment hex by withholding the environment delta.
- Tightened the parity gate to verify session result parsing, remote marker parsing, remote environment deltas, and environment hex decoding stay in `WorkspaceTerminalSessionAdapter`.

Remaining risk:

- Relay terminal execution should reuse this adapter contract or split behind a transport protocol; it should not reintroduce marker parsing into `WorkspaceTerminalEngine`.

## 2026-06-24 MCP Stdio Public Contracts Split

Overall grade after this slice: **A+ MCP stdio prober focus, A+ public MCP contract ownership, A+ parity guard coverage**.

The previous MCP pass removed framing and result mapping from `MCPStdioProber.swift`, but the file still owned public probe DTOs, probe errors, and static MCP `ToolDefinition` factories. That made the stdio session coordinator the easiest place to add unrelated public contract surface.

Code quality changes:

- Added `MCPStdioModels.swift` as the public owner for `MCPServerProbeResult`, `MCPToolDescriptor`, and `MCPProbeError`.
- Added `MCPToolDefinitions.swift` as the public owner for `ToolDefinition.mcpCall`, `ToolDefinition.mcpReadResource`, and `ToolDefinition.mcpGetPrompt`.
- Reduced `MCPStdioProber.swift` to locked request IDs, initialize/list/call/read/get flows, response matching, errors surfaced from the shared model file, and fd polling.
- Extended the parity gate so public MCP models and static MCP tool definitions cannot drift back into the prober.

Remaining risk:

- The MCP prober still handles optional `resources/list` and `prompts/list` retries inline. That is acceptable while probe behavior is simple; if MCP capability probing grows pagination, caching, or partial-failure reporting, move optional list orchestration into a small capability collector.

## 2026-06-24 Sidebar Thread List Builder Split

Overall grade after this slice: **A+ sidebar DTO focus, A+ shared list derivation, A regression guard**.

`QuillCodeSidebarSurface.swift` still owned both stable sidebar DTO contracts and the derived behavior for search filtering, pinned/recent/archived partitioning, and relative date bucket sectioning. That behavior is shared by native SwiftUI, static HTML, and search dialogs, so it should be easy to test without making the DTO file the landing zone for future sidebar algorithms.

Code quality changes:

- Added `QuillCodeSidebarThreadListBuilder.swift` for query filtering, pinned/recent/archived lists, recent date bucket grouping, and newest-first row sorting inside each bucket.
- Kept the public `SidebarSurface.filteredItems`, `pinnedItems`, `recentItems`, `recentSections`, and `archivedItems` API stable by delegating to the builder.
- Removed `SidebarThreadDateBucket` from the aggregate sidebar surface file.
- Added a parity gate so list derivation and date bucketing cannot drift back into `QuillCodeSidebarSurface.swift`.

Remaining risk:

- `QuillCodeSidebarView.swift` still builds bulk-action `WorkspaceCommandSurface` values in two local helpers. That duplication is small, but the next sidebar UI pass should extract a tiny command adapter before adding more selection actions.

## 2026-06-24 Sidebar Command Adapter Split

Overall grade after this slice: **A+ command payload consistency, A+ view simplicity, A regression guard**.

`QuillCodeSidebarView.swift` built equivalent `WorkspaceCommandSurface` values in multiple local helpers: one for the thread header select/done button, one for the horizontal bulk-action toolbar, and an inline selection-toggle command in row rendering. The behavior was correct, but the view file was starting to own command payload details that belong to the workspace-command boundary.

Code quality changes:

- Added `QuillCodeSidebarCommandAdapter.swift` for sidebar bulk-action commands and row selection-toggle commands.
- Removed duplicate `command(for:)` helpers from `QuillCodeSidebarView.swift`.
- Moved row selection-toggle command construction out of the view row body.
- Added direct adapter tests and parity coverage preventing inline `WorkspaceCommandSurface` construction from drifting back into the native sidebar view.

Remaining risk:

- Project row menu actions still route directly through typed row actions, which is appropriate for now because they do not need command-palette payloads. Revisit only if project row actions become workspace commands.

## 2026-06-24 Project Context Refresh Split

Overall grade after this slice: **A+ context refresh boundary, A thread-context sync guard, A metadata loading ownership**.

`WorkspaceModel.swift` still owned local metadata reloads, remote metadata reloads, global memory reloads, and repeated instruction/memory snapshot assignment for selected threads. The behavior was correct, but the model was becoming the implicit owner of project context refresh policy.

Code quality changes:

- Added `WorkspaceProjectContextRefresher` for local project metadata refresh, SSH Remote project context refresh, global-memory reloads, and thread context snapshots.
- Added `WorkspaceThreadContextSnapshot` so instruction/memory refresh has a named value boundary instead of repeated local variables.
- Updated `WorkspaceModel` to delegate refresh and thread sync while keeping orchestration, persistence, and top-bar status updates in the model.
- Added focused tests for local project/global memory reloads, project plus global memory merge order, thread-project precedence over fallback project, and memory-only refresh.
- Added a parity gate so metadata loaders, global-memory loads, and direct thread instruction/memory sync do not drift back into `WorkspaceModel`.

Remaining risk:

- `WorkspaceModel` still calls context snapshots for new threads, worktrees, automations, and status copy. Those reads are acceptable because they assemble different workflows; if those workflows start mutating project context directly, move them through this refresher instead of adding more inline refresh logic.

## 2026-06-24 Context Snapshot Call-Site Pass

Overall grade after this slice: **A+ snapshot ownership, A+ model boundary, A parity guard coverage**.

After the project context refresher split, `WorkspaceModel.swift` still read instruction and memory snapshots directly from `WorkspaceContextResolver` in several workflow-specific call sites: new chat creation, workspace automations, project refresh notices, worktree opening, status copy, and memory mutation follow-up. Those reads were correct, but they kept the model coupled to resolver details and made future context policy changes harder to audit.

Code quality changes:

- Added `WorkspaceProjectContextRefresher.threadCreationContext` and `worktreeOpenContext` so thread and worktree builders receive typed contexts from the same snapshot owner.
- Reduced `WorkspaceModel` to a single `workspaceThreadContext(_:)` wrapper for instruction/memory snapshots.
- Kept `WorkspaceModel` using `WorkspaceContextResolver` only for local environment action lookup, where the resolver is still the correct owner.
- Added focused tests proving thread creation and worktree opening use the same merged global/project memory snapshot.
- Tightened the parity gate so direct `contextResolver.instructions(for:)` and `contextResolver.memoryNotes(for:)` reads cannot drift back into `WorkspaceModel`.

Remaining risk:

- `WorkspaceProjectContextRefresher` now creates both thread and worktree contexts. If automation context assembly gains extra fields beyond instructions and memories, add an automation-specific typed context there instead of reintroducing resolver reads in `WorkspaceModel`.

## 2026-06-24 Command Palette Ranker Split

Overall grade after this slice: **A+ command search boundary, A+ query-scope coverage, A regression guard coverage**.

`WorkspaceCommandPaletteSurface.swift` still owned stable command DTOs, top-bar overflow projections, public palette API constants, and all search/ranking internals. The behavior was correct, but the file mixed durable surface records with ranking policy, tokenization, slash/action query scoping, and category tie-breaking.

Code quality changes:

- Added `WorkspaceCommandPaletteRanker` for command search, scoring, query normalization, slash/action scoping, grouping, and category ordering.
- Kept the public `WorkspaceCommandPalette.rankedCommands` and `groupedCommands` API stable by delegating to the ranker.
- Added focused ranker tests for shortcuts, multi-token PR queries, slash-only scope, action-only scope, mixed-scope slash inclusion, category grouping, and public API delegation.
- Tightened the parity gate so scoring and `QueryRequest` cannot drift back into `WorkspaceCommandPaletteSurface.swift`.

Remaining risk:

- Ranking weights are intentionally simple integer heuristics. If command count or plugin command volume grows enough to need fuzzier ranking, keep that policy inside `WorkspaceCommandPaletteRanker` rather than expanding the command surface DTO file.

## 2026-06-24 Extension Manifest Surface Row Split

Overall grade after this slice: **A+ extension row ownership, A+ compatibility coverage, A secondary-pane focus**.

`QuillCodeSecondaryPaneSurface.swift` still owned aggregate secondary-pane surfaces plus the full extension-manifest row contract. The row type has MCP probe metadata, launch/update action derivation, disabled/missing-command status policy, and custom decoding for older payloads, so keeping it inside the aggregate pane file made that file a landing zone for extension-specific changes.

Code quality changes:

- Added `ProjectExtensionManifestSurface.swift` as the focused owner for extension row projection, MCP probe display compatibility, and row decode compatibility.
- Kept `WorkspaceExtensionsSurface` unchanged as the aggregate pane contract and delegated row mapping to `ProjectExtensionManifestSurface`.
- Moved older payload decode coverage out of the broad `WorkspaceSurfaceTests` file into focused extension-row tests.
- Added direct tests for MCP row metadata/action derivation and disabled/missing-command start-action suppression.
- Tightened the parity gate so extension row internals cannot drift back into `QuillCodeSecondaryPaneSurface.swift`.

Remaining risk:

- `QuillCodeSecondaryPaneSurface.swift` still owns memory-note and automation-workflow rows. Those are acceptable while small, but if either gains custom compatibility decoding or richer action policy, split it into the same row-contract pattern.

## 2026-06-24 Memory And Automation Row Surface Split

Overall grade after this slice: **A+ secondary pane row ownership, A aggregate secondary-pane contract**.

`QuillCodeSecondaryPaneSurface.swift` now owns only aggregate secondary-pane surfaces: Extensions, Memories, and Automations. Memory note rows and automation workflow rows moved into focused row contract files, matching the earlier extension manifest row split and keeping delete/run/pause/resume command derivation beside the row contracts that render those actions.

What changed:
- Added `MemoryNoteSurface.swift` for memory preview normalization, byte labels, and global-memory delete command IDs.
- Added `AutomationWorkflowSurface.swift` for configured automation status labels, run-now eligibility, pause/resume commands, delete commands, and planned workflow rows.
- Moved row-specific tests into `MemoryNoteSurfaceTests` and `AutomationWorkflowSurfaceTests`.
- Tightened the parity gate so row internals cannot drift back into `QuillCodeSecondaryPaneSurface.swift`.

Remaining risk:
- `WorkspaceMemoriesSurface` still computes memory count labels inline, and `WorkspaceAutomationsSurface` still computes aggregate status labels inline. That is appropriate while the aggregate labels remain compact and directly tested; split them only if secondary-pane aggregate state grows beyond count/status projection.

## 2026-06-24 Workspace UI State Contract Split

Overall grade after this slice: **A+ UI state ownership, A workspace-model boundary**.

`WorkspaceModel.swift` still orchestrates live workspace behavior, but it no longer defines the reusable UI state contracts for the composer, Memories pane, and Activity pane. Those DTOs are shared by the native UI, surface builders, and focused tests, so keeping them in the model file made the model look like the owner of presentation contracts that are not actor-bound behavior.

What changed:
- Added `WorkspaceUIState.swift` for `ComposerState`, `MemoriesState`, and `ActivityState`.
- Added direct default-state coverage in `WorkspaceUIStateTests`.
- Added a parity gate so the state contracts do not drift back into `WorkspaceModel.swift`.

Remaining risk:
- `WorkspaceModel.swift` is still the largest app source file because it owns actor-bound orchestration for sends, tools, terminal, projects, memory, automations, and MCP lifecycle. Continue extracting pure state transitions and copy into focused helpers before adding larger Codex-parity features.

## 2026-06-24 Native Sidebar Project List Split

Overall grade after this slice: **A+ sidebar project-list ownership, A native sidebar scanability**.

`QuillCodeSidebarView.swift` was still a broad left-rail file: primary actions, thread sections, thread rows, project rows, and utility controls all lived together. Project rows have their own action menu, remote badge, path truncation, selected styling, and growth behavior, so keeping them inline made the sidebar harder to scan and easier to regress when Codex-parity project workflows expand.

What changed:
- Added `QuillCodeProjectListView.swift` for native project-list and project-row rendering.
- Bounded project rows in a focused scroll region so many projects do not crowd the bottom Tools and Settings controls.
- Kept the main sidebar at composition level by delegating project-list rendering.
- Added a parity gate so project-row rendering and project-list sizing policy do not drift back into `QuillCodeSidebarView.swift`.

Remaining risk:
- `QuillCodeSidebarView.swift` still owns primary actions, bulk selection controls, thread sections, thread rows, and utility actions. Split thread rows next if the left rail gains more Codex parity controls such as per-thread status badges, drag ordering, or richer context menus.

## 2026-06-24 Workspace Retry Planner Split

Overall grade after this slice: **A retry ownership, A+ regression guard, A workspace-model boundary**.

`WorkspaceModel.swift` still owned the transcript scan that decides whether the latest user turn can be retried and which exact draft should be restored. The behavior was small, but it is shared by runtime issue recovery, command enablement, and transcript retry affordances, so keeping it inline made the model responsible for another pure state query.

What changed:
- Added `WorkspaceRetryPlanner` for retry availability and retry draft selection.
- Preserved exact draft text while ignoring empty/whitespace-only user messages.
- Added focused retry planner tests for latest-user-message selection and send-state gating.
- Tightened the parity gate so retry transcript scans do not drift back into `WorkspaceModel.swift`.

Remaining risk:
- `WorkspaceModel.swift` still owns the broader send lifecycle and cancellation side effects. Keep extracting pure send/session planning and small recovery policies before adding larger Codex-parity run controls.

## 2026-06-24 Sidebar Surface Contract Split

Overall grade after this slice: **A+ project-list contract ownership, A+ thread-sidebar contract ownership, A regression guard coverage**.

`QuillCodeSidebarSurface.swift` still mixed two separate surface families: project-list rows/actions and thread-sidebar rows/actions. They happen to render in the same left rail, but they have different compatibility payloads, action defaults, and growth paths. Keeping them in one file made future project workflow changes likely to touch thread selection/search code, and vice versa.

What changed:
- Added `QuillCodeProjectListSurface.swift` for project-list aggregate records, project rows, project action labels, and project action compatibility decoding.
- Renamed the remaining sidebar file to `QuillCodeThreadSidebarSurface.swift` so thread rows, bulk actions, selection copy, filtering entry points, and thread action defaults have a precise owner.
- Split the matching surface tests into project-list and thread-sidebar suites so compatibility coverage follows the owning contract file.
- Kept public type names stable so existing native SwiftUI, HTML, command-planning, and surface-builder call sites do not need behavioral changes.
- Tightened the parity gate so project-list contracts, thread-sidebar contracts, and workspace aggregate contracts remain separated.

Remaining risk:
- `QuillCodeThreadSidebarSurface.swift` still owns both thread row action defaults and the aggregate sidebar wrapper. That is appropriate while the behavior stays compact; if archived/pinned/search behavior gains richer compatibility decoding or row badges, split `SidebarItemSurface` into a focused row contract file.

## 2026-06-24 Native Sidebar Thread Row Split

Overall grade after this slice: **A+ sidebar thread-row ownership, A native sidebar scanability, A+ parity guard**.

The native sidebar thread list still owned the per-row interaction details for selecting threads, toggling bulk selection, and opening row actions. Those details are likely to expand as Codex-parity controls grow, so keeping them inline with section/list composition made the list file responsible for both collection layout and individual row behavior.

What changed:
- Added `QuillCodeSidebarThreadRowView.swift` as the focused owner for thread-row selection, action menus, selected styling, minimum hit targets, and bulk-selection toggles.
- Kept `QuillCodeSidebarThreadListView.swift` at the collection/section level so it composes pinned, recent, and archived groups without owning row internals.
- Preserved the shared sidebar command adapter for bulk-selection payload construction.
- Tightened the parity gate so row rendering and toggle-selection behavior cannot drift back into the thread-list or sidebar shell files.

Remaining risk:
- `QuillCodeSidebarThreadListView.swift` still owns the thread section header view. That is acceptable while section policy is just a title and row loop; split it later if sections gain per-group counters, collapsible state, drag targets, or richer Codex-style status summaries.

## 2026-06-24 Native Settings File Split

Overall grade after this slice: **A+ settings shell ownership, A+ Computer Use onboarding ownership, A reusable runtime issue boundary**.

`QuillCodeSettingsView.swift` still owned the settings sheet shell, Computer Use permission card, individual permission rows, reusable runtime issue diagnostics, and `QuillCodeSettingsDraft`. The file was correct, but it mixed four different change paths: settings authentication controls, desktop permission onboarding, transcript/runtime issue reuse, and draft-to-update projection.

What changed:
- Added `QuillCodeComputerUseSettingsCard.swift` for the Computer Use settings card and permission rows.
- Added `QuillCodeRuntimeIssueView.swift` for the reusable runtime issue/diagnostics callout used in settings and transcript surfaces.
- Added `QuillCodeSettingsDraft.swift` for settings draft state and `WorkspaceSettingsUpdate` projection.
- Reduced `QuillCodeSettingsView.swift` to the settings sheet shell, authentication picker, API URL field, OAuth/developer override sections, and footer actions.
- Updated decisions documentation and added a parity gate so the focused native settings files do not drift back into the shell.

Remaining risk:
- Authentication controls are still compact enough to live in the settings shell. If TrustedRouter OAuth gains account switching, token diagnostics, or multiple profiles, split authentication sections into a focused settings-authentication view before adding more branching.

## 2026-06-24 Pull Request Slash Parser Split

Overall grade after this slice: **A+ slash parser ownership, A+ PR argument coverage, A regression guard**.

`SlashCommand.swift` still owned general slash command parsing plus every `/pr` subcommand, including selector/body splitting, reviewer and label argument construction, merge flags, and structured `ToolCall` creation. That made a broad parser responsible for one of the highest-growth Codex parity surfaces.

What changed:
- Added `SlashPullRequestCommandParser.swift` as the focused owner for `/pr` create, view, checks, diff, checkout, comment, review, reviewers, labels, and merge parsing.
- Reduced `SlashCommand.swift` to top-level command routing and general slash parsing.
- Added direct parser tests for empty `/pr`, selector normalization, comments, reviews, reviewers, labels, merge flags, and invalid usage copy.
- Added a parity gate so PR selector/body and reviewer/label parsing do not drift back into the outer slash parser.
- Updated decisions documentation to mark PR slash parsing as a dedicated owner.

Remaining risk:
- `SlashCommand.swift` still owns project, terminal, mode, model, and generic routing. That remains reasonable while those branches are small; split `SlashProjectCommandParser` only if project commands gain richer argument parsing or remote-project setup variants.

## 2026-06-24 Prometheus Model Command Feedback

Overall grade after this slice: **A+ model alias UX, A command transcript clarity, A+ regression coverage**.

The TrustedRouter catalog correctly accepts legacy Fusion IDs as aliases for Prometheus 1.0, but the `/model` command acknowledgement still used the raw command argument. That could make a successful `/model /fusion` look like QuillCode still preferred Fusion terminology even though config, picker rows, and docs now prefer Prometheus 1.0.

What changed:
- `QuillCodeWorkspaceModel.setModel` now returns the canonical model ID it actually stored.
- Slash-command model feedback is rendered from the canonical model ID instead of the raw user input.
- Recommended models show user-facing brand plus preferred ID, such as `Prometheus 1.0 (/synth)`, while arbitrary provider/model IDs stay literal.
- Added focused planner and integration regressions proving `/model /fusion` stores Prometheus 1.0 and confirms `Model set to Prometheus 1.0 (/synth).`

Remaining risk:
- Other non-command surfaces should keep using `TrustedRouterDefaults.preferredDisplayModelID` rather than hand-formatting model IDs. If model picker subtitles or thread metadata gain richer copy, keep the branding policy centralized in `TrustedRouterDefaults` or a small display-label helper.

## 2026-06-24 Browser HTML Snapshot Builder Split

Overall grade after this slice: **A+ browser adapter ownership, A+ static HTML extraction tests, A regression guard**.

`BrowserInspector.swift` still mixed browser URL/file/fetched-page orchestration with low-level static HTML parsing: regex capture helpers, outline candidate ordering, HTML entity cleanup, tag counts, and snippet truncation. That made future browser preview work likely to touch fragile parser details while changing unrelated browser tool-result behavior.

What changed:
- Added `BrowserHTMLSnapshotBuilder.swift` as the focused owner for static HTML snapshot details, outline extraction, text cleanup, and snippet limits.
- Reduced `BrowserInspector.swift` to browser metadata snapshots, local-file handling, fetched-page adaptation, and browser-inspection tool output.
- Added focused builder tests for title/heading/count details, ordered outline extraction, fallback labels, script/style removal, entity decoding, outline limits, and snippet truncation.
- Tightened the parity gate so HTML outline/snippet parsing does not drift back into `BrowserInspector.swift`.

Remaining risk:
- `BrowserHTMLSnapshotBuilder` intentionally uses lightweight regex extraction for static previews. That is enough for Codex-style preview summaries, but if browser comments or element targeting grow into DOM-level interactions, add a dedicated DOM adapter rather than expanding regex parsing.

## 2026-06-24 Project Slash Parser Split

Overall grade after this slice: **A+ project slash ownership, A+ direct parser coverage, A outer parser boundary**.

`SlashCommand.swift` still owned `/project` subcommand aliases, rename validation, project command IDs, and project-specific error copy. The branch was compact, but project workflows are likely to grow with remote-project setup and Codex parity, so keeping this inside the broad top-level parser made the file responsible for one more feature-specific grammar.

What changed:
- Added `SlashProjectCommandParser.swift` for `/project new`, refresh, rename/title, and remove aliases.
- Reduced `SlashCommand.swift` to top-level `/project` delegation.
- Added direct parser tests for empty usage, navigation aliases, rename trimming, and invalid subcommand copy.
- Added a parity gate so project aliases and project error copy do not drift back into the outer slash parser.

Remaining risk:
- `SlashCommand.swift` still owns terminal, mode, model, and generic routing. Split terminal parsing next only if it gains richer shell/session arguments; keep mode/model in the top-level parser while they stay one-argument commands.

## 2026-06-24 Shell Streaming Process Runner Split

Overall grade after this slice: **A shell facade ownership, A+ streaming lifecycle isolation, A regression guard**.

`ShellToolExecutor.swift` still owned the public shell facade plus the full streaming process implementation: async stdout/stderr readers, timeout state, cancellation state, process waiting, and final streamed `ToolResult` emission. That made the core shell executor harder to audit and increased the chance that future streaming UI work would touch blocking shell execution.

What changed:
- Added `ShellStreamingProcessRunner.swift` as the focused owner for streaming process lifecycle.
- Kept `ShellToolExecutor` as the stable public facade for blocking, cancellable, and streaming shell entry points.
- Added streaming regressions for empty-command failure and timeout behavior preserving partial output.
- Added a parity gate so streaming lifecycle internals do not drift back into `ShellToolExecutor.swift`.

Remaining risk:
- Blocking shell execution and cancellable blocking execution still share the same file. That is acceptable while the public facade stays compact; if cancellation state grows beyond `CancellableProcessBox`, extract a blocking process runner with the same explicit ownership boundary.

## 2026-06-24 Terminal Slash Parser Split

Overall grade after this slice: **A+ terminal slash ownership, A+ alias coverage, A outer parser boundary**.

`SlashCommand.swift` still owned `/terminal`, `/term`, and `/shell` subcommand behavior. The branch was small, but terminal behavior is user-facing and cross-wired through the command palette, visible pane actions, Stop All, and terminal persistence. Keeping the terminal grammar in a focused parser makes it easier to add future terminal session arguments without making the top-level slash dispatcher broader.

What changed:
- Added `SlashTerminalCommandParser.swift` for terminal toggle, clear, and reset parsing.
- Reduced `SlashCommand.swift` to top-level terminal alias delegation.
- Added direct parser tests for `/terminal`, `/term`, `/shell`, clear/reset aliases, whitespace-tolerant direct parsing, and invalid usage copy.
- Added a parity gate so terminal command IDs and usage copy do not drift back into the outer slash parser.

Remaining risk:
- `SlashCommand.swift` still owns mode, model, scheduling, SSH, memory, and generic routing. Keep one-argument commands in place while they stay trivial; split scheduling or SSH parsing first if either gains richer validation or structured arguments.

## 2026-06-24 Top-Bar Parity Gate Split

Overall grade after this slice: **A+ parity suite ownership, A top-bar regression coverage, A maintainability**.

`ParityGateTests.swift` was still acting as the catch-all for top-bar and runtime-label architecture checks even though tool and desktop parity gates already had focused suites. The file remained the largest Swift file in the repo, which made quality-gate review slower and increased merge-conflict risk for parallel agents.

What changed:
- Added `ParityTopBarGateTests.swift` as the focused owner for top-bar presentation, lifecycle labels, runtime/auth labels, model-catalog surface, and top-bar surface builder gates.
- Kept the broad parity suite focused on cross-cutting project structure and non-top-bar app architecture boundaries.
- Updated the focused-suite guard so top-bar/runtime gates do not drift back into `ParityGateTests.swift`.

Remaining risk:
- `ParityGateTests.swift` is still large because it covers many historical extraction gates. Continue splitting cohesive surface groups into focused parity suites when touching those areas; avoid creating one-test files unless the feature area is likely to grow.

## 2026-06-24 Mode Slash Parser Split

Overall grade after this slice: **A+ mode slash ownership, A+ alias coverage, A outer parser boundary**.

`SlashCommand.swift` still owned `/mode` argument parsing and mode-specific usage/error copy. Mode is a small grammar, but it is central to the send-time UX and appears in composer controls, slash suggestions, transcript copy, and persisted thread configuration. Keeping the mode grammar focused makes future mode additions or copy changes testable without expanding the top-level dispatcher.

What changed:
- Added `SlashModeCommandParser.swift` for Auto, Review, and Read-only aliases.
- Reduced `SlashCommand.swift` to top-level `/mode` delegation.
- Added direct parser tests for aliases, case/whitespace tolerance, empty usage, and unknown-mode copy.
- Added a parity gate so mode usage/error copy does not drift back into the outer slash parser.

Remaining risk:
- `SlashCommand.swift` still owns model, scheduling, SSH, memory, and generic routing. Model parsing should stay small while it delegates canonical naming to `TrustedRouterDefaults`; split scheduling or SSH first if either gains richer argument validation.

## 2026-06-24 Model Category Search Filter Split

Overall grade after this slice: **A+ model picker search ownership, A+ direct search coverage, A top-bar DTO boundary**.

`QuillCodeTopBarSurface.swift` still mixed stable top-bar records with model picker query policy: whitespace normalization, Favorites/Recent scoping, searchable model metadata construction, and State-row special handling. That made a public surface DTO responsible for UX search behavior and made future model picker changes more likely to touch serialization-facing records.

What changed:
- Added `ModelCategorySearchFilter.swift` as the focused owner for model picker search semantics.
- Reduced `TopBarSurface.filteredModelCategories(matching:)` to a stable compatibility delegator.
- Added direct regressions for whitespace-tolerant search, special Favorites/Recent category visibility, branded TrustedRouter labels, and State metadata matching.
- Tightened the top-bar parity gate so query normalization and model metadata haystack construction do not drift back into the surface DTO.
- Updated the fallback TrustedRouter display contract from Synth to Prometheus 1.0 while preserving the existing `/synth`, `tr/synth`, and legacy Fusion aliases for saved configs.

Remaining risk:
- The filter still performs simple substring matching. That is appropriate for the Codex-style picker today; if model catalog search grows aliases, fuzzy ranking, or provider/category facets, add a small ranking value type rather than expanding SwiftUI picker state.
