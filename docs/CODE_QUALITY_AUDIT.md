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
| `QuillCodeApp` surface contracts | B+ | Strong shared surface model and broad tests. The main risk is `WorkspaceModel`, `WorkspaceSurface`, and `WorkspaceSwiftUIView` continuing to absorb too many responsibilities. |
| Playwright harness | B+ | Valuable parity harness with broad coverage. It intentionally duplicates rendering behavior, so keep it thin and derived from stable surface concepts. |

## File Hotspots

| File | Grade | Next Improvement |
| --- | --- | --- |
| `Sources/QuillCodeApp/WorkspaceModel.swift` | B+ | Command parsing, automation records/run drafts, terminal session construction, and project registry transitions now live in focused helpers; extract desktop/runtime coordination next. |
| `Sources/QuillCodeApp/WorkspaceSwiftUIView.swift` | B+ | The shell is now mostly composition, state, and routing. Next step is moving remaining transcript/find/context-banner rendering or command-routing helpers out if they grow again. |
| `Sources/QuillCodeApp/WorkspaceSurface.swift` | B+ | Surface assembly is valuable but large. Keep moving small ranking/formatting helpers out or make them single-pass builders. |
| `Sources/quill-code-desktop/QuillCodeDesktopApp.swift` | A- | App scene composition is now small and declarative. Keep it limited to window/menu-bar wiring and root-view routing. |
| `Sources/quill-code-desktop/QuillCodeDesktopController.swift` | B+ | Desktop controller is now mostly UI/workspace routing. Next split should move platform settings actions and settings persistence into focused helpers before more desktop behavior lands. |
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

1. Split platform settings actions and settings persistence out of `QuillCodeDesktopController.swift` before adding more desktop behavior.
2. Continue pulling pure workflow planning out of `WorkspaceModel` before adding new Codex-parity commands.
3. Keep splitting remaining workspace surface assembly into single-purpose builders when behavior grows.
4. Keep the parity matrix updated whenever a feature moves from planned to implemented.

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
