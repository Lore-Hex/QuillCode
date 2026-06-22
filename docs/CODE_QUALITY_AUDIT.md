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
| `Sources/QuillCodeApp/WorkspaceModel.swift` | B | Split command handling, automation runners, terminal state, and project actions into focused coordinators. |
| `Sources/QuillCodeApp/WorkspaceSwiftUIView.swift` | B | Extract large panes and reusable controls as native QuillUI components before visual polish work expands. |
| `Sources/QuillCodeApp/WorkspaceSurface.swift` | B+ | Surface assembly is valuable but large. Keep moving small ranking/formatting helpers out or make them single-pass builders. |
| `Sources/quill-code-desktop/main.swift` | B | Desktop bootstrap mixes app lifecycle, menu-bar status, OAuth, and commands. Extract coordinator types before adding more platform behavior. |
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

1. Extract workspace command execution from `WorkspaceModel`.
2. Extract automation runners from `WorkspaceModel`.
3. Continue splitting `WorkspaceSwiftUIView` into pane/control files matching the surface structs. The composer, model picker, top bar, sidebar, review pane, design primitives, transcript message bubbles, and tool-card/artifact-preview family are now extracted; the next targets are settings, runtime issue panels, terminal/browser panes, and workspace command execution.
4. Move desktop menu-bar/OAuth orchestration out of `Sources/quill-code-desktop/main.swift`.
5. Keep the parity matrix updated whenever a feature moves from planned to implemented.

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
