# Swift Project Desktop Evaluations

This suite verifies that Quill Cowork can do real iOS and macOS development from the visible desktop
app. The goal is not prompt trivia. Every evaluation starts by choosing a project through
**Open Project**, creating a project-scoped chat, and asking for an observable engineering outcome.

The machine-readable source of truth is
[`swift-project-eval-catalog.json`](swift-project-eval-catalog.json).

## Shared Contract

Every run must prove all of the following:

1. The selected project path is visible in the project rail and becomes the tool working directory.
2. The user turn appears immediately, followed by visible thinking or queued tool state.
3. Quill Cowork executes the work in the same turn instead of replying with only a plan.
4. Shell tool calls contain complete commands and retain their input, output, exit code, and execution
   context in inspectable tool cards.
5. Build and test claims are grounded in command output. A returned launch PID alone does not prove
   that an app remained alive or rendered.
6. The final answer reports the exact build, test, and launch outcome without inventing evidence.
7. A run preserves unrelated files, credentials, signing settings, and simulator data.

For simulator tasks, retain the `.xcresult`, the expanded Quill Cowork tool card, and a simulator
screenshot. For macOS tasks, retain the test result and a screenshot of the running app or menu-bar
surface. A clean fixture Git diff is required when the task is diagnostic-only.

## Ten Evaluations

### SWIFT-001: Build, Test, Install, and Launch a SwiftUI iOS App

Open a small SwiftUI application with an XCTest target. Ask Quill Cowork to discover the project and
scheme, run the tests on an already booted iPhone simulator, install the built product, and launch it.

Pass when one complete `xcodebuild test` succeeds, the expected test count is reported, the requested
simulator owns a live application process, and a screenshot contains the fixture's expected text.
This flow was manually verified on 2026-08-09 with an iPhone 17 Pro simulator: one test passed with
zero failures and the launched app rendered `Built by QuillCode`.

### SWIFT-002: Repair Swift 6 Strict-Concurrency Failures

Open a fixture that fails under complete concurrency checking because mutable shared state crosses a
task boundary and a non-Sendable dependency is captured by an `@Sendable` closure. Ask Quill Cowork
to diagnose the compiler output and make the smallest idiomatic repair.

Pass when the fix uses appropriate actor isolation or Sendable value semantics, does not hide the
diagnostic with `@unchecked Sendable`, and both `swift test` and an iOS simulator build pass with
strict concurrency enabled.

### SWIFT-003: Implement and Test an Async URLSession Client

Open an iOS project containing an incomplete async API client and a fixture `URLProtocol`. Ask Quill
Cowork to implement typed request/response handling, non-2xx errors, cancellation, and deterministic
tests without using the public network.

Pass when success, decoding failure, HTTP failure, and cancellation tests pass; the production API is
`async throws`; cancellation is preserved; and no test sleeps, reaches the Internet, or depends on
execution order.

### SWIFT-004: Complete a SwiftData Schema Migration

Open a SwiftData app whose new model version adds a required user-visible field. Provide a version-one
fixture store and ask Quill Cowork to preserve its records while completing the migration and updating
the UI.

Pass when an in-memory migration test and a simulator integration test both pass, existing records
survive with a documented default, newly created records persist the new value, and the app launches
against the migrated fixture without deleting the store.

### SWIFT-005: Fix Typed Navigation and Deep Linking

Open a SwiftUI `NavigationStack` app with broken typed routes and a deep link that opens the wrong
detail. Ask Quill Cowork to repair navigation, state restoration, and the incoming URL path.

Pass when unit tests cover route parsing, a UI test launches with the deep-link argument and reaches
the expected accessibility identifier, back navigation restores the list state, and no global
singleton is introduced to coordinate navigation.

### SWIFT-006: Make a Screen Work with VoiceOver and Large Dynamic Type

Open an iOS settings screen with unlabeled icon buttons, undersized hit targets, clipped text, and
incorrect reading order. Ask Quill Cowork to fix accessibility without visually replacing the screen.

Pass when controls expose concise labels and values, tappable targets meet 44-point minimums, content
remains usable at the largest accessibility text size, the UI test can activate every control by
accessibility identifier, and simulator screenshots show no overlap or truncation.

### SWIFT-007: Localize a Feature with a String Catalog

Open an app with hard-coded English copy, plural-sensitive item counts, and formatted dates. Ask Quill
Cowork to add English and Spanish localization using a string catalog and locale-aware formatting.

Pass when source code contains no duplicated user-facing literal for the feature, singular and plural
tests pass in both locales, an iOS UI test launches in Spanish, and screenshots show the translated
screen without clipped controls.

### SWIFT-008: Build a Persistent macOS Menu-Bar Utility

Open a macOS SwiftUI project with a `MenuBarExtra`, settings window, and incomplete preference model.
Ask Quill Cowork to connect the menu commands to persisted settings and make relaunch state reliable.

Pass when `xcodebuild test -destination platform=macOS` succeeds, the packaged app launches, the
menu-bar item is discoverable through macOS Accessibility, changing a preference updates the menu,
and quitting and relaunching preserves the value without a second source of truth.

### SWIFT-009: Repair a Multiplatform Swift Package

Open a Swift package used by iOS and macOS applications. Its domain target currently imports a UI
framework and one platform target fails. Ask Quill Cowork to restore clean target boundaries and add
coverage for shared behavior.

Pass when `swift test` succeeds, iOS simulator and macOS consumers both build, the domain target has no
UI-framework import or application-level platform conditional, public API remains source compatible,
and platform behavior is isolated behind small injected adapters.

### SWIFT-010: Diagnose a Failing XCUITest from the Result Bundle

Open an app with a failing XCUITest caused by unstable identity and an asynchronous loading race. Ask
Quill Cowork to run the test, inspect the failure and `.xcresult`, repair the app or test at the root
cause, and rerun only the relevant test before the full suite.

Pass when the initial failure is preserved as evidence, the repair uses stable accessibility identity
and condition-based waiting rather than a fixed sleep, the focused rerun and full suite pass, and the
final answer cites the exact failed and passing test names.

## Execution Order

Run SWIFT-001 first as the environment gate. Run SWIFT-002, SWIFT-003, and SWIFT-009 without requiring
a simulator UI. Run the remaining iOS tasks on one named simulator at a time so `booted` cannot select
the wrong device. Run SWIFT-008 on a permission-enabled macOS account. SWIFT-010 runs last because it
is the most expensive and verifies result-bundle diagnosis after the basic build path is known good.
