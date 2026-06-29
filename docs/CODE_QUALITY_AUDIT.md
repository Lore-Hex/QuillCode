# Code Quality Audit

## 2026-06-29 Native Smoke Artifact Evidence Pass

Overall grade after this slice: **A native smoke evidence, A CI review ergonomics, A- packaged-window observability**.

Native smoke already rendered the actual SwiftUI workspace and desktop chrome, but that evidence disappeared with the temp directory. This pass makes those images and reports a stable CI artifact so UI polish, hit-target, and release-entrypoint regressions can be inspected visually after every smoke run.

| Before | After |
| --- | --- |
| `scripts/native-desktop-smoke.sh` generated `workspace.png`, `chrome.png`, `workspace.html`, `report.json`, and `stdout.log`, then deleted the temp root before a PR reviewer or another agent could inspect them. | The script now accepts `QUILLCODE_NATIVE_DESKTOP_SMOKE_ARTIFACT_DIR`, copies every smoke evidence file plus a manifest into that folder, and still preserves the old cleanup behavior unless explicit artifact preservation is requested. |
| Packaged macOS smoke proved direct bundle executable and Launch Services paths, but their screenshots and reports were not separated by launch path. | `scripts/packaged-macos-smoke.sh` now writes direct-executable and Launch Services artifact subfolders plus packaged `Info.plist`, making launch-path regressions easier to compare. |
| CI smoke was a pass/fail log for the native UI evidence. | The smoke job now sets `QUILLCODE_SMOKE_ARTIFACT_DIR` and uploads short-retention UI artifacts on success or failure, so rendered workspace/chrome screenshots are attached to the run. |

Residual risk:

- These artifacts make native smoke inspectable, but they still come from the deterministic render-smoke path. The next deeper layer remains packaged-window Accessibility automation that clicks and samples the real app surface.

## 2026-06-29 Live TrustedRouter Smoke Observability Pass

Overall grade after this slice: **A real-provider failure observability, A- release-lane operator ergonomics, A- live workflow evidence**.

The live smoke already covered the high-risk behaviors that hurt QuillConnect/QuillCode usability: passive “I'll do it” replies, empty shell arguments, missing file side effects, public download side effects, and malformed persisted tool events. This pass makes those failures inspectable without rerunning the provider call.

| Before | After |
| --- | --- |
| `scripts/live-tr-smoke.sh` printed stage labels and ad hoc assertion messages, but a failure could still require manual reconstruction of which prompt, output file, and transcript state mattered. | Every scenario now has an explicit ID, prompt, start/end timing, and JSONL report row with stdout/stderr byte counts plus artifact paths. |
| A live CLI nonzero exit or assertion failure could lose the most useful context behind shell cleanup or scattered `cat` output. | Failures now print the scenario name, prompt, stdout/stderr paths, bounded stdout/stderr tails, and the accumulated scenario report summary before preserving artifacts. |
| Successful live smoke gave only a final pass line. | Successful runs now print a compact table of all real-provider scenarios so release reviewers can see which paths were exercised and how long they took. |

Residual risk:

- This still drives the CLI live path, not the packaged SwiftUI app. The next higher-fidelity layer should run these same prompts through the native desktop window with a live or recorded TrustedRouter transport and inspect the saved transcript/artifact state.

## 2026-06-28 Launch Services Smoke Pass

Overall grade after this slice: **A packaged entrypoint coverage, A- Launch Services coverage, A- release packaging maturity**.

The packaged smoke now proves the same native render-smoke contract through the app bundle's Launch Services entrypoint, not only by invoking the bundle executable directly.

| Before | After |
| --- | --- |
| `scripts/native-desktop-smoke.sh` could run SwiftPM or a direct executable path, but could not validate app-bundle launch semantics. | The smoke accepts `QUILLCODE_DESKTOP_APP_BUNDLE` and runs `open -W -n "$APP_BUNDLE" --args ...`, while keeping the same JSON, PNG, HTML, side-effect, transcript, chrome, and hit-target assertions. |
| `scripts/packaged-macos-smoke.sh` proved bundle metadata and direct executable behavior. | It now runs both direct bundle executable smoke and Launch Services smoke, catching missing argument forwarding, bad package metadata, and release entrypoint drift earlier. |
| Launch Services was listed as a residual packaging gap. | Launch Services argument-passing is now covered; signing/notarization, packaged Accessibility automation, appshot capture, and Linux packaging remain the deeper release gates. |

Residual risk:

- `open -W` proves release entrypoint and argument plumbing, but it does not yet click a real packaged window or verify notarized distribution behavior.

## 2026-06-28 Click-Target Semantic Consistency Pass

Overall grade after this slice: **A semantic action contract, A rendered regression coverage, A- packaged native frame sampling**.

The click-target audit now checks that target kind, target class, target action, and native element behavior agree. This catches the subtle broken states that feel worst in app use: a visually large button that declares itself as text input, a link rendered with press semantics, or a row/icon class mismatch that still happens to meet the 44 px geometry rule.

| Before | After |
| --- | --- |
| Rendered targets could have valid dimensions and explicit metadata while still declaring the wrong action for their element. | Playwright now fails `hit_target_kind_class_mismatch`, `hit_target_action_mismatch`, and `element_action_mismatch` in both broad audits and focused target probes. |
| Fixture coverage caught missing contracts, blocked interiors, and edge ownership, but not semantic contradictions. | The interaction audit fixture now includes wrong-kind, wrong-action, wrong-link, and class/kind-mismatch controls so the gate proves those regressions fail. |
| Swift parity gates only required the helper names used for geometry and metadata checks. | `ParityInteractionTargetGateTests` now requires the semantic mismatch gates too, keeping the rendered audit helper from silently losing those checks. |

Residual risk:

- This is strong rendered harness coverage. The remaining A+ layer is still packaged native Accessibility frame sampling plus live edge-click automation for the macOS/Linux SwiftUI windows.

## 2026-06-28 Packaged macOS Smoke Pass

Overall grade after this slice: **A packaged entrypoint coverage, A- release packaging maturity, B+ Launch Services coverage**.

The macOS desktop app now has a deterministic bundle smoke lane instead of only testing the SwiftPM executable.

| Before | After |
| --- | --- |
| CI proved the native desktop product executable could render and dispatch a real action, but it did not prove the release `.app` bundle pointed at the right executable or carried valid metadata. | `scripts/build-macos-app.sh` builds `quill-code-desktop`, assembles `QuillCode.app`, writes a validated `Info.plist`, and optionally ad-hoc signs for local release experiments. |
| Packaged launch remained a manual checklist item. | `scripts/packaged-macos-smoke.sh` validates bundle metadata and reuses the native render-smoke harness through `QUILLCODE_DESKTOP_EXECUTABLE`, so the packaged executable must pass the same side-effect, transcript, HTML, PNG, chrome, and hit-target checks. |
| `scripts/smoke.sh` covered native desktop behavior on macOS but could miss bundle-entrypoint drift. | Darwin smoke now runs the packaged macOS app smoke after the native executable smoke. |

Historical residual risk at that point:

- This earlier smoke executed the packaged app's bundle executable directly. The later Launch Services smoke pass closes the `open -W` argument-passing gap; signing/notarization, Accessibility-driven packaged UI automation, and Linux packaging still need separate release gates.

## 2026-06-28 Click-Target Action Contract Pass

Overall grade after this slice: **A explicit target semantics, A rendered coverage, A- native pixel measurement**.

Click targets now carry a complete interaction contract instead of only a visual class. Every designed rendered target says what shape it is, what kind of action it performs, and whether that contract came from source markup or runtime fallback.

| Before | After |
| --- | --- |
| A control with a `hit-target-*` class could still omit action/source metadata, so tests could not distinguish a deliberately designed target from one normalized after render. | `WorkspaceHTMLPrimitives` emits `data-hit-target-kind`, `data-hit-target-action`, and `data-hit-target-source="explicit"` together; the harness normalizer marks fallback targets as `auto-*`. |
| Broad Playwright audits accepted fallback-normalized controls once they had a 44 px class. | The audit now fails `auto-*` source/kind/action metadata, forcing primary UI to declare target ownership at the render site. |
| Native hit-target contracts only described family/kind/size. | Native contracts now include semantic action plus behavior flags for nested children and unblocked interior requirements. |

Residual risk:

- Native SwiftUI targets are still source/smoke audited rather than sampled from packaged macOS/Linux windows. The rendered harness has pixel-level interior probes; native parity still needs a future UI automation layer.

## 2026-06-28 Context Summary Telemetry Pass

Overall grade after this slice: **A summary fallback resilience, A- progress observability**.

| Before | After |
| --- | --- |
| Model-backed compact/fork summary failures silently returned `nil`, causing deterministic fallback without visible proof of why. | Summary generation now returns an explicit outcome and records model vs deterministic-fallback notices plus structured telemetry. |
| Fallback diagnostics could have tempted raw error logging near secret-bearing runtime paths. | Diagnostics are whitespace-collapsed, redacted, and bounded before they enter thread events. |
| The created continuation thread only said it was compacted/forked. | It now also records whether the continuation used a model summary or deterministic fallback. |

Residual risk:

- Activity currently renders these as ordinary notices. A richer progress row/spinner for in-flight model summaries remains a UI polish slice.

## 2026-06-28 Click-Target Collision Budget Pass

Overall grade after this slice: **A native source gates, A dense-control spacing, A- native pixel measurement**.

The click-target system already enforced 44 pt/px targets, semantic target kinds, and rendered interior sampling. This pass adds the missing adjacent-control rule: a target can be individually valid and still feel bad if nearby controls are packed with unexplained magic spacing.

| Before | After |
| --- | --- |
| SwiftUI button clusters could use local `4`/`5` point spacing while still passing minimum-size target checks. | The native source audit now rejects tight numeric spacing when the scoped cluster contains interactive controls. |
| Review file actions, saved-filter capsules, and extension/MCP reference grids used one-off dense spacing values. | Those clusters now use `QuillCodeMetrics.denseControlClusterSpacing`, keeping the collision budget named and consistent. |
| Click-target docs focused on the target rectangle itself. | Decisions now explicitly treat adjacent-control spacing as part of the hit-target contract. |

Residual risk:

- Native SwiftUI hit regions are still source-gated and smoke-tested rather than sampled from a packaged macOS/Linux window.

## 2026-06-28 Rendered Click-Target Semantics Pass

Overall grade after this slice: **A semantic target architecture, A rendered regression coverage, A- native pixel measurement**.

Rendered click targets now state their intended interaction shape through a typed `WorkspaceHTMLHitTargetKind` before CSS classes are emitted. This removes the old pattern where each renderer had to remember which `hit-target-*` class to append, and it lets Playwright assert the intended kind for critical controls.

| Before | After |
| --- | --- |
| Feature renderers passed hit-target CSS constants directly, mixing visual classes with interaction semantics and making class order part of the contract. | Renderers pass `hitTargetKind: .icon/.text/.row/.capsule/.formAction/.link` or `hitTargetAttributes(kind:)`; the primitive maps that to classes plus `data-hit-target-kind`. |
| The `summary` primitive defaulted to a row target class even when callers wanted an icon-sized disclosure, so caller intent could be overridden by the default class list. | `summary` defaults through `hitTargetKind: .row` with no implicit class list, so icon summaries and row summaries both get the correct semantic class. |
| Critical Playwright probes checked expected CSS classes, which made tests care about implementation spelling more than interaction meaning. | Probes now support `expectedKind`, verify the matching class and `data-hit-target-kind`, and still sample center/edge/interior click ownership. |

Residual risk:

- Native SwiftUI hit regions are still source-gated and smoke-tested rather than sampled from a packaged macOS/Linux window.

## 2026-06-27 Click Target Affordance And Narrow-Viewport Pass

Overall grade after this slice: **A rendered click-target behavior, A narrow-layout resilience, A- native pixel measurement**.

The target contract now covers more than size: a visible clickable control must look clickable, and squeezed layouts must wrap before stealing width from text-entry targets. A new 320 px audit caught the transcript find bar collapsing its input to 32 px; the rendered and native SwiftUI find bars now switch to compact layouts that preserve 44 px targets.

| Before | After |
| --- | --- |
| The rendered audit caught undersized, blocked, nested, and overlapping controls but did not fail a large control that visually used the default cursor and felt inert. | Added `missing_click_affordance` for non-disabled clickable controls without pointer affordance, with text-entry/select controls exempted. |
| Compact coverage used a 390 px viewport, which missed narrower squeezed pane failures. | Added a 320 px narrow viewport audit across top-bar overflow, model picker, command palette, browser, settings, transcript tool cards, and find. |
| The transcript find bar used a fixed six-column layout, so the input could collapse below the target minimum under squeeze. | Rendered find wraps input/status rows on compact widths, and SwiftUI uses `ViewThatFits` to choose horizontal or compact layouts before compression breaks the text field. |

Residual risk:

- Native target validation is still source-gated and smoke-tested through Swift compilation rather than measured in a packaged macOS/Linux window.

## 2026-06-27 Pull Request Command Palette Parity Pass

Overall grade after this slice: **A command catalog parity, A search target resilience, A- native command breadth smoke**.

Rendered command-palette coverage now mirrors the native pull-request command family instead of exposing only the first four PR actions. The harness also treats command discovery as token-based intent matching, so users can type partial natural queries like `resolve review thread` and still hit the exact structured command.

| Before | After |
| --- | --- |
| The native catalog exposed checkout, reviewer, comment, review, thread, label, and merge PR actions, but the rendered command palette only covered create/view/checks/diff. | Added the missing rendered PR command rows and routing for draft-based actions plus the concrete review-thread list action. |
| Palette tests assumed one result for broad queries such as `view pull request`, which broke as the command family became complete. | Tests now click exact `data-command-id` targets and assert every PR command appears in the rendered palette. |
| Palette search only matched contiguous phrases, so intent queries that skipped filler words could show no results. | Added token-wise command matching across title, ID, category, and keywords. |

Residual risk:

- Full native packaged-window click automation should still confirm that every SwiftUI PR command surface has the same discoverability and hit-target behavior as the rendered harness.

## 2026-06-27 Critical Click-Target Registry Pass

Overall grade after this slice: **A rendered click-target coverage, A registry maintainability, A- native pixel measurement**.

The click-target system already enforced shared 44 px/pt primitives, but high-risk controls were still scattered through individual assertions. This pass makes the user-facing target checklist explicit so primary chrome, model choice, command palette, settings, secondary panes, composer, and transcript tool cards all have named, measured targets.

| Before | After |
| --- | --- |
| Critical target checks were spread across state-specific tests, making it easy to miss a small row action or input when chrome changed. | Added `CriticalTargetProbe` and `expectCriticalTargetRegistry` so high-risk surfaces declare their important controls in one readable registry. |
| Model picker coverage focused on panel visibility and broad audits. | The registry now measures model option rows, details buttons, and favorite buttons, which are exactly the compact row actions most likely to regress. |
| Settings/browser/transcript coverage depended on broad visible-target sweeps. | The registry now explicitly probes auth/sign-in controls, browser address/comment inputs, and tool-card disclosures. |

Residual risk:

- Native SwiftUI rendered hit regions are still source-gated rather than sampled from a packaged macOS/Linux window. The next upgrade should add platform UI automation that measures real native windows with the same named-target registry.

## 2026-06-27 Scoped Native Click-Target Audit Pass

Overall grade after this slice: **A scoped native source gates, A call-site target ownership, A- native pixel measurement**.

The native SwiftUI click-target gate now audits the actual control/modifier scope instead of accepting any target helper in a broad nearby source window. Menu trigger checks inspect the trigger/label portion rather than menu-item content, so a styled menu action cannot accidentally satisfy the ellipsis/button that opens the menu.

Code quality changes:

- Added scoped Swift source extraction for `Button`, `Menu`, `Picker`, `Link`, text-entry, and toggle controls, plus regression coverage proving a nearby compliant button or a target inside Menu content does not satisfy another control.
- Moved native control contracts into the owning call sites for context-banner buttons, browser comment submission, memory-card icon actions, settings footer/API-key actions, worktree dialog footers, and artifact Links.
- Artifact `Link` previews now own their 44 pt target inside the Link label instead of relying on a parent `Group` modifier, making the target contract easier to inspect and harder to break.

Residual risk:

- Native SwiftUI hit regions are still source-gated and offscreen-render smoke tested, not measured by packaged-window click automation. The next coverage layer should drive real macOS/Linux windows and sample rendered hit regions the way Playwright samples the HTML harness.

## 2026-06-27 Click Target System Rethink Pass

Overall grade after this slice: **A native source gates, A rendered label semantics, A- native pixel measurement**.

Click targets now have a stricter meaning across the app: every visible control needs a shared semantic target, every rendered target needs a usable 44 px interior, and label-based controls are treated as real click surfaces only when they actually operate a checkbox/radio target.

| Before | After |
| --- | --- |
| Native gates audited `Button`, `Link`, text fields, toggles, and segmented controls, but visible `Menu` triggers and generic picker triggers could rely on nearby style by convention. | `Menu` triggers, visible `Picker` controls, and `TextEditor` now participate in the source audit with fixture tests for both failing and compliant source. |
| The rendered audit treated labels as passive text, so a tiny checkbox/radio label could feel clickable while escaping the 44 px target contract. | Checkbox/radio labels are audited as click targets, disabled associated labels are ignored, and passive form captions stay out of the target set. |
| Nested-target checks would reject valid HTML when an input lived inside its own label. | The audit keeps rejecting nested interactive controls, but allows the one valid associated label/control pair. |

Residual risk:

- Native SwiftUI hit regions are still source-gated rather than sampled from a packaged app window. The next step is a native UI automation layer that measures rendered macOS/Linux controls with the same 3x3 interior probe used in Playwright.

## 2026-06-27 Click Target Hittability Pass

Overall grade after this slice: **A interaction test oracle, A disabled-control semantics, A- native rendered pixel coverage**.

The prior click-target architecture gave QuillCode a strong shared 44 px target contract, but the browser audit could still under-model real user misses: it sampled only the center plus corners, filtered out visible controls with `pointer-events: none`, and did not assert that generic dialogs participate in active-layer scoping. This pass keeps the UI visually compact while making the audit closer to real click behavior.

| Before | After |
| --- | --- |
| Visible controls with `pointer-events: none` could be filtered out before the audit produced an issue. | Non-disabled visible controls with `pointer-events: none` now fail with `pointer_events_none`; semantically disabled controls still get size/name checks without false clickable-interior failures. |
| Explicit hit-target probes sampled five points, leaving edge-only blockers easier to miss. | Probes now sample a 3x3 interior grid at 20%, 50%, and 80% across the target. |
| Active-layer scoping knew QuillCode-specific panels and popovers. | Generic `dialog[open]` and `[role="dialog"]` surfaces are also treated as active interaction layers. |
| There was no regression fixture proving the audit catches dead/edge-blocked controls. | Added a Playwright fixture that injects a dead target, an edge-blocked target, and a disabled target, then verifies only the real failures are reported. |

Residual risk:

- Native SwiftUI rendered hit regions are still guarded through source-level semantic target contracts plus desktop smoke, not pixel-level native UI inspection. A future packaged UI automation layer should apply the same grid-sampling idea to actual macOS/Linux rendered controls.

## 2026-06-27 Real-World Smoke Coverage Pass

Overall grade after this slice: **A deterministic CI stability, A- real-provider release coverage, B+ live workflow observability until secrets are configured**.

The deterministic suite is strong enough for every PR, but real model regressions need a first-class lane because the failures users noticed were end-to-end behavior failures: passive promises, empty shell arguments, missing file side effects, and model-output/schema drift. This pass turns the existing live TrustedRouter smoke into a documented release lane instead of an easy-to-forget script.

- Added `scripts/real-world-smoke.sh` as the release-candidate wrapper: deterministic smoke always runs, live TrustedRouter smoke runs when a key is available, and `QUILLCODE_REQUIRE_LIVE_SMOKE=1` makes the live path mandatory for prompt/parser/runtime/safety changes.
- Added a manual and weekly `Live TrustedRouter Smoke` workflow that runs the real-provider suite when `QUILLCODE_LIVE_API_KEY` is configured.
- Preserved live smoke artifacts on failure, and optionally on success, so stdout/stderr/thread JSON/workspace state survive debugging.
- Documented when to use deterministic CI versus the real-world smoke lane in the test plan and decisions log.

Residual risk:

- The live workflow depends on a repository secret being configured. Until that exists, local keyfile runs remain the real-provider release gate.

## 2026-06-27 Sidebar Saved Filters Pass

Overall grade after this slice: **A saved-filter architecture, A command/selection consistency, A- custom-search readiness**.

The sidebar had pinned/recent/archived sections but no Codex-like saved-filter affordance, so users had to visually scan the whole chat list even when they only wanted pinned, recent, or archived threads. Adding this at the surface level would have been easy to drift across SwiftUI, static HTML, and Playwright, so the filter state now lives in the shared workspace/sidebar model instead.

Code quality changes:

- Added built-in `All`, `Pinned`, `Recent`, and `Archived` sidebar filters with stable `sidebar-filter:*` command IDs, counts, active state, accessibility labels, and compatibility decoding.
- Routed filter changes through the existing workspace command pipeline instead of view-local callbacks, so SwiftUI, command palette, static HTML, and the Playwright harness share the same behavior.
- Made visible rows the source of truth for select-all and sidebar bulk actions; changing filters clears transient selection and stale hidden selections are intersected away before rendering.
- Kept partitioning/date buckets in `QuillCodeSidebarThreadListBuilder` and filter predicates in `SidebarSavedFilterKind`, preserving a small model boundary instead of adding renderer-specific list logic.
- Added focused Swift tests plus Playwright coverage for counts, active filters, empty states, filtered selection, and disabled bulk pin when the visible selection is already pinned.

Remaining risk:

- These are fixed built-in filters, not user-authored saved searches. Custom saved searches, drag/drop ordering, and packaged-native click automation remain future Codex-parity work, but the command IDs and visible-row selection contract should not need to change.

## 2026-06-27 HTML Command Routing Contract Pass

Overall grade after this slice: **A command attribute consistency, A renderer/harness drift coverage, A- full click-action breadth**.

The click-target audits proved buttons were visible and hittable, but a visible target can still be dead if generated HTML does not expose the same command attribute the click router reads. The Extensions pane had exactly that class of bug: production Swift HTML emitted `data-command` for extension and MCP reference actions, while the harness and click handler expected `data-command-id`.

Code quality changes:

- Normalized extension install/update/start/stop and MCP resource/prompt buttons in `WorkspaceHTMLSecondaryPaneRenderer` to emit `data-command-id`.
- Extended the focused secondary-pane renderer test to cover plugin install/update, MCP stop, MCP resource actions, and MCP prompt actions with exact command IDs.
- Added a parity gate that rejects `data-command` in secondary-pane HTML so future renderer changes stay aligned with the shared click-routing contract.
- Documented `data-command-id` as the single command-button contract in `docs/DECISIONS.md`.

Remaining risk:

- This pass hardens one renderer family and one known drift pattern. A broader generated-HTML audit that enumerates every enabled `data-command-id` in a rendered surface and proves it maps to a dispatchable command would further reduce “button looks live but does nothing” regressions.

## 2026-06-27 Promised Work Execution Hardening

Overall grade after this slice: **A action reliability, A streaming behavior, A- model prompt dependence**.

Codex-style interaction breaks down when the assistant says it will do work and then waits for the user to ask again. The agent already corrected a narrow version of this, but the correction path still depended on a single follow-up and did not directly recover explicit shell promises from `say` actions.

- Promised `say` actions like `I'll run whoami` are now parsed into `host.shell.run` before asking the model for a correction.
- Correction is bounded and repeated promised-work answers now fail as a model-action error instead of becoming a fake final answer.
- Streaming promised-work drafts stay hidden while the final parsed action can still recover and execute the shell command.
- The TrustedRouter system prompt now explicitly forbids future-tense action answers when a tool action can be returned immediately.

Residual risk:

- This recovery only handles explicit shell-command promises. Natural-language promises like `I'll check disk usage` still depend on the correction prompt producing a concrete tool call. Broader intent-to-tool planning should stay in the model/tool planner rather than growing ad hoc command heuristics.

## 2026-06-27 Click Target Re-Architecture Pass

Overall grade after this slice: **A native target contracts, A compact viewport coverage, A- native pixel smoke coverage**.

Click targets need to be treated as a product invariant, not as incidental padding. The existing 44 px HTML audit was valuable, but it only covered the default desktop flow and the native source gate did not require every pressable SwiftUI control to declare an explicit target contract.

| Before | After |
| --- | --- |
| The empty-state starter cards relied on `QuillCodePressableButtonStyle` to provide target size indirectly. | Starter cards now declare a centered full-row target with a 72 px minimum height and the same 14 px radius as the visible card. |
| Native source gates only checked compact platform button styles and icon-only labels. | The parity gate now also rejects any `QuillCodePressableButtonStyle` control that lacks a nearby shared hit-target modifier. |
| The broad Playwright interaction audit ran only through the default desktop workspace states. | Added a compact 390 x 844 audit that exercises top-bar overflow, model picker, search, settings, tool cards, terminal, and browser pane targets. |
| The browser address field could collapse to 32 px wide on compact layouts because navigation, address, and Open controls were forced into one row. | Browser navigation wraps on compact layouts, preserving a full-width address target while keeping nav buttons at 44 px. Native SwiftUI uses `ViewThatFits` to choose the same desktop-vs-compact structure. |

Residual risk:

- Pixel-perfect native target verification still depends on source gates plus SwiftUI smoke until a packaged native UI automation layer can inspect rendered SwiftUI hit regions directly.

## 2026-06-27 Browser Navigation Shortcut Pass

Overall grade after this slice: **A shortcut contract, A native/menu parity, A regression coverage**.

The in-app browser already had visible Back, Forward, and Reload actions, but they behaved like mouse-only controls. Codex-style browser work needs keyboardable history navigation, and shortcut labels are only trustworthy when they route through the same command executor as visible commands.

- Added shared `Cmd+[`, `Cmd+]`, and `Cmd+R` shortcut registry entries for browser Back, Forward, and Reload.
- Surfaced those labels in the command palette, keyboard-shortcuts panel, static HTML harness, and desktop menus.
- Routed native menu shortcuts through `runWorkspaceCommand` so disabled browser actions safely no-op instead of bypassing existing command availability policy.
- Added Playwright coverage for actual keyboard dispatch and a desktop parity gate for native shortcut wiring.

Residual risk:

- Browser shortcuts are still single-tab history controls. Multi-tab browser-session management remains a larger browser parity milestone.

## 2026-06-22 Pass

Overall grade: **A- foundation, B+ product surface maturity**.

The architecture is moving in the right direction: core state is value typed, persistence and runtime adapters are separated, tools use explicit schemas, and SwiftUI plus the Playwright harness render from the same surface contract. The main drag on the grade is file size and feature density in the workspace layer, not a broken abstraction boundary.

## 2026-06-27 Status E2E Coverage Pass

Overall grade after this slice: **A real-world slash coverage, A status copy parity, A spec ownership**.

The `/status` command had strong Swift coverage but no browser-level path through the composer, even though the Playwright harness advertised the command in slash suggestions. That left a realistic user flow untested: type `/status`, submit, and verify the transcript and top bar present the branded model state users actually see.

- Added `status.spec.ts` with composer-driven `/status` coverage for the default Nike 1.0 model and the Synth model after a real model-picker switch.
- Implemented `/status` in the HTML harness so the mock app exercises the command end to end instead of only documenting it in suggestions.
- Hardened the worktree-prune Playwright flow to assert the durable loaded state instead of a transient spinner that can disappear before the browser assertion attaches.
- Added a parity gate so status E2E ownership stays in the focused spec and does not drift into `core.spec.ts` or `composer.spec.ts`.

Residual risk:

- This still uses the HTML harness rather than packaged native automation. Native smoke should eventually assert the same `/status` transcript after app launch/relaunch once the desktop UI runner can inspect SwiftUI text reliably.

## 2026-06-27 Shared Playwright Hit-Target Audit Pass

Overall grade after this slice: **A reusable UI audit helper, A chrome spec cohesion, A regression coverage**.

`workspace-chrome.spec.ts` had absorbed the generic visible-interactive-target and overlap audit implementation while the rest of the Playwright suite used shared harness helpers for navigation and measurement. That made the chrome spec harder to review and prevented other feature specs from reusing the same 44 px hit-target contract without copying browser-side DOM logic.

- Moved `MINIMUM_HIT_TARGET`, hit-target measurement, overlap detection, and `expectHitTarget` into `E2E/playwright/tests/harness-helpers.ts`.
- Kept `workspace-chrome.spec.ts` focused on QuillCode chrome scenarios while importing the shared audit helpers.
- Verified the extraction with the focused chrome spec and the full 77-test Playwright suite.

Residual risk:

- The helper still duplicates some browser-side visibility primitives between size and overlap reporting to keep this pass behavior-preserving. A later cleanup can combine both audits into one browser evaluation if more specs start calling both in the same flow.

## 2026-06-27 Interaction Audit Helper Split

Overall grade after this slice: **A helper ownership, A chrome spec cohesion, A regression coverage**.

The shared hit-target pass made the audits reusable, but it also made `harness-helpers.ts` responsible for both generic harness navigation helpers and a full interaction-audit implementation. This pass splits those concerns so future Playwright specs can opt into UI target auditing without turning the generic helper module into a catch-all.

- Added `interaction-audit-helpers.ts` for the 44 px target contract, visible-interactive-target audits, overlap audits, and single-control hit-target assertions.
- Kept `harness-helpers.ts` focused on harness URL, style measurement, element geometry, sidebar navigation, command palette, top-bar overflow, and settings navigation.
- Updated `workspace-chrome.spec.ts` to import generic harness helpers and interaction audit helpers from separate modules.

Residual risk:

- The audit implementation is still browser-side TypeScript with DOM heuristics rather than native UI automation. That is appropriate for the HTML harness, but packaged macOS/Linux UI hit targets still need native smoke coverage before release gating can rely on exact platform pixels.

## 2026-06-27 Interaction Audit DRY Pass

Overall grade after this slice: **A helper cohesion, A- browser-side audit simplicity, A regression coverage**.

The interaction audit helper had the right module boundary, but the size audit and overlap audit still duplicated browser-side visibility, active-layer, center-point, clipping, and label helpers. This pass keeps the public Playwright expectations unchanged while running one browser-side audit that computes visible targets once and derives both target-size issues and overlap issues from the same inspected target set.

- Replaced the separate `targetAuditIssues` and `targetOverlapIssues` page evaluations with one `interactionAuditReport`.
- Preserved the different semantics for clipped/offscreen controls: target-size auditing ignores uninspectable centers, while overlap auditing excludes them from peer-overlap checks.
- Reused one active interaction layer, one visibility predicate, one clipping predicate, and one interaction-layer label path.

Residual risk:

- The helper remains intentionally browser-DOM specific. Native SwiftUI hit-target confidence still depends on mirrored HTML harness coverage plus smoke tests until a native UI automation layer exists.

## 2026-06-27 Interaction Audit Spec Split

Overall grade after this slice: **A spec ownership, A failure locality, A regression coverage**.

`workspace-chrome.spec.ts` still owned both top-bar/workspace chrome scenarios and the broad interaction-audit sweeps. This made the largest Playwright spec harder to scan and made interaction target failures look like generic chrome failures. This pass moves the cross-state hit-target, overlap, banner, recovery, and secondary-pane target checks into a dedicated interaction-audit spec.

- Added `interaction-audit.spec.ts` for visible target audits, overlap audits, context/runtime recovery target checks, and secondary-pane target checks.
- Kept `workspace-chrome.spec.ts` focused on top-bar overflow flows, horizontal clipping, interface polish primitives, and long-status top-bar stability.
- Reduced `workspace-chrome.spec.ts` from 538 lines to 377 lines without changing test behavior.

Residual risk:

- The interface polish primitive test still covers a broad visual contract inside `workspace-chrome.spec.ts`. Split it only if the visual contract grows or starts failing independently from chrome behavior.

## 2026-06-27 Visual Polish Spec Split

Overall grade after this slice: **A spec ownership, A visual contract locality, A regression coverage**.

The prior split moved interaction-audit sweeps out of `workspace-chrome.spec.ts`, but clipping, polish primitives, and quiet long-status top-bar checks still lived beside top-bar overflow workflow tests. This pass separates visual contract tests from chrome behavior so failures identify whether the issue is navigation/workflow or visual polish.

- Added `visual-polish.spec.ts` for horizontal clipping, interface polish primitives, and quiet long-status top-bar stability.
- Kept `workspace-chrome.spec.ts` focused on top-bar overflow utility routing, Computer Use setup routing, and disconnect-all routing.
- Reduced `workspace-chrome.spec.ts` from 377 lines to 66 lines without changing test behavior.

Residual risk:

- `visual-polish.spec.ts` intentionally spans several UI surfaces because the visual contract is cross-cutting. Extract smaller visual specs only when a specific surface accumulates enough unique polish behavior.

## 2026-06-27 Visual Polish Helper Pass

Overall grade after this slice: **A helper ownership, A visual spec readability, A regression coverage**.

The visual polish split created the right spec boundary, but its horizontal overflow audit still lived as an inline browser-side scanner inside the first test. That made the test harder to scan and made it too easy for future clipping checks to copy broad DOM inspection logic.

- Added `visual-polish-helpers.ts` for the reusable horizontal overflow audit.
- Kept `visual-polish.spec.ts` focused on scenarios: settings, tool flow, interface primitives, and quiet long-status top bar behavior.
- Added a parity gate so the broad `body *` overflow scanner stays in the helper instead of drifting back into the spec.

Residual risk:

- The helper currently exposes only the horizontal overflow audit. Add more visual helpers only when a second spec needs them, so the module stays narrow and behavior-preserving.

## 2026-06-27 Click Target Architecture Pass

Overall grade after this slice: **A click-target contract, A- source coverage breadth**.

The rendered Playwright audits already measured 44 px targets across common surfaces, but source gates did not cover the highest-frequency native controls or generated HTML links. That left room for future patches to reintroduce literal frames on composer actions or small link targets while the current harness still passed.

- Moved composer send/stop controls onto semantic hit-target helpers.
- Made icon target sizing configurable inside the shared design system instead of using literal frames for larger visible icon buttons.
- Added parity gates for top bar, sidebar, composer, search, command palette, settings, transcript controls, Find, and generated HTML links.

Residual risk:

- This still combines source gates with HTML Playwright audits rather than native UI automation measuring the built SwiftUI app. Add native accessibility-frame checks once the packaged app test runner can inspect SwiftUI controls directly.

## 2026-06-27 Reliable Click Target Audit Pass

Overall grade after this slice: **A reliable hit geometry, A overlap detection, A cross-surface coverage**.

The interaction audit now treats click targets as real pointer surfaces instead of only checking their center point. This caught stacked sidebar menus and form controls whose visible checkbox was intentionally smaller than the user-facing label row.

- Sampled center and inset corner points for every visible interactive target so partially blocked controls fail with `interior_click_area_blocked`.
- Evaluated checkbox and radio controls through their associated label when the label provides the actual 44 px pointer target.
- Expanded the Playwright interaction sweep across menus, selection controls, empty model search, worktree dialogs, slash suggestions, PR replies, and approval action buttons.
- Fixed sidebar menu stacking and checkbox row styling in the harness so the visible target and the DOM click target agree.

Residual risk:

- Native SwiftUI hit areas still need direct accessibility-frame automation. The harness now catches the same layout class before it ships through web parity, but packaged native measurement remains a release-gate improvement.

## 2026-06-27 Model Status Display Pass

Overall grade after this slice: **A user-facing model copy, A formatter ownership, A alias compatibility**.

Nike/Synth naming was already enforced in the model picker, slash commands, config, and catalog normalization, but status copy still rendered raw IDs like `tr/synth` in the top-bar subtitle and `/status` transcript. This pass moves model status copy into `WorkspaceStatusTextBuilder` so status surfaces use the same model-branding rule.

- Top-bar subtitles now show recommended model display names such as `Nike 1.0`, `Synth`, and `Synth Code`.
- `/status` text keeps enough detail for support by showing branded recommended models with their preferred command IDs, such as `Synth (/synth)`.
- Unknown provider/model IDs remain literal so advanced users can still verify exact custom model routing.

Residual risk:

- The subtitle still includes model identity for now because that matches the existing surface contract. If the top bar gets visually crowded again, remove the model from the subtitle rather than reintroducing raw IDs.

## 2026-06-28 Linux Computer Use Helper Backend Pass

Overall grade after this slice: **A- Computer Use backend parity, A helper-command contract, B+ visual verification depth**.

Linux Computer Use moved from capability reporting to a real helper-backed backend behind the same `ComputerUseBackend` protocol as macOS. The factory now enables Linux only when the detected graphical session has enough helper coverage, keeping under-provisioned machines on the explicit unavailable path instead of exposing buttons that cannot work.

- Added `LinuxComputerUseBackend` for screenshots, cursor movement, clicks, typing, scrolling, and key presses through Wayland (`grim`, `ydotool`, optional `wtype`) or X11 (`import`/`scrot`, `xdotool`) helpers.
- Changed complete Linux helper detection from "adapter pending" to a ready `ComputerUseStatus` with explicit screen/input readiness.
- Added focused tests for ready Wayland/X11 detection, exact helper command routing, PNG screenshot metadata extraction, scroll wheel-step expansion, and helper failure messages.
- Updated parity docs so Linux Computer Use is treated as implemented when helper prerequisites exist.

Residual risk:

- This is command-contract verified and CI-smoked through fake Linux helpers in a subprocess boundary, but not visually verified on real Linux desktops yet. The next quality step is a real desktop smoke with actual helper binaries plus screenshots checked through the same artifact preview path.

## 2026-06-27 Computer Use Status Contract Pass

Overall grade after this slice: **A- Computer Use executor contract, A status copy accuracy, B+ platform parity**.

Computer Use now has a clearer runtime boundary between permission-missing states and backend-unavailable states. The executor already preflights per-tool permissions before invoking platform APIs; this pass makes unsupported or unavailable backend states explicit so future Linux adapters, helper-process failures, or disabled Computer Use runtimes do not look like macOS permission problems.

- Added a compatibility-safe `unavailableReason` field to `ComputerUseStatus`, with `unavailable` and `unsupportedPlatform` constructors for adapter-owned failures.
- Updated `ComputerUseToolExecutor` to report backend-unavailable errors before permission guidance, but only for known Computer Use tools so unrelated tool names still fall through to the normal router.
- Added focused tests for unavailable status construction, unavailable executor behavior, unknown-tool fallthrough, and preserving screenshot capture when only Accessibility is missing.

Residual risk:

- Product parity is still limited by app-specific approval UX and native visual verification loops. The protocol/executor contract is stronger, and Linux now has a helper-backed route, but the feature still needs real-hardware visual verification before it is fully A-grade.

## 2026-06-27 Desktop Model State Coordinator Pass

Overall grade after this slice: **A desktop state synchronization, A- controller size, A refresh rule clarity**.

`QuillCodeDesktopController.swift` was down to mostly UI routing, but it still directly inspected the workspace model for bootstrap defaults, surface snapshots, composer draft mirroring, terminal draft mirroring, and browser address mirroring. Those rules are small, but they are also easy to break when native Codex-style interactions add more panes, status banners, or command surfaces.

- Added `QuillCodeDesktopModelStateCoordinator` for bootstrap project fallback, initial state capture, refresh-state synchronization, and forced composer draft synchronization after workspace commands.
- Rewired `QuillCodeDesktopController` so published SwiftUI state remains in the controller while model reads and draft-mirroring rules live in one focused coordinator.
- Added a parity gate so direct `model.surface()`, draft reads, browser address reads, and bootstrap project fallback logic do not drift back into the controller.

Residual risk:

- This remains source-gated because the desktop executable still is not split into a standalone library target. The coordinator is intentionally data-only and should become a direct unit-test target once the desktop module boundary is extracted.

## 2026-06-27 PR Review Thread Parity Matrix Guard

Overall grade after this slice: **A documentation parity, A regression guard, unchanged execution quality**.

The structured PR review reply and review-thread tools already existed locally, over SSH Remote projects, in slash commands, in visible command surfaces, and in safety coverage, but `docs/CODEX_PARITY_MATRIX.md` still described those workflows as pending. That drift makes agent handoffs worse because future work may reimplement a completed execution path instead of improving the remaining browse/select UI.

- Updated the Tools, Review pane, and Remote rows to mark inline review replies plus review-thread resolve/unresolve as implemented while keeping richer GitHub review-session browse/select UI pending.
- Added a parity gate that fails if the matrix regresses to saying implemented PR review reply/thread execution is still pending.
- Kept execution code untouched; existing `WorkspaceRemoteProjectToolExecutorTests`, `SlashPullRequestCommandParserTests`, safety tests, parser tests, and command-surface tests already cover the shipped paths.

## 2026-06-27 Compact Click Target Follow-Up

Overall grade after this slice: **A compact control hit targets, A press feedback consistency, A- native measurement**.

The broad click-target pass raised the shared target contract to 44 pt/px and added harness bounding-box coverage. A follow-up audit found two native compact controls that still depended on SwiftUI's small/borderless defaults instead of making the QuillCode hit-target contract explicit.

- Added an explicit 44 pt hit target to the Computer Use settings `Refresh status` action.
- Made activity-section disclosure rows full-width 44 pt targets with a rectangular content shape and shared 0.96 press feedback.
- Added a parity gate that keeps those compact/plain controls from regressing back to platform-default hit boxes.

Residual risk:

- Native SwiftUI hit targets are still source-guarded rather than measured by screenshot/UI automation. Keep mirroring critical controls in Playwright until native UI automation exists.

## 2026-06-27 Click Target Standardization Pass

Overall grade after this slice: **A click-target consistency, A interaction regression coverage, A- native measurement**.

Click targets are now a design-system concern instead of a local padding habit. Compact controls remain visually dense, but text buttons, icon-only buttons, full-row buttons, and capsule controls use semantic helpers that preserve a 44 pt minimum target and make source review straightforward.

- Added `quillCodeTextButtonTarget`, `quillCodeIconButtonTarget`, and `quillCodeFullRowButtonTarget` beside the existing pressable button style.
- Moved browser, terminal, settings, worktree, context banner, sidebar, model picker, memory, review, transcript, command/search result, composer suggestion, and tool-card controls onto the semantic target helpers.
- Added a global HTML harness baseline for `button`, `summary`, and link-style interactive targets, including 0.96 press feedback and targeted sizing for activity, memory, and extension controls.
- Expanded Playwright coverage to measure rendered hit boxes for browser, terminal, activity, extensions, automations, and memory controls.
- Expanded parity gates so native and HTML controls cannot quietly drift back to ad hoc frames or platform-default compact targets.

Residual risk:

- Native SwiftUI measurement is still source-gated. The Playwright harness now measures the corresponding rendered controls; add native UI automation before relying on exact platform pixels in packaged builds.

## 2026-06-27 Desktop Pane Coordinator Pass

Overall grade after this slice: **A- desktop pane routing, A browser-comment mutation ownership, A controller readability**.

Pane visibility toggles and browser comments are small operations, but keeping their model mutations inline in `QuillCodeDesktopController.swift` made the controller the fallback owner for every uncategorized UI action. Moving them behind a named coordinator keeps desktop routing consistent with the existing terminal, browser, workspace action, worktree, and navigation boundaries.

- Added `QuillCodeDesktopPaneCoordinator` for terminal, browser, extensions, and memories pane toggles plus browser comment mutation.
- Rewired `QuillCodeDesktopController` to delegate pane/comment mutation while retaining refresh and UI action exposure.
- Added a parity gate so direct pane and browser-comment model mutations do not drift back into the desktop controller.

Residual risk:

- This is still source-gated because desktop coordinators are not yet built as directly importable units. Keep each coordinator thin until the desktop target gains focused unit-test seams.

## 2026-06-27 Desktop Workspace Action Follow-Up

Overall grade after this slice: **A desktop action mutation routing, A active-root fallback consistency, A- controller mutation hygiene**.

After moving tool-card, review, review-comment, pane, and browser-comment flows out of `QuillCodeDesktopController.swift`, two action mutations still remained inline: message feedback and generic workspace command execution. Those are small, but they kept the controller as a direct model mutation fallback for transcript and command-surface actions.

- Extended `QuillCodeDesktopWorkspaceActionCoordinator` to own message feedback mutation and generic workspace command execution.
- Reused the same active workspace root fallback helper for generic workspace commands.
- Tightened the desktop parity gate so direct message feedback and generic workspace command execution do not drift back into the controller.

Residual risk:

- The controller still owns refresh/draft mirroring because those are published UI state concerns. That boundary is acceptable for now; extract it only if refresh rules become more complex.

## Component Grades

| Component | Grade | Notes |
| --- | --- | --- |
| `QuillCodeCore` | A | Stable value models, focused app-config ownership, focused TrustedRouter default/catalog ownership, canonical IDs, branded display names, and compatibility decoding. Keep future provider/settings behavior out of the general domain model file. |
| `QuillCodeAgent` | A- | Runtime/tool loop is well covered and keeps tool feedback hidden from user transcript surfaces. Next grade step is richer retry/cancellation telemetry. |
| `QuillCodeTools` | A- | Shell/file/git/MCP executors are bounded and testable. Git and MCP files are necessarily dense; keep extracting parsers/policies when behavior grows. |
| `QuillCodeSafety` | A- | Small, explicit policy layer. Needs more production prompt telemetry once live Auto reviewer tuning begins. |
| `QuillCodePersistence` | A | Focused stores, compatibility tests, and clear path ownership. |
| `QuillComputerUseKit` | A-/B+ | Protocol shape, macOS adapter isolation, per-tool permission preflight, and backend-unavailable status copy are solid. Linux adapter, app approvals, and visual feedback loops are still parity gaps. |
| `QuillCodeApp` surface contracts | A- | Strong shared surface model and broad tests. Settings, runtime issue, model catalog, top-bar/model contracts, navigation assembly, sidebar/project contracts, command, command palette, review, review-comment planning, tool override composition, remote-project tool execution, context banner, transcript projection, execution-context enrichment, browser location/state transitions, MCP launch/session creation, thread seeding, thread lifecycle transitions, sidebar selection transitions, sidebar bulk action planning, and automation pane assembly now have focused builders; the main remaining risk is `WorkspaceModel`, `WorkspaceSurface`, and `WorkspaceSwiftUIView` continuing to absorb too many responsibilities. |
| Playwright harness | B+ | Valuable parity harness with broad coverage. It intentionally duplicates rendering behavior, so keep it thin and derived from stable surface concepts. |

## File Hotspots

| File | Grade | Next Improvement |
| --- | --- | --- |
| `Sources/QuillCodeApp/WorkspaceModel.swift` | A- | Command parsing, automation records/run drafts, terminal session construction, project registry transitions, context/action lookup, review-comment planning, tool override composition, SSH Remote tool execution, browser location/state transitions, MCP surface state, MCP request parsing, MCP runtime/catalog/launch work, tool-card surface types, execution-context enrichment, thread seeding, thread lifecycle transitions, thread persistence, selected-thread mutation primitives, local command transcript mutation, thread notice mutation, sidebar selection transitions, sidebar bulk action planning, project context refresh, selected context queries, `/status` context assembly, and top-bar state assembly now live in focused helpers; keep extracting pure surface/workflow builders before adding more parity commands. |
| `Sources/QuillCodeApp/WorkspaceSwiftUIView.swift` | A | The shell is now top-bar/sidebar chrome, state, and routing; center-pane layout, workspace sheet presentation, and worktree dialog lifecycle live in focused files. Keep future modal families and command workflow rules out of the root shell. |
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
| `Sources/quill-code-desktop/QuillCodeDesktopController.swift` | A- | Desktop controller is now mostly published UI state and host capability routing. Bootstrap fallback, surface/draft synchronization, pasteboard feedback, project-import resolution, project/thread navigation, pane toggles/browser comments, workspace action/message-feedback/command routing, worktree routing/loading, terminal run/history, composer send/retry, automation ticking/notification fan-out, command action dispatch, and stop/disconnect orchestration now live in focused coordinators; keep future desktop protocol/workflow details out of the controller. |
| `Sources/QuillCodeAgent/Agent.swift` | A- | Good test coverage; keep tool continuation limits and transcript filtering explicit. |
| `Sources/QuillCodeCore/Models.swift` | A | General chat/thread/memory domain models only; app config, automation scheduling, project/workspace records, tool payloads, and TrustedRouter defaults/catalog records now live in focused core files. Watch for persistence, workflow, tool, or provider-specific behavior trying to drift back in. |
| `Sources/QuillCodeCore/AppConfig.swift` | A | App settings, auth mode compatibility, signed-in account metadata, and favorite model normalization live together without pulling UI/runtime dependencies into core. |
| `Sources/QuillCodeCore/AutomationModels.swift` | A | Automation kind/status/schedule records, recurrence semantics, next-run calculation, and display sorting live together without pulling app-layer automation execution into core. |
| `Sources/QuillCodeCore/ProjectModels.swift` | A | Local/SSH project connection parsing, project refs, instructions, local environment actions, and extension manifests live together without pulling chat/thread runtime state into the project model boundary. |
| `Sources/QuillCodeCore/ToolModels.swift` | A | Tool schema records, tool-call redaction, built-in core tool definitions, tool results, and browser/memory tool-output compatibility live together without pulling router/runtime dependencies into core. |
| `Sources/QuillCodeCore/TrustedRouterDefaults.swift` | A | Central source of truth for TrustedRouter IDs, aliases, branded model names, fallback catalog rows, and catalog normalization. |
| `Sources/QuillCodeCore/ModelInfo.swift` | A | Small catalog value records and sort-key semantics with no app/runtime dependency. |

## Changes From This Pass

- Extracted composer retry, submit, slash-dispatch, agent-send session construction, progress application, and terminal outcome handling from `WorkspaceModel.swift` into `WorkspaceModelComposer.swift`.
- Added parity gates that require composer orchestration to stay in the focused extension while keeping send planning/session execution in their existing focused helpers.
- Extracted mode/model/favorite/catalog/settings/runtime/status APIs from `WorkspaceModel.swift` into `WorkspaceModelConfiguration.swift`.
- Added a configuration parity gate that requires configuration/runtime APIs to stay in the focused model extension while keeping normalization and settings policy in `WorkspaceConfigurationEngine`.
- Extracted global memory save/delete, mutation application, global reload, and thread memory refresh from `WorkspaceModel.swift` into `WorkspaceModelMemory.swift`.
- Added a memory parity gate that requires memory workflow APIs to stay in the focused model extension while keeping memory policy in `WorkspaceMemoryEngine`.
- Extracted local environment action execution and `/env` slash-command dispatch from `WorkspaceModel.swift` into `WorkspaceModelLocalEnvironment.swift`.
- Added a parity gate that requires local environment action execution to stay in the focused model extension and keeps `/env` transcript planning delegated to `WorkspaceEnvironmentSlashCommandPlanner`.
- Added keyboard result highlighting to native and harness chat search so users can type, move with ArrowUp/ArrowDown, and press Enter to select a thread.
- Added Playwright and parity-gate coverage for chat search keyboard selection.
- Added keyboard result highlighting to the native and harness model picker so users can type, move with ArrowUp/ArrowDown, and press Enter to select a model without leaving the keyboard.
- Fixed the harness model-picker button path to focus the search field on open, matching the runtime issue recovery path and Codex-style command popovers.
- Added Playwright coverage for model picker keyboard selection.
- Kept `trustedrouter/fast` stable and moved the fallback model to preferred `/synth`/`tr/synth` while preserving `trustedrouter/fusion`, `tr/fusion`, `/fusion`, `fusion-code`, and `/fusion-code` legacy aliases. User-facing model surfaces brand the defaults as **Nike 1.0** and **Synth**.
- Promoted Synth Code (`/synth-code`, `tr/synth-code`) into the bundled Recommended catalog so the preferred code model is visible offline instead of only working as a hidden alias.
- Added explicit catalog-normalization regression coverage so live or persisted legacy Fusion rows dedupe into Synth/Synth Code and do not reappear as user-facing picker rows.
- Centralized the branded default names in `TrustedRouterDefaults`, with tests proving canonical IDs and display names separately.
- Hardened the model alias boundary so branded `Nike 1.0`, `/fast`, and case-varied `TR` inputs normalize to canonical IDs instead of leaking display copy into persisted model settings.
- Removed dead provider plumbing from model metadata summary generation.
- Refactored model-category construction to compute favorite IDs once and pass a `Set` through option building instead of recomputing favorites for every model.
- Updated the Playwright harness to preserve branded labels after model selection.
- Fixed stale decisions documentation that still described recurring automation as deferred.
- Extracted message feedback mutation and pane visibility APIs from `WorkspaceModel.swift` into focused model extensions.
- Added `WorkspaceMessageFeedbackPlanner` so feedback event construction and summary copy are directly unit tested instead of being embedded in the actor model.
- Strengthened parity gates so feedback and pane visibility APIs cannot drift back into the central workspace model.
- Moved selected-project refresh and project-extension update APIs into `WorkspaceModelProjects.swift`.
- Removed the unused root-model `WorkspaceContextResolver` property; active context lookup now lives only in the surface builder and project context refresher.
- Split native worktree sheet value state and shared choice-row chrome out of `QuillCodeWorktreeDialogs.swift`.
- Added focused draft/request tests and parity gates that keep worktree draft state, shared row chrome, minimum hit-targets, and shared 0.96 press feedback out of the dialog composition file.
- Split native model picker row/detail chrome out of `QuillCodeModelPickerView.swift` into `QuillCodeModelPickerRows.swift`.
- Added a parity gate that keeps model-picker search/highlight state in the picker shell and row/detail/badge/press-feedback behavior in the focused row file.
- Split memory note content/filename policy and traversal-safe path resolution out of `MemoryNoteLoader.swift`.
- Added direct path resolver tests and parity gates that keep memory content validation and file-target resolution out of the broad loader.

## 2026-06-26 Desktop Worktree Coordinator Pass

Overall grade after this slice: **A worktree routing boundary, A async load ownership, A- controller boundary**.

`QuillCodeDesktopController.swift` still directly owned the desktop bridge for worktree create/open/remove/prune actions plus choice-load and prune-preview request construction. Those calls are small, but they all need the same active-workspace-root fallback and are likely to grow with Codex-style worktree UX, remote projects, and diagnostics.

Changes:

- Added `QuillCodeDesktopWorktreeCoordinator` for desktop worktree action routing, worktree choice loading, prune-preview loading, and active workspace root fallback.
- Rewired `QuillCodeDesktopController` to delegate worktree actions while keeping refresh and published UI state ownership at the controller boundary.
- Extended the desktop parity gate so worktree model calls and async loading mechanics cannot drift back into the controller.

## 2026-06-25 Worktree Dialog Coordinator Pass

Overall grade after this slice: **A worktree dialog lifecycle, A stale async-result protection, A root shell boundary**.

`WorkspaceSwiftUIView.swift` still owned worktree dialog draft state and async loading tasks after the dialogs and chrome had been split into focused files. That kept stale-result checks close to the view, but it also meant the root shell owned cancellable worktree-specific behavior and made future dialog changes easier to regress.

Changes:

- Added `QuillCodeWorktreeDialogCoordinator` as the single owner of worktree sheet selection, create/open/remove/prune draft state, choice loading, prune-preview loading, retry handling, and task cancellation.
- Rewired `WorkspaceSwiftUIView` to delegate worktree presentation and retry behavior to the coordinator while keeping the root shell focused on command routing and layout.
- Added coordinator tests proving successful loads apply to the intended draft, retries do not run against hidden sheets, and late async choice results do not overwrite the currently visible dialog after a sheet switch.

## 2026-06-25 Desktop Active Work Coordinator Pass

Overall grade after this slice: **A stop/disconnect routing, A task-slot reuse, A controller boundary**.

`QuillCodeDesktopController.swift` still owned Stop All and Disconnect All orchestration: cancelling interactive desktop task slots, cancelling active model work, disconnecting model state, clearing the composer draft, and refreshing. That behavior is shared command execution policy, not view-state ownership, and it should stay coherent as Computer Use, browser, terminal, and agent work grow.

Changes:

- Added `QuillCodeDesktopActiveWorkCoordinator` for Stop All and Disconnect All behavior.
- Rewired `QuillCodeDesktopController` to delegate stop/disconnect while keeping published draft and refresh ownership at the controller boundary.
- Extended the desktop parity gate so interactive task-slot cancellation, active-work cancellation, and disconnect mutation stay in the focused coordinator.

## 2026-06-25 Desktop Command Coordinator Pass

Overall grade after this slice: **A command planning boundary, A action dispatch boundary, A- controller boundary**.

`QuillCodeDesktopController.swift` already delegated raw command ID planning to `QuillCodeDesktopCommandPlanner`, but it still owned the typed command-action switch. That made the controller the place where new command palette, menu bar, and top-bar actions would naturally accumulate.

Changes:

- Added `QuillCodeDesktopCommandCoordinator` and `QuillCodeDesktopCommandPerforming` so typed command action dispatch has one focused owner.
- Rewired `QuillCodeDesktopController` to plan commands, delegate action dispatch, and keep only concrete UI/workspace capabilities such as opening settings, toggling panes, and running workspace commands.
- Extended the desktop parity gate so typed action switching stays in the command coordinator and cannot drift back into the controller.

## 2026-06-25 Desktop Navigation Coordinator Pass

Overall grade after this slice: **A desktop navigation boundary, A sidebar action reuse, A- controller boundary**.

`QuillCodeDesktopController.swift` still directly routed common project/thread navigation mutations: new chat, thread selection, thread row actions, thread rename, project selection, project row actions, project rename, and add project. These are thin calls, but they are high-frequency Codex navigation paths and naturally attract sidebar-specific workflow branches.

Changes:

- Added `QuillCodeDesktopNavigationCoordinator` for desktop project/thread navigation and sidebar row mutation routing.
- Rewired `QuillCodeDesktopController` to delegate navigation mutations while keeping published UI state and refresh ownership in the controller.
- Extended the desktop parity gate so project/thread navigation and sidebar row dispatch cannot drift back into the controller.

## 2026-06-25 Workspace Context Extension Pass

Overall grade after this slice: **A read-side context ownership, A execution-context enrichment boundary, A- central model size**.

`WorkspaceModel.swift` still owned selected thread/project lookup, active local workspace lookup, terminal current-directory lookup, and current transcript/tool-card projection queries. These are read-side context surfaces, not root storage or mutation policy, and they are used broadly across workflows.

Changes:

- Added `WorkspaceModelContext.swift` for selected thread/project lookup, active workspace root, terminal current directory, current tool cards, current timeline items, and project lookup.
- Kept execution-context enrichment delegated to `WorkspaceExecutionContextSurfaceBuilder`.
- Extended the workspace model parity gate so selected context queries and current transcript projections stay out of the root model file.

## 2026-06-25 Workspace Thread Mutation Extension Pass

Overall grade after this slice: **A thread mutation ownership, A persistence helper boundary, A- central model size**.

`WorkspaceModel.swift` still owned selected-thread mutation, timestamped thread mutation, sidebar selected-ID resolution, notice event appending, and asynchronous agent-run thread replacement. These are shared actor-owned side effects, but they are cohesive thread mutation primitives rather than root storage.

Changes:

- Added `WorkspaceModelThreadMutation.swift` for selected-thread mutation, timestamped thread persistence mutation, sidebar selected-ID resolution, notice appending, valid-thread ID lookup, and agent-run thread replacement.
- Kept pure rename/archive/delete/upsert/fallback logic delegated to `WorkspaceThreadLifecycleEngine` and persistence timestamping delegated to `WorkspaceThreadPersistence`.
- Extended parity gates so thread mutation primitives stay out of the root model.

## 2026-06-25 Desktop Automation Coordinator Pass

Overall grade after this slice: **A desktop automation routing, A task-slot reuse, A controller boundary**.

`QuillCodeDesktopController.swift` still owned the startup due-automation run, recurring ticker loop, tick interval, report query, and notification fan-out. That behavior is desktop runtime orchestration, not view-state routing, and it should be reviewable beside the notification adapter and task-slot use.

Changes:

- Added `QuillCodeDesktopAutomationCoordinator` for startup due-automation execution and recurring automation ticks.
- Rewired `QuillCodeDesktopController` to delegate startup and recurring automation behavior while keeping the controller responsible for refresh state.
- Extended the desktop parity gate so ticker task replacement, tick timing, due-report queries, and notification fan-out stay in the focused coordinator instead of drifting back into the controller.

## 2026-06-25 Desktop Composer Coordinator Pass

Overall grade after this slice: **A desktop composer routing, A send-task reuse, A controller boundary**.

`QuillCodeDesktopController.swift` still owned composer prompt trimming, selected-draft submission, retry preparation, draft clearing, and send-task startup. Those are core chat interactions, so they should stay small, repeatable, and isolated from general desktop UI routing.

Changes:

- Added `QuillCodeDesktopComposerCoordinator` for composer send and retry-last-turn wiring.
- Rewired `QuillCodeDesktopController` to delegate send/retry behavior while keeping published UI state and refresh ownership in the controller.
- Extended the desktop parity gate so send task-slot use, prompt normalization, and retry preparation stay in the focused coordinator instead of drifting back into the controller.

## 2026-06-25 Desktop Terminal Coordinator Pass

Overall grade after this slice: **A desktop terminal routing, A task-slot reuse, A controller boundary**.

`QuillCodeDesktopController.swift` still owned terminal command trimming, run-task startup, UI draft clearing, history-draft synchronization, and previous/next recall. Those rules are small but important for a fast native app: terminal commands should not double-run, stale UI drafts should be preserved correctly when browsing history, and the controller should not become the owner of every desktop workflow.

Changes:

- Added `QuillCodeDesktopTerminalCoordinator` for terminal command execution and history recall wiring.
- Rewired `QuillCodeDesktopController` to delegate terminal run/previous/next behavior while keeping the controller responsible for published UI state and refresh.
- Extended the desktop parity gate so terminal task-slot use, command normalization, and draft-history synchronization stay in the focused coordinator instead of drifting back into the controller.

## 2026-06-25 Inline Pull Request Review Comment Pass

Overall grade after this slice: **A GitHub PR tool schema, A local/SSH Remote parity, A validation boundary**.

Codex-style review workflows need an explicit inline PR review primitive rather than asking the model to compose ad hoc `gh api` commands. Top-level PR comments and review submissions already existed, but changed-line comments were still missing.

Changes:

- Added `host.git.pr.review_comment` with structured selector/path/line/side/body/start-line arguments and conservative append risk.
- Implemented local execution by resolving PR number/head commit through `gh pr view --json`, resolving repository owner/name through `gh repo view --json`, and posting the inline comment through `gh api`.
- Implemented SSH Remote parity with the same validation and a quoted remote command that expands only resolved metadata variables.
- Added `/pr review-comment` plus command-palette prefill, command icon, execution-context classification, and local/remote command-surface coverage.
- Added focused tests for local API arguments, early validation, router dispatch, slash parsing, SSH Remote command construction, and JSON URL artifact extraction.

## 2026-06-25 Shared Task Coordinator Pass

Overall grade after this slice: **A cancellable task lifecycle, A desktop task-slot wrapper, A stale-callback guard**.

Desktop sends, terminal commands, browser previews, and the automation ticker already shared a focused task-slot coordinator, but that coordinator lived only in the desktop executable. That kept the controller clean, but the cancellation semantics themselves had no direct unit tests and could not be reused by future app surfaces.

Code quality changes:

- Added `QuillCodeTaskCoordinator` to `QuillCodeApp` as the shared MainActor task-slot coordinator.
- Kept `QuillCodeDesktopTaskCoordinator` as a thin desktop slot wrapper around the shared coordinator.
- Tightened stale task replacement behavior so a cancelled or replaced task cannot run its old `onFinish` callback after it is no longer the current task for that slot.
- Added focused unit coverage for duplicate start rejection, slot cancellation, replace cancellation, and cancel-all behavior.
- Added a parity gate that prevents raw task storage from drifting back into the desktop wrapper.

Remaining risk:

- The task coordinator intentionally manages lifecycle slots only; it does not own higher-level send, terminal, browser, or automation policy. Future cancellation telemetry should stay in those workflow planners rather than adding domain-specific branching to this primitive.

## 2026-06-25 Memory Loader Policy Boundary Pass

Overall grade after this slice: **A memory loader ownership, A path safety, A- content policy boundary**.

`MemoryNoteLoader.swift` had absorbed memory file loading, content validation, filename generation, sensitive-content detection, and traversal-safe path resolution. That was workable but risky: project/global memory delete and edit behavior depends on exact path bounds, and broad loader edits made those security rules harder to review.

Code quality changes:

- Added `MemoryNoteContentPolicy.swift` for write/update validation, sensitive-content detection, title normalization, slugging, and available filename generation.
- Added `MemoryNotePathResolver.swift` for global-memory file lookup, project memory directory resolution, and project-memory file lookup.
- Kept `MemoryNoteLoader.validatedUpdateContent` as the stable compatibility shim used by SSH Remote memory edits.
- Reduced `MemoryNoteLoader.swift` from 491 lines to 339 lines so it now focuses on orchestration, bounded file reads, and save/update/delete flows.
- Added direct unit tests for traversal, absolute path, nested path, wrong-prefix, and wrong-scope rejection.
- Added parity gates that prevent content policy and path resolution from drifting back into the loader.

Remaining risk:

- Memory loading still uses one broad loader function for global and project reads. That is acceptable while both scopes share identical read behavior, but extracting a small file enumeration/reader helper is the next cleanup if read formats or remote-backed memory files grow.

## 2026-06-25 Model Picker Row Boundary Pass

Overall grade after this slice: **A model picker interaction ownership, A- row chrome ownership, A parity guard**.

`QuillCodeModelPickerView.swift` had become a mixed SwiftUI file: trigger button, popover search/focus/highlight state, category sections, rows, action buttons, badges, and expanded details lived together. The behavior was correct, but the file made model-picker UX harder to refine and risked search/keyboard behavior getting tangled with row visual polish.

Code quality changes:

- Added `QuillCodeModelPickerRows.swift` for category sections, option rows, badges, favorite/detail buttons, and expanded metadata.
- Kept `QuillCodeModelPickerView.swift` focused on trigger, popover, search, keyboard navigation, highlighted selection, and final model selection.
- Preserved shared `QuillCodePressableButtonStyle` and `QuillCodeMetrics.minimumHitTarget` inside the row file.
- Added a parity gate that prevents row/detail/badge rendering from drifting back into the picker shell.

Remaining risk:

- Model picker row visual behavior is still covered indirectly by SwiftUI compile/parity and Playwright harness behavior. Future native UI automation should cover favorite toggle, details expand/collapse, and keyboard highlight state directly.

## 2026-06-25 Worktree Dialog Boundary Pass

Overall grade after this slice: **A worktree dialog ownership, A- worktree row chrome, A draft/request state**.

`QuillCodeWorktreeDialogs.swift` had grown into a mixed file: worktree sheet identity, draft request values, load-state reducers, shared status/choice row rendering, and the four actual dialog bodies all lived together. The behavior was correct, but the file made future worktree UX changes harder to review and encouraged more view-state logic inside the sheet composition file.

Code quality changes:

- Added `QuillCodeWorktreeDrafts.swift` for worktree sheet identity, create/open/remove/prune drafts, choice load state, prune preview load state, and request projection.
- Added `QuillCodeWorktreeDialogChrome.swift` for known-worktree choice sections, status rows, record rows, and the shared sheet frame.
- Kept `QuillCodeWorktreeDialogs.swift` focused on the four visible sheet bodies: create, open, remove, and prune.
- Applied the shared pressable button style and explicit minimum hit target to selectable worktree rows so they match the rest of the Codex-like chrome.
- Added direct draft/request tests and parity gates so draft state and worktree row chrome cannot drift back into the dialog file.

Remaining risk:

- Worktree dialog accessibility still relies mostly on standard SwiftUI labels. Future product polish should add native UI automation identifiers for each worktree text field and choice row before deeper Playwright/native automation around these sheets.

## 2026-06-25 Workspace Project API Extension

Overall grade after this slice: **A- project API ownership, A context resolver boundary, B+/A- central model size**.

Project workflows already had a focused model extension, but the root workspace model still owned selected-project context refresh and project-extension update orchestration. That made `WorkspaceModel.swift` look like the owner of user-facing project behavior even though project registry APIs, metadata refresh helpers, and extension update tests were already focused.

Code quality changes:

- Moved `refreshSelectedProjectInstructions`, `refreshSelectedProjectContext`, and `runProjectExtensionUpdate` into `WorkspaceModelProjects.swift`.
- Kept local/remote metadata refresh primitives in the root model for now because they are shared actor-owned helpers used by composer, tool runs, automations, memory refresh, and worktrees.
- Removed the dead `contextResolver` property from `WorkspaceModel.swift`; context lookup now happens in `WorkspaceSurface` and `WorkspaceProjectContextRefresher`.
- Strengthened project and context parity gates so selected-project refresh, extension-update orchestration, and resolver ownership cannot drift back into the central model.

Remaining risk:

- Shared project helper primitives still sit in `WorkspaceModel.swift`. They should move only if a focused helper can serve all current extension users without widening storage or creating awkward pass-through APIs.

## 2026-06-25 Workspace Feedback And Pane Visibility API Extension

Overall grade after this slice: **A- feedback ownership, A- pane visibility ownership, B+/A- central model size**.

Message feedback and secondary-pane visibility are small workflows, but they were still public API bodies on `WorkspaceModel.swift`. Moving them out keeps the central actor focused on shared state coordination while putting user-facing feedback event construction and pane toggle behavior in named, reviewable extension files.

Code quality changes:

- Added `WorkspaceModelFeedback.swift` for assistant-message feedback mutation.
- Added `WorkspaceMessageFeedbackPlanner.swift` for feedback event construction and summary copy.
- Added `WorkspaceModelPaneVisibility.swift` for Extensions, Memories, Activity, Automations, and Activity-section visibility toggles.
- Narrowly changed secondary pane states to same-module writable so focused model extensions can mutate actor-owned pane visibility while external package clients still observe read-only state.
- Added focused feedback planner tests and parity gates that require feedback planning and pane visibility mutation APIs to stay outside `WorkspaceModel.swift`.

Remaining risk:

- `WorkspaceModel.swift` still owns project-extension update orchestration and some shared app-actor primitives. Those should only move when the next extraction has a cohesive workflow boundary, not as a mixed utility sweep.

## 2026-06-25 Workspace Composer API Extension

Overall grade after this slice: **A- composer workflow ownership, A send-planner/session boundaries, A- central model size**.

Composer submission is a cohesive workflow family: retry availability, draft mutation, slash-command dispatch, thread preparation, agent-send session construction, live progress application, cancellation, failure, and successful completion all coordinate the same visible send lifecycle. The detailed policies already lived in focused planners and session objects; the central model no longer needs to own the public API body.

Code quality changes:

- Added `WorkspaceModelComposer.swift` for retry/draft APIs, `submitComposer`, slash dispatch, agent-send thread preparation, send-session factory creation, progress application, terminal outcome handling, and agent-send thread context sync.
- Kept prompt/slash classification in `WorkspaceComposerSubmissionPlanner`, send-start state in `WorkspaceAgentSendStartPlanner`, live progress state in `WorkspaceAgentSendProgressPlanner`, terminal lifecycle state in `WorkspaceAgentSendTerminalPlanner`, and async send execution in `WorkspaceAgentSendTaskCoordinator`.
- Moved browser tool mutation for agent sends through `mutateBrowserState` so the composer extension does not need direct write access to `browser` or `lastError`.
- Kept generic thread mutation and agent-run thread replacement as same-module helpers on the central model because they are shared actor-owned state primitives, not composer policy.
- Strengthened parity gates so composer submission, slash dispatch consumption, schedule transcripts, session factory usage, and agent-send progress cannot drift back into `WorkspaceModel.swift`.

Remaining risk:

- `WorkspaceModel.swift` still owns message feedback, pane visibility, project-extension update orchestration, project-context refresh primitives, and persistence helpers. Those are smaller than the previous agent-send block, but the next pass should look for another cohesive ownership group rather than moving mixed utilities.

## 2026-06-25 Workspace Configuration API Extension

Overall grade after this slice: **A- configuration workflow ownership, A policy boundary, B+/A- central model size**.

Model, mode, favorites, catalog replacement, settings application, runtime swaps, and explicit agent-status overrides are one cohesive configuration/runtime workflow family. The detailed policy already lived in `WorkspaceConfigurationEngine`; the central model only needed to coordinate selected-thread synchronization and top-bar refresh. Moving those public API bodies out keeps the root coordinator focused on cross-cutting workspace orchestration.

Code quality changes:

- Added `WorkspaceModelConfiguration.swift` for mode/model selection, favorite mutation, catalog replacement, settings application, runtime replacement, and status overrides.
- Kept model alias normalization, favorite dedupe, catalog normalization, and config/thread sync policy in `WorkspaceConfigurationEngine`.
- Kept runtime runner storage same-module only so the focused extension can apply runtime swaps without making the runner public API.
- Strengthened the configuration parity gate so configuration/runtime APIs cannot drift back into `WorkspaceModel.swift`.

Remaining risk:

- The central model still owns agent-send orchestration, project-context refresh helpers, and generic thread mutation helpers. Those are harder boundaries because they coordinate visible selected state, persistence, and async progress, but they should keep shrinking through focused helpers.

## 2026-06-25 Workspace Memory API Extension

Overall grade after this slice: **A- memory workflow ownership, A memory policy boundary, B+/A- central model size**.

Memory loading, save/delete policy, transcript copy, error copy, and context-update planning were already focused, but the central model still owned the app-coordination methods for `/remember`, global Forget, mutation application, global reload, and thread memory refresh after agent memory writes. Those are cohesive memory workflow APIs and now live together.

Code quality changes:

- Added `WorkspaceModelMemory.swift` for global memory delete, `/remember` execution, global memory reload, mutation application, and thread memory refresh.
- Kept write/delete policy and user-facing memory transcript summaries in `WorkspaceMemoryEngine` and related planners.
- Kept central send completion behavior unchanged: completed agent runs still refresh thread memory context when the session reports a saved memory.
- Strengthened the memory parity gate so memory workflow APIs cannot drift back into `WorkspaceModel.swift`.

Remaining risk:

- Memory editing, richer conflict UI, and autonomous Chronicle-style inference are still product parity gaps. The current change improves ownership and testability, not that broader feature set.

## 2026-06-25 Workspace Local Environment API Extension

Overall grade after this slice: **A- local environment workflow ownership, A planner boundary, B+/A- central model size**.

Local environment action metadata loading, matching, shell-call construction, transcript copy, and integration tests were already focused. The remaining issue was that the central workspace model still owned the public run path and `/env` slash-command dispatch body. That made `WorkspaceModel.swift` look like the owner of local environment workflow policy even though the actual decisions had already moved out.

Code quality changes:

- Added `WorkspaceModelLocalEnvironment.swift` for `runLocalEnvironmentAction` and `runEnvironmentSlashCommand`.
- Kept action matching in `LocalEnvironmentActionMatcher`, command construction in `WorkspaceShellToolCallPlanner`, and `/env` list/run/not-found planning in `WorkspaceEnvironmentSlashCommandPlanner`.
- Avoided widening the private `contextResolver` boundary; the extension reads selected project local actions directly and keeps actor-owned coordination explicit.
- Strengthened the parity gate so local environment execution and slash dispatch cannot drift back into `WorkspaceModel.swift`.

Remaining risk:

- `WorkspaceModel.swift` still owns core tool-run execution and memory workflows. The next extraction should target memory command APIs or tool-run lifecycle ownership only if a cohesive helper boundary emerges.

## 2026-06-25 Terminal History Recall Pass

Overall grade after this slice: **A terminal interaction boundary, A draft-preservation behavior, A regression coverage**.

The integrated terminal had command history as rendered entries, but the input field did not support the Codex-style Up/Down recall loop users expect from a shell. That made repeated terminal work slower and left the native terminal feeling less like a real coding workspace.

Code quality changes:

- Added terminal history cursor and saved draft state to `TerminalState`, with all traversal owned by `WorkspaceTerminalEngine`.
- Preserved partially typed drafts while walking previous commands, skipped running entries, and reset the cursor on manual edits, command start, project switch, and clear-history.
- Wired native SwiftUI Up/Down handling through explicit callbacks so the desktop controller can synchronize its live text-field draft without making the view own workflow state.
- Mirrored the same behavior in the Playwright harness and covered it with a terminal E2E flow.
- Added focused engine tests for traversal, draft restoration, running-command guards, and reset behavior.

Remaining risk:

- This is still line-oriented terminal history, not full interactive PTY parity. Job control, stdin during long-running commands, and curses-style TUI handling remain the larger terminal product gap.

## 2026-06-25 Workspace Active-Work API Extension

Overall grade after this slice: **A- Stop/Disconnect ownership, A planner boundary, B+/A- central model size**.

`WorkspaceModel.swift` still owned the public Stop All and Disconnect All API bodies even though the user-visible lifecycle decisions already lived in `WorkspaceActiveWorkStopPlanner`. Those commands cut across composer sends, terminal runs, MCP processes, and SSH Remote project detachment, so the app actor still needs to coordinate state mutation, but that coordination no longer needs to sit in the central model file.

What changed:

- Added `WorkspaceModelActiveWork.swift` for `cancelActiveWork`, `disconnectAll`, active-work aggregation, and stop-plan application.
- Kept stop/disconnect status policy in `WorkspaceActiveWorkStopPlanner`; the extension only applies actor-owned state, selected project/thread detachment, terminal state cleanup, and top-bar refresh.
- Narrowly changed `composer` to same-module writable so the focused model extension can clear send state while external package users still observe read-only state.
- Updated parity gates to require active-work APIs in the focused extension and prevent cancel/disconnect aggregation from drifting back into `WorkspaceModel.swift`.

Current strict grades:

- `WorkspaceModelActiveWork.swift`: **A-**. It is cohesive and deliberately small; its remaining complexity is the necessary cross-surface cleanup between composer, terminal, MCP, and remote project selection.
- `WorkspaceActiveWorkStopPlanner.swift`: **A**. Status/last-error choices remain pure and directly tested.
- `WorkspaceModel.swift`: **B+/A-**. It dropped another cross-surface command group, but still owns send, tool-run, memory, local environment, worktree, review, and shared persistence orchestration.
- `ParityWorkspaceExecutionGateTests.swift`: **A-**. It now enforces the active-work extension boundary and the planner/status boundary.

Remaining risk:

- `WorkspaceModel.swift` still contains multiple public workflow API families. The next central-model extraction should target a cohesive group such as worktree APIs or review/comment APIs rather than a mixed utility sweep.

## 2026-06-25 Workspace Worktree API Extension

Overall grade after this slice: **A- Worktree workflow ownership, A planner/engine reuse, B+/A- central model size**.

Worktree create/open/remove/prune is a cohesive workflow family: it builds git-worktree tool calls, runs them through the common tool executor, opens local or SSH Remote worktree projects, creates the focused handoff thread, and powers side-effect-free choice/preview loading. Keeping that whole family in `WorkspaceModel.swift` made the central coordinator look like it owned worktree policy even though the detailed tool-call and thread-record decisions already lived in focused helpers.

What changed:

- Added `WorkspaceModelWorktrees.swift` for worktree create/open/remove/prune APIs, choice loading, prune preview loading, and local/SSH Remote worktree handoff helpers.
- Kept tool-call construction in `WorkspaceWorktreeToolCallPlanner`, handoff thread construction in `WorkspaceWorktreeOpenEngine`, and project/thread context snapshots in `WorkspaceProjectContextRefresher`.
- Removed now-unused default-project-name wrappers from `WorkspaceModel.swift`; the extension calls the shared `WorkspaceProjectEngine` helpers directly.
- Updated parity gates so worktree APIs and handoff helpers are required to live in the focused extension and cannot drift back into `WorkspaceModel.swift`.

Current strict grades:

- `WorkspaceModelWorktrees.swift`: **A-**. The file is cohesive and readable; remaining complexity comes from real cross-surface orchestration across tool execution, project registry updates, and thread creation.
- `WorkspaceWorktreeToolCallPlanner.swift`: **A**. Request-to-tool-call construction remains typed and directly tested.
- `WorkspaceWorktreeOpenEngine.swift`: **A**. Local and SSH Remote handoff records stay pure and directly tested.
- `WorkspaceModel.swift`: **B+/A-**. It dropped another large public workflow family, but still owns agent-send, review/action, local environment, memory, and tool-run orchestration.

Remaining risk:

- The next best central-model extraction is probably review/action APIs or local environment action APIs. Tool-run execution is still central by necessity, but its helper boundary is a candidate for a focused extension once review and local-action calls are outside the main file.

## 2026-06-25 Workspace Tool-Run API Extension

Overall grade after this slice: **A- tool-run API boundary, A executor/planner reuse, B+/A- central model size**.

Manual and review-triggered tool runs are a shared workflow family: they make sure a thread exists, refresh project context, start visible agent status, route the tool through the shared workspace executor, record transcript events, persist the thread, and return the final tool result. Keeping that public API body in `WorkspaceModel.swift` made the central coordinator look like the owner of generic tool execution, even though project selection, lifecycle planning, routing, and transcript event construction already lived in focused helpers.

What changed:

- Added `WorkspaceModelToolRuns.swift` for `runToolCall`, selected-thread context sync, shared workspace executor construction, and tool-run event recording.
- Kept effective project selection in `WorkspaceToolRunPreparer`, lifecycle status in `WorkspaceToolRunLifecyclePlanner`, routing in `WorkspaceToolCallExecutor`, and queued/completed transcript event construction in `WorkspaceToolEventRecorder`.
- Left browser mutation, last-error mutation, selected-thread persistence, and top-bar refresh on the app actor where visible workspace state still lives.
- Updated parity gates so generic tool-run APIs and executor construction are required to live in the focused extension and cannot drift back into `WorkspaceModel.swift`.

Current strict grades:

- `WorkspaceModelToolRuns.swift`: **A-**. Cohesive, short, and deliberately thin around already-tested helpers; remaining complexity is necessary app-actor coordination across selected thread, browser state, persistence, and top-bar status.
- `WorkspaceToolCallExecutor.swift`: **A**. Centralized tool routing remains directly tested and reusable by manual, review, and future workflow calls.
- `WorkspaceToolRunPreparer.swift`: **A**. Effective project selection and context sync stay pure enough for focused regression coverage.
- `WorkspaceModel.swift`: **B+/A-**. It dropped another public workflow family, but still owns agent-send, local environment, memory, and shared persistence orchestration.

Remaining risk:

- The central model still coordinates too many public workflow surfaces. The next high-value extraction should target local environment action APIs or memory APIs, because both are cohesive enough to move without weakening actor-owned state safety.

## 2026-06-25 Agent Send Progress Planner Pass

Overall grade after this slice: **A live-progress boundary, A async-thread safety, A regression coverage**.

`WorkspaceModel` already delegated send execution setup and successful completion, but live progress still mixed wrong-thread filtering, send-state mutation, and agent-status selection inline. That progress path is the Codex-like responsiveness path: streaming text, queued tools, running tools, and review blocks need to appear before the run fully completes, while late callbacks from an old thread must not steal the current workspace state.

Code quality changes:

- Added `WorkspaceAgentSendProgressPlanner` as the focused owner of accepted live-progress snapshots and their UI status plan.
- Kept `WorkspaceAgentStatusBuilder` as the single owner of event-to-status copy while routing progress through the typed send-progress plan.
- Simplified `WorkspaceModel.applyAgentProgress` to apply the plan: update the run thread, keep the composer sending, clear stale errors, and refresh the top bar.
- Added focused tests for queued-tool progress, streaming-status progress, and wrong-thread progress rejection.
- Strengthened the parity gate so `WorkspaceModel` no longer chooses live progress status inline.

Remaining risk:

- `WorkspaceModel` still coordinates the active async send task, persistence, and top-bar refresh. That remains acceptable for the app coordinator, but future background/remote runs should move task ownership into a dedicated session coordinator instead of adding more run-state branches here.

## 2026-06-25 Agent Cancellation Telemetry Pass

Overall grade after this slice: **A agent cancellation telemetry, A focused transcript boundary, A regression coverage**.

`AgentRunner.send` already checked cancellation, and the workspace layer repaired cancelled transcripts for the visible app. The agent boundary itself still threw cancellation without publishing a final stopped state, which meant standalone callers and future CLI/remote send sessions could leave the last progress snapshot as queued or running.

Code quality changes:

- Added `AgentCancellationRecorder` as the single owner of agent-level stopped-run transcript mutation.
- Cancellation before the model returns now publishes a stopped notice after the user message.
- Cancellation while a tool is queued or running now publishes a stopped `toolFailed` event plus the stopped notice before rethrowing `CancellationError`.
- Kept `AgentRunner.send` focused on the orchestration loop by delegating stopped-copy and payload JSON to the recorder.
- Added focused async tests for pre-action cancellation and active-tool cancellation.
- Added a parity gate so stopped-run copy and mutation rules do not drift back into `Agent.swift`.

Remaining risk:

- The workspace send lifecycle still owns UI state, persistence timing, and top-bar recovery. That is correct while the app coordinator controls visible selection, but a future session coordinator should own richer retry telemetry if background runs gain more states.

## 2026-06-25 Agent Send Task Coordinator Pass

Overall grade after this slice: **A task-outcome boundary, A cancellation/error classification, A regression coverage**.

`WorkspaceModel.submitComposer` had already delegated prompt planning, run-context construction, live progress planning, and terminal-state planning. The remaining async branch still started the session, awaited progress, caught cancellation/errors, and converted those failures into UI terminal paths inline. That made the app coordinator the owner of send-task classification, which would be the wrong place to add background runs, remote dispatch, or richer retry telemetry.

Code quality changes:

- Added `WorkspaceAgentSendTaskCoordinator` as the focused owner of session execution and terminal outcome classification.
- Added typed `WorkspaceAgentSendTaskOutcome` values for completed, cancelled, and failed sends.
- Kept completed-send persistence, cancellation transcript mutation, and UI lifecycle application in `WorkspaceModel`, where selected-thread and visible app state still live.
- Simplified `submitComposer` so it creates a session, runs the coordinator, and routes the typed outcome to a named terminal helper.
- Added focused async tests for successful completion, progress forwarding, cancellation classification, and runtime failure classification.
- Strengthened the parity gate so active send task execution/error classification stays outside `WorkspaceModel`.

Remaining risk:

- `WorkspaceModel` still owns visible selected-thread updates, persistence timing, and top-bar refresh. That remains appropriate for the visible workspace coordinator, but background task queues should build on the task coordinator instead of adding more branches to `submitComposer`.

## 2026-06-25 Review Action Runner Pass

Overall grade after this slice: **A review-action execution boundary, A status/result clarity, A regression coverage**.

Review action planning already lived outside `WorkspaceModel`, but the model still executed the action tool, executed the diff refresh tool, paired those calls with results, and derived the terminal status inline. That sequencing is small today, but Codex-like review workflows will keep expanding around staging, restoring, hunk actions, PR comments, and multi-file batches.

Code quality changes:

- Added `WorkspaceReviewActionRunner` as the focused owner of executing the planned review action and required diff refresh.
- Added `WorkspaceReviewActionRunResult` so ordered tool results and final status travel as one typed value.
- Simplified `WorkspaceModel.runReviewAction` so it records runner results, saves the selected thread, and applies the final top-bar state.
- Added focused tests that prove successful review actions stage files, failed actions still refresh diff state, and final status reflects both tool results.
- Strengthened the parity gate so review action execution sequencing stays outside `WorkspaceModel`.

Remaining risk:

- `WorkspaceModel` still owns review-action transcript recording and selected-thread persistence because those are actor-bound workspace side effects. Richer review batches or PR publication should build on the runner result instead of adding another tool sequencing branch to the model.

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
- Moved `TrustedRouterDefaults` into `TrustedRouterDefaults.swift`, keeping Nike 1.0, Synth, aliases, fallback catalog rows, and catalog normalization together.
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

- Slash suggestion rows now guarantee the shared 44 pt hit target.
- Suggestion rows use the shared `QuillCodePressableButtonStyle` for consistent `0.96` press feedback.
- The command usage chip no longer relies on a fixed 230 pt row column; long command names truncate in the chip instead of squeezing row detail text first.
- The panel includes a quiet keyboard hint for Up/Down and Tab so command discovery feels more self-explanatory.
- Composer input and send/stop controls use matching 15 pt continuous radii and 46 pt minimum height for a more concentric, tactile bottom bar.

## 2026-06-22 Model Picker Refactor Pass

Overall grade after this slice: **A- foundation, B+ product surface maturity**.

The native model picker moved out of `WorkspaceSwiftUIView.swift` into `QuillCodeModelPickerView.swift`. Model picking now has named subviews for the trigger, popover body, category sections, rows, action buttons, and expanded metadata, which keeps future model-catalog and provider-capability work away from the already-large workspace shell.

Interface polish changes:

- The model trigger now uses the shared `0.96` press feedback instead of a borderless static button.
- Model search controls keep the shared 44 pt minimum hit target.
- Model rows now guarantee a 44 pt selectable summary area and use the shared press style for tactile feedback.
- Info and favorite controls now use the same press style as other high-frequency icon buttons while preserving 44 pt hit areas.
- Long provider/model metadata truncates in the middle instead of pushing row actions off-screen.
- The empty state keeps the same 12 pt inner radius and wraps explanatory copy without clipping.

## 2026-06-22 Top Bar Refactor Pass

Overall grade after this slice: **A- foundation, B+ product surface maturity**.

The native top bar moved out of `WorkspaceSwiftUIView.swift` into `QuillCodeTopBarView.swift`. This keeps workspace shell layout separate from the Codex-like chrome contract: thread identity, model/mode picker, status, and overflow actions now live together in one focused control.

Interface polish changes:

- The overflow menu uses the shared `0.96` press feedback instead of a static borderless icon.
- The overflow menu keeps the shared 44 pt hit target while adding a quiet selected-surface background and 10 pt continuous radius.
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

- Primary sidebar actions now use the shared `0.96` press feedback and a guaranteed 44 pt hit target.
- Thread rows use a shared selection-toggle helper instead of duplicating command construction in two button handlers.
- Thread and project row buttons keep 44 pt minimum interactive height while preserving the compact left-rail density.
- Bulk action buttons, project header icons, row overflow menus, Tools, and Settings now use the same press feedback contract as the composer/model/top-bar controls.

## 2026-06-22 Review Pane Refactor Pass

Overall grade after this slice: **A- foundation, B+ product surface maturity**.

The native git review pane moved out of `WorkspaceSwiftUIView.swift` into `QuillCodeReviewPaneView.swift`. Review summary, file rows, hunk rows, inline comments, range notes, and review action buttons now live beside each other in one focused component, which keeps future diff-review work away from the transcript shell.

Interface polish changes:

- Review action icon buttons now use the shared `0.96` press feedback and a guaranteed 44 pt hit target.
- File-level, hunk-level, and line-level note actions use the same press feedback contract instead of borderless static controls.
- Range and line note inputs keep a 44 pt minimum height, so text entry does not feel cramped beside the action buttons.
- The review hunk count uses tabular numerals, preventing subtle width shifts as review data changes.

## 2026-06-22 Design System Refactor Pass

Overall grade after this slice: **A- foundation, B+ product surface maturity**.

Shared visual primitives moved out of `WorkspaceSwiftUIView.swift` into `QuillCodeDesignSystem.swift`. The workspace shell no longer owns palette constants, hit-target metrics, press feedback, surface styling, or image outlines. That keeps the monolithic file shrinking and gives extracted native controls one stable place to pull UI primitives from.

Interface polish changes:

- The shared 44 pt hit-target metrics now have design-system ownership instead of workspace-shell ownership.
- The shared `0.96` press feedback lives beside the metrics it depends on, making tactile button behavior harder to fork.
- Surface and image-outline modifiers are reusable outside the workspace file while preserving the pure-white dark-mode outline and existing continuous radii.

## 2026-06-22 Transcript Message Refactor Pass

Overall grade after this slice: **A- foundation, B+ product surface maturity**.

Transcript message bubbles moved out of `WorkspaceSwiftUIView.swift` into `QuillCodeTranscriptMessageView.swift`. User and assistant message rendering, retry/use-as-draft controls, feedback controls, and the shared transcript copy button now live beside each other instead of being embedded between terminal and tool-card code.

Interface polish changes:

- Message action controls keep the shared 44 pt minimum hit target and `0.96` press feedback in one focused file.
- The transcript copy button is now shared from the transcript-message component file, so message bubbles and tool cards do not need separate copy affordance implementations.
- The workspace shell shrank by another focused chunk, reducing the risk that future transcript edits accidentally touch terminal, settings, or browser panes.

## 2026-06-22 Tool Card Refactor Pass

Overall grade after this slice: **A- foundation, B+ product surface maturity**.

Tool cards and artifact previews moved out of `WorkspaceSwiftUIView.swift` into `QuillCodeToolCardView.swift`. Tool status badges, execution-context chips and rails, artifact chips, document/image/text previews, and raw JSON detail blocks now live beside the tool-card renderer. The workspace shell places transcript timeline items and wires copy actions, but it no longer owns the tool-card rendering family.

Interface polish changes:

- Tool-card header density, status rails, and bounded raw details preserve the existing rhythm while making future polish safer to localize.
- Artifact chips and previews preserve 44 pt minimum hit areas, pure-white image outline behavior through the design system, and bounded raw JSON/details.
- The shared transcript copy button is reused from transcript message controls so message and tool-card copy affordances stay consistent.

## 2026-06-22 Settings Refactor Pass

Overall grade after this slice: **A- foundation, B+ product surface maturity**.

Settings, runtime issue callouts, Computer Use permission onboarding, and settings draft state moved out of `WorkspaceSwiftUIView.swift` into `QuillCodeSettingsView.swift`. The workspace shell now opens the sheet and applies settings updates, while the settings file owns authentication mode controls, developer override fields, permission rows, diagnostics, and the reusable runtime issue callout used in the transcript.

Interface polish changes:

- Settings now has named subviews for header, authentication picker, API base URL field, OAuth/developer override sections, and footer, reducing body density without changing the visible flow.
- Computer Use setup keeps its permission/status rows together and uses named subviews for header, requirements, next action, restart hint, and refresh action.
- Permission action rows preserve the shared 44 pt minimum hit target through `QuillCodeMetrics.minimumHitTarget`.
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

- Command palette rows now use the shared `0.96` press feedback and guaranteed 44 pt minimum hit target.
- Search result rows now use the shared press feedback and 44 pt minimum hit target instead of plain static buttons.
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

## 2026-06-24 Synth Model Command Feedback

Overall grade after this slice: **A+ model alias UX, A command transcript clarity, A+ regression coverage**.

The TrustedRouter catalog correctly accepts legacy Fusion IDs as aliases for Synth, but the `/model` command acknowledgement still used the raw command argument. That could make a successful `/model /fusion` look like QuillCode still preferred Fusion terminology even though config, picker rows, and docs now prefer Synth.

What changed:
- `QuillCodeWorkspaceModel.setModel` now returns the canonical model ID it actually stored.
- Slash-command model feedback is rendered from the canonical model ID instead of the raw user input.
- Recommended models show user-facing brand plus preferred ID, such as `Synth (/synth)`, while arbitrary provider/model IDs stay literal.
- Added focused planner and integration regressions proving `/model /fusion` stores Synth and confirms `Model set to Synth (/synth).`

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
- Kept the fallback TrustedRouter display contract on Synth while preserving the existing `/synth`, `tr/synth`, and legacy Fusion aliases for saved configs.

Remaining risk:
- The filter still performs simple substring matching. That is appropriate for the Codex-style picker today; if model catalog search grows aliases, fuzzy ranking, or provider/category facets, add a small ranking value type rather than expanding SwiftUI picker state.

## 2026-06-24 Slash Parity Gate Split

Overall grade after this slice: **A+ slash parity suite ownership, A parser regression coverage, A maintainability**.

`ParityGateTests.swift` still owned the PR, project, terminal, and mode slash-parser architecture gates even though tool, desktop, and top-bar gates already had focused suites. The broad parity file remained the largest Swift file and had become a frequent conflict point for parallel agents working on parser slices.

What changed:
- Added `ParitySlashGateTests.swift` as the focused owner for slash parser delegation gates.
- Moved PR, project, terminal, and mode parser boundary checks out of the broad parity suite.
- Updated the focused-suite guard so slash parser gates do not drift back into `ParityGateTests.swift`.

Remaining risk:
- `ParityGateTests.swift` is still large because it owns many historical workspace architecture gates. Continue extracting cohesive groups when touching them; avoid splitting isolated one-off tests unless a feature area is actively growing.

## 2026-06-24 Scheduling Slash Parser Split

Overall grade after this slice: **A+ scheduling slash ownership, A+ alias coverage, A outer parser boundary**.

`SlashCommand.swift` still owned `/follow-up` and `/workspace-check` schedule argument validation plus user-facing usage copy. Those commands are small, but they are tied to persisted automations and visible Automations-pane behavior, so schedule-command grammar needs focused coverage before richer natural-language or recurrence parsing expands.

What changed:
- Added `SlashSchedulingCommandParser.swift` for thread follow-up and workspace-check schedule arguments.
- Reduced `SlashCommand.swift` to top-level scheduling alias delegation.
- Added direct parser tests for schedule argument trimming, empty usage copy, and top-level scheduling aliases.
- Added a parity gate so scheduling usage copy and command construction do not drift back into the outer slash parser.

Remaining risk:
- `SlashCommand.swift` still owns model, SSH, memory, and generic routing. SSH parsing should be the next extraction if remote-project setup gains richer validation or additional address forms.

## 2026-06-24 Synth Naming Restoration

Overall grade after this slice: **A+ model naming consistency, A+ alias compatibility, A picker contract**.

A concurrent model-picker cleanup temporarily changed the `tr/synth` display name away from Synth. The latest product direction is to call this model Synth everywhere while retaining `/synth`, `tr/synth`, and the legacy Fusion aliases for saved configs and older commands.

What changed:
- Restored `TrustedRouterDefaults.synthModelDisplayName` to `Synth`.
- Updated model, transcript, picker, configuration, and parity regressions back to Synth copy.
- Kept legacy Fusion IDs as hidden compatibility aliases that normalize to `tr/synth` and display as `/synth`.

Remaining risk:
- Live provider catalogs can still return arbitrary labels. `TrustedRouterDefaults.normalizedModelCatalog` currently normalizes recommended IDs back to bundled names; keep that invariant if richer provider metadata lands.

## 2026-06-24 App Test Fixture Cleanup

Overall grade after this slice: **A+ app fixture ownership, A cleanup discipline, A maintainability**.

Several app integration suites still carried private `makeTempDirectory()` helpers or raw temporary-directory roots even though `TemporaryDirectoryTestSupport` already provides teardown-backed cleanup. `WorkspaceSlashCommandIntegrationTests` also duplicated the app git-repository fixture, making future git fixture changes easier to miss.

What changed:
- Moved the legacy app integration `makeTempDirectory()` wrapper onto `XCTestCase` and delegated it to `makeQuillCodeTestDirectory()`.
- Removed private temp-directory helpers from browser, command-plan, remote-project tool, and surface tests.
- Removed duplicated slash-command git fixture code so slash integration tests use the shared app git helpers.
- Updated the parity guard to reject private temp helpers and raw temp roots in the cleaned suites.

Remaining risk:
- `WorkspaceModelIntegrationTestSupport.swift` still contains broad cross-domain fixtures because many workspace integration suites share fake SSH, fake GitHub CLI, and git helpers. If one fixture becomes owned by a single domain, move it into that domain's support file instead of growing this shared support module.

## 2026-06-24 Model Slash Parser Split

Overall grade after this slice: **A+ model slash ownership, A+ Synth usage copy, A outer parser boundary**.

`SlashCommand.swift` still owned `/model` argument validation and user-facing Synth usage copy. Model parsing is intentionally small, but it is visible in the composer, transcript confirmations, saved model aliases, and the Codex-style model picker. Keeping the parser focused makes future alias or usage changes testable without expanding the top-level dispatcher.

What changed:
- Added `SlashModelCommandParser.swift` for `/model` argument trimming and empty-argument usage copy.
- Reduced `SlashCommand.swift` to top-level `/model` delegation.
- Added direct parser tests for trimming, empty usage, and top-level delegation.
- Added a parity gate so model usage copy and command construction do not drift back into the outer slash parser.

Remaining risk:
- `SlashCommand.swift` still owns SSH, memory, and generic routing. SSH should be the next parser extraction if remote-project setup gains additional address formats, auth options, or validation copy.

## 2026-06-24 Tool Execution Recorder Cleanup

Overall grade after this slice: **A+ transcript event ownership, A+ follow-up recording coverage, A model simplicity**.

`WorkspaceModel.runToolCall` still manually appended primary and follow-up tool lifecycle events even though `WorkspaceToolEventRecorder` already owned queued/running/completed event construction and transcript redaction. That made the model retain one more piece of tool sequencing detail and made follow-up recording harder to test directly.

What changed:
- Added `WorkspaceToolEventRecorder.append(execution:to:)` for `WorkspaceToolCallExecution`.
- Replaced the manual primary/follow-up loop in `WorkspaceModel.runToolCall` with a single recorder call.
- Added direct test coverage proving execution-level recording preserves primary and follow-up event order.

Remaining risk:
- `WorkspaceModel.swift` is still the largest production app file because it coordinates project, thread, browser, terminal, automation, and tool state. Continue extracting pure planners/engines at behavior boundaries, especially where another helper already owns the detailed semantics.

## 2026-06-24 SSH Remote Slash Parser Split

Overall grade after this slice: **A+ SSH Remote slash ownership, A+ remote usage copy, A outer parser boundary**.

`SlashCommand.swift` still owned `/ssh` and `/remote` argument validation plus user-facing remote-project usage copy. The grammar is small today, but remote projects are a core Codex-parity workflow and will likely grow richer address forms, saved hosts, and auth/setup affordances. Keeping that parsing focused makes the current behavior explicit and gives future remote-project work a stable place to evolve.

What changed:
- Added `SlashRemoteProjectCommandParser.swift` for `/ssh` and `/remote` address trimming and empty-argument usage copy.
- Reduced `SlashCommand.swift` to top-level SSH Remote delegation.
- Added direct parser tests for address trimming, empty usage, and top-level `/ssh`/`/remote` aliases.
- Added a parity gate so SSH Remote usage copy and command construction do not drift back into the outer slash parser.

Remaining risk:
- `SlashCommand.swift` still owns thread lifecycle, memory, environment action, and generic workspace routing. Thread lifecycle aliases should be the next extraction if rename/archive/new-chat commands gain additional confirmation or batch behavior.

## 2026-06-24 Scheduling Slash Execution Cleanup

Overall grade after this slice: **A slash dispatch readability, A scheduling transcript boundary, A model extraction progress**.

`WorkspaceModel.handleSlashCommand` still owned the full success/failure bodies for `/follow-up` and `/workspace-check` even though scheduling grammar and transcript copy already live in focused helpers. The dispatcher should show routing intent, not duplicate the automation/transcript mechanics for every scheduled command.

What changed:
- Extracted `runThreadFollowUpSlashCommand` and `runWorkspaceScheduleSlashCommand` from the central slash-command switch.
- Kept schedule creation in named helpers and shared the success/failure transcript plumbing through `appendScheduledAutomationTranscript`.
- Documented the boundary so future schedule-command changes do not expand `handleSlashCommand` again.

Remaining risk:
- `handleSlashCommand` is still the largest remaining private dispatcher in `WorkspaceModel.swift`. The next stronger extraction should group pure local transcript commands or move workspace-action slash effects behind a small typed executor once the model method access boundary is ready.

## 2026-06-24 Thread Lifecycle Slash Parser Split

Overall grade after this slice: **A+ thread lifecycle slash ownership, A+ alias coverage, A outer parser boundary**.

`SlashCommand.swift` still owned thread lifecycle aliases, thread command IDs, and `/rename` usage copy. These commands are visible in the sidebar, command palette, keyboard shortcuts, context banners, and transcript flow, so keeping their slash grammar beside focused parser tests reduces drift between Codex-style thread UX surfaces.

What changed:
- Added `SlashThreadCommandParser.swift` for `/new`, `/compact`, `/rename`, `/duplicate`, `/archive`, and `/unarchive` aliases.
- Reduced `SlashCommand.swift` to top-level thread lifecycle delegation through `SlashThreadCommandParser.supports`.
- Added direct parser tests for alias recognition, new-chat, compact-context, rename trimming/usage validation, duplicate, archive, and unarchive commands.
- Added a parity gate so thread lifecycle command IDs and `/rename` usage copy do not drift back into the outer slash parser.

Remaining risk:
- `SlashCommand.swift` still owns memory, environment action, worktree, browser, help, status, and generic routing. Memory should be the next parser extraction if `/remember` grows delete/list/search or memory-scope options.

## 2026-06-24 Memory Slash Parser Split

Overall grade after this slice: **A+ memory slash ownership, A+ remember trimming coverage, A outer parser boundary**.

`SlashCommand.swift` still owned memory pane aliases and `/remember` content trimming. The behavior is intentionally small, but it is tied to durable context, memory-pane navigation, transcript-visible slash commands, and command-palette insertions. Keeping it in a focused parser makes future `/remember list/search/delete` work possible without growing the broad slash dispatcher again.

What changed:
- Added `SlashMemoryCommandParser.swift` for `/memory`, `/memories`, and `/remember` aliases.
- Reduced `SlashCommand.swift` to top-level memory command delegation through `SlashMemoryCommandParser.supports`.
- Added direct parser tests for memory-pane aliases, empty `/remember`, and trimmed remember content.
- Added a parity gate so memory pane command IDs and remember parsing do not drift back into the outer slash parser.

Remaining risk:
- `SlashCommand.swift` still owns worktree, browser, help, status, environment action, and generic routing. Environment action parsing should be the next small extraction if local environment commands gain subcommands or usage copy.

## 2026-06-24 Shared Command Icon Catalog

Overall grade after this slice: **A+ icon ownership, A sidebar compatibility, A command-palette DRYness**.

The native sidebar and command palette both mapped many of the same command IDs to SF Symbols. That duplication was low-level but drift-prone: command IDs like `toggle-terminal`, `toggle-browser`, `toggle-memories`, `settings`, Git PR actions, worktrees, Computer Use, and local environment actions could silently get different icons across surfaces.

What changed:
- Added `QuillCodeCommandIconCatalog` as the single native SF Symbol map for command IDs.
- Updated the command palette to consume the shared catalog and removed its private duplicate `QuillCodeCommandIcon`.
- Kept the sidebar’s deliberate `toggle-activity` override for its compact utility menu while delegating all other native symbols to the catalog.
- Added direct catalog tests for fixed command IDs, dynamic slash commands, local environment commands, and fallback symbols.
- Updated parity gates so command icon mapping stays centralized.

Remaining risk:
- HTML sidebar icon tokens are intentionally separate because they map to CSS token names, not SF Symbols. If the HTML shell grows more native-like, bridge those through a dedicated token catalog instead of mixing HTML token and native symbol concerns.

## 2026-06-24 Workspace Utility Slash Parser Split

Overall grade after this slice: **A+ workspace utility slash ownership, A+ alias coverage, A outer parser boundary**.

`SlashCommand.swift` still owned direct workspace utility aliases for browser preview and git worktree listing. These commands are small, but they are visible in the command palette, keyboard-shortcut surface, browser pane, worktree workflows, and Codex-style workspace navigation. Keeping the aliases and command IDs in one focused parser prevents the top-level dispatcher from becoming a bag of unrelated workspace toggles.

What changed:
- Added `SlashWorkspaceCommandParser.swift` for `/browser`, `/preview`, `/worktree`, `/worktrees`, and `/wt`.
- Reduced `SlashCommand.swift` to top-level workspace utility delegation through `SlashWorkspaceCommandParser.supports`.
- Added direct parser tests for browser and worktree aliases.
- Added a parity gate so browser/worktree command IDs do not drift back into the outer slash parser.

Remaining risk:
- `SlashCommand.swift` still owns help, status, environment action, and generic unknown routing. Environment action parsing should move next if `/env` grows richer subcommands, usage copy, or filtering behavior.

## 2026-06-24 Local Environment Slash Parser Split

Overall grade after this slice: **A+ local environment slash ownership, A+ query trimming coverage, A outer parser boundary**.

`SlashCommand.swift` still owned `/env`, `/environment`, and `/local-env` alias matching plus the list-vs-run query conversion. That behavior is small but important because local environment actions are project-specific executable workflows, feed command-palette entries, and surface setup/build/test scripts that multiple agents can extend. Keeping the aliases and query semantics in one parser makes future `/env search`, `/env edit`, or richer action filtering easier without growing the top-level dispatcher.

What changed:
- Added `SlashEnvironmentCommandParser.swift` for local environment aliases and query trimming.
- Reduced `SlashCommand.swift` to top-level local environment delegation through `SlashEnvironmentCommandParser.supports`.
- Added direct parser tests for empty list behavior, top-level aliases, and trimmed action queries.
- Added a parity gate so local environment aliases and query semantics do not drift back into the outer slash parser.

Remaining risk:
- `SlashCommand.swift` still owns `/help`, `/status`, and generic unknown routing. Those are now intentionally close to the root dispatcher, but they can move into a tiny top-level parser if help/status copy or unknown-command recovery grows.

## 2026-06-24 Local Environment Slash Command Planner

Overall grade after this slice: **A+ local environment slash orchestration, A+ action matching ownership, A WorkspaceModel boundary**.

`WorkspaceModel.runEnvironmentSlashCommand` still owned the `/env` decision tree: list local actions, match a user query, choose the not-found transcript, or run the selected action. That kept a small but important project-workflow policy inside the largest app model and duplicated responsibility with `WorkspaceContextResolver`'s local-action matching surface.

What changed:
- Added `LocalEnvironmentActionMatcher` as the single matcher for action IDs, titles, relative paths, and normalized title/path aliases.
- Updated `WorkspaceContextResolver` to delegate local action lookup through the matcher while keeping its public resolver API intact.
- Added `WorkspaceEnvironmentSlashCommandPlanner` to return either a local transcript or a local action ID for `/env` commands.
- Reduced `WorkspaceModel.runEnvironmentSlashCommand` to metadata refresh plus executing the planner result.
- Added direct tests for matcher aliases, normalized names, list-action plans, not-found plans, and run-action plans.
- Updated parity gates so `/env` transcript choice and action matching do not drift back into `WorkspaceModel`.

Remaining risk:
- `WorkspaceModel.handleSlashCommand` still owns the broad slash-command side-effect switch. That is acceptable while each branch delegates to focused planners/engines, but a future pass can split the switch into a small `WorkspaceSlashCommandExecutor` once more command families have similarly focused execution planners.

## 2026-06-24 Desktop Command Planner Split

Overall grade after this slice: **A desktop command-routing boundary, A controller readability, A parity guard**.

`QuillCodeDesktopController.runCommand` still switched directly over command ID strings for native-only actions, Computer Use settings links, retry, stop, and workspace-command fallback. The controller should apply UI state and delegate platform work, not own the string vocabulary for every desktop command surface.

What changed:
- Added `QuillCodeDesktopCommandPlanner` to map `WorkspaceCommandSurface` IDs into typed `QuillCodeDesktopCommandAction` values.
- Reduced `QuillCodeDesktopController.runCommand` to planner delegation plus typed action application.
- Kept native-only Computer Use System Settings routing and workspace-command fallback behavior unchanged.
- Added a desktop parity gate so raw command-ID routing does not drift back into the controller.

Remaining risk:
- The desktop controller still owns applying each typed command action because it owns SwiftUI presentation flags and model refresh sequencing. That is acceptable; if desktop workflows grow more platform-specific side effects, split those into coordinators the same way sign-in, settings, project import, copy feedback, and tasks are already split.

## 2026-06-24 Sidebar Command Metadata Table

Overall grade after this slice: **A+ sidebar presentation DRYness, A native/HTML consistency, A parity guard**.

`QuillCodeSidebarCommandPresentation` had already centralized sidebar command labels and icons, but it still repeated command IDs across separate switches for display titles, HTML icon tokens, HTML test IDs, and the Activity SF Symbol override. That is exactly the kind of low-level duplication that makes native SwiftUI, static HTML, and Playwright surfaces quietly drift as the Codex-style rail grows.

What changed:
- Added `QuillCodeSidebarCommandMetadata` and one `metadataByCommandID` table for sidebar-specific command labels, HTML icon tokens, HTML test IDs, and native icon overrides.
- Replaced three command-ID switches plus the Activity override branch with table lookups and existing fallbacks.
- Added a fallback behavior test for unknown sidebar commands.
- Tightened the parity gate so sidebar command presentation cannot regress to repeated command-ID switches.

Remaining risk:
- The command palette and sidebar intentionally share SF Symbols through `QuillCodeCommandIconCatalog`, while HTML icon tokens remain sidebar-specific CSS tokens. If the HTML shell later adopts a richer icon system, add a dedicated HTML token catalog rather than mixing native symbol names into static markup.

## 2026-06-24 Workspace Slash Dispatch Planner

Overall grade after this slice: **A slash dispatch boundary, A model readability, A regression guard**.

`WorkspaceModel.handleSlashCommand` still switched directly over every parsed `SlashCommand` case. The individual parsers and command-family planners were already split out, but the largest model still owned the raw parsed-command dispatch vocabulary plus local transcript decisions for help/status/invalid/unknown commands.

What changed:
- Added `WorkspaceSlashCommandDispatchPlanner` to map parsed slash commands into typed `WorkspaceSlashCommandDispatchAction` values.
- Reduced `WorkspaceModel.handleSlashCommand` to planner lookup, typed action application, and shared send/top-bar cleanup.
- Kept stateful effects in the model where they belong: thread/project renames, settings mutation, tool execution, environment actions, and persistence still go through existing model methods.
- Added direct planner tests for help/status transcripts, stateful command actions, external command families, invalid commands, and unknown commands.
- Added a parity gate so raw slash-command case handling does not drift back into `WorkspaceModel`.

Remaining risk:
- The typed slash action switch now belongs in `WorkspaceSlashCommandActionExecutor`, but the executor is still a model extension because it mutates workspace state. A future protocol-based executor would be useful only once another model implementation or deeper isolated unit tests justify that indirection.

## 2026-06-24 Workspace Slash Action Executor

Overall grade after this slice: **A slash action executor boundary, A model readability, A parity guard**.

`WorkspaceModel.runSlashCommandDispatchAction` still applied every typed slash action in the main model file. The planner had already removed raw parsed-command switching from the model, but the typed action switch still made the largest file responsible for transcript execution, mode/model changes, thread/project renames, SSH project setup, memory saves, automations, workspace commands, tool calls, and local environment routing.

What changed:
- Added `WorkspaceSlashCommandActionExecutor` as a focused `QuillCodeWorkspaceModel` extension for applying typed slash actions.
- Removed the typed action switch from `WorkspaceModel.swift`, leaving `handleSlashCommand` as parser/dispatch lifecycle coordination.
- Kept stateful helper methods in `WorkspaceModel` where they still own persistence, selected thread/project mutation, local environment refresh, and top-bar sequencing.
- Updated parity gates so raw typed slash action application and workspace-command failure transcript selection do not drift back into the main model file.

Remaining risk:
- The executor still calls model helpers directly because it is an extension over the model. A future protocol-based executor would be useful only if another workspace model implementation or broader isolated executor tests appear.

## 2026-06-24 Whole-Tree Grade

Overall code grade: **A-**.
Overall product/parity grade: **B+**.
Overall test/CI grade: **A**.

Validation run:
- `swift test` passed: 1022 tests.
- `npm test` in `E2E/playwright` passed: 61 Playwright tests.
- Focused parity gates passed: 117 `ParityGateTests`.

The codebase is substantially healthier than a normal prototype at this feature count. The architectural direction is correct: domain models are value typed, tool calls use explicit schemas, shell/file/git paths are bounded, TrustedRouter integration is isolated, native SwiftUI and the static Playwright harness share surface contracts, and parity gates prevent many large-file regressions. The repo is not A+ yet because the central app coordinator still has too much workflow gravity, the static HTML harness is necessarily broad but now oversized, command/action identifiers are still too stringly in several presentation seams, and several Codex-parity surfaces are implemented as first-pass adapters rather than full runtime-quality implementations.

| Area | Grade | Reason |
| --- | --- | --- |
| `QuillCodeCore` | A | Clean value records, focused config/tool/project/model files, strong compatibility decoding, and centralized TrustedRouter model branding. Keep provider/runtime behavior out of core. |
| `QuillCodeAgent` | A- | Good tool-loop semantics, immediate command/file execution coverage, bounded multi-step continuation, streaming draft support, and final-answer recovery. Needs richer live telemetry and provider-failure observability before A+. |
| `QuillCodeTools` | A- | Good workspace bounding and focused shell/file/git/MCP executors. Remaining risk is breadth: GitHub PR/worktree/MCP behavior is powerful but still needs more real-world edge coverage and interactive-terminal parity. |
| `QuillCodeSafety` | B+ | Small and testable, with hard denies plus model-backed Auto review. The static intent matcher is still heuristic-heavy, which is acceptable as a guardrail fallback but not A+ production policy. |
| `QuillCodePersistence` | B+ | Simple stores and compatibility tests are good. `FileSecretStore` is useful for fallback/dev but should set restrictive file permissions or move behind a stronger encrypted adapter before production-grade secret handling. |
| `QuillComputerUseKit` | A- | Protocol, macOS adapter, Linux helper-backed adapter, and permission/status contracts are correctly isolated. App approval UX and visual verification loops are still parity gaps. |
| `QuillCodeApp` model/surfaces | A- | Many responsibilities have been extracted into planners/builders with parity gates. `WorkspaceModel.swift` is still 1858 lines and remains the dependency magnet for workflows. |
| Native SwiftUI views | A- | Recent splits made the sidebar, review pane, workspace shell, and tool cards much easier to maintain. Continue moving workflow rules out of views and into reducers/planners. |
| Static HTML/Playwright harness | B+ | Very valuable for deterministic UI parity, but `E2E/harness/index.html` is 8504 lines and `core.spec.ts` is 2037 lines. It needs modularization before it can be called A-grade long term. |
| Desktop app wrapper | A- | Controller has been reduced through coordinators/planners. Still owns enough command application and presentation state that future desktop-only work should continue extracting platform side effects. |
| CI/release process | A | macOS Swift tests, Linux CLI build, Playwright, smoke, and merge train exist. Add stricter format/lint and more Linux adapter tests before A+. |

Highest-risk files:

| File | Grade | Why |
| --- | --- | --- |
| `Sources/QuillCodeApp/WorkspaceModel.swift` | B+ | The biggest remaining architecture risk. It delegates heavily, but still coordinates automations, browser, memories, project selection, terminal, tool runs, and persistence in one type. Next A+ step is extracting a slash-command/workflow executor and remote/runtime orchestration boundaries. |
| `E2E/harness/index.html` | B | It proves UI behavior, but one 8504-line HTML/JS file is difficult for parallel agents to edit safely. Split renderers/state handlers by pane or generate more of it from shared surface JSON. |
| `E2E/playwright/tests/core.spec.ts` | B+ | Good breadth, but 2037 lines in one spec increases merge conflict and debugging cost. Split by feature area while keeping a small full-flow smoke spec. |
| `Sources/QuillCodePersistence/SecretStore.swift` | B | API is clean, but fallback storage writes plain UTF-8 files without explicit restrictive permissions. Production-grade secrets need Keychain/libsecret/encrypted-file hardening. |
| `Sources/QuillCodeSafety/Safety.swift` | B+ | Correctly compact, but the static matcher has a growing list of phrase heuristics. Move intent classification into typed policy cases or table-driven matchers as tool families grow. |
| `Sources/QuillCodeApp/QuillCodeCommandIconCatalog.swift` | B+ | Still a raw command-ID switch. Acceptable for now, but command metadata should continue consolidating so native, HTML, menu bar, and command palette do not drift. |
| `Package.swift` | B+ | Good module split and Linux CLI build coverage, but package platforms currently declare macOS only while the product goal includes Linux UI. Platform targets/adapters need clearer packaging once QuillUI Linux lands. |

Immediate A+ path:
1. Extract the remaining broad `WorkspaceModel` side-effect switch families into `WorkspaceSlashCommandExecutor`, `WorkspaceBrowserWorkflow`, and `WorkspaceRemoteRuntimeCoordinator` style helpers.
2. Split the Playwright harness into feature modules or a generated renderer bundle so tests remain easy for multiple agents to edit.
3. Harden `QuillSecretStore` fallback with restrictive permissions and an encrypted-file adapter; keep app code on the single secret-store API.
4. Replace growing safety string heuristics with typed tool-intent categories and table-driven approval policy tests.
5. Keep implementing true Codex parity, not just shell surfaces: PTY job control, real browser rendering/live DOM, Linux Computer Use backend, richer memory editing/redaction, and QuillCloud/remote project execution.

## 2026-06-24 File Secret Store Hardening

Overall grade after this slice: **A- fallback secret-store hygiene, A call-site boundary, A regression coverage**.

The fallback `FileSecretStore` was intentionally small, but it wrote plain UTF-8 files without setting restrictive directory or file permissions. That was acceptable for early CLI/dev smoke tests, but not good enough for a public coding agent that stores TrustedRouter delegated keys through one `QuillSecretStore` API.

What changed:
- `FileSecretStore.write` now prepares the secret directory with `0700` permissions and resets existing broader permissions.
- Written secret files are forced to `0600` after the atomic write.
- Secret keys are sanitized to a single filename component using only ASCII letters, digits, `.`, `_`, and `-`, so odd keys cannot create nested/path-like filenames.
- Persistence tests now prove round-trip behavior, private directory permissions, private file permissions, and single-file key sanitization.

Remaining risk:
- This is still a fallback/dev backend, not the final platform backend. The A+ path remains adding Apple Keychain, Linux Secret Service/libsecret, and encrypted-file fallback adapters behind the existing `QuillSecretStore` protocol.

## 2026-06-24 Agent Argument Normalizer Split

Overall grade after this slice: **A parser boundary, A schema-normalization boundary, A regression guard**.

`AgentActionJSONParser` had already been extracted from the TrustedRouter transport, but it still owned every tool-specific argument alias, pull request selector normalization, no-argument tool exception, and shell-command repair path. That made the parser less readable and made future model-output tolerance changes likely to pile into one file.

What changed:
- Added `AgentToolArgumentNormalizer` for canonical tool argument construction, alias cleanup, pull request sub-argument normalization, empty-shell-command repair from explicit nearby backticked prose, and minimum-argument checks.
- Reduced `AgentActionJSONParser` to action extraction, action-type validation, normalizer delegation, and `AgentAction` construction.
- Updated the parity gate so JSON extraction, prose shell recovery, tool argument normalization, and TrustedRouter transport stay in separate files.
- Preserved existing parser behavior for shell aliases, file-write aliases, PR aliases, no-argument tools, and malformed-output shell recovery.

Remaining risk:
- The normalizer is intentionally tolerant because live LLMs vary. If alias support keeps growing, the next A+ step is a table-driven schema alias catalog rather than adding more switch branches.

## 2026-06-24 Static Safety Policy Table

Overall grade after this slice: **A static policy boundary, A intent-rule maintainability, A regression coverage**.

`StaticSafetyReviewer` had stayed compact, but it still mixed mode decisions with raw hard-deny command strings and a long chain of user-intent phrase checks. That made the fallback Auto policy harder to grow safely as PR, worktree, Computer Use, and shell actions expanded.

What changed:
- Added `StaticSafetyPolicy` to own normalized hard-deny matching and user-intent matching.
- Replaced inline blocked-command arrays and phrase chains with `StaticSafetyHardDenyRule`, `StaticSafetyIntentRule`, and `StaticSafetyPullRequestPolicy` tables.
- Kept `StaticSafetyReviewer` focused on mode behavior, hard-deny precedence, low-risk approval, and model-backed reviewer orchestration.
- Added safety tests for representative high-risk pattern-table denies and PR intent specificity.
- Added a parity gate so raw hard-deny patterns and pull-request intent chains do not drift back into `Safety.swift`.

Remaining risk:
- This is still a deterministic fallback for Auto. The production path should keep collecting reviewer-model telemetry and eventually move richer command intent classification into typed tool-intent categories rather than phrase lists.

## 2026-06-24 Worktree Thread Insertion Cleanup

Overall grade after this slice: **A- workspace insertion reuse, A regression coverage, B+ remaining model size**.

`WorkspaceModel` already delegates most thread construction to focused engines, but worktree-created threads still had a separate insertion body that duplicated the central new/fork/compact/duplicate selection, project touch, persistence, and top-bar refresh path. That kind of almost-identical state mutation is where sidebar selection, terminal sync, or persistence behavior can drift.

What changed:
- `openCreatedWorktreeThread` now delegates to `insertCreatedThread` instead of maintaining a parallel insertion sequence.
- Worktree-created threads now clear sidebar bulk selection through the same path as every other created thread.
- Added integration coverage proving a selected source thread is cleared after the worktree thread opens while the original tool audit card remains attached to the source thread.

Remaining risk:
- `WorkspaceModel` is still the largest app-code coordinator. The next A+ pass should extract another stateful boundary only when it can reuse an existing reducer/engine or add a clear one, not by moving state mutations into a less obvious object.

## 2026-06-24 Automation Thread Insertion Cleanup

Overall grade after this slice: **A- created-thread consistency, A automation-run regression coverage, B+ remaining model size**.

Automation-run follow-up threads had the same risk as worktree-open threads: they manually inserted, selected, synced, touched, saved, and refreshed the top bar instead of using the central created-thread insertion helper. That kept behavior correct today, but it meant future selection or persistence changes would need another call site update.

What changed:
- `applyAutomationRunDraft` now reuses `insertCreatedThread` for the follow-up or scheduled workspace thread.
- Automation runs keep their existing automation visibility and error/status finalization while inheriting shared thread insertion behavior.
- Added integration coverage proving an automation run clears sidebar bulk selection when it opens the generated follow-up thread.

Remaining risk:
- `applyAutomationRunDraft` still coordinates automation replacement plus thread insertion because that crosses two state domains. A future extraction should only happen if it can model that cross-domain state transition explicitly.

## 2026-06-24 Browser Workflow Boundary

Overall grade after this slice: **A browser workflow boundary, A stale-fetch safety, A regression guard**.

`WorkspaceModel` still owned browser workflow mechanics directly: resolving addresses, setting invalid-address errors, starting snapshot fetches, checking stale fetch results, applying fetched pages, handling failures, and adding comments. The lower-level browser engine was already focused, but the app coordinator still had enough browser state logic to keep growing as live DOM capture and richer browser tools arrive.

What changed:
- Added `WorkspaceBrowserWorkflow` to own browser workflow state transitions over `WorkspaceBrowserEngine` and `WorkspaceBrowserLocationResolver`.
- Kept `WorkspaceModel` as the actor-bound async caller that starts fetches, awaits the injected page fetcher, and refreshes the top bar.
- Added focused workflow tests for invalid-address handling, successful fetched-page completion, stale fetch protection, navigation, reload, and comments.
- Updated parity gates so direct browser engine/resolver calls do not drift back into `WorkspaceModel`.

Remaining risk:
- Browser preview is still a static/metadata adapter rather than a full live DOM runtime. The next product-grade step is a real browser session adapter with lifecycle, navigation events, authenticated-browser options, and screenshot/DOM verification, while keeping those runtime details behind this workflow boundary.

## 2026-06-24 Browser Parity Gate Suite Split

Overall grade after this slice: **A browser parity ownership, A merge-conflict reduction, A regression guard**.

`ParityGateTests.swift` had already been split by top-bar, slash, tool, and desktop domains, but browser architecture rules were still mixed into the broad catch-all. Browser work is now active enough that those gates should live beside each other, especially while browser workflow, live DOM capture, HTML rendering, and browser-tool contracts evolve.

What changed:
- Added `ParityBrowserGateTests` for browser surface ownership, static HTML snapshot extraction, browser workflow state transitions, browser location resolving, browser integration test ownership, and HTML browser renderer boundaries.
- Removed those browser-specific gates from `ParityGateTests.swift`, trimming the broad suite by about 120 lines.
- Added a guard that fails if browser architecture gates drift back into the broad parity suite.

Remaining risk:
- `ParityGateTests.swift` is still the largest test file because it owns many general app-surface boundaries. Continue extracting by coherent domains when a feature family has multiple related gates and active parallel work.

## 2026-06-24 Model Parity Gate Suite Split

Overall grade after this slice: **A model naming guard, A config ownership, A merge-conflict reduction**.

The Synth rename was already implemented in defaults, slash commands, picker rows, docs, and config normalization, but the architecture gates for model/catalog/config ownership still lived in the broad parity suite. That made it easier for future model-picker work to scatter branding checks or accidentally reintroduce Fusion as user-facing copy.

What changed:
- Added `ParityModelGateTests` for TrustedRouter model catalog ownership, app config ownership, and model naming boundaries.
- Moved model/catalog/config gates out of `ParityGateTests.swift`.
- Added a source-level guard proving Fusion stays confined to the TrustedRouter alias boundary while app surfaces prefer Synth.

Remaining risk:
- The guard intentionally allows legacy aliases in `TrustedRouterDefaults.swift`. If future API compatibility requires another legacy model spelling elsewhere, add a focused compatibility object rather than weakening app-surface naming checks.

## 2026-06-24 Top-Bar Disconnect All Wiring

Overall grade after this slice: **A command architecture, A native/menu parity, A regression coverage**.

The macOS menu bar had a visible `Disconnect All` affordance, but it was permanently disabled and wired to no behavior. That was below the bar for Codex parity because it looked like a real command while providing no state transition, and it also meant active MCP server processes could only be stopped through the broader Stop All path.

What changed:
- Added `disconnect-all` to the shared command catalog, action planner, command executor, native icon catalog, SwiftUI/HTML top-bar overflow projection, desktop menu-bar planner, and desktop controller.
- Made Disconnect All state-derived: enabled for active MCP servers or a selected SSH Remote project, hidden from the quiet workspace top-bar overflow until actionable, and disabled in the native menu when no connection-like state exists.
- Reused one `WorkspaceModel` active-work stop helper for Stop All and Disconnect All so composer sends, terminal runs, terminal entries, and MCP server processes cannot drift between commands.
- Kept SSH Remote semantics explicit: Disconnect All detaches the selected remote project and terminal context without removing the saved project, because SSH remote execution is currently noninteractive per-command rather than a persistent socket.
- Mirrored the behavior in the Playwright harness and tightened keywords so `>ssh` still finds the Add SSH Remote command without being polluted by Disconnect All.
- Added focused Swift tests for command availability, action planning, icon coverage, remote detach behavior, HTML overflow visibility, MCP lifecycle shutdown, and native menu-bar non-regression.

Remaining risk:
- QuillCloud relay sessions and future persistent remote transports will need their own disconnect lifecycle. The current command is ready for that because it already sits behind the shared command/action/executor path, but today it only stops MCP servers and detaches SSH Remote context.

## 2026-06-24 Model Picker Surface Integration Split

Overall grade after this slice: **A test ownership, A conflict reduction, A parity guard**.

`WorkspaceSurfaceTests.swift` still owned model-picker integration cases even though model picker construction, filtering, and DTO compatibility had already been split into focused app tests. That kept a large, frequently edited catch-all file in the path of model naming and top-bar work.

What changed:
- Added `WorkspaceModelPickerSurfaceIntegrationTests` for workspace-state coverage of model category grouping, search, unknown selected models, recent/favorite ordering, and badge metadata.
- Removed the same coverage from `WorkspaceSurfaceTests.swift`.
- Left older payload decoding in `QuillCodeTopBarSurfaceTests`, where the `ModelOptionSurface` Codable contract lives.
- Added a top-bar parity guard that fails if these cases drift back into the broad workspace surface suite.

Remaining risk:
- `WorkspaceSurfaceTests.swift` is still large because it covers command, sidebar, browser, memory, activity, and automation projections. Keep extracting feature-family integration suites when a family has enough related tests and active parallel work.

## 2026-06-24 HTML Chrome Renderer Test Split

Overall grade after this slice: **A test ownership, A merge-conflict reduction, A renderer smoke coverage**.

`WorkspaceSurfaceTests.swift` still owned a broad block of static HTML renderer smoke tests. The first half of that block covers app chrome and global transcript scaffolding rather than generic workspace surface projection, so it made the catch-all suite more likely to conflict with active sidebar, top-bar, composer, and HTML harness work.

What changed:
- Added `WorkspaceHTMLChromeRendererTests` for static HTML primary-region labels, escaping, top-bar overflow, active-send stop markup, multiline composer markup, context banners, runtime issues, and sidebar pinned/today/archive grouping.
- Removed those HTML chrome tests from `WorkspaceSurfaceTests.swift`.
- Added `ParityHTMLGateTests` to keep the coverage in the focused suite.

Remaining risk:
- `WorkspaceSurfaceTests.swift` still owns HTML tool-card, terminal, browser, extensions, memories, and review-pane renderer tests. The next cleanup should split those by renderer family so HTML work can evolve with less conflict and clearer ownership.

## 2026-06-24 HTML Parity Gate Suite Split

Overall grade after this slice: **A architecture-gate ownership, A merge-conflict reduction, A regression guard**.

`ParityGateTests.swift` still owned pure HTML renderer delegation gates even after HTML chrome smoke coverage had moved into a focused suite. That made the broad architecture file more likely to conflict with parallel renderer work and made it harder to see which suite was responsible for HTML ownership rules.

What changed:
- Moved pure HTML renderer delegation gates for tool cards, top bar, terminal, secondary panes, review, transcript, and sidebar into `ParityHTMLGateTests`.
- Added a shared parity-test source helper and a guard that fails if those HTML renderer gates drift back into `ParityGateTests.swift`.
- Kept browser-specific HTML rendering gates in `ParityBrowserGateTests` and left mixed native/workspace/composer surface gates in the broad suite until they have a clearer focused home.

Remaining risk:
- `ParityGateTests.swift` is still large because it owns general app-surface and workspace-model boundaries. Continue extracting by feature family when a domain has multiple related gates and active development pressure.

## 2026-06-24 Browser Open Tool Parity

Overall grade after this slice: **A browser tool architecture, A agent/browser parity, A regression coverage**.

The browser feature had a product-level asymmetry: users could manually open browser previews and the agent could inspect the current page, but the agent could not navigate the browser itself. That left Codex-style browser workflows incomplete and encouraged future one-off routing if a model tried to inspect a page that had not already been opened by hand.

What changed:
- Added `host.browser.open` as a first-class browser tool definition with canonical `url` arguments and alias normalization for `address`, `href`, `target`, and `page`.
- Added `WorkspaceBrowserToolExecutor` so browser inspect and open route through one focused executor, reusing `WorkspaceBrowserWorkflow.openPreview` instead of branching in `WorkspaceModel`.
- Added a thin main-actor browser override bridge for agent runs so agent-driven browser navigation mutates the live SwiftUI/browser state while keeping the agent package UI-agnostic.
- Added mock-LLM intent coverage for “open/preview/go to” browser requests and concise final-answer formatting for opened pages.
- Added focused tests for browser-open routing, composer-driven browser navigation, TrustedRouter action parsing, core tool schema, and browser parity ownership.

Remaining risk:
- Agent-driven browser open currently gets the same static/metadata snapshot as manual open. Full Codex parity still needs a real live browser session adapter that can navigate, wait for dynamic pages, inspect DOM state, and share signed-in browser profiles behind the same `WorkspaceBrowserToolExecutor` boundary.

## 2026-06-24 HTML Tool-Card Renderer Test Split

Overall grade after this slice: **A renderer test ownership, A conflict reduction, A regression guard**.

`WorkspaceSurfaceTests.swift` still owned the static HTML tests for tool-card output, approval actions, artifacts, and preview rendering. Those cases exercise the HTML tool-card renderer and transcript ordering more than generic workspace surface projection, so keeping them in the broad suite made renderer work noisier and harder to review.

What changed:
- Added `WorkspaceHTMLToolCardRendererTests` for tool-card output, approval action markup, file/text artifacts, image previews, document previews, appshot previews, and transcript ordering.
- Removed the same cases from `WorkspaceSurfaceTests.swift`.
- Added a `ParityHTMLGateTests` guard that fails if these tool-card HTML cases drift back into the broad surface suite.

Remaining risk:
- `WorkspaceSurfaceTests.swift` still owns terminal, browser, secondary-pane, and review HTML renderer tests. Continue splitting those by renderer family in small slices.

## 2026-06-24 HTML Terminal Renderer Test Split

Overall grade after this slice: **A renderer test ownership, A conflict reduction, A regression guard**.

`WorkspaceSurfaceTests.swift` still owned terminal HTML renderer smoke coverage after the chrome and tool-card splits. Those tests assert terminal pane markup, command rows, clear controls, and running/stopped status classes, which are terminal-renderer concerns rather than broad workspace surface projection.

What changed:
- Added `WorkspaceHTMLTerminalRendererTests` for visible terminal pane rendering and running/stopped terminal entry labels.
- Removed the same terminal HTML cases from `WorkspaceSurfaceTests.swift`.
- Added a `ParityHTMLGateTests` guard that fails if those terminal HTML cases drift back into the broad surface suite.

Remaining risk:
- `WorkspaceSurfaceTests.swift` still owns browser, secondary-pane, and review HTML renderer tests. Keep splitting those by renderer family in small slices while the HTML harness evolves.

## 2026-06-24 HTML Review Renderer Test Split

Overall grade after this slice: **A renderer test ownership, A conflict reduction, A regression guard**.

`WorkspaceSurfaceTests.swift` still owned static review-pane HTML smoke coverage after the chrome, tool-card, and terminal splits. That case asserts `WorkspaceHTMLReviewRenderer` markup and review action data attributes more than broad workspace surface projection.

What changed:
- Added `WorkspaceHTMLReviewRendererTests` for review pane, file, action, hunk, line, comment, and stage/restore action markup.
- Removed the same review HTML case from `WorkspaceSurfaceTests.swift`.
- Added a `ParityHTMLGateTests` guard that fails if the review HTML case drifts back into the broad surface suite.

Remaining risk:
- `WorkspaceSurfaceTests.swift` still owns browser and secondary-pane HTML renderer tests. Continue splitting those by renderer family in small slices while the HTML harness evolves.

## 2026-06-24 Browser Inspection Depth Contract

Overall grade after this slice: **A browser inspection contract, A regression coverage, B+ overall app architecture**.

The browser surface had one subtle contract problem: local static HTML files and fetched HTTP(S) HTML pages both reported `static_html_snapshot`. That made the current preview look more complete than it is and left no stable vocabulary for the next native WebView/live DOM adapter. The model, SwiftUI surface, Playwright harness, and tool JSON now distinguish the source and depth of browser inspection.

What changed:
- Added explicit browser inspection depth cases for `network_html_snapshot` and future `live_dom_snapshot`.
- Let `BrowserHTMLSnapshotBuilder` receive the intended depth from callers instead of hardcoding static HTML.
- Made fetched web/localhost pages report `Network HTML snapshot`, while local `.html` files remain `Static HTML snapshot` and metadata-only pages remain unchanged.
- Added Swift and Playwright coverage for the new labels and raw values.
- Updated the browser decision note so it does not overclaim live DOM or WebView support.

Current strict grades:
- `QuillCodeCore`: **A**. Data models are explicit, Codable-compatible, and well tested. Continue guarding enum raw values and older payload decoding.
- `QuillCodeTools`: **A-**. Tool executors are bounded and mostly focused. The large tool test suite still needs family splits for lower merge pressure.
- `QuillCodeSafety`: **A-**. The policy/model boundary is clear. More live TrustedRouter reviewer telemetry and denial/clarify UX tests are still needed.
- `QuillCodeAgent`: **A-**. Streaming, parsing, argument recovery, and final-answer formatting are mostly separated. Mock intent planning is still broad and should not absorb more product logic.
- `QuillCodePersistence`: **A**. Path/config/thread/secret concerns are cleanly isolated with direct tests.
- `QuillComputerUseKit`: **B+**. macOS status and primitives are isolated, but Linux adapter parity and permission/approval UX remain incomplete.
- `QuillCodeApp`: **B+**. Many feature boundaries have been split out, but `WorkspaceModel.swift` is still the central architectural risk because it coordinates project, thread, terminal, browser, automation, memory, tool, and persistence side effects.
- `quill-code-desktop`: **A-**. Native app/menu-bar coordination is in good shape; remaining risk is richer lifecycle handling for long-running agent/router/browser processes.
- `E2E harness`: **A-**. It exercises core UX flows well and catches UI drift, but duplicated Swift/harness display strings remain a maintenance risk.

Remaining risk:
- This is still not an A+ whole repo. The top priorities are shrinking `WorkspaceModel.swift`, splitting the largest mixed test files, introducing a real browser session/live DOM adapter, and reducing duplicated UI constants between Swift and the HTML harness.

## 2026-06-24 HTML Secondary Pane Renderer Test Split

Overall grade after this slice: **A renderer test ownership, A conflict reduction, A regression guard**.

`WorkspaceSurfaceTests.swift` still owned Extensions and Memories static HTML coverage after the other HTML renderer splits. Those cases assert `WorkspaceHTMLSecondaryPaneRenderer` markup rather than broad workspace surface projection, so keeping them in the broad suite made renderer work more conflict-prone.

What changed:
- Added `WorkspaceHTMLSecondaryPaneRendererTests` for Extensions and Memories pane HTML smoke coverage.
- Removed the same secondary-pane HTML cases from `WorkspaceSurfaceTests.swift`.
- Added a `ParityHTMLGateTests` guard that fails if those secondary-pane cases drift back into the broad surface suite.

Remaining risk:
- Browser HTML coverage still has its own active browser ownership path because browser preview/inspection state is broader than secondary-pane rendering. Keep browser-specific tests in browser-focused suites instead of mixing them into this secondary-pane split.

## 2026-06-24 Workspace Surface Parity Gate Split

Overall grade after this slice: **A test ownership, A merge-conflict reduction, A regression guard**.

`ParityGateTests.swift` had become the largest Swift file in the repository and still owned a broad block of workspace-surface gates covering secondary panes, composer chrome, terminal panes, review panes, transcript contracts, and review action planning. Those checks are important, but keeping them in the generic suite made active UI and surface-contract work noisier for parallel agents.

What changed:
- Added `ParityWorkspaceSurfaceGateTests` for workspace secondary-pane, composer, terminal, review, and transcript surface ownership gates.
- Removed the same 11 gates from `ParityGateTests.swift`, reducing the broad suite from 2,199 lines to 1,941 lines.
- Updated the focused-suite meta-gate so workspace-surface gates cannot drift back into the broad architecture suite.

Current strict grades:
- `QuillCodeCore`: **A**. Stable data contracts and compatibility gates remain strong.
- `QuillCodeTools`: **A- at this slice**. Tool behavior was well bounded, but the broad tool test suite still needed follow-up ownership splits; the 2026-06-25 tool-test slices below retired that catch-all.
- `QuillCodeSafety`: **A-**. Policy boundaries are cleaner than earlier; live Auto-review telemetry and UX coverage still need depth.
- `QuillCodeAgent`: **A-**. Good parser/streaming/final-answer splits; mock intent planning should continue shrinking by feature family.
- `QuillCodePersistence`: **A**. Persistence boundaries remain clean.
- `QuillComputerUseKit`: **A-**. macOS and Linux helper-backed adapters are isolated; app-approval parity and richer visual verification remain open.
- `QuillCodeApp`: **B+**. Surface test ownership improved, but `WorkspaceModel.swift` is still the largest production risk.
- `quill-code-desktop`: **A-**. Native lifecycle surfaces are good; richer long-running process control still pending.
- `E2E harness`: **A-**. Coverage is valuable, but the HTML harness and Playwright spec still need more modularization.

Remaining risk:
- This is still not an A+ whole repo. Next highest-leverage steps are extracting another `WorkspaceModel` workflow boundary, adding a real browser session/live DOM adapter, and continuing to reduce duplicated Swift/HTML harness display contracts.

## 2026-06-24 Workspace Automation Model API Extraction

Overall grade after this slice: **A- model decomposition, A behavior preservation, A regression guard**.

`WorkspaceModel.swift` still owned the full automation scheduling and run orchestration API even though automation state reduction, draft creation, surface projection, and integration coverage already lived in focused files. That kept the main model larger than necessary and made future automation work more likely to conflict with unrelated project/thread/browser changes.

What changed:
- Added `WorkspaceModelAutomations.swift` for the public automation model API: set, create, schedule, run, due-run, status update, and delete.
- Kept public model state read-only outside the model while exposing narrow internal helpers for automation extension side effects: project lookup, thread insertion, project context refresh, automation persistence, error copy, and top-bar refresh.
- Updated the parity gate so reducer calls are expected in the focused automation extension and automation scheduling/run APIs cannot drift back into `WorkspaceModel.swift`.

Current strict grades:
- `QuillCodeCore`: **A**. Automation models and recurrence records remain explicit and isolated.
- `QuillCodeApp`: **B+/A-**. `WorkspaceModel.swift` dropped from 1,821 to 1,528 lines, but it is still the largest production coordination file and needs additional workflow extraction.
- Automation architecture: **A-**. API orchestration, pure state reduction, and draft construction now have clearer ownership; a future pass should extract another non-automation workflow before widening automation behavior.

Remaining risk:
- `WorkspaceModel.swift` still coordinates many side-effect families. Continue shrinking it through focused extensions or coordinators with parity gates, without broadening public state mutability.

## 2026-06-24 Shell Tool Executor Test Split

Overall grade after this slice: **A test ownership, A fixture reuse, A merge-conflict reduction**.

`ToolTests.swift` mixed shell, SSH shell request construction, file, patch, git, GitHub PR, and router coverage in one large suite. Shell behavior changes are common and can be reviewed independently, so keeping shell and SSH shell executor cases in the broad suite created unnecessary conflict pressure.

What changed:
- Added `ShellToolExecutorTests` for blocking shell, cancellable shell, streaming shell, timeout, and SSH shell request coverage.
- Moved reusable temp directory, git repo, fake GitHub CLI, and fake SSH fixtures into `ToolTestSupport`.
- Added a parity gate so shell executor cases and shared tool fixtures do not drift back into the broad mixed suite.

Remaining risk:
- `ToolTests.swift` still contains several tool families. The next low-risk split should move file/patch or GitHub PR coverage into focused suites before adding more tool behavior.

## 2026-06-24 Browser Live DOM Contract

Overall grade after this slice: **A- browser architecture, A adapter seam, A regression guard**.

The browser feature already had URL normalization, local HTML snapshots, fetched HTTP(S) snapshots, history, comments, and agent-facing inspection tools. The remaining architecture gap was that "live DOM" existed only as a future enum value and user-facing copy; there was no seam for a native WebView or signed-in browser adapter to provide rendered-page state without reaching into `WorkspaceModel`.

What changed:
- Added `BrowserLiveDOMCapturing` and `BrowserLiveDOMSnapshot` as the rendered-session adapter contract.
- Added `BrowserLiveDOMSnapshotBuilder` so rendered title, outline, viewport, and visible text are bounded and converted into the existing browser snapshot surface.
- Added workflow and reducer support for live DOM capture success/failure, including stale-request protection and graceful metadata fallback.
- Added model-level async refresh orchestration without platform branches or direct WebView dependencies.
- Added focused builder, engine, and integration tests proving `host.browser.inspect` reports `live_dom_snapshot` when a rendered-session capture exists.

Current strict grades:
- `QuillCodeCore`: **A**. Browser inspection depth contracts remain stable and explicit.
- `QuillCodeApp browser layer`: **A-**. Browser state, workflow, inspection, and adapter contracts are now cleaner. It is not A+ until a native rendered browser backend actually feeds this seam.
- `WorkspaceModel.swift`: **B+/A-**. The model gained only a narrow orchestration method, but it remains too large overall and still needs more workflow extraction.

Remaining risk:
- Native WebView/rendering, signed-in browser profile, and Linux/browser-process implementations are still pending. The new seam should make those additions isolated, but parity is incomplete until a real backend exercises the contract in app smoke tests.

## 2026-06-24 GitHub Pull Request Tool Test Split

Overall grade after this slice: **A test ownership, A fixture reuse, A merge-conflict reduction**.

`ToolTests.swift` still mixed unrelated file, patch, git, GitHub PR, worktree, and router behavior after the shell split. GitHub PR command construction changes are frequent and carry their own input-validation and fake-`gh` fixture needs, so keeping them in the catch-all suite made future PR workflow work harder to review.

What changed:
- Added `GitHubPullRequestToolExecutorTests` for PR create/view/checks/diff/checkout/reviewer/label/comment/review/merge behavior, shared PR input/output helper coverage, and PR-specific router dispatch.
- Replaced repeated fake-`gh` setup and argument-file parsing with one small `GitHubCLIFixture`.
- Removed the same PR-specific tests from `ToolTests.swift`.
- Added a parity gate so GitHub PR coverage does not drift back into the mixed tool suite.

Remaining risk:
- `ToolTests.swift` is smaller but still owns several tool families. Next low-risk splits should move file/patch, local git, worktree, or generic router coverage into focused suites before adding more tool behavior.

## 2026-06-24 Desktop Browser Live DOM Adapter

Overall grade after this slice: **A- browser backend, A boundary preservation, A regression guard**.

The browser live-DOM work had a clean shared contract, but the desktop app still only fetched static HTTP(S) HTML. That made the architecture look better than the shipped capability: dynamic pages could not be inspected as rendered DOM in the native app.

What changed:
- Added `DesktopBrowserLiveDOMCapturer`, a macOS desktop adapter that renders HTTP(S) pages in an offscreen non-persistent `WKWebView`.
- Captures final URL, title, viewport, bounded visible text, bounded outline, and bounded rendered HTML through one JSON-returning JavaScript evaluation.
- Wired the desktop preview task to fetch the network HTML snapshot first, then opportunistically upgrade it with rendered live DOM through `refreshRenderedBrowserSnapshot`.
- Added a desktop parity gate proving WebKit/JavaScript details stay in the focused adapter and do not leak into `QuillCodeDesktopController`.

Current strict grades:
- `QuillCodeApp browser layer`: **A-**. The model/workflow/engine remain platform-free and now have a real desktop caller for the live-DOM path.
- `quill-code-desktop browser backend`: **A-**. Rendered DOM capture exists and is bounded. It is not A+ until it supports reusable signed-in browser profiles and a native visible WebView session instead of one-shot offscreen capture.
- `WorkspaceModel.swift`: **B+/A-**. This slice did not grow the model; the main remaining architectural risk is still broad facade size.

Remaining risk:
- Signed-in browser profile reuse, richer browser session controls, and Linux/browser-process capture remain deferred. Native smoke tests should exercise this adapter against a real local web app before marking browser parity complete.

## 2026-06-24 Persistent Desktop Browser Profile

Overall grade after this slice: **A- browser profile seam, A boundary preservation, B+ product completeness**.

The desktop rendered-DOM adapter worked, but it used a non-persistent WebKit data store for every capture. That kept the implementation privacy-conservative, but it also blocked a core Codex browser expectation: inspecting pages whose rendered state depends on cookies or login/session storage.

What changed:
- Added `DesktopBrowserLiveDOMProfile` with explicit `.persistent` and `.ephemeral` modes.
- Made `DesktopBrowserLiveDOMCapturer` default to `.persistent`, backed by `WKWebsiteDataStore.default()`, so offscreen rendered captures can reuse WebKit cookie/session state across pages and launches.
- Kept `.ephemeral` available as an explicit mode for future test fixtures, privacy toggles, or one-shot isolated captures.
- Extended the desktop parity gate so persistent profile support cannot silently regress to always-non-persistent captures.

Current strict grades:
- `quill-code-desktop browser backend`: **A-**. It now has bounded live DOM capture plus persistent WebKit session reuse by default.
- Browser product parity: **B+**. A visible signed-in browser/login surface and reusable visible browser sessions are still required before this feels like full Codex browser parity.

Remaining risk:
- The persistent profile path is compile- and source-gated, but it still needs an interactive smoke path where the user signs into a site through a visible WebKit/browser surface and later `host.browser.inspect` proves the captured DOM reflects that session.

## 2026-06-24 Visible Desktop Browser Session

Overall grade after this slice: **A- browser session seam, A adapter isolation, B+ browser product completeness**.

Persistent rendered-DOM capture is only useful for signed-in pages if users have a visible way to create that browser state. Before this pass, the offscreen capture reused WebKit's default website data store, but there was no QuillCode-owned window where a user could sign into a site using that same profile.

What changed:
- Added `DesktopBrowserSessionPresenter`, an injectable desktop adapter that opens retained visible `WKWebView` session windows.
- Backed the visible session window with `WKWebsiteDataStore.default()` so cookies/session state are shared with offscreen live DOM capture.
- Made `WorkspaceBrowserLocationResolver` public and reused it from the desktop controller, avoiding a second URL parser for localhost, domains, files, and project-relative paths.
- Added an optional shared browser-pane `Session` action and a menu-bar `Open Browser Session` action. Non-desktop surfaces can omit the closure without carrying WebKit dependencies.
- Extended desktop parity gates to prevent visible browser sessions from becoming no-op buttons or leaking WebKit into `QuillCodeDesktopController`.

Current strict grades:
- `DesktopBrowserSessionPresenter.swift`: **A-**. It owns the platform-specific visible WebKit window, persistent data store, file loading, and retention lifecycle in one focused adapter.
- Browser preview/session architecture: **A-**. Address resolution is now shared, and controller code remains free of WebKit details.
- Browser product parity: **B+**. Users can sign into sites and then inspect with a shared persistent profile, but reusable tab management, session state display, and Linux browser-process capture remain pending.

Remaining risk:
- This is compile/source-gated and should be followed by a native smoke test that opens the session window, signs into or sets a cookie on a local test page, then verifies `host.browser.inspect` sees rendered signed-in DOM through the persistent profile.

## 2026-06-24 Approval Card Edit Action

Overall grade after this slice: **A approval UX seam, A planner/model boundary, A regression guard**.

The approval-card implementation had reached a usable Run/Skip state, but it still forced a binary decision. That is not good enough for a Codex-style workflow: users often want to correct a nearly-right command or path before it runs, and forcing them to copy raw JSON or retype the command makes safe execution feel brittle.

What changed:
- Added a first-class `edit` tool-card action alongside `approve` and `deny`.
- Added an Edit action to ready approval cards, keeping hard-denied cards blocked with no override button.
- Extended `WorkspaceApprovalActionPlanner` so Run/Skip create approval decisions while Edit only produces a composer draft.
- Kept `WorkspaceModel` as the side-effect owner: it applies the draft, executes approved tools, or records skipped decisions, but it does not own request lookup or draft construction.
- Added focused planner, workspace integration, transcript surface, HTML renderer, and parity-gate coverage.

Current strict grades:
- `WorkspaceApprovalActionPlanner.swift`: **A**. The action semantics are now explicit and pure. It can still become A+ by moving generic non-shell draft copy into a reusable tool-call formatter if more edit surfaces need it.
- `WorkspaceModel.swift`: **B+/A-**. This pass did not grow the model much, and approval behavior stays delegated, but the file remains a broad facade that should keep shedding orchestration.
- Tool-card UX parity: **A-**. Approval cards now support Run/Edit/Skip. A later pass should add inline argument editing or a small command-edit sheet when the app has a richer command editor surface.

Remaining risk:
- The edit path preloads text into the composer instead of editing structured tool-call fields in place. That is a pragmatic, safe first step; full inline editing should be deferred until the command editor can preserve schema validation and safety-review context.

## 2026-06-24 Browser Session Command Surface

Overall grade after this slice: **A command routing, A parity guard, B+ browser product completeness**.

The visible browser session existed in the browser pane and native menu bar, but not in the Codex-style command palette. That made it discoverable only from two places and left the command vocabulary incomplete compared with Browser Back/Forward/Reload.

What changed:
- Added `Browser: Open session` to the workspace command catalog with the same browser-availability gate as the visible pane action.
- Routed the command through `WorkspaceViewCommandPlanner` as a typed `openBrowserSession` action instead of falling through to generic workspace command execution.
- Added a typed desktop command action so native command invocations can open the retained WebKit session without switching on raw command IDs in the controller.
- Extended unit and parity tests so the command cannot become unavailable, no-op, or stringly routed without failing CI.

Remaining risk:
- Browser session management is still one-window-per-request with shared persistent cookies. Reusable tab/session state and Linux/browser-process adapters remain the next product-completeness step.

## 2026-06-24 Whole Repo Code Grade

Overall strict grade: **B+/A- today, trending toward A**.

This pass graded the current `origin/main` tree after PR #298 by scanning every tracked source/test/doc file and reviewing the main architectural seams. The repo now has 288 production Swift files, 156 Swift test files, about 37.8k production Swift LOC, about 26.8k Swift test LOC, and 1066 listed XCTest cases. Production Swift remains free of ordinary `try!`, `as!`, and force-unwrap patterns. The codebase is much healthier than the early prototype state, but not yet A+ because the app layer is still large, Linux delivery is not proven, and several Codex-parity features are partial.

Module grades:

| Module | Grade | Notes |
| --- | --- | --- |
| `QuillCodeCore` | **A** | Compact value models and defaults. Good ownership of config, project, model, automation, and tool contracts. |
| `QuillCodeAgent` | **A-** | Strong parser/prompt/tool-step boundaries, streaming support, tool feedback loop, and recovery for malformed model actions. Not A+ until live-model UI smoke tests run routinely and prompt compliance is measured. |
| `QuillCodeTools` | **A-** | Good split across shell, file, git, GitHub PR, worktree, MCP, patch, and SSH executors. Remaining risk is breadth: more focused test-suite splits should continue before adding new tool families. |
| `QuillCodeSafety` | **B+/A-** | Clear static/model reviewer split and user-intent matching. Needs broader real-world safety fixtures, telemetry, and less phrase-table brittleness before A+. |
| `QuillCodePersistence` | **A-** | Small and direct JSON stores plus secret-store abstraction. Needs Linux Secret Service/libsecret smoke coverage before cross-platform A+. |
| `QuillComputerUseKit` | **B+** | Clean protocol and macOS backend seam. Product parity remains partial until Linux and richer permission/app-control flows are implemented. |
| `QuillCodeApp` | **B+/A-** | Many extracted planners/builders/surfaces are A-level, but the target still owns 26.8k LOC and `WorkspaceModel.swift` remains a 1.5k-line orchestration facade. Continue extracting workflow owners. |
| `quill-code-desktop` | **A-** | Desktop-specific adapters are now mostly isolated: sign-in, tasks, settings, copy, project import, browser sessions, and commands. Needs packaged native smoke coverage for A+. |
| `quill-code` CLI | **A-** | Small, understandable CLI. Its parity role is intentionally limited, but live/auth edge cases need more integration coverage. |
| Tests and parity gates | **A-** | 1066 tests and source-boundary parity gates are a major strength. Biggest weakness is huge catch-all parity suites, especially `ParityGateTests.swift`, which should keep splitting by feature area. |
| E2E harness | **B+** | Useful Playwright/static harness and polish checks. Needs more live mock-LLM UI flows around browser session, tool approvals, search focus, and model picker before A-level UI confidence. |
| Docs/decisions | **A-** | Strong architectural memory through `DECISIONS`, `CODEX_PARITY_MATRIX`, `ROADMAP`, and this audit. Needs a generated or checklist-backed release status for public contributors. |

Hotspot file grades:

| File/family | Grade | Notes |
| --- | --- | --- |
| `WorkspaceModel.swift` | **B** | Mostly delegates to focused engines now, but it still coordinates browser, threads, projects, terminal, MCP, worktrees, memories, automations, and persistence in one actor. It should become thinner through feature-specific coordinators. |
| `WorkspaceSwiftUIView.swift` | **A-** | Down to a reasonable shell size and routes typed actions. Keep resisting command-ID switches and feature-specific view logic here. |
| `QuillCodeDesignSystem.swift` | **A-** | Good shared primitives for hit targets, press feedback, surfaces, palette, and motion. Needs a richer token system if more platform skins arrive. |
| Command palette/catalog/planner files | **A** | Well factored by command family, typed planner actions, and parity tests. This is one of the best current architecture seams. |
| Agent action parsing and normalization | **A-** | Explicit JSON contract, alias normalization, empty shell rejection, and conservative prose recovery. This pass trims and drops empty array-valued aliases so reviewer/label commands cannot carry blank values. |
| `AgentRunner`/tool-step runner | **A-** | Multi-step tool loop is clear and bounded. Needs more cancellation and concurrent-progress stress tests before A+. |
| Browser workflow/session files | **A-/B+ product** | Good separation between app state, resolver/workflow, desktop WebKit adapters, and command surfaces. Reusable session lifecycle and Linux/browser-process support remain product gaps. |
| MCP runtime/prober files | **A-** | Strong ownership split across DTOs, codec, prober, result mapping, runtime, and catalog. Needs broader malicious/slow MCP server integration fixtures. |
| `ParityGateTests.swift` | **B** | Valuable but too large at 1.9k lines. It should keep splitting into narrower parity suites so failures point directly to the violated boundary. |
| Large integration suites | **A-/B+** | Good behavior coverage with recent surface, remote-project, and agent-test splits. Remaining oversized hotspots include `TrustedRouterAdapterTests`, `WorkspaceAutomationIntegrationTests`, and the broad Playwright core spec. |

Immediate cleanup done in this pass:
- Trim and drop empty string entries from array-valued normalized tool arguments. This keeps PR reviewer/label aliases canonical after validation instead of preserving blank model output.
- Extended TrustedRouter adapter tests so reviewer and label aliases prove trimming and blank removal.

Recommended next A+ work:
- Split `WorkspaceModel` by workflow side-effect owners: browser coordinator, MCP coordinator, automation coordinator, and thread/project coordinator.
- Split `ParityGateTests.swift` and `WorkspaceSurfaceTests.swift` along the same feature boundaries.
- Add repeatable live/mock UI smoke tests for search typing, command palette execution, model picker, approval Run/Edit/Skip, visible browser session, and first-run auth.
- Add packaged native smoke tests for macOS desktop and a Linux build target/adapters check. The package currently declares macOS as the only platform even though the product goal is macOS plus Linux.
- Keep every feature slice on merge-train PRs with a focused test list and audit entry.

## 2026-06-24 Reusable Desktop Browser Session

Overall grade after this slice: **A- browser session UX, A adapter boundary, B+ browser product completeness**.

The visible browser session was wired correctly, but every Session/Menu/Command action created another WebKit window. That made sign-in flows feel noisy and put window lifecycle in the user's lap instead of making QuillCode's browser session feel like a stable Codex-style utility.

What changed:
- Changed `DesktopBrowserSessionPresenter` from a dictionary of retained windows to one reusable retained session window.
- Repeated opens now navigate and focus the existing WebKit session; closing the window clears the retained session so the next open recreates it cleanly.
- Kept focus, navigation, AppKit activation, and WebKit details inside the presenter adapter so `QuillCodeDesktopController` remains platform-lifecycle free.
- Extended the desktop parity gate so the presenter cannot silently regress to one retained window per click.

Current strict grades:
- `DesktopBrowserSessionPresenter.swift`: **A-**. The adapter now owns persistence, reuse, focus, navigation, and close cleanup in one focused file.
- Browser product parity: **B+**. A stable single signed-in browser session exists; multi-tab management, session state display, and Linux/browser-process adapters remain.

Remaining risk:
- This still needs an interactive native smoke test that opens a session, signs in or sets a cookie, focuses/navigates the existing window, and verifies rendered inspection reuses that profile.

## 2026-06-24 Workspace Model Parity Gate Split

Overall grade after this slice: **A focused gate ownership, A regression protection, B+ catch-all size**.

The catch-all parity suite still owned several workspace-model boundary checks, including tool-card surface contracts, UI state contracts, actionable review-card wiring, and execution-context enrichment. Those checks are valuable, but mixing them with repo-wide gates made failures harder to route and kept `ParityGateTests.swift` as a merge-conflict hotspot.

What changed:
- Added `ParityWorkspaceModelGateTests` for workspace-model boundary and surface-contract gates.
- Moved the first coherent model-boundary cluster out of `ParityGateTests.swift`.
- Extended the meta-gate so the focused workspace-model suite is required and the moved checks cannot drift back into the catch-all.

Current strict grades:
- `ParityWorkspaceModelGateTests.swift`: **A**. It gives model-boundary checks a clear owner and uses the shared parity support helpers.
- `ParityGateTests.swift`: **B+**. It is still broad, but smaller and better at acting as a top-level architectural gate registry.

Remaining risk:
- More workspace-model gates still live in the catch-all. Continue moving them by domain, especially project/thread lifecycle and MCP/tool execution boundaries, before adding new Codex-parity gates.

## 2026-06-24 Browser Session E2E Harness Pass

Overall grade after this slice: **A- browser-session harness coverage, A command parity guard, B+ browser product completeness**.

The native browser pane and desktop presenter exposed a visible persistent browser session, but the Playwright harness still tested only static browser preview/navigation. That left a gap where the pane Session button or `Browser: Open session` command could become disabled or no-op without the UI smoke suite noticing.

What changed:
- Added `Browser: Open session` to the Playwright harness command catalog with dynamic enablement.
- Added a visible Session control to the harness browser pane and matched native semantics: a typed address or current page can open a session.
- Recorded the resolved session URL and open count in the harness so tests can assert real state changes instead of only checking that a button exists.
- Extended the browser Playwright flow to open a session from the pane and from the command palette.

Remaining risk:
- This is still a deterministic HTML harness, not a packaged native WebKit smoke test. The next product-grade browser slice should automate a native app smoke run that opens a visible session, reuses its cookie profile, and verifies the same window is focused/navigated instead of duplicated.

## 2026-06-24 Workspace Thread Parity Gate Split

Overall grade after this slice: **A focused thread-boundary ownership, A regression protection, B+ catch-all size**.

The workspace-model suite owned the first surface and tool-card boundary cluster, but project/thread context, seed, creation, and lifecycle gates still lived in the broad parity file. Those checks all protect the same actor boundary: `WorkspaceModel` delegates thread/project record construction and mutation to focused engines.

What changed:
- Moved project context refresh, thread seed, thread creation, and thread lifecycle gates into `ParityWorkspaceModelGateTests`.
- Added a drift guard so thread lifecycle gates do not return to `ParityGateTests.swift`.
- Reduced the broad parity file again without changing app behavior.

Current strict grades:
- `ParityWorkspaceModelGateTests.swift`: **A**. It now owns the core workspace-model surface, context, and thread boundary checks.
- `ParityGateTests.swift`: **B+**. Still broad, but increasingly limited to cross-cutting and not-yet-extracted model boundaries.

Remaining risk:
- Configuration, retry, context resolving, MCP, and tool execution model gates still live in the catch-all. Continue extracting those by domain before adding more Codex-parity surface checks.

## 2026-06-24 Workspace Model Gate Drain

Overall grade after this slice: **A focused workspace-model gate ownership, A- suite maintainability, B+ catch-all size**.

After the thread split, the catch-all parity suite still owned the next contiguous model-boundary cluster: configuration, focused configuration integration ownership, retry, activity, status, context lookup, thread notice mutation, and agent-run update gates. That still made the broad suite a merge-conflict hotspot for parallel agents working near `WorkspaceModel` boundaries.

What changed:
- Moved the remaining contiguous workspace-model boundary cluster into `ParityWorkspaceModelGateTests`.
- Converted the top-level focused-suite guard to a table-driven check so future moved tests can be registered without another repeated assertion block.
- Added explicit drift guards for the moved workspace-model checks.

Current strict grades:
- `ParityWorkspaceModelGateTests.swift`: **A-**. The file now owns the first large set of workspace-model boundary checks, but should later split again by project/thread/config/activity once it gets too large.
- `ParityGateTests.swift`: **B+**. The catch-all is substantially smaller and more DRY, but it still owns later workspace-model gates for composer, slash commands, runtime, automation, worktrees, MCP, and execution overrides.

Remaining risk:
- Continue draining `ParityGateTests.swift` by feature family. The next clean split should move composer/send-session/tool-execution gates to a dedicated workspace execution gate suite.

## 2026-06-24 Workspace Execution Gate Split

Overall grade after this slice: **A focused execution-boundary ownership, A- merge-risk reduction, B+ catch-all size**.

The catch-all parity suite still owned workspace execution gates for composer cancellation/submission, agent send sessions, slash transcript and dispatch planning, command execution planning, tool event recording, tool-call routing, shell tool-call construction, and tool override composition. Those checks are all execution-boundary constraints, so keeping them in the broad suite made failures harder to triage and increased conflict pressure for parallel feature work.

What changed:
- Added `ParityWorkspaceExecutionGateTests` for workspace execution, command, slash-dispatch, and tool routing boundaries.
- Moved the coherent execution-boundary cluster out of `ParityGateTests.swift`.
- Extended the focused-suite guard so execution gates cannot drift back into the catch-all.

Current strict grades:
- `ParityWorkspaceExecutionGateTests.swift`: **A**. The suite has a clear domain owner and keeps execution-path architecture checks close together.
- `ParityGateTests.swift`: **B+**. It is materially smaller and still useful as a top-level architecture registry, but it has more domains to drain.

Remaining risk:
- Memory, project metadata, local environment, automation, worktree, MCP, remote project, and review-runtime gates still live in the catch-all. Continue extracting by domain before adding more Codex-parity gates.

## 2026-06-24 Workspace Project Gate Split

Overall grade after this slice: **A focused project-boundary ownership, A merge-risk reduction, B+ catch-all size**.

After the execution split, the catch-all parity suite still mixed project metadata loading, project loader ownership, project extension integration, local/remote project flows, pull-request flows, and worktree handoff gates with unrelated memory, MCP, automation, sidebar, and surface checks. Those gates all protect project and remote-project ownership boundaries, so they now have a focused suite.

What changed:
- Added `ParityWorkspaceProjectGateTests` for project metadata, project loader ownership, project extension, project registry, remote project, pull request, and worktree gates.
- Moved the project-family gates out of `ParityGateTests.swift`.
- Extended the focused-suite guard so project-family gates cannot drift back into the catch-all.

Current strict grades:
- `ParityWorkspaceProjectGateTests.swift`: **A**. The suite is coherent, small, and directly tied to project/remote-project ownership boundaries.
- `ParityGateTests.swift`: **B+**. The file is smaller again, but still owns memory, MCP, automation, terminal, sidebar, and remaining surface-boundary gates.

Remaining risk:
- Continue splitting the broad parity file by remaining domains: memory, MCP, automation/terminal, sidebar, and final workspace-surface contracts.

## 2026-06-24 Workspace Memory Gate Split

Overall grade after this slice: **A memory-gate ownership, A drift protection, B+ catch-all size**.

After the project split, memory command orchestration and memory integration ownership still lived in the broad parity file. Those checks protect a user-visible behavior: memories should be persisted, summarized, deleted, and refreshed through focused engines rather than leaking file and transcript details back into `WorkspaceModel`.

What changed:
- Added `ParityWorkspaceMemoryGateTests` for memory orchestration and memory integration ownership gates.
- Registered the memory suite in the top-level parity guard so moved memory gates cannot drift back to the catch-all.
- Reduced the catch-all parity file again while leaving behavior unchanged.

Current strict grades:
- `ParityWorkspaceMemoryGateTests.swift`: **A**. Memory persistence, copy, and context-refresh boundaries now have a focused parity owner.
- `ParityGateTests.swift`: **B+**. Smaller, but still owns MCP, automation, terminal, sidebar, review/runtime, and remaining surface-boundary gates.

Remaining risk:
- Continue draining `ParityGateTests.swift` by feature family. Good next splits: MCP gates, automation/terminal gates, sidebar gates, and final workspace-surface gates.

## 2026-06-24 Workspace Integration Gate Split

Overall grade after this slice: **A integration-suite ownership, A merge-risk reduction, B+ catch-all size**.

After the memory split, the broad parity file still owned test-suite ownership gates for MCP, review, feedback/artifacts, runtime issues, thread lifecycle, slash commands, local environments, automations, terminal flows, and runtime factory coverage. Those gates all answer the same architecture question: focused integration suites should own behavior coverage instead of letting `WorkspaceModelTests` grow back into a large catch-all.

What changed:
- Added `ParityWorkspaceIntegrationGateTests` for integration-suite ownership checks.
- Moved the coherent integration-ownership cluster out of `ParityGateTests.swift`.
- Registered the new suite in the parity drift guard so these checks cannot return to the catch-all.

Current strict grades:
- `ParityWorkspaceIntegrationGateTests.swift`: **A**. It has one job: guard that behavior flows stay in focused integration suites.
- `ParityGateTests.swift`: **B+**. It is smaller and more registry-like, but still owns sidebar, MCP implementation, automation state, and final workspace-surface boundary gates.

Remaining risk:
- Continue extracting the remaining implementation-boundary clusters: sidebar, MCP support/runtime, automation state/surface, and final workspace surface contracts.

## 2026-06-24 Workspace Sidebar Gate Split

Overall grade after this slice: **A sidebar-boundary ownership, A merge-risk reduction, B+ catch-all size**.

After the integration split, sidebar concerns still lived in two different regions of the broad parity suite: model selection mutations and native/HTML row rendering near the middle, then sidebar surface/navigation contracts later. That made sidebar regressions harder to discover and increased conflict pressure for agents working on navigation UI.

What changed:
- Added `ParityWorkspaceSidebarGateTests` for sidebar selection, row actions, command presentation, project-list rendering, sidebar surface contracts, and navigation surface assembly.
- Moved the sidebar/navigation gates out of `ParityGateTests.swift`.
- Registered the new focused suite in the meta-gate so sidebar ownership checks stay together.

Current strict grades:
- `ParityWorkspaceSidebarGateTests.swift`: **A**. It has a cohesive UI/navigation boundary and covers both native and HTML sidebar surfaces.
- `ParityGateTests.swift`: **B+**. It is now under 800 lines and more clearly a global architecture registry, but still owns MCP implementation, automation state/surface, and final workspace-surface contracts.

Remaining risk:
- Split the remaining broad suite by feature family: MCP implementation gates, automation gates, and final workspace surface/view gates.

## 2026-06-24 MCP Parity Gate Split

Overall grade after this slice: **A MCP-gate ownership, A drift protection, B+ catch-all size**.

After the workspace integration and sidebar splits, MCP process/runtime ownership and MCP stdio prober decomposition were still in the broad parity file. Those checks protect plugin-style extension behavior and cross-process tool execution, so they now have a focused owner.

What changed:
- Added `ParityMCPGateTests` for workspace MCP runtime boundaries and stdio codec/result-mapper boundaries.
- Registered the MCP suite in the parity drift guard.
- Reduced `ParityGateTests.swift` again without changing product behavior.

Current strict grades:
- `ParityMCPGateTests.swift`: **A**. The suite has a clear domain owner covering MCP runtime boundaries and low-level stdio plumbing.
- `ParityGateTests.swift`: **B+**. Smaller, but still owns automation, terminal, review/runtime, and remaining surface-boundary gates.

Remaining risk:
- Continue draining `ParityGateTests.swift` by feature family. Good next splits: automation/terminal gates and runtime/review surface gates.

## 2026-06-24 Automation Parity Gate Split

Overall grade after this slice: **A automation-boundary ownership, A drift protection, B+ catch-all size**.

Automation model isolation and workspace automation state/surface boundaries were still mixed into the global parity registry. Those checks all protect the same feature family: scheduled runs, follow-ups, recurrence records, and automation-pane projection should stay in focused model, reducer, and surface-builder files.

What changed:
- Added `ParityAutomationGateTests` for automation core model isolation, workspace automation state mutation delegation, and automation surface building.
- Registered the automation suite in the parity drift guard.
- Reduced `ParityGateTests.swift` again without changing product behavior.

Current strict grades:
- `ParityAutomationGateTests.swift`: **A**. The suite has one cohesive feature boundary and covers core, model, and surface layers.
- `ParityGateTests.swift`: **B+**. Smaller and easier to merge, but still owns terminal, review/runtime, command, settings, and final workspace-surface gates.

Remaining risk:
- Continue draining `ParityGateTests.swift` by feature family. Good next splits: runtime/review surface gates, command/settings surface gates, and agent/TrustedRouter implementation gates.

## 2026-06-24 Runtime And Review Parity Gate Split

Overall grade after this slice: **A runtime/review ownership, A drift protection, B+ catch-all size**.

After the automation split, runtime issue building, runtime/execution context contracts, recovery routing, and native review-pane decomposition still lived in the broad parity file. Those checks protect the main coding workflow's failure recovery and diff-review surfaces, so they now have a focused suite.

What changed:
- Added `ParityWorkspaceRuntimeReviewGateTests` for native review pane decomposition, runtime issue building, runtime/execution context contracts, and runtime recovery planning.
- Registered the runtime/review suite in the parity drift guard.
- Reduced `ParityGateTests.swift` again without changing product behavior.

Current strict grades:
- `ParityWorkspaceRuntimeReviewGateTests.swift`: **A**. It has one coherent owner for runtime failure surfaces and review-pane decomposition.
- `ParityGateTests.swift`: **B+**. Smaller, but still owns command-surface, settings/sheet, TrustedRouter, agent-runner, and global hygiene gates.

Remaining risk:
- Continue draining `ParityGateTests.swift` by feature family. Good next splits: command-surface gates, native settings/sheet gates, and agent/TrustedRouter gates.

## 2026-06-24 Command Surface Parity Gate Split

Overall grade after this slice: **A command-surface ownership, A drift protection, B+ catch-all size**.

Command planning, command palette construction, and command surface contract checks were still mixed into the broad parity registry. Those checks all protect the same user-facing surface: slash/command-palette dispatch should stay in focused planner, catalog, builder, and ranker files instead of regressing into aggregate workspace views.

What changed:
- Added `ParityWorkspaceCommandGateTests` for workspace command planning, command surface building, and command palette contract boundaries.
- Registered the command suite in the parity drift guard.
- Reduced `ParityGateTests.swift` again without changing product behavior.

Current strict grades:
- `ParityWorkspaceCommandGateTests.swift`: **A**. The suite has one cohesive command-surface boundary and covers view routing, catalog construction, and palette ranking ownership.
- `ParityGateTests.swift`: **B+**. Smaller, but still owns settings/sheet, TrustedRouter, agent-runner, and global hygiene gates.

Remaining risk:
- Continue draining `ParityGateTests.swift` by feature family. Good next splits: native settings/sheet gates and agent/TrustedRouter gates.

## 2026-06-24 Settings And Sheet Parity Gate Split

Overall grade after this slice: **A settings/sheet ownership, A drift protection, B+ catch-all size**.

Native sheet presentation and settings-surface contracts were still in the broad parity registry after the command split. These checks protect the modal/settings UX boundary: the workspace shell should compose one sheet presenter, settings should keep draft state and permission cards focused, and aggregate surface builders should not own settings copy.

What changed:
- Added `ParityWorkspaceSettingsSheetGateTests` for workspace sheet presentation, focused settings views, and settings surface contracts.
- Registered the settings/sheet suite in the parity drift guard.
- Reduced `ParityGateTests.swift` again without changing product behavior.

Current strict grades:
- `ParityWorkspaceSettingsSheetGateTests.swift`: **A**. It owns one modal/settings UX boundary and keeps sheet wiring, settings draft state, and settings-surface copy together.
- `ParityGateTests.swift`: **B+**. Smaller, but still owns TrustedRouter, agent-runner, transcript/context-banner, and global hygiene gates.

Remaining risk:
- Continue draining `ParityGateTests.swift` by feature family. Good next splits: agent/TrustedRouter gates and transcript/context-banner gates.

## 2026-06-24 Transcript Surface Parity Gate Split

Overall grade after this slice: **A transcript-surface ownership, A drift protection, B+ catch-all size**.

Transcript layout, transcript Find, and context banner ownership were the last workspace UI surface gates in the broad parity registry. Those checks protect center-pane composition, not settings or command routing, so they now have their own focused suite.

What changed:
- Added `ParityWorkspaceTranscriptGateTests` for workspace center-pane, transcript Find, context banner, runtime issue, review, and tool-card placement boundaries.
- Registered the transcript suite in the parity drift guard.
- Reduced `ParityGateTests.swift` again without changing product behavior.

Current strict grades:
- `ParityWorkspaceTranscriptGateTests.swift`: **A**. It owns one center-pane transcript boundary and keeps transcript layout assertions away from settings and command suites.
- `ParityGateTests.swift`: **B+**. Smaller, but still owns TrustedRouter, agent-runner, core/project model boundaries, and global hygiene gates.

Remaining risk:
- Continue draining `ParityGateTests.swift` by feature family. Good next split: agent/TrustedRouter gates.

## 2026-06-24 Agent Router Parity Gate Split

Overall grade after this slice: **A agent/router ownership, A drift protection, A- catch-all size**.

Agent runner decomposition, mock LLM routing, stream parsing, tool-step execution, and TrustedRouter transport boundaries were the largest remaining feature family in the broad parity registry. They all protect the same runtime contract: model output should become structured, recoverable agent actions without transport files accumulating prompt, parsing, key resolution, or safety-review responsibilities.

What changed:
- Added `ParityAgentRouterGateTests` for final-answer formatting, mock LLM planning, agent streaming, tool-step execution, TrustedRouter action parsing, prompt building, API-key resolution, safety transport, and shared chat parameters.
- Registered the agent/router suite in the parity drift guard.
- Reduced `ParityGateTests.swift` again without changing product behavior.

Current strict grades:
- `ParityAgentRouterGateTests.swift`: **A**. It owns one cohesive agent/router boundary and keeps transport, parser, prompt, key, and tool-step checks together.
- `ParityGateTests.swift`: **A-**. It is now mostly global hygiene, docs, focused-suite registry, static safety policy, and core/project model boundary checks.

Remaining risk:
- Consider one final split for core/project model boundary checks, but the broad suite is now small enough to act as the global parity registry.

## 2026-06-24 Agent And TrustedRouter Parity Gate Split

Overall grade after this slice: **A agent ownership, A TrustedRouter ownership, A drift protection**.

The combined agent/router suite was a good step down from the broad parity registry, but it still coupled local agent-runner decomposition to TrustedRouter transport responsibilities. Splitting those domains makes ownership clearer for future runtime and provider work.

What changed:
- Replaced `ParityAgentRouterGateTests` with `ParityAgentGateTests` for agent runner, mock LLM, streaming, and tool-step boundaries.
- Added `ParityTrustedRouterGateTests` for action parsing, prompt building, API-key resolution, safety transport, and shared chat parameters.
- Updated the parity drift guard so the two domains cannot collapse back together.

Current strict grades:
- `ParityAgentGateTests.swift`: **A**. It owns local agent-runner decomposition without provider transport concerns.
- `ParityTrustedRouterGateTests.swift`: **A**. It owns provider transport, parsing, prompt, key, and safety-client boundaries.
- `ParityGateTests.swift`: **A-**. It remains a small global registry plus global hygiene and core model-boundary checks.

Remaining risk:
- Optional final split for core/project model boundary checks; otherwise the broad suite is now appropriately small.

## 2026-06-24 Safety And Core Model Parity Gate Split

Overall grade after this slice: **A safety-boundary ownership, A core-model ownership, A global registry shape**.

The last non-global checks in `ParityGateTests` covered static safety policy and core model decomposition. Those are separate architectural concerns: safety policy should guard the Auto-review fallback boundary, while core/project model checks should guard domain model ownership. Keeping them in focused suites makes the global parity suite a small registry plus hygiene gate instead of a mixed dumping ground.

What changed:
- Added `ParitySafetyGateTests` for static safety policy ownership and reviewer delegation.
- Added `ParityCoreModelGateTests` for tool schema/model and project model decomposition.
- Registered both suites in the parity drift guard.
- Reduced `ParityGateTests.swift` to global hygiene, docs presence, and focused-suite registration checks.

Current strict grades:
- `ParitySafetyGateTests.swift`: **A**. It owns one safety policy boundary and directly guards the hard-deny and user-intent delegation points.
- `ParityCoreModelGateTests.swift`: **A**. It keeps core tool models and project models in one focused domain-boundary suite.
- `ParityGateTests.swift`: **A**. It is now an intentionally small global gate with no feature-specific architecture assertions.

Remaining risk:
- The focused-suite registry table is still hand-maintained. If it grows much further, move it into a data helper or manifest so the global gate stays declarative.

## 2026-06-24 Focused Suite Registry Helper

Overall grade after this slice: **A parity registry shape, A merge ergonomics, A global gate readability**.

After the safety/core split, `ParityGateTests` no longer owned feature-specific assertions, but it still carried the full focused-suite manifest inline. That made the global gate look heavier than its actual responsibility and created an easy merge hotspot for agents adding new parity slices.

What changed:
- Added `ParityFocusedSuiteRegistry` to own required parity test files and focused-suite test names.
- Updated `ParityGateTests` to consume the registry helper instead of carrying manifest data inline.
- Added a guard so the focused-suite registry data does not drift back into the global gate.

Current strict grades:
- `ParityFocusedSuiteRegistry.swift`: **A**. It has one data-manifest responsibility and no test execution logic.
- `ParityGateTests.swift`: **A**. It now reads as global hygiene plus registry enforcement, not a mixed feature/assertion dump.

Remaining risk:
- If the registry grows substantially again, the next step is a generated or declarative manifest file; for now a typed Swift helper is simple and keeps CI fast.

## 2026-06-24 Typed Focused Suite Manifest

Overall grade after this slice: **A+ manifest clarity, A+ Swift ergonomics, A global gate readability**.

The focused-suite helper removed the broad registry from `ParityGateTests`, but its tuple-shaped API still exposed file and test names as loosely related values. A tiny typed manifest makes the contract clearer: each focused parity suite has one file name and the tests it owns.

What changed:
- Replaced `ParityFocusedSuiteRegistry` with `ParityFocusedSuiteManifest`.
- Added a `Suite` value type so each parity suite's file name and test ownership stay together.
- Updated the global parity gate to iterate typed suite records while keeping required support and manifest files explicit.

Current strict grades:
- `ParityFocusedSuiteManifest.swift`: **A+**. It is structured, readable Swift data with one responsibility.
- `ParityGateTests.swift`: **A+**. It stays compact and reads as global hygiene plus manifest enforcement.

Remaining risk:
- The manifest is still maintained by hand, which is acceptable at this size. If parity suites continue to grow rapidly, move to a generated manifest with a validation script.

## 2026-06-24 Workspace Surface Test Ownership Split

Overall grade after this slice: **A activity surface ownership, A automation surface ownership, B+ broad workspace surface smoke**.

`WorkspaceSurfaceTests.swift` had become another mixed surface catch-all. It still provided good regression coverage, but activity-plan assertions and automation-pane assertions belonged with their focused integration suites. Moving those tests reduces the broad file's responsibility and makes failures route to the right owner faster.

What changed:
- Moved activity pane, authored plan, command toggle, and activity section-collapse coverage into `WorkspaceActivityIntegrationTests`.
- Added `WorkspaceAutomationSurfaceIntegrationTests` for automation pane visibility, configured automation rows, thread follow-up run actions, and creation commands.
- Removed the now-unused broad-surface agent import.

Current strict grades:
- `WorkspaceActivityIntegrationTests.swift`: **A**. It owns the activity surface plus plan update tool integration in one cohesive suite.
- `WorkspaceAutomationSurfaceIntegrationTests.swift`: **A**. It owns automation surface composition and command exposure without coupling to unrelated workspace smoke checks.
- `WorkspaceSurfaceTests.swift`: **B+**. Smaller and healthier, but still covers several surface families including sidebar, browser, memory, review, settings, and command palette.

Remaining risk:
- Continue splitting `WorkspaceSurfaceTests.swift` by feature family. Good next slices are browser/HTML preview ownership and settings/runtime issue surface ownership.

## 2026-06-24 Browser Surface Test Ownership Split

Overall grade after this slice: **A browser surface ownership, A HTML browser harness ownership, B+ broad workspace surface smoke**.

Browser parity now includes URL normalization, local/web snapshots, comments, live-DOM snapshot fallbacks, agent browser tools, native surface state, and static HTML rendering. Two browser surface assertions still lived in `WorkspaceSurfaceTests.swift`, which made browser regressions look like generic workspace smoke failures.

What changed:
- Moved browser preview surface-state coverage into `WorkspaceBrowserIntegrationTests`.
- Moved static HTML browser-pane renderer coverage into `WorkspaceBrowserIntegrationTests`.
- Reduced `WorkspaceSurfaceTests.swift` below 1,000 lines while preserving the same assertions.

Current strict grades:
- `WorkspaceBrowserIntegrationTests.swift`: **A**. It owns browser workflow, agent browser tools, surface projection, and HTML harness checks in one cohesive browser parity suite.
- `WorkspaceSurfaceTests.swift`: **B+**. It is now smaller broad smoke coverage, but still owns several unrelated surface families including settings, runtime issue decoding, memory, extensions/MCP, review, command palette, and sidebar search.

Remaining risk:
- Continue splitting `WorkspaceSurfaceTests.swift` by feature family. Good next slices are settings/runtime surface ownership and review surface ownership.

## 2026-06-24 Sidebar Primary Action Parity

Overall grade after this slice: **A Codex alignment, A sidebar command ownership, A- visual density**.

The sidebar command presentation was well-factored, but it had drifted too quiet: only New chat was visible in the primary rail while Search, Plugins, and Automations were hidden behind Tools. The Codex reference makes those four actions visible because they anchor the first-read navigation, while lower-frequency utilities can stay in a compact footer.

What changed:
- Promoted Search, Plugins, and Automations into `QuillCodeSidebarCommandPresentation.primaryCommandIDs` beside New chat.
- Kept Command Palette, Terminal, Browser, Memories, and Activity in the compact Tools menu.
- Updated sidebar command presentation tests to lock the visible order, labels, symbols, HTML icon tokens, and test IDs.
- Updated the Playwright harness smoke flow so the rendered sidebar proves the primary rows are visible and the footer Tools menu only contains secondary utilities.
- Updated the static browser harness sidebar so it matches the shared Swift/HTML renderer contract.
- Updated the HTML chrome renderer regression to prove Search, Plugins, and Automations are primary rows and no longer duplicate inside Tools.
- Updated `docs/DECISIONS.md` so future agents do not re-hide the primary Codex navigation by following stale prose.

Current strict grades:
- `QuillCodeSidebarCommandPresentation.swift`: **A**. It remains a single presentation boundary for native and HTML sidebar command rows.
- `QuillCodeSidebarCommandPresentationTests.swift`: **A**. It now protects the Codex-like primary action rail and the compact secondary tools menu separately.
- `WorkspaceHTMLChromeRendererTests.swift`: **A**. It now guards the static renderer hierarchy directly, including the absence of duplicate Tools rows.
- `E2E/playwright/tests/core.spec.ts`: **A-**. The smoke harness now exercises the intended hierarchy, though future screenshot diffing would catch spacing regressions more directly.
- `E2E/harness/index.html`: **B+**. The static harness remains intentionally hand-authored, but this slice closes a visible drift point between the harness and shared renderer.
- `docs/DECISIONS.md`: **A-**. The chrome decision is current again, though the sidebar still needs rendered screenshot review for exact spacing and hierarchy.

Remaining risk:
- The native and HTML sidebar styles should get a visual pass after this structural change to ensure four primary rows feel calm rather than bulky in narrow windows.

## 2026-06-24 Settings Runtime Surface Test Ownership Split

Overall grade after this slice: **A settings/runtime ownership, A compatibility coverage, B+ broad workspace surface smoke**.

`WorkspaceSurfaceTests.swift` still owned settings defaults, TrustedRouter account copy, older Computer Use payload decoding, and older runtime issue decoding. Those assertions protect settings/runtime compatibility, not the broad aggregate workspace smoke surface, so failures routed to the wrong owner and kept the broad suite large.

What changed:
- Added `WorkspaceSettingsRuntimeSurfaceTests` for settings defaults, Computer Use command/status copy, TrustedRouter account labels, old Computer Use payload compatibility, and old runtime issue compatibility.
- Removed settings/runtime-specific assertions from `WorkspaceSurfaceTests.swift` while preserving the aggregate surface smoke checks.
- Removed the now-unused Computer Use import from the broad surface suite.
- Updated the stale sidebar hierarchy decision that still described Search, Plugins, and Automations as hidden secondary tools.

Current strict grades:
- `WorkspaceSettingsRuntimeSurfaceTests.swift`: **A**. It owns settings/runtime presentation compatibility without coupling to unrelated workspace surface behavior.
- `WorkspaceSurfaceTests.swift`: **B+**. It is smaller, but still owns several unrelated surface families including memory, extensions/MCP, review, command palette, and sidebar search.
- `docs/DECISIONS.md`: **A**. The sidebar hierarchy decisions now agree on the current Codex-like primary rail.

Remaining risk:
- Continue splitting `WorkspaceSurfaceTests.swift` by feature family. Good next slices are review surface ownership and memory/extensions surface ownership.

## 2026-06-24 Playwright Browser Spec Split

Overall grade after this slice: **A browser E2E ownership, A shared harness helper boundary, B+ broad Playwright core spec**.

The mock Playwright suite is valuable because it catches Codex-like UI regressions quickly, but `core.spec.ts` was still the owner for browser preview flows. That made browser failures look like global core failures and kept the largest spec file harder for parallel agents to edit safely.

What changed:
- Added `browser.spec.ts` for browser preview, session, navigation, comments, and chat-to-browser flows.
- Added `harness-helpers.ts` for shared harness URL and sidebar tool navigation helpers.
- Removed browser-specific E2E flows from `core.spec.ts` while keeping broad smoke and cross-feature flows there.
- Added a browser parity gate that enforces focused browser E2E ownership and registered `ParityBrowserGateTests` in the focused-suite manifest.

Current strict grades:
- `E2E/playwright/tests/browser.spec.ts`: **A**. It owns one browser surface area and keeps browser expectations reviewable.
- `E2E/playwright/tests/harness-helpers.ts`: **A**. It is tiny, typed, and avoids helper drift between focused specs.
- `E2E/playwright/tests/core.spec.ts`: **B+**. Smaller and healthier, but still owns many unrelated UI families. Continue splitting settings/runtime, review, terminal, extensions, and sidebar flows into focused specs.

Remaining risk:
- `E2E/harness/index.html` is still a single large static harness. Once the spec files are split by feature, the next larger A+ step is modularizing the harness state/render/event handlers by pane.

## 2026-06-24 Review Surface Test Ownership Split

Overall grade after this slice: **A review surface ownership, A dependency cleanup, B+ broad workspace surface smoke**.

`WorkspaceSurfaceTests.swift` still owned git-diff review surface summaries, review-comment attachment, and stale-diff hiding. Those assertions protect Codex-style review behavior and should fail beside the review action/comment integration tests, not inside the broad workspace smoke suite.

What changed:
- Moved latest completed diff summary, matching review comments, and failed latest diff hiding coverage into `WorkspaceReviewIntegrationTests`.
- Reduced `WorkspaceSurfaceTests.swift` from 876 lines to 742 lines while preserving the same assertions.

Current strict grades:
- `WorkspaceReviewIntegrationTests.swift`: **A**. It now owns review action execution, remote review actions, review-comment events, and review surface projection together.
- `WorkspaceSurfaceTests.swift`: **B+**. It is materially smaller, but still owns several unrelated surface families including memory, extensions/MCP, command palette, sidebar search, shortcuts, and context banners.

Remaining risk:
- Continue splitting `WorkspaceSurfaceTests.swift` by feature family. Good next slices are memory/extensions surface ownership and command/sidebar search ownership.

## 2026-06-24 Playwright Review Spec Split

Overall grade after this slice: **A review E2E ownership, A shared harness helper reuse, B+ broad Playwright core spec**.

The review and diff flows are central to Codex parity, but they were still embedded in `core.spec.ts`. Moving them to a focused review spec makes git diff, patch review, staging, hunk staging, review comments, and commit flows easier to maintain without forcing every UI agent to edit the same broad spec file.

What changed:
- Added `review.spec.ts` for review summary, apply-patch diff, file staging, hunk staging, and one-turn commit flows.
- Reused `harnessURL()` from the shared Playwright helper instead of rebuilding the file URL in each test.
- Removed review-specific E2E flows from `core.spec.ts`.
- Added a workspace surface parity gate that keeps those review flow names out of `core.spec.ts` and registered it in the focused-suite manifest.

Current strict grades:
- `E2E/playwright/tests/review.spec.ts`: **A**. It owns one review/git workflow area and keeps the assertions cohesive.
- `E2E/playwright/tests/core.spec.ts`: **B+**. It is smaller again, but still owns several unrelated UI families including terminal, extensions, sidebar, settings, and slash/workflow smoke coverage.
- `ParityWorkspaceSurfaceGateTests.swift`: **A**. It now guards both review surface architecture and focused review E2E ownership.

Remaining risk:
- Continue splitting `core.spec.ts` by feature family. Good next slices are terminal flows, extension/MCP flows, and settings/sidebar flows.

## 2026-06-24 Memory And Extensions Surface Test Ownership Split

Overall grade after this slice: **A memory ownership, A extensions/MCP ownership, B+ broad workspace surface smoke**.

`WorkspaceSurfaceTests.swift` still owned memory summary projection, project extension summary projection, and ready MCP probe summary projection. Those assertions protect feature-owned panes, not the broad workspace shell, and they also forced the broad suite to import `QuillCodeTools` only for MCP probe descriptors.

What changed:
- Moved memory summary and command-category assertions into `WorkspaceMemoryIntegrationTests`.
- Moved project extension summary and update-command assertions into `WorkspaceProjectExtensionIntegrationTests`.
- Moved ready MCP server probe summary and start/stop command assertions into `WorkspaceMCPIntegrationTests`.
- Added parity guards so those focused suites own the moved assertions and `WorkspaceSurfaceTests.swift` does not regain them.
- Reduced `WorkspaceSurfaceTests.swift` from 743 lines to 575 lines and removed its `QuillCodeTools` import.

Current strict grades:
- `WorkspaceMemoryIntegrationTests.swift`: **A**. It owns memory loading, `/remember`, agent memory writes, deletion, and memory pane projection together.
- `WorkspaceProjectExtensionIntegrationTests.swift`: **A**. It owns manifest loading, update behavior, update failure, and extension pane projection together.
- `WorkspaceMCPIntegrationTests.swift`: **A**. It owns MCP lifecycle, probe surface projection, agent calls, resources, prompts, and advertised-tool safety together.
- `WorkspaceSurfaceTests.swift`: **B+**. Smaller and no longer coupled to `QuillCodeTools`, but still owns command palette, sidebar search, shortcuts, context banners, and global shell smoke.

Remaining risk:
- Continue splitting `WorkspaceSurfaceTests.swift` by feature family. Good next slices are command/sidebar search ownership and context banner ownership.

## 2026-06-24 Playwright Terminal Spec Split

Overall grade after this slice: **A terminal E2E ownership, A shared harness helper reuse, B+ broad Playwright core spec**.

The integrated terminal flow exercises Codex-critical behavior: cwd display, command execution, streaming output, cwd persistence, environment persistence, cancellation, and clearing. It belonged in a terminal-specific E2E owner instead of the broad core smoke spec.

What changed:
- Added `terminal.spec.ts` for the integrated terminal execution flow.
- Reused `harnessURL()` and `clickSidebarTool()` from the shared Playwright helper.
- Removed the terminal-owned execution flow from `core.spec.ts` while leaving cross-feature terminal smoke paths in core.
- Added a workspace surface parity gate that keeps the terminal execution flow out of `core.spec.ts` and registered it in the focused-suite manifest.

Current strict grades:
- `E2E/playwright/tests/terminal.spec.ts`: **A**. It owns the terminal lifecycle behavior and uses shared helpers.
- `E2E/playwright/tests/core.spec.ts`: **B+**. Smaller again, but still owns unrelated extension/MCP, sidebar, settings, command palette, and slash/workflow coverage.
- `ParityWorkspaceSurfaceGateTests.swift`: **A**. It guards native terminal architecture plus focused terminal E2E ownership.

Remaining risk:
- Continue splitting `core.spec.ts` by feature family. Good next slices are extension/MCP flows and command/sidebar search flows.

## 2026-06-25 Command, Sidebar, And Context Surface Test Split

Overall grade after this slice: **A command ownership, A sidebar ownership, A context-banner ownership, A- broad workspace smoke**.

`WorkspaceSurfaceTests.swift` still owned command palette ranking, shortcut registry invariants, sidebar search behavior, sidebar bulk-action integration, composer slash suggestions, command-surface decode compatibility, and context-banner behavior. Those assertions each have focused owners now, so broad workspace smoke failures no longer mask command/sidebar/transcript regressions.

What changed:
- Moved sidebar search filtering into `QuillCodeThreadSidebarSurfaceTests`.
- Added `WorkspaceSidebarIntegrationTests` for model-level sidebar bulk selection archive/delete behavior.
- Added `WorkspaceShortcutRegistryTests` for shortcut label mapping and duplicate binding prevention.
- Moved command-surface decode compatibility into `WorkspaceCommandSurfaceBuilderTests`.
- Moved full slash suggestion filtering into `QuillCodeTranscriptSurfaceTests`.
- Moved context-banner surface command and hidden-state behavior into `WorkspaceContextBannerBuilderTests`.
- Added parity guards so the focused suites keep these responsibilities and `WorkspaceSurfaceTests.swift` does not regain them.
- Reduced `WorkspaceSurfaceTests.swift` from 575 lines to 274 lines.

Current strict grades:
- `WorkspaceCommandPaletteRankerTests.swift`: **A**. It owns command palette ranking, scoping, grouping, and public delegation.
- `WorkspaceShortcutRegistryTests.swift`: **A**. It owns shortcut registry invariants without coupling to workspace surface smoke.
- `QuillCodeThreadSidebarSurfaceTests.swift`: **A**. It owns sidebar search, grouping, selection labels, archive groups, and compatibility rows.
- `WorkspaceSidebarIntegrationTests.swift`: **A-**. It is intentionally small and focused on the model bridge for bulk sidebar actions.
- `WorkspaceContextBannerBuilderTests.swift`: **A**. It owns context estimation, banner copy, compatibility, and surface command enablement.
- `WorkspaceSurfaceTests.swift`: **A-**. It is now a broad assembly smoke suite plus a handful of high-level workspace checks.

Remaining risk:
- Continue reducing the largest integration files. Good next slices are `TrustedRouterAdapterTests.swift`, `WorkspaceAutomationIntegrationTests.swift`, and the remaining broad Playwright `core.spec.ts` flows.

## 2026-06-24 Search Input Stability

Overall grade after this slice: **A- native dialog typing stability, A focused search E2E coverage, B+ broad Playwright core spec**.

User-facing search and command-palette entry need to behave like Codex: open from visible chrome, take focus immediately, and keep accepting text while the workspace surface continues to update. The previous SwiftUI dialogs bound each keystroke directly to workspace-level sheet state, which was unnecessarily fragile because it let root surface churn participate in every input edit.

What changed:
- Search and command-palette dialogs now keep active keystrokes in local dialog state and sync outward only as a side effect.
- Native dialog focus now gets a second post-presentation tick so fields are still focused after sheet/menu animation settles.
- Both native fields expose stable accessibility identifiers for future native UI automation.
- Added `search.spec.ts` for chat-search typing from sidebar and top-bar entry points plus command-palette typing from the top-bar entry point.
- Hardened the HTML harness focus helper so menu-launched search/palette fields receive focus across the next frame and short timeout.
- Fixed the HTML harness generic `search` command path to call the same focused `openSearchPanel()` helper as the sidebar button instead of falling through to a plain render.
- Added parity guards for local native dialog typing state and focused Playwright search ownership.

Current strict grades:
- `QuillCodeSearchAndShortcutDialogs.swift`: **A-**. Search keeps local typing state and stable focus, but the search result row UI still shares the broad shortcut/dialog file.
- `QuillCodeCommandPaletteDialog.swift`: **A-**. Palette search keeps local typing state and stable focus; richer native keyboard regression tests are still pending.
- `E2E/playwright/tests/search.spec.ts`: **A**. It owns the user-visible search typing regression directly.

Remaining risk:
- Add packaged native UI smoke tests that drive `quillcode-search-input` and `quillcode-command-palette-input` directly once the desktop app has a stable automation harness.

## 2026-06-25 Remote Project Integration Test Split

Overall grade after this slice: **A remote setup/context ownership, A shell/git ownership, A file/patch ownership, A PR ownership, A worktree ownership**.

`WorkspaceRemoteProjectIntegrationTests.swift` had grown into a 1k-line suite covering five separate remote-project domains: SSH setup/context loading, remote shell/git execution, remote file/patch tools, remote GitHub PR tools, and remote worktree safety. That made unrelated SSH regressions look coupled and forced agents to scan too much unrelated setup before changing one remote workflow.

What changed:
- Kept SSH setup, context refresh, malformed address handling, and remote-safe tool advertisement in `WorkspaceRemoteProjectIntegrationTests.swift`.
- Moved remote shell, git status, commit, push, workspace git commands, and cwd normalization into `WorkspaceRemoteProjectShellGitIntegrationTests.swift`.
- Moved remote file write/read, unsafe path rejection, patch apply, and unsafe patch rejection into `WorkspaceRemoteProjectFilePatchIntegrationTests.swift`.
- Moved remote PR create/comment/review/merge/checkout/reviewer/label flows into `WorkspaceRemoteProjectPullRequestIntegrationTests.swift`.
- Moved remote worktree create and unsafe worktree path rejection into `WorkspaceRemoteProjectWorktreeIntegrationTests.swift`.
- Updated the project parity gate so these focused suites own their behavior and `WorkspaceModelTests.swift` stays free of remote-project integration coverage.
- Reduced `WorkspaceRemoteProjectIntegrationTests.swift` from 1037 lines to 172 lines.

Current strict grades:
- `WorkspaceRemoteProjectIntegrationTests.swift`: **A**. It now owns only SSH project setup, context refresh, parser rejection, and advertised remote-safe tool surface.
- `WorkspaceRemoteProjectShellGitIntegrationTests.swift`: **A**. It owns SSH command execution, git execution, current branch push behavior, and remote cwd normalization together.
- `WorkspaceRemoteProjectFilePatchIntegrationTests.swift`: **A**. It owns remote filesystem mutations and local preflight safety for path/patch escapes.
- `WorkspaceRemoteProjectPullRequestIntegrationTests.swift`: **A**. It owns remote GitHub CLI command construction through the SSH path.
- `WorkspaceRemoteProjectWorktreeIntegrationTests.swift`: **A**. It owns remote worktree creation plus pre-SSH path rejection.

Remaining risk:
- Continue reducing the largest broad files. Good next slices are `TrustedRouterAdapterTests.swift`, `WorkspaceAutomationIntegrationTests.swift`, and the remaining broad Playwright `core.spec.ts` flows.

## 2026-06-24 Playwright Extensions Spec Split

Overall grade after this slice: **A extension/MCP E2E ownership, A shared harness helper reuse, A- broad Playwright core spec**.

The project extension and MCP manifest flow exercises a full Codex extension surface: sidebar entry, plugin update commands, skill rows, MCP process start/stop, advertised tools, resources, prompts, and command-palette discovery. Keeping that in `core.spec.ts` made the broad smoke own too many unrelated feature families.

What changed:
- Added `extensions.spec.ts` for project extension manifests and MCP probe display.
- Reused `harnessURL()` and `clickSidebarTool()` from the shared Playwright helper.
- Removed the extension/MCP-owned flow from `core.spec.ts`.
- Added a workspace surface parity gate that keeps the extension flow out of `core.spec.ts` and registered it in the focused-suite manifest.

Current strict grades:
- `E2E/playwright/tests/extensions.spec.ts`: **A**. It owns extension and MCP manifest behavior with one cohesive flow.
- `E2E/playwright/tests/core.spec.ts`: **A-**. It is smaller, but still owns broad workspace smoke plus several feature families such as settings, composer, runtime issue recovery, automations, remote projects, and worktrees.
- `ParityWorkspaceSurfaceGateTests.swift`: **A**. It now guards review, terminal, search, and extension E2E ownership.

Remaining risk:
- Continue splitting `core.spec.ts` by feature family. Good next slices are settings/runtime issue flows and automation flows.

## 2026-06-25 Playwright Automation Spec Split

Overall grade after this slice: **A automation E2E ownership, A shared harness helper reuse, A- broad Playwright core spec**.

Automations are a major Codex parity surface, but the mock harness still kept thread follow-up, workspace schedule, quick-action scheduling, slash scheduling, recurring schedules, and Activity separation inside `core.spec.ts`. Those flows are cohesive and deserve a focused owner so automation changes do not require editing broad workspace smoke.

What changed:
- Added `automations.spec.ts` for automation pane separation, create/run/pause/delete, quick scheduling, slash scheduling, and recurring schedule behavior.
- Reused `harnessURL()` and `clickSidebarTool()` from the shared Playwright helper.
- Removed automation-owned lifecycle flows from `core.spec.ts`.
- Added an automation parity gate that keeps the flows in the focused spec and registered it in the focused-suite manifest.

Current strict grades:
- `E2E/playwright/tests/automations.spec.ts`: **A**. It owns automation lifecycle and scheduling behavior with one cohesive feature spec.
- `E2E/playwright/tests/core.spec.ts`: **A-**. It is smaller, but still owns broad workspace smoke plus feature families such as settings, runtime issues, command palette, worktrees, projects, and remote projects.
- `ParityAutomationGateTests.swift`: **A**. It now guards automation model ownership, surface building, and focused Playwright ownership.

Remaining risk:
- Continue splitting `core.spec.ts` by feature family. Good next slices are settings/runtime issue flows and worktree/project flows.

## 2026-06-25 Agent Behavior Test Split

Overall grade after this slice: **A immediate-action ownership, A tool-loop ownership, A streaming ownership, A mock PR ownership, A final-answer ownership**.

`AgentTests.swift` mixed agent intent heuristics, multi-step tool execution, streaming progress, transcript redaction, patch follow-up behavior, final-answer copy, git execution smoke, and mock PR parsing in one broad file. That made failures hard to triage and duplicated final-answer coverage that already had a focused owner.

What changed:
- Moved direct one-turn execution smoke tests into `AgentImmediateActionTests.swift`.
- Moved multi-step tool-loop, plan-update, repeated-tool fallback, environment redaction, and patch diff-refresh behavior into `AgentToolLoopTests.swift`.
- Moved progress and streaming-action behavior into `AgentStreamingTests.swift`.
- Moved deterministic mock PR planning assertions into `MockLLMClientPullRequestTests.swift`.
- Moved the remaining browser/patch final-answer copy assertions into `AgentFinalAnswerBuilderTests.swift` and removed duplicate openclaw/long-output assertions from the deleted broad suite.
- Added `AgentTestSupport.swift` for shared fake LLMs, streaming clients, progress recording, and temp git helpers.
- Added a parity gate that keeps the focused agent behavior suites present and prevents broad `AgentTests.swift` from regrowing.

Current strict grades:
- `AgentImmediateActionTests.swift`: **A**. It owns user-facing “just do it” smoke behavior for shell, file write, commit, and push.
- `AgentToolLoopTests.swift`: **A**. It owns bounded multi-tool orchestration, audit events, redaction, and follow-up diff refresh behavior.
- `AgentStreamingTests.swift`: **A**. It owns stream-to-progress behavior and draft assistant message finalization.
- `MockLLMClientPullRequestTests.swift`: **A**. It owns deterministic PR tool-call planning without coupling to runner orchestration.
- `AgentFinalAnswerBuilderTests.swift`: **A**. It now owns all final-answer copy cases in one place.
- `AgentTestSupport.swift`: **A-**. Shared fakes are compact and reusable; if agent test fixtures keep growing, split fake LLMs from filesystem helpers.

Remaining risk:
- `TrustedRouterAdapterTests.swift` is now the largest agent test hotspot. Split parser, prompt-builder, streaming, model-catalog, and key-resolution coverage when it is next touched.

## 2026-06-25 Playwright Settings And Runtime Spec Split

Overall grade after this slice: **A settings/runtime E2E ownership, A shared top-bar settings helper reuse, A- broad Playwright core spec**.

Settings and runtime recovery are their own Codex parity surface: TrustedRouter sign-in, runtime issue callouts, retry recovery, malformed model recovery, rate-limit diagnostics, and Computer Use permission setup. Keeping those in `core.spec.ts` made broad smoke changes touch unrelated auth/runtime behavior.

What changed:
- Added `settings.spec.ts` for Computer Use setup, TrustedRouter sign-in-needed recovery, network retry recovery, runtime diagnostics/redaction, malformed model recovery, and rate-limit recovery.
- Promoted `openTopBarOverflow()` and `openSettings()` into `harness-helpers.ts` so focused specs reuse the same top-bar navigation path.
- Removed settings/runtime-owned flows from `core.spec.ts`.
- Added a settings parity gate that keeps these flows in the focused spec and registered it in the focused-suite manifest.

Current strict grades:
- `E2E/playwright/tests/settings.spec.ts`: **A**. It owns runtime recovery and settings behavior with a cohesive feature boundary.
- `E2E/playwright/tests/harness-helpers.ts`: **A**. Shared top-bar and sidebar navigation helpers now keep focused specs DRY.
- `E2E/playwright/tests/core.spec.ts`: **A-**. It is smaller, but still owns broad workspace smoke plus command palette, worktrees, projects, and remote-project flows.
- `ParityWorkspaceSettingsSheetGateTests.swift`: **A**. It now guards native settings structure, local dialog typing, settings surface contracts, and focused Playwright ownership.

Remaining risk:
- Continue splitting `core.spec.ts` by feature family. Good next slices are command-palette/git/worktree flows and sidebar/project lifecycle flows.

## 2026-06-25 TrustedRouter Adapter Test Split

Overall grade after this slice: **A parser ownership, A streaming ownership, A prompt-builder ownership, A model-catalog ownership, A key-resolution ownership**.

`TrustedRouterAdapterTests.swift` mixed five behavior families in one 564-line suite: messy action JSON parsing, streaming collection/draft preview, prompt/message construction, model catalog normalization, and API-key resolution. These are all adjacent TrustedRouter integration concerns, but they fail for different reasons and should not require scanning one large file when tuning prompts, aliases, or transport behavior.

What changed:
- Moved action parsing, prose recovery, canonical tool arguments, PR aliases, and no-argument tool allowances into `TrustedRouterActionParserTests.swift`.
- Moved streamed action collection and visible assistant draft preview into `TrustedRouterStreamingActionTests.swift`.
- Moved system prompt, project instruction projection, memory projection, tool-feedback history, and history-limit behavior into `TrustedRouterPromptBuilderTests.swift`.
- Moved provider/category mapping and ranked recommended fallback dedupe into `TrustedRouterModelCatalogTests.swift`.
- Moved missing-key copy, override trimming, stored-key fallback, and actionable missing-key errors into `TrustedRouterAPIKeyResolverTests.swift`.
- Added a parity gate that keeps these focused suites present and prevents `TrustedRouterAdapterTests.swift` from regrowing.

Current strict grades:
- `TrustedRouterActionParserTests.swift`: **A**. It owns parser, normalizer, prose recovery, and tool-alias behavior together.
- `TrustedRouterStreamingActionTests.swift`: **A**. It owns stream assembly and visible assistant draft behavior without prompt/catalog noise.
- `TrustedRouterPromptBuilderTests.swift`: **A**. It owns prompt and message projection contracts, including project instructions, memories, tool feedback, and history limits.
- `TrustedRouterModelCatalogTests.swift`: **A**. It owns TrustedRouter catalog fallback and recommended-model dedupe.
- `TrustedRouterAPIKeyResolverTests.swift`: **A**. It owns key resolution and actionable missing-key behavior.

Remaining risk:
- The production TrustedRouter adapter boundaries are now well guarded. The next quality slices should target `WorkspaceAutomationIntegrationTests.swift`, remaining broad Playwright `core.spec.ts` flows, or another focused `WorkspaceModel` workflow extraction.

## 2026-06-25 New Chat Command Execution Boundary

Overall grade after this slice: **A command-plan completeness, A action-executor wiring, A regression coverage**.

`new-chat` was exposed through the sidebar command catalog and context warning banner, but it was explicitly invalid in `WorkspaceCommandPlan`. Native SwiftUI command handling sends most ordinary command IDs through the model command executor, so a surfaced `new-chat` button could silently no-op depending on which surface emitted it.

What changed:
- Added `WorkspaceCommandAction.newChat` so the command ID parses through the same command-plan path as other visible workspace actions.
- Added `WorkspaceCommandActionEffect.newChat` and executor handling that calls the existing `newChat()` model path, preserving selected-project/default mode/model behavior.
- Added focused tests for command parsing, action planning, and model execution.

Current strict grades:
- `WorkspaceCommandPlan.swift`: **A**. Static command IDs that are visible in UI now include the global new-chat action instead of requiring a special missing-command exception.
- `WorkspaceCommandActionPlanner.swift`: **A**. Context-free workspace actions include new-chat alongside terminal/browser/activity toggles.
- `WorkspaceCommandActionExecutor.swift`: **A**. New-chat uses the existing model lifecycle API rather than duplicating thread construction.
- `WorkspaceCommandPlanExecutorTests.swift`: **A**. It now catches visible command IDs that parse but fail to mutate model state.

Remaining risk:
- Continue auditing command IDs emitted by native-only surfaces. Any command that appears in a `WorkspaceCommandSurface` should either have an explicit view-planner presentation route or a model command plan with an execution test.

## 2026-06-25 Command Palette Playwright Locator Boundary

Overall grade after this slice: **A E2E interaction determinism, A shared command-palette helper reuse**.

The HTML mock harness intentionally re-renders the command palette as the query changes so it can model SwiftUI-style derived state. A focused extensions E2E test reused a command-palette input locator across two filters, which passed locally but exposed a CI race after main merged: the second query could miss the expected `toggle-extensions` row before the click wait timed out.

What changed:
- Added shared Playwright helpers that reacquire the current command-palette input, assert the entered query, and wait for an exact command row before clicking.
- Updated the extensions parity test to use those helpers for both the `>update github` discovery check and the `>extensions` navigation action.

Current strict grades:
- `E2E/playwright/tests/harness-helpers.ts`: **A**. Command-palette tests now have one deterministic query/click path.
- `E2E/playwright/tests/extensions.spec.ts`: **A**. The test still owns extension sidebar and command-palette parity without relying on stale input element handles.

Remaining risk:
- Migrate other command-palette specs to the shared helpers opportunistically as they are touched, especially broad `core.spec.ts` command-palette flows.

## 2026-06-25 Playwright Sidebar And Project Spec Split

Overall grade after this slice: **A sidebar/project E2E ownership, A focused helper locality, A- broad Playwright core spec**.

`core.spec.ts` still owned thread search/reopen, sidebar new-chat behavior, chat lifecycle actions, recency grouping, bulk selection, project row actions, and SSH remote project setup. These are all navigation/sidebar flows with shared failure modes, so keeping them in the broad smoke file made sidebar regressions harder to isolate and kept project row helpers in the wrong place.

What changed:
- Added `sidebar.spec.ts` for sidebar search/reopen, new chat, chat lifecycle, recency grouping, bulk selection, local project management, and SSH remote project setup.
- Moved sidebar-specific `replaceFocusedText()` and project-row `clickProjectAction()` helpers next to the focused flows that use them.
- Reused the shared Playwright `harnessURL()` and sidebar utility helper in the new focused spec.
- Removed those sidebar/project flows and helpers from `core.spec.ts`.
- Added a sidebar parity gate that keeps the flows in the focused spec and registered it in the focused-suite manifest.

Current strict grades:
- `E2E/playwright/tests/sidebar.spec.ts`: **A**. It owns chat/sidebar/project lifecycle behavior with a cohesive feature boundary.
- `E2E/playwright/tests/core.spec.ts`: **A-**. It is materially smaller, but still owns broad workspace smoke plus command palette, worktree, artifact, composer, and model flows.
- `ParityWorkspaceSidebarGateTests.swift`: **A**. It now guards native/sidebar architecture and focused Playwright ownership.

Remaining risk:
- Continue splitting `core.spec.ts` by feature family. Good next slices are command-palette/git/worktree flows, artifact-preview flows, and composer/model-picker flows.

## 2026-06-25 Playwright Command Palette Spec Split

Overall grade after this slice: **A command-palette E2E ownership, A Git/worktree command coverage, A- broad Playwright core spec**.

`core.spec.ts` still owned command palette execution, query scoping, keyboard navigation, Git worktree actions, pull request commands, local environment actions, and worktree dialogs. Those all depend on the command surface/ranker/planner stack and should fail together in one focused spec rather than inside the broad smoke file.

What changed:
- Added `command-palette.spec.ts` for command palette action execution, slash/action query scoping, keyboard ranking/navigation, Git worktree commands, pull request commands, local environment action execution, and worktree create/remove dialogs.
- Reused the shared Playwright `harnessURL()`, sidebar utility, and deterministic command-palette query/result helpers in the new focused spec.
- Removed those command palette and Git/worktree/local-environment flows from `core.spec.ts`.
- Added a command parity gate that keeps these flows in the focused spec and registered it in the focused-suite manifest.

Current strict grades:
- `E2E/playwright/tests/command-palette.spec.ts`: **A**. It owns command palette and command-dispatched Git/worktree/local-environment behavior with a cohesive feature boundary.
- `E2E/playwright/tests/core.spec.ts`: **A-**. It is now below 1,000 lines, but still owns broad workspace smoke plus artifact, composer, shortcut, slash, memory, context, and model-picker flows.
- `ParityWorkspaceCommandGateTests.swift`: **A**. It now guards native command architecture and focused Playwright command ownership.

Remaining risk:
- Continue splitting `core.spec.ts` by feature family. Good next slices are artifact-preview flows, composer/model-picker flows, shortcut/slash flows, and memory/context flows.

## 2026-06-25 Playwright Artifact Spec Split

Overall grade after this slice: **A artifact E2E ownership, A tool-card preview coverage, A- broad Playwright core spec**.

`core.spec.ts` still owned file artifact surfacing plus image, PDF/document, and appshot preview flows. Those flows all exercise the tool-card artifact preview surface and should fail together in a focused artifact spec instead of broad workspace smoke.

What changed:
- Added `artifacts.spec.ts` for file artifact links/text previews, Activity artifact handoff surfacing, image preview chrome, document preview chrome, and appshot preview chrome.
- Reused the shared Playwright `harnessURL()` and sidebar utility helper in the focused artifact spec.
- Removed artifact preview flows from `core.spec.ts`, bringing the broad smoke file down to the remaining workspace/composer/context/model families.
- Added a surface parity gate that keeps artifact flows in the focused spec and registered it in the focused-suite manifest.

Current strict grades:
- `E2E/playwright/tests/artifacts.spec.ts`: **A**. It owns artifact preview behavior across file, image, document, and appshot surfaces with a cohesive tool-card boundary.
- `E2E/playwright/tests/core.spec.ts`: **A-**. It is now smaller, but still owns broad workspace smoke plus composer, shortcut, slash, memory, context, and model-picker flows.
- `ParityWorkspaceSurfaceGateTests.swift`: **A**. It now guards focused ownership for terminal, search, extension, artifact, and review Playwright flow families.

Remaining risk:
- Continue splitting `core.spec.ts` by feature family. Good next slices are composer/model-picker flows, shortcut/slash flows, and memory/context flows.

## 2026-06-25 Playwright Composer Spec Split

Overall grade after this slice: **A composer E2E ownership, A model/slash interaction coverage, A- broad Playwright core spec**.

`core.spec.ts` still owned multiline composer editing, active-run cancellation, slash command execution and suggestions, approval-mode switching, and model browser search/selection. Those flows all depend on the composer interaction surface and should fail together in a focused composer spec instead of broad workspace smoke.

What changed:
- Added `composer.spec.ts` for multiline entry, Enter-to-send, run cancellation, slash mode, slash routing, slash suggestions, approval-mode switching, and model browser selection.
- Reused the shared Playwright `harnessURL()` helper in the focused composer spec.
- Removed composer/model/slash interaction flows from `core.spec.ts`, leaving the broad smoke suite focused on workspace shell, transcript, context, memory, and UI stability.
- Added a surface parity gate that keeps composer flows in the focused spec and registered it in the focused-suite manifest.

Current strict grades:
- `E2E/playwright/tests/composer.spec.ts`: **A**. It owns composer behavior across text entry, slash commands, mode control, cancellation, and model selection with a cohesive interaction boundary.
- `E2E/playwright/tests/core.spec.ts`: **A-**. It is now substantially smaller, but still owns broad workspace smoke plus top-bar, polish, transcript, activity/context, shortcut, and memory flows.
- `ParityWorkspaceSurfaceGateTests.swift`: **A**. It now guards focused ownership for terminal, search, extension, artifact, composer, and review Playwright flow families.

Remaining risk:
- Continue splitting `core.spec.ts` by feature family. Good next slices are top-bar/polish flows, shortcut flows, and memory/context/activity flows.

## 2026-06-25 Playwright DOM Query Hardening

Overall grade after this slice: **A E2E DOM assertion hygiene, A shared Playwright metric helpers, A- broad Playwright core spec**.

The Playwright suite had useful visual-polish checks, but a few still used TypeScript non-null assertions such as `boundingBox()!` and `querySelector(...)!`. Those are acceptable for quick prototypes, but they produce poor diagnostics in CI and encourage fragile browser-side selector probing as the harness grows.

What changed:
- Added shared Playwright helpers for computed style reads and element rectangle reads.
- Replaced `core.spec.ts` bounding-box non-null assertions with labeled `expectPresent(...)` checks.
- Moved style and rect probes out of ad hoc `page.evaluate()` scripts and onto locator-backed helpers.
- Replaced nested artifact-preview `querySelector(...)!` probes with locator-backed style helper calls.
- Added a parity gate that scans Playwright tests for DOM force unwraps and TypeScript non-null assertions.

Current strict grades:
- `E2E/playwright/tests/harness-helpers.ts`: **A**. Shared E2E helpers now cover command palette, sidebar, settings, computed styles, and element rects.
- `E2E/playwright/tests/core.spec.ts`: **A-**. The broad spec still needs more feature-family splits, but its remaining style and layout checks now fail with better selector diagnostics.
- `ParityGateTests.swift`: **A**. It now guards both production Swift crash patterns and Playwright DOM assertion hygiene.

Remaining risk:
- Continue splitting `core.spec.ts` by feature family. Composer/model-picker, shortcut/slash, and memory/context flows are still the highest-value next splits.

## 2026-06-25 Playwright Workspace Chrome Spec Split

Overall grade after this slice: **A workspace chrome E2E ownership, A visual stability coverage, A- broad Playwright core spec**.

`core.spec.ts` still owned top-bar overflow utilities, horizontal clipping checks, interface polish primitives, and long top-bar metadata stability. These flows all guard visual/interaction chrome rather than core agent behavior, so they should fail in a focused visual-stability suite instead of broad workspace smoke.

What changed:
- Added `workspace-chrome.spec.ts` for top-bar overflow utilities, desktop/mobile clipping checks, interface polish primitives, and quiet top-bar metadata stability.
- Reused shared Playwright `harnessURL()`, `openTopBarOverflow()`, and `openSettings()` helpers in the focused workspace chrome spec.
- Removed visual chrome and layout stability flows from `core.spec.ts`, leaving the broad smoke suite focused on initial workspace, tool cards, transcript, activity, context, memory, and shortcuts.
- Added a surface parity gate that keeps workspace chrome flows in the focused spec and registered it in the focused-suite manifest.

Current strict grades:
- `E2E/playwright/tests/workspace-chrome.spec.ts`: **A**. It owns the visual chrome, clipping, and polish regression checks with a cohesive UI stability boundary.
- `E2E/playwright/tests/core.spec.ts`: **A-**. It is now materially smaller, but still owns broad workspace smoke plus transcript, activity/context, memory, shortcuts, and review-card behavior.
- `ParityWorkspaceSurfaceGateTests.swift`: **A**. It now guards focused ownership for terminal, search, extension, artifact, composer, workspace chrome, and review Playwright flow families.

Remaining risk:
- Continue splitting `core.spec.ts` by feature family. Good next slices are shortcut/find flows and memory/context/activity flows.

## 2026-06-25 Playwright Shortcut Spec Split

Overall grade after this slice: **A shortcut E2E ownership, A transcript find shortcut coverage, A- broad Playwright core spec**.

`core.spec.ts` still owned keyboard shortcut dispatch for search, command palette, shortcuts help, terminal, browser, transcript find, and new chat. Those flows all exercise global keyboard routing and should fail in a focused shortcut suite instead of broad workspace smoke.

What changed:
- Added `shortcuts.spec.ts` for global keyboard dispatch, transcript find navigation, and new-chat shortcut reset.
- Reused the shared Playwright `harnessURL()` helper in the focused shortcut spec.
- Removed shortcut/find dispatch flow from `core.spec.ts`, leaving the broad smoke suite focused on initial workspace, tool cards, transcript scroll, activity, context pressure, memory, and review-card behavior.
- Added a surface parity gate that keeps shortcut flows in the focused spec and registered it in the focused-suite manifest.

Current strict grades:
- `E2E/playwright/tests/shortcuts.spec.ts`: **A**. It owns shortcut routing across global app panels, secondary panes, transcript find, and new-chat reset.
- `E2E/playwright/tests/core.spec.ts`: **A-**. It is smaller again, but still owns broad workspace smoke plus transcript, activity/context, memory, and review-card behavior.
- `ParityWorkspaceSurfaceGateTests.swift`: **A**. It now guards focused ownership for terminal, search, extension, artifact, composer, workspace chrome, shortcut, and review Playwright flow families.

Remaining risk:
- Continue splitting `core.spec.ts` by feature family. Good next slices are memory/context/activity flows and review-card behavior.

## 2026-06-25 Playwright Workspace State And Memory Spec Split

Overall grade after this slice: **A workspace state E2E ownership, A memory coverage, A core smoke spec**.

`core.spec.ts` still owned transcript scroll retention, model-authored Activity plans, context pressure compaction/forking, and memory creation/deletion. These are durable workspace state and memory flows rather than core startup smoke, so keeping them in `core.spec.ts` made regressions harder to isolate.

What changed:
- Added `workspace-state.spec.ts` for transcript scroll intent, Activity plan rendering, and context pressure compact/fork flows.
- Added `memories.spec.ts` for sidebar and command-palette memory flows, including `/remember` creation and deletion.
- Removed those flows from `core.spec.ts`, leaving core focused on initial workspace command execution and review-card smoke after the shortcut split.
- Added parity gates that keep state and memory flows in focused specs and registered them in the focused-suite manifest.

Current strict grades:
- `E2E/playwright/tests/core.spec.ts`: **A**. It now acts like a real smoke spec instead of a catch-all E2E bucket.
- `E2E/playwright/tests/workspace-state.spec.ts`: **A**. It owns context, Activity, and transcript state flows with a cohesive state boundary.
- `E2E/playwright/tests/memories.spec.ts`: **A**. It owns memory UX and persistence-facing command flows.
- `ParityWorkspaceSurfaceGateTests.swift` and `ParityWorkspaceMemoryGateTests.swift`: **A**. They now guard focused Playwright ownership for the remaining extracted flow families.

Remaining risk:
- `core.spec.ts` still includes both the full first-run command smoke and review-card smoke. That is acceptable for now, but the next quality slice could move review-card approval/denial smoke into `review.spec.ts` if core should become a single first-run scenario.

## 2026-06-25 Playwright Review Card Spec Split

Overall grade after this slice: **A review-card E2E ownership, A shared Playwright geometry helpers, A core smoke spec**.

`core.spec.ts` still owned the approval-card and denied-review-card smoke flows. Those checks validate review-card interaction semantics, not first-run workspace setup, so they belong beside the review pane, stage, hunk, and commit flows.

What changed:
- Moved actionable approval-card and denied-review-card flows into `review.spec.ts`.
- Reused the shared Playwright `elementRect()` helper for action button geometry instead of keeping local bounding-box unwrap helpers in `core.spec.ts`.
- Removed the local `expectPresent` helper from `core.spec.ts`, leaving it focused on the first-run command smoke path.
- Expanded the review Playwright parity gate so approval-card and denied-review-card flows must stay in `review.spec.ts`.

Current strict grades:
- `E2E/playwright/tests/core.spec.ts`: **A**. It now acts as a true first-run command smoke test.
- `E2E/playwright/tests/review.spec.ts`: **A**. It owns review-card actions, blocked-review presentation, diff review, staging, hunk staging, and commit flows.
- `ParityWorkspaceSurfaceGateTests.swift`: **A**. It now guards focused ownership for all review Playwright flow families.

Remaining risk:
- Good next slices should move beyond E2E suite shape and target deeper Codex parity: richer review diff interactions, worktree lifecycle polish, and real app-shell smoke around browser/Computer Use.

## 2026-06-25 Composer Send Lifecycle Reducer

Overall grade after this slice: **A composer lifecycle ownership, A cancellation/error state coverage, A- WorkspaceModel send path**.

`WorkspaceModel.submitComposer` still owned low-level composer send state transitions inline: clearing the draft, flipping `isSending`, clearing/reporting `lastError`, and choosing the top-bar status for started, completed, cancelled, and failed sends. That made the agent send path harder to audit because UI state mutation sat beside runner construction, progress application, persistence, and memory refresh.

What changed:
- Added `WorkspaceComposerSendLifecycle` as a focused reducer for composer send start, completion, cancellation, and failure state.
- Replaced direct inline composer/top-bar send-state mutations in `WorkspaceModel.submitComposer` and `finishCancelledSend`.
- Added focused reducer tests for draft clearing, sending flags, stopped status, idle status, and described failure errors.
- Added a WorkspaceModel parity gate so future refactors keep send lifecycle transitions outside the broad workspace model.

Current strict grades:
- `WorkspaceComposerSendLifecycle.swift`: **A**. The reducer is small, value-oriented, and directly testable without runner, persistence, or thread dependencies.
- `WorkspaceModel.submitComposer`: **A-**. It still coordinates runner context, memory refresh, thread persistence, and progress updates, but the repeated composer state transitions are now delegated.
- `WorkspaceComposerSendLifecycleTests.swift`: **A**. It covers every lifecycle branch and keeps the state contract explicit.

Remaining risk:
- `WorkspaceModel.submitComposer` remains a high-value extraction target. The next architectural slice should separate runner context creation and result persistence from the UI-facing send orchestration.

## 2026-06-25 Workspace Chrome Action Coverage

Overall grade after this slice: **A workspace chrome action coverage, A focused parity guard, A harness behavior confidence**.

The chrome spec already checked that top-bar utility buttons existed and that a few panels opened, but two user-critical actions were under-covered: Computer Use setup from the top-bar overflow and Disconnect All for remote project sessions. Both are the kind of "button looks present but does nothing useful" regression users feel immediately.

What changed:
- Added a top-bar overflow Computer Use setup flow that verifies the Settings sheet opens directly to the Computer Use card and routes the Screen Recording permission action.
- Added a top-bar Disconnect All flow that creates an SSH Remote project through the public `/ssh` path, invokes Disconnect All from the overflow menu, verifies the workspace detaches to `No project`, and verifies the command hides when there is nothing left to disconnect.
- Expanded the workspace chrome parity gate so these action semantics stay in `workspace-chrome.spec.ts`.

Current strict grades:
- `E2E/playwright/tests/workspace-chrome.spec.ts`: **A**. The file now owns both visual chrome stability and the critical top-bar action semantics users touch first.
- `ParityWorkspaceSurfaceGateTests.swift`: **A**. It guards focused ownership without tying the test to implementation details.

Remaining risk:
- Native packaged smoke should eventually drive the macOS menu-bar widget and SwiftUI top-bar directly; the current coverage proves the shared HTML harness contract.

## 2026-06-25 Agent Send Session Factory

Overall grade after this slice: **A runner/session composition ownership, A factory coverage, A- WorkspaceModel send path**.

`WorkspaceModel.submitComposer` still assembled the per-turn `AgentRunner` and constructed `WorkspaceAgentSendSession` inline. That kept browser override wiring, MCP tool resolution, memory directory selection, SSH remote executor selection, and workspace-root capture in the same method as composer state, progress updates, memory refresh, persistence, and error handling.

What changed:
- Added `WorkspaceAgentSendSessionFactory` as the focused composition boundary for current workspace state, configured runner creation, and send-session construction.
- Simplified `WorkspaceModel.submitComposer` so it asks the factory for a session and then only owns actor-bound UI/persistence side effects.
- Added focused factory tests for local tool composition, remote project tool composition, workspace/thread capture, memory/MCP tool propagation, and injected browser override behavior.
- Updated architectural parity gates so `WorkspaceModel` cannot reintroduce inline run-context builder or send-session construction.

Current strict grades:
- `WorkspaceAgentSendSessionFactory.swift`: **A**. It is a small value boundary that cleanly composes existing runner-context and send-session types without adding new policy.
- `WorkspaceModel.submitComposer`: **A-**. Runner/session setup is now delegated, but the method still owns progress application, memory refresh, thread persistence, cancellation, and final UI status.
- `WorkspaceAgentSendSessionFactoryTests.swift`: **A**. It directly checks the factory’s local, remote, and override contracts.

Remaining risk:
- The next high-value extraction is a send-result/persistence coordinator that turns progress, memory refresh, final save, and cancellation transcript updates into typed effects. That should happen only after the factory boundary has stayed green across CI.

## 2026-06-25 Send Session Factory Hardening

Overall grade after this slice: **A immutable factory boundary, A black-box factory tests**.

The send-session factory had the right responsibility after extraction, but its stored state was mutable and tests reached into `configuredRunner` directly. That made the helper feel more like a bag of fields than a narrow composition boundary.

What changed:
- Made `WorkspaceAgentSendSessionFactory` immutable with private stored state.
- Kept configured-runner construction private so callers use one path: `makeSession`.
- Updated factory tests to assert behavior through the returned `WorkspaceAgentSendSession`.

Current strict grades:
- `WorkspaceAgentSendSessionFactory.swift`: **A**. It now exposes one construction contract and hides implementation details.
- `WorkspaceAgentSendSessionFactoryTests.swift`: **A**. Tests cover local, remote, memory, MCP, and browser override wiring through the public factory contract.

Remaining risk:
- `WorkspaceModel.submitComposer` still owns post-run completion, persistence, and memory-refresh coordination. That remains the next high-value extraction.

## 2026-06-25 Agent Send Completion Planner

Overall grade after this slice: **A completion planning, A focused parity guard, A- WorkspaceModel send path**.

`WorkspaceModel.submitComposer` still owned successful send completion inline after the session returned: copying the completed thread, branching on saved-memory events, refreshing memory context, updating the thread list, throwing on final persistence, and then applying completed composer/top-bar state. That kept final persistence timing and UI completion mixed into the main async send method.

What changed:
- Added `WorkspaceAgentSendCompletionPlanner` and `WorkspaceAgentSendCompletionPlan` to describe successful send completion from the session result and current composer state.
- Added `finishCompletedSend(_:)` so `submitComposer` delegates memory refresh, final thread update, throwing persistence, and completed lifecycle application to a named helper.
- Added focused planner tests for normal completion and saved-memory refresh signaling.
- Added a parity gate that inspects the `submitComposer` body and prevents inline memory refresh, final save, and completed lifecycle selection from returning there.

Current strict grades:
- `WorkspaceAgentSendCompletionPlanner.swift`: **A**. It is a tiny pure planner with no actor or persistence dependencies.
- `WorkspaceModel.submitComposer`: **A-**. It now delegates runner/session setup and successful completion, but still owns first-thread creation, progress callback wiring, cancellation, and failure routing.
- `WorkspaceAgentSendCompletionPlannerTests.swift`: **A**. It covers the completion lifecycle and memory-refresh flag explicitly.

Remaining risk:
- The next step should continue shrinking `submitComposer` by moving cancellation and failure routing into the same completion boundary, or by introducing a send coordinator once retry/resumable-run semantics need one.

## 2026-06-25 Agent Send Terminal Planner

Overall grade after this slice: **A terminal send planning, A direct lifecycle coverage, A- WorkspaceModel send path**.

The completion planner boundary was useful but too narrow: successful sends used a focused planner while cancellation and failure still chose composer/top-bar lifecycle in `WorkspaceModel`. That made the method read like it had three separate terminal-state policies.

What changed:
- Renamed the boundary to `WorkspaceAgentSendTerminalPlanner` so the name matches its broader ownership.
- Added explicit cancelled and failed terminal plans alongside successful completion.
- Routed failed sends through `finishFailedSend(_:)`, matching the existing named helpers for completed and cancelled sends.
- Expanded planner and parity tests so success, cancellation, and failure lifecycle choices stay out of `submitComposer`.

Current strict grades:
- `WorkspaceAgentSendTerminalPlanner.swift`: **A**. It is a pure terminal-outcome planner with no persistence or actor dependencies.
- `WorkspaceModel.submitComposer`: **A-**. It delegates runner/session composition and all terminal lifecycle choices, but still owns first-thread creation and progress callback wiring.
- `WorkspaceAgentSendTerminalPlannerTests.swift`: **A**. It covers success, saved-memory refresh, cancellation, and failure state directly.

Remaining risk:
- The next high-value extraction is a small send coordinator that groups first-thread creation, context sync, session creation, progress callback wiring, and terminal helper calls into a clearer orchestration boundary without taking over actor-isolated mutations.

## 2026-06-25 Agent Send Start Planner

Overall grade after this slice: **A start planning, A focused lifecycle coverage, A- WorkspaceModel send path**.

`submitComposer` still prepared agent sends inline after prompt classification: it captured the synced thread id, selected the started composer/top-bar lifecycle, and then separately threaded prompt/thread/threadID into session execution and cancellation cleanup. That made the start of a send less explicit than the session factory and terminal planner boundaries.

What changed:
- Added `WorkspaceAgentSendStartPlanner` and `WorkspaceAgentSendStartPlan` to describe the immutable start contract for an agent send.
- Routed `submitComposer` through the start plan before applying started lifecycle, making prompt/thread/threadID/start lifecycle travel together.
- Added focused start planner tests for prompt/thread identity and started lifecycle state.
- Added parity gates so started lifecycle selection stays out of `submitComposer`.

Current strict grades:
- `WorkspaceAgentSendStartPlanner.swift`: **A**. It is a pure value planner with no actor, persistence, runner, or workspace dependencies.
- `WorkspaceModel.submitComposer`: **A-**. It now delegates submission classification, start planning, session composition, and terminal lifecycle selection, but still owns new-chat creation, context sync, progress callback wiring, and terminal helper dispatch.
- `WorkspaceAgentSendStartPlannerTests.swift`: **A**. It directly covers the start contract and lifecycle state.

Remaining risk:
- The next extraction should target progress callback wiring or context/new-thread preparation. Keep actor-owned mutations in `WorkspaceModel`; move only pure planning or narrowly injectable execution boundaries.

## 2026-06-25 Agent Send Progress Planner

Overall grade after this slice: **A progress planning, A focused status coverage, A- WorkspaceModel send path**.

`applyAgentProgress` still mixed actor-owned mutation with policy: it updated the thread, forced the composer into sending state, cleared the last error, and chose the top-bar status from the latest thread event. That made progress handling the only send phase without a focused value boundary.

What changed:
- Added `WorkspaceAgentSendProgressPlanner` and `WorkspaceAgentSendProgressPlan` to describe progress updates as a typed value.
- Routed `WorkspaceModel.applyAgentProgress` through the progress plan before applying thread, composer, error, and top-bar state.
- Added focused progress planner tests for thread identity, composer sending state, stale-error clearing, and latest-event status copy.
- Added parity gates so `WorkspaceModel` cannot reintroduce inline progress status or composer-state policy.

Current strict grades:
- `WorkspaceAgentSendProgressPlanner.swift`: **A**. It is pure and depends only on thread/composer input plus the existing status builder.
- `WorkspaceModel.applyAgentProgress`: **A-**. It now applies a typed plan, but still owns actor-isolated thread mutation and top-bar refresh side effects.
- `WorkspaceAgentSendProgressPlannerTests.swift`: **A**. It covers the progress contract without duplicating the status builder’s full matrix.

Remaining risk:
- `submitComposer` still owns new-chat creation and thread context sync before the start planner. That should remain in the model until there is a clean thread-preparation boundary that can preserve actor isolation and selection behavior.

## 2026-06-25 Agent Send Thread Preparation Boundary

Overall grade after this slice: **A thread preparation boundary, A parity guard, A- WorkspaceModel send path**.

`submitComposer` still contained the one remaining pre-run setup block: create a first thread when needed, read the selected thread, and sync the active project/instructions/memory context into that thread. Those are actor-owned mutations and should stay in `WorkspaceModel`, but they made the public send method harder to scan beside prompt routing, start planning, session execution, progress, and terminal handling.

What changed:
- Added `prepareAgentSendThread()` as a named boundary for first-thread creation and context sync.
- Simplified `submitComposer` so it delegates thread preparation before start planning.
- Added a parity gate that prevents first-thread creation and context sync from drifting back into `submitComposer`.

Current strict grades:
- `WorkspaceModel.prepareAgentSendThread`: **A-**. It is intentionally actor-bound and side-effectful, but now names the setup step clearly.
- `WorkspaceModel.submitComposer`: **A-**. It now reads as prompt classification, thread preparation, start planning, session execution, and terminal routing.

## 2026-06-25 Automation Integration Suite Split

Overall grade after this slice: **A automation command ownership, A scheduling ownership, A run ownership, A shared fixtures**.

`WorkspaceAutomationIntegrationTests.swift` had become the largest app integration suite and mixed three separate failure domains: command/persistence wiring, schedule creation, and automation execution. That made merges noisier and made an automation failure harder to triage because unrelated command, parser, recurrence, due-run, report, persistence, and surface assertions all lived in one file.

What changed:
- Kept command/persistence flows in `WorkspaceAutomationIntegrationTests.swift`.
- Moved concrete, natural-language, recurring, and slash schedule creation flows into `WorkspaceAutomationSchedulingIntegrationTests.swift`.
- Moved manual run, due run, recurrence advancement, report, and limit flows into `WorkspaceAutomationRunIntegrationTests.swift`.
- Moved shared automation test fixtures into `WorkspaceAutomationIntegrationTestSupport.swift` so the split does not duplicate setup code.
- Strengthened the workspace integration parity gate so automation coverage stays split by workflow family.

Current strict grades:
- `WorkspaceAutomationIntegrationTests.swift`: **A**. It now owns the command and store-persistence contract only.
- `WorkspaceAutomationSchedulingIntegrationTests.swift`: **A**. It owns all schedule-creation entry points and recurrence parsing.
- `WorkspaceAutomationRunIntegrationTests.swift`: **A**. It owns automation execution, report, recurrence advancement, and limit behavior.
- `WorkspaceAutomationIntegrationTestSupport.swift`: **A**. Shared fixtures are small, teardown-backed, and local to automation integration tests.

Remaining risk:
- `WorkspaceAutomationEngineTests.swift` is still a large pure-unit suite. It is acceptable while the engine is evolving, but the next automation quality slice should split factory, runner, and reducer tests if that file grows further.
- `ParityWorkspaceExecutionGateTests`: **A**. It protects the send-method shape without forcing a premature pure abstraction around actor-isolated state.

Remaining risk:
- Progress callback wiring and the do/catch send-session orchestration still live in `submitComposer`. A future coordinator could group those only after resumable or background run semantics are clearer.

## 2026-06-25 Tool Run Preparation Boundary

Overall grade after this slice: **A tool-run context preparation, A parity guard, A- WorkspaceModel tool path**.

`runToolCall` still contained the tool-run context policy inline: it selected the effective project, refreshed metadata, rebuilt instruction/memory snapshots, and assigned those snapshots to the selected thread before executing. That made the command path harder to audit because execution, transcript recording, persistence, and context synchronization were all adjacent.

What changed:
- Added `WorkspaceToolRunPreparer` and `WorkspacePreparedToolRun` to name the effective project and selected-thread context sync contract for tool execution.
- Routed `WorkspaceModel.runToolCall` through the preparer while keeping actor-owned mutation, execution, persistence, and top-bar state in the model.
- Added focused tests for thread-project precedence, selected-project fallback, and instruction/memory snapshot sync.
- Added a parity gate so `runToolCall` does not reintroduce inline `workspaceThreadContext`, `thread.instructions`, or `thread.memories` assignment.

Current strict grades:
- `WorkspaceToolRunPreparer.swift`: **A**. It is a pure context-preparation boundary over existing project context rules, with no routing, persistence, UI state, or shell execution.
- `WorkspaceModel.runToolCall`: **A-**. It now delegates project/context preparation, tool routing, and event recording, but still owns actor-bound orchestration, persistence, and visible status updates.
- `WorkspaceToolRunPreparerTests.swift`: **A**. It covers the subtle thread-project versus selected-project edge case directly.

Remaining risk:
- `runToolCall` still sequences status, executor construction, transcript recording, persistence, and final status. A future extraction could group execution plus recording only if it preserves `browser` and `lastError` mutation semantics cleanly.

## 2026-06-25 Tool Run Lifecycle Planner

Overall grade after this slice: **A tool-run lifecycle planning, A focused status coverage, A- WorkspaceModel tool path**.

`runToolCall` still chose the started and finished top-bar states inline. That was not a large defect, but it kept lifecycle policy next to routing, event recording, thread persistence, and actor-owned browser/error mutation. The next small extraction was to name that policy without pretending the whole execution path is pure.

What changed:
- Added `WorkspaceToolRunLifecyclePlanner` with typed start and finish plans for error clearing, returned primary result, and final top-bar status.
- Routed `WorkspaceModel.runToolCall` start and finish status selection through the planner while leaving actor-isolated mutation in the model.
- Added focused unit tests for start state, all-success execution, failed follow-up execution, and failed primary execution.
- Added a parity gate so `runToolCall` does not reintroduce inline started/final status selection.

Current strict grades:
- `WorkspaceToolRunLifecyclePlanner.swift`: **A**. It is tiny, pure, and deliberately limited to lifecycle status decisions. It does not know about routers, persistence, browser state, or thread mutation.
- `WorkspaceModel.runToolCall`: **A-**. It now delegates project/context preparation, execution, event recording, and lifecycle planning, but still owns the actor-isolated orchestration that has to mutate `browser`, `lastError`, selected thread state, and persistence.
- `WorkspaceToolRunLifecyclePlannerTests.swift`: **A**. It covers the lifecycle branch behavior directly, including the subtle case where a successful primary tool still leaves the overall execution failed because a follow-up failed.

Remaining risk:
- `runToolCall` still sequences executor construction, event recording, selected-thread persistence, and final UI update. That is acceptable for now because those steps share actor-bound state; the next extraction should only happen if it can preserve those mutation semantics without adding callback-heavy indirection.

## 2026-06-25 Terminal Run Lifecycle Planner

Overall grade after this slice: **A terminal lifecycle planning, A focused status coverage, A- WorkspaceModel terminal path**.

`runTerminalCommand` still selected top-bar status inline for terminal start, missing execution context, stop, cancellation, and completion. The terminal engine already owns entry mutation and session-marker cleanup, but the model still mixed lifecycle policy with streaming orchestration. The extraction keeps the async process loop in the model while naming status decisions as a pure value boundary.

What changed:
- Added `WorkspaceTerminalLifecyclePlanner` with typed lifecycle plans for started, missing execution context, stopped, cancelled, and finished terminal runs.
- Routed `WorkspaceModel.runTerminalCommand` through the planner using one small `applyTerminalLifecyclePlan` helper for actor-owned state application.
- Added focused lifecycle planner tests for terminal, failed, stopped, cancelled, idle, and failed-completion statuses.
- Added a parity gate so `runTerminalCommand` does not reintroduce inline terminal/stopped/final status selection.

Current strict grades:
- `WorkspaceTerminalLifecyclePlanner.swift`: **A**. It is pure and intentionally limited to top-bar lifecycle planning; it does not know about processes, SSH, session markers, terminal entries, or persistence.
- `WorkspaceModel.runTerminalCommand`: **A-**. It still owns the async streaming loop and terminal entry mutation sequence, which is appropriate for actor-bound state, but it no longer owns lifecycle status policy.
- `WorkspaceTerminalLifecyclePlannerTests.swift`: **A**. It covers every branch that previously lived inline in the model.

Remaining risk:
- `runTerminalCommand` still sequences execution-context lookup, streaming event application, terminal finish mutation, and cancellation handling. A future extraction could isolate the async run coordinator, but only if it avoids callback-heavy indirection and preserves terminal session state updates precisely.

## 2026-06-25 Active Work Stop Planner

Overall grade after this slice: **A active-work stop planning, A focused command coverage, A- WorkspaceModel top-bar command path**.

`cancelActiveWork` and `disconnectAll` still chose stopped/idle top-bar outcomes inline after cancelling sends, terminal runs, and MCP servers. That kept Stop All and Disconnect All slightly behind the rest of the lifecycle architecture, where send, tool-run, and terminal status decisions already live in focused planners.

What changed:
- Added `WorkspaceActiveWorkStopPlanner` and `WorkspaceStoppedActiveWork` to describe cancel/disconnect lifecycle decisions as pure values.
- Routed `WorkspaceModel.cancelActiveWork` and `WorkspaceModel.disconnectAll` through the planner while keeping actor-owned cancellation, remote-project detachment, and top-bar application in the model.
- Added focused planner tests for cancel, no-op disconnect, active work, MCP server cancellation, and remote-only detach behavior.
- Added a parity gate so `WorkspaceModel` does not reintroduce inline stopped/idle status selection for Stop All and Disconnect All.

Current strict grades:
- `WorkspaceActiveWorkStopPlanner.swift`: **A**. It is pure, tiny, and owns only lifecycle status and error-clearing decisions.
- `WorkspaceModel.cancelActiveWork` / `disconnectAll`: **A-**. They still own actor-isolated mutation and project selection side effects, but the policy branch is now named and directly tested.
- `WorkspaceActiveWorkStopPlannerTests.swift`: **A**. It covers all branch behavior that previously lived inline in the model.

Remaining risk:
- Stop All and Disconnect All still share actor-bound state mutation with terminal and MCP runtime teardown. That is acceptable for now; a future coordinator should only extract the mutation sequence if persistent remote sessions or resumable work add more teardown cases.

## 2026-06-25 Command Dispatch Routing Coverage

Overall grade after this slice: **A command routing, A desktop fallback safety, A command-surface coverage**.

The command surface had strong coverage for individual commands, but native and desktop planners still had broad fallback behavior: an unknown command ID could be dispatched into the workspace model, where it might fail as a silent no-op. That is the same failure class users see as “buttons don’t work,” so the routing boundary needed to be shared and testable.

What changed:
- Added `WorkspaceCommandRoutingCatalog` as the shared contract for host-owned commands and workspace-model command plans.
- `WorkspaceViewCommandPlanner` now rejects unplannable command IDs instead of forwarding them as generic dispatch requests.
- `QuillCodeDesktopCommandPlanner` now returns optional actions and delegates only commands the workspace model can execute.
- Added command-surface coverage proving every emitted command is presentational or dispatchable.

Current strict grades:
- `WorkspaceCommandRoutingCatalog.swift`: **A**. It is deliberately small and owns the one cross-surface distinction between host-owned commands and workspace-model command plans.
- `QuillCodeWorkspaceViewCommandPlanner.swift`: **A**. Its fallback is no longer permissive; unknown command IDs are rejected before they can become dead UI.
- `QuillCodeDesktopCommandPlanner.swift`: **A-**. It still has a host-specific switch, which is appropriate for native-only actions, and now avoids accidental workspace fallback.
- `QuillCodeWorkspaceViewCommandPlannerTests.swift`: **A**. It covers host-owned Computer Use commands, unknown-command rejection, and full command-surface dispatchability.

Remaining risk:
- The catalog should stay intentionally narrow. If future host-owned commands are added, add them here with a focused test rather than restoring broad planner fallback.

## 2026-06-25 Local Git Tool Test Split

Overall grade after this slice: **A local git coverage, A router coverage, A mixed-suite containment**.

`ToolTests.swift` had shrunk shell and GitHub PR responsibilities into focused suites, but still owned local git, hunk patch, worktree, and git router coverage. That kept unrelated git failures in one broad catch-all.

What changed:
- Moved local git stage/restore/commit/push/input-validation tests into `GitLocalToolExecutorTests.swift`.
- Moved hunk patch staging/restoring and patch-path mismatch tests into `GitPatchToolExecutorTests.swift`.
- Moved worktree create/list/remove coverage into `GitWorktreeToolExecutorTests.swift`.
- Moved git dispatcher/router definition and route smoke coverage into `GitToolRouterTests.swift`.
- Added parity gates so `ToolTests.swift` stays focused on file/patch primitives plus shell router boundary coverage.

Current strict grades:
- `ToolTests.swift`: **A-**. It is down to focused mixed primitives and shell-router boundary checks, but still can be split further around file/patch primitives later.
- `GitLocalToolExecutorTests.swift`: **A**. It owns local git user workflows and shared input validation.
- `GitPatchToolExecutorTests.swift`: **A**. It owns hunk patch behavior and quoted-path mismatch parsing.
- `GitWorktreeToolExecutorTests.swift`: **A**. It owns worktree lifecycle safety coverage.
- `GitToolRouterTests.swift`: **A**. It owns git dispatcher and router exposure smoke coverage.

Remaining risk:
- Superseded by the 2026-06-25 retired mixed tool suite slice below.

## 2026-06-25 Retire Mixed ToolTests Suite

Overall grade after this slice: **A tool test ownership, A suite naming, A mixed-suite containment**.

After the local git split, `ToolTests.swift` contained only file primitives, generic apply-patch primitives, and shell-router boundary checks. Keeping even a small catch-all made it too easy for future tool coverage to drift back into an ambiguous suite, so the better A+ architecture move was to retire the file entirely.

What changed:
- Moved file read/write path-containment coverage into `FileToolExecutorTests.swift`.
- Moved generic apply-patch success and unsafe-path coverage into `PatchToolExecutorTests.swift`.
- Moved shell dispatcher and `ToolRouter` shell boundary coverage into `ShellToolRouterTests.swift`.
- Deleted `ToolTests.swift`.
- Added a parity gate that fails if `ToolTests.swift` returns and verifies the focused suites own the remaining primitive coverage.

Current strict grades:
- `FileToolExecutorTests.swift`: **A**. It owns file primitive behavior and path containment directly.
- `PatchToolExecutorTests.swift`: **A**. It owns generic patch primitive behavior without mixing git hunk behavior.
- `ShellToolRouterTests.swift`: **A**. It owns shell-router boundary coverage, separate from process execution and SSH request tests.
- `ShellToolExecutorTests.swift`: **A**. It remains focused on process execution, streaming, cancellation, and SSH shell request construction.
- `QuillCodeToolsTests` ownership: **A**. Each current suite now names a tool family or protocol boundary instead of relying on a broad catch-all.

Remaining risk:
- `MCPStdioProberTests.swift` and `GitHubPullRequestToolExecutorTests.swift` are still the largest tools test files. They are focused enough to keep for now, but should be split by protocol probing and PR command family if they grow materially.

## 2026-06-25 Browser Model API Extension

Overall grade after this slice: **A- browser model ownership, A workflow preservation, A- state encapsulation**.

`WorkspaceModel.swift` was still the largest production file and owned the public browser API methods inline even after browser state transitions moved into `WorkspaceBrowserWorkflow`. That made the main model a magnet for future browser fetch, navigation, and live-DOM logic. The better architecture is to keep actor-owned storage in the model while giving browser actions their own extension file.

What changed:
- Added `WorkspaceModelBrowser.swift` for public browser model APIs: draft updates, visibility, navigation, static snapshot fetch, live DOM capture, and browser comments.
- Kept `WorkspaceBrowserWorkflow` as the only owner of browser state-transition policy.
- Added a narrow `mutateBrowserState` helper in `WorkspaceModel` so extensions can mutate browser state without widening the public or internal setters on `browser` and `lastError`.
- Updated browser parity gates to require the extension boundary and prevent browser workflow delegation from drifting back into `WorkspaceModel.swift`.

Current strict grades:
- `WorkspaceModelBrowser.swift`: **A-**. It is focused and keeps browser workflow delegation together; the remaining repetition is the repeated top-bar refresh after successful state transitions.
- `WorkspaceModel.swift`: **A-**. It is still large, but browser public APIs moved out and the added state helper is narrow rather than exposing broad setters.
- `ParityBrowserGateTests.swift`: **A**. It now enforces surface ownership, workflow delegation, adapter boundaries, and the model-extension split.

Remaining risk:
- `WorkspaceModel.swift` is still the largest app file. Continue extracting focused same-actor API families only when the extracted file owns a real domain boundary and can keep model storage encapsulated.

## 2026-06-25 Open Existing Worktree Flow

Overall grade after this slice: **A worktree parity, A local/remote validation, A- model side-effect boundary**.

Codex-style worktree parity needs more than create/remove. Users also need to reopen a registered local or SSH Remote worktree as a focused project/thread without recreating it. The initial PR covered the surface area but was based on the old mixed `ToolTests.swift` suite and represented open handoff context as a create request. This update brought the branch onto current main, kept the deleted catch-all suite deleted, and tightened the context shape.

What changed:
- Added `host.git.worktree.open` to local and SSH Remote git worktree execution, with registered-worktree validation before opening.
- Added command-palette, SwiftUI sheet, desktop-controller, and Playwright harness coverage for opening existing worktrees.
- Moved open-worktree tool/router assertions into `GitWorktreeToolExecutorTests` and `GitToolRouterTests` instead of resurrecting `ToolTests.swift`.
- Changed `WorkspaceWorktreeOpenContext` to store neutral `path` and `branch` fields so create and open flows can share `WorkspaceWorktreeOpenEngine` without leaking create-specific request types.

Current strict grades:
- `GitWorktreeToolExecutor.open`: **A**. It reuses the same safe sibling-path and registered-worktree checks as removal, then returns a path artifact for project handoff.
- `WorkspaceRemoteGitWorktreeCommandBuilder`: **A-**. It validates registered worktrees remotely and reports SSH artifacts; the shell check is necessarily compact, but directly covered.
- `WorkspaceWorktreeOpenEngine`: **A**. It owns local/remote thread copy and context preservation with a request-neutral context.
- `QuillCodeWorktreeDialogs.swift`: **A-**. It now covers create/open/remove sheets in one family file; future polish can add browse/autocomplete for known worktrees.

Remaining risk:
- The open-worktree UI still requires manual path entry. A stronger Codex-parity follow-up is a picker backed by `git worktree list --porcelain`, especially for SSH Remote projects where paths are harder to type.

## 2026-06-25 Worktree Open Picker

Overall grade after this slice: **A worktree picker UX, A parser ownership, A harness parity**.

The open-existing-worktree flow was functionally safe but still made users type absolute paths even though Git already knows the registered worktrees. That is slower, error-prone, and especially awkward for SSH Remote projects. The better Codex-parity shape is a dialog that surfaces known worktrees first, then keeps manual path entry as an escape hatch.

What changed:
- Added `WorkspaceWorktreeListSurfaceBuilder` and `WorkspaceWorktreeChoice` to parse `git worktree list --porcelain` into UI choices with branch/detached/bare detail text.
- Added a non-auditing workspace-model query for known worktree choices so opening the dialog does not create transcript tool cards.
- Updated the SwiftUI open-worktree dialog to show selectable known worktrees above the manual path field.
- Updated the Playwright harness to keep registered mock worktrees as state, render picker rows, and open selected existing worktrees.
- Added focused Swift parser/integration tests plus E2E coverage for selecting an existing worktree from the dialog.

Current strict grades:
- `WorkspaceWorktreeListSurfaceBuilder.swift`: **A**. It owns porcelain parsing, current-project filtering, and stable user-facing labels in one pure helper.
- `QuillCodeWorktreeDialogs.swift`: **A**. The open dialog now handles both discoverable choices and manual paths without leaking Git parsing into view code.
- `WorkspaceModel.worktreeChoices`: **A-**. It keeps the query side-effect free for transcripts; the remaining compromise is that the first implementation only lists local choices from the active root while richer SSH Remote picker loading can follow.
- `E2E/harness/index.html` worktree state: **A-**. The mock harness now models registered worktrees instead of fixed one-off strings, though it remains a lightweight stand-in for real Git porcelain.

Remaining risk:
- SSH Remote open dialogs still need async remote choice loading and loading/error states. The parser and dialog shape are ready for it, but the first slice keeps remote choice discovery out of the UI until the SSH query path can be made nonblocking.

## 2026-06-25 Worktree Prune Lifecycle

Overall grade after this slice: **A cleanup affordance, A remote parity, A- command-plan explicitness**.

Codex-style worktree workflows need lifecycle cleanup, not only create/open/remove. `git worktree prune` is the right narrow next step because it cleans stale administrative records without inventing QuillCode-specific state. The important design point was avoiding an unsafe empty-argument command-palette execution path: the palette action dispatches a dry-run verbose tool call by default, while `/worktree prune` remains available for explicit cleanup.

What changed:
- Added `host.git.worktree.prune` to the tool schema, local executor, git facade, router, remote-safe tool set, SSH Remote command builder, and execution-context surfaces.
- Added typed `WorkspaceWorktreePruneRequest` and `WorkspaceWorktreeToolCallPlanner.prune` so slash commands and command-palette actions reuse structured JSON.
- Added `/worktree prune [--dry-run] [--verbose]` and `wt cleanup -n -v` parsing with clear invalid-option and no-path errors.
- Updated the command palette, icon catalog, Playwright harness, docs, and parity gates.

Current strict grades:
- `GitWorktreeToolExecutor.prune`: **A**. It is a minimal `git worktree prune` adapter with explicit flag construction and no shell interpolation.
- `WorkspaceCommandPlan.runToolCall`: **A-**. It gives command IDs a structured-argument escape hatch without changing existing simple tool plans; future use should stay rare and covered by tests.
- `WorkspaceRemoteGitWorktreeCommandBuilder.pruneCommand`: **A**. It uses the existing shell-quoted argument builder and has direct unit coverage for dry-run/verbose output.
- `SlashWorktreeCommandParser.parsePrune`: **A-**. The grammar is small, explicit, and tested; future UX could surface known stale records before a destructive prune.

Remaining risk:
- Prune is still a command, not a rich stale-worktree review UI. Full Codex parity should eventually show stale records from `--dry-run --verbose` and offer a one-click confirm flow.

## 2026-06-25 Remote And Remove Worktree Picker Proof

Overall grade after this slice: **A worktree picker reuse, A SSH Remote proof, A- loading-state maturity**.

The open-worktree picker had the right shape, but it only proved local choice discovery and left remove users typing paths even though the same registered-worktree list is available. This slice keeps the choice surface shared, extends it to remove, and proves SSH Remote choice discovery runs through the remote executor without producing transcript tool-card audit noise.

What changed:
- Reused one SwiftUI known-worktree choice list for open and remove dialogs.
- Passed known choices into the remove dialog so users can select a registered worktree before confirming removal.
- Extended the Playwright harness so remove dialogs render the same known-worktree choices and update the remove path from selection.
- Added SSH Remote integration coverage proving `worktreeChoices` lists registered sibling worktrees through `ssh ... git worktree list --porcelain`.
- Verified the non-auditing query leaves `currentToolCards` empty, so opening a picker does not pollute the chat transcript.

Current strict grades:
- `QuillCodeWorktreeDialogs.swift`: **A**. Create/open/remove stay in one cohesive dialog family, with shared choice rendering and no Git parsing in SwiftUI views.
- `WorkspaceModel.worktreeChoices`: **A**. It now has local and SSH Remote proof while preserving side-effect-free transcript behavior.
- `E2E/harness/index.html` worktree dialog state: **A-**. The mock harness now mirrors open/remove picker behavior; it is still intentionally synchronous.
- `WorkspaceWorktreeIntegrationTests.swift`: **A**. It owns local and remote picker proof alongside create/open/remove handoff coverage.

Remaining risk:
- Choice loading now has explicit async loading/error rows. Richer production polish should keep improving recovery affordances around transient SSH failures and stale-worktree cleanup.

## 2026-06-25 Worktree Choice Retry Recovery

Overall grade after this slice: **A recovery UX, A- native/harness parity, A test coverage**.

Async worktree choice loading solved the slow SSH Remote picker problem, but a transient failure still left users with a warning row and only manual path entry. Codex-style recovery should keep the manual fallback while offering a direct retry that routes through the same side-effect-free choice loader.

What changed:
- Added a Retry action to failed known-worktree choice rows in the native open/remove worktree dialogs.
- Routed retry through `QuillCodeWorkspaceSheetsModifier` back into the existing workspace-model async load path instead of duplicating load logic in the dialog.
- Added Playwright harness fault injection for one failed choice load, then verified Retry returns the dialog to loading and renders known worktree choices.
- Updated parity docs so worktree picker loading/error/retry states are tracked as implemented rather than pending.

Current strict grades:
- `QuillCodeWorktreeChoiceSection`: **A-**. The view stays presentational and reusable for open/remove; the small compromise is an optional inline action on the status row.
- `QuillCodeWorkspaceSheetsModifier`: **A**. Sheet ownership remains thin and forwards retry intent without knowing how choices are loaded.
- `QuillCodeWorkspaceView.retryWorktreeChoices`: **A**. It guards against stale sheet callbacks and reuses the single async choice-loading pipeline.
- `E2E/harness/index.html` retry fault injection: **A-**. It proves the user-visible recovery path without over-modeling Git failure causes.
- `command-palette.spec.ts` retry regression: **A**. It covers failed load, visible retry, return to loading, success, and error removal.

Remaining risk:
- There is still no cached last-known worktree list when a remote host is offline. Branch lifecycle polish and PR handoff remain broader Codex-parity follow-ups.

## 2026-06-25 Workspace Thread API Extension

Overall grade after this slice: **A- thread API ownership, A sidebar parity gates, B+ central model size**.

`WorkspaceModel.swift` was still carrying user-facing thread lifecycle and sidebar-selection API bodies even though the actual record construction, lifecycle mutation, and sidebar reducers already lived in focused helpers. That kept the central model larger than necessary and made future thread or sidebar UX work more likely to collide with unrelated project, tool-run, terminal, and browser changes.

What changed:
- Added `WorkspaceModelThreads.swift` as the focused same-actor extension for new chat, fork, compact, thread selection, sidebar selection, sidebar bulk actions, thread rename/duplicate/pin/archive/unarchive/delete, and created-thread insertion.
- Left storage, persistence bridges, selected-thread mutation, project helpers, and top-bar refresh on `QuillCodeWorkspaceModel` so behavior stays actor-owned and side effects remain explicit.
- Narrowly changed `root` and `sidebarSelection` setters to `public internal(set)` so same-module model extensions can mutate state while external package users still see read-only state.
- Updated parity gates to require thread/sidebar API bodies and their helper delegations in `WorkspaceModelThreads.swift`, and to prevent them from drifting back into `WorkspaceModel.swift`.

Current strict grades:
- `WorkspaceModelThreads.swift`: **A-**. It is cohesive and delegates creation/lifecycle/sidebar policy to focused helpers, but still necessarily coordinates persistence, selected project state, and top-bar refresh around thread mutations.
- `WorkspaceModel.swift`: **B+/A-**. It dropped another large API family and is easier to scan, but remains the central actor for project, send, terminal, tool, MCP, memory, automation, and persistence orchestration.
- `ParityWorkspaceModelGateTests.swift`: **A-**. It now checks ownership at the extension boundary instead of treating `WorkspaceModel.swift` as the only acceptable delegation site.
- `ParityWorkspaceSidebarGateTests.swift`: **A**. It keeps sidebar reducer/executor ownership visible while preventing sidebar API bodies from returning to the central model.

Remaining risk:
- `WorkspaceModel.swift` is still the largest app file. The next high-leverage extraction should move another coherent same-actor API family, likely project APIs or terminal APIs, only if helper access can stay narrow and focused tests prove behavior did not change.

## 2026-06-25 Workspace Project API Extension

Overall grade after this slice: **A- project API ownership, A project parity gates, B+/A- central model size**.

`WorkspaceModel.swift` still owned the public project API bodies even though the actual project registry policy already lived in `WorkspaceProjectEngine` and project context loading lived in the focused metadata/refresher helpers. Moving those public methods into a same-actor extension keeps the central model focused on shared storage, execution, persistence bridges, and actor-bound helper mutation.

What changed:
- Added `WorkspaceModelProjects.swift` for local project add, SSH project add, project selection, rename, explicit context refresh, and removal.
- Kept project storage on `QuillCodeWorkspaceModel`, and reused existing helpers for terminal sync, context refresh, persistence, selected-thread mutation, and top-bar refresh.
- Routed SSH project validation failures through the existing `setLastError` helper instead of widening `lastError` mutation.
- Updated project parity gates to require project API bodies in the focused extension and prevent them from drifting back into `WorkspaceModel.swift`.

Current strict grades:
- `WorkspaceModelProjects.swift`: **A-**. It is cohesive and delegates registry policy to `WorkspaceProjectEngine`; it still necessarily coordinates persistence, thread context refresh, terminal sync, and top-bar refresh because those are actor-owned side effects.
- `WorkspaceModel.swift`: **B+/A-**. It dropped another public API family, but remains the largest app file because send, tool, terminal, MCP, memory, automation, and shared persistence orchestration still live there.
- `ParityWorkspaceProjectGateTests.swift`: **A**. It now checks both the project API extension boundary and the pure engine/loader ownership boundaries.

Remaining risk:
- The next central-model extraction should target terminal or tool-run APIs only if the resulting extension can preserve narrow helper access without broadening model storage setters.

## 2026-06-25 Worktree Prune Review Flow

Overall grade after this slice: **A cleanup UX, A side-effect boundary, A harness parity**.

`git worktree prune` was available as a structured command, but the command palette still behaved like an immediate dry-run tool dispatch. That was safe, but not Codex-like: users should see what Git considers stale, recover from a transient preview failure, and explicitly confirm before the real cleanup mutates repository administrative state.

What changed:
- Added a side-effect-free `WorkspaceWorktreePrunePreviewLoadRequest` that runs `git worktree prune --dry-run --verbose` locally or over SSH Remote without adding transcript tool cards.
- Added a native Review Stale Worktrees sheet with loading, error/retry, empty, record-list, and disabled-confirm states.
- Kept `/worktree prune --dry-run` and model-level `WorkspaceCommandPlan("git-worktree-prune")` as explicit audited tool-call paths, while routing the visible command-palette action to the richer review sheet.
- Updated the Playwright harness to model stale records, preview failure injection, retry, confirm, and post-confirm transcript output.
- Added focused Swift and E2E coverage for preview parsing, non-auditing local/remote preview, command-palette routing, and retry recovery.

Current strict grades:
- `WorkspaceWorktreePrunePreviewLoader.swift`: **A**. It keeps preview execution side-effect free, reuses the same local/SSH tool execution paths as real prune, and exposes a small UI-focused result type.
- `QuillCodeWorktreePruneView`: **A-**. The states are clear and reusable with the existing worktree dialog styling; future polish can add richer record grouping if Git emits more varied verbose messages.
- `WorkspaceSwiftUIView` worktree sheet orchestration: **A**. Async choice and prune-preview tasks are separate and cancel stale callbacks before opening a different worktree sheet.
- `E2E/harness/index.html` prune preview model: **A-**. It mirrors the user-visible flow and recovery path without pretending to be a full Git implementation.
- `command-palette.spec.ts`: **A**. It now proves the command-palette review/confirm flow plus retry after a failed preview.

Remaining risk:
- The preview currently displays the first 20 non-empty Git output lines as records. That is robust for current `git worktree prune --dry-run --verbose` output, but a future richer UI could classify messages by stale administrative path, missing checkout, or reason when Git exposes more structured detail.

## 2026-06-25 Workspace Terminal API Extension

Overall grade after this slice: **A- terminal API ownership, A terminal parity gates, B+/A- central model size**.

`WorkspaceModel.swift` still owned the public terminal draft, visibility, history, and command-run API bodies even though terminal state transitions already lived in `WorkspaceTerminalEngine` and lifecycle status decisions lived in `WorkspaceTerminalLifecyclePlanner`. Moving the API body to a same-actor extension keeps terminal orchestration discoverable without making the central model carry every workspace surface.

What changed:
- Added `WorkspaceModelTerminal.swift` for terminal draft mutation, visibility toggles, history clearing, and async command execution.
- Kept the actor-owned terminal state on `QuillCodeWorkspaceModel`, but narrowed external exposure with `public internal(set)` so same-module extensions can mutate terminal state without making it writable to package users.
- Widened the immutable SSH executor from file-private to module-internal so terminal, project, and worktree helpers use the same collaborator without a callback bridge.
- Routed terminal error clearing and lifecycle error writes through the existing `setLastError` helper.
- Updated parity gates to require terminal lifecycle delegation in the focused extension and prevent terminal run/history APIs from drifting back into `WorkspaceModel.swift`.

Current strict grades:
- `WorkspaceModelTerminal.swift`: **A-**. It is cohesive and delegates the command/session mechanics to focused helpers; the async streaming loop remains actor-owned because it mutates terminal entries in order.
- `WorkspaceModel.swift`: **B+/A-**. It dropped another public API family, but still owns send, tool-run, MCP, memory, automation, and shared persistence orchestration.
- `ParityWorkspaceExecutionGateTests.swift`: **A-**. It now tests the terminal extension boundary directly and catches regression back into the central model.

Remaining risk:
- The terminal extension still sequences execution-context lookup, streaming events, stop/cancel detection, and finish mutation. A future extraction could introduce a terminal run coordinator, but only if it keeps actor mutation order explicit and avoids callback-heavy indirection.

## 2026-06-25 Workspace MCP API Extension

Overall grade after this slice: **A- MCP API ownership, A MCP runtime boundary, B+/A- central model size**.

`WorkspaceModel.swift` still owned the MCP start/stop public API bodies and termination callback even though process launch, probe, stop, cancel, catalog, and dynamic tool routing were already delegated to `WorkspaceMCPRuntime` and focused MCP helpers. Moving the actor-facing API to a same-actor extension keeps the central model from becoming the catch-all for every workspace surface while preserving explicit app-state mutation.

What changed:
- Added `WorkspaceModelMCP.swift` for MCP server start, stop, selected-manifest lookup, runtime-result application, and process termination callback handling.
- Kept process handles and dynamic MCP execution inside `WorkspaceMCPRuntime`; the extension only coordinates selected-project lookup, actor-owned `ExtensionsState`, notices, last-error state, and top-bar refresh.
- Narrowly changed `extensions` and `mcpRuntime` to same-module access so the focused extension can mutate actor-owned extension state and use the single runtime instance.
- Kept transcript notice appending as a shared workspace-model helper because extension update, MCP, and future app-level notices use the same primitive.
- Updated MCP parity gates to require lifecycle APIs in the focused extension and prevent start/stop/finish callbacks from drifting back into `WorkspaceModel.swift`.

Current strict grades:
- `WorkspaceModelMCP.swift`: **A-**. It is cohesive and small; its only side effects are actor-owned state mutation, top-bar refresh, and transcript notices.
- `WorkspaceMCPRuntime.swift`: **A-**. It remains the correct owner for process/session handles, launch/probe/stop/cancel, and dynamic tool routing; no new app UI policy moved into it.
- `WorkspaceModel.swift`: **B+/A-**. It dropped another lifecycle API group, but still owns send, tool-run, memory, automation, and active-work stop orchestration.
- `ParityMCPGateTests.swift`: **A**. It now verifies state/runtime/catalog/launcher boundaries plus the app-facing model extension boundary.

Remaining risk:
- Stop-all still coordinates MCP cancellation with composer and terminal state in `WorkspaceModel.swift`. That is currently a cross-surface app command, but it should be the next extraction candidate if more stop/disconnect semantics are added.

## 2026-06-25 Workspace Review API Extension

Overall grade after this slice: **A- review API ownership, A review/action parity gates, B+/A- central model size**.

`WorkspaceModel.swift` still owned review action execution, actionable approval-card decisions, and review comment mutation even though those flows already delegated detailed planning to focused review helpers. Moving the actor-facing review API to a same-actor extension keeps review orchestration visible without leaving the central model as the default owner for every UI command.

What changed:
- Added `WorkspaceModelReview.swift` for review stage/restore actions, tool-card approval/edit/deny actions, review comment insertion, review-result transcript recording, and assistant notice insertion for skipped actions.
- Kept selected-thread mutation, persistence, top-bar refresh, and tool dispatch on `QuillCodeWorkspaceModel`, but routed error mutation through the existing `setLastError` helper instead of widening property setters.
- Kept review tool execution on the shared `WorkspaceToolCallExecutor` so local, browser, remote SSH, and apply-patch follow-up routing stay identical between manual tool calls and review actions.
- Updated review, tool-card, and execution parity gates to require review API bodies in the focused extension and prevent them from drifting back into `WorkspaceModel.swift`.

Current strict grades:
- `WorkspaceModelReview.swift`: **A-**. It is cohesive and thin; it coordinates actor-owned review side effects while delegating planning and execution mechanics to focused helpers.
- `WorkspaceReviewActionRunner.swift`: **A**. It still owns ordered action/diff-refresh execution and returns typed recorded results for transcript persistence.
- `WorkspaceApprovalActionPlanner.swift`: **A**. It remains the correct owner for approve/edit/deny decision planning and keeps composer draft generation pure.
- `WorkspaceModel.swift`: **B+/A-**. It dropped another public API group and is down to 800 lines, but still owns send, generic tool-run, slash command, memory, automation, and shared persistence orchestration.
- `ParityWorkspaceSurfaceGateTests.swift` and `ParityWorkspaceModelGateTests.swift`: **A**. They now enforce both helper delegation and focused extension ownership rather than only checking that delegation exists somewhere in the central model.

Remaining risk:
- Generic `runToolCall` still lives in `WorkspaceModel.swift` because it coordinates project context sync, lifecycle recording, execution, persistence, and top-bar status. It is now the clearest next extraction candidate if the model continues to grow.

## 2026-06-25 Global Memory Editing Slice

Overall grade after this slice: **A- memory workflow, A command/test boundaries, B+/A- Chronicle parity**.

QuillCode could add and forget global memories, but existing global memories could not be revised in place. That left the Memories/Chronicle surface behind Codex-style long-running context management: users had to delete and recreate notes, which lost the original file identity and made context updates noisier than necessary.

What changed:
- Added bounded global memory update support to `MemoryNoteLoader`, reusing the same global-memory path guard as delete and the same sensitive-content policy as writes.
- Added `WorkspaceMemoryEngine.updateGlobal` plus focused success/failure transcript planning so `WorkspaceModel` still delegates storage, reload, user-facing copy, and thread-context notices.
- Added `memory-edit:*` workspace commands that prefill an auditable `/remember-edit <id>` draft with the existing memory content, and added `/remember-edit` parsing to update the existing memory file after user edits.
- Added native SwiftUI and static HTML memory-card Edit actions for global memories only; project memories remain read-only because they belong to the workspace.
- Updated the Playwright harness so memory editing is a real state transition, not only static markup.

Current strict grades:
- `MemoryNoteLoader.swift`: **A-**. Add/update/delete now share bounded path and content validation behavior. The only remaining duplication is save-vs-update user-facing error wording, which keeps messages precise without widening the public API.
- `WorkspaceMemoryEngine.swift`: **A-**. It owns memory mutation outcomes and transcript intent cleanly; if Chronicle grows conflict review or redaction previews, promote edit/add/delete into a dedicated workflow coordinator.
- `WorkspaceModelMemory.swift`: **A-**. It stays a thin same-actor extension that coordinates composer prefill, mutation application, and context refresh.
- `SlashMemoryCommandParser.swift`: **A-**. The command format is explicit and robust across LF/CRLF. A future rich inline editor could hide the memory ID while preserving this slash fallback.
- `E2E/harness/index.html`: **B+**. The harness mirrors the product behavior, but its monolithic structure remains a long-term test-maintenance cost.

Remaining risk:
- Memory editing is explicit and user-driven. Richer redaction review, conflict UI, idle Chronicle jobs, and fully autonomous memory inference are still pending parity work.

## 2026-06-25 Local Project Memory Editing Slice

Overall grade after this slice: **A- memory mutation architecture, A local/remote safety boundary, B+/A- Chronicle parity**.

Global memory editing was available, but project memories loaded from `.quillcode/memories` were still read-only. That made the Memories pane inconsistent: users could revise personal memory but had to manually edit repository-local memory files outside QuillCode. Local project memories now use the same `/remember-edit` command and memory-card Edit flow as global memories. At this point in the audit history, SSH Remote project memories were intentionally left read-only until a real remote write path landed.

Code quality changes:

- Added `MemoryNoteLoader.updateProject` using the same bounded directory resolution and sensitive-content guards as global updates.
- Extended `WorkspaceMemoryEngine` and `WorkspaceModelMemory` with a typed project-memory update path that refreshes project memory state, selected-thread memory context, transcript copy, and notice events.
- Kept project Delete out of scope. Global Forget still exists, but project memory files are repository files and need a stronger review/delete UX before QuillCode should remove them.
- Thread/project editability is explicit in `WorkspaceMemoriesSurface`: local project memories expose Edit; remote project memories do not.
- Updated the Playwright harness to edit both a global memory and a project memory, while keeping Forget global-only.

Strict grades:

- `MemoryNoteLoader.swift`: **A-**. Project update now reuses shared directory validation and file loading. The later Memory Loader Policy Boundary pass splits path resolution into a focused helper.
- `WorkspaceMemoryEngine.swift`: **A-**. Mutation payloads now support global and project refreshes without making the model know file policy. The next Chronicle step should consider a dedicated workflow coordinator before adding conflict review.
- `WorkspaceModelMemory.swift`: **A-**. The extension remains cohesive: command prefill, slash update dispatch, and selected-thread context refresh live together. Remaining complexity comes from actor-owned state mutation.
- Memory Playwright harness: **B+/A-**. It covers the user-visible flow, but the harness still duplicates state/render behavior; keep future changes small and surface-contract driven.

Remaining parity risk:

- Remote project memories are intentionally read-only. Conflict UI, redaction review, idle Chronicle jobs, and autonomous memory inference remain the larger Codex-parity gaps.

## 2026-06-25 SSH Remote Project Memory Editing Slice

Overall grade after this slice: **A- remote memory boundary, A validation reuse, B+/A- Chronicle parity**.

Local project memories were editable, but SSH Remote project memories still required manual file edits on the remote host. That was inconsistent with the rest of SSH Remote parity: shell, file, patch, git, terminal, and context refresh already route safely through the remote executor. Remote project memories now use the same explicit `/remember-edit` path as global and local project memories while keeping the write narrowly bounded to already loaded `.quillcode/memories` files.

Code quality changes:

- Added `WorkspaceRemoteProjectMemoryUpdater` as the owner for SSH Remote memory ID validation, safe remote path bounding, remote write execution, and post-write context refresh.
- Reused `MemoryNoteLoader.validatedUpdateContent` so global, local project, and SSH Remote memory edits share empty/size/sensitive-content rejection.
- Extended `WorkspaceMemoryEngine.updateRemoteProject` and routed project memory edits through local or remote mutation paths based on the active project.
- Updated the Memories surface so active SSH Remote project memories expose the same Edit command as local project memories.
- Added fake-SSH integration coverage that edits a remote memory file, verifies the remote file contents, refreshes project context, and updates the selected thread memory snapshot.

Strict grades:

- `WorkspaceRemoteProjectMemoryUpdater.swift`: **A-**. It is focused and defensive: only known project memory IDs under `.quillcode/memories` can be changed, symlink targets are rejected by the remote shell test, and context is refreshed after writes. A future remote-write abstraction could share more code with `WorkspaceRemoteProjectToolExecutor`.
- `WorkspaceMemoryEngine.swift`: **A-**. It now owns global, local project, and remote project mutation outcomes consistently. The engine is still small enough, but conflict review would justify a richer Chronicle coordinator.
- `WorkspaceModelMemory.swift`: **A-**. The extension remains the correct actor boundary for memory commands and selected-project dispatch. It now handles remote/local choice without learning shell details.
- Memory integration tests: **A**. The tests cover UI command prefill, slash execution, fake SSH write behavior, and selected-thread refresh.

Remaining parity risk:

- Project memory delete/review UX, redaction review, idle Chronicle jobs, conflict handling, and autonomous memory inference are still pending.

## 2026-06-25 Project Memory Forget Slice

Overall grade after this slice: **A- memory mutation symmetry, A remote delete boundary, B+/A- Chronicle parity**.

Global memories already had Forget actions, while local and SSH Remote project memories could be edited but not removed from the Memories pane. That made the memory surface inconsistent and left users with a manual file-editing escape hatch for repository-local or remote notes. Project memories now use the same visible Forget command as global memories while keeping deletion bounded to already loaded `.quillcode/memories` files.

Code quality changes:

- Added `MemoryNoteLoader.deleteProject` with the same project-root and direct-file bounds used by project updates.
- Added `WorkspaceRemoteProjectMemoryTarget` so remote edit and delete share one known-memory and `.quillcode/memories` path validator.
- Added `WorkspaceRemoteProjectMemoryDeleter` for SSH Remote `test -f`, `test ! -L`, `rm`, and post-delete context refresh.
- Routed `memory-delete:*` through one `WorkspaceModelMemory.deleteMemory` path that handles global, local project, and SSH Remote project memories.
- Updated native SwiftUI/static HTML/Playwright memory cards so active project memories expose Forget alongside Edit.
- Added loader, engine, model integration, fake-SSH, static HTML, parity, and Playwright coverage for project-memory deletion.

Strict grades:

- `MemoryNoteLoader.swift`: **A-**. Global/local project update/delete operations now share the same path discipline. The later Memory Loader Policy Boundary pass extracts that path-target helper.
- `WorkspaceRemoteProjectMemoryUpdater.swift`: **A-**. The file now owns remote memory mutation helpers, not only update. The target validator keeps delete and edit DRY; if more remote memory operations land, rename this file to a mutation-oriented name.
- `WorkspaceMemoryEngine.swift`: **A-**. It now returns consistent mutation payloads for save, edit, delete, local, and SSH Remote memory changes. Conflict/review workflows should still get a richer Chronicle coordinator rather than expanding this enum indefinitely.
- `WorkspaceModelMemory.swift`: **A-**. The actor extension remains thin and chooses global/local/remote dispatch without learning storage or shell details.
- Memory Playwright harness: **A-**. It covers create, edit, global delete, and project delete in one user-visible flow; the remaining harness risk is still the broad static HTML fixture.

Remaining parity risk:

- Project memory review/conflict UI, redaction review, idle Chronicle jobs, and autonomous memory inference remain pending.

## 2026-06-25 Memory Workflow Boundary Slice

Overall grade after this slice: **A memory routing boundary, A- model thinness, B+/A- Chronicle parity**.

The Project Memory Forget slice made global, local project, and SSH Remote project memory mutations symmetric, but `WorkspaceModelMemory` still owned too much routing policy: it parsed memory IDs, selected local vs remote project mutation paths, and applied the resulting model state. That was acceptable while there were only explicit user commands, but conflict review, redaction previews, and autonomous Chronicle inference would have made the model extension a policy magnet.

Code quality changes:

- Added `WorkspaceMemoryWorkflow` and `WorkspaceMemoryWorkflowContext` as the focused boundary for memory ID scope, editable-note lookup, and global/local/SSH Remote update-delete routing.
- Kept `WorkspaceMemoryEngine` as the mutation-result builder and storage adapter coordinator, so transcript copy, refresh payloads, and remote helpers stay in their existing tested locations.
- Reduced `WorkspaceModelMemory` to actor-owned state application: build context from selected project state, call the workflow, apply global/project memory mutations, and refresh the top bar.
- Added focused workflow unit tests for scope lookup, editable-note resolution, global deletion routing, and local project update routing.
- Tightened the parity gate so `WorkspaceModelMemory` cannot regain direct memory ID parsing or local-vs-remote routing.

Strict grades:

- `WorkspaceMemoryWorkflow.swift`: **A**. It is deliberately small and has one job: route memory commands based on typed context. It does not mutate workspace state, touch files directly, or know UI details.
- `WorkspaceModelMemory.swift`: **A-**. The extension is now thinner and keeps the necessary actor mutation boundary. It still applies context notices because selected-thread mutation is actor-owned model state.
- `WorkspaceMemoryEngine.swift`: **A-**. The engine remains the right place for mutation outcome construction. The next Chronicle feature can now add review/conflict state without forcing another routing branch into the model.
- `WorkspaceMemoryWorkflowTests.swift`: **A**. It directly guards the new seam with cheap unit tests and leaves expensive remote shell behavior in the existing fake-SSH integration tests.

Remaining parity risk:

- Project memory review/conflict UI, redaction review, idle Chronicle jobs, and autonomous memory inference remain pending, but they now have a better architecture boundary to land behind.

## 2026-06-25 Project Extension Install Lifecycle Slice

Overall grade after this slice: **A- extension lifecycle boundary, A command routing, B+/A- plugin marketplace parity**.

Project extension manifests previously supported discovery, MCP start/stop, and update commands, but there was no first-class install/setup action for project-local plugins, skills, or MCP servers. That left the Extensions pane closer to an inventory than a lifecycle surface. Manifests can now expose bounded `installCommand` and `installTimeoutSeconds` fields that flow through the same shell tool-card path as update commands, refresh project metadata afterward, and record transcript notices.

Code quality changes:

- Added install metadata to `ProjectExtensionManifest` and `ProjectExtensionManifestLoader` with the same trimming, size, and timeout bounds as update commands.
- Added `WorkspaceShellToolCallPlanner.projectExtensionInstall` and shared install/update shell-call construction through one private helper.
- Added command-palette rows, command-plan parsing, model execution, SwiftUI Extension pane buttons, and static HTML renderer output for `extension-install:<id>`.
- Refactored project extension install/update orchestration through one `runProjectExtensionCommand` actor helper to keep refresh, dispatch, and notice behavior DRY.
- Added loader, surface, shell planner, command-plan, command-palette, integration, and parity coverage so install cannot degrade into a UI-only button.

Strict grades:

- `ProjectExtensionManifestLoader.swift`: **A-**. Install/update lifecycle metadata shares bounded normalization; manifest discovery remains defensive against root escapes and oversized files.
- `WorkspaceShellToolCallPlanner.swift`: **A**. Local environment, extension install, and extension update shell calls share one canonical argument builder.
- `WorkspaceProjectCommandCatalog.swift`: **A-**. Install/update rows share lifecycle row construction and keywords. If more extension lifecycle verbs land, promote the action enum only if it needs cross-file reuse.
- `WorkspaceModelProjects.swift`: **A-**. The actor extension owns orchestration and shares install/update refresh and notice behavior without leaking shell argument details.
- Extension lifecycle tests: **A**. The slice covers parsing, display compatibility, command routing, real shell execution against a test project, and architecture gates.

Remaining parity risk:

- Marketplace browsing/install, executable plugin activation beyond explicit shell commands, signed plugin trust, and MCP streaming still need dedicated lifecycle work.

## 2026-06-25 MCP Resource And Prompt Action Slice

Overall grade after this slice: **A- MCP action surface, A runtime reuse, B+/A- extension marketplace parity**.

Ready MCP servers already exposed resources and prompts to the agent through generic allowlisted tools, but the Extensions pane still made that metadata feel passive. Codex-style extension UX needs advertised capabilities to be directly usable without making the user prompt the model to discover them. Ready MCP resources and prompts are now surfaced as bounded actions in the Extensions pane, static HTML renderer, command palette, and Playwright harness.

Code quality changes:

- Added `MCPReferenceActionSurface` so resource/prompt actions share one small surface type instead of duplicating title/detail/command identifiers.
- Derived resource/prompt action rows from Ready MCP probe summaries only, capped the visible pane actions, and kept command-palette discovery available for the full advertised set.
- Added typed command-plan cases for `mcp-resource:<server>:<index>` and `mcp-prompt:<server>:<index>`, using last-colon parsing so MCP server IDs can safely contain colons.
- Exposed a direct `WorkspaceMCPRuntime.execute` path for host MCP resource/prompt tools so UI actions reuse the live session runtime and safety checks instead of inventing a second executor.
- Routed direct MCP actions through normal queued/running/completed/failed tool-card events plus concise assistant summaries, keeping the user-visible transcript consistent with agent-authored MCP calls.
- Added focused Swift and Playwright coverage for surface compatibility, command discovery, command parsing, live fixture MCP resource reads, prompt gets, action button rendering, and stop-state cleanup.

Strict grades:

- `ProjectExtensionManifestSurface.swift`: **A-**. The action derivation is deterministic and compatibility-safe; keeping pane actions capped avoids noisy extension cards while leaving command-palette access broader.
- `WorkspaceProjectCommandCatalog.swift`: **A-**. MCP lifecycle and reference commands now share command-surface conventions. If MCP grows argument-taking prompt/resource forms, promote a typed MCP command descriptor before adding more ID string parsing.
- `WorkspaceMCPRuntime.swift`: **A-**. Dynamic MCP execution stays centralized around live sessions, summaries, and allowlisted host MCP tools. It now serves both agent-authored and UI-authored actions without duplicating runtime policy.
- `WorkspaceModelMCP.swift`: **A-**. The model extension coordinates actor-owned transcript/tool-card state while delegating execution to the runtime. It should stay small; future argument forms belong in an MCP action planner.
- MCP action tests: **A**. The slice covers pure command parsing, surface projection, fixture-backed live MCP execution, and Playwright-visible UI behavior.

Remaining parity risk:

- MCP streaming, marketplace trust/install, richer argument forms for MCP prompts, and executable plugin activation remain pending.

## 2026-06-25 Scoped Project Instructions Slice

Overall grade after this slice: **A- instruction scope model, A prompt clarity, B+/A- conflict diagnostics parity**.

Project instructions were already loaded in broad-to-specific order, but each record only exposed the instruction file path. That made nested rules ambiguous in the model context: a deeper `Sources/Feature/AGENTS.md` looked like another general instruction file unless the model inferred path scope from the filename. Instructions now carry an explicit derived scope and the TrustedRouter prompt tells the model when scoped rules apply.

Code quality changes:

- Added backward-compatible `ProjectInstruction.scopePath` decoding and encoding, with older persisted thread/project records deriving scope from `path`.
- Added `ProjectInstruction.scopePath(for:)` and `scopeLabel` in the core model so loaders, prompts, UI surfaces, and tests use one source of truth.
- Explicitly set scope during local instruction loading and rely on the same core derivation for SSH Remote refreshed instruction records.
- Updated the TrustedRouter project-instruction prompt to distinguish whole-project rules from subtree-scoped rules and to preserve broad-to-specific override behavior for matching paths.
- Updated Activity sources to show instruction applicability scope beside the loaded path so users can audit why a rule is in context.
- Added focused core, loader, prompt-builder, and Activity integration coverage.

Strict grades:

- `ProjectInstruction` core model: **A-**. Scope derivation is centralized and old JSON remains compatible. If future rule formats add glob patterns, promote scope into a richer value type instead of adding string conventions.
- `ProjectInstructionLoader.swift`: **A**. Loading semantics remain bounded and unchanged while scope is attached at the model boundary.
- `TrustedRouterPromptBuilder.swift`: **A-**. The prompt now gives explicit applicability instructions without increasing tool-call complexity.
- `WorkspaceActivitySourceSurfaceBuilder.swift`: **A-**. Scope is visible in the existing source row instead of adding another pane or noisy control.

Remaining parity risk:

- QuillCode still does not detect contradictory instructions or show a conflict review UI. That remains the next meaningful AGENTS/rules parity slice.

## 2026-06-25 Project Instruction Diagnostics Slice

Overall grade after this slice: **A- structural diagnostics, A Activity integration, B semantic conflict parity**.

The scoped-instructions slice made rule applicability explicit, but users still had to inspect paths manually to see likely precedence pressure. This slice adds structural diagnostics for the cases QuillCode can prove without interpreting prose: multiple instruction files sharing the same scope, and nested instruction scopes that may override broader project rules.

Code quality changes:

- Added `ProjectInstructionDiagnosticsBuilder` as a focused, pure Activity-support boundary for duplicate-scope and nested-override diagnostics.
- Added `ProjectInstruction.scopeLabel(for:)` so scope display copy stays centralized instead of reconstructing labels in Activity code.
- Updated Activity sources to include diagnostic rows and to mark truncated instruction files directly on their source rows.
- Added focused diagnostics tests, Activity integration coverage, and a parity architecture gate to keep diagnostics out of `WorkspaceModel`.

Strict grades:

- `ProjectInstructionDiagnosticsBuilder.swift`: **A-**. The builder is deterministic, pure, and honest about structural diagnostics. If future work performs semantic comparison, keep it as a separate conflict-review engine rather than extending this simple builder.
- `WorkspaceActivitySourceSurfaceBuilder.swift`: **A-**. Source rows now combine loaded rule files, bounded diagnostics, and memories without creating another mutable surface.
- `ProjectInstruction` core model: **A-**. Scope display and derivation are now both centralized.

Remaining parity risk:

- QuillCode still does not compare rule prose for contradictory instructions or provide accept/dismiss/resolve workflows for conflicts. The next AGENTS/rules parity slice should add a dedicated review surface if semantic conflict handling becomes necessary.

## 2026-06-25 Tool Run Coordinator Slice

Overall grade after this slice: **A- tool-run orchestration, A executor reuse, B+/A- workspace model size**.

`WorkspaceModelToolRuns.swift` was already extracted from the main model file, but it still owned the full generic tool-run sequence inline. That sequence is central to Codex parity: visible commands, slash actions, review buttons, and model-authored tools all depend on the same context refresh, execution, audit, persistence, and top-bar lifecycle. Keeping it in a named coordinator makes future tool families easier to add without turning the model extension into another broad dispatcher.

Code quality changes:

- Added `WorkspaceToolRunCoordinator` as the focused owner for first-thread creation, effective project refresh, selected-thread instruction/memory sync, lifecycle status application, tool execution, audit-event recording, persistence, and final top-bar refresh.
- Added `WorkspaceToolCallExecutorFactory` so generic tool runs and review actions share selected-project/browser/SSH executor construction without putting the factory back on `WorkspaceModel`.
- Kept `QuillCodeWorkspaceModel.runToolCall` as a tiny public same-actor entry point that delegates to the coordinator.
- Left low-level tool routing in `WorkspaceToolCallExecutor`, audit payload construction in `WorkspaceToolEventRecorder`, context preparation in `WorkspaceToolRunPreparer`, and lifecycle status copy in `WorkspaceToolRunLifecyclePlanner`.
- Added direct coordinator coverage proving a first tool run creates a thread, runs the shell tool, records queued/running/completed events, and restores idle top-bar state.
- Updated parity gates so the model extension cannot regain executor construction, context sync, lifecycle planning, or audit-event recording.

Strict grades:

- `WorkspaceToolRunCoordinator.swift`: **A-**. The coordinator still touches actor-owned workspace state, but the side-effect order is now explicit and contained. If async or cancellable direct tool runs expand, promote the coordinator result into a typed plan/outcome before adding more branches.
- `WorkspaceToolCallExecutorFactory.swift`: **A**. It has one job and keeps review actions aligned with normal tool execution routing.
- `WorkspaceModelToolRuns.swift`: **A**. It is now a thin API surface instead of an orchestration body.
- `WorkspaceToolCallExecutor.swift`: **A-**. Routing remains focused and reusable by review actions and the coordinator.
- `WorkspaceToolRunCoordinatorTests.swift`: **A-**. The test covers the public sequence on a real shell tool. Future direct-tool behavior should add focused coordinator tests instead of relying only on broad workspace integration tests.

Remaining parity risk:

- Generic direct tool runs remain synchronous for UI-authored commands. Richer cancellation/progress parity for direct long-running tool actions should build on this coordinator rather than adding state branches back to `WorkspaceModel`.

## 2026-06-25 Shared Thread Context Preparer Slice

Overall grade after this slice: **A thread-context preparation, A tool/agent consistency, A regression guard**.

Agent sends and generic tool runs both need to resolve the effective project for a thread and synchronize project instructions plus memories before execution. Tool runs had a focused preparer, while composer still called the project refresher directly. That made it easy for future Codex-parity execution paths to drift on which project context a model or direct command receives.

Code quality changes:

- Added `WorkspaceThreadContextPreparer` as the shared owner of effective-project selection and thread instruction/memory synchronization.
- Rewired `WorkspaceToolRunPreparer` to delegate to the shared preparer while keeping its tool-run-specific result type.
- Rewired agent-send preparation in `WorkspaceModelComposer` to use the same shared context preparer instead of calling `WorkspaceProjectContextRefresher.syncThreadContext` directly.
- Added focused preparer tests plus parity gates that prevent composer and tool-run code from reintroducing duplicate context-sync behavior.

Strict grades:

- `WorkspaceThreadContextPreparer.swift`: **A**. It is pure, directly tested, and has one project-context responsibility shared by send and direct-tool paths.
- `WorkspaceToolRunPreparer.swift`: **A**. It is now a thin tool-run adapter over the shared context policy.
- `WorkspaceModelComposer.swift`: **A-**. The composer still owns agent-send orchestration, but project-context sync no longer lives inline.
- Context-preparer tests and parity gates: **A**. The slice covers project preference, fallback behavior, memory/instruction sync, and architecture drift.

Remaining parity risk:

- Agent sends still prepare the first thread inside `WorkspaceModelComposer`. If more execution entry points need first-thread creation plus context sync, promote that first-thread setup into a small shared actor coordinator rather than growing the composer extension.

## 2026-06-27 GitHub PR Metadata Resolver And Review Thread Slice

Overall grade after this slice: **A metadata lookup boundary, A inline PR review-thread support, A- PR executor size**.

Inline PR review comments and replies need the current pull request number, head commit, and repository owner/name before posting through `gh api`. That lookup and JSON validation had been embedded in `GitHubPullRequestToolExecutor`, making the executor own both command routing and metadata decoding. Review-thread resolve/unresolve also belongs in the structured PR tool family rather than falling back to ad hoc shell commands.

Code quality changes:

- Added `GitHubPullRequestMetadataResolver` for `gh pr view` / `gh repo view` metadata lookup and validation.
- Rewired `GitHubPullRequestToolExecutor` review comments and replies to delegate metadata lookup while keeping `gh api` argument construction in the executor.
- Added structured `host.git.pr.review_reply` and `host.git.pr.review_thread` tools with prompt guidance, argument normalization, safety policy, remote execution, slash usage, and transcript subtitles.
- Added direct resolver tests and parity coverage so metadata records, JSON decoding, and error copy cannot drift back into the executor.

Strict grades:

- `GitHubPullRequestMetadataResolver.swift`: **A**. It has one responsibility, validates the CLI JSON boundary, and is cheap to test with a fake GitHub CLI.
- `GitHubPullRequestToolExecutor.swift`: **A-**. The executor still owns a broad PR command family, but inline review comments and replies no longer add metadata lookup policy to that surface.
- `WorkspaceRemoteGitHubPullRequestCommandBuilder.swift`: **A-**. Local and SSH Remote PR review-thread actions now share the same structured tool names and validators. Remote command construction remains string-oriented by necessity, so keep adding tests whenever the `gh api` shape changes.
- `GitHubPullRequestMetadataResolverTests.swift`: **A**. The tests cover success, invalid PR metadata, and invalid repository metadata without depending on a real GitHub repository.
- `ParityToolGateTests.swift`: **A-**. The new gate protects the ownership boundary. It remains a string-based architecture guard, which is appropriate for broad drift prevention but should not replace behavioral tests.

Remaining parity risk:

- `GitHubPullRequestToolExecutor` is still a large focused executor because PR create/view/check/diff/checkout/comment/review/reviewer/label/merge/review-comment behavior shares validation and fake-CLI fixture needs. If inline comments or review actions grow materially, split by PR command family next rather than expanding one file indefinitely.

## 2026-06-27 PR Review Thread Command Surface Slice

Overall grade after this slice: **A command discoverability, A safety coverage, A- command-surface breadth**.

The review-thread tool slice made inline review replies and resolve/unresolve operations available to the agent and slash parser, but the user-facing command surfaces still stopped at inline review comments. That left the new structured tools harder to discover from the command palette, `/help`, visible command suggestions, and draft-prefill flows.

Code quality changes:

- Added `git-pr-review-reply` and `git-pr-review-thread` rows to the workspace Git command catalog, slash command catalog, draft planner, and native icon catalog.
- Extended command-palette ranking, workspace surface, remote-project surface, command-plan, command-icon, and PR integration tests so the new actions appear wherever older PR actions appear.
- Added parser/normalizer tests for model-authored review reply and thread aliases, plus Auto safety approval coverage for user-requested inline comments, replies, and review-thread resolution.

Strict grades:

- `WorkspaceGitCommandCatalog.swift`: **A-**. The PR command list remains straightforward and complete. If more PR actions land, the next refactor should group PR command descriptors to avoid manual row duplication across catalog, icons, and plans.
- `SlashCommandCatalog.swift`: **A-**. Slash discovery now matches implemented PR review-thread behavior. The catalog is still a static table, which is acceptable until command metadata is promoted into a shared descriptor.
- `WorkspaceCommandPlan.swift`: **A**. The new actions use normal draft-prefill plans instead of special UI branches.
- Safety and parser tests: **A**. They cover the exact utility risk: user-requested review-thread actions should Auto approve without becoming broad PR write permission.

## 2026-06-27 PR Review Thread Discovery Slice

Overall grade after this slice: **A tool parity, A safety routing, A- future review UX**.

The previous PR review-thread slice let users reply to inline comments and resolve/unresolve GraphQL review threads, but it did not provide a structured way to discover the IDs those actions require. This slice adds a read-only `host.git.pr.review_threads` tool that queries GitHub GraphQL for thread IDs, resolved/outdated state, file/line metadata, and first review-comment `databaseId` values for replies.

Code quality changes:

- Added local and SSH Remote execution for `host.git.pr.review_threads`, sharing the existing PR metadata resolver, selector validation, remote shell quoting, execution-context chips, slash parser, and command palette path.
- Made the command run directly like other read-only PR actions instead of drafting text, while keeping reply/resolve mutation actions as explicit draft or structured agent actions.
- Allowed omitted selectors through both argument-normalization paths so `show review threads` works for the current branch without forcing the model to invent empty arguments.
- Added a typed final-answer summary for GraphQL review-thread output so chat shows unresolved/resolved counts, file/line locations, thread IDs, and first comment IDs instead of raw JSON.
- Updated Auto safety routing so “show unresolved review threads” approves the read-only list tool instead of accidentally matching the review-submission or resolve-thread mutation rules.
- Expanded tool, router, slash, remote command builder, workspace surface, command plan, command ranker, icon, safety, and parity tests around the new read-only action.

Strict grades:

- `AgentFinalAnswerBuilder.swift`: **A-**. The new formatter keeps review-thread discovery readable in chat; the file is still accumulating tool-specific answer formatters and will eventually want a registry split.
- `AgentToolArgumentNormalizer.swift`: **A**. The no-selector rule now matches the tool schema and the prompt guidance exactly.
- `GitHubPullRequestToolExecutor.swift`: **A-**. The GraphQL query is explicit and covered, but PR command growth is pushing this executor toward a split by command family.
- `WorkspaceRemoteGitHubPullRequestCommandBuilder.swift`: **A**. Remote parity is complete and quote-safe for this command, and the GraphQL query is shared with the local executor through the tool-layer query helper.
- `StaticSafetyPolicy.swift`: **A**. The new list rule is intentionally ordered before mutation/review rules and avoids broad “thread” matching so resolve requests still route to the mutation tool.

Remaining parity risk:

- PR command metadata is still duplicated across command catalog, slash catalog, icon catalog, and draft planner. The code is correct and tested, but a future descriptor table would be more DRY if the PR tool family keeps growing.

## 2026-06-27 PR Command Descriptor Slice

Overall grade after this slice: **A command metadata ownership, A command-plan reuse, A- slash catalog still separate**.

The PR command family had grown enough that every new action needed edits across the palette catalog, command planner, icon catalog, and tests. That made command additions correct but expensive, and created an obvious drift risk for parallel agents adding GitHub parity features.

Code quality changes:

- Added `WorkspacePullRequestCommandCatalog` as the single descriptor table for PR command IDs, titles, keywords, SF Symbols, direct tool mappings, and draft-prefill copy.
- Rewired `WorkspaceGitCommandCatalog`, `WorkspaceCommandPlan`, and `QuillCodeCommandIconCatalog` to consume the descriptor table instead of repeating PR metadata.
- Added focused descriptor tests that verify PR command order, enabled command surfaces, direct tool mappings, draft mappings, and icon routing.
- Kept slash parsing separate in this slice because `/pr` subcommands carry additional argument grammar and aliases that are not one-to-one with palette rows.

Strict grades:

- `WorkspacePullRequestCommandCatalog.swift`: **A**. It is small, declarative, and owns exactly the metadata that had been duplicated.
- `WorkspaceGitCommandCatalog.swift`: **A**. The file now reads as Git basics plus PR descriptors plus worktree commands.
- `WorkspaceCommandPlan.swift`: **A**. PR direct-tool and draft plans are table-driven without changing existing command behavior.
- `QuillCodeCommandIconCatalog.swift`: **A**. PR icons no longer require another switch branch when command metadata changes.

Remaining parity risk:

- Slash command catalog/parser entries remain separate because they include grammar and aliases. If PR slash command help starts drifting from palette metadata, add optional slash-usage fields to the descriptor rather than spreading PR copy across another static table.

## 2026-06-27 PR Slash Descriptor Slice

Overall grade after this slice: **A slash discovery ownership, A command descriptor cohesion, A- parser grammar boundary**.

The PR command descriptor table now owns `/pr ...` slash discovery metadata as well as palette rows, direct-tool mappings, icons, and draft-prefill copy. `SlashCommandCatalog` still owns global slash ordering and non-PR commands, but it now imports PR slash definitions from `WorkspacePullRequestCommandCatalog` instead of duplicating another static PR table.

Code quality changes:

- Added optional `SlashCommandDefinition` metadata to `WorkspacePullRequestCommandDescriptor`.
- Rebuilt `SlashCommandCatalog.definitions` from prefix commands, PR descriptor slash definitions, and suffix commands so `/help`, slash suggestions, and command-palette slash rows use the same PR source.
- Added descriptor tests that lock PR slash ordering, catalog reuse, labels insert text, and `/pr review-threads` help coverage.
- Kept `SlashPullRequestCommandParser` separate because it owns grammar, aliases, selector/body parsing, and tool-call construction rather than discovery metadata.

Strict grades:

- `WorkspacePullRequestCommandCatalog.swift`: **A**. PR command metadata is now cohesive and readable; future PR actions can add palette/tool/draft/icon/slash metadata in one row.
- `SlashCommandCatalog.swift`: **A**. The catalog now describes global slash command order without owning PR copy.
- `SlashPullRequestCommandParser.swift`: **A-**. Parser ownership remains correct, but PR grammar is still broad enough that grouped parser helpers may be worthwhile if more subcommands land.
- `WorkspacePullRequestCommandCatalogTests.swift`: **A**. The test catches the exact drift this slice removes.

Remaining parity risk:

- Slash metadata is now DRY, but parser behavior still needs separate tests for every PR grammar branch. That is intentional because parser grammar is behavior, not display metadata.

## 2026-06-27 Click Target Audit Slice

Overall grade after this slice: **A hit-target architecture, A dense-pane coverage, A- native visual regression coverage**.

The app already had a `QuillCodeMetrics.minimumHitTarget` constant, but several dense secondary controls still relied on platform button defaults or compact CSS overrides. That made hit behavior inconsistent across terminal controls, extension cards, memories, dialogs, model rows, and raw tool-data disclosures.

Code quality changes:

- Added a shared `quillCodeHitTarget` SwiftUI modifier so native views use one explicit minimum target and content shape instead of repeating frame boilerplate.
- Applied the modifier to compact terminal, browser, settings, memories, extensions, automations, context-banner, worktree, rename-dialog, runtime-issue, and find-bar controls.
- Removed the web harness model-picker override that set top-bar model rows to `min-height: 0`.
- Expanded tool-card disclosure summaries to a real 44 px target with specific hover transitions.
- Added Playwright bounding-box assertions for top-bar, model-picker, tool-card, terminal, browser, extension, memory, and automation controls.

Strict grades:

- `QuillCodeDesignSystem.swift`: **A**. Hit-target policy now has a small reusable API alongside existing surface and pressable-button primitives.
- Dense native pane views: **A-**. The risky controls now explicitly meet the target; a future visual snapshot layer would make native layout drift easier to detect.
- `E2E/harness/index.html`: **A**. The harness no longer has known compact-control exceptions that violate the minimum hit target.
- `workspace-chrome.spec.ts`: **A**. It now validates rendered bounds for the most failure-prone desktop controls, not just CSS declarations.

Remaining parity risk:

- SwiftUI hit-target coverage is compile-verified but not pixel-measured in native tests. If QuillCode adds native screenshot testing, promote these Playwright assertions into matching AppKit/SwiftUI smoke checks.

## 2026-06-27 Agent Final Answer Formatter Registry

Overall grade after this slice: **A formatter extensibility, A behavior preservation, A- builder file size**.

`AgentFinalAnswerBuilder.finalAnswer` had started accumulating one branch per tool family. That kept behavior correct, but it made the top-level method responsible for dispatching shell, browser, file, patch, MCP, Computer Use, memory, worktree, and PR review-thread summaries directly. The builder now keeps failure/default output at the top level and routes successful tool-specific summaries through a small formatter registry.

Code quality changes:

- Added a `ToolAnswerFormatter` registry for tool-specific final-answer summaries.
- Moved file-write, apply-patch, worktree prune, PR review-thread, plan, memory, shell, browser, MCP, screenshot, and Computer Use summaries behind small formatter functions.
- Preserved existing user-facing copy and truncation behavior.
- Added a parity guard so future tool summaries use the registry instead of regrowing the top-level method.

Strict grades:

- `AgentFinalAnswerBuilder.swift`: **A-**. Dispatch is cleaner and more extensible; the file still owns all final-answer copy, which is acceptable until formatter families become large enough to justify per-domain files.
- `AgentFinalAnswerBuilderTests.swift`: **A**. Existing behavioral coverage caught the refactor without changing expected copy.
- `ParityAgentGateTests.swift`: **A**. The gate now protects the registry shape while leaving individual formatters free to evolve.

Remaining parity risk:

- Browser and PR review-thread summaries are the most likely to grow richer. If either gains substantially more formatting logic, split that formatter family into a separate helper rather than expanding this file again.

## 2026-06-27 Agent Tool Answer Formatter Owner

Overall grade after this slice: **A final-answer reducer boundary, A formatter ownership, A- formatter family size**.

The formatter registry made successful tool summaries extensible, but `AgentFinalAnswerBuilder.swift` still owned every tool-domain branch plus the reducer itself. That kept behavior correct but left the builder as a 496-line mixed file where shell, browser, MCP, Computer Use, PR review-thread, worktree, memory, patch, and file-write copy could collide with top-level failure/default answer changes.

Code quality changes:

- Moved successful tool-specific answer copy into `AgentToolAnswerFormatters`.
- Reduced `AgentFinalAnswerBuilder` to failure handling, registry dispatch, and default output only.
- Removed `QuillCodeTools` and `QuillComputerUseKit` imports from the core builder file.
- Updated the parity gate so future tool-specific branches stay in the formatter owner instead of regrowing the reducer.
- Preserved existing final-answer copy, truncation behavior, and behavioral test expectations.

Strict grades:

- `AgentFinalAnswerBuilder.swift`: **A**. It now owns one job: reduce a tool result into final chat copy by handling errors/defaults and delegating success formatters.
- `AgentToolAnswerFormatters.swift`: **A-**. It is the right ownership boundary for current tool-specific copy. If browser, PR review-thread, or shell formatting grows substantially, split those families into smaller formatter files behind this registry.
- `ParityAgentGateTests.swift`: **A**. The gate now enforces both sides of the boundary: the builder stays lean, and the formatter owner keeps the registry and tool imports.

Remaining parity risk:

- The formatter owner is intentionally broad across tool families. Keep it table-driven for now, but extract per-domain helpers when a formatter family needs more than compact summary logic.

## 2026-06-27 Click Target Contract Pass

Overall grade after this slice: **A click-target policy, A harness enforcement, A- native visual measurement**.

The previous click-target pass removed the worst compact controls, but the contract still mixed 40 px controls, 32 px header actions, and a 40 pt native metric. That made the UI feel inconsistent and let future work satisfy source-level tests without proving the rendered target was easy to click.

Changes:

- Raised the shared SwiftUI `QuillCodeMetrics.minimumHitTarget` and `topBarHeight` from 40 pt to 44 pt so native controls follow the stricter touch/click target convention.
- Added a `--hit-target: 44px` CSS primitive in the Playwright harness and routed primary chrome, composer controls, model picker actions, sidebar controls, browser controls, transcript actions, tool disclosures, runtime recovery, context actions, and secondary pane buttons through it.
- Kept non-interactive badges and line-number columns compact so density stays Codex-like without shrinking real click targets.
- Expanded Playwright coverage to measure primary sidebar actions, add-project, Tools, Settings, model/mode controls, tool details, context banner actions, runtime recovery, and secondary-pane actions by rendered bounding box.

File grades:

- `QuillCodeDesignSystem.swift`: **A**. The minimum target is now a single 44 pt source of truth for native controls.
- `E2E/harness/index.html`: **A-**. The harness now has a central hit-target variable, though it remains a large file and should eventually move style primitives into smaller focused assets.
- `E2E/playwright/tests/workspace-chrome.spec.ts`: **A**. Coverage now checks real click boxes across core chrome and recovery surfaces instead of relying only on CSS text.

Residual risk:

- Native SwiftUI hit boxes are compile-covered but still not pixel-measured. When native screenshot/UI automation lands, mirror the Playwright bounding-box assertions for AppKit/SwiftUI controls.

## 2026-06-27 Click Target System Audit

Overall grade after this slice: **A native target contract, A HTML target semantics, A- duplicate harness renderer**.

The first click-target pass established the 44 pt/px policy, but too much of the implementation still depended on each caller remembering to add a frame. This pass moves the guarantee closer to the shared interaction primitives and names the HTML click-target contract for non-button controls.

Changes:

- Updated `QuillCodePressableButtonStyle` to enforce the shared 44 pt minimum target and full `contentShape`, so pressable native buttons cannot silently shrink below the design-system target.
- Replaced remaining compact native borderless/plain action styling for Computer Use refresh, runtime recovery, memory edit/delete, and worktree retry actions with the shared pressable button style.
- Kept artifact `Link` controls visually compact while explicitly expanding their native target with `quillCodeHitTarget`.
- Added a shared HTML `interactive-hit-target` class for semantic clickable links such as artifact chips and document preview opens.
- Added explicit review, extension, and memory action classes in HTML renderers so target sizing is addressable by CSS and guarded by parity tests.
- Mirrored those semantics in the Playwright harness, including a generic `details > summary` minimum target guard for disclosure controls.

File grades:

- `QuillCodeDesignSystem.swift`: **A**. Native press feedback and target sizing now share one primitive.
- `QuillCodeToolArtifactViews.swift`: **A-**. Link styling still needs `.plain` for SwiftUI, but target sizing is explicit and localized.
- `WorkspaceHTMLPrimitives.swift`: **A**. The target class is a small shared semantic primitive beside escaping and chip rendering.
- `WorkspaceHTMLToolCardRenderer.swift`: **A**. Artifact links and tool details now declare click-target intent in markup.
- `E2E/harness/index.html`: **A-**. The harness mirrors production target semantics, though its duplicate renderer remains the long-term cleanup target.

Residual risk:

- AppKit/SwiftUI rendered hit boxes still need native UI automation measurement. Until then, parity gates protect the source contract and Playwright measures the HTML harness.

## 2026-06-27 Agent Answer Formatter Family Split

Overall grade after this slice: **A registry ownership, A formatter family boundaries, A shared argument parsing**.

`AgentToolAnswerFormatters.swift` had become the correct owner after the reducer split, but it still mixed unrelated formatter families in one 462-line file. That made a browser answer tweak compete with shell summaries, PR review-thread GraphQL response models, worktree prune copy, utility tool copy, MCP output, and Computer Use feedback.

Code quality changes:

- Reduced `AgentToolAnswerFormatters` to the formatter registry and shared truncation helper.
- Split domain copy into focused files: `AgentShellToolAnswerFormatters`, `AgentBrowserToolAnswerFormatters`, `AgentGitToolAnswerFormatters`, and `AgentUtilityToolAnswerFormatters`.
- Added `AgentToolAnswerFormatterSupport` for shared argument parsing, boolean parsing, first-line extraction, and trimmed non-empty string handling.
- Updated agent and browser parity gates to protect the new registry-plus-family boundary.
- Preserved existing final-answer copy and all tool summary behavior.

Strict grades:

- `AgentToolAnswerFormatters.swift`: **A**. It now reads as a registry with no domain-specific parsing or response models.
- `AgentShellToolAnswerFormatters.swift`: **A**. Shell command special cases are cohesive and isolated from unrelated tool families.
- `AgentBrowserToolAnswerFormatters.swift`: **A**. Browser open/inspect copy now sits beside the browser output projection code that will likely evolve with browser parity.
- `AgentGitToolAnswerFormatters.swift`: **A-**. Worktree and PR review-thread copy are both git-family behavior. If more PR output formatting lands, split PR answer models into a `AgentPullRequestToolAnswerFormatters` file.
- `AgentUtilityToolAnswerFormatters.swift`: **A-**. Utility tools remain compact enough together; split MCP or Computer Use only if those summaries become multi-state.

Remaining parity risk:

- Formatter tests still validate behavior through `AgentFinalAnswerBuilderTests`, which is appropriate for user-visible copy. If any formatter family gains branching policy beyond summary formatting, add direct focused tests for that family.

## 2026-06-27 Desktop Computer Use Coordinator Pass

Overall grade after this slice: **A platform capability boundary, A controller ownership, A- direct executable coverage**.

`QuillCodeDesktopController.swift` was already delegating most workflow families, but it still directly owned the macOS Computer Use backend, status refresh, and System Settings opening. That is host capability routing, not controller state ownership, and it would be easy for future Computer Use work to push more platform-specific behavior back into the controller.

Code quality changes:

- Added `QuillCodeDesktopComputerUseCoordinator` as the owner of macOS Computer Use backend installation, status refresh, and System Settings routing.
- Removed direct `QuillComputerUseKit` import and backend/status mutation from the desktop controller.
- Kept the controller responsible only for invoking the coordinator and refreshing published surface state.
- Strengthened the desktop parity gate so backend installation, status refresh, and System Settings opens stay out of the controller.

Strict grades:

- `QuillCodeDesktopController.swift`: **A-**. The file is still broad because it is the desktop UI state bridge, but it no longer owns Computer Use platform capability details.
- `QuillCodeDesktopComputerUseCoordinator.swift`: **A**. Small focused adapter with injectable backend and System Settings opener.
- `ParityDesktopGateTests.swift`: **A**. The gate now protects both the settings persistence boundary and the Computer Use capability boundary.

Remaining risk:

- Desktop executable behavior is still guarded through parity/source gates rather than a dedicated desktop XCTest target. If the package later exposes desktop coordinators as a library target, add direct coordinator tests with fake backend and opener injections.

## 2026-06-27 Provider Outage Runtime Diagnostics

Overall grade after this slice: **A runtime classification ownership, A diagnostics redaction, A- live provider-health parity**.

TrustedRouter runtime failures already normalized missing auth, rejected keys, rate limits, network failures, empty responses, malformed actions, and generic failures. Provider-side outages still fell through as generic failures or network-ish errors, which made live model instability harder to distinguish from local connectivity or key problems.

Changes:

- Added provider identity to runtime diagnostics for every runtime issue surface.
- Classified 5xx/upstream/provider-unavailable errors as `TrustedRouter provider unavailable` with model-switch recovery.
- Parsed provider-outage diagnostics for provider status, HTTP status, and request ID while preserving existing secret redaction for the raw last-error line.
- Kept 5xx detection regex-based so arbitrary text such as token counts does not become a provider outage.
- Mirrored provider-outage diagnostics in the Playwright harness and added settings recovery coverage for model-switch action plus diagnostics rendering.
- Updated parity gates so provider outage classification and diagnostics stay in `WorkspaceRuntimeIssueBuilder` rather than drifting into `WorkspaceSurface`.

File grades:

- `WorkspaceRuntimeIssueBuilder.swift`: **A**. Runtime issue classification remains pure, directly testable, and renderer-independent.
- `WorkspaceRuntimeIssueBuilderTests.swift`: **A**. Tests cover provider diagnostics, request IDs, provider labels, and the false-positive guard.
- `settings.spec.ts`: **A**. Runtime recovery now covers sign-in, network retry, malformed output, rate limit, and provider-outage branches.
- `ParityWorkspaceRuntimeReviewGateTests.swift`: **A**. The gate now protects rate-limit, provider-outage, and redaction ownership together.

Residual risk:

- This is local runtime-error classification, not live provider-health telemetry. Full parity still needs a stable TrustedRouter provider-status source before QuillCode can proactively warn about outages before a run fails.

## 2026-06-27 Desktop Sign-In Apply Coordinator Pass

Overall grade after this slice: **A OAuth lifecycle ownership, A controller boundary, A- desktop executable coverage**.

`QuillCodeDesktopSignInCoordinator` owned PKCE OAuth, callback capture, token exchange, and key persistence, but `QuillCodeDesktopController` still applied the sign-in result to workspace settings/runtime, refreshed the model catalog, and handled sign-in failure state. That split the OAuth lifecycle across two files and made controller-level auth changes more likely.

Code quality changes:

- Added `completeSignInAndApply` to `QuillCodeDesktopSignInCoordinator`.
- Moved OAuth result application, runtime refresh, post-auth model catalog refresh, and sign-in failure status into the sign-in coordinator.
- Reduced the desktop controller to launching the coordinator workflow and refreshing published state through a callback.
- Strengthened the desktop parity gate so result application and sign-in failure handling do not drift back into the controller.

Strict grades:

- `QuillCodeDesktopSignInCoordinator.swift`: **A-**. It now owns the complete desktop OAuth lifecycle. If it grows further, split raw OAuth transport from model application behind a small result-applier type.
- `QuillCodeDesktopController.swift`: **A-**. The controller is still broad but no longer owns auth lifecycle decisions.
- `ParityDesktopGateTests.swift`: **A**. It now protects OAuth transport, result application, post-auth catalog refresh, and failure handling as one coordinator-owned boundary.

Remaining risk:

- Like the other desktop coordinators, this is source-gated rather than covered by a dedicated executable test target. If desktop internals become importable, add fake OAuth/model-application tests around success and failure paths.

## 2026-06-27 Desktop Runtime Settings Coordinator Pass

Overall grade after this slice: **A settings/runtime ownership, A model-catalog boundary, A- desktop executable coverage**.

`QuillCodeDesktopController.swift` still directly owned mode/model/favorite persistence, settings-result application, runtime rebuilds, and model-catalog refreshes. Those are runtime configuration policy, not UI routing, and they should live beside the existing key persistence and settings normalization rules.

Code quality changes:

- Moved desktop mode/model/favorite persistence into `QuillCodeDesktopSettingsCoordinator`.
- Moved settings-result application and runtime rebuilds into the settings coordinator.
- Moved post-save and manual model-catalog refreshes into the settings coordinator.
- Reduced the desktop controller to invoking the coordinator and refreshing published UI state.
- Strengthened the desktop parity gate so runtime settings mutations, catalog fetches, catalog application, and runtime rebuilds do not drift back into the controller.

Strict grades:

- `QuillCodeDesktopSettingsCoordinator.swift`: **A-**. It now owns desktop runtime settings policy coherently. If it grows further, split secret persistence from model/runtime application behind a small runtime-settings applier.
- `QuillCodeDesktopController.swift`: **A-**. The controller still has broad desktop UI routing duties, but it no longer owns configuration mutation policy.
- `ParityDesktopGateTests.swift`: **A**. The gate now protects mode/model/favorite persistence, settings saves, catalog refreshes, and Computer Use platform routing together.

Remaining risk:

- This is still source-gated rather than directly unit tested through an importable desktop library. If desktop coordinators move into a testable target, add fake-bootstrap tests for settings save, catalog refresh, API-key clear/replace, and runtime rebuild flows.

## 2026-06-27 Desktop Workspace Action Coordinator Pass

Overall grade after this slice: **A action routing boundary, A active-root fallback ownership, A- desktop executable coverage**.

`QuillCodeDesktopController.swift` still directly routed tool-card actions, review actions, and review-comment mutations into the workspace model. Those calls are compact, but they share active-workspace-root fallback and are likely to grow as review UX, comments, and tool-card affordances mature.

Code quality changes:

- Added `QuillCodeDesktopWorkspaceActionCoordinator` for tool-card actions, review actions, and review-comment mutation routing.
- Centralized active-workspace-root fallback for desktop tool-card and review actions.
- Reduced the desktop controller to invoking the coordinator and refreshing published UI state.
- Strengthened the desktop parity gate so tool-card action routing, review action routing, review-comment mutation, and active-root fallback do not drift back into the controller.

Strict grades:

- `QuillCodeDesktopWorkspaceActionCoordinator.swift`: **A**. Small, focused coordinator with no UI state and one clear fallback rule.
- `QuillCodeDesktopController.swift`: **A-**. The controller keeps shrinking toward UI-state glue while preserving direct refresh ownership.
- `ParityDesktopGateTests.swift`: **A**. The new source gate protects the next likely review/tool-card growth boundary.

Remaining risk:

- The coordinator is intentionally source-gated for now. If desktop coordinators move into a testable library target, add direct fake-model tests for review action routing and comment mutation edge cases.

## 2026-06-27 Model-Authored Activity Handoff Pass

Overall grade after this slice: **A event-log contract, A executor boundary, A- Activity depth**.

The Activity pane had model-authored plans, but handoff summaries were deterministic fallback text only. That made continuation summaries replayable, but it prevented the agent from recording higher-context Codex-style handoff state when a task reached a natural transfer point.

Code quality changes:

- Added `AgentHandoffUpdate` and the built-in `host.handoff.update` tool schema beside the existing core tool records.
- Added `HandoffUpdateToolExecutor` to normalize bounded summary and next-step payloads, parse the latest successful event-log update, and render the shared Activity body text.
- Exposed the handoff tool through `WorkspaceAgentRunContextBuilder` and the generic workspace tool executor without adding branches to `WorkspaceModel`.
- Updated Activity projection to prefer the latest model-authored handoff, then fall back to deterministic derived summary text.
- Added unit, integration, agent-loop, and parity gates covering round-trip schema, tool routing, run-context exposure, transcript recording, and Activity rendering.

Strict grades:

- `HandoffUpdateToolExecutor.swift`: **A**. Small, pure, bounded, and parallel to the plan executor without broadening workspace model responsibilities.
- `WorkspaceActivitySurfaceBuilder.swift`: **A-**. Activity owns one more authored-state preference cleanly, but richer task dependency rendering will eventually need a deeper activity-state reducer.
- `WorkspaceAgentRunContextBuilder.swift`: **A-**. The additional Activity tool boundary is coherent; if more Activity-owned tools appear, split the tool list into a tiny `WorkspaceActivityToolDefinitions` helper.

Remaining risk:

- Handoff summaries are now model-authored when the model calls the tool, but QuillCode does not yet proactively prompt for handoff updates at every long-task boundary. Richer task lifecycle triggers remain part of broader Activity/task parity.

## 2026-06-27 Approval Card Progressive Disclosure Pass

Overall grade after this slice: **A UX contract accuracy, A renderer parity, A future-agent handoff**.

Ready-to-run approval cards now use progressive disclosure: the user sees the decision and Run/Edit/Skip actions immediately, while raw JSON stays closed until requested. Blocked or denied cards still expand as `Needs review` because that is where extra context is useful.

| Area | Before | After |
| --- | --- | --- |
| Routine approvals | Docs implied all review cards expanded by default, encouraging raw tool JSON to dominate routine approvals. | Parity docs state that ready approvals peek while keeping direct actions visible. |
| Blocked approvals | Ready and blocked review density could be described as the same interaction. | The documented contract separates calm ready approvals from expanded blocked review cards. |
| Agent handoff | Future agents had to infer the new behavior from tests and decisions. | The parity matrix and audit log describe the exact shared UI contract. |

Remaining risk:

- This pass is documentation-only after the implementation merge. If tool-card density evolves again, update `ToolCardState` tests, Playwright review tests, the parity matrix, and this audit together.

## 2026-06-27 Real-World Action E2E Coverage Pass

Overall grade after this slice: **A focused browser coverage, A- mock command realism, A parity guard**.

The user-visible regressions around simple shell/file actions needed a focused browser spec instead of relying on broad coverage buried in `core.spec.ts` and `artifacts.spec.ts`. Natural prompts such as `whoami?`, backticked commands such as `Run \`ls\``, and file creation requests now have direct E2E coverage for one-turn execution, nonempty structured arguments, final-answer rendering, and absence of confirmation-loop placeholder responses.

Code quality changes:

- Added `real-world-actions.spec.ts` for high-signal user flows that should never regress silently.
- Normalized natural shell prompts in the harness so punctuation and polite wrappers do not become literal command text.
- Routed mock shell prompts through the same terminal-output simulator used by the integrated terminal.
- Parsed simple file-write requests into a bounded request object instead of relying on a broad string branch.
- Added a parity gate so the real-world action spec remains focused and keeps guarding against empty shell arguments.

Remaining risk:

- This is deterministic browser harness coverage. The next layer should connect the same scenarios to a mock TrustedRouter transcript parser or live smoke harness so real model output is checked against the same one-turn action contract.

## 2026-06-27 Agent Real-World Action Coverage Pass

Overall grade after this slice: **A parser recovery guardrails, A agent one-turn action coverage, A- model-output tolerance**.

The browser harness now catches simple action regressions at the UI level, but the deeper agent layer still needed direct coverage for malformed model output seen during device testing: `whoami?` should execute immediately, “I'll run whoami” must not become a dead promise, and an empty `host.shell.run` object should be repaired only when a nearby explicit command exists.

Code quality changes:

- Added agent-level coverage for the exact `whoami?` prompt, including inspection of the queued tool payload to require `{"cmd":"whoami"}`.
- Added parser coverage for non-backticked promised shell commands, disk checks, dotted URL commands, and empty shell-argument repair from nearby plain-text commands.
- Preserved conservative guardrails for passive suggestions and negative execution intent so the fallback does not turn arbitrary prose into commands.
- Added an agent-loop regression that keeps non-backticked “I'll run ...” promises out of the transcript before the actual tool executes.

Remaining risk:

- Plain-text command recovery is intentionally narrow and allowlisted. Broader command recovery should come from stronger TrustedRouter structured output and live-model smoke tests, not from making this fallback permissive.

## 2026-06-27 Device Diagnostic Prompt Coverage Pass

Overall grade after this slice: **A real-device prompt coverage, A agent/browser parity, A DRY test helper**.

The previous real-world action coverage protected `whoami?`, `Run \`ls\``, and file creation. The next user-visible device prompts from Feather testing were disk usage and OpenClaw discovery. Both now have direct browser-harness and agent-level coverage so they cannot regress into empty shell calls, passive promises, or extra confirmation turns.

Code quality changes:

- Added Playwright coverage for `How much hd?` and `Do you have openclaw?` with exact nonempty shell commands, final answer text, and no confirmation-loop copy.
- Added agent immediate-action tests for disk usage and OpenClaw discovery.
- Reused a focused `queuedShellCommand` helper to keep command-payload assertions DRY across immediate-action tests.

Remaining risk:

- “Download a site” is now specified in the follow-up pass as a workspace-bounded file download into `downloads/`; keep browser navigation requests separate from file download requests.

## 2026-06-27 Interaction Target Contract Gate

Overall grade after this slice: **A target contract enforcement, A rendered accessibility coverage, A- native pixel measurement**.

The click-target system had good shared primitives and broad Playwright coverage, but it still depended on reviewers noticing new escaped controls. This pass makes the intent fail-fast in tests: compact native button styles, icon-only buttons, and gesture-based interactions now have explicit source gates, and the rendered harness rejects visible click targets that have no user-facing name.

| Principle | Before | After |
| --- | --- | --- |
| Minimum hit area | Existing controls mostly used shared 44 pt/px helpers, but future compact `.bordered`, `.plain`, or icon-only controls could bypass the convention. | `ParityInteractionTargetGateTests` scans SwiftUI app sources and fails compact platform button styles without a `quillCode...Target`, icon-only controls without `quillCodeIconButtonTarget`, and gesture-only click handlers. |
| Accessible targets | The Playwright audit measured size, clipping, center ownership, and overlap, but a nameless visible control could still pass. | `interaction-audit-helpers.ts` now computes accessible names from ARIA, labelled-by text, title, placeholders, and visible text, and fails `missing_accessible_name`. |
| Future UI slices | Click-target checks were spread across hand-written source assertions plus rendered state audits. | Native source gates and rendered browser audits now cover different failure modes: misuse at code review time and real layout failure at E2E time. |

Remaining risk:

- Native SwiftUI hit boxes are still source-gated rather than pixel-measured in a packaged app. When native UI automation lands, mirror the Playwright visible-rect and overlap checks against the actual macOS/Linux windows.

## 2026-06-27 Explicit Download Prompt Coverage Pass

Overall grade after this slice: **A- real-world download behavior, A safety specificity, A prompt/test alignment**.

The phone-visible `Can you download LinkedIn.com?` failure needed a product-level decision. QuillCode now treats explicit `download`, `save`, or `fetch` requests for a URL/domain as a workspace-bounded file download: use `curl`/`wget`, write under a relative path such as `downloads/linkedin.com.html`, and present a concise final answer with the saved path. Browser navigation remains separate: prompts like `open LinkedIn.com` still route to browser-open semantics.

Code quality changes:

- Added TrustedRouter prompt guidance for safe URL/domain downloads, including relative workspace paths and no remote-content shell piping.
- Added mock planner support for deterministic download commands so local and browser tests exercise the intended one-turn behavior.
- Added a specific static safety mini-policy that approves only matching curl/wget file downloads for the requested host, while rejecting unrelated shell commands or domain mismatches.
- Added final-answer formatting for successful shell downloads so users see `Downloaded to ...` instead of raw `ls` output.
- Added native and Playwright coverage guarding against empty shell arguments, passive confirmation loops, and scary confirmation copy for explicit downloads.

Remaining risk:

- Live TrustedRouter models can still choose a different safe file name or command variant. The safety policy allows common curl/wget output forms, but live smoke coverage should keep checking that model output stays bounded and useful.

## 2026-06-27 Responsiveness Budget E2E Pass

Overall grade after this slice: **A- responsiveness coverage, A CI-stable budgets, A- native measurement gap**.

QuillCode had broad UI coverage, but it lacked explicit speed and reflow budgets for interactions users feel immediately: first-load interactivity, simple one-turn tool completion, stop latency, and tool-card expand/collapse stability. This pass adds focused Playwright coverage with generous CI-stable thresholds so obvious jank regressions fail before they reach users.

Code quality changes:

- Added `responsiveness.spec.ts` with budgets for first load, one-turn shell completion, slow-task stop response, and tool-card expand/collapse.
- Reused the shared `harnessURL()` helper and real harness interactions instead of synthetic DOM mutation.
- Checked no horizontal overflow and stable scroll position after expand/collapse.
- Added a Swift parity gate so responsiveness budgets stay in their focused spec instead of drifting into broad smoke tests.

Remaining risk:

- These are harness-level browser timings, not packaged native-window measurements. Native macOS/Linux UI automation should mirror these once available.

## 2026-06-27 Live TrustedRouter Smoke Pass

Overall grade after this slice: **A- real-provider coverage, A secret hygiene, B+ live-flake containment**.

The deterministic mock and Playwright suites now catch many user-visible action regressions, but they still cannot prove that a live TrustedRouter model returns structured QuillCode actions under current prompt wording. This pass adds an explicit opt-in live smoke script instead of folding paid/network work into every PR.

Code quality changes:

- Added `scripts/live-tr-smoke.sh`, which reads `QUILLCODE_API_KEY`, `TRUSTEDROUTER_API_KEY`, or `~/.quill.code.keyfile` without printing secrets.
- Defaulted the live smoke to the user-facing `deepseekv4flash` alias and normalize it to `deepseek/deepseek-v4-flash` for the CLI call.
- Exercised real `quill-code --live` flows for an exact backticked shell command and a natural `whoami?` diagnostic.
- Made the script fail on the exact regressions seen in device testing: empty shell arguments, passive “I’ll run...” answers, empty stdout, or missing expected command output.
- Documented the live smoke as an opt-in release/prompt/parser/safety gate in `docs/TEST_PLAN.md`.

Remaining risk:

- Live provider behavior can be flaky or rate-limited. Keep this out of normal PR gates unless a stable CI secret, retry policy, and provider budget are explicitly configured.

## 2026-06-27 Live File-Write Smoke Pass

Overall grade after this slice: **A- live write-path coverage, A bounded workspace safety, B+ provider-output variability**.

The first live TrustedRouter smoke proved real shell/diagnostic actions, but it still did not cover the user-visible “make a file” workflow that previously regressed into passive promises and empty tool calls. This pass extends the opt-in smoke to require a real temp-workspace file write with exact content verification.

Code quality changes:

- Split live smoke assertions into reusable output-regression checks and expected-output checks.
- Added a live prompt for `live-smoke.txt` with exact content, then verified the file exists under the temp workspace and contains only the requested content.
- Kept the write path bounded to a temporary workspace so the smoke tests real model/tool behavior without touching user files.
- Updated the test plan so release and prompt/parser changes include live write-path validation.

Remaining risk:

- Live file-write behavior can still vary by model. If a model writes a safe alternate file path, the smoke should fail intentionally because the product contract for this prompt is an exact requested path.

## 2026-06-27 Live Transcript Integrity Smoke Pass

Overall grade after this slice: **A live transcript evidence, A regression detection, B+ external tool dependency**.

The live smoke now proves the user-visible results and the actual persisted thread evidence. This closes a gap where a smoke could pass from stdout alone while saved transcripts still carried malformed, empty, failed, or passive action records.

Code quality changes:

- Added `jq` availability checking to the live smoke because transcript inspection needs structured JSON parsing.
- Added transcript integrity checks across all saved live-smoke threads: at least one queued tool call per thread, nonempty tool names, nonempty JSON argument objects, no tool failures, successful completed tool results, and no persisted assistant “I’ll run/check/do” or empty-shell-command copy.
- Kept detailed failure output bounded to the relevant saved thread titles, messages, and events so live-smoke failures are actionable without printing secrets.
- Updated the test plan to treat persisted transcript integrity as part of live release/prompt/parser validation.

Remaining risk:

- This still runs through the CLI, not the packaged native SwiftUI window. Native smoke should eventually inspect the same transcript evidence after a real app run.

## 2026-06-27 Expanded Live Real-World Prompt Smoke Pass

Overall grade after this slice: **A- live prompt realism, A bounded workspace effects, B+ provider/network variability**.

The live smoke now covers the real user phrasings that have repeatedly regressed during device testing, not only minimal command examples. The goal is to catch live-model drift before it reaches the app: OpenClaw discovery should run a concrete shell command, and public-page downloads should create the requested workspace file.

Code quality changes:

- Added reusable live-smoke helpers for regex-based output checks and nonempty workspace-file assertions.
- Extended the opt-in live TrustedRouter smoke from three prompts to five: backticked shell command, natural `whoami?`, exact file creation, `Do you have openclaw?`, and a public `https://example.com` download into `downloads/example.html`.
- Hardened the TrustedRouter download prompt so live models create parent directories with `mkdir -p` before writing nested download paths.
- Raised persisted transcript expectations to require all five live prompt transcripts, each with nonempty queued tool arguments, no failed tool events, and successful completed tool results.
- Kept all external side effects bounded to an isolated temporary HOME and workspace.

Remaining risk:

- This still depends on live model, network, and public-page availability, so it remains an opt-in release/prompt/parser gate rather than a required PR check.
- The smoke still drives the CLI entrypoint. Native macOS/Linux UI automation should later run the same scenarios through the packaged SwiftUI app and inspect saved transcripts.

## 2026-06-27 Default Smoke Real-World Action Pass

Overall grade after this slice: **A default-entrypoint coverage, A local side-effect isolation, A- mock planner realism**.

The optional live smoke catches real provider drift, but every PR also needs cheap coverage for the same user-visible action family. The default smoke now runs natural prompts through the real `quill-code` CLI with the deterministic mock model, real shell execution, real filesystem writes, and a local curl download.

Code quality changes:

- Added default smoke assertions that reject empty-shell and passive “I’ll run/check/do...” output for CLI prompts.
- Expanded `scripts/smoke.sh` beyond `run whoami` and file creation to cover `whoami?`, `How much hd?`, `Do you have openclaw?`, and a local `file://` download into the requested `downloads/example.html` path.
- Hardened the mock LLM download planner so it distinguishes source URLs/domains from requested output paths and supports local `file://` smoke sources.
- Added agent-level coverage for explicit download output paths so deterministic tests catch the exact command shape before CI smoke runs.

Remaining risk:

- This still exercises the CLI rather than the packaged SwiftUI app. It is valuable because it is cheap and required in CI, but native UI smoke should eventually drive these same prompts through the desktop window.

## 2026-06-27 App Surface Real-World Action Pass

Overall grade after this slice: **A shared-surface coverage, A side-effect verification, B+ packaged-window coverage**.

The default smoke now catches the real prompt family through the CLI, but the app still needed a Swift-side guard that proves those same actions survive through the workspace model and renderable surface contract used by SwiftUI and the HTML harness.

Code quality changes:

- Added a compact table-driven workspace integration smoke that sends `whoami?`, disk usage, OpenClaw discovery, file creation, and local download prompts through `QuillCodeWorkspaceModel.submitComposer`.
- The test validates the shared `WorkspaceSurface` timeline shape, tool card title/status/input, visible assistant answer, absence of passive “I'll run...” regressions, and real workspace file side effects.
- The assertions normalize tool input JSON formatting so the test checks behavior and command content without coupling to pretty-print whitespace or JSON slash escaping.

Remaining risk:

- This still stops at the shared Swift app surface, not the packaged macOS window event loop. A future smoke should launch `quill-code-desktop`, drive the native window, and compare an appshot/screenshot against the same prompt family.

## 2026-06-27 Desktop Controller Real-World Action Pass

Overall grade after this slice: **A- native desktop-controller coverage, A side-effect verification, B packaged-window coverage**.

The prior app-surface smoke proved the Swift workspace model and renderable surface, but it did not enter the macOS desktop controller/coordinator layer that owns draft clearing, async task slots, default project bootstrapping, and desktop refresh timing.

Code quality changes:

- Added a dedicated `QuillCodeDesktopTests` target that imports the desktop executable module with `@testable import quill_code_desktop`.
- Added `QuillCodeDesktopControllerSmokeTests/testDesktopControllerSendPathCoversRealWorldActionPromptFamily`, which builds isolated temp app state, forces the mock runtime, and drives `QuillCodeDesktopController.send()` for `whoami?`, disk usage, OpenClaw discovery, file creation, and local download prompts.
- The smoke validates desktop-controller surface refresh, nonempty tool-card arguments, completed tool status, concrete final answers, no passive “I'll run...” regression, no empty-command regression, and actual file side effects.

Remaining risk:

- This still does not synthesize native click/key events against a packaged `.app` window. The next coverage layer should launch `quill-code-desktop`, drive the native window with Accessibility/XCTest or a small appshot harness, and capture a screenshot/appshot for the same prompt family.

## 2026-06-27 Click Target Contract Pass

Overall grade after this slice: **A native target primitives, A rendered target coverage, A- source-level precision**.

The click-target contract now treats every interactive surface as a first-class target, not just obvious buttons. The main risk was that source gates could miss text-only `Link` controls or pass because a nearby unrelated target helper appeared in a broad source window.

Code quality changes:

- Added native parity coverage proving the shared hit-target modifier enforces the 44 pt minimum frame and explicit `contentShape` for rectangle, rounded, and capsule targets.
- Extended native source gating from `Button` declarations to `Link` declarations so artifact links and future link-style controls cannot shrink to text bounds.
- Strengthened the rendered interaction-audit parity check so whole-screen audits and explicit critical-control probes both use the same 44 px minimum.
- Updated `docs/DECISIONS.md` to make the `Button`/`Link` click-target contract explicit for future UI contributors.

Remaining risk:

- Native SwiftUI hit-target validation is still source-gated rather than measured with platform UI automation. Keep mirrored Playwright harness coverage for high-risk controls until packaged native UI automation can measure real pixels.

## 2026-06-27 Live Smoke Hardening Pass

Overall grade after this slice: **A live prompt regression detection, A transcript integrity checks, B+ provider/network variability**.

The opt-in live smoke had fallen slightly behind the deterministic real-world smoke family. It covered live shell, `whoami?`, file write, OpenClaw, and public download, but it did not cover natural disk-usage prompts and its passive-answer guard still allowed “I'll download/create/write...” regressions that were visible in app testing.

Code quality changes:

- Expanded the live passive-answer guard from `run/check/do` to `run/check/do/download/create/write`, and applied the same rule to persisted transcript inspection.
- Added a real TrustedRouter `How much hd?` prompt that must produce concrete disk-usage output instead of a promise.
- Added a natural `hello-world.txt` file-write prompt with exact temp-workspace side-effect verification, in addition to the existing explicit file-write case.
- Raised persisted transcript expectations from five to seven live prompt transcripts so every live scenario has nonempty queued tool arguments, no failed tool events, and successful completed tool results.

Remaining risk:

- Live smoke remains opt-in because it depends on an external model, network access, public-page availability, and a local/CI secret. It should run before releases and after prompt/parser/safety changes, while required PR CI keeps using deterministic mock coverage.

## 2026-06-27 Native Render Smoke Pass

Overall grade after this slice: **A- native render coverage, A real side-effect validation, B packaged-window coverage**.

The desktop controller smoke proved native state transitions, but it still could not catch an app surface that visually rendered blank, collapsed, or visually disconnected from the action result. The new render smoke adds pixel-level coverage for the SwiftUI shell and the message/tool-card components that users actually inspect after a command runs.

Code quality changes:

- Added `QuillCodeDesktopRenderedSmokeTests`, which runs a real “write hello world” prompt through `QuillCodeDesktopController.send()`, verifies the `hello.txt` side effect, and renders the SwiftUI workspace shell to a deterministic 1280x900 image.
- Added a focused transcript excerpt render that uses the real `QuillCodeMessageBubble` and `QuillCodeToolCardView` components for the latest user prompt, completed `host.file.write` card, artifact preview, and final answer.
- The render smoke checks opacity, color diversity, bright text/control pixels, and QuillCode blue-accent pixels so dark-mode snapshots can stay dark while still failing on blank, monochrome, or missing-result regressions.
- Debug image paths are opt-in through `QUILLCODE_RENDER_SMOKE_IMAGE_PATH` and `QUILLCODE_RENDER_SMOKE_TRANSCRIPT_IMAGE_PATH`, which keeps CI clean while making local visual inspection easy.

Remaining risk:

- `ImageRenderer` is a render-layer smoke, not a real packaged-window click test. It does not synthesize native mouse/keyboard events or prove AppKit menu-bar behavior. The next native coverage layer should launch a packaged `quill-code-desktop` app and drive it through Accessibility/XCTest or a small appshot harness.

## 2026-06-27 Immediate Action Preflight Pass

Overall grade after this slice: **A live-model drift resistance, A deterministic local diagnostics, A- planner scope control**.

The opt-in live smoke exposed a concrete provider failure: `deepseek/deepseek-v4-flash` answered “OpenCL is not installed” from general knowledge when asked “Do you have openclaw?” instead of checking the local `openclaw` executable. This was the same user-visible failure class as earlier empty shell calls and “I'll check...” promises.

Code quality changes:

- Added `AgentImmediateActionPlanner`, a focused preflight planner for high-confidence local tasks before any LLM/provider call: explicit shell commands, `whoami`, disk usage, OpenClaw executable discovery, URL downloads, and simple hello-world file writes.
- Added an explicit `AgentRunner` preflight option and enabled it for the TrustedRouter app runtime and CLI `--live` path before streaming/non-streaming provider calls, so live providers cannot hallucinate answers for these deterministic diagnostics while mock/custom LLM tests keep their exact model path.
- Added `AgentImmediateActionTests` coverage with a deliberately failing LLM client to prove OpenClaw and disk-usage requests do not depend on provider knowledge.
- Reran the opt-in live TrustedRouter smoke after the change; the OpenClaw stage now executes the local command and the full live smoke passes.

Remaining risk:

- The planner is intentionally narrow. Broader natural-language tool planning still depends on the model and the promised-work correction path; new deterministic preflight cases should only be added for actions that are unambiguous, bounded to the workspace/device, and already covered by real-world smoke prompts.

## 2026-06-27 Routed Click Target Architecture Pass

Overall grade after this slice: **A routed-command consistency, A hit-target architecture, A- native pixel measurement**.

The previous click-target work measured many rendered states, but HTML feature renderers still hand-wrote routed buttons. That made it too easy to regress into a control with the right visual size but the wrong command attribute, missing disabled semantics, or a mismatched hit-target class.

Code quality changes:

- Added `WorkspaceHTMLPrimitives.commandButton` and `buttonAttributes` so routed HTML buttons share one implementation for `type`, `data-testid`, `data-command-id`, ARIA labels, titles, roles, disabled state, and default hit-target classing.
- Migrated top-bar Stop/overflow actions, sidebar primary/tool/bulk actions, browser tab actions, transcript retry/context actions, extension/MCP/memory/automation actions, and activity-section toggles to the shared primitive path.
- Preserved structured nested button content where it matters: browser tabs still keep title/URL spans, and activity sections still keep label/count spans while using shared attribute construction.
- Added a parity gate that rejects raw `data-command-id` button literals in HTML renderers except for the two documented nested-content cases.
- Updated HTML renderer tests to assert command routing by semantic contract rather than brittle attribute order.

Remaining risk:

- Native SwiftUI controls are still source-gated for target helpers instead of measured by packaged-app UI automation. Playwright continues to measure the mirrored HTML harness until native appshot/Accessibility pixel checks are wired into CI.

## 2026-06-27 Native Desktop Executable Smoke Pass

Overall grade after this slice: **A- product-executable coverage, A rendered side-effect proof, B+ packaged-window automation**.

The previous native render smoke proved the SwiftUI surface in the test bundle, but it did not execute the built `quill-code-desktop` product. That left a gap where app-target initialization, executable wiring, or product-specific imports could fail while unit tests and the HTML harness stayed green.

Code quality changes:

- Added `QuillCodeDesktopSmokeRunner`, an explicit `--native-render-smoke` mode in the desktop executable that builds isolated temp state, forces the mock runtime, sends a real file-writing prompt through `QuillCodeDesktopController`, and verifies the created workspace file plus transcript message/tool/timeline counts.
- The smoke renders `QuillCodeDesktopRootView` to a deterministic 1280x900 PNG and checks opacity, color diversity, bright text/control pixels, and QuillCode blue-accent pixels before returning a structured JSON report.
- The same product run writes rendered workspace HTML and verifies that the transcript contains the expected `host.file.write` tool and `Wrote \`hello.txt\`.` final answer, so the gate is not satisfied by a merely nonblank chrome image.
- Added `scripts/native-desktop-smoke.sh` as a release-gate wrapper that runs the product executable, verifies the JSON report, verifies the expected tool/final-answer/transcript counts, and rejects missing result HTML or suspiciously tiny PNG output.
- Wired the native executable smoke into `scripts/smoke.sh`, so required CI now covers the desktop product render path in addition to Swift tests, CLI smoke, and Playwright.

Remaining risk:

- This still renders the SwiftUI root view offscreen and exits through a smoke flag; it does not synthesize real clicks/typing against a packaged `.app` window or verify AppKit menu-bar behavior. The next native layer should package the app and drive it through Accessibility/XCTest/appshot automation.

## 2026-06-27 Browser Session Reverse Sync Pass

Overall grade after this slice: **A- app-layer sync architecture, A focused state coverage, B+ live browser feedback loop**.

The visible macOS browser session could already mirror QuillCode browser tabs, but it was still one-way. If a user signed in, clicked through a site, or selected a different tab inside the WebKit session, QuillCode's preview model could remain stale until another model-driven browser action happened.

Code quality changes:

- Added `BrowserSessionUpdate` and `BrowserSessionTabUpdate` as app-layer reverse-sync data types next to the existing sync snapshot.
- Added `WorkspaceBrowserEngine.applySessionUpdate` so visible-session URL/title/active-tab changes update isolated tab state, append browser history, refresh metadata snapshots, and preserve the AppKit/WebKit boundary.
- Exposed `QuillCodeWorkspaceModel.applyBrowserSessionUpdate` through `WorkspaceBrowserWorkflow`, keeping state mutation actor-owned and focused.
- Wired `DesktopBrowserSessionPresenter` to emit reverse updates from native tab selection and WebKit navigation finish events, with `QuillCodeDesktopBrowserCoordinator` installing the model update handler.
- Added focused unit, integration, desktop-controller, and parity coverage for the bidirectional session seam.

Remaining risk:

- Reverse sync currently captures title, URL, and selected tab. Rich live-DOM feedback from user navigation and Linux/browser-process adapters remain pending, but they now have a clear snapshot/update seam to plug into without leaking platform types into `QuillCodeApp`.

## 2026-06-27 Desktop Click Target Hardening Pass

Overall grade after this slice: **A shared target reuse, A rendered clickability checks, A- native pixel measurement**.

The click-target contract covered the main app module and rendered HTML harness, but it still missed visible desktop-only SwiftUI chrome. The menu-bar popover used raw SwiftUI buttons, and explicit Playwright `expectHitTarget` probes measured box size without proving the center and inset corners were actually owned by the intended target.

Code quality changes:

- Made the shared `QuillCodeMetrics`, target modifiers, and `QuillCodePressableButtonStyle` public so desktop SwiftUI can reuse the same hit-target design system instead of copying frame/content-shape logic.
- Routed every visible `QuillCodeMenuBarView` action through one `menuActionButton` helper with full-row 44 pt targets and the standard 0.96 press feedback.
- Expanded native source gating to include visible desktop SwiftUI sources while keeping true AppKit-owned command menu items exempt.
- Strengthened Playwright `expectHitTarget` to require an accessible name, reject `pointer-events: none`, and sample the center plus inset corners with `elementFromPoint`.

Remaining risk:

- The native desktop popover is still source-gated rather than measured by Accessibility/UI automation. The shared primitive and rendered HTML audit reduce drift, but a packaged-app pixel probe remains the next stronger validation layer.

## 2026-06-27 Desktop Chrome Smoke Hardening Pass

Overall grade after this slice: **A desktop command-route coverage, A product-smoke usefulness, B+ packaged menu-bar automation**.

The executable smoke was useful for the main chat path, but desktop chrome could still drift: a command could be visible in the top bar or menu bar while the native command planner silently dropped it. The hardened smoke immediately found one such bug: `keyboard-shortcuts` was present in chrome but did not route through the desktop command planner/coordinator.

Code quality changes:

- Extended `QuillCodeDesktopSmokeRunner` to validate required desktop chrome command IDs, exercise Command Palette, Keyboard Shortcuts, Settings, Terminal, and Browser routes against the real `QuillCodeDesktopController`, and fail if any command does not mutate the expected native state.
- Added the missing first-class `keyboardShortcuts` desktop command action to the planner/coordinator instead of relying on source parity or menu notifications.
- Added a desktop chrome evidence render to the product smoke report, including app name, top-bar title/subtitle, selected model/mode, Computer Use label, required command IDs, and exercised route IDs.
- Updated `scripts/native-desktop-smoke.sh` to require the chrome evidence PNG and command-route JSON fields, so CI now catches visible-but-unrouted desktop chrome regressions.

Remaining risk:

- The chrome evidence panel is deterministic smoke evidence, not a real AppKit menu capture. Raw `MenuBarExtra` menu content does not render faithfully offscreen with `ImageRenderer`, so the true next layer remains packaged `.app` UI automation that opens the menu-bar extra and clicks the commands through Accessibility or XCTest.

## 2026-06-27 Context Fork Control Pass

Overall grade after this slice: **A strategy boundary, A shared renderer contract, A- deterministic summaries**.

The context pressure banner only had one fork action, which forced every “continue with context” decision into the same latest-turn behavior. That was simple, but it did not match Codex-style recovery choices for users who need a smaller, summarized, or full visible-context continuation.

Code quality changes:

- Added `WorkspaceThreadForkStrategy` as the single source for fork command IDs, titles, keywords, thread-title prefixes, notice copy, and banner test IDs.
- Moved fork seeding behind one strategy-aware `WorkspaceThreadSeedBuilder` boundary while keeping legacy `forkSeedMessages(from:)` behavior intact.
- Extended `ContextBannerSurface` with backward-compatible `forkCommands` decoding so old payloads with only `forkCommand` still work.
- Routed command palette actions, SwiftUI banner buttons, static HTML, and the Playwright harness through the same strategy IDs instead of renderer-local forks.
- Reused one derived-thread insertion path in the harness for compact, latest fork, summary fork, and full fork.

Remaining risk:

- Summarized forks still use deterministic local summaries. Exact provider token accounting and model-authored summaries remain separate parity work.

## 2026-06-28 Command Click Routing Audit Pass

Overall grade after this slice: **A- rendered click action routing, A regression coverage, B+ native click automation**.

Large hit targets are not enough if the target routes to no command. The rendered harness already measured size, clipping, overlap, accessible names, and interior ownership, but it could still render a visible `data-command-id` that the mock command router ignored. That leaves a button looking correct while doing nothing when clicked.

Code quality changes:

- Added an explicit harness command routing registry for static command IDs and dynamic prefixes used by slash insertions, automations, memories, MCP, browser tabs, sidebar filters, activity sections, local env actions, and extension commands.
- Added `commandRoutingAuditReport()` and exported it as `window.__quillCodeCommandRoutingAudit`, reporting both unroutable command catalog entries and visible enabled command targets.
- Made `runCommand` reject unknown command IDs and record `lastUnroutableCommandID` instead of silently re-rendering.
- Integrated command-routing checks into the broad Playwright interaction audit so every opened popover, panel, dialog, secondary pane, transcript state, and compact viewport state also proves visible command targets are routable.
- Added a dead-command regression fixture that injects an otherwise visible 44 px button with `data-command-id="definitely-not-routable"` and verifies the audit reports it.
- Added a Swift parity gate so future harness changes keep the routing audit hook, the unknown-command rejection, and the Playwright regression wired together.

Remaining risk:

- This proves the rendered harness command contract and catches silent no-ops in HTML parity states. Native SwiftUI/AppKit packaged-window click automation is still the next deeper layer for proving every actual macOS button invokes the expected controller action.

## 2026-06-28 Native/Rendered Command Routing Parity Pass

Overall grade after this slice: **A rendered/native command registry parity, A PR-command click routing coverage, B+ packaged-window click automation**.

The rendered command audit exposed a second registry alongside the native Swift command surface. That is useful for Playwright, but it creates drift risk: a native command can be added and tested while the rendered harness forgets to route it, leaving a Codex-parity action invisible to E2E interaction audits.

Code quality changes:

- Added `WorkspaceRenderedCommandRoutingParityTests`, which builds a rich native command surface with thread, project, GitHub PR, local environment, MCP, extension, automation, memory, browser, and Computer Use commands.
- The test parses `E2E/harness/index.html` and verifies every native command ID is covered by either the harness static routing registry or a dynamic command prefix.
- Added a focused pull-request descriptor check so new `WorkspacePullRequestCommandCatalog` commands cannot silently drop out of rendered click routing.
- Fixed the rendered harness registry to include every PR command descriptor: checkout, comment, reviewers, labels, merge, review, inline review comment, review reply, review threads, and review-thread resolution.

Remaining risk:

- This prevents native/rendered command registry drift for command IDs. A true packaged-window UI automation layer is still needed to prove AppKit/SwiftUI event delivery from actual pixels through the desktop controller.

## 2026-06-28 Structured Pull Request Review Draft Pass

Overall grade after this slice: **A command-action routing, A review-surface state, A- review-session parity**.

The command-palette `git-pr-review` action was still a composer prefill even though PR review execution had a structured `host.git.pr.review` tool. That made review submission feel less like Codex's dedicated review workflow and kept approve/comment/request-changes validation outside the review pane.

Code quality changes:

- Moved `git-pr-review` from draft-prefill routing into the typed `WorkspaceCommandAction` path.
- Added `WorkspacePullRequestReviewDraftSurface` as review-pane state for action, optional selector, body copy, submit validation, and presentation labels.
- Added a small `WorkspacePullRequestReviewDraftToolCallPlanner` so submit builds the existing `host.git.pr.review` call and reuses local/SSH Remote tool execution.
- Rendered the draft in native SwiftUI and static HTML with shared 44 pt form-action/text-entry target helpers and matching Playwright `data-testid` contracts.
- Added command-palette E2E coverage for opening the draft, switching to request changes, requiring a body, submitting, and verifying the resulting tool-card JSON.

Remaining risk:

- This covers one submitted review at a time. Full Codex-style multi-comment review-session batching, editable pending review queues, and submit-review summaries remain future review-pane work.

## 2026-06-28 Pull Request Review Inline Notes Pass

Overall grade after this slice: **A- review-session parity, A local/SSH routing reuse, A regression coverage**.

The structured PR review draft still ignored review notes that users had already placed on changed diff lines. That forced users to either submit those notes one by one or rely on the model to recreate them, which is too far from Codex's review workflow.

Code quality changes:

- Extended `WorkspacePullRequestReviewDraftSurface` with a snapshot of line/range review notes and an explicit include/skip toggle.
- Added `WorkspacePullRequestReviewDraftCommentSurface` as the normalized bridge from visible diff notes to `host.git.pr.review_comment` arguments, including line ranges and LEFT/RIGHT side mapping.
- Kept submission on the existing `runToolCall` coordinator so inline comments and the final `host.git.pr.review` share local and SSH Remote execution, tool-card recording, safety/audit metadata, and failure handling.
- Mirrored the draft-note preview and toggle in native SwiftUI, static HTML, and the Playwright harness.
- Added focused Swift coverage for note collection, planner arguments, HTML markup, and an SSH Remote integration test that posts an inline comment before the final review. Added Playwright coverage for creating a diff note, opening the PR review draft, and seeing the inline comment tool card before the final review card.

Remaining risk:

- Inline notes are snapshotted when the draft opens. Richer editable pending-review queues, per-note removal/reordering, and a review summary before submit remain future review-pane work.

## 2026-06-28 Click Target Semantics Pass

Overall grade after this slice: **A- native target semantics, A rendered collision audit, B+ packaged-window click automation**.

The app already had broad 44 px hit-target coverage, but two native semantics still needed to be made explicit: interactive parent containers should not collapse live child buttons into one accessibility element, and dense adjacent controls should use named spacing contracts instead of local magic numbers.

Code quality changes:

- Added shared `controlClusterSpacing` and `denseControlClusterSpacing` metrics to the design system so target-spacing decisions are reviewable and consistent.
- Moved dense top-bar, composer, sidebar, model-row, tool-card action, and find-bar control clusters onto the shared spacing metrics.
- Changed top-bar and tool-card containers from `.accessibilityElement(children: .combine)` to `.contain`, preserving child targets for buttons, menus, disclosures, and action rows.
- Added a native parity gate that blocks regressions back to parent-combined interactive containers and checks that high-risk adjacent controls use named target spacing.

Remaining risk:

- The static SwiftUI gate catches source-level target contracts and the Playwright harness catches rendered HTML target size, clipping, overlap, and routing. True packaged-window pixel clicking across every native SwiftUI control remains the deeper future layer.

## 2026-06-28 Pull Request Review Pending Queue Pass

Overall grade after this slice: **A review-draft state model, A selected-note dispatch, A- review-session parity**.

The previous inline-note draft support was still all-or-nothing: a user could include every saved line note or skip all of them, and the draft preview only showed the first few notes. That was not enough for Codex-style pending review workflows where users decide exactly which comments ship with the final review.

Code quality changes:

- Added per-note `isIncluded` state to `WorkspacePullRequestReviewDraftCommentSurface`, with backward-tolerant decoding so older saved draft snapshots default to included.
- Kept `WorkspacePullRequestReviewDraftSurface.selectedInlineComments` as the single dispatch boundary, now filtering both the global inline-note toggle and per-note Included/Skipped choices.
- Updated the native SwiftUI draft to render every pending inline note with a full-size Included/Skipped action pill instead of a tiny checkbox or truncated preview.
- Mirrored the pending-note queue in the static HTML renderer and Playwright harness, including state syncing for action/body/selector edits so queue toggles cannot wipe typed draft fields.
- Added focused Swift coverage for selected-note counts, legacy decoding, skipped-note tool planning, rendered markup, and SSH Remote dispatch. Added Playwright coverage that creates two saved inline notes, skips one, and verifies only the selected note is posted before the final review.

Remaining risk:

- This queue supports include/skip decisions only. Richer per-note text editing, reordering, and a final submit-summary screen remain future review-pane work.

## 2026-06-28 Editable Pull Request Review Notes Pass

Overall grade after this slice: **A editable note state, A validation boundary, A- review-session parity**.

The pending inline-note queue could include or skip saved diff notes, but the note text itself was still fixed at draft-open time. That left users unable to polish a comment before submitting a GitHub review, which is a core Codex review-session behavior.

Code quality changes:

- Added `normalizedBody` and `invalidSelectedInlineComments` to the PR review draft surface so selected inline notes are validated before any tool call is built.
- Added a shared `updateInlineComment` mutation path for toggling and editing queued notes, keeping queue state inside the review-surface model instead of view-local state.
- Updated the tool-call planner to post trimmed edited note text and reject empty selected notes before creating `host.git.pr.review_comment` calls.
- Replaced static native inline-note copy with an editable multiline text field and an inline warning when a selected note has no text.
- Mirrored editable note bodies in the HTML renderer and Playwright harness without re-rendering on every inline-note keystroke, preserving focused text entry while still updating submit validation.
- Added focused Swift and Playwright coverage for edited note dispatch, empty-note blocking, skipped-note unblocking, and SSH Remote GitHub API arguments.

Remaining risk:

- Inline-note reordering and a final submit-summary screen remain future review-pane work. The harness still duplicates some Swift display logic, so shared renderer contracts or generated fixtures remain a good future cleanup.

## 2026-06-28 Explicit Click Target Ownership Pass

Overall grade after this slice: **A rendered target ownership, A source-gated generated HTML inputs, A- native-packaged click automation**.

The prior audits proved minimum size, clipping, overlap, nested target, center ownership, command routing, and native helper usage. The missing layer was target ownership: a visible control could be large enough but still be a one-off element outside the shared click-target design system.

Code quality changes:

- Added neutral `hit-target-owned` and semantic `hit-target-text-entry` classes for controls whose visible shape is already supplied by native browser semantics or field styling.
- Made the Playwright interaction audit fail visible interactive controls that do not carry one of the shared hit-target classes.
- Normalized dynamic harness controls after render so mock-only UI states use the same target contract as generated app HTML.
- Kept hidden accessibility labels and passive text-field labels out of the target normalizer, while preserving checkbox/radio label auditing for intentional tap surfaces.
- Extended the Swift source gate to include raw generated `input`, `select`, and `textarea` controls, then updated composer, terminal, browser, and PR review renderers to use the text-entry target class.

Remaining risk:

- This proves rendered harness/source contracts and catches uncategorized HTML controls. Packaged-window pixel automation across every native SwiftUI/AppKit control remains the deeper layer for final desktop event-delivery proof.

## 2026-06-28 Pull Request Review Submit Summary Pass

Overall grade after this slice: **A review-draft derived state, A native/static/harness parity, A- review-session parity**.

The PR review draft had editable pending inline notes, but users still had to infer the final submission shape from controls scattered through the pane. Codex-style review sessions need a compact final summary before submission so action, target, body readiness, skipped notes, and invalid selected notes are obvious.

Code quality changes:

- Added `WorkspacePullRequestReviewDraftSubmitSummarySurface` as a pure derived value from the existing draft state instead of adding persisted UI state.
- Rendered the submit summary in SwiftUI and static HTML with ready/blocked state, target, body readiness, and inline-note selected/skipped/invalid counts.
- Mirrored the summary in the Playwright harness and updated it live while typing or toggling notes without re-rendering the form and stealing focus.
- Added Swift and Playwright coverage for ready, blocked, skipped-note, invalid-note, selector, and body-required summary states.
- Updated the parity matrix and decision log so future review-note reordering builds on the same draft surface.

Remaining risk:

- Inline-note reordering was the next review-session parity gap after this pass. The harness still duplicates some Swift summary display logic, so generated fixture parity would be a useful future cleanup.

## 2026-06-28 Pull Request Review Inline Note Reordering Pass

Overall grade after this slice: **A draft mutation boundary, A dispatch-order coverage, A- full review-session parity**.

The pending inline-note queue could edit, skip, and summarize notes, but the note order was still fixed to diff traversal order. Codex-style review sessions need users to control the final comment order before publishing a PR review.

Code quality changes:

- Added `moveInlineComment(id:offset:)` to `WorkspacePullRequestReviewDraftSurface` so reordering is a clamped draft mutation rather than view-local state.
- Rendered explicit up/down icon controls in the SwiftUI draft row with boundary disabled states, help text, and accessibility labels while preserving existing 44 pt target helpers.
- Mirrored reorder controls in static HTML and the Playwright harness, syncing current form values before rerendering so moving a row cannot drop edited note text.
- Kept `selectedInlineComments` as the single dispatch boundary, so reordered selected notes naturally flow through `WorkspacePullRequestReviewDraftToolCallPlanner` and final `host.git.pr.review_comment` call order.
- Added Swift and Playwright coverage for draft reordering, boundary clamping, rendered controls, and final planner order.

Remaining risk:

- The PR review queue now covers include, skip, edit, reorder, readiness summary, and dispatch ordering. Remaining review-pane work should focus on richer native diff affordances and shared Swift/HTML fixture generation rather than more draft state.

## 2026-06-28 Native Action Click Target Pass

Overall grade after this slice: **A native action primitives, A source gate, A- packaged-window pointer automation**.

Native SwiftUI action buttons still mixed shared hit-target modifiers with compact platform button styles. That kept most controls large enough, but the visible surface, disabled treatment, and press feedback were split between QuillCode and SwiftUI defaults.

Code quality changes:

- Added `QuillCodeActionButtonStyle` with primary, secondary, and destructive tones that own the visible action surface, 44 pt minimum target, rounded tappable shape, disabled opacity, and 0.96 press feedback.
- Migrated settings, context banners, automations, extensions, memories, worktree dialogs, browser comments, Computer Use setup, terminal Stop, and artifact links away from `.bordered`, `.borderedProminent`, and `.plain`.
- Tightened `ParityInteractionTargetGateTests` so visible app and desktop code must use QuillCode-owned action or pressable styles instead of compact platform button styles.

Remaining risk:

- Source gates and Playwright rendered audits now cover the shared target contracts. Full packaged-window pointer automation across native macOS controls remains the deeper final proof layer.

## 2026-06-28 Tool-Call Wrapper Parsing Pass

Overall grade after this slice: **A action extraction, A argument normalization, A- live provider drift coverage**.

Live model failures that look like “queued empty command” are often not tool-executor bugs; they come from valid intent wrapped in provider-specific action shapes. The parser already recovered several QuillCode-near JSON and prose cases, but it did not understand common `tool_calls`, `function_call`, `tool_use/input`, or stringified-arguments envelopes.

Code quality changes:

- Added wrapper-aware action extraction for OpenAI chat `choices[].message.tool_calls[].function`, Responses-style `output` entries, Anthropic-style `tool_use` entries, and direct `function_call` objects.
- Kept extraction and schema cleanup split: the parser only chooses one action object, while `AgentToolArgumentNormalizer` decodes `arguments`/`args`/`input` dictionaries or stringified JSON and applies canonical key aliases.
- Preserved the existing empty-command guard and passive-promise correction instead of silently accepting invalid shell calls.
- Added focused tests for wrapper parsing, stringified arguments, `input` aliases, and canonical shell/file/browser arguments.

Remaining risk:

- This hardens deterministic parser coverage. The opt-in live TrustedRouter smoke remains the proof lane for actual provider/model behavior across passive promises, empty shell args, file side effects, download side effects, and persisted transcript integrity.

## 2026-06-28 Project Instruction Conflict Diagnostics Pass

Overall grade after this slice: **A- instruction diagnostics, A scope discipline, B+ conflict review UX**.

The instruction pipeline already made broad-to-specific scope precedence visible, but it only flagged structural risk. Users could still load explicit opposing instructions and have the model silently resolve them by order.

Code quality changes:

- Added conservative semantic-conflict diagnostics for high-confidence opposing rules such as requiring tests versus avoiding tests over the same or nested scopes.
- Kept contradiction detection inside `ProjectInstructionDiagnosticsBuilder` so WorkspaceModel, Activity projection, and prompt building stay decoupled from rule-analysis details.
- Deduplicated repeated phrases per instruction and avoided sibling-scope conflicts, because sibling rules can intentionally differ.
- Added focused unit coverage plus a parity gate requiring visible conflict diagnostics.

Remaining risk:

- This is deterministic, intentionally conservative text analysis. A richer conflict review UI and optional model-assisted rule audit are still needed before this reaches full Codex parity.

## 2026-06-28 Activity Instruction Review Section Pass

Overall grade after this slice: **A section derivation, A- review visibility, B+ conflict resolution UX**.

Instruction conflicts were visible as source diagnostics, but users still had to find them inside the mixed Sources section. Codex parity needs important workflow risks to have a dedicated place in the activity/task pane.

Code quality changes:

- Added `instructionReview` as a first-class `ActivitySectionKind` with issue-oriented count labels and a dedicated `activity-instruction-conflict` test ID.
- Derived the section from existing conflict diagnostic source rows, keeping one source of truth instead of adding persisted review state.
- Prioritized conflict diagnostics inside the existing source cap so the review section cannot disappear behind lower-severity structural diagnostics.
- Added Swift and HTML renderer coverage plus architecture gates for the first-class section.

Remaining risk:

- The section makes conflicts visible and reviewable. Follow-up parity work should add source-to-file navigation, edit actions, and explicit resolve/dismiss state once the project file-editing UX is ready.

## 2026-06-28 Click Target Semantic Contract Pass

Overall grade after this slice: **A target semantics, A rendered audit, A- native rendered-window proof**.

The click-target system already enforced 44 px/pt targets, interior clickability, pointer affordance, no nested targets, no peer overlap, and command routing. The remaining weakness was semantic drift: generic fallback classes could make controls large enough while hiding whether the control was intended to be an icon, text button, row, capsule, form action, text entry, or link.

Code quality changes:

- Changed the dynamic rendered harness normalizer to classify fallback targets by role and visible shape instead of defaulting most controls to `hit-target-owned`.
- Added `data-hit-target-kind` on normalized controls so rendered debugging can distinguish explicit target contracts from auto-classified fallbacks.
- Added focus-visible treatment for summaries, semantic links, ARIA controls, and shared hit-target classes so keyboard focus gets the same affordance as mouse/touch targets.
- Tightened the critical Playwright registry so high-risk controls assert their expected semantic class in addition to 44 px geometry and 3x3 interior ownership.
- Promoted top-bar overflow actions, model picker options, and command palette results to row targets where the visible UI behaves as a full-row choice.

Remaining risk:

- The rendered harness and Swift source gates now prove intent and geometry. The deeper remaining proof layer is packaged native UI automation that samples actual macOS/Linux SwiftUI control interiors the way Playwright samples rendered HTML.

## 2026-06-28 Activity Instruction Source Actions Pass

Overall grade after this slice: **A typed action contract, A command routing, A- full source-resolution UX**.

Instruction Review made project-rule conflicts visible, but the rows still ended at passive diagnostics. Users needed obvious click targets to inspect the loaded instruction source, start an edit, or resolve a conflict without hunting through the filesystem manually.

Code quality changes:

- Added typed `ActivityItemActionSurface` metadata to Activity items so native SwiftUI, static HTML, and the Playwright harness share one source-action contract.
- Added Open/Edit actions to instruction source rows and Resolve actions to instruction conflict diagnostics.
- Routed `activity-source-open:*`, `activity-source-edit:*`, and `activity-instruction-resolve:*` through `WorkspaceCommandPlan` and `WorkspaceCommandPlanExecutor` instead of feature-local click handlers.
- Kept mutations explicit: Open runs the bounded `host.file.read` tool, while Edit/Resolve seed composer drafts so edits still go through the normal model, safety, file-write, and review flow.
- Added Swift surface/executor/HTML coverage plus Playwright coverage that clicks Open/Edit and verifies the resulting tool card and composer draft.

Remaining risk:

- This closes the first source-action gap. Richer native editor jump-to-line, diff-assisted conflict fixes, and explicit resolved/dismissed state remain the next AGENTS/rules parity layer.

## 2026-06-28 Activity Instruction Diagnostic Dismissal Pass

Overall grade after this slice: **A UI-state boundary, A command routing, A- durable conflict-resolution UX**.

Resolve made conflict diagnostics actionable, but there was still no lightweight way to clear a reviewed diagnostic from the Activity pane without editing instruction files. This pass adds Dismiss as a UI-only state transition so users can keep the Activity pane focused while preserving the underlying project rules and audit trail.

Code quality changes:

- Added `dismissedInstructionDiagnosticIDs` to `ActivityState`, keeping reviewed diagnostic visibility in workspace UI state instead of mutating thread messages or project instruction records.
- Added typed `activity-instruction-dismiss:*` routing through `WorkspaceCommandPlan` and `WorkspaceCommandPlanExecutor`, matching the existing Open/Edit/Resolve command path.
- Filtered dismissed diagnostics in `WorkspaceActivitySourceSurfaceBuilder` so Instruction Review and Sources stay consistent across SwiftUI/static HTML/Playwright surfaces.
- Updated the Playwright harness to render the same Instruction Review section data and to exercise Dismiss end to end.

Remaining risk:

- Dismiss is intentionally session/workspace UI state. Durable project-level resolution records, diff-assisted rule edits, and native editor jump-to-line remain future AGENTS/rules parity work.

## 2026-06-28 Critical Click Target Source Contract Pass

Overall grade after this slice: **A explicit target ownership, A Playwright proof, A- native packaged-window proof**.

The previous click-target pass made rendered controls measurable and semantically classified, but critical controls could still pass the registry through an `auto-*` classification added after render. That was too weak for primary actions because a future UI edit could accidentally depend on fallback geometry while losing the intended button, row, capsule, icon, form-action, or text-entry semantics.

Code quality changes:

- Promoted primary harness controls to explicit semantic target classes across top bar, sidebar, composer, settings, search, command palette, Find, terminal, browser, model picker, slash suggestions, and transcript tool cards.
- Centralized Playwright target constants so the audit report and edge/interior probe use the same 44 px baseline, shared target class list, and 3x3 sample grid.
- Tightened `expectCriticalTargetRegistry` to require the expected class and matching non-fallback `data-hit-target-kind`, so high-risk controls cannot pass by fallback normalization alone.
- Added browser-tab coverage to the critical registry because tab strips are easy to regress into tiny or overlapping controls.

Remaining risk:

- This is strong for the HTML harness and source gates. The remaining A+ proof is packaged native macOS/Linux UI automation that samples real SwiftUI control interiors, focus rings, and click ownership outside the harness.

## 2026-06-28 Terminal Interactive Stdin Pass

Overall grade after this slice: **A line-oriented terminal input, A lifecycle cancellation, A- full PTY parity**.

The integrated terminal could stream output and cancel commands, but the command field went inert while a process was running. That blocked common interactive shell flows such as a script prompting for a value, and made the terminal feel less like Codex even though the shell runner could own a real stdin pipe.

Code quality changes:

- Added `ShellStreamingSession` as the public streaming handle so callers can keep the existing async event stream while also sending stdin or cancelling the active runner.
- Kept process lifecycle ownership inside `ShellStreamingProcessRunner`; it now creates a stdin pipe before launch completes, writes input through a throwing `FileHandle` API, closes stdin on cancel/finish, and still emits the final `ToolResult` through the existing stream.
- Added `WorkspaceModel.sendTerminalInput` and a model-held active session reference so Stop All cancels the real shell process, not only the UI entry state.
- Updated SwiftUI, static HTML, and Playwright harness terminal controls so Run becomes Send during active commands, the input stays focusable, Clear remains unavailable, Stop remains explicit, and Up/Down history recall stays disabled while the process is running.
- Added shell, workspace-model, terminal-surface, and Playwright coverage for running-command stdin.

Remaining risk:

- This is deliberately line-oriented stdin support. Full PTY features such as alternate screen buffers, cursor-addressed TUIs, terminal resizing, job control, and raw-mode interactive programs still require a dedicated PTY adapter.

## 2026-06-28 Secondary Pane Click Target Coverage Pass

Overall grade after this slice: **A secondary target semantics, A edge-click regression coverage, A- native packaged-window proof**.

The main chrome already had explicit semantic target classes plus center, interior, edge, overlap, nesting, and routing audits. The remaining click-target quality gap was secondary-pane drift: extension, memory, and automation controls could rely on harness fallback classification even though the Swift renderer had explicit contracts.

Code quality changes:

- Added explicit semantic target classes to the Playwright harness for extension install/start/stop/update actions, MCP resource/prompt capsules, memory add/edit/delete actions, and automation create/run/pause/delete/schedule actions.
- Promoted Extensions, Memories, and Automations into the named critical click-target registry so those panes are reviewed with the same standard as top-bar, model picker, settings, terminal, browser, and transcript controls.
- Added edge-click behavioral coverage for terminal, browser tabs/comments, extension MCP actions, memory edits, and automation runs so controls must respond away from the center, where missed taps commonly happen.
- Updated the parity gate so future interaction-audit edits must keep secondary-pane critical coverage and behavioral probes in place.

Remaining risk:

- The harness and source gates now cover secondary panes deeply. The remaining A+ layer is still packaged native UI automation that samples actual SwiftUI/AppKit control frames and click ownership in a running macOS/Linux app.

## 2026-06-28 Native Hit Target Audit Smoke Pass

Overall grade after this slice: **A native semantic target audit, A release-smoke evidence, A- AppKit frame sampling proof**.

The rendered HTML and Playwright layers had strong click-target geometry, semantic-kind, overlap, and edge-click coverage. The native app still relied mostly on Swift source gates plus rendered PNG pixel sanity checks, so the desktop executable smoke could not explain which native target contracts were actually expected in the running app state.

Code quality changes:

- Added `QuillCodeNativeHitTargetAudit`, a typed report for native SwiftUI target semantics, required command IDs, 44 pt minimum dimensions, 0.96 press scale, and visible secondary-pane contracts.
- Wired the audit into `quill-code-desktop --native-render-smoke`, so CI now receives machine-readable native target evidence in the product smoke JSON and fails if core command targets or design-system kinds disappear.
- Added focused unit and parity gates for the native audit report, including representative terminal, browser, extension, memory, and automation pane contracts.
- Tightened native secondary-pane buttons so Extensions, MCP resource/prompt actions, Memories, and Automations declare explicit form/capsule target helpers instead of relying only on action button styling.

Remaining risk:

- This proves the native target contract through SwiftUI semantics and the packaged executable smoke report. It still does not sample live `.app` Accessibility frames or perform OS-level edge clicks in a real window; that remains the final A+ native interaction layer.

## 2026-06-28 Semantic Native Button Target Pass

Overall grade after this slice: **A native semantic ownership, A source gate strictness, A- live frame sampling**.

The previous native source gate still allowed `QuillCodeActionButtonStyle` to satisfy click-target ownership. That was too loose because a style describes visual treatment and press feedback, not whether the control is intended to be a form action, text button, icon target, capsule target, or full-row target.

Code quality changes:

- Removed `QuillCodeActionButtonStyle` from the native hit-target source gate's target marker list, so styled buttons now require an explicit semantic target helper.
- Added the missing semantic helpers to settings, Computer Use setup, context banner actions, terminal stop, browser comment, and worktree dialog footer actions.
- Added a regression test proving a styled button without a semantic target is rejected.

Remaining risk:

- This closes the style-vs-semantics gap at source level. The next native A+ layer is still real packaged-window Accessibility frame and edge-click sampling.

## 2026-06-28 Desktop Optimistic Send And Thinking Trace Target Pass

Overall grade after this slice: **A desktop optimistic state proof, A native thinking trace target, A- packaged-window event automation**.

The desktop send path already had workspace-model coverage, but the user-facing bug was subtler: a native coordinator can have correct model state while failing to repaint the user bubble and Thinking indicator until the agent finishes. Thinking traces also need to feel intentionally clickable instead of appearing as tiny disclosure text.

Code quality changes:

- Added a desktop coordinator smoke test that sends through `QuillCodeDesktopComposerCoordinator` with a slow mock LLM and asserts the draft clears, the user message is visible, Thinking is visible, and the send task is running before the model responds.
- Replaced the native Thinking trace disclosure label with a semantic capsule button that has chevron state, event count, press feedback, a 96 pt target contract, and explicit accessibility label/value.
- Added the Thinking trace capsule to `QuillCodeNativeHitTargetAudit` whenever visible trace lines exist, and extended the representative audit fixture so the target cannot disappear without failing tests.

Remaining risk:

- This covers the coordinator and SwiftUI target contract. The remaining A+ layer is a packaged-window Accessibility click test that samples the live trace control frame and clicks near its edges in a running `.app`.

## 2026-06-28 Subagent Scheduler Runtime Slice

Overall grade after this slice: **A scheduler architecture, A replayable Activity state, B+ model-backed worker parity**.

Subagents previously had a good visible progress contract, but execution was still model-authored display state only. That meant QuillCode could show parallel-agent progress without having a local runtime that actually fans out work and replays progress from the event log.

Code quality changes:

- Added `WorkspaceSubagentScheduler`, an injectable-worker scheduler that runs workers with Swift task groups, emits queued/running/per-worker-completed updates, preserves partial success when one worker fails, and aggregates a concise final summary.
- Added `/subagents objective | Name: role` with a bounded deterministic parser so users and tests can run an explicit local parallel workflow without relying on model guessing.
- Added `WorkspaceSubagentSlashCommandRunner`, which appends the user request, records progress through the existing `host.subagents.update` tool/event path, updates Activity from replayable events, and writes the final assistant summary.
- Added parser, scheduler concurrency, dispatch-planner, workspace integration, and parity-gate coverage so future changes cannot regress subagents back to display-only state.

Remaining risk:

- The scheduler is ready for real agent workers, but the default slash-command worker is still a deterministic local worker. Full Codex parity still needs model-backed subagent sessions, cancellation, per-worker transcript drilldown, and richer dependency/status controls.

## 2026-06-28 Click Target Ownership Hardening Pass

Overall grade after this slice: **A semantic target architecture, A source-gate coverage, A- live packaged-window sampling**.

The click-target system already enforced 44 pt geometry, semantic helpers, rendered Playwright audits, and native smoke evidence. The remaining architectural weakness was that local SwiftUI views could still introduce raw hit-shape or hit-testing overrides, and custom gesture regions had no first-class semantic target.

Code quality changes:

- Added an `ownedGesture` native target kind plus `quillCodeOwnedGestureTarget`, a named escape hatch for intentional custom gesture regions that still enforces 44 pt minimum shape and button accessibility traits.
- Extended the native hit-target audit and desktop smoke contract so the owned-gesture kind is release evidence alongside icon, text, form, text-entry, segmented, adjustable, switch, full-row, and capsule targets.
- Tightened `SwiftSourceInteractionTargetAudit` to reject raw `.contentShape(...)`, `.allowsHitTesting(...)`, and unnamed tap/long-press/priority gestures outside the shared design system.
- Added regression tests proving raw hit-shape and hit-testing overrides fail, named owned gesture targets pass, and unnamed gestures are blocked.

Remaining risk:

- Source, semantic, rendered, and smoke gates are now stronger. The final A+ layer is still a packaged-window Accessibility frame sampler that clicks near target edges in the live macOS app.

## 2026-06-28 Subagent Cancellation Progress Pass

Overall grade after this slice: **A scheduler cancellation contract, A replayable Activity state, B+ Stop All worker wiring**.

`WorkspaceSubagentScheduler` previously collapsed `CancellationError` into the generic failed-worker path. That made an interrupted worker look equivalent to a broken worker and left future Stop All wiring without a clean replayable state.

Code quality changes:

- Added `SubagentStatus.cancelled` and updated the `host.subagents.update` schema enum so cancellation is part of the public progress contract.
- Added a typed scheduler worker outcome so completed, cancelled, and failed results are handled explicitly instead of flowing through a generic `Result<String, Error>`.
- Added focused scheduler and parity coverage to keep cancellation separate from failure in progress updates and final summaries.

Remaining risk:

- This establishes scheduler-level cancellation semantics. The next parity step is wiring Stop All or worker timeouts into active model-backed subagent sessions once those sessions exist.

## 2026-06-28 Subagent Slash Cancellation Wiring Pass

Overall grade after this slice: **A slash cancellation lifecycle, A stopped-state preservation, B+ model-backed worker parity**.

After scheduler cancellation became a first-class status, the slash-command path still had a stale completion edge: a cancelled `/subagents` send could finish the scheduler, append a normal final summary, and flip the top bar back to Idle.

Code quality changes:

- Added an injectable `subagentScheduler` on `QuillCodeWorkspaceModel` so cancellation behavior can be tested through the real composer/slash path.
- Stopped `/subagents` runs now keep cancelled progress but skip the final assistant summary when the surrounding send task is cancelled.
- Slash-command completion now preserves `Stopped` top-bar state when the task was cancelled instead of blindly reporting `Idle`.
- Added composer integration and parity coverage for the stopped-state/no-fake-summary behavior.

Remaining risk:

- This covers deterministic slash-command subagent workers. Full Codex parity still needs model-backed subagent sessions with per-worker transcript drilldown and richer dependency controls.

## 2026-06-28 Click Target Surface-Family Pass

Overall grade after this slice: **A target ownership, A surface-family coverage, A- native accessibility-frame sampling**.

The click-target system already enforced 44 pt helpers, source gates, rendered Playwright probes, and native smoke validation, but the mental model was still too call-site oriented. A control could be well sized while an entire transient surface family, such as command palette, settings, model picker, or menu-bar actions, quietly fell out of the release evidence.

Code quality changes:

- Added `QuillCodeInteractionSurfaceFamily` so every native hit-target contract records where the user interacts, not only what shape the target uses.
- Added canonical transient-surface contracts for sidebar thread rows, transcript message actions, tool cards, context banners, command palette, search, settings, model picker, review, secondary panes, terminal, browser, extensions, memories, automations, and menu-bar popover actions.
- Extended the native audit report and desktop smoke contract to fail if any expected surface family is missing.
- Updated parity and unit tests so click-target reviews start with the surface-family inventory before inspecting individual controls.

Remaining risk:

- This is still semantic/source/native-smoke evidence. The next A+ layer is packaged native UI automation that samples actual Accessibility frames for each family on a built `.app`, matching the rendered Playwright interior sampling already used for the HTML harness.

## 2026-06-28 Icon Target Naming Pass

Overall grade after this slice: **A native icon target clarity, A source-gate coverage, A- packaged accessibility-frame sampling**.

The click-target model now treats icon-only controls as a naming problem as well as a sizing problem. A 44 pt ellipsis, chevron, or close button is still poor UX if the target has no discoverable label or tooltip.

Code quality changes:

- Tightened `SwiftSourceInteractionTargetAudit` so every native `.quillCodeIconButtonTarget` outside the design system must be in a control scope with `Label(...)`, `.accessibilityLabel(...)`, or `.help(...)`.
- Added regression fixtures proving bare-image icon buttons and menus fail while named icon buttons, icon-only labels with text, and tooltipped menus pass.
- Named the sidebar thread action ellipsis and transcript Find previous/next/close buttons with explicit help and accessibility labels.

Remaining risk:

- This still verifies source-level naming. Full A+ native parity needs packaged `.app` Accessibility automation that samples the real accessibility label and frame for icon targets after SwiftUI/AppKit composition.

## 2026-06-28 Menu Trigger Icon Scope Pass

Overall grade after this slice: **A native menu trigger semantics, A source-gate precision, A- packaged accessibility-frame sampling**.

The previous icon naming gate was strong for normal buttons, but menu triggers had one subtle false-positive risk: the source scope could include named menu items inside the body and accidentally treat those names as proof that the compact trigger itself was discoverable.

Code quality changes:

- Scoped icon target naming for `Menu` declarations to the trigger label and outer menu modifiers instead of the full menu body.
- Added a regression fixture where a menu item has its own help tooltip while the trigger ellipsis remains unnamed, and verified the trigger still fails the native source audit.
- Documented the menu-trigger naming boundary so future click-target passes do not weaken the opener/item distinction.

Remaining risk:

- The gate now proves trigger naming at source level. The final A+ layer remains packaged `.app` Accessibility automation that samples real menu opener labels and frames after SwiftUI/AppKit composition.

## 2026-06-28 Native Hit Target Report Integrity Pass

Overall grade after this slice: **A native report integrity, A CI smoke evidence, A- packaged accessibility-frame sampling**.

Native hit-target smoke already covered semantic kind, surface family, focus targets, minimum size, and press scale. The remaining weakness was that the report could still become harder to debug if a future contract had an empty label/source or reused another contract ID.

Code quality changes:

- Added contract-level validation for empty ID, surface, accessible label, source, undersized icons, and minimum-height regressions.
- Added report-level duplicate contract ID detection and surfaced it in the native smoke JSON.
- Updated the shell smoke parser to fail on duplicate IDs or blank contract metadata, so packaged executable evidence remains trustworthy in CI.
- Added focused unit and parity coverage for the stricter report shape.

Remaining risk:

- This improves the evidence substrate for native click targets. The final A+ layer remains packaged `.app` Accessibility automation that uses these stable IDs to sample real frames and labels from the running app.

## 2026-06-28 Immediate File-Write Intent Pass

Overall grade after this slice: **A- immediate utility, A parser ownership, A ambiguous-request safety**.

QuillCode already recovered common shell commands and the special hello-world file request, but obvious file-write requests still had too much room to depend on provider behavior. That made it possible for weaker models to answer "I'll create it" before using a tool, or to route through a duplicated mock-only heuristic.

Code quality changes:

- Added `AgentFileWriteRequestParser` as the single high-confidence parser for common "write/create/make a file ... that says/with content ..." requests.
- Replaced the immediate planner's hard-coded hello-world file block with the shared parser while preserving `hello.txt` for the existing hello-world flow.
- Reused the same parser from `MockLLMClient`, removing the duplicate mock-only file-write heuristic and keeping fallback shell writes path-aware.
- Added regression tests proving named nested-path writes run without a provider round trip, quoted-content writes default to `note.txt`, and ambiguous "Make a file" still goes through the model instead of manufacturing an empty write.

Remaining risk:

- This deliberately handles only high-confidence file-write phrasing. Full Codex parity still needs model/tool-call reliability across richer edit intents, multi-file creation, and follow-up clarification flows.
