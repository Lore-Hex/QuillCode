# Code Quality Audit

## 2026-06-22 Pass

Overall grade: **A- foundation, B+ product surface maturity**.

The architecture is moving in the right direction: core state is value typed, persistence and runtime adapters are separated, tools use explicit schemas, and SwiftUI plus the Playwright harness render from the same surface contract. The main drag on the grade is file size and feature density in the workspace layer, not a broken abstraction boundary.

## Component Grades

| Component | Grade | Notes |
| --- | --- | --- |
| `QuillCodeCore` | A- | Stable models, canonical TrustedRouter IDs, branded display names, and compatibility decoding. Keep pushing presentation-only naming into helpers instead of scattering strings. |
| `QuillCodeAgent` | A- | Runtime/tool loop is well covered and keeps tool feedback hidden from user transcript surfaces. Next grade step is richer retry/cancellation telemetry. |
| `QuillCodeTools` | A- | Shell/file/git/MCP executors are bounded and testable. Git and MCP files are necessarily dense; keep extracting parsers/policies when behavior grows. |
| `QuillCodeSafety` | A- | Small, explicit policy layer. Needs more production prompt telemetry once live Auto reviewer tuning begins. |
| `QuillCodePersistence` | A | Focused stores, compatibility tests, and clear path ownership. |
| `QuillComputerUseKit` | B+ | Protocol shape is good and macOS adapter is isolated. Linux adapter, app approvals, and visual feedback loops are still parity gaps. |
| `QuillCodeApp` surface contracts | A- | Strong shared surface model and broad tests. Settings, runtime issue, model catalog, top-bar/model contracts, sidebar/project contracts, command, command palette, review, review-comment planning, tool override composition, remote-project tool execution, context banner, transcript projection, execution-context enrichment, browser location/state transitions, MCP launch/session creation, thread seeding, thread lifecycle transitions, sidebar selection transitions, and sidebar bulk action planning now have focused builders; the main remaining risk is `WorkspaceModel`, `WorkspaceSurface`, and `WorkspaceSwiftUIView` continuing to absorb too many responsibilities. |
| Playwright harness | B+ | Valuable parity harness with broad coverage. It intentionally duplicates rendering behavior, so keep it thin and derived from stable surface concepts. |

## File Hotspots

| File | Grade | Next Improvement |
| --- | --- | --- |
| `Sources/QuillCodeApp/WorkspaceModel.swift` | A- | Command parsing, automation records/run drafts, terminal session construction, project registry transitions, review-comment planning, tool override composition, SSH Remote tool execution, browser location/state transitions, MCP surface state, MCP request parsing, MCP runtime/catalog/launch work, tool-card surface types, execution-context enrichment, thread seeding, thread lifecycle transitions, sidebar selection transitions, and sidebar bulk action planning now live in focused helpers; keep extracting pure surface/workflow builders before adding more parity commands. |
| `Sources/QuillCodeApp/WorkspaceSwiftUIView.swift` | B+ | The shell is now mostly composition, state, and routing. Next step is moving remaining transcript/find/context-banner rendering or command-routing helpers out if they grow again. |
| `Sources/QuillCodeApp/WorkspaceSurface.swift` | A- | Surface assembly is now mostly aggregate payload plus runtime/execution context records. Settings copy/compatibility, runtime issue classification, model catalog presentation, top-bar/model presentation contracts, sidebar/project contracts, browser state/presentation contracts, terminal presentation contracts, review presentation contracts, transcript/composer/context presentation contracts, secondary-pane presentation contracts, command construction, command palette ranking, review diff construction, context banner estimation, and transcript message projection are extracted into focused files. Next step is extracting runtime/execution context contracts if their presentation behavior grows. |
| `Sources/QuillCodeApp/WorkspaceHTMLRenderer.swift` | A- | Static HTML harness rendering is still broad, but top-bar HTML delegates to `WorkspaceHTMLTopBarRenderer`, sidebar HTML delegates to `WorkspaceHTMLSidebarRenderer`, tool-card/artifact preview HTML delegates to `WorkspaceHTMLToolCardRenderer`, review pane HTML delegates to `WorkspaceHTMLReviewRenderer`, secondary pane HTML delegates to `WorkspaceHTMLSecondaryPaneRenderer`, browser pane HTML delegates to `WorkspaceHTMLBrowserRenderer`, terminal pane HTML delegates to `WorkspaceHTMLTerminalRenderer`, and shared escaping/context chips live in `WorkspaceHTMLPrimitives`. Next step is extracting another transcript/composer family only when renderer drift appears. |
| `Sources/quill-code-desktop/QuillCodeDesktopApp.swift` | A- | App scene composition is now small and declarative. Keep it limited to window/menu-bar wiring and root-view routing. |
| `Sources/quill-code-desktop/QuillCodeDesktopController.swift` | A- | Desktop controller is now mostly UI/workspace routing. Pasteboard feedback and project-import resolution now live in focused coordinators; keep future desktop protocol/workflow details out of the controller. |
| `Sources/QuillCodeAgent/Agent.swift` | A- | Good test coverage; keep tool continuation limits and transcript filtering explicit. |
| `Sources/QuillCodeCore/Models.swift` | A- | Central source of truth for model IDs, branding, and compatibility. Watch for model/persistence surface bloat. |

## Changes From This Pass

- Kept `trustedrouter/fast` and `tr/fusion` as stable API/config IDs while branding them as **Nike 1.0** and **Prometheus 1.0** in user-facing model surfaces.
- Centralized the branded default names in `TrustedRouterDefaults`, with tests proving canonical IDs and display names separately.
- Removed dead provider plumbing from model metadata summary generation.
- Refactored model-category construction to compute favorite IDs once and pass a `Set` through option building instead of recomputing favorites for every model.
- Updated the Playwright harness to preserve branded labels after model selection.
- Fixed stale decisions documentation that still described recurring automation as deferred.

## Current Refactor Priority

1. Keep `QuillCodeDesktopController.swift` to UI/workspace routing; split future desktop protocol/workflow details before they grow into controller branches.
2. Continue pulling pure workflow planning and surface builders out of `WorkspaceModel` before adding new Codex-parity commands.
3. Keep splitting remaining workspace surface assembly into single-purpose builders when behavior grows; avoid adding new transcript or tool-card projection rules outside the transcript builder.
4. If MCP transports expand beyond stdio, add new launch/session implementations behind `WorkspaceMCPServerLaunching` instead of adding transport-specific branches to the runtime.
5. Keep the parity matrix updated whenever a feature moves from planned to implemented.

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
- Extracted `/help`, `/status`, `/mode`, `/model`, `/rename`, `/project rename`, `/ssh`, `/follow-up`, `/workspace-check`, invalid-command, unknown-command, and workspace-command failure transcript construction.
- Kept command side effects in `WorkspaceModel` so this pass stays behavior-preserving.
- Added parity gates that prevent slash-command local copy from drifting back into `WorkspaceModel`.

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
- Mode and model search controls keep the shared 40 pt minimum hit target.
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
- Kept artifact preview construction routed through `ToolArtifactPreviewBuilder`.
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

Static HTML top-bar rendering, model/mode display, project instruction and memory status, Computer Use status, runtime issue pill, and overflow command buttons moved out of `WorkspaceHTMLRenderer.swift` into `WorkspaceHTMLTopBarRenderer.swift`. This keeps shell identity/status rendering beside the top-bar contract instead of mixing it into transcript composition.

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

Top-bar and model-picker presentation records moved out of `WorkspaceSurface.swift` into `QuillCodeTopBarSurface.swift`, matching the existing native top-bar/model-picker views, static HTML top-bar renderer, and `WorkspaceModelCatalogSurfaceBuilder` boundary. The aggregate workspace surface still carries the `topBar` slot, but model option compatibility decoding, model detail copy, metadata rows, badge/state summaries, and searchable category filtering now live beside the top-bar/model-picker contract.

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
