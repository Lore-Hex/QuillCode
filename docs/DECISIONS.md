# QuillCode Decisions

## 2026-08-12: updates continue after transactional relocation

- **Decision:** When an update is available to a copy running outside `/Applications`, the update
  sheet offers **Move to Applications** instead of making the user download the DMG again. That
  action presents the existing verified first-install flow, stages the current app transactionally,
  relaunches it from `/Applications`, and resumes the update check automatically.
- **Ordering:** A build-scoped, 15-minute continuation intent is recorded only after the detached
  relocation helper launches successfully. The relaunched app waits for the helper's bounded success
  result before contacting the release feed, so update preparation cannot overlap the helper's
  three-second launch-stability observation.
- **Recovery:** The intent remains pending if the relocated app fails its handshake or stability
  window. The restored source copy therefore presents the installation flow again even when the
  ordinary once-per-build reminder was dismissed. A helper failure stays visible instead of being
  replaced by a network check. An installed, writable copy may continue after a bounded wait if the
  helper result file cannot be read.
- **Trust boundary:** The updater continues only for an exact current version/build success result.
  Intent state is one-shot, scoped by bundle, channel, and build, tolerant of a small clock skew, and
  rejected after expiry. Existing bundle, architecture, commit, signature, atomic activation,
  handshake, stability, and rollback checks remain authoritative.
- **Evidence:** Controller tests cover update-requested relocation, once-per-build override,
  one-shot consumption, expiry, delayed helper completion, missing-result fallback, and failure
  preservation. Fixed-size rendering covers the revised update sheet; packaged relocation and
  updater smokes continue to exercise the shared production helper.

## 2026-08-12: native memory pressure releases only reconstructible state

- **Decision:** The packaged macOS app observes dispatch memory-pressure warning and critical events
  after its first window appears. Both levels purge bounded artifact-preview caches and compact
  durable inactive transcript payloads; critical pressure also cancels and drops the reconstructible
  workspace file-mention index. Inactive project environment surfaces are trimmed to the selected
  project at either level.
- **Safety boundary:** Selected, running, ephemeral, and persistence-failed chats stay resident.
  Composer drafts, active terminal processes, browser sessions, and agent tasks are untouched.
  Optional language-server processes are retired only at critical pressure when no agent run is
  active, and teardown runs outside the main actor. Later use reconstructs every released resource.
- **Evidence:** Focused model/controller tests inject warning and critical events and prove protected
  state, idempotent observation, and off-actor service teardown. Packaged live-window and 100-chat
  performance smoke now inject critical pressure, verify inactive transcript eviction, selected-chat
  and composer-draft preservation, and a valid native render afterward. Offline release validators
  require that evidence and reject inconsistent payload counts.

## 2026-08-12: Developer ID desktop credentials migrate to macOS Keychain

- **Decision:** The canonical user-account store selects macOS Keychain only when the packaged app
  carries a valid ten-character `QuillCodeSigningTeamIdentifier`, the running process passes macOS
  signature validation, and its signature reports the same team. Missing, invalid, malformed, or
  mismatched identity data fails closed. Ad-hoc tester builds, standalone CLI processes, Linux,
  explicit `--home` runs, smoke fixtures, and tests keep the bounded private file backend.
- **Migration:** A signed desktop read checks Keychain first, migrates a legacy private-file value
  only after the Keychain write succeeds, and then attempts to retire the old copy. Cleanup failure
  does not hide a valid credential and is retried on the next read. A current Keychain value always
  wins over stale fallback data. Explicit replacement writes Keychain before removing the fallback;
  explicit clear removes fallback material before Keychain so a failed clear cannot resurrect a
  credential through migration.
- **Why signature-gated:** Current tester apps are ad-hoc signed, so their designated requirement is
  a build-specific code hash. A Keychain item created by one tester build would not provide silent,
  durable access to the next build. Developer ID gives the app a stable signed identity across
  updates. Sealed metadata and independent runtime signature attestation must agree before that
  stable identity becomes the activation and migration boundary.
- **CLI boundary:** The separately distributed CLI remains on its existing `0600` private file store.
  Modern noninteractive sharing through a Data Protection Keychain access group requires an
  Apple-authorized entitlement and provisioning profile for every participating executable. The
  desktop does not weaken Keychain ACLs merely to make an ad-hoc or independently installed CLI
  share its item.
- **Evidence:** Focused tests exercise real Keychain create/read/update/delete, byte and identifier
  bounds, factory eligibility, missing and mismatched runtime identities, isolated-file selection,
  primary precedence, migration ordering, failed-write preservation, and delete ordering. A parity
  gate rejects direct production `FileSecretStore` composition outside the persistence factory and
  pins the runtime signature check. The immutable validated runtime identity is initialized once per
  process, and ineligible ad-hoc or isolated stores return before initializing it, so multiple
  credential consumers do not add Security-framework work to the normal tester startup path.

## 2026-08-12: public performance evidence gates settled idle resources

- **Decision:** Every packaged release attempt measures a two-second idle window after two complete
  reversible native interaction sweeps. The app reads its own cumulative user-plus-system CPU time
  from `proc_taskinfo`, alongside physical footprint and thread count, before and after that window.
- **Budgets:** The release majority must reach its live window within 2.5 seconds. Every resource
  sample must remain below 128 MiB and 32 threads; first-pass retained growth is capped at 64 MiB,
  repeated-pass growth at 16 MiB and two threads, and settled idle at 5% CPU, 8 MiB, and two threads.
- **Evidence contract:** Version-6 evidence records the processor-time source, measured wall time,
  nanosecond CPU delta, derived CPU percentage, idle resource snapshot, signed deltas, and per-attempt
  budget flags. Offline and post-publication validators independently recompute those values and
  require the exact production policy.
- **Why:** A native app can look fast and memory-light at a screenshot boundary while a polling loop,
  animation, or delayed worker continues consuming battery and accumulating state. Idle behavior is
  part of the product advantage and therefore belongs at the release boundary, not in an occasional
  manual profile.
- **Calibration:** The first native Intel candidate measured 12,890,112 bytes (12.29 MiB) of
  repeated-pass growth in one of three otherwise healthy fresh processes, 307,200 bytes above the
  proposed 12 MiB ceiling. The proven 16 MiB convergence limit remains strict while accommodating
  native allocator variance; every absolute, first-pass, thread, and idle limit remains tightened.

## 2026-08-11: rich artifact previews have a recent residency budget

- **Decision:** Durable tool events retain every artifact reference, but transcript projection no
  longer reads local artifact files while reducing each historical tool completion. After reduction,
  only the newest 12 tool cards may be inspected for rich text; inspection stops after 48 artifacts,
  eight successful previews, or 64 KiB of preview text.
- **Cache boundary:** Unchanged text previews reuse a purgeable cache limited to 16 entries and
  128 KiB. Cache identity includes the standardized path, file size, modification time, and resource
  identifier. Changed, replaced, deleted, nonregular, unreadable, and no-longer-authorized files are
  revalidated before cached content can be returned.
- **Usability boundary:** Older cards keep their artifact chip, path or URL, type classification,
  open action, and durable tool output; only their disposable inline text copy is released. Timeline
  and tool-card projections receive the same hydrated values through the reducer's positional index,
  including malformed histories that reuse a tool-call ID.
- **Why:** Rebuilding the desktop surface reopened every historical text artifact and retained a
  separate preview string for each card. Long coding sessions therefore paid filesystem and memory
  costs for content that was usually far offscreen.
- **Evidence:** Focused tests cover card, artifact-count, preview-count, byte, cache-invalidation, and
  duplicate-ID boundaries. A source parity gate rejects eager preview reads in tool-event projection
  and pins both cache limits.

## 2026-08-11: updater activation uses Launch Services

- **Decision:** The production update helper opens both the replacement app and any restored rollback
  app through `NSWorkspace`. It pins the exact bundle path, requests a new foreground instance,
  rejects running-application substitution, forwards the launch-handshake arguments and inherited
  environment, and bounds the asynchronous open request with the existing handshake timeout.
- **Test boundary:** Fixture helpers retain a direct-process launch mode so unit tests can execute
  deterministic shell-backed app bundles and inject launch, handshake, and stability failures. The
  production environment selects Launch Services explicitly, and packaged updater smoke proves that
  mode against a signed `.app` and its real SwiftUI first-window readiness boundary.
- **Why:** Directly spawning the executable can leave a healthy AppKit process without the normal
  application-open event that materializes SwiftUI's primary `Window`. A daily-driver 729-to-730
  update reproduced that state: staging and signature validation passed, but no window or readiness
  acknowledgement appeared and the helper correctly rolled back. The same update completed after
  the helper adopted the system application-launch path.

## 2026-08-11: updater success waits for first-window readiness

- **Decision:** Parsing the updater or relocation launch-handshake argument remains the first normal
  process step, but parsing performs no filesystem mutation. The desktop controller writes the
  acknowledgement only from the same first-window-ready transition that marks launch lifecycle
  state ready.
- **Why:** Process entry proves only that dyld reached the executable. An app can still hang while
  loading persistence or constructing its first SwiftUI workspace and remain alive beyond the
  helper's stability interval. A process-entry acknowledgement could therefore discard the
  known-good rollback bundle before the replacement was usable.
- **Recovery behavior:** A normal launch acknowledges after post-window services are installed. A
  recovery-mode launch keeps both the crash marker and update acknowledgement pending until the user
  explicitly keeps background work paused or resumes it. Failed acknowledgement writes remain
  retryable and never clear the controller's one-shot request.
- **Evidence:** Lifecycle tests prove normal readiness creates the acknowledgement and recovery
  startup does not create it prematurely. The packaged updater parity gate requires parsing to stay
  mutation-free in the app entry point and requires acknowledgement to remain owned by the shared
  ready transition. Native public updater smoke then exercises that boundary on both architectures.

## 2026-08-11: updater relaunches serialize cleanup and durable exit work

- **Decision:** A foreground update cancels and joins the one-shot interrupted-update recovery task
  before downloading or staging a fresh app. Relaunch termination synchronously broadcasts a private
  lifecycle boundary before asking AppKit to quit or using its bounded forced-exit fallback.
- **Why:** Startup recovery removes orphaned `.update-<uuid>.app` bundles beside the installed app. If
  its delayed scan overlapped a new install, it could delete that installer's live staging bundle.
  AppKit may also defer sheet-driven termination long enough to reach the fallback, which otherwise
  bypasses the normal launch-marker and pending-draft cleanup notifications.
- **Correctness boundary:** Cancellation alone is insufficient because recovery may already be in a
  detached filesystem scan. The update awaits complete recovery termination, then rechecks operation
  cancellation and generation before preparation. Relaunch cleanup is synchronous and idempotent;
  the later AppKit notification may safely repeat it.
- **Evidence:** Controller coverage blocks recovery behind a deterministic gate and proves neither
  preparation nor installation begins until cancelled recovery exits. Lifecycle and composer tests
  prove the relaunch boundary removes the active-launch marker and flushes pending draft text.

## 2026-08-11: packaged launches require graceful termination

- **Decision:** Packaged Quill Cowork apps explicitly disable macOS sudden termination. Automatic
  termination support remains unchanged, but every operating-system termination must cross AppKit's
  normal `willTerminate` boundary before the process exits.
- **Why:** The active-launch record is intentionally removed only at that graceful boundary. Apple
  documents that sudden termination skips `willTerminate`; advertising it made an ordinary fast
  logout or shutdown indistinguishable from a crash and could show a false unexpected-exit warning or
  pause automatic workspace services on the next launch.
- **Release boundary:** Packaged smoke reads the built `Info.plist` and fails unless
  `NSSupportsSuddenTermination` is false. Source parity separately pins both the generated plist entry
  and the artifact assertion so future packaging changes cannot silently reintroduce the mismatch.

## 2026-08-11: pane visibility changes reuse the current workspace projection

- **Decision:** Opening or closing Automations, Extensions, Memories, or Activity updates only that
  pane's presentation surface. The desktop no longer rebuilds the transcript, 100-chat navigation
  projection, composer, model catalog, or filesystem-backed settings for a visibility-only change.
  Extensions still reprojects its own contents because a normal toggle clears any focused extension
  kind; the other panes retain their already-current content and change only visibility.
- **Correctness boundary:** Model state remains authoritative. Each narrow projection is compared with
  the corresponding field from a fresh full surface, while unrelated sentinel fields prove the
  projection did not silently fall back to a full rebuild. Content-changing mutations continue to use
  authoritative refreshes.
- **Evidence:** The release-configured three-process `daily-driver-100-chats` gate passed 3/3 with a
  354 ms median launch, 103.45 MiB initial RSS, 176.30 MiB after the first interaction sweep, and
  182.11 MiB after the repeated sweep. The like-for-like single-process trace fell from 191.2 MB to
  178.3 MB after the first sweep and from 198.7 MB to 187.3 MB after the repeated sweep.

## 2026-08-10: public performance measures a verified daily-driver workspace

- **Decision:** Every packaged performance attempt first invokes the app's own fixture helper to
  atomically create one project, 100 saved chats, and a 200-message selected transcript. The timed
  process loads that state normally and validates the marker, project binding, chat count, selected
  chat, and message counts before capturing launch or resource evidence.
- **Evidence contract:** Version-4 performance evidence identifies the workload as
  `daily-driver-100-chats`. Raw window reports and the public architecture-specific manifests must
  agree on that exact identity; an empty, malformed, mislabeled, or partially seeded workspace fails
  closed. Seeding runs in a separate process so fixture creation is outside launch timing.
- **Coverage boundary:** The full packaged smoke keeps its first-run empty-state window for onboarding,
  Accessibility frames, and Computer Use proof, then starts a second, separately seeded daily-driver
  window for its performance manifest. It packages an optimized release executable by default (with
  an explicit diagnostic override), so production budgets never judge debug-code memory behavior.
  Published speed and memory numbers therefore represent a returning user's restored workspace
  without surrendering first-run coverage.
- **Why:** Empty-state launch evidence could remain green while persistence loading, transcript
  restoration, navigation context, or reconnect UX regressed for established users. Distribution
  claims should measure the state people keep after adopting the product.

## 2026-08-10: process-owned application services begin after the first window

- **Decision:** Normal desktop launch no longer registers notification categories, inspects the
  installed app location, recovers an interrupted update, or schedules automatic update checks from
  `App.init`. The yielded first-window startup gate starts that same idempotent service bundle once,
  before optional workspace automation begins.
- **Availability boundary:** Draft lifecycle flushes, approval notifications, installation recovery,
  and updates still start in both normal and recovery launches. Recovery mode pauses only automatic
  workspace services; it does not withhold distribution or durability services after the saved
  workspace is visible.
- **Evidence:** Application-service tests prove controller construction performs none of this work,
  the first-window boundary starts it once, and repeated boundary completion cannot duplicate updater
  recovery. Desktop parity rejects an application-services call from `App.init` and pins ownership to
  the post-window gate.

## 2026-08-10: Computer Use permission probes begin after the first window

- **Decision:** Installing the native Computer Use backend no longer reads its status. The desktop
  keeps the backend available immediately, then queries Screen Recording and Accessibility trust in
  the existing cancellable post-window refresh task. The synchronous operating-system preflights
  run at utility priority instead of occupying the main actor during first-window construction.
- **Lifecycle boundary:** Status refreshes are generation-bound. Cancellation or a later backend
  replacement prevents an obsolete preflight result from mutating the model. Permission and
  foreground-app refreshes use distinct replaceable task slots: recovery startup refreshes
  permission state while automatic foreground observation remains paused, and rapid application
  activations retain only the latest result of each kind. Optional CUA discovery requests another
  pair of refreshes only when it actually replaces the backend.
- **Evidence:** Coordinator tests prove controller construction and repeated surface projection read
  no backend status, an explicit refresh does not spawn foreground lookup work, and a cancelled
  preflight cannot update the model. Launch coverage proves recovery mode refreshes permission state
  without starting automatic workspace or foreground work. Desktop parity pins side-effect-free
  installation, explicit command routing, and the utility-priority refresh boundary.

## 2026-08-10: project bookmark restoration begins after the first window

- **Decision:** Security-scoped project bookmarks are no longer read, resolved, activated, or
  rewritten while the desktop controller is constructing its initial surface. The yielded
  first-window startup boundary restores them once, then configures local artifact-preview access
  before automatic project services begin.
- **Persistence boundary:** Bookmark reconciliation writes `UserDefaults` only when it removes an
  obsolete or invalid record or renews a stale bookmark. A healthy launch with unchanged bookmarks,
  including the common empty-bookmark case, performs no preferences write.
- **Recovery boundary:** Recovery startup restores explicit project access while leaving automatic
  workspace work paused. All normal, paused, and resumed paths share one idempotent post-window gate.
- **Evidence:** Focused coordinator tests inject bookmark persistence and prove unchanged state has
  zero writes. Launch lifecycle coverage proves controller construction performs no bookmark
  resolution and repeated first-window completion restores and activates access exactly once.

## 2026-08-10: Computer Use status refresh is event-driven and task-owned

- **Decision:** Workspace surface projection no longer polls Computer Use permissions or launches a
  foreground-application query. Automatic startup performs one explicit refresh, and macOS
  application-activation notifications request later refreshes only when the foreground app can
  actually change. Returning from Computer Use system settings uses the same path.
- **Bounded work:** Foreground queries occupy one replaceable desktop task slot. A newer activation
  cancels the prior owner, generation checks reject late backend results, and cancellation is checked
  before model mutation. Repeated surface refreshes therefore retain no lookup tasks or provider
  subprocesses. Status and foreground values publish only when they changed.
- **Recovery boundary:** Activation observation begins with automatic workspace services, so startup
  recovery keeps this optional work paused. Native Computer Use remains installed for explicit user
  actions, and resolving the optional CUA driver schedules a fresh status query after the backend swap.
- **Evidence:** Coordinator tests prove 1,000 real controller surface projections perform zero
  permission reads and foreground lookups beyond installation, activation observation installs once,
  late results cannot replace newer applications, and canceled work cannot mutate the model. Desktop
  task and progress-projection parity gates require cancellable ownership and reject Computer Use work
  from the presentation path.

## 2026-08-10: startup failures reopen with automatic workspace work paused

- **Decision:** Controller construction now loads and projects the usable workspace without starting
  managed-worktree retention, pull-request reconciliation, project context and mention indexing,
  due automations, refresh tickers, account requests, or optional Computer Use driver discovery.
  A yielded first-window task starts that work once and then marks the launch ready.
- **Crash-loop boundary:** An active launch record left in the `starting` phase selects recovery
  startup on the next process. The workspace opens, but automatic background work remains paused and
  the launch remains classified as starting until the user chooses either **Keep Background Work
  Paused** or **Resume Background Work**. The first choice marks the usable paused session ready; the
  second starts the same idempotent normal service set before marking it ready. Ready-state exits keep
  the existing warning because they are not evidence that startup work caused the failure.
- **Availability boundary:** Draft lifecycle flushes, update recovery and automatic update checks,
  issue reporting, the installed-location recovery path, native Computer Use capability, and all
  explicit workspace actions remain available. The optional foreground-app lookup and CUA driver
  resolution are deferred and owned by a cancellable task slot instead of escaping controller
  lifecycle ownership.
- **Evidence:** `QuillCodeDesktopLaunchLifecycleTests` covers first-window deferral, both recovery
  choices, phase transitions, and normal ready incidents. `QuillCodeDesktopComputerUseCoordinatorTests`
  proves the startup lookup can remain dormant. Packaged launch-recovery smoke and desktop parity
  gates pin the executable and release architecture paths.

## 2026-08-10: agent transcript progress projects only proven tail changes

- **Decision:** Reconciliation classifies each presentation-cadence snapshot as transcript
  unchanged, one assistant-tail replacement, one assistant-tail append, or full rebuild. It also
  marks message/tool/approval events and execution-context changes as projection-relevant. The next
  coalesced agent refresh may reuse the selected transcript or patch that one tail only when the
  model has an authoritative published baseline and every accumulated mutation remains compatible.
- **Correctness boundary:** Hints are consumed once. A missing or changed baseline, changed message
  identity or role, persisted message-event ambiguity, tool lifecycle mutation, structural history
  change, project-context change, or incompatible coalesced sequence falls back to the complete
  transcript projector. The incremental result is regression-tested against the authoritative
  surface, including 50,000-event selected histories and 10,000-message background histories.
- **Memory boundary:** The tracker retains only enum cases and UUIDs, never messages, events, tool
  cards, timelines, or producer snapshots. Assistant streaming therefore reuses the already-reduced
  tool-card buffer, and background progress reuses every selected transcript buffer, without
  reintroducing copy-on-write coupling between the producer and workspace model.
- **Evidence:** `WorkspaceAgentTranscriptRefreshTrackerTests`, `WorkspaceProgressSurfaceTests`,
  `ParityDesktopTaskCoordinationGateTests`, the complete 5,831-test Swift suite, and release-packaged
  native smoke with launch, resident-memory, repeated-interaction, and Accessibility budgets.

## 2026-08-10: agent progress keeps producer and model histories independently owned

- **Decision:** Presentation-cadence progress reconciles identified message, context, event, and
  subagent histories into the model's existing arrays. Matching records update in place, new tails
  append, truncated tails are removed, and identity changes trigger a detached structural rebuild.
- **Memory and CPU boundary:** The model never retains the agent producer's large array storage.
  After a callback returns, the producer can mutate its next streamed tail without a transcript-sized
  copy-on-write clone, while the model also retains and reuses its own capacity. Reconciliation scans
  the overlapping history without allocating; persistence still repairs legacy reasoning bursts and
  returns healthy arrays unchanged.
- **State ownership:** Instructions, memories, goals, composer drafts and attachments, and queued
  follow-ups stay model-owned because they can change after the agent captures its send-start copy.
  Completion remains the authoritative full-snapshot boundary, and destroyed ephemeral chats retain
  their existing non-resurrection guard.
- **Evidence:**
  `WorkspaceComposerIntegrationTests/testAgentProgressKeepsLargeProducerAndModelEventStorageIndependent`
  proves two independent 50,000-event buffers survive successive ticks; the structural-history test,
  `ThreadEventLogCompactorTests`, `JSONThreadStoreTests`, `ParityAgentStreamingGateTests`, and
  `ParityWorkspaceThreadMutationModelGateTests` cover exact replacement, durable repair, and ownership.

## 2026-08-10: model streams publish at presentation cadence

- **Decision:** Provider token cadence is no longer desktop presentation cadence. Visible assistant
  drafts and reasoning summaries publish at most every 50 milliseconds while preserving an immediate
  first update and an exact final flush on both successful and failed streams.
- **Memory and CPU boundary:** A streamed action is limited to 16 MiB of UTF-8. The collector stops
  before appending an over-limit chunk, and non-`say` actions stop repeated preview parsing as soon as
  their action type is known. This bounds retained response data and removes provider-token-driven
  parsing and full-thread copying that cannot become visible.
- **Recovery:** An over-limit response becomes a focused warning with narrower-request guidance and a
  direct model-picker action. Usage and the latest bounded reasoning summary remain committed on
  failure, and the newest safe visible draft is not discarded when a provider disconnects.
- **Evidence:** `TrustedRouterStreamingActionTests` deterministically reduces a 4,096-fragment answer
  to two draft publications under one cadence window, verifies success and failure final flushes, and
  rejects UTF-8 overflow. `WorkspaceRuntimeIssueBuilderTests` and `ParityAgentStreamingGateTests`
  protect the recovery surface, shared cadence, final-flush ownership, and response limit.

## 2026-08-10: live composer drafts checkpoint outside large transcripts

- **Decision:** The desktop synchronizes its live composer binding into model memory immediately, then
  debounces durable writes for 350 milliseconds. App deactivation and termination flush pending work.
  Every delayed request retains its original optional thread identity and is ignored if selection has
  changed before it runs.
- **Persistence:** Standard drafts use private `0600` per-thread records beneath a `0700` directory.
  Records are schema-checked, owner-checked, symlink-safe on read, and bounded to one MiB of draft text.
  A nil draft is a tombstone, so a stale full-thread snapshot cannot resurrect sent or cleared text.
  The first checkpoint makes an unsaved new chat durable; later typing does not serialize its transcript.
- **Recovery:** A pending first message without a thread owner has a separate checkpoint and transfers
  to the created chat. Oversized or unavailable sidecar storage removes stale checkpoint authority and
  falls back to the established atomic full-thread save. Deleting a chat removes both stores.
- **Privacy:** Confidential and side-conversation drafts remain memory-only. The same runtime-context
  guard that excludes their transcripts also excludes checkpoint files.
- **Evidence:** `ComposerDraftCheckpointStoreTests`,
  `WorkspaceComposerDraftIntegrationTests`,
  `QuillCodeDesktopComposerDraftCheckpointCoordinatorTests`, and
  `ParityDesktopGateTests/testDesktopCrashRecoveryCheckpointsLiveComposerDrafts` cover storage bounds,
  permissions, malformed/symlink rejection, burst coalescing, lifecycle flushes, relaunch, tombstones,
  fallback, cleanup, selection races, and confidential-session exclusion.

## 2026-08-09: releases update from the untouched previous public app

- **Decision:** Download Builds captures the current public manifest and matching arm64 and x86_64
  updater archives before publication begins. GitHub upload state, bounded size, release digest,
  manifest identity, commit, architecture, URL, and SHA-256 must agree before the snapshot is kept.
- **Release ordering:** Tester or stable publication depends on the capture job, while release-asset
  assembly downloads only packaging artifacts. The prior binaries therefore cannot be mistaken for
  new release assets and cannot be captured after a moving release changes.
- **Compatibility proof:** Native post-publication jobs update the untouched captured app through its
  real embedded channel feed to the newly published build, then require exact source/target metadata,
  activation, signature, relaunch, process liveness, and staging cleanup.
- **First release:** A missing channel release is recorded explicitly and permits the existing
  synthetic one-build-behind smoke. Once a public source is available, the workflow cannot rewrite or
  re-sign it to manufacture the upgrade path.
- **Evidence:** Transactional capture modules, stateful fake-GitHub tests for success, absence,
  corruption, and preflight rejection, workflow ordering assertions, and both native updater runners.

## 2026-08-09: moving tester publication retains a verified rollback snapshot

- **Decision:** Tester assets upload under run-scoped candidate names and must match GitHub's
  recorded size, upload state, and SHA-256 digest before canonical names change. Existing assets
  move to rollback aliases; they are not clobbered or deleted in place.
- **Commit order:** Candidates take canonical names with the updater manifest last, then release
  metadata moves to the new commit, then the `tester-latest` Git ref moves last. Prior assets are
  deleted only after the new metadata and remote tag have both been read back and verified.
- **Failure recovery:** Upload, rename, metadata, and tag failures delete every known candidate,
  restore prior asset names by immutable GitHub asset ID, restore the complete metadata snapshot,
  force the old tag back, and compare the recovered inventory, digests, metadata, and ref with the
  snapshot before returning failure. Cleanup deletions receive bounded retries.
- **Scope:** Immutable stable releases retain their draft, consumer-verification, and promotion
  transaction. This publisher owns only the deliberately moving tester release.
- **Evidence:** `scripts/tester_publication`, the thin `publish-tester-release.py` entry point,
  workflow ordering assertions, and deterministic injected failures at upload, asset rename,
  release metadata, tag push, and post-commit cleanup.

## 2026-08-09: superseded tester builds never mutate the moving release

- **Decision:** The Download Builds publisher re-fetches `origin/main` after all architecture
  artifacts are ready and immediately before any `tester-latest` mutation. A tester run whose
  commit is no longer current records `publish-required=false` and completes without moving the
  tag, editing release notes, or replacing assets.
- **Serialization:** Download builds remain serialized with cancellation disabled. An in-flight
  publisher cannot be interrupted halfway through replacing a release, while a completed but
  superseded build yields cleanly to the already queued newer run.
- **Stable releases:** Canonical immutable version tags remain publishable even when `main` advances,
  but the planner rechecks that the tag still resolves to the workflow commit and otherwise fails
  closed.
- **Evidence:** `scripts/plan-download-publication.sh`, the publish/verification job conditions in
  `download-builds.yml`, deterministic fresh/stale/tag planner tests, and the workflow parity gate.

## 2026-08-09: process services start at application entry

- **Decision:** The ordinary `QuillCodeDesktopApp` entry path calls
  `QuillCodeDesktopController.startApplicationServices` before handing the controller to SwiftUI.
  The method owns notification action registration, the installation-location check, interrupted
  update recovery, and automatic update scheduling.
- **Window independence:** None of these services depends on `QuillCodeDesktopRootView.task` or
  command-binding `onAppear`. macOS may restore the menu-bar process without creating its workspace
  window, and process responsibilities must still run in that state.
- **Mode isolation:** Helper and smoke launch modes return before application services start, so
  deterministic test processes do not schedule updates, inspect installation location, or register
  notification actions.
- **View boundary:** The local keyboard monitor remains in a view modifier because its lifetime must
  follow the visible workspace. Notification registration instead accepts only the packaged product
  bundle identifier and remains idempotent for the process lifetime.

## 2026-08-09: verified-update launch acknowledgment belongs to app entry

- **Decision:** `QuillCodeDesktopApp.init` acknowledges a validated updater launch token exactly
  once, immediately after recording app-entry uptime and before helper-mode or scene dispatch.
- **Window independence:** The token is not owned by `QuillCodeDesktopRootView.task`; macOS can
  restore a menu-bar app without materializing its main window, and update success must not depend
  on a particular scene or view lifecycle.
- **Recovery boundary:** The detached helper still owns process-exit waiting, atomic activation,
  handshake timeout, launch stability, rollback, result persistence, and staging cleanup. Moving
  acknowledgment earlier does not weaken any helper validation or allow an unverified update.
- **Why:** A daily-driver updater run staged build 687 correctly, but the relaunched app restored
  without creating the root view. The handshake timed out and the helper correctly restored build
  686. Process-entry acknowledgment proves the executable launched regardless of window state.

## 2026-08-09: accessibility readiness uses collision-safe targeted traversal

- **Decision:** Accessibility traversal deduplicates `AXUIElement` values with `CFEqual` and hashes
  them with `CFHash`. A hash value alone is never treated as element identity or cycle evidence.
- **Readiness boundary:** Dismissible surfaces request only their title, required control, and close
  identifiers. The targeted traversal reads only identifiers while searching, records requested
  matches with positive-area frames, and stops when the whole set is present; consumers that need
  the full hierarchy keep the complete traversal.
- **Failure integrity:** Sampling remains bounded and does not replay the activating command. Missing
  elements still fail the strict interaction contract, while evidence reports the exact targeted
  sample count and sorted safe identifiers that never appeared.
- **Why:** The former `Set<CFHashCode>` could mistake a collision for a previously visited element and
  skip an unrelated subtree. Rebuilding every Accessibility snapshot also did unnecessary work at
  the exact packaged-launch boundary where panes can still be materializing.

## 2026-08-09: settings and credentials persist as one compensated transaction

- **Decision:** A full desktop settings save snapshots the existing TrustedRouter credential,
  applies the requested credential mutation, and saves configuration last. Any mutation or
  configuration failure attempts to restore the previous credential before returning failure.
- **Live state:** Proposed full settings do not enter the workspace model until both durable writes
  succeed. Quick mode, model, favorite, and keyboard-shortcut changes still apply to the current
  session immediately, but a failed configuration save remains visibly unsaved until a retry works.
- **OAuth:** Loopback sign-in uses the same transaction for its exchanged credential and account
  configuration, so the app cannot report a completed sign-in from only one durable half.
- **Privacy:** Persistence errors and the issue tracker retain only affected enum kinds and a bounded
  rollback-failure boolean. Raw errors, paths, URLs, account details, and credential values never
  enter runtime diagnostics.
- **Why:** Separate best-effort writes could leave a new credential paired with old configuration,
  old credentials paired with new configuration, or session-only settings with no visible warning.
  Compensation preserves the last known durable pair whenever the filesystem permits recovery.

## 2026-08-09: workspace registry persistence failures remain visible until exact recovery

- **Decision:** Project, automation, and saved-search snapshots share a focused registry
  persistence helper. Every attempted write records success or failure for its exact registry kind;
  a successful project save never clears an automation or saved-search warning.
- **UX:** The normal runtime-issue surface reports that workspace changes are not durable and names
  only the affected data types. Startup load damage and failed chat snapshots remain higher priority,
  and provider/runtime issues return automatically after every affected registry becomes durable.
- **Privacy:** The tracker stores only enum cases in memory. It never retains or displays filesystem
  errors, paths, project names, automation details, saved-search queries, or credentials.
- **Recovery mode:** A nil store remains a no-op because bootstrap already uses nil to protect data
  that could not be loaded. Its startup recovery issue stays visible, and later in-memory edits do
  not overwrite the original damaged file.
- **Why:** These registries previously used `try?` in the central model. Disk exhaustion, read-only
  storage, permission loss, or bounded-file limits could leave visible project, automation, and
  saved-search changes available only in memory without telling the user.

## 2026-08-09: failed chat persistence is visible until that snapshot recovers

- **Decision:** Every non-ephemeral chat save and delete reports success or failure to a shared,
  session-bounded tracker. A failed chat stays in the tracker until a later full snapshot or delete
  for that exact chat succeeds; repairing one chat never clears another chat's warning.
- **UX:** The normal runtime-issue surface reports that changes are not durable, counts affected
  chats, and suggests disk-space, app-data permission, and large-chat compaction recovery. Startup
  load damage remains higher priority because it describes data that was already unavailable when
  the session opened.
- **Privacy:** The tracker stores only chat UUIDs in memory. Its diagnostics contain a count and an
  explicit no-private-content statement; filesystem errors, paths, titles, transcript text, and
  credentials are never copied into the surface.
- **Why:** Persistence previously used `try?` for ordinary saves and deletes. Disk exhaustion,
  read-only storage, permission loss, or the bounded transcript-size limit could therefore leave
  the workspace looking saved even though its latest state existed only in memory.

## 2026-08-09: release app executables are stripped before signing

- **Decision:** macOS release apps remove debug symbols and local symbols with `strip -S -x` after
  the Swift executable is copied into the app bundle and before ad-hoc or Developer ID signing.
  Debug builds retain their symbols for development and CI diagnosis.
- **Integrity boundary:** The strip helper accepts only one regular executable file, rejects
  symlinks and unavailable tools, and fails if stripping removes executability, empties the image,
  or grows it. Signing remains downstream so stripping cannot invalidate a finished signature.
- **Public evidence:** Architecture-specific `BUILD_INFO` files declare the strip policy and exact
  executable size. The public verifier compares that size with the regular Mach-O entry inside the
  downloaded ZIP in addition to checking its thin architecture and app metadata.
- **Why:** The arm64 release executable measured 56,099,184 bytes before stripping and 28,144,256
  bytes afterward, a 49.8% reduction. Smaller native images reduce download and cold page-in work
  while retaining global symbols for useful crash backtraces.

## 2026-08-09: public updater smoke waits out bounded feed propagation

- **Decision:** The packaged public-updater runner retries only an authenticated, valid feed that
  still reports the smoke fixture as current. It makes at most six checks with a two-second delay.
- **Failure boundary:** Invalid responses, malformed or mismatched manifests, unsupported
  architecture, signing or checksum failures, preparation errors, activation failures, and relaunch
  failures remain immediate hard failures. Exhausted stale-feed retries fail publication.
- **Why:** GitHub replaces the stable manifest asset in place. During build 681 publication, the
  Apple silicon verifier reached that URL seconds before propagation completed and saw build 680;
  Intel reached it moments later and completed 680-to-681 update and relaunch. A short bounded wait
  distinguishes eventual release propagation from a broken updater without masking integrity bugs.

## 2026-08-09: the desktop has one main-window owner

- **Decision:** The product workspace is a uniquely identified SwiftUI `Window`, not a
  `WindowGroup` paired with a second AppKit presenter. SwiftUI owns creation, close/reopen,
  frame restoration, and scene identity for the normal application lifecycle.
- **Menu-bar UX:** Actions that reveal workspace UI open the unique scene before mutating
  controller state. Operational actions such as Stop All, Disconnect All, Report an Issue,
  and Quit remain usable without forcing the workspace onscreen.
- **Release evidence:** Packaged smoke reuses an existing scene window before constructing
  its isolated fallback and reports the complete visible workspace-window count. Public
  validation requires exactly one, so a visible duplicate UI tree fails publication even if
  screenshots and foreground interactions look correct.
- **Test cleanup:** The read-only DMG relocation smoke canonicalizes `TMPDIR`, captures the
  relaunched app PID, and owns bounded TERM/KILL cleanup. Path-pattern fallback remains only
  for failures before the PID becomes observable.
- **Why:** A shared controller does not make multiple SwiftUI trees cheap. Competing AppKit
  and SwiftUI creation paths could retain redundant view state, make closed-window menu
  actions invisible, distort memory evidence, and leave relocation-test apps running after
  their temporary bundles were removed.

## 2026-08-09: first install reuses transactional update activation

- **Decision:** A copy launched from a DMG, App Translocation, or another
  non-replaceable location offers **Move & Relaunch** instead of sending the user
  to Finder as its primary action. Finder remains an explicit recovery action.
- **Integrity boundary:** The running app stages a copy beside the Applications
  destination and verifies its exact bundle identifier, version, build, source
  commit, architecture, and current signing requirement before launching a detached
  helper. Another running copy or a same-name different bundle fails closed.
- **Activation:** First install and replacement use explicit helper modes. A new
  destination is activated with a same-directory atomic rename; an existing Quill
  Cowork bundle uses the updater's atomic swap. Both require the normal launch
  handshake and three-second stability window.
- **Recovery:** Replacement failure swaps back and reopens the previous installed
  bundle. First-install failure removes the failed destination and reopens the
  original mounted copy. A destination that appears between staging and activation
  is never overwritten, and verified staging is removed.
- **Release evidence:** Every macOS download build mounts the completed DMG
  read-only, invokes the production relocation helper into an isolated Applications
  directory, waits for its success result, then checks the relocated code signature,
  native architecture, version, build, and exact source commit.
- **Why:** The previous reminder explained the right manual action but left the most
  important first-run workflow to Finder and did not exercise it as a release gate.

## 2026-08-09: public release pages are validated build artifacts

- **Decision:** Tester and stable GitHub release pages are generated by a bounded standalone tool
  from canonical macOS `BUILD_INFO.txt`, the exact repository/tag/channel/commit, and the publishing
  workflow URL. Workflow-local free-form Markdown is no longer the user-facing download contract.
- **User experience:** The page leads with a commit-pinned product screenshot, distinct Apple
  silicon and Intel DMG links, minimum macOS version, install and first-launch steps, and automatic
  update behavior. CLI, updater, checksum, manifest, and performance assets remain available behind
  one secondary disclosure, followed by exact source and workflow provenance.
- **Integrity boundary:** Generation rejects mismatched product, platform, architecture, release
  configuration, channel, commit, canonical version/build, minimum system version, signing mode,
  signing team, or notarization status. Stable pages require a notarized Developer ID build; ad-hoc
  pages cannot claim a team or notarization.
- **Why:** The live release was cryptographically and operationally strong but asked people to infer
  their installer from wildcard filenames in a flat asset list. Download guidance is part of the
  shipped product experience and should be regenerated and tested with the same identity evidence as
  the updater feed.
- **Evidence:** Five executable generator cases cover tester and stable output plus commit, stable
  version, and signing rejection. The existing download workflow suite pins the complete invocation and
  proves the old heredoc and duplicated signing-copy branch are absent.

## 2026-08-09: visible-browser DOM refreshes are latest-wins per tab

- **Decision:** Best-effort rendered-DOM updates from a visible WebKit session run through one
  latest-wins scheduler keyed by tab. Each tab may have one active capture and one pending request;
  subsequent events replace that pending request instead of creating another task.
- **Freshness:** If a newer request arrives during an active capture, the active result is discarded.
  Worker identities and tab/WebView identity checks prevent cancelled or replaced work from
  publishing stale state or interfering with a replacement worker.
- **Lifecycle:** Tab removal cancels work for that tab. Window closure cancels every worker, drops all
  pending input, and releases the scheduler. Requests hold WebKit views weakly until a capture begins.
- **Scope:** Explicit agent-requested DOM capture remains direct and authoritative. Coalescing applies
  only to reverse session updates emitted after visible browser activity, where current state matters
  and intermediate snapshots do not.
- **Why:** Navigation and JavaScript completion events can arrive faster than WebKit can serialize a
  rendered document. One untracked task per event allowed memory, work, and stale-result risk to grow
  with the event burst instead of with the number of tabs.
- **Evidence:** Scheduler tests cover a 10,000-request burst, independent keys, failure recovery,
  cancellation, replacement-worker isolation, and ownership release. A real WebKit integration test
  keeps active and pending counts at one or less through 200 rapid mutations and captures the final
  DOM state.

## 2026-08-09: Apple signing setup is transactional and team-bound

- **Decision:** Distribution setup validates Apple team and key identifiers plus the App Store
  Connect issuer UUID before decoding secrets. After certificate import, the selected Developer ID
  identity must be present in the private build keychain and its identity line must name the same
  Apple team.
- **Credential boundary:** Certificate and notary bytes remain in a mode-700 runner directory as
  mode-600 files. The workflow environment receives only their paths and the non-secret signing
  identifiers; certificate bytes, private-key bytes, certificate password, and generated keychain
  password are never exported.
- **Recovery:** Once sensitive files can exist, a local exit trap owns failure cleanup. Any decode,
  keychain, import, partition, identity, ownership, or environment-write failure deletes the
  temporary keychain and the complete signing directory before preserving the original exit status.
  Successful setup transfers cleanup ownership to the workflow's unconditional cleanup step.
- **Why:** Stable release automation was already fail-closed, but an import failure occurred before
  cleanup paths were exported and therefore left decoded files for ephemeral-runner disposal. Stable
  publication should be ready for real credentials without depending on runner destruction for
  secret cleanup or discovering a team mismatch during final package validation.
- **Evidence:** Six executable fake-tool cases prove no-op tester behavior, partial and malformed
  rejection before disk writes, path-only success, import-failure cleanup, and wrong-team cleanup.
  The complete stable-release, download, updater-signing, and full Swift suites remain green.

## 2026-08-09: native smoke wall-clock guards encompass semantic retry budgets

- **Decision:** The packaged live-window process receives a named 90-second wall-clock guard. CI and
  release use that reviewed default; controlled stress runs may override it only with a positive
  integer through `QUILLCODE_PACKAGED_WINDOW_SMOKE_TIMEOUT_SECONDS`.
- **Why:** Exact-main CI completed both native interaction sweeps, including Memories and Activity,
  then the outer shell killed the process at the legacy 45-second limit while the second sweep was
  settling. The inner verifier now deliberately permits bounded SwiftUI presentation and dismissal
  latency, so its aggregate healthy path must fit inside the outer catastrophic-hang guard.
- **Integrity boundary:** The change does not retry, skip, or convert any interaction failure into
  success. Every semantic verifier keeps its own tighter deadline, the process must still write its
  report and screenshot, and exhaustion still terminates and reaps the app with a failing status.
- **Evidence:** The parity contract pins the default, override validation, variable-based wait, and
  absence of the obsolete literal invocation. Exact-main CI and the next dual-architecture package
  remain the final native-host evidence.

## 2026-08-09: native surface readiness is one Accessibility generation

- **Decision:** A dismissible native pane is ready only when its identified title, required content,
  and Close control coexist in one Accessibility-tree generation. The verifier takes one fresh tree
  per attempt for up to 100 attempts at 50 ms and never assembles success from partial generations.
- **Latency:** A ready pane now needs one tree walk instead of the previous three independent waits.
  Slow SwiftUI presentation and post-press disappearance retain a bounded five-second semantic
  window, and cancellation stops further sampling.
- **Why:** Public build 673 completed Activity but the hosted Intel runner observed Memories' title
  and content without its Close control inside the previous one-second snapshot window. Independent
  title, content, and Close waits could also combine different hierarchy generations, making the
  evidence weaker while still being brittle during a healthy native transition.
- **Integrity boundary:** The gate still performs a real `AXPress`, requires the pane to disappear,
  and reports the latest generation's missing identifier on exhaustion. It does not mutate a
  controller directly, weaken a surface contract, retain runtime Accessibility state, or poll in the
  shipped product.
- **Evidence:** Unit tests prove delayed complete readiness and rejection of complementary partial
  generations. The packaged app passed two live interaction sweeps across all shared dismissible
  panes, including Memories and Activity, within the existing launch, memory, and thread budgets.

## 2026-08-09: native layout evidence must stabilize before comparison

- **Decision:** The Activity Accessibility verifier first proves the identified title, task summary,
  and Close control are present, then samples the composer until three consecutive measurable frames
  agree within half a point. The normally ready path completes in about 100 ms; the slow path remains
  bounded to 40 samples at 50 ms.
- **Restoration:** After the real Close-button `AXPress` dismisses Activity, constrained composer
  frames are ignored until a stable frame is at least 240 points wider. This waits for the semantic
  layout outcome instead of failing on a valid but stale frame from the preceding SwiftUI pass.
- **Why:** Public build 672 reached the hosted Intel window smoke but briefly exposed the composer
  without a measurable AX frame after Activity state changed. The prior verifier checked that
  transient snapshot before it checked whether Activity's identified content had finished appearing,
  so a healthy native transition could fail before disk-image packaging began.
- **Integrity boundary:** The release gate still requires identified Activity content, successful
  native dismissal, surface disappearance, and restored workspace width. It does not mutate the
  controller directly, remove the interaction, or convert a timeout into success.
- **Evidence:** Unit tests cover delayed, changing, jittering, stale, and never-stable frame streams.
  The packaged app passed direct and Launch Services smoke plus two complete native interaction
  sweeps, measuring composer restoration from 563 to 884 points.

## 2026-08-09: disk-image publication is transactional and bounded-retry

- **Decision:** DMG packaging builds a private candidate beside the requested output and replaces
  the public artifact only after `hdiutil` create, verify, and read-only attach; mounted bundle and
  `/Applications` validation; code-signature verification; and clean detach all succeed.
- **Retry boundary:** Create, verify, and attach are macOS disk-image service operations and receive
  up to three attempts with the exact stage and exit status in logs. Bundle shape, install shortcut,
  code signature, empty output, and detach safety remain fail-fast correctness checks. Normal detach
  gets one force fallback, but packaging never treats an invalid app as transient.
- **Recovery:** Each attempt uses a fresh candidate and mount point. Exhaustion removes only private
  temporary state and preserves a pre-existing destination byte-for-byte, so an infrastructure blip
  cannot silently destroy the last usable installer.
- **Why:** Public build 671 passed all three Intel launches, both real Accessibility sweeps, and every
  memory/thread budget, then the quiet `hdiutil` step exited without diagnostics. A workflow rerun
  recovered, proving infrastructure transience while also exposing an avoidable publication delay.
- **Evidence:** Executable fake-tool tests recover independent create, verify, and attach failures;
  clean a simulated partial attach before retry; prove three-attempt exhaustion preserves the
  previous output; reject invalid retry policy before work; and prove signature rejection performs
  no retry or publication.

## 2026-08-08: workspace surface refreshes project transcript history once

- **Decision:** The selected chat now produces messages, canonical tool cards, and chronological
  timeline items through one transcript projection. A paired reducer constructs each tool card once
  and updates its canonical-list and timeline positions together; focused callers can still request
  only messages or canonical cards through their existing APIs.
- **Why:** Every coalesced streaming repaint previously planned message reverts twice and reduced the
  complete tool-event history twice before SwiftUI received an immutable surface. A 2,000-turn
  daily-driving fixture therefore spent 259 ms in a debug surface rebuild despite the native view
  itself using lazy rows.
- **Memory and recovery boundary:** Visible message reuse is indexed by one compact integer per source
  message, speculative tool capacity is capped at 4,096 entries, and no retained cache or invalidation
  graph is added. Malformed terminal events remain timeline-only, but derive stable fallback identity
  from their persisted event UUID so repeated refreshes cannot manufacture apparent row changes.
- **Evidence:** The same 2,000-turn fixture projects 4,000 messages, 2,000 completed tools, and 6,000
  chronological rows in 190-196 ms after the change. Focused tests preserve duplicate text/ID
  behavior, hidden internal messages, unmatched-message append order, approval replacement, orphan
  exclusion from canonical cards, execution-context enrichment, review and Activity projections, and
  streaming-refresh coalescing.

## 2026-08-08: new chats own composer focus and native interaction order is intentional

- **New Chat focus:** The desktop navigation boundary bumps the existing composer focus token after
  creating a chat and before refreshing the rendered surface. Sidebar, menu, shortcut, and command
  palette routes all converge there, so a newly created chat is immediately ready for typing instead
  of leaving keyboard focus on the command that created it.
- **Smoke ordering:** Accessibility activation still groups contracts by lifecycle phase, but now
  preserves declaration order inside each phase. Developer-key onboarding runs first, the composer
  model picker runs first among repeatable transient controls, and New Chat remains last because it
  replaces workspace state.
- **Why:** Native Intel build 669 passed both sweeps in its first fresh process, then exposed two
  cumulative interaction issues in its second: the model button was absent after seven transient
  surface cycles, and menu-driven New Chat created the correct thread without focusing its composer.
  Alphabetically reordering independent UI contracts added no product value and obscured the intended
  low-churn-first sequence.
- **Evidence integrity:** The smoke still performs real `AXPress` actions, repeats every durable
  interaction twice, and restores each baseline. Ordering avoids unrelated accumulated presentation
  churn; it does not skip, mock, or weaken any contract.

## 2026-08-08: native Accessibility discovery tolerates equivalent titles and delayed trees

- **Decision:** Native command-menu fallback compares case-, diacritic-, and width-folded titles, so
  equivalent AppKit capitalization such as `New Chat` and workspace capitalization such as
  `New chat` resolve to the same real menu item. Identified workspace controls remain preferred.
- **Timing:** Activation target discovery re-snapshots the live Accessibility hierarchy for up to
  five seconds instead of abandoning a control after one second. A normally available target still
  resolves on the first snapshot and incurs no retry delay; cancellation and the attempt bound remain
  explicit.
- **Interaction integrity:** The sampler still requires a resolvable native element and a successful
  `AXPress` followed by observable state and deeper interaction evidence. It does not substitute
  controller mutation for a missing control or turn a failed live interaction into a pass.
- **Why:** Native Intel packaging exposed both platform-real behaviors in one first sweep: AppKit
  surfaced the New Chat menu item with title-case capitalization, and SwiftUI had not yet exposed the
  model-picker button during the previous one-second discovery window. Distribution smoke should be
  strict about semantics while allowing bounded native rendering latency and equivalent UI spelling.

## 2026-08-08: sidebar transcript search is bounded before concatenation

- **Decision:** `SidebarItem` builds its searchable transcript prefix incrementally and stops after
  8,000 user/assistant characters. It preserves the existing message order, newline separators, role
  filtering, and extended-grapheme behavior without first joining the complete transcript.
- **Why:** Workspace surface refreshes rebuild sidebar rows frequently. Joining a long transcript and
  trimming afterward created a transcript-sized temporary allocation and O(total history) latency on
  the main actor even though the UI retained only a bounded prefix.
- **Architecture:** The projection remains a pure value transformation beside `SidebarItem`; no
  long-lived cache, invalidation protocol, or duplicate retained transcript is introduced. Work and
  temporary storage are bounded by the actual 8,000-character product contract.
- **Evidence:** `SidebarItemSearchTextTests` covers exact legacy parity, hidden system/tool messages,
  boundary separators, and composed Unicode. An optimized 128-million-character stress benchmark
  reduced twelve projections from about 105 ms to 0.49 ms while producing the same output.

## 2026-08-08: first-run developer keys reuse the Settings credential path

- **Decision:** The first-run connection surface offers browser OAuth as the primary action and
  `Use a developer key` as a clearly secondary action. The secondary action presents the existing
  Settings sheet with a one-shot `.developerOverride` draft override; it does not introduce another
  secret field, persistence service, or Keychain owner.
- **Persistence boundary:** The override changes only the newly presented settings draft. The active
  workspace configuration remains OAuth until the user explicitly saves Settings, after which the
  existing bootstrap and secret-store path owns validation and persistence. Canceling or closing the
  sheet clears the presentation override without mutating configuration.
- **Release evidence:** The native Accessibility smoke activates the first-run button before any
  workspace-replacement interactions, requires the Developer override secure key field, and dismisses
  Settings through its real Close button. Later resource-convergence sweeps omit this initial-only
  action while repeating every control that remains valid after workspace mutation.
- **Why:** Developer-key users need a discoverable first-run path, but credential storage and failure
  handling should remain centralized. A presentation-only route gives them one click to the correct
  form without creating divergent security behavior.

## 2026-08-08: release smoke fallbacks preserve current UI and connection truth

- **Native command fallback:** Accessibility activation continues to prefer the visible workspace
  control. When that control is temporarily absent after a repeated interaction sweep, the existing
  native-menu fallback also recognizes plain, three-dot, and Unicode-ellipsis command titles. The
  fallback still resolves a real menu item and performs `AXPress`; it does not replace interaction
  evidence with direct model mutation.
- **Connection generation fence:** An exec-server status response may arrive immediately before the
  WebSocket reader observes a close. The status call captures its connection generation and may only
  clear the disconnect error when that generation, initialized state, and socket are still current.
  A stale response therefore cannot turn a newer disconnect into a misleading pending state.
- **Why:** Real Intel packaging exposed the Settings title mismatch during the second native sweep,
  while exact-main CI exposed the response/close ordering race. Release smoke should remain strict
  about actual user interaction and actual connection state while tolerating equivalent platform
  title spelling and actor scheduling order.

## 2026-08-08: stable releases use verified promotion and automatic quarantine

- **Decision:** A versioned release first becomes a non-latest prerelease candidate. The exact public
  inventory and semantic contract must pass before the candidate can become GitHub's stable latest
  release. Candidate verification is an explicit verifier mode and remains invalid for tester builds.
- **Promotion proof:** After promotion, native Apple silicon and Intel runners update and relaunch
  through the real stable latest feed. Final verification requires both GitHub's latest-release
  identity and the moving stable manifest bytes to match the verified versioned release.
- **Recovery:** Candidate verification failure returns the new release to draft before promotion.
  Native updater or final feed failure returns a promoted release to draft, causing GitHub to resume
  the previous stable latest release without modifying that prior release.
- **Why:** Upload completion does not prove public asset semantics, and a successful release-edit
  command does not prove the moving updater feed. Stable publication must be an ordered, observable,
  fail-closed state transition with an automatic path back to the last known-good release.

## 2026-08-08: macOS distribution is native on Apple silicon and Intel

- **Decision:** Every public macOS release contains exactly one native arm64 and one native x86_64
  app ZIP, DMG, CLI archive, build-info file, and performance report. GitHub packages and measures
  each set on a matching native runner instead of cross-publishing an unexecuted binary.
- **Updater compatibility:** `updater.macOSAppAssets` is the canonical arm64/x86_64 inventory. The
  legacy `updater.macOSAppAsset` remains the arm64 archive so existing Apple-silicon tester builds
  can install the transition release; new clients select exactly one matching architecture and
  reject missing or duplicate matches.
- **Publication boundary:** The public verifier requires the complete architecture matrix, checks
  both build-info contracts and performance reports, and reads each ZIP's thin Mach-O header. Native
  post-publication updater jobs then prove download, validation, swap, and relaunch on both runners.
- **Why:** A public desktop app should not exclude Intel users or label an unexecuted cross-build as
  supported. Native packaging plus native daily-path updater validation makes support measurable.

## 2026-08-08: public performance evidence is verified semantically

- **Decision:** The post-publication release verifier must require one performance asset for each
  supported macOS architecture and validate its meaning after size, digest, and checksum verification.
- **Contract:** Published evidence uses the canonical production schema, boundaries, two-sweep count,
  three fresh attempts, two-of-three launch policy, median selected headline, and exact production
  budgets. The verifier recomputes raw memory/thread deltas, MiB projections, every budget result,
  launch pass counts, and headline fields instead of trusting embedded success flags.
- **Failure behavior:** Missing evidence, extra/missing fields without a schema bump, weakened limits,
  incomplete aggregation, forged deltas, non-finite values, resource overruns, or selected-attempt
  drift fail the public release job even when all published hashes are internally consistent.
- **Why:** Checksums prove which bytes were published, not that those bytes still prove Quill Cowork's
  native speed and resource promises. Distribution readiness requires both integrity and semantics.

## 2026-08-08: repeated native interactions must converge

- **Decision:** Every packaged performance process runs the same reversible native Accessibility
  interaction sweep twice. Process resources are captured at the initial live window and after a
  one-second settling interval following each sweep; the second sweep must pass every interaction
  contract again before its resources can become release evidence.
- **Budgets:** All three resident-memory samples remain capped at 256 MiB and all thread samples at
  64. The first sweep may retain at most 80 MiB over the initial window, while the repeated sweep may
  add at most 16 MiB or four threads over the first settled snapshot. Launch timing remains a
  two-of-three gate; every resource sample and convergence delta must pass in every fresh process.
- **Evidence contract:** Version-3 performance evidence carries the three raw snapshots, two signed
  memory/thread deltas, exact sweep count, per-attempt results, and all enforced budgets. Validation
  recomputes both deltas and rejects a missing sweep, forged growth value, or repeated thread surge.
- **Calibration:** Three optimized local processes added 8.27, 5.12, and 3.97 MiB on the repeated
  pass, with repeated thread deltas of -1, 0, and 1. The 16 MiB ceiling leaves nearly twice the worst
  observed allocator variation without allowing sustained UI-state accumulation to ship.
- **Why:** A single post-interaction snapshot distinguishes a light first frame from one-time UI
  warming, but cannot prove repeated open/type/dismiss cycles release transient state. Convergence is
  the stronger daily-driving signal and protects Quill Cowork's native memory advantage.

## 2026-08-08: release performance includes settled interaction resources

- **Decision:** Every packaged performance attempt captures process resources at the initial live
  window and again after the existing reversible native interaction sweep has restored the UI and
  settled for one second. Launch timing remains anchored to the first snapshot.
- **Budgets:** Initial and post-interaction resident memory must each remain at or below 256 MiB,
  retained growth must remain at or below 80 MiB, and both thread counts must remain at or below 64.
  Every fresh process must pass the resource budgets; launch timing retains its two-of-three policy
  to tolerate a loaded hosted runner.
- **Evidence contract:** The version-2 performance report and public asset carry both snapshots,
  signed memory/thread growth, per-attempt budget results, and the selected median-launch attempt.
  The validator recomputes growth from the snapshots instead of trusting reported deltas.
- **Why:** The release smoke already exercised real sheets, panes, search, text entry, and model
  selection, but sampled resources only before that work. A build could therefore launch lightly
  and retain expensive UI or worker state without failing publication.

## 2026-08-08: first launch explains relocation before updates are needed

- **Status:** Superseded by the 2026-08-09 transactional first-install relocation decision above.
- **Decision:** A packaged app launched from a read-only disk image, App Translocation, or another
  non-replaceable location outside `/Applications` presents a native installation reminder
  immediately. The primary action opens `/Applications`; the user can still defer or close the sheet.
- **Frequency:** Deferral is remembered once per bundle identifier and build. The same build does not
  interrupt every launch, while a newly downloaded build can explain its installation state again.
  Writable installed copies and copies already inside `/Applications` never present the reminder.
- **Presentation boundary:** Installation guidance and updater state share one sheet presenter. The
  installation reminder has priority while visible, then an already available update can occupy the
  same surface after dismissal. Smoke modes disable the reminder so automation remains deterministic.
- **Ownership:** The reminder reuses the updater's injected installation-location inspector. The
  inspector decides whether the bundle is replaceable, a small controller owns persistence and the
  Applications action, and SwiftUI only projects state.
- **Why:** The updater could explain a read-only location only after a newer build existed. A new user
  launching directly from the DMG therefore received no guidance at the moment moving the app mattered.
- **Evidence:** Controller tests cover writable suppression, read-only presentation, once-per-build
  dismissal, disabled configuration, and the Applications action. A fixed-size rendered test and a
  normal launch from a mounted packaged DMG cover the real first-run surface.

## 2026-08-08: updater preflights read-only installation locations

- **Decision:** The desktop updater inspects the running app bundle, executable, and parent-directory
  writability before downloading an available update. A copy launched from a read-only disk image,
  App Translocation, or another non-replaceable location presents a manual installer action instead
  of starting preparation that cannot finish.
- **Recovery contract:** The release model carries the architecture-matching DMG only after its kind,
  install mode, bounded size, digest, safe `.dmg` name, exact URL filename, tag, and repository URL
  pass manifest validation. Query and fragment suffixes are rejected. Manual recovery opens that
  installer, falling back to the scoped release page for older manifests that do not declare one.
  It never sends an ordinary user to the machine-oriented updater ZIP.
- **Race boundary:** Preflight is a UX optimization, not the authority for mutation. The installer
  rechecks the app identity, executable, destination existence, and parent writability immediately
  before staging beside the running bundle.
- **Why:** The DMG is intentionally read-only and is also the first place many users launch a newly
  downloaded app. Previously Quill Cowork could download and validate the entire update before
  reporting that it could not replace itself, then offer the ZIP as its browser fallback.
- **Evidence:** Filesystem tests cover writable and read-only parents, non-directory app paths, and
  executables outside the bundle; controller tests prove no preparation or installation starts when
  relocation is required; manifest tests reject hostile and malformed installer URLs; fixed-size
  rendering and a real mounted-DMG launch cover the dedicated installer state.

## 2026-08-08: updater signing policy survives the Developer ID cutover

- **Decision:** Manifest validation derives one typed payload requirement. Tester updates are either
  exactly ad-hoc with no team or notarization claim, or Developer ID Application signed with a valid
  ten-character team and Apple notarization. Stable updates require the latter and an already pinned
  matching team.
- **Payload boundary:** Archive verification carries that requirement into app validation. The
  downloaded bundle must pass strict `codesign` verification, its `Signature`, `Authority`, and
  `TeamIdentifier` fields must match the manifest-derived requirement, and Developer ID payloads must
  also pass `spctl --assess`. A valid signature from another team, an Installer certificate, a false
  notarization claim, or an ad-hoc downgrade is rejected before staging.
- **Migration boundary:** An existing ad-hoc tester may trust its first notarized Developer ID
  Application through the configured GitHub feed and Apple assessment. That replacement embeds its
  team identifier, after which tester and stable updates are pinned to that exact team. The public
  manifest schema stays unchanged, so build 651 can still install the first hardened ad-hoc build.
- **Why:** Before this change, an ad-hoc tester accepted Developer ID metadata without requiring
  notarization, while downloaded-app validation accepted any internally valid signature when no team
  was embedded. Adding Apple credentials could therefore make the signing transition less strict
  than steady-state updates.
- **Evidence:** `QuillCodeDesktopUpdateSigningTests` cover contradictory metadata, malformed teams,
  notarization, trust transition, downgrade/cross-team refusal, stable pinning, and signature output
  parsing. The public updater smoke continues to exercise download, payload validation, swap, and
  relaunch against the published ad-hoc channel.

## 2026-08-08: streaming progress coalesces expensive desktop projection

- **Decision:** Every model progress callback still updates the authoritative thread and run state,
  while the native desktop coalesces `WorkspaceSurface` projection behind one 50 ms main-actor
  cadence. Ordinary sends, side conversations, failed-run retries, code reviews, and recorded
  workflow skill creation share the same presentation path.
- **Responsiveness boundary:** Send start, terminal completion, cancellation, failure, and every
  user-driven refresh bypass the cadence. An immediate refresh cancels the pending projection and
  renders the latest model state, so coalescing cannot leave stale Thinking, Stop, approval, or final
  answer UI behind.
- **Resource boundary:** A burst owns at most one delay task and one replaceable weak-controller
  callback. The delay task does not retain its scheduler, and scheduler teardown cancels it. Ten
  thousand synchronous progress signals therefore retain one pending presentation update instead of
  constructing ten thousand full transcript/sidebar/activity surfaces.
- **Why:** Streaming token fragments previously awaited a complete surface rebuild on every callback.
  Long transcripts amplified transient allocation, main-thread work, and provider backpressure even
  though only the newest fragment could be displayed at the next visible cadence.
- **Evidence:** `QuillCodeDesktopProgressRefreshSchedulerTests` cover 10,000-signal coalescing,
  latest-state publication, cancellation, immediate flush, and non-retention. The concurrent-chat
  integration suite proves streaming progress uses the bounded path while start and finish remain
  immediate.

## 2026-08-08: update activation survives an immediate post-launch crash

- **Decision:** The detached updater retains the previous application until the replacement both
  writes its launch handshake and remains alive for a three-second startup observation window. If
  the replacement exits during that window, the helper atomically restores and reopens the previous
  build instead of treating the handshake alone as a successful installation.
- **Persistence boundary:** The one-shot install result is accepted only as a regular non-symlink
  file of at most 64 KiB through the shared bounded persistence reader. Missing, malformed,
  oversized, and unexpected filesystem entries are removed without becoming visible update state;
  helper result writes enforce the same size contract.
- **User experience:** A replacement that crashes immediately returns the user to the working build
  and reports that startup stopped and rollback succeeded. Healthy replacements still appear at
  once; only the detached helper waits before deleting the backup and reporting final success.
- **Evidence:** `QuillCodeDesktopUpdateModelTests` launches a fixture that acknowledges and exits,
  then verifies restoration and relaunch of the prior build. `QuillCodeDesktopUpdateControllerTests`
  covers oversized and dangling-symlink result rejection, while the packaged updater smoke exercises
  the complete signed-bundle swap, observation, cleanup, and relaunch path.

## 2026-08-08: damaged workspace registries recover independently

- **Decision:** Config, projects, automations, and saved-search registries are accepted only as
  regular non-symlink files within explicit 4 MiB or 16 MiB limits. Bootstrap loads each registry
  independently, so one rejected file uses a safe in-memory default without hiding healthy chats or
  other registries.
- **Preservation boundary:** Startup never rewrites a rejected registry. Its store is detached for
  the recovery session, preventing automatic model saves from replacing recoverable bytes. Failed
  subagent reconciliation saves are also reported without aborting launch.
- **User experience:** One content-free warning names affected data categories and the number of
  healthy chats loaded. It routes to Settings diagnostics without exposing absolute paths, file
  contents, or decoder errors. If workspace-directory setup is incomplete, bootstrap still loads
  readable state and presents an explicit storage-recovery warning instead of silently constructing
  a blank-looking workspace.
- **Why:** Singleton registry loads previously shared one throwing bootstrap path. A malformed
  `projects.json`, `automations.json`, `sidebar-saved-searches.json`, or `config.toml` therefore made
  every healthy conversation appear gone for that launch, and several reads had no preflight bound.
- **Evidence:** `BoundedFileDataReaderTests`, `ConfigStoreTests`,
  `WorkspaceConfigurationIntegrationTests`, `JSONThreadStoreTests`, and
  `QuillCodeDesktopControllerSmokeTests` cover bounded rejection, independent recovery, unchanged
  source bytes, healthy-state preservation, aggregated diagnostics, and catastrophic storage failure.

## 2026-08-07: damaged saved chats stay bounded, visible, and recoverable

- **Decision:** Persisted chat files are inspected as regular non-symlink files before decoding,
  rejected above 128 MiB, and loaded with mapped data. Startup continues with every healthy chat
  when another file is truncated, schema-incompatible, oversized, or an unexpected filesystem type.
- **Recovery boundary:** Rejected files remain unchanged. Bootstrap carries only bounded reason
  counts and validated UUID chat IDs into a persistent warning; the transcript and Settings expose
  recovery diagnostics without reading file contents, displaying absolute paths, or leaking decoder
  errors. The warning takes priority over provider status until the storage problem is resolved.
- **Why:** The persistence layer already skipped damaged files, but bootstrap discarded that evidence,
  making chats disappear silently. Unbounded reads also let one malformed file create an avoidable
  startup memory spike.
- **Evidence:** `JSONThreadStoreTests` cover healthy preservation, strict direct loads, sparse
  oversized files, and symlink refusal. `WorkspaceConfigurationIntegrationTests` covers bootstrap
  diagnostics and source-file preservation, while `QuillCodeDesktopRenderedSmokeTests` verifies the
  warning in an otherwise empty workspace.

## 2026-08-07: update downloads are bounded while bytes are in flight

- **Decision:** The desktop updater streams each response directly into an updater-owned hidden
  partial file. It rejects a declared oversized response before accepting it, cancels at the first
  chunk that would exceed the manifest size, and requires the completed transfer to match that size
  exactly before moving it into the preparation workspace.
- **Resource boundary:** Response bytes do not accumulate in memory. Progress reporting is throttled,
  the controller keeps only the newest pending update, and every failure or cancellation closes and
  removes the partial file before returning.
- **User experience:** The update sheet shows determinate bytes and percentage while downloading,
  followed by distinct verifying, unpacking, and app-validation phases. Operation generations prevent
  late progress from a cancelled or replaced transfer from changing visible state.
- **Evidence:** `QuillCodeDesktopUpdateTests` exercise exact streaming, declared and runtime oversize
  rejection, cancellation, and partial-file cleanup. `QuillCodeDesktopUpdateControllerTests` covers
  progress lifetime, and `QuillCodeDesktopRenderedSmokeTests` verifies the fixed-size sheet at 50%.

## 2026-08-07: transcript projection stays linear in long-session history

- **Decision:** Message events use an on-demand content index that consumes duplicate text in
  persisted source order, and revert planning advances one chronological user-turn cursor across
  queued tool events. Equal timestamps use persisted source order as the deterministic tie-breaker.
- **Why:** The native transcript uses lazy view construction, but its model projection still matched
  every message event by rescanning all messages and attributed every queued tool by searching all
  prior user turns. Rebuilding a long daily-driving transcript could therefore take quadratic work
  before SwiftUI displayed any row. Message-only chats also sorted every user turn for revert plans
  even when no queued tool existed.
- **Safety boundary:** The message index remains lazy until a message event needs it, unmatched visible
  messages still append in source order, duplicate IDs retain their historical suppression behavior,
  and out-of-order persisted collections are sorted without changing within-timestamp source order.
- **Evidence:** `WorkspaceTranscriptSurfaceBuilderTests` cover duplicate text, duplicate IDs, and
  unmatched messages, including a 10,000-message projection fixture.
  `WorkspaceTurnRevertPlannerTests` cover chronological grouping, out-of-order persistence,
  equal-time attribution, and a 2,500-editing-turn fixture.

## 2026-08-07: shell subprocesses receive the environment used to plan their launch

- **Decision:** Synchronous and streaming shell execution resolve one effective environment and pass
  that same value to sandbox planning and `Process`. An omitted command-local environment inherits
  the Quill Cowork process environment explicitly; an explicit environment remains authoritative.
- **Why:** The launch paths previously computed the inherited environment for sandbox setup but
  assigned the original optional override to `Process`. Under SwiftPM and some GUI launch contexts,
  login shells could start without `HOME`, source the user's profile with broken absolute paths, and
  contaminate command and SSH diagnostics. The mismatch also made full-suite results depend on the
  developer machine's profile.
- **Evidence:** `ShellToolExecutorTests` cover inherited `HOME` in synchronous and streaming paths.
  `AppServerUserShellTests` uses an isolated temporary home, and `SSHRemoteProjectProbeTests` proves
  that the intended remote failure remains the surfaced diagnostic.

## 2026-08-07: interrupted updates clean up only updater-owned staging

- **Decision:** Failed or cancelled preparation removes the workspace it created. On app startup,
  `QuillCodeDesktopUpdateRecovery` waits two minutes and then removes only immediate hidden sibling
  directories named `.Quill Cowork.update-<lowercase UUID>.app` beside a valid configured Quill
  Cowork bundle.
- **Safety boundary:** Recovery refuses symlinks, malformed identifiers, other app names, and an
  unexpected destination bundle identity. The grace period exceeds the helper's parent-exit and
  launch-handshake budgets so a second app instance cannot delete a legitimate in-flight staging
  bundle. The successful preparation workspace remains intact for the detached helper.
- **Why:** A process or machine stop can happen before activation, after the atomic swap, or during
  rollback cleanup. Every window keeps a runnable destination bundle, but without reconciliation a
  hidden full app copy could remain indefinitely. The bounded ownership contract recovers disk space
  without broad deletion beside the user's installed application.
- **Evidence:** `QuillCodeDesktopUpdateRecovery`, `QuillCodeDesktopUpdatePreparer`,
  `QuillCodeDesktopUpdateControllerTests`, and `QuillCodeDesktopUpdateTests` cover exact ownership,
  symlink/lookalike refusal, startup idempotence, cancellation, failure, swap, and rollback paths.

## 2026-08-06: macOS updates use a verified staged swap with rollback

- **Decision:** Quill Cowork consumes its embedded GitHub release manifest directly. It checks on a
  channel-specific cadence and through a manual app-menu command, then validates repository, channel,
  architecture, version/build, asset size, SHA-256, app identity, code signature, and configured
  signing team before offering Update and Relaunch.
- **Crash boundary:** The running app copies the verified bundle to a hidden sibling and launches a
  copied helper. The helper waits for the parent to exit, keeps the old bundle as a backup, activates
  the staged bundle, and requires a launch-handshake file from the new app. A missing handshake rolls
  back and reopens the prior bundle instead of leaving a broken installation.
- **Distribution boundary:** Tester builds may remain ad-hoc signed for rapid iteration. Stable tags
  fail closed unless CI has a Developer ID Application certificate, signing team, and App Store
  Connect API key; configured builds use the hardened runtime, `notarytool`, and a stapled ticket.
- **Why:** An update feed without an in-app consumer does not make the product updateable, while a
  blind self-replacement can strand users. The staged handshake keeps updates user-visible and
  recoverable while preserving a direct browser fallback for read-only or protected locations.
- **Evidence:** `QuillCodeDesktopUpdateController`, `QuillCodeDesktopUpdatePreparer`,
  `QuillCodeDesktopUpdateHelper`, `scripts/package-macos-downloads.sh`, and
  `QuillCodeDesktopUpdateTests`.

## 2026-07-27: Office Coworker Catalog Drives QuillCode Parity Tracking

- **Decision:** Treat the office coworker task spreadsheet as the canonical QuillCode coverage
  tracker for business-user workflows, not just a brainstorming list.
- **Rationale:** The 310-row catalog spans file cleanup, document packets, multi-file summaries,
  spreadsheets, browser/SaaS tasks, and Computer Use. A durable tracker makes it clear which rows are
  covered by current code/tests and which still need focused smoke evidence.
- **Implementation:** Columns K:N in the sheet now derive QuillCode coverage, evidence, next gap, and
  review date from the existing row metadata. QuillCode also gained compact office-task prompt
  guidance and broader promised-work verb detection so "inventory assets", "standardize the sheet",
  and "chart usage" cannot silently degrade into future-tense narration when tools are available.
- **Constraint:** The base prompt remains small; row-specific instructions belong in the sheet,
  focused tests, and optional skills. Rows move to covered only when current source/test/smoke
  evidence proves the actual user-facing task.
- **Update:** Optional live SaaS evidence now must include `catalogTaskIDs`, the exact row IDs from
  the office coworker catalog that a signed-in SaaS run proves. The manifest writes those IDs and the
  canonical spreadsheet URL beside service, task, tool sequence, live-DOM, and Computer Use evidence
  so humans or secure live-SaaS harnesses can update only the proven rows.
- **Update:** Live SaaS capture now has a row-linked evidence template generator,
  `scripts/live-saas-template.sh`. The generated JSON starts with the exact catalog rows, the
  required browser proof shape, optional Computer Use proof shape, and the validation command, but it
  remains intentionally invalid until every placeholder is replaced by a real signed-in capture.
- **Update:** The native smoke contract CLI can now roll validated live SaaS manifests into a
  `coworker-coverage.json` summary with `provenTaskIDs`, `pendingTaskIDs`, and `evidenceByTaskID`.
  This gives the spreadsheet a durable row-level audit artifact before changing status cells.
- **Update:** Packaged macOS smoke now emits `packaged-one-turn-coworker.json` for catalog rows
  #15, #16, #17, #18, #19, #20, #21, #22, #23, #24, #25, #26, #27, #28, #29, #30, #31, #32, #33, #34, #35, #36, #37, #38, #39, #40, #41, #42, #43, #44, #45, #46, #47, #48, #49, #50, #51, #52, #53, #54, #55, #56, #57, #58, #59, #60, #61, #62, #63, #64, #65, #66, #67, and #68. The manifest compares direct packaged executable and Launch Services
  evidence, proving non-empty `host.file.write`/`host.shell.run` actions plus artifact assertions
  before those rows can be treated as row-linked one-turn coworker coverage. The manifest now carries
  the canonical spreadsheet URL and `catalogTaskIDs`, and the coworker coverage rollup accepts it as
  first-class row evidence.
- **Update:** Packaged macOS smoke now emits row-linked multi-file artifact evidence in
  `packaged-multi-file-artifact.json`. The row #69 case reads `org-changes.pptx` and
  `reorg-qa/hardest-questions.md`, writes `ceo-reorg-all-hands-email.md`, verifies the reorg details,
  transition dates, and eight hard questions, so the coworker coverage rollup can count deterministic
  multi-source deliverables independently from one-turn shell rows.
- **Update:** The same packaged multi-file artifact manifest now includes catalog row #70. The row
  #70 case reads three `analyst-reports` sources, writes `analyst-claims-contradictions.md`, verifies
  Gartner claims, Forrester claims, explicit contradictions, and recommended framing, and exposes
  row-linked catalog evidence so deterministic multi-document synthesis advances in the coworker
  coverage rollup.
- **Update:** The packaged multi-file artifact manifest now includes catalog row #71, Bulk Rename.
  The row #71 case reads two invoice PDFs under `Documents/Invoices`, runs a shell rename operation
  that moves them to `YYYY-MM-DD_Vendor_Amount.pdf` names, writes
  `Documents/Invoices/invoice-rename-undo.csv`, verifies both renamed outputs and undo mappings, and
  exposes `catalogTaskIDs: [69, 70, 71]` so deterministic multi-file mutation coverage advances in
  the coworker coverage rollup.
- **Update:** The packaged multi-file artifact manifest now includes catalog row #72, Capacity
  Planning. The row #72 case reads `allocations.csv` plus three project plans, writes
  `capacity-rebalance.md`, verifies overbooked people, named swaps, project constraints, and
  at-or-under-capacity outcomes, and exposes `catalogTaskIDs: [69, 70, 71, 72]` so deterministic
  multi-document planning coverage advances in the coworker coverage rollup.
- **Update:** The packaged multi-file artifact manifest now includes catalog row #73, Compliance
  Audit. The row #73 case reads three subcontractor COI PDFs under `coi-pdfs`, writes
  `coi-compliance-audit.csv`, verifies carrier, policy number, limits, expiry, under-limit, and
  expiring-soon flags, and exposes `catalogTaskIDs: [69, 70, 71, 72, 73]` so deterministic
  compliance extraction coverage advances in the coworker coverage rollup.

## 2026-07-27: TrustedRouter balance history is locally observed

- **Decision:** Keep a bounded, most-recent-first history of successful TrustedRouter account-balance
  snapshots in `TrustedRouterCreditsState` and surface it in the top-bar balance detail.
- **Why:** Users need to see whether their provider credits are moving, and Codex parity expects
  account/quota visibility. The current TrustedRouter credits endpoint returns the present balance,
  not a provider-hosted ledger, so QuillCode should be explicit that history is locally observed.
- **Boundary:** This is not a provider-owned transaction ledger. If TrustedRouter exposes a ledger or
  quota-history API later, that should replace or augment the local observation list.

## 2026-07-19: Render Robot XML As A Bounded Artifact Preview

- **Decision:** Treat local `.xml` files whose root validates as Robot Framework `robot` output as
  acceptance/integration test reports rather than generic XML.
- **Rationale:** Robot Framework is common in UI, device, and acceptance testing. Showing suite,
  test, keyword, status-bucket, runtime, and capped failing-test labels gives readable Codex-style
  verification feedback without opening raw XML.
- **Constraints:** Only local regular files under 512 KB are parsed; QuillCode does not read Robot
  suites, expand keyword logs or messages, run Robot, load listener metadata, or fetch remote reports.

## 2026-07-19: Render TestNG XML As A Bounded Artifact Preview

- **Decision:** Treat local `.xml` files whose root validates as TestNG `testng-results` output as
  Java test reports rather than generic XML.
- **Rationale:** TestNG is common in Java, Selenium, and mobile automation projects. Showing suite,
  test-group, class, method, status-bucket, runtime, and capped failing-method labels gives readable
  Codex-style verification feedback without opening raw XML.
- **Constraints:** Only local regular files under 512 KB are parsed; QuillCode does not read Java
  source files, expand reporter logs or stack traces, run TestNG, load suite configuration, or fetch
  remote reports.

## 2026-07-19: Render Allure JSON As A Bounded Artifact Preview

- **Decision:** Treat local `.json` files whose root validates as an Allure test-result JSON object
  as structured test-report output rather than generic JSON.
- **Rationale:** Allure is common around browser, mobile, and integration suites. Showing the result
  name, status, step counts, runtime, suite labels, and capped failing result labels gives readable
  Codex-style verification feedback without opening raw JSON.
- **Constraints:** Only local regular files under 512 KB are parsed; QuillCode does not read source
  files, expand attachments or status-detail logs, run Allure, load report directories, or fetch
  remote reports.

## 2026-07-19: Render CTest XML As A Bounded Artifact Preview

- **Decision:** Treat local `.xml` files whose root validates as CTest `Site/Testing/Test` output
  as C/C++ test reports rather than generic XML.
- **Rationale:** CMake/CTest is a common verification path for native projects. Showing test counts,
  pass/fail/not-run buckets, runtime, and capped failing test labels gives readable Codex-style
  feedback without opening raw XML.
- **Constraints:** Only local regular files under 512 KB are parsed; QuillCode does not read CMake
  projects or source files, expand test output logs, run CTest, load dashboard metadata, or fetch
  remote reports.

## 2026-07-19: Render RSpec JSON As A Bounded Artifact Preview

- **Decision:** Treat local `.json` files whose root validates as RSpec JSON formatter output as
  Ruby test reports rather than generic JSON.
- **Rationale:** Ruby/Rails coding sessions commonly produce RSpec JSON. Showing example counts,
  pass/fail/pending buckets, runtime, and capped failing/pending example labels gives useful
  Codex-style feedback without opening raw JSON.
- **Constraints:** Only local regular files under 512 KB are parsed; QuillCode does not read Ruby
  source files, expand exception backtraces, run RSpec, load formatter configuration, or fetch remote
  reports.

## 2026-07-19: Render Cucumber JSON As A Bounded Artifact Preview

- **Decision:** Treat local `.json` files whose root validates as Cucumber JSON formatter output as
  acceptance-test reports rather than generic JSON.
- **Rationale:** Cucumber-style acceptance tests often describe end-user workflows in a way that is
  useful in Codex-like coding sessions. Showing feature/scenario/step counts, status buckets,
  runtime, and capped failing scenario labels gives readable feedback without opening raw JSON.
- **Constraints:** Only local regular files under 512 KB are parsed; QuillCode does not read feature
  files, expand step errors, run Cucumber, load formatter configuration, or fetch remote reports.

## 2026-07-19: Render Playwright JSON As A Bounded Artifact Preview

- **Decision:** Treat local `.json` files whose root validates as Playwright JSON reporter output
  as browser/E2E test reports rather than generic JSON.
- **Rationale:** Playwright is a common way Codex-style coding sessions verify UI behavior. Showing
  expected/unexpected/flaky/skipped counts, runtime, and capped failing spec labels gives useful
  feedback without opening raw reporter JSON.
- **Constraints:** Only local regular files under 512 KB are parsed; QuillCode does not read
  Playwright config or source files, expand error stacks, run browsers, resolve traces/videos, or
  fetch remote reports.

## 2026-07-19: Render Mocha JSON As A Bounded Artifact Preview

- **Decision:** Treat local `.json` files whose root validates as Mocha JSON reporter output as
  JavaScript test reports rather than generic JSON.
- **Rationale:** Node coding sessions commonly export Mocha JSON. Showing test/pass/fail/pending
  counts, runtime, and capped failure/pending labels gives useful Codex-style feedback without
  opening raw JSON.
- **Constraints:** Only local regular files under 512 KB are parsed; QuillCode does not read
  JavaScript source files, expand stack traces, run Mocha, load test configuration, or fetch remote
  reports.

## 2026-07-19: Render Go Test JSONL As A Bounded Artifact Preview

- **Decision:** Treat local `.jsonl` and `.ndjson` files whose records validate as Go
  `go test -json`/`test2json` output as test-result reports rather than generic JSON Lines.
- **Rationale:** Go coding sessions commonly capture line-oriented test output. Showing
  event/package/test/pass/fail/skip counts plus capped failed/skipped test labels gives useful
  Codex-style feedback without opening raw NDJSON.
- **Constraints:** Only local regular files under 512 KB are parsed; QuillCode does not read Go
  source files, expand output lines, run `go test`, load module metadata, or fetch remote reports.

## 2026-07-19: Render Psalm JSON As A Bounded Artifact Preview

- **Decision:** Treat local `.json` files whose root validates as Psalm JSON output as a
  specialized PHP static-analysis report rather than generic JSON.
- **Rationale:** Psalm reports are common in PHP coding sessions and CI exports. Showing
  issue/file/type/severity-bucket counts plus capped file/type labels gives useful Codex-style
  feedback without opening raw JSON.
- **Constraints:** Only local regular files under 512 KB are parsed; QuillCode does not read PHP
  source files, expand diagnostic messages, run Psalm, load Psalm configuration, or fetch remote
  reports.

## 2026-07-19: Render PHPStan JSON As A Bounded Artifact Preview

- **Decision:** Treat local `.json` files whose root validates as PHPStan JSON output as a
  specialized PHP static-analysis report rather than generic JSON.
- **Rationale:** PHPStan reports are common in PHP coding sessions and CI exports. Showing
  error/file/identifier counts plus capped file/identifier labels gives useful Codex-style feedback
  without opening raw JSON.
- **Constraints:** Only local regular files under 512 KB are parsed; QuillCode does not read PHP
  source files, expand diagnostic messages, run PHPStan, load PHPStan configuration, or fetch remote
  reports.

## 2026-07-19: Render SwiftLint JSON As A Bounded Artifact Preview

- **Decision:** Treat local `.json` files whose root validates as SwiftLint JSON output as a
  specialized Swift lint report rather than generic JSON.
- **Rationale:** SwiftLint JSON is the common native report format for Swift projects. Showing
  violation/file/rule/severity counts plus capped file/rule labels gives useful Codex-style feedback
  without opening raw JSON.
- **Constraints:** Only local regular files under 512 KB are parsed; QuillCode does not read Swift
  source files, expand violation reasons, invoke SwiftLint, load rule configuration, or fetch remote
  reports.

## 2026-07-19: Render Cargo Compiler JSONL As A Bounded Artifact Preview

- **Decision:** Treat local `.jsonl` and `.ndjson` files whose records include Cargo
  `compiler-message` entries as Rust compiler/Clippy diagnostics rather than generic JSON Lines.
- **Rationale:** Rust coding sessions commonly capture `cargo check --message-format=json` and
  Clippy output. Showing diagnostic/file/code/level counts plus capped file/code labels gives useful
  Codex-style feedback without opening raw line-oriented JSON.
- **Constraints:** Only local regular files under 512 KB are parsed; QuillCode does not read Rust
  source files, expand spans, invoke Cargo, load Cargo metadata, or fetch remote reports.

## 2026-07-19: Render Pyright JSON As A Bounded Artifact Preview

- **Decision:** Treat local `.json` files whose root validates as native Pyright JSON output as a
  specialized Python type-check report rather than generic JSON.
- **Rationale:** Pyright reports are common in Python coding sessions and CI exports. Showing
  diagnostic/file/rule/severity counts plus capped file/rule labels gives useful Codex-style
  feedback without opening the raw report.
- **Constraints:** Only local regular files under 512 KB are parsed; QuillCode does not read Python
  source files, expand diagnostic messages, load Pyright configuration, shell out, or fetch remote
  reports.

## 2026-07-19: Render mypy JSON As A Bounded Artifact Preview

- **Decision:** Treat local `.json` and `.jsonl` files whose records validate as mypy JSON output
  as a specialized Python type-check report rather than generic JSON or JSON Lines.
- **Rationale:** mypy reports are common in Python coding sessions and CI exports. Showing
  diagnostic/file/code/severity counts plus capped file/code labels gives useful Codex-style
  feedback without opening the raw report.
- **Constraints:** Only local regular files under 512 KB are parsed; QuillCode does not read Python
  source files, expand diagnostic messages, load mypy configuration, shell out, or fetch remote
  reports.

## 2026-07-19: Render Code Climate JSON As A Bounded Artifact Preview

- **Decision:** Treat local `.json` files whose root validates as Code Climate issue JSON output as
  a specialized review/static-analysis artifact rather than generic JSON.
- **Rationale:** Code Climate JSON is a common interchange format for CI quality reports across
  linters. Showing issue/file/check/category/severity counts plus capped file/check/category labels
  gives useful Codex-style feedback without opening the raw JSON.
- **Constraints:** Only local regular files under 512 KB are parsed; QuillCode does not read source
  files, expand issue locations, fetch remote reports, or call Code Climate tooling.

## 2026-07-19: Render Semgrep JSON As A Bounded Artifact Preview

- **Decision:** Treat local `.json` files whose root validates as native Semgrep JSON output as a
  specialized static-analysis artifact rather than generic JSON.
- **Rationale:** Semgrep reports are common in security and code-review sessions. Showing finding,
  file, rule, severity, and scanner-error counts plus capped file/rule labels gives useful
  Codex-style feedback without opening the raw JSON.
- **Constraints:** Only local regular files under 512 KB are parsed; QuillCode does not read source
  files, expand match snippets, load Semgrep rules, shell out, or fetch remote reports.

## 2026-07-19: Render Bandit JSON As A Bounded Artifact Preview

- **Decision:** Treat local `.json` files whose root validates as Bandit JSON output as a
  specialized security report artifact rather than generic JSON.
- **Rationale:** Bandit is a common Python security scanner. Showing issue/file/test,
  severity, and confidence counts plus capped file/test labels gives useful Codex-style feedback
  without opening the raw JSON.
- **Constraints:** Only local regular files under 512 KB are parsed; QuillCode does not read Python
  source files, expand issue code snippets, load Bandit plugins, or fetch remote reports.

## 2026-07-19: Render Pylint JSON As A Bounded Artifact Preview

- **Decision:** Treat local `.json` files whose root validates as Pylint JSON output as a
  specialized lint report artifact rather than generic JSON.
- **Rationale:** Pylint reports are common in Python coding sessions and CI exports. Showing
  message/file/symbol/type counts plus capped file/symbol labels gives useful Codex-style feedback
  without opening the raw JSON.
- **Constraints:** Only local regular files under 512 KB are parsed; QuillCode does not read Python
  source files, load Pylint plugins, expand messages, or fetch remote reports.

## 2026-07-19: Render Ruff JSON As A Bounded Artifact Preview

- **Decision:** Treat local `.json` files whose root validates as Ruff formatter output as a
  specialized lint report artifact rather than generic JSON.
- **Rationale:** Ruff reports are common in Python coding sessions. Showing violation/file/rule and
  fixable counts plus capped file/rule labels gives useful Codex-style feedback without opening the
  raw JSON.
- **Constraints:** Only local regular files under 512 KB are parsed; QuillCode does not read Python
  source files, load rules, expand violation bodies, or fetch remote reports.

## 2026-07-19: Render golangci-lint JSON As A Bounded Artifact Preview

- **Decision:** Treat local `.json` files whose root validates as golangci-lint output as a
  specialized lint report artifact rather than generic JSON.
- **Rationale:** Go coding sessions often produce `golangci-lint run --out-format json` reports.
  Showing issue/file/linter/severity counts plus capped file/linter labels gives useful Codex-style
  feedback without opening the raw JSON.
- **Constraints:** Only local regular files under 512 KB are parsed; QuillCode does not read Go
  source files, load linters, expand issue text, or fetch remote reports.

## 2026-07-19: Render SpotBugs XML As A Bounded Artifact Preview

- **Decision:** Treat local `.xml` files with a SpotBugs `BugCollection` root as a specialized
  lint report artifact rather than generic XML.
- **Rationale:** SpotBugs reports are common in Java coding sessions and CI exports. Showing
  bug/class/priority counts plus capped bug-type/category/class labels gives a useful Codex-style
  summary without opening the raw XML.
- **Constraints:** Only local regular files under 512 KB are parsed; QuillCode does not read
  bytecode, source files, expand bug messages, load detectors, or fetch remote reports.

## 2026-07-19: Render RuboCop JSON As A Bounded Artifact Preview

- **Decision:** Treat local `.json` files whose root validates as RuboCop formatter output as a
  specialized lint report artifact rather than generic JSON.
- **Rationale:** RuboCop JSON is common in Ruby coding sessions and CI exports. A compact card with
  file/offense/severity/correctable counts plus capped file/cop labels gives the user useful
  Codex-style feedback without opening a raw report.
- **Constraints:** Only local regular files under 512 KB are parsed; QuillCode does not read Ruby
  source files, load cops, expand offense messages, or fetch remote reports.

## 2026-07-19: Render PMD XML As A Bounded Artifact Preview

- **Decision:** Treat local `.xml` files with a PMD root as a specialized lint report artifact
  rather than generic XML.
- **Rationale:** PMD XML is common in Java and CI coding workflows. Showing file/violation counts,
  priority counts, and capped file/rule labels gives the user a useful Codex-style result card
  without forcing them to open the raw XML.
- **Constraints:** Only local regular files under 512 KB are parsed; QuillCode does not open
  referenced source files, expand violation bodies, run PMD, or fetch remote reports.

## 2026-07-19: Render Checkstyle XML As A Bounded Artifact Preview

- **Decision:** Treat local `.xml` files with a Checkstyle root as a specialized lint report
  artifact rather than generic XML.
- **Rationale:** Checkstyle XML is a common lint interchange format across Java, SwiftLint,
  frontend tooling, and CI exports. A compact report card with file/issue/severity counts and
  capped file/source labels is more useful than root-element metadata when reviewing tool output.
- **Constraints:** Only local regular files under 512 KB are parsed; QuillCode does not open
  referenced source files, load linter plugins, expand messages, or fetch remote reports.

## 2026-07-19: Render Stylelint JSON As A Bounded Artifact Preview

- **Decision:** Treat local `.json` files whose root validates as Stylelint formatter output as a
  specialized lint report artifact rather than generic JSON.
- **Rationale:** Stylelint reports are common in frontend coding sessions and need the same compact
  Codex-style artifact treatment as ESLint: source counts, warning/error severity, parse errors,
  deprecations, invalid option warnings, and capped rule/source labels.
- **Constraints:** Only local regular files under 512 KB are parsed; QuillCode does not read the
  referenced stylesheets, load Stylelint plugins, or fetch remote reports.

## 2026-07-19: Render ESLint JSON As A Bounded Artifact Preview

- **Decision:** Treat local `.json` files whose root validates as ESLint formatter output as a
  specialized lint report artifact instead of falling back to generic JSON metadata.
- **Rationale:** Codex-style coding sessions often generate lint reports. A bounded report card with
  file/message/error/warning/fixable counts and capped file/rule labels is more useful than raw
  top-level JSON keys while avoiding source-file reads, plugin/rule loading, or network lookups.
- **Constraints:** Only local regular files under 512 KB are parsed; remote URLs, generic JSON
  arrays, binary data, and non-ESLint shapes fall back to existing artifact handling.

## 2026-07-17: MCP run input aliases are compatible but fail closed

- **Compatibility boundary:** The public `codex` MCP tool accepts and advertises Codex-style
  kebab-case, snake_case, and camelCase spellings for top-level run arguments that clients commonly
  vary: approval policy, sandbox mode, base instructions, compact prompt, and developer
  instructions.
- **Conflict boundary:** Alias groups are mutually exclusive. If a client sends two spellings for the
  same semantic field, QuillCode rejects the call before creating or persisting a task instead of
  choosing one silently.
- **Safety boundary:** The broader config object remains allowlisted and continues to reject
  account, secret, and unknown keys. Alias compatibility does not become arbitrary config passthrough.
- **Evidence:** Focused MCP catalog/config-overlay tests prove snake/camel aliases are visible in the
  JSON schema, normalize correctly, and conflicting aliases fail closed; the parity matrix records
  that full MCP parity still excludes complete native Codex event coverage and arbitrary config
  passthrough. The later typed OS-sandbox decision defines `on-failure` retry semantics.

## 2026-07-16: Experimental feature state uses one real precedence chain

- **Catalog boundary:** One typed core registry owns canonical names, lifecycle stage, presentation
  copy, code defaults, and whether a feature can change at process runtime. The app-server projects
  only real QuillCode flags; it does not copy Codex-internal flags that have no QuillCode behavior.
- **Precedence:** Effective state is resolved as managed requirements, app-server `--enable` or
  `--disable`, merged system/user/project config, process runtime enablement, then code default.
  Project config is refreshed from the loaded task's CWD on every list request, including the primary
  checkout for linked worktrees. Invalid runtime keys are ignored without becoming latent state.
- **Runtime boundary:** `memories` is the first runtime-mutable flag because disabling it genuinely
  removes durable notes from model input while preserving those notes in the task. Re-enabling it
  restores context on the next model step. One actor-backed store is shared by every socket client in
  the app-server process, while stdio naturally owns one store for its single connection. Stable
  `hooks` state remains discoverable through the same config chain but is not advertised as
  runtime-mutable until app-server hook execution shares that gate end to end.
- **Wire contract:** `experimentalFeature/list` matches Codex's metadata/nullability, offset cursor,
  zero-limit clamping, loaded-task validation, and error boundary. `experimentalFeature/enablement/set`
  is process-only, patches named supported entries, and returns only accepted keys.
- **Evidence:** Core catalog, CLI parser, cross-session process-state, config precedence, project
  refresh, and model-context tests cover the implementation. The executable JSONL smoke and parity
  gate bind the public process contract to the tests and documentation.

## 2026-07-16: App-server agent migration revalidates and serializes every item

- **Wire contract:** `externalAgentConfig/detect`, `externalAgentConfig/import`, and
  `externalAgentConfig/import/readHistories` preserve the Codex 0.142.5 request, response, progress,
  completion, grouping, and nullability shapes. Import returns its ID before any progress event.
- **Authority boundary:** A client may choose only a subset of freshly detected details. Every import
  re-detects its source and destination and rejects an item, session path, scope, or detail that is no
  longer present. Descriptions never grant file authority.
- **Mutation boundary:** Imports are serialized so concurrent requests cannot lose config updates.
  Writes are additive, directory publication is no-overwrite and rollback-safe, hook/MCP/session
  subsets cannot broaden an empty or partial selection, and runtime config, skills, and MCP state
  refresh only after the import settles.
- **Security:** Source and destination files are bounded regular files beneath revalidated roots.
  Symlinks fail closed, static MCP secrets and Claude environment values are excluded, inherited
  variable names may remain, and private import history uses a bounded owner-only file.
- **Durability:** Recent sessions become ordinary durable QuillCode projects and tasks with Claude
  provenance. Missing session working directories fall back to the app-server workspace; history and
  provenance suppress duplicate imports across restart and crash recovery.
- **Evidence:** Persistence and actor tests cover scope, ordering, partial failure, selective import,
  concurrent config updates, secret exclusion, forged paths, session persistence, history reload,
  symlink rejection, and EOF cancellation. The real JSONL smoke and parity gate bind the public
  process, tests, and documentation together.

## 2026-07-16: Injected response items use a durable model-only timeline

- **Visibility boundary:** `thread/inject_items` never fabricates `ChatMessage` or `ThreadEvent`
  records. Raw structured response items live in `ChatThread.modelContextItems`, so thread reads,
  search, turn history, rollback projections, exports, and native transcripts remain unchanged.
- **Ordering boundary:** Each injected item records the last visible message as its anchor; no anchor
  means before the first visible turn. Prompt assembly merges items immediately after that anchor in
  request order. A missing anchor after compaction is retained at the end of available history rather
  than silently dropped.
- **Transport boundary:** Responses `message` items preserve roles, text, and inline image detail when
  projected into TrustedRouter chat-completions input. Developer messages become system messages.
  Non-message and future variants remain model-visible as sorted canonical JSON; they are never
  interpreted as locally executable tool calls.
- **Concurrency boundary:** Active turn, review, compaction, and user-shell state owns the latest task
  snapshot. Injection updates that state and persistence together; every progress/completion merge
  explicitly carries model-only context forward so an older asynchronous snapshot cannot erase it.
- **Evidence:** Exact-error actor tests cover validation, inline images, archive handling, transcript
  isolation, and persistence. A blocking-LLM test injects during an active turn and proves the item
  reaches the next model request. Prompt, legacy decode, real executable smoke, and parity-gate tests
  cover ordering and durability.

## 2026-07-16: Background-terminal control reuses thread shell ownership

- **One process owner:** App-server background-terminal methods project the existing active user-shell
  registry. They do not introduce a parallel process table or treat connection-scoped `process/spawn`
  and `command/exec` sessions as thread-owned terminals.
- **Identity and ordering:** A running shell is identified by its existing item id and real OS PID.
  Lists sort by PID and use the last PID as the forward cursor, matching current Codex behavior.
- **Race contract:** Terminate and clean first mark matching commands as terminating, then cancel their
  shared streaming sessions. They disappear from subsequent lists immediately, repeated termination
  returns `false`, and the ordinary event consumer remains responsible for exactly-once completion,
  persistence, and standalone-turn settlement.
- **Resource fields:** `osPid` is truthful; CPU and RSS remain null, matching current Codex app-server,
  until a portable bounded process-metrics adapter exists.
- **Evidence:** Concurrent-shell and invalid-input XCTest, the real executable app-server smoke, and a
  source parity gate cover PID pagination, idempotent termination, clean-all, and lifecycle cleanup.

## 2026-07-16: Thread controls separate connection state from durable settings

- **Connection contract:** Loaded and subscribed are distinct connection-local states. Start, resume,
  and fork both load and subscribe a task. `thread/unsubscribe` suppresses only detailed `turn/*` and
  `item/*` events, leaves task-level status/name events visible, and does not remove the task from
  `thread/loaded/list`. The first operation on a persisted but not-yet-loaded task subscribes it;
  later operations preserve an explicit unsubscribe. Resume always restores detailed delivery.
- **Pause contract:** Out-of-band elicitation counts belong to one app-server connection, use
  overflow-safe accounting, and disappear with that connection. They do not become durable task
  metadata or alter normal MCP elicitation ownership.
- **Persistence contract:** Git metadata, runtime settings, named permission profiles, collaboration
  mode, and memory mode are stored with app-server task metadata. Omitted patch fields preserve state;
  supported null fields follow observed Codex semantics; no-op settings patches produce no
  notification; changed settings notify only after the response.
- **Memory contract:** Disabled memory mode withholds notes from the runner rather than erasing them.
  The durable notes are restored to the completed task before persistence, so a later re-enable or
  reconnect sees the original memory state.
- **Compatibility boundary:** Built-in `:read-only`, `:workspace`, and `:danger-full-access`
  permission profiles are supported. Custom profiles and Codex's external-sandbox policy remain
  explicit future app-server work because QuillCode does not yet have equivalent configured profile
  or external-sandbox owners. External sandbox policy requests are rejected with a dedicated
  app-server error instead of being folded into a generic unsupported policy failure.
- **Evidence:** Isolated Codex 0.142.5 probes define response/error/null/ordering behavior. Focused
  actor tests cover connection isolation, event filtering, resume, patch persistence, validation,
  reconstruction, and actual model memory visibility; the real JSONL smoke exercises all six method
  families against the executable.

## 2026-07-16: Thread discovery and history use durable content and stable anchors

- **Discovery contract:** `thread/search` searches bounded persisted user and assistant transcript
  content rather than titles, returns a contextual snippet, and honors archive, source, sort, and
  pagination fields. `thread/loaded/list` is deliberately connection-scoped: persisted tasks are not
  called loaded until this client starts, resumes, forks, or runs work on them.
- **History contract:** `thread/turns/list` rebuilds durable turns from stable user-turn identities and
  supports Codex's `summary`, `full`, and `notLoaded` item views. Summary keeps the first user and final
  assistant item; full history reuses the live app-server projector for reasoning and tool cards.
- **Ordering contract:** Persisted event timestamps are only second-resolution, so they cannot define
  same-second tool ordering. Reconstruction preserves append order and aligns message events with
  persisted user/assistant messages. New pages use opaque anchor cursors with an explicit
  `includeAnchor` bit, avoiding duplicate or skipped entries when navigating in either direction.
- **Compatibility boundary:** Codex 0.142.5 advertises `thread/turns/items/list` in generated schemas
  but returns method-not-supported at runtime. QuillCode returns the same explicit error instead of
  inventing behavior a client cannot rely on.
- **Evidence:** Focused actor tests cover search semantics, connection isolation, forward/backward
  cursors, all item views, validation, multi-turn same-second tool history, and reconnect recovery. The
  real JSONL smoke exercises discovery and paging against the packaged executable.

## 2026-07-15: App-server review reuses one capability-limited engine

- **Wire contract:** `review/start` decodes Codex's uncommitted, base-branch, commit, and custom
  targets plus inline/default or detached delivery. The response precedes inline lifecycle output;
  detached review transactionally creates a persisted fork and emits `thread/started` before its
  response. Review turns share one user-item/turn identity and remain interruptible through
  `turn/interrupt`.
- **Capability boundary:** App-server review calls the same `WorkspaceCodeReviewRunner` used by the
  native and CLI workflows. MCP is not initialized, and shell, mutation, hooks, skills, web, Computer
  Use, subagents, and ordinary extension tools are removed before the model runs.
- **Transcript contract:** Intermediate reviewer prose is private investigation state. The visible
  thread retains tool evidence but receives exactly one final assistant message built from the
  validated `host.review.submit` report. Historical assistant items are marked completed when a new
  projector starts, preventing a later turn from re-emitting earlier answers.
- **Failure boundary:** Invalid targets do not mutate the parent; detached creation is complete before
  notification; active parent operations are rejected; persistence failure cancels the run; and EOF
  or explicit interruption drains the same actor-owned task lifecycle as ordinary turns.
- **Evidence:** Focused actor tests cover inline ordering and review-mode items, detached fork
  persistence, target validation, capability restriction, transcript hygiene after historical turns,
  and interruption. The real app-server process smoke runs `review/start` over JSONL and verifies the
  final report and idle transition.

## 2026-07-15: Rich turn input preserves identity and snapshots trusted skill context

- **Wire contract:** App-server `turn/start` and `turn/steer` accept Codex 0.142.5 `skill` and
  `mention` items and project them unchanged as structured user-message content. Visible transcript
  text remains separate from model-only context.
- **Skill trust boundary:** A selected path must exactly identify an enabled entry from the same
  bounded `SkillResolver` catalog used by `skills/list` and `host.skill.load`. Arbitrary, disabled,
  non-regular, oversized, and non-UTF-8 files fail closed without being read. The bounded manifest is
  snapshotted with the message so later file edits cannot rewrite prior model history.
- **Mention boundary:** Mention names and paths are bounded single-line metadata. Their path is never
  opened as a file; QuillCode preserves connector identity without claiming the deferred remote app
  runtime is available.
- **Evidence:** Focused tests cover projection, persistence migration, immutable snapshots, duplicate
  selection, disabled/arbitrary paths, control characters, and reference caps. A real app-server
  process sends text, image, skill, and mention items together and verifies exact wire and disk state.

## 2026-07-15: App-server fuzzy search is bounded, cancellable, and connection-scoped

- **Wire contract:** Stable `fuzzyFileSearch` and experimental `fuzzyFileSearch/sessionStart`,
  `sessionUpdate`, and `sessionStop` mirror Codex 0.142.5 field names, result ordering, match indices,
  empty-query behavior, missing-session errors, and updated/completed notifications.
- **Shared traversal:** Search reuses `WorkspaceFileIndexer` rather than adding another filesystem
  crawler. It inherits hidden/build-directory exclusions and deterministic paths, then applies explicit
  root, query, entry, and result caps before projecting the Codex response shape.
- **Concurrency contract:** One-shot requests run outside the session actor so a repeated cancellation
  token can supersede work without blocking input. Live sessions build one index, cancel stale query
  generations, and re-check generation after every notification await. Stop and EOF cancel and drain
  all work, preventing late notifications or detached connection-owned tasks.
- **Evidence:** Focused tests pin Codex's reference scores and indices, case-insensitive matching,
  response shape and ordering, cancellation response completion, query clearing, stop behavior,
  capability gating, and exact errors. The real JSONL process smoke exercises one-shot and live search.

## 2026-07-15: Doctor diagnostics are bounded, read-only, and redacted at every boundary

- **Compatibility contract:** `quill-code doctor` follows the observable Codex 0.142.5 command and
  option surface, including grouped human output, stable JSON, warning-versus-failure status, and a
  nonzero exit only for failures. TrustedRouter `/models` reachability replaces OpenAI-specific checks.
- **Mutation boundary:** Diagnostics inspect paths and decode task files directly; they do not call
  `QuillCodePaths.ensure()`, write migration output, repair config, refresh credentials, or alter task
  state. A missing home is a healthy new-install state.
- **Cost boundary:** Git commands have two-second limits, network reachability has a five-second limit,
  and task inventory stops after 5,000 immediate JSON files while refusing symlinks, special files,
  and files above 8 MiB. `--all` expands already-collected detail; it never expands the scan boundary.
- **Privacy boundary:** Reports name credential/proxy sources rather than values. URL userinfo, query,
  and fragment data are removed; network errors are type/code based and API-key redacted again at the
  collector; MCP command, argument, header, and environment values plus malformed config text and task
  content never enter report models.
- **Evidence:** Focused tests cover parsing, schema, stable ordering, summary/ASCII/list rendering,
  redaction, malformed and legacy config, corrupt/oversized/mismatched/duplicate tasks, scan caps,
  auth/reachability classification, and no-state creation. A real executable smoke uses an authorized
  loopback `/models` server and proves JSON/human output plus before/after state identity.

## 2026-07-15: App-server MCP OAuth is asynchronous and shares durable desktop credentials

- **Wire contract:** `mcpServer/oauth/login` returns a genuine authorization URL before waiting for
  the browser and later emits `mcpServer/oauthLogin/completed`. Optional scopes, timeout, and thread ID
  follow the current Codex contract; duplicate in-flight logins for the same server scope are rejected.
  The `mcpServer/refresh` alias and `config/mcpServer/reload` both refresh cached MCP sessions.
- **Credential contract:** Desktop and app-server transports resolve the same per-server token and
  dynamic-registration records through `MCPRemoteAuthorizationResolver`. Explicit bearer environment
  values or Authorization headers always win. OAuth access and refresh tokens never appear on the
  app-server wire, and a successful login reloads the registry before the completion notification.
- **OAuth transport:** Each remote server receives a stable, URL-bound loopback callback path. A static
  client ID takes precedence; dynamic registrations are reused only when their redirect URI still
  matches. Server HTTP headers reach discovery, registration, and token endpoints without replacing
  request-specific fields such as `Accept` or `Content-Type`.
- **Lifecycle and evidence:** EOF cancels callbacks and suppresses late notifications. Provider response
  bodies are redacted from protocol errors. Focused tests cover response ordering, scopes, timeout
  clamping, thread scope, duplicate rejection, cancellation, failure redaction, persisted auth,
  registration refresh, header precedence, and a real localhost callback/code exchange.

## 2026-07-15: App-server account mutation reuses TrustedRouter OAuth without inventing identity

- **Wire contract:** `account/login/start` supports Codex-compatible `apiKey` and `chatgpt`
  discriminators plus the explicit `trustedRouter` alias. API-key login completes immediately;
  browser login returns a real authorization URL and login ID before asynchronous completion.
  `account/login/cancel` returns exact `canceled`/`notFound` states, `account/logout` clears only the
  managed credential, and completion/update notifications honor client opt-outs.
- **Identity contract:** TrustedRouter browser OAuth ultimately yields a delegated API key, so
  `account/read` and `account/updated` truthfully report `apiKey`/`apikey`. QuillCode does not fabricate
  a ChatGPT email, plan type, quota, or provider account history. Optional TrustedRouter userinfo is
  persisted locally for QuillCode UI only and never returned with the key on the app-server wire.
- **Platform boundary:** One `QuillCodePlatform` loopback callback server owns loopback-only sockets,
  bounded HTTP parsing, cancellation, and one-shot callback capture. App-server OAuth, desktop sign-in,
  and desktop MCP OAuth reuse it; platform socket details remain in the C adapter rather than three
  divergent Swift implementations or app-level conditionals. TrustedRouter account flows bind the
  exact allowlisted `http://localhost:3000/callback` redirect, while MCP OAuth retains its own
  server-registration-compatible candidate ports.
- **Durability and lifecycle:** Credential/config updates are transactional and preserve unrelated TOML
  keys. Cancellation, EOF, and failed exchange cannot persist a late credential or emit duplicate
  completion. Explicit/environment credentials remain externally managed and therefore survive logout.
- **Evidence:** Dedicated lifecycle tests cover success, failure, cancellation ordering, logout,
  external credentials, notification opt-outs, disconnect cleanup, exact TrustedRouter callback
  selection, and secret non-disclosure. Shared listener tests cover exact configured redirects,
  matching/unrelated requests, stalled partial requests, invalid callback URLs, and cancellation. The
  real executable smoke proves login/read/logout ordering without losing the session's MCP
  configuration.

## 2026-07-15: Desktop and app-server share one MCP transport runtime

- **Decision:** `QuillCodeTools` owns the reusable MCP client session, process controller, stdio/HTTP
  launcher, bounded wire-shaped JSON values, and lossless probe/tool/resource result models. The desktop
  launcher keeps project-manifest validation and secret-store OAuth resolution, then delegates concrete
  transport construction to that shared runtime. App-server config uses the same runtime instead of
  spawning a second MCP implementation.
- **App-server contract:** `mcpServerStatus/list`, `config/mcpServer/reload`,
  `mcpServer/tool/call`, and `mcpServer/resource/read` follow the Codex 0.142.5 camel-case JSONL shapes.
  Status preserves exact server names, server info, raw tool schemas/annotations, resources, resource
  templates, and auth status. Tool calls preserve arbitrary arguments, `_meta`, content blocks,
  `structuredContent`, `isError`, and result metadata. OAuth login uses the asynchronous, durable shared
  credential contract documented above.
- **Configuration and scope:** Global `~/.quillcode/config.toml` MCP tables merge with thread-workspace
  `.codex/config.toml` and `.quillcode/config.toml`, in that precedence order, without normalizing server
  names. Stdio servers use direct command/argv, declared and inherited environment, bounded timeouts, and
  optional tool filters. HTTP servers support static/environment headers and environment-backed bearer
  tokens without returning those values on the app-server wire. Thread IDs select persisted project cwd;
  unknown threads fail instead of silently falling back to global config.
- **Lifecycle and cost:** Each app-server connection caches one initialized session per scope/server,
  invalidates it when config changes, terminates all children on reload or EOF, and restarts a lightweight
  session before a later full inventory because MCP initialization is single-use. `toolsAndAuthOnly`
  deliberately skips resource, template, and prompt enumeration; `full` performs the complete bounded
  inventory.
- **Evidence:** Stdio and StreamableHTTP tests cover exact payload preservation, metadata forwarding, and
  lightweight discovery. App-server integration tests cover pagination, dash/underscore name collisions,
  project overrides, tool filters, thread errors, reload, and teardown. The shipped-binary smoke launches
  a real Content-Length-framed MCP child, discovers it, calls a tool, reads a resource, reloads it, and
  verifies lightweight rediscovery.

## 2026-07-15: Local plugin detail reads stay lazy and data-only

- **Decision:** Codex-compatible `plugin/read` accepts exactly one local or remote marketplace source.
  Local reads project the 0.142.5 `PluginDetail` shape from the shared marketplace entry and a lazy
  package-detail loader. Local `plugin/skill/read` re-resolves the same marketplace/package boundary
  before returning bounded `SKILL.md` content and metadata. Remote reads still return explicit
  invalid-request errors until QuillCode has a genuine remote plugin service.
- **Progressive disclosure:** Detail discovery parses skill frontmatter and optional interface policy,
  but never reads `SKILL.md` bodies into model context. It filters skills to the Codex product, applies
  namespaced persistent enablement, and projects exact hook keys, app metadata, and usable MCP names.
- **Filesystem boundary:** Component manifests must be bounded regular files below a real package root.
  Absolute paths, traversal, symlink roots, nested symlink escapes, oversized files, malformed JSON,
  unsupported handler types, and excessive component counts are excluded without executing package code.
  An explicit invalid component path never falls back to a default component directory.
- **Evidence:** Dedicated loader tests cover default and explicit components, product filters, hook order,
  inline manifests, malformed and oversized data, path traversal, and root/nested symlinks. Protocol tests
  cover the exact local plugin response, local skill-content response, Codex product filtering, and every
  source/error boundary. The shipped-binary stdio smoke performs a real `plugin/read` and verifies the
  explicit remote skill-read error.

## 2026-07-15: App-server plugin discovery reuses the desktop's data-only catalog

- **Decision:** `plugin/list` and `plugin/installed` project local home and repository marketplaces
  through the Codex 0.142.5 response schema. The app-server and desktop now share one bounded catalog
  reader instead of decoding the same marketplace and package manifests independently.
- **Security boundary:** Discovery reads only bounded regular JSON files, rejects symlinked catalogs
  and installed-state directories, accepts explicit `./` local package sources that remain within
  their workspace, and never clones, downloads, or executes plugin code. Invalid marketplaces are
  skipped and returned as per-path load errors without hiding valid marketplaces from other roots.
- **State boundary:** QuillCode package directories and explicit project manifests determine local
  installed/enabled state. `plugin/installed` returns installed entries plus bounded explicit install
  suggestions and ignores orphaned installed state when no catalog advertises it. Local package
  versions and interface asset paths project truthfully from the package manifest.
- **Remote boundary:** Codex marketplace-kind values are accepted, but only `local` has an implemented
  backend. Local plugin detail reads are implemented separately above. Remote catalogs, sharing, featured
  IDs, install/update mutation, private Codex cache/config conventions, and remote detail/skill methods
  remain deferred rather than being synthesized from local data or TrustedRouter state.
- **Evidence:** Shared loader tests cover modern/legacy manifests, interface metadata, path escapes,
  symlinks, byte limits, and partial failure. JSON-RPC tests cover exact response fields, home and
  workspace roots, local versions, installed/suggested filtering, installed-state symlink rejection,
  invalid parameters, and remote-only empty results. The real executable smoke verifies both methods
  over an open stdio process.

## 2026-07-15: App-server config mutation shares one structured TOML document

- **Decision:** `ConfigDocumentStore` is the shared representation for app settings and Codex-compatible
  `config/read`, `config/value/write`, and `config/batchWrite`. It parses real nested TOML instead of
  line matching, preserves unknown tables and values when QuillCode-owned settings are saved, and
  migrates the repeated scalar list keys emitted by early QuillCode builds into valid arrays.
- **Wire fidelity:** Writes accept Codex dotted/quoted paths, `replace` and recursive table `upsert`,
  null deletion, optional user-file paths, and optimistic `expectedVersion` checks. Batches apply to an
  in-memory copy and validate before one atomic save. Legacy profile writes, non-user layers, nested
  nulls, malformed paths, and invalid known value types fail with Codex `config_write_error_code`
  values without partial persistence.
- **Read fidelity:** Effective reads retain unknown user keys, fill only absent runtime defaults, mark
  command-line model overrides as `sessionFlags`, flatten persisted leaves into user origins, and use
  one SHA-256 content version for origins, optional raw user layers, conflict checks, and write results.
  Secret-store credentials never enter this document or response.
- **Formatting tradeoff:** A changed document is emitted as deterministic canonical TOML because the
  Swift encoder does not provide Rust `toml_edit`-style trivia-preserving edits. A no-op write does not
  touch the file and therefore preserves comments and formatting byte-for-byte. Functional values and
  unknown keys survive changed writes, including offset/local date-times, local dates, local times,
  infinities, and NaN; temporal and non-finite values project as canonical strings on the JSON wire.
  Preserving comments around changed
  values remains a documented lower-priority fidelity improvement.
- **Evidence:** Persistence tests cover nested round trips, quoted paths, parent replacement, recursive
  upsert, deletion, all TOML temporal types, special floats, list migration, unknown-key preservation, keyboard
  shortcuts, and legacy loading.
  JSON-RPC tests cover versions/origins/layers, atomic batches, conflict and readonly errors, profile
  rejection, malformed values, no-op bytes, and runtime reload. The real executable smoke performs
  both write methods and verifies the resulting read through an open stdio session.

## 2026-07-15: App-server filesystem authority belongs to the connected client

- **Decision:** Implement the Codex 0.142.5 `fs/readFile`, `fs/writeFile`, `fs/createDirectory`,
  `fs/getMetadata`, `fs/readDirectory`, `fs/remove`, `fs/copy`, `fs/watch`, and `fs/unwatch` wire
  contracts as direct host operations. This surface is not routed through model tool approval because
  the app-server client already holds the process and filesystem authority; model-authored file calls
  continue through QuillCode's workspace and safety gates.
- **Fidelity:** File payloads are base64 and reads stop at 512 MiB. Metadata follows symlink targets
  while separately reporting `isSymlink`. Recursive copy merges existing directories, overwrites
  regular files, preserves relative and absolute symlinks, ignores special children, and rejects a
  standalone special source or a destination that resolves inside its source.
- **Watch lifecycle:** Each stdio session owns its watch IDs. A cross-platform Foundation watcher takes
  its initial snapshot before acknowledging `fs/watch`, polls at 100 ms, invalidates cached resource
  values so atomic replacement is visible, and emits sorted changes after a 200 ms debounce. Unwatch
  awaits task cancellation; EOF cancels every remaining watch and suppresses later notifications.
- **Evidence:** Dedicated protocol tests cover all methods, exact response fields, empty/binary files,
  defaults and failures, symlinks, FIFO handling, immediate/atomic/missing-target changes, duplicate
  IDs, unwatch, and disconnect. The executable smoke performs a binary host-filesystem round trip.

## 2026-07-15: One bounded skill catalog powers live agents and app-server clients

- **Discovery:** QuillCode follows Codex/Open Agent Skills roots: repository `.agents/skills` from the
  active directory through the Git root, user `~/.agents/skills`, admin/system locations, plus legacy
  `.quillcode` and `.codex` roots. Root order is explicit precedence; the catalog keeps duplicate names
  while the name-only live tool resolves the first match.
- **Progressive disclosure:** Discovery parses bounded YAML frontmatter and optional
  `agents/openai.yaml` interface/tool metadata. Full `SKILL.md` instructions enter model context only
  after `host.skill.load`, keeping the base prompt compact.
- **Filesystem boundary:** Repo, user, and admin skill-directory symlinks are supported like Codex,
  but system roots do not follow them. Canonical visited paths, depth/count/byte caps, hidden-directory
  skips, and safe name/icon validation bound traversal. Parent traversal derives normalized filesystem
  paths so a non-Git workspace stops at `/` instead of walking indefinitely through `/..`.
- **Protocol:** `skills/list` uses the shared catalog, caches by canonical working directory, supports
  explicit `forceReload`, and reports invalid working directories as per-entry errors. Bounded absolute
  `skills/extraRoots/set` roots are session-local, clear the cache, and emit `skills/changed`.
- **Configuration:** `skills/config/write` accepts exactly one bounded absolute manifest path or
  bounded skill name. Disabled selectors persist in the ordinary config store, survive older config
  payloads, and are enforced by desktop, CLI, and app-server metadata. A disabled higher-precedence
  path can fall through to an enabled skill of the same name in a later root; a name selector disables
  every matching root.
- **Change lifecycle:** After `skills/list`, one session-owned Foundation task recursively snapshots
  all deduplicated roots, including missing roots, under catalog-equivalent depth/directory bounds and
  a hard entry cap. It fingerprints bounded manifests/metadata, follows only allowed directory links,
  debounces edits, clears every CWD cache, emits invalidation-only `skills/changed`, and is cancelled on
  EOF. This keeps clients current without creating one task per root or leaking work after disconnect.
- **Evidence:** Core normalization, config round trips, resolver precedence, live desktop/CLI runner
  enforcement, app-server validation/persistence, missing-root creation, manifest edits, cache refresh,
  and disconnect cleanup have focused tests. The real-process smoke disables, re-enables, edits, and
  reloads a skill through the public wire surface.
- **Why:** A separate RPC scanner and live-agent resolver would drift in roots, metadata validation,
  and precedence. One catalog gives desktop, CLI, and app-server clients the same truthful skill set.

## 2026-07-14: Record & Replay is an explicit-consent Computer Use workflow

- **Decision:** QuillCode implements Codex-style Record & Replay on macOS as two structured tools, `host.workflow.record.start` and `host.workflow.record.stop`. **Record a skill** drafts a normal composer request; the agent starts recording immediately after the user submits and approves it, and Stop ends capture before any model analysis begins.
- **Consent boundary:** Starting cross-app recording always requires one explicit user confirmation in Review and Auto modes. The confirmation discloses that screenshots and typed text are sent to TrustedRouter to create the skill and that password fields are redacted. A reviewer-model approval and a persisted permission-rule allow cannot bypass it. Stopping is always available without a second review, including after Computer Use permissions are revoked, so QuillCode cannot strand an active recording.
- **Capture boundary:** Recording is owned by its originating task and project. It is bounded to 30 minutes, 240 events, and 12 snapshots. App switches, pointer actions, scrolls, and bounded text/special-key activity are recorded; protected Accessibility fields retain only a character count. Screenshots are privately stored with owner-only directory/file permissions and are resized to a 1440 px longest edge. Model context receives a first-to-final representative subset rather than only the earliest screenshots.
- **Lifecycle:** Event monitors reject queued events as soon as stop begins. Start installation is generation-bound, so concurrent cancel invalidates monitors created by an obsolete startup. Reaching 30 minutes invalidates monitors, preserves an explicit limit-reached state, and keeps Stop available to finish the captured skill. Stop All and Disconnect All also cancel recording. A stopped capture returns to its originating task even when another task is selected. The structured capture enters model context as a hidden tool message, while only concise progress and completion copy appears in the visible transcript.
- **Skill creation:** After stop, the ordinary TrustedRouter agent continuation must create exactly one `.quillcode/skills/<slug>/SKILL.md` through normal audited file tools. The skill includes purpose, variable inputs, generalized steps, and verification; captured secrets and literal one-off values must not be copied into the reusable workflow.
- **Presentation:** Extensions and the command palette expose Record/Stop. Active recording uses one restrained red status indicator and a direct Stop action. The macOS menu-bar widget also exposes Stop so the user does not have to return to the originating window before ending capture.
- **Why:** Recording is useful only when it is immediate, legible, stoppable, and safe to demonstrate across apps. Keeping consent, capture, model analysis, and file mutation as separate typed boundaries makes that behavior testable and prevents reviewer heuristics from silently broadening surveillance.

## 2026-07-14: Keyboard shortcuts are one configurable command profile

- **Decision:** `WorkspaceShortcutRegistry` is the source of truth for Codex-compatible defaults and QuillCode-specific additions. The workspace surface, command palette, Settings editor, native menus, and deterministic browser harness consume that same command identity and binding model.
- **Customization:** User overrides persist in `AppConfig` as normalized command/key/modifier values. The editor supports Action and Keystroke search, conflict feedback, per-command reset, and Reset all. Unsupported keys and unmodified typing keys are rejected at the core configuration boundary, including hand-edited config.
- **Conflict recovery:** A valid set of simultaneous overrides can swap bindings. If hand-edited overrides still collide, only conflicting customizations fall back to known defaults; the active profile never ships duplicate command bindings.
- **Native routing:** SwiftUI menus own each command's primary binding, preserving standard macOS discoverability and reserved-key behavior. A narrow AppKit monitor handles secondary aliases only. All activations post one command notification and return to the existing command planner/model route.
- **Behavior:** Quick Chat opens an ephemeral side conversation when a parent user turn exists and otherwise creates a normal chat. Previous/Next Chat wraps predictably and starts at the nearest edge when no chat is selected. Review, text-scale, terminal, sidebar, search, and dictation shortcuts use their existing workspace actions instead of view-local mutations.
- **Why:** Parallel menu, monitor, palette, and view shortcut tables drift quickly and can steal text-entry keys. A validated profile keeps customization safe, testable, platform-native, and behaviorally identical across visible entry points.

## 2026-07-13: Agent imports are additive, reviewable, and destination-scoped

- **Decision:** Import from another agent is a Settings workflow with a discovery phase, editable project/item selection, and an outcome phase. Discovery is read-only; import starts only after explicit review. The first source adapter is Claude Code and covers local projects, recent chats, instructions, settings, skills, plugins, MCP servers, hooks, slash commands, and subagents.
- **Mutation boundary:** Existing project files are never overwritten. Imported instructions, settings snapshots, and extension packages receive unique QuillCode-owned destinations. The mutation records only artifacts created by that import. Projects, chats, created artifacts, and the destination-scoped receipt commit as one workspace transaction; a project, thread, or receipt failure restores the prior stores and removes only those newly-created artifacts.
- **Identity:** Receipts bind a source candidate fingerprint to its destination project. This prevents repeat imports without incorrectly treating global setup as complete for projects discovered later. Imported chats additionally retain source/session provenance so an existing transcript is not duplicated.
- **Security:** Discovery and copying revalidate regular-file, root-containment, symlink, file-count, and byte-count limits. Dependency trees and credential-like files are excluded. Settings, hook payloads, MCP arguments, URLs, and environment declarations are sanitized; credentials are never copied. Imported hooks require trust and MCP servers require credential reconnection before use.
- **Context:** Imported instructions are written beneath `.quillcode/rules/` and enter the same bounded broad-to-specific local and SSH Remote instruction loader as native QuillCode rules. Import does not create a parallel instruction runtime.
- **Presentation:** The native dialog and deterministic Playwright harness share loading, review, importing, result, cancellation, selection, previously-imported, and follow-up states. Counts use tabular presentation, controls keep full hit targets, and cancellation invalidates delayed asynchronous discovery.
- **Why:** Migration should reduce switching cost without turning another agent's mutable configuration into trusted executable state or making a partially understood bulk copy impossible to audit.

## 2026-07-12

- Permission wildcard `**/` is compiled as a two-state complete-segment NFA fragment, while bare `**` keeps its cross-separator self-loop. Only the directory-boundary state may epsilon-skip the fragment. A direct epsilon edge around the slash would also be reachable after consuming a partial segment and could broaden an allow rule, so the matcher is regression-checked against an independent recursive oracle over a generated corpus.
- Managed Worktree tasks are transactional detached checkouts, not implicit feature branches. The materializer snapshots staged and unstaged patches plus frozen bounded local-file content before `git worktree add --detach`, then rolls the registered worktree back on any apply/copy failure. `.worktreeinclude` is evaluated as a gitignore-style selector but candidates must also be normally ignored; ignored `AGENTS.override.md` is included automatically. Untracked nonignored files transfer as current work, source symlinks are skipped, existing destinations are never overwritten, and explicit branch-creating worktrees remain a separate permanent workflow. This gives future Local/Worktree Handoff, cleanup snapshots, and restoration one deterministic materialization boundary.

## 2026-07-05

- Project sidebar reordering stays recency-rank based until the sidebar owns a first-class manual ordering field.
  The project surface is sorted by `lastOpenedAt`, so adjacent Move up/down actions must not merely shuffle the
  backing array. `WorkspaceProjectEngine.moveProject` swaps the visible sorted rows and rewrites bounded recency
  timestamps for the affected visible order, keeping persisted project ordering deterministic while preserving the
  existing recency-sorted storage contract.
- Live work, Activity, notification approval copy, transcript export/search labels, and tool-card chrome should speak in user-facing action names instead of internal tool identifiers. Persisted
  cards and HTML metadata still preserve exact `host.*` names, but visible status copy is scan-first text such as
  `Running Shell command`, `Review Shell command`, and focused details like `Shell command: swift test`. The display
  names live in one shared app presentation helper so future Codex-style surfaces do not each reinvent their own raw-tool
  name mapping.
- Visible browser agent actions are routed through a desktop executor, not the desktop controller or the app model.
  `QuillCodeDesktopVisibleBrowserToolExecutor` owns the `host.browser.inspect`, `host.browser.click`,
  `host.browser.type`, and `host.browser.script` override path for the open WebKit session, while the controller only
  installs the override and the browser coordinator owns session lifecycle. This keeps selector/source parsing,
  structured browser action/script output, and no-open-session errors close to the platform adapter without leaking
  WebKit or JavaScript into app-level code.
- Auto safety reviewer calibration starts with deterministic fixture coverage before live transcript scoring. The
  fixtures run through the real `AutoSafetyReviewer` model path and pin representative reviewer decisions for bounded
  diagnostics, missing shell arguments, unrelated chained credential reads, and project-local file creation. Live
  reviewer-model transcript calibration can build on this table instead of relying on ad hoc manual prompts.
- Redacted live reviewer calibration uses a manifest contract, not raw transcript dumps.
  `scripts/safety-reviewer-calibration-smoke.sh` validates expected-versus-actual approve/clarify/deny
  outcomes, reviewer route/model attribution, and bounded rationale summaries while rejecting raw prompts,
  raw arguments, responses, cookies, auth headers, and API keys. This gives production calibration an
  auditable artifact without leaking hidden prompts or sensitive command payloads.
- Recurring safety calibration is a rollup over validated manifests, not a second raw evidence format.
  `scripts/safety-reviewer-calibration-rollup.sh` accepts only `safetyReviewerCalibrationValidated`
  manifests, rejects duplicate case identities across runs, and summarizes verdict, source, and reviewer
  model coverage as both JSON and Markdown. This lets production calibration evidence accumulate over
  time while keeping raw prompts, arguments, responses, and secrets outside the repo.
- The Auto safety model prompt is a compact contract over the same static safety floor, not a second broad policy
  system. It now names explicit approve/clarify/deny boundaries: approve bounded user-requested work, clarify missing
  or empty arguments and ambiguous targets, and deny credential exfiltration, unrelated extra shell actions, broad
  destruction, persistent security weakening, and irreversible disk/account changes. This keeps cheap reviewer models
  from over-blocking normal coding work while preserving the product rule that the tool call must match the user's
  latest request.
- Auto safety reviewer parsing accepts only raw JSON or a whole-response fenced `json` block. Some cheap reviewer
  models wrap otherwise valid strict JSON in Markdown fences despite the prompt, and treating that as malformed makes
  Auto fall back to the static floor unnecessarily. The parser still rejects prose-wrapped JSON instead of scraping
  arbitrary text because safety decisions should be deterministic and easy to audit.
- Download manifests should identify platform-specific metadata assets with the same platform/architecture semantics as
  executable assets. `BUILD_INFO.txt` is emitted by the macOS packager and is therefore classified as macOS metadata,
  while `BUILD_INFO-linux-<arch>.txt` is Linux metadata for that architecture. This keeps support scripts, website
  download cards, and future updater experiments from treating build-info files as generic blobs.
- Auto safety should approve common read-only diagnostics by command shape, not by broad shell trust.
  `StaticSafetyReadOnlyShellPolicy` now recognizes single-command requests for identity, date/time, hostname,
  OS/kernel, uptime, process listing, memory, and disk usage when the latest user request asks for that class of
  information. The matcher still rejects shell composition (`;`, `&&`, pipes, redirects, substitutions), environment
  dumps, and unsafe paths so Codex-like "show me the system state" questions run immediately without making vague
  diagnostic wording an arbitrary shell approval.
- Merge-train merges use GitHub Actions' `GITHUB_TOKEN`, so GitHub does not enqueue normal push-triggered
  workflows afterward. The train therefore dispatches both `ci.yml` and `download-builds.yml` explicitly after a
  successful merge. This keeps `main` validated and refreshes `tester-latest` without requiring a maintainer to
  remember a manual tester-build run after agent PRs land.
- Download-build runs serialize instead of canceling an in-progress run. A delayed scheduled run can otherwise arrive
  after both platform packages finish and cancel the publisher while it is fetching the repository, leaving valid
  artifacts without an updated `tester-latest` release. Serial execution favors a complete release over a newer run
  preempting the final publication step.
- Tool-card image previews read only bounded local file headers for dimensions. `ToolArtifactImageMetadataReader`
  handles PNG, GIF, and JPEG width/height from the first 64 KiB and refuses URLs/non-file artifacts. The preview
  builders surface a plain `dimensionsLabel`, keeping SwiftUI/HTML renderers filesystem-free and avoiding a general
  image-decoding dependency while making Computer Use screenshots and generated local images easier to inspect.
- Office document previews inspect only bounded local ZIP central-directory metadata. `ToolArtifactOfficePreviewBuilder`
  refuses remote URLs, oversized files, zip64/multidisk packages, and large central directories, then renders package
  entry counts plus spreadsheet worksheet and presentation slide counts without decompression, shelling out, or full
  document parsing. Rich embedded page/sheet/slide rendering belongs in a later asynchronous artifact renderer service.
- Project `.quillcode/config.toml` starts as a bounded source-derived configuration layer, not another persisted app-state
  object. `WorkspaceProjectConfigurationLoader` currently lets repositories add local action directories and cap discovered
  local actions while keeping `.quillcode/actions` and `.quillcode/local-env` enabled by default. Unsafe, absolute, parent
  traversing, oversized, or malformed directory entries are ignored independently so one bad project config row cannot hide
  later safe actions. The loaded configuration is consumed only by `WorkspaceProjectMetadataLoader`, keeping `ProjectRef`
  persistence stable and avoiding another project metadata fork.

## 2026-07-04

- Native desktop smoke should prove the browser feature through a deterministic local HTML page before broader live-site
  automation. The smoke now opens `browser-smoke.html` through the same browser pane controls users see, adds a browser
  comment, sends a composer prompt that must dispatch `host.browser.inspect`, and records a `browserSmoke` JSON block
  with title, source label, inspection depth, outline, text snippet, comment count, tool name, and final answer. This
  avoids network flake while proving the release artifact can inspect a real page through the agent/tool/transcript path.
- Tester distribution uses one moving GitHub prerelease, `tester-latest`, plus normal version tags. The **Download
  Builds** workflow publishes macOS app, macOS CLI, and Linux CLI archives as short-retention workflow artifacts and
  refreshes the stable tester release after successful `main` builds so early testers can use one download URL while
  maintainers can still cut immutable `v*` releases for public announcements. The macOS tester app is ad-hoc signed
  and explicitly not notarized until Apple signing/notarization credentials are configured.
- Tester releases also publish `latest-tester-build.json` as a machine-readable download manifest. The manifest records
  channel, tag, commit, workflow run, version/build metadata, and per-asset URL/size/platform/arch/SHA-256 fields so the
  website, support scripts, and in-app updater consume the same stable tester channel without scraping GitHub release
  HTML.
- QuillCode keeps TrustedRouter model-advisor guidance as a compact skill-backed pointer in the base prompt instead of
  carrying the full Lore-Hex/LLM-advisor playbook on every request. The prompt names the live-data-first behavior,
  concise 2-5 option recommendations, key privacy filters, and secret-handling guardrails; detailed model-selection
  knowledge belongs in on-demand skills/docs loaded through the skill harness. `docs/SKILL_HARNESS.md` now documents the
  broader pattern: index skill names/descriptions cheaply, load `SKILL.md` only when invoked or clearly relevant, then
  read referenced workflow files only as needed.
- The top bar's usage chip is cost-aware without becoming a billing dashboard. Threads with priced provider usage show a
  compact spend/fuse chip such as `Spend $0.0050 / $1.00`, with token usage and unpriced-call detail in the tooltip; if
  model pricing is unavailable, the top bar keeps showing the raw token-usage chip. This keeps Codex-like chrome clear
  while avoiding fake precision when the model catalog lacks prices.
- Day/week/month spend rows are local QuillCode caps until TrustedRouter exposes account-history or quota APIs. Optional
  `run_spend_daily_limit_usd`, `run_spend_weekly_limit_usd`, and `run_spend_monthly_limit_usd` config keys render
  `$spent / $cap` in the existing token-budget popover even at zero spend, while uncapped periods continue to appear only
  after priced model receipts exist. Provider quota rows still come only from provider errors, not guesses. Period caps
  also enforce through the same Spend Review pause as the thread fuse: the app passes a start-of-run workspace thread
  snapshot into the runner, the runner replaces the active thread with live progress while evaluating caps, and approval
  payloads include a limit kind so daily/weekly/monthly approvals cannot satisfy thread-fuse buckets. The card title,
  decision rationale, and stop notice all decode that same payload kind so the transcript says which cap is being
  continued or stopped.
- Model discovery should remain useful even when TrustedRouter's authenticated `/v1/models` endpoint is unavailable or
  the user has not signed in yet. `TrustedRouterModelCatalogClient` now falls back to the public TrustedRouter model
  catalog page, preserving the branded Recommended defaults while adding provider rows such as MiniMax to picker search.
  The desktop runtime also reads `~/.quill.code.keyfile` and explicit key-file environment variables for local smoke
  testing, so a developer can chat live and refresh the model catalog without re-entering credentials in Settings.
- Linux rendered-browser capture should use a browser-process adapter before a full Linux visible browser session. The
  desktop target now keeps WebKit as the macOS default while mapping `DesktopBrowserLiveDOMCapturer` to a testable
  `ChromiumBrowserLiveDOMCapturer` on Linux. The Chromium adapter finds Chromium/Chrome-compatible executables on
  `PATH`, runs a bounded headless `--dump-dom` capture with an isolated temporary profile, and converts the dumped
  rendered HTML into the existing `BrowserLiveDOMSnapshot` contract. If no browser exists, it returns the existing
  `noRenderedSession` failure so the browser pane falls back to static metadata instead of pretending live capture ran.

## 2026-07-02

- Context summary progress is derived from thread notices instead of stored as a separate workspace flag.
  Compact and fork-summary already append source-thread start/finish notices, so `ContextBannerSurface` reads the
  latest matching notice to show a running strip and disable competing context-move actions. This keeps the visible
  "clicked and work is happening" state replayable from persisted thread history and avoids a second cleanup path when
  the continuation thread is inserted.
- Nested instruction diagnostics should distinguish normal scope layering from real cleanup work. A nested `AGENTS.md`,
  `.quillcode/rules.md`, or `.quillcode/instructions.md` that only adds scoped guidance is no longer flagged just
  because broader instructions exist; Codex-style nested rule files are expected. Activity now flags a nested overlap
  only when a meaningful line repeats broad guidance already supplied by an applicable broader file, and that case gets
  a direct `Remove repeated lines...` action that runs through audited `host.apply_patch` against the nested file while
  preserving the broader source. Explicit nested override diagnostics now point at the exact override lines and may offer
  `Remove override lines...` when the loaded excerpts still match; richer rewrite/merge proposals stay manual because
  changing the underlying guidance would guess at user intent.

## 2026-07-01


- Browser domain policy is a persisted runtime policy, not a renderer-only guard. `AppConfig` stores normalized allowed
  and blocked domain lists, and `WorkspaceBrowserWorkflow` applies them after URL resolution and before manual opens,
  model-authored `host.browser.open`, snapshot fetches, live-DOM capture, redirect final URLs, and visible browser-session
  updates. Blocked domains win over allowed domains and match subdomains; local file previews remain governed by the
  existing workspace/file resolver rather than domain matching. This keeps Codex-style browser safety and developer
  workflow control in one reusable policy seam.
- Computer Use approval management belongs in Settings as an editable draft over the same `AppConfig` keys that the
  executor enforces. Empty bundle/app-name lists remain the explicit unrestricted policy; non-empty lists form the
  foreground-app allowlist. The settings sheet keeps the approval UI in `QuillCodeComputerUseApprovalSettingsCard`,
  while `WorkspaceSettingsSurface`, `QuillCodeSettingsDraft`, and `WorkspaceSettingsUpdate` carry normalized values
  through the existing save path. This prevents a UI-only approval state from drifting away from agent execution.
- Workspace history uses `Cmd+Option+←` and `Cmd+Option+→`, leaving `Cmd+[` and `Cmd+]` for browser-tab history.
  The shortcut registry remains the single source for SwiftUI menus, command-palette labels, Keyboard Shortcuts, and the
  rendered Playwright harness, and the harness normalizes arrow glyphs back to keyboard event names so shortcut dispatch
  is tested through the same user-facing labels.
- Native `NavigationLink` controls are in-app press targets, not external links. Source audits now reject
  `NavigationLink` without a shared QuillCode hit-target helper, reject `quillCodeLinkTarget` on in-app navigation,
  and require explicit press/action styling. Future Codex-style navigation rows should use row/text/capsule/form press
  semantics so they keep 44 pt geometry, tactile feedback, and unambiguous action ownership.
- GitHub pull request lifecycle belongs in the structured PR tool family, not in ad hoc shell recipes. `host.git.pr.lifecycle` accepts a validated `action` of `close` or `reopen`, shares the same selector validation as other PR tools, runs through local or SSH Remote `gh pr close|reopen`, and is exposed through slash commands plus the command palette. The agent argument normalizer treats lifecycle as selector/action-only, not a body-bearing PR comment/review tool.
- Instruction diagnostic apply actions must stay deterministic. Semantic conflicts may remove the opposite known line only
  when source excerpts still match, duplicate-scope diagnostics may clear a selected source only when another same-scope
  instruction file has identical normalized content, nested-overlap diagnostics may remove repeated broad lines from
  the nested source only when the loaded line still matches, and explicit nested-override diagnostics may remove exact
  override-language lines when the loaded excerpts still match. Non-identical duplicate-scope merges and semantic
  rewrites of nested overrides remain manual Resolve/Edit workflows because merging those files would guess at user intent.
- Generated Python bytecode must not be tracked. Native click-probe validator caches are now ignored with
  `__pycache__/` and `*.py[cod]`, so grade generation and smoke validation cannot rewrite binary artifacts in normal
  development.
- Slash parser parity gates should be split by command domain. Repository/project/remote parsers, terminal/mode/model parsers, thread/memory parsers, and workspace/environment/scheduling parsers now live in separate focused gates instead of one broad parser ownership file.
- Top-bar parity gates should be split by presentation, native chrome, and surface/model-catalog ownership. `ParityTopBarPresentationGateTests.swift` owns status/runtime copy semantics, `ParityNativeTopBarChromeGateTests.swift` owns native chrome and picker composition, and `ParityTopBarSurfaceGateTests.swift` owns top-bar DTO/model-catalog construction and focused integration-test placement.
- Browser parity gates should be grouped by browser architecture boundary. Browser state/surface ownership, snapshot extraction, visible-session sync, workflow/location routing, browser tool/rendering ownership, broad-suite exclusion, and Playwright flow placement now live in focused parity classes instead of one mixed `ParityBrowserGateTests.swift` file.
- Settings/source-inspection parity gates should separate sheet ownership, settings draft/view ownership, native hit-target contracts, search/palette typing state, settings surface records, and Playwright settings/runtime evidence. `ParityWorkspaceSettingsSheetGateTests.swift` now keeps only workspace sheet presentation and settings view/draft delegation, while focused parity files own compact hit targets, primary chrome hit targets, search dialogs, settings surface records, and Playwright settings/runtime flow placement.
- Browser source-inspection parity should stay split by browser boundary once those boundaries are established.
  `ParityBrowserGateTests.swift` keeps the core browser surface and broad-suite exclusions, while snapshot extraction,
  visible-session sync, workflow routing, and browser tool/rendering checks live in focused files. The focused-suite
  manifest names each split file explicitly so the registry cannot drift back toward one mixed browser gate.
- Desktop source-inspection parity gates should be organized by desktop ownership boundary. Menu-bar widget contracts, packaged macOS live-window smoke proof, TrustedRouter loopback OAuth, cancellable task coordination, desktop WebKit/browser adapters, and desktop controller routing now live in separate parity gate classes instead of a single broad `ParityDesktopGateTests.swift` file. This keeps Codex-style desktop parity checks reviewable without weakening the contracts.
- Broad source-inspection parity gates should be split by ownership boundary before adding more assertions. `ParityToolGateTests.swift` now keeps only core argument and slash catalog contracts; remote project tools, git/GitHub PR tools, shell/file tools, and workspace context banner contracts live in focused test classes. Source contains/excludes checks should use `QuillCodeParityTestCase.assertSource` so failure messages stay consistent without hundreds of long one-off XCTest lines.
- Live TrustedRouter smoke should keep `scripts/live-tr-smoke.sh` as the public command and visible scenario matrix, while moving reusable runtime, artifact, assertion, and transcript helpers under `scripts/live_tr_smoke/`. This keeps release-critical prompts easy to review in one place, avoids a data-table DSL for now, and lets parity tests inspect the whole suite through `liveTrustedRouterSmokeText()` so secret handling, transcript integrity checks, and negative-action guards remain covered after the split. Negative-action validators must check both forbidden output text and forbidden workspace side effects so a model cannot pass by silently creating a file.
- Packaged live Accessibility evidence must prove selected controls activate, not only that their frames are large and hit-testable. `QuillCodeDesktopAccessibilityTree` owns AX traversal, hit-testing, AXPress, focused-state reads, and reversible AXValue text entry so frame and interaction sampling share one implementation. Typed activation contracts now cover the safe always-visible command set (`Search`, `Settings`, `Automations`, and `Extensions`), verify controller-visible state changes, restore every changed state, and let Search additionally prove that its field becomes focused, accepts text, and clears again. The packaged `frames` validator requires this evidence in `accessibilityActivation` and preserves it in `packaged-accessibility-frames.json`, so release artifacts catch controls that look clickable but do not actually fire or accept typing.
- Native click-probe validation should keep the public script path stable while splitting implementation by release artifact boundary. `scripts/native-click-probe-contracts.py` is now only the executable facade used by smoke scripts; `scripts/native_click_probe_contracts/` owns constants, JSON/value helpers, click-probe normalization, packaged-window comparison/readiness manifests, live Accessibility frame validation, and CLI wiring. Parity tests read the full validator package instead of the facade, so release contract checks still fail if selector precedence, sample coordinates, policy drift, window command coverage, or live frame evidence regresses.
- Native text-entry click targets must be addressable by Accessibility ID, not only by internal focus state. The source hit-target gate now rejects raw `TextField`, `SecureField`, and `TextEditor` controls unless the owning control scope declares `.accessibilityIdentifier(...)` beside the `quillCodeTextEntryTarget()`. Reusable dialog text fields synthesize deterministic `quillcode-...-field` identifiers, while specialized settings, transcript-find, browser, terminal, and review/PR fields use explicit IDs. This closes the "field looks right but cannot be clicked or typed into by smoke automation" gap without weakening the existing 44 pt/focus-target contracts.
- Instruction Review dismissals and resolved-by-edit audit records are project-scoped diagnostic records, not only pane UI state. `ProjectRef` owns normalized `ProjectInstructionDiagnosticResolution` records with `dismissed` and `resolved` dispositions, metadata refresh preserves them, and Activity combines durable dismissals with transient session dismissals before rendering diagnostics. A diagnostic that disappears after a context refresh is recorded as `resolved`; that is audit history only and never suppresses a future reintroduced diagnostic with the same ID. Only `dismissed` hides currently active diagnostics. The dismiss command only accepts currently known instruction diagnostics, so stale or fabricated command IDs cannot hide nonexistent rule issues. Resolve remains an explicit draft/edit workflow for broad, remote, stale, or ambiguous diagnostics. Exact two-reference semantic conflicts may also expose `Keep ...` quick fixes, but those must still run through audited `host.apply_patch`, verify the current file/line/excerpt, refresh metadata, and fall back to Resolve if any safety check fails.

## 2026-06-30

- Agent runner files must preserve the command-execution ownership split. `Agent.swift` is the orchestration root only: it records the user turn, loops bounded tool steps, emits final answers, and handles cancellation. `AgentTypes.swift` owns the stable public API, `AgentActionResolver.swift` owns immediate/streaming/non-streaming action selection, `AgentTextStreamActionRunner.swift` and `AgentUsageStreamActionRunner.swift` own streaming setup, the focused stream collectors and `AgentStreamingDraftPublisher.swift` own progress mutation, and `AgentPromisedWorkResolver.swift` owns the bounded recovery path for assistant text that promises action without returning a tool call. This keeps the high-risk "run this now" behavior modular, test-gated, and resistant to regressions where the model says "I'll do it" or emits an empty shell action.
- Native click-target contracts must include feel policy, not only geometry and ownership. `QuillCodeNativeHitTargetKind` now derives whether a target requires tactile press feedback and whether text selection is allowed, then carries those fields through design-system specs, native surface contracts, click probes, packaged smoke manifests, and live Accessibility frame samples. Text entry is the only selectable/non-tactile target class; buttons, links, owned gestures, segmented controls, sliders/steppers, rows, capsules, and form actions must remain non-selecting and tactile. This keeps "click targets everywhere" reviewable across SwiftUI, rendered harness, CI smoke, packaged artifacts, and future AX clicking.
- Rendered click targets must be tactile by semantic action, not by element type. The shared harness CSS now applies touch-action manipulation, no accidental text selection, transform transitions, and 0.96 press feedback to explicit `data-hit-target-action` values (`press`, `link`, `owned-gesture`, `adjust`) instead of depending on `button`/`summary` selectors plus screen-local overrides. The Playwright interaction audit rejects visible clickable targets that are large and named but missing this tactile contract, so "click targets everywhere" covers feel as well as geometry, semantics, routing, and non-overlap.
- Primary workspace panes need registry-backed shortcuts and typed desktop routes, not palette-only discovery. Terminal, Browser, Activity, Automations, Memories, and Extensions now all carry `WorkspaceShortcutRegistry` bindings, show those labels in the command palette and Keyboard Shortcuts sheet, and route through typed desktop pane actions where the native menu owns the event. This keeps Codex-style navigation keyboard-first while preserving one command ID per visible action.
- Rendered click-target kind must be explicit at production primitive call sites. `WorkspaceHTMLPrimitives` still keeps safe default classes as a backstop, but renderers now pass `hitTargetKind:` for every button, command button, button-attribute block, and details summary so reviewers can see whether a control is an icon, row, text button, text entry, or form action without inferring from CSS. A parity source gate scans balanced multiline primitive calls to keep future renderer work from silently falling back to generic text-button semantics.
- Terminal output rendering should stay a pure single-page screen buffer until QuillCode owns a real emulator model. `TerminalOutputRenderer` now applies common cursor-addressed CSI/DEC controls, bounded scroll regions, reverse-index, explicit scroll up/down, insert/delete line, alternate-screen latest-frame preservation, width-two CJK/emoji/emoji-presentation cell advancement, ZWJ grapheme-cluster preservation, combining-mark cursor accounting, and an explicit narrow-by-default ambiguous-width transcript policy while preserving raw PTY bytes in state and exposing only cleaned display text through `TerminalCommandSurface`. Full curses semantics, attributes, mouse tracking, and locale-specific ambiguous-width switching remain deferred until a dedicated emulator model exists.

## 2026-06-29

- First-run starter actions belong in release real-world evidence, not only core UI tests. The "Review changes" card is the fastest path from a fresh QuillCode window into useful Codex-style behavior, so `real-world-actions.spec.ts` now clicks that card, requires a real user turn, `host.git.diff`, rendered diff output, cleared composer state, and no passive "I'll review" limbo. The Playwright manifest validator and release wrapper now require that scenario, prompt fragment, and guard so release-candidate evidence cannot drop first-run action dispatch silently.
- Automation slash scheduling should handle practical one-off calendar phrases without needing a full cron model. `/follow-up ...` and `/workspace-check ...` now share deterministic parsing for `today at`, `tonight`, bare clock phrases, tomorrow phrases, and upcoming weekdays such as `Friday afternoon` or `next Monday at noon`, then persist the same concrete `nextRunAt` records as quick actions. Interval recurrence remains `hourly`/`daily`/`weekly`/`every N units`; business calendars, monthly rules, and nth-weekday recurrence still need a richer recurrence model instead of being squeezed into the interval-only record.
- Click-target confidence needs near-edge activation coverage, not just minimum geometry. Native click probes now sample the same 8/92% edge midlines that rendered Playwright audits use, and the primary utility E2E flow clicks search, command palette, model row actions, settings actions, worktree choices, and composer send from near-edge points. This keeps "works everywhere" tied to real user aim instead of center-only success.
- Everyday click targets need their own activation coverage because broad geometry audits can still miss normal user paths. The rendered interaction suite now edge-clicks sidebar primary actions, saved filters/searches, sidebar thread menus, project rows/actions, empty starter cards, slash suggestions, transcript feedback/use-as-draft/retry actions, context actions, and runtime recovery buttons. Those checks sit beside the generic hit-target audit so a future button can be large, named, and non-overlapping but still fail if its real near-edge activation path does not work.
- Rendered and native click targets need a peer-clearance contract in addition to size and overlap checks. A pair of independent controls with only a 1-5 px gutter is still ambiguous even when their rectangles do not intersect, so the Playwright interaction audit, native click-probe manifests, and live Accessibility frame validator now require 6 px clearance between adjacent peer targets in the same interaction layer or collision scope. Tight vertical menu/list rows and segmented controls remain explicit exceptions because those surfaces intentionally share edges and have a familiar interaction model.
- Interactive click-target spacing is now a design-system token, not a local numeric choice. Any SwiftUI `HStack`, grid, or similar cluster that contains controls must use `QuillCodeMetrics.controlClusterSpacing` or `QuillCodeMetrics.denseControlClusterSpacing`; passive typography/layout can keep local spacing values. The source gate rejects raw numeric spacing in interactive clusters, which keeps adjacent 44 pt targets from depending on one-off visual tuning and makes "click targets everywhere" reviewable as a native contract.
- Workspace directory listing should be a structured tool, not shell `ls` by default. QuillCode now exposes `host.file.list` for bounded immediate directory entries, with workspace-relative paths, directory/file/symlink kind metadata, file sizes, hidden-file opt-in, artifact links, natural-language immediate action planning, TrustedRouter prompt guidance, deterministic CLI smoke, and Playwright real-world evidence. Explicit requests such as `Run ls` still use `host.shell.run`; natural prompts such as "Can you list the files here?" should use `host.file.list` so normal source browsing stays bounded, parseable, and reviewable.
- Workspace text search should be a structured tool, not shell grep by default. QuillCode now exposes `host.file.search` for bounded literal searches across UTF-8 workspace files, skips dependency/build directories and large/binary files, streams through files with hard caps, and returns file/line/preview matches plus artifacts. Natural prompts such as "Where is AgentRunner defined?" route through the immediate-action preflight, while TrustedRouter is explicitly prompted to prefer `host.file.search` over shell grep unless the user asks for a shell command. Deterministic CLI smoke, Playwright real-world evidence, and opt-in live TrustedRouter smoke now cover this path.
- Provider quota guidance should survive runtime error seams and render near the token budget, not only inside verbose diagnostics. `HTTPRateLimitDetails` now formats a compact parseable summary that `TrustedRouterAgentError` appends to HTTP failures, `WorkspaceRuntimeIssueBuilder` extracts reset/remaining quota diagnostics, and `WorkspaceQuotaLimitSurfaceBuilder` maps rate-limit issues into top-bar `TokenQuotaLimitSurface` rows. The view layer only renders supplied rows; account-history/day/week/month quota APIs remain a future runtime source rather than a guessed UI fixture.
- Packaged live Accessibility samples should prove OS hit-test ownership when the host exposes point hit-testing, not just geometry. Frame size and center/interior coordinates catch tiny controls, but they do not catch a visually correct control whose interior is covered by another AX element. `QuillCodeDesktopAccessibilityFrameSampler` now records live AX hit-test availability, errors, target identifiers, and ancestor identifiers for every sample point; required unblocked targets fail when an available hit-test routes outside the intended control. Availability requires a successful AX point lookup with usable identity because GitHub's macOS runner can report success with no element or an unidentified element. The packaged frame manifest keeps that evidence so release review can distinguish "large enough" from "actually clickable" while still running on CI sessions where macOS frame enumeration works but point hit-testing is unavailable.
- Real-world release smoke must prove natural file-read prompts use the structured `host.file.read` path. Codex-style users frequently ask "What is in README.md?" before editing; relying on a provider to infer that can regress into passive answers or shell `cat` fallbacks. Deterministic CLI smoke now reads a real README fixture, Playwright evidence adds a dedicated file-read scenario with `host.file.read` assertions, the manifest validator raises the prompt/guard floor, and live TrustedRouter smoke reads a freshly written file by natural wording.
- Click-target semantics should be canonical in the native interaction taxonomy, with rendered HTML deriving class names, action names, and kind spellings from that source instead of maintaining a parallel vocabulary. Segmented controls and switch rows are now first-class target kinds (`hit-target-segmented` and `hit-target-switch-row`), while the browser harness fallback only classifies natural controls and toggle labels when markup lacks explicit classes. This makes "click targets everywhere" mean semantic ownership plus consistent minimum target behavior across SwiftUI, static HTML, Playwright, and future packaged Accessibility probes.
- Release smoke should treat future-tense action promises as failures whether the provider says "I'll ..." or "I will ...". Users saw both forms during real device/app testing, and both mean the same product regression when a clear command, file write, download, or diagnostic request should have produced a concrete tool call. Deterministic and live TrustedRouter smoke now share a broader passive-action pattern across stdout and persisted transcript integrity checks so the release lane catches promise-without-action failures instead of depending on one contraction.
- Packaged live-window command IDs must be backed by native click-probe contracts. The window surface already records `commandIDs`, but that alone only proves routing metadata exists. `scripts/native-click-probe-contracts.py window` now derives `command.<id>` contract IDs from every surfaced command and fails when the embedded native hit-target report lacks a matching click probe. The `frames` manifest also records `windowCommandContractCount` and `windowCommandContractIDs`, so release artifacts prove the packaged app's visible command inventory is tied to the same click-target contract that future Accessibility automation will sample.
- Native click targets need collision scopes, not just minimum frame contracts. Rendered Playwright already rejects overlapping peer hit areas in the active layer; native packaged smoke now carries `collisionScope` from each surface contract into click probes and live Accessibility frame samples, then rejects overlapping peer frames within that scope. This makes "click targets everywhere" mean one unambiguous owner per hit region, not a collection of individually large controls that can still collide.
- Native surface click-target policy needs separate required and allowed target sets. Some controls, such as project-header icon actions and transcript thinking-trace capsules, are valid only when that UI state exists; making them globally required creates false failures, but leaving them out lets unreviewed clickable shapes drift in. `QuillCodeNativeSurfaceTargetPolicy` now records required and allowed kinds/actions/focus targets, and the native audit rejects any surface contract that emits an unallowed interaction kind, action, or focus target.
- Packaged live Accessibility frame sampling should be a first-class artifact, not an inline shell assertion hidden inside `window-report.json`. `scripts/native-click-probe-contracts.py frames` now validates the live-window report, screenshot, click-probe manifest, required core/sidebar Accessibility contract IDs, 44 pt frame floor, and exact center/interior sample coordinates before writing `packaged-accessibility-frames.json`. `scripts/packaged-macos-smoke.sh` preserves that manifest next to `packaged-click-probes.json`, `packaged-accessibility-readiness.json`, `window-report.json`, and `window.png`, so release review can distinguish readiness evidence from actual live frame sampling without duplicating JSON checks in shell.
- Packaged live-window semantic checks belong in the shared native smoke validator, not shell string matching. `scripts/native-click-probe-contracts.py window` now validates the packaged `window-report.json` and screenshot together: app/window identity, native click-probe contracts, semantic workspace surface fields, disabled empty composer state, required command IDs, default starter actions, image dimensions/color diversity, and screenshot byte floor. `scripts/packaged-macos-smoke.sh` delegates to that command after producing the live SwiftUI window evidence, so future Accessibility/appshot sampling can reuse one structured contract parser instead of duplicating brittle `grep` assertions.
- Deterministic release smoke should prove read-only git inspection in the same user-facing layers as live smoke. Natural prompts such as `Please check git status.` and `what changed?` now run against a tiny modified git workspace in `scripts/smoke.sh`, publish a `cliGitRead` manifest step, and appear in Playwright real-world action evidence as structured `host.git.status` / `host.git.diff` cards with final chat text. The release wrapper and validator now require six scenarios, fifteen prompts, and eighteen regression guards so browser/CLI evidence cannot silently drop the core Codex-style "what changed?" workflow.
- Release-candidate smoke should validate and surface deterministic Playwright real-world evidence at the wrapper level. `scripts/real-world-smoke.sh` now calls the shared Playwright real-world manifest validator after deterministic smoke passes when Playwright is required, verifies that `deterministic-smoke-manifest.json` promoted `steps.playwright.realWorldActions`, and lifts that summary into `real-world-smoke-manifest.json` under `deterministic.realWorldActions`. This prevents a green top-level release artifact from hiding missing browser coverage for immediate action, diagnostic, download, and negative-intent flows.
- Deterministic smoke should fail closed when Playwright real-world action evidence is incomplete. The Playwright suite already writes `playwright-real-world-actions-manifest.json`; `scripts/smoke.sh` now validates that manifest after browser E2E runs, checks the scenario/prompt/regression-guard floor for immediate shell, file-write, diagnostic, download, and negative-intent flows, and embeds the manifest summary under `steps.playwright.realWorldActions` in `deterministic-smoke-manifest.json`. This keeps release artifacts self-auditing instead of forcing reviewers to infer whether browser smoke actually covered the user-facing "do it now" regressions.
- Playwright real-world action smoke should leave release evidence, not only pass/fail browser assertions. `real-world-actions.spec.ts` now publishes `playwright-real-world-actions-manifest.json` when `QUILLCODE_PLAYWRIGHT_REAL_WORLD_ARTIFACT_DIR` is set, summarizing scenario names, prompts, expected tool families, and regression guards for empty shell arguments, passive promises, missing artifacts, blocked clear intent, and negative-intent side effects. `scripts/smoke.sh` wires that artifact directory under deterministic smoke output so release-candidate artifacts show the UI-layer real-world coverage alongside CLI, native desktop, packaged macOS, and live TrustedRouter evidence.
- Native hit-target helpers must fail closed at the design-system boundary. Every semantic target factory now clamps supplied width and height values to the 44 pt floor, including icon targets and callers that pass `nil` for flexible row/link/capsule widths. The Swift source audit also requires visible `Button` and `Menu` controls to pair their hit-target helper with `QuillCodePressableButtonStyle` or `QuillCodeActionButtonStyle`, while explicit platform-owned menu rows stay documented with `quillCodePlatformMenuItemTarget`. This makes click-target review about semantic intent plus actual press behavior, not caller discipline.
- Packaged live-window smoke now samples real macOS Accessibility frames for core native click targets. `QuillCodeDesktopAccessibilityFrameSampler` resolves the running app through `AXUIElementCreateApplication`, matches the native click-probe contract to live identifiers/command targets, validates the 44 pt floor and normalized sample points, and writes `accessibilityFrameSamples` into `window-report.json`. The mode picker keeps its identifier on the full capsule label so AX sees the intended 44 pt target instead of a tiny text or chevron child.
- Primary sidebar actions are part of the packaged live-frame gate, not optional evidence. The Accessibility sampler now requires New Chat, Search, Plugins, Automations, and Settings command frames because those first-run controls are always visible and must fail CI if their hit targets disappear, shrink, or lose stable identifiers.
- Reduced-motion behavior belongs in one shared rendered harness contract. The HTML harness already models the native surface for Playwright, so it now has a single `prefers-reduced-motion` block near the final interaction styles that disables the thinking-dot animation, shortens transitions to 1ms, and suppresses hover/press transforms for the shared hit-target primitives. A Playwright test holds the Send button in `:active` under reduced motion and verifies both the missing scale transform and stopped thinking animation, while a Swift parity gate rejects split screen-local media blocks or one-off press scales such as `0.97`.
- Live smoke should prove explicit negative action intent without weakening positive transcript integrity. Positive live TrustedRouter scenarios still must persist nonempty queued tool calls and successful completed results. Negative live scenarios such as `Do not run`, `Do not write`, and `Don't download` are now their own no-tool lane: they must produce an assistant response, must not create forbidden output/files, and their persisted transcripts must contain zero queued tool calls. This keeps model-provider regressions visible in release smoke without depending on exact refusal wording.
- Native OS notification observation is a separate release-evidence contract from the app notifier boundary. Packaged scheduled-coworker smoke proves QuillCode emitted the task-specific notification report through the desktop notifier path, while `scripts/scheduled-notification-observation-smoke.sh` validates a redacted captured OS-banner/action observation only when a reviewer has real screenshot or Accessibility/Computer Use evidence. The validator requires exact `catalogTaskIDs`, the existing packaged scheduled-coworker manifest, visible task text, visible follow-up action, screenshot evidence, and rejects raw prompts or secrets. The coworker catalog coverage aggregator accepts these manifests beside live SaaS manifests, so scheduling rows cannot be marked covered by notification intent alone or by evidence that is not tied to spreadsheet row IDs.
- Obvious Git branch commands should execute through deterministic preflight before asking the model. Users expect `list git branches`, `switch to branch name`, and `create branch name from ref` to act immediately just like `git status` or `run whoami`; routing these through a shared parser avoids provider-dependent "I'll switch..." responses while preserving the model path for ambiguous Git prose. Live transcript integrity also allows legitimate zero-argument read tools such as branch-list, worktree-list, and browser-inspect instead of treating them as empty-command regressions.
- Real-world smoke should prove explicit negative action intent as well as positive one-turn execution. The immediate-action path exists to make obvious commands fast, but it must never treat `do not run/write/download` as an action request. Deterministic CLI smoke, native desktop controller smoke, and Playwright real-world actions now cover no-tool/no-side-effect cases for shell, file-write, and download wording, with parity gates keeping that release evidence in the focused smoke surfaces.
- Immediate-action preflight must be clause scoped and negation-aware before it bypasses model planning. The preflight path exists to make obvious local actions fast and reliable, but it runs before normal model planning. `AgentActionIntentSegments` now splits user prompts into coarse clauses, ignores clauses with nearby negated action intent such as `do not run`, `don't check`, or `do not write`, and can still execute a later affirmative clause like `run pwd` in `do not run whoami; run pwd`. The deterministic mock client uses the same segment helper, so offline demos do not create noisy denied tool cards for all-negated prompts.
- Packaged live-window smoke must validate semantic workspace state, not only pixels. A nonblank SwiftUI screenshot can still hide broken routing if the underlying workspace surface loses commands, starter actions, or composer/sidebar state, so `--native-window-smoke` now retains its smoke controller and emits a `surface` report with top-bar identity, model/mode/status, composer readiness, sidebar title, command IDs, and starter action IDs. The packaged smoke checks those fields directly while still leaving real selector-to-frame clicking to the future Accessibility/appshot layer.
- Native click probes must carry interior ownership policy, not only selector and geometry. `allowsNestedInteractiveChildren` and `requiresUnblockedInterior` now flow from each surface contract into every emitted click probe, the shared validator rejects policy drift, and packaged manifests preserve the policy summary for reviewers. This makes the future Accessibility/appshot runner able to decide whether interior sample points must stay owned by the target itself or may intentionally land on a nested child control.
- Packaged Accessibility readiness is a separate artifact from click-probe comparison. `packaged-click-probes.json` answers whether direct executable and Launch Services launch paths emit the same native probe plan; `packaged-accessibility-readiness.json` answers whether the packaged smoke artifact root contains the direct/Launch reports, stable contract IDs, required center/interior sample points, and 44 pt target floor that a live Accessibility/appshot runner can consume next. The readiness manifest is relocatable (`artifactRoot: "."`) and deliberately records `liveAccessibilitySampling: "not-run"` so release evidence is honest until the packaged window is actually clicked.
- Native click-probe validation should have one implementation. `scripts/native-click-probe-contracts.py` now owns exact sample coordinates, selector precedence, missing/duplicate probe coverage, typed `clickProbeValidationIssues`, and packaged direct-vs-Launch Services comparison. `scripts/native-desktop-smoke.sh` keeps the broader native hit-target family/focus policy checks and calls the validator's `validate` command; `scripts/packaged-macos-smoke.sh` calls the validator's `compare` command and receives the same `packaged-click-probes.json` evidence. This keeps the report-level release gate DRY and gives the future packaged Accessibility frame sampler a single contract parser to reuse.
- Packaged direct executable launch and Launch Services launch must publish the same native click-probe plan before QuillCode can claim packaged UI parity. `scripts/packaged-macos-smoke.sh` now preserves both launch-path reports, compares `nativeHitTargets.clickProbes` by contract ID, selector, semantic kind/action, minimum target size, and normalized sample points, and emits `packaged-click-probes.json` with `launchServicesMatchesDirect`. This is still one layer below live Accessibility frame sampling, but it prevents packaged entrypoint drift from hiding behind two independently passing smoke runs.
- Packaged native click automation needs one explicit probe contract, not test-local click conventions. `QuillCodeNativeHitTargetAudit` emits `clickProbes` with selector type/value, semantic kind/action, required minimum dimensions, and normalized center/interior sample points; native desktop smoke validates both selector drift and the exact sample coordinates. This keeps source, rendered Playwright probes, native smoke, and future packaged Accessibility-frame sampling converged on one target plan.
- Polite bare shell-command requests are high-confidence actions when the command itself is explicit and allow-listed. Users type "Can you run ls?" or "Can you run printf ..." as often as imperative "Run ..."; those should not depend on provider formatting or regress into capability chatter. `AgentShellCommandRecovery` now allows standalone `run`/`execute`/`check` markers after exact polite prefixes such as "can you", "could you", "would you", "will you", and "please", while still requiring a known command first word and still rejecting incidental prose like "The docs say run ls after setup." Deterministic CLI smoke, Playwright real-world actions, and live TrustedRouter smoke now include a non-backticked polite command with required output.
- Release-candidate smoke needs a first-class CI entrypoint, not only local instructions. The `Real World Smoke` workflow now runs `./scripts/real-world-smoke.sh` directly, installs Playwright before the wrapper preflight, defaults manual runs to `QUILLCODE_REQUIRE_LIVE_SMOKE=1`, keeps scheduled runs useful when the live secret is absent, and uploads the wrapper artifact root so reviewers can inspect `real-world-smoke-manifest.json` plus deterministic/live sub-suite evidence.
- Real-world action smoke must explicitly cover do-it-now wording, not only generic command prompts. Users often phrase follow-through as "run this now" after a model has promised work; deterministic CLI smoke, Playwright, and opt-in live TrustedRouter smoke now include a `printf quillcode_*_now_smoke` command prompt that must dispatch a concrete `host.shell.run` call with nonempty arguments and visible output in the same turn. The non-live CLI now enables the same immediate-action preflight as live CLI runs, so deterministic smoke exercises production planner code before falling back to the mock model. The live transcript integrity floor increased with that scenario so release evidence proves the extra thread was persisted as an actionable tool run.
- Native click-target policy must describe each surface by target kind, user action, and focus ownership. A 44 pt frame is necessary but not sufficient: a browser surface needs text input plus pressable actions, a review surface needs reply/body text entry plus segmented/action controls, and composer/search/model picker settings must declare which text-entry target owns focus. `QuillCodeNativeSurfaceTargetPolicy` now carries `requiredActions` and `requiredFocusTargets` beside `requiredKinds`, and native smoke fails on missing surface actions or focus targets so future UI work cannot pass by preserving only token geometry.
- Download request parsing is production agent behavior, not a mock-LLM heuristic. `AgentDownloadRequestParser` owns natural-language download intent, URL/path extraction, workspace-relative path guarding, and curl command construction; `AgentImmediateActionPlanner` and `MockLLMClient` both call that parser. This keeps real-world actions such as "download LinkedIn.com" consistent across native agent runs, desktop smoke, and Playwright while preventing the mock harness from becoming the hidden source of production behavior.
- Native SwiftUI click targets are a source-level contract, not only a rendered snapshot property. Any workspace control using `QuillCodePressableButtonStyle` or `QuillCodeActionButtonStyle` must declare the narrowest semantic target helper near the rendered control (`icon`, `textButton`, `formAction`, `fullRow`, `capsule`, etc.), and raw SwiftUI `TextField`, `SecureField`, `Picker`, `Toggle`, and `DisclosureGroup` uses must declare their corresponding text-entry, segmented/adjustable, switch-row, or disclosure-label target. The source audit deliberately ignores wrapped controls such as `QuillCodeLabeledTextField` so reusable primitives can own their own target contract, while new raw controls fail tests until their hit area, shape, and focus semantics are explicit.
- Native click-target helpers are not interchangeable geometry shims. The source gate rejects mismatched helper/control pairs, such as a `Button` using a text-entry target, a segmented `Picker` using a row target, or an adjustable control using a text-button target. This keeps the review question at the right level: what kind of interaction does this control own, and should its hit surface be icon-sized, row-wide, input-shaped, segmented, adjustable, or link-like?
- Local integrated-terminal commands should run through PTY by default, while SSH Remote terminal commands should keep using the existing noninteractive `ssh -T` pipe path. Local terminal parity depends on programs seeing a real TTY (`isatty()`), prompt input echo, and interactive stdin behavior; SSH Remote continuity already depends on explicit marker parsing over a predictable pipe. `WorkspaceTerminalProcessLauncher` owns that policy so `QuillCodeWorkspaceModel` depends only on the shared `ShellInteractiveSession` protocol and does not know whether the active process is pipe-backed or PTY-backed.
- Superseded: the first model-backed subagent implementation used a focused, tool-free `LLMClient.nextAction` turn. The current runtime uses the configured multi-step agent session described in the latest subagent decision below; this historical note remains only to explain the migration.
- High-confidence read-only git inspection requests should resolve before a live provider call. `git status`, `git diff`, and natural "what changed?" prompts are core coding-agent workflows, have no write side effects, and should not regress into passive promises, empty shell calls, or provider-specific command formatting. `AgentGitReadRequestParser` is shared by the live immediate-action preflight and deterministic mock path, returns canonical `host.git.status` / `host.git.diff` calls with `{}` arguments, and final answers summarize the actual git output as `Git status:` or `Git diff:`. Live TrustedRouter smoke seeds a tiny repo and verifies both prompts against real workspace state; transcript integrity therefore allows `{}` only for these read-only git tools while still rejecting empty argument objects for action tools.
- `WorkspaceToolCardSubtitleBuilder` matches on the registered `ToolDefinition.*.name` constants instead of hardcoded tool-name string literals, matching the idiom the rest of QuillCodeApp already uses (`WorkspaceBrowserToolExecutor`, `WorkspaceAgentRunContextBuilder`, `WorkspaceRemoteGitHubPullRequestCommandBuilder`, the agent argument normalizer). The string-literal switch was what allowed the MCP subtitle typos (`host.mcp.read_resource` vs the real `host.mcp.resource.read`); keying on the constants makes a renamed or mistyped tool a compile error rather than a silently missing subtitle. The change is behavior-preserving — every constant's `name` equals the literal it replaced — and the existing subtitle tests pin the output. The static-harness JS keeps string literals because it has no access to the Swift constants; the paired Swift/Playwright tests guard against the two surfaces drifting.
- Behind PR branches should pause the merge train by default instead of being updated with GitHub Actions' `GITHUB_TOKEN`. We observed `gh pr update-branch` from the train mutate a branch without producing normal completed `pull_request` CI checks, leaving the train to see "no completed CI checks" until a human/agent pushed the branch again. `MERGE_TRAIN_UPDATE_BEHIND_BRANCHES` now defaults to `false`; agents should rebase or merge `main` and push normally, while installations with a token that can trigger required PR checks can explicitly opt back into automatic branch updates.
- Tool-card subtitle detail must use each tool's real canonical argument keys, including the MCP and Computer Use tool families. `WorkspaceToolCardSubtitleBuilder` read `host.mcp.call`'s tool name from a non-existent `tool` key (the canonical key is `toolName`) and matched `host.mcp.read_resource`/`host.mcp.get_prompt`, which are not the registered tool names (`host.mcp.resource.read`/`host.mcp.prompt.get`), so all three MCP cards showed no detail. The builder now reads `toolName` for calls, `resourceName`/`name`/`resourceURI`/`uri` for resource reads, and `promptName`/`name` for prompt gets. Computer Use cards previously showed only the state label; `host.computer.click`/`move` now show `x, y`, `host.computer.scroll` shows `dx, dy`, and `host.computer.type`/`key` show their text. `host.computer.screenshot` remains argument-detail-free while queued or running, then completed screenshot cards derive size, foreground-app, and visible-control-count detail from the structured tool result. The static-harness `toolCardDetail` mirror was corrected to the same keys, and Swift and Playwright tests pin every case.
- Tool-card subtitles derive their detail from the argument the tool actually carries, and the Swift builder and static-harness JS must agree on every tool. `WorkspaceToolCardSubtitleBuilder` keyed the URL detail to `host.browser.inspect` (which takes no arguments, so the detail was always empty) while never handling `host.browser.open` (which carries the `url`), so the common "agent opened a page" card showed no URL. The open case now reads `url` and `host.git.pr.review_comment` joins the path tools (its changed-file path is more useful than the optional selector). The static-harness `toolCardDetail` mirror dropped the dead `host.browser.inspect` branch, added `host.git.pr.review_comment` to its path set, and added an explicit `host.git.pr.review_thread` action branch before the generic `host.git.pr.*` selector fallback so the two surfaces produce identical subtitles. Swift and Playwright tests pin the opened-URL and reviewed-path subtitles.
- Native smoke should prove follow-through in the app surface, not only a first-turn side effect. The native render smoke now sends a second desktop composer turn after creating `hello.txt`, reads the file back through `host.file.read`, renders the follow-up result evidence, and requires both write/read tool names plus the read-back answer in `report.json` and `workspace.html`. The legacy `prompt`/`finalAnswer`/`toolName` fields continue to describe the write turn for compatibility, while `followUpPrompt`, `followUpFinalAnswer`, `followUpToolName`, and `toolNames` document the complete two-turn desktop workflow.
- Labeled action buttons in flex header rows must not shrink below their own text. The shared `hit-target-text` primitive sets `min-width: var(--hit-target)` (44px) as a floor for compact controls, but that floor also lets a flex parent compress a labeled button below its content width, clipping words like "Add memory" when the Activity pane narrows the secondary-pane column. `.memories-add-button`, `.memory-edit-button`, and `.memory-delete-button` now set `flex-shrink: 0` so the label keeps its natural width and the wrappable title block absorbs the layout pressure instead. A Playwright invariant sweeps the secondary panes at a 768px tablet width with the Activity pane open and fails if any visible labeled button reports `scrollWidth > clientWidth`.
- Multi-line card buttons must own their internal layout instead of inheriting the shared text hit target's centered row. The empty-state starter actions render a bold title above a muted subtitle to match the native SwiftUI `VStack`, but the shared `hit-target-text` primitive applies `display: inline-flex` with centered row alignment, which collapsed the `<strong>` title and `<span>` subtitle onto one line with no separating space (e.g. "Review changesFind risks in the current diff"). `.empty-starter` now sets a left-aligned vertical column (`display: flex; flex-direction: column; align-items: stretch`) with a 72px minimum height so the title/subtitle stack as designed across HTML, Playwright, and native. A Playwright invariant asserts the subtitle sits below the title and shares its left edge at desktop and mobile widths.
- Real-world smoke must prove workspace follow-through, not only first-turn side effects. Direct file-read prompts now route through `host.file.read` when they name a safe workspace-relative path, deterministic smoke lists and reads back the file it just created, and live TrustedRouter smoke adds `workspace-list-followup` plus `workspace-read-followup` after file-write scenarios. This keeps "created a file but cannot inspect it next" regressions in the release lane where they belong.
- Labeled controls must use a hit target that grows with their text, not a fixed icon-sized square. The HTML composer "Send" button rendered through `WorkspaceHTMLPrimitives.button` now uses `hitTargetKind: .text` like its active-send "Stop" sibling instead of `.icon`; a 44pt icon square clipped the word "Send" because its content was wider than the box. Icon hit targets remain correct for single-glyph controls (browser reload `R`, inline-note move `v`, and the native SwiftUI send button, which renders an `arrow.up` glyph rather than text). A Playwright invariant now asserts labeled composer controls never report `scrollWidth > clientWidth` and never declare the `icon` kind, so a clipped label fails CI instead of slipping past the geometry-only clipping audit.
- Deterministic smoke needs the same auditability as live smoke. When `QUILLCODE_SMOKE_ARTIFACT_DIR` is set, `scripts/smoke.sh` now writes `deterministic-smoke-manifest.json` with step-level statuses for Swift tests, CLI prompt families, live-mode missing-key handling, native desktop smoke, packaged macOS smoke, and Playwright. `scripts/real-world-smoke.sh` embeds that manifest under the deterministic section, so a release-candidate artifact proves which deterministic layers ran without reading terminal logs.
- Release-candidate smoke should fail closed on missing browser E2E coverage. `scripts/smoke.sh` still skips Playwright by default for lightweight local runs, but `scripts/real-world-smoke.sh` defaults `QUILLCODE_REAL_WORLD_REQUIRE_PLAYWRIGHT=1`, preflights `E2E/playwright/node_modules`, records `missing-playwright-dependencies` in `real-world-smoke-manifest.json`, and exits before running partial release evidence. Developers can set `QUILLCODE_REAL_WORLD_REQUIRE_PLAYWRIGHT=0` only for an intentional lighter local run.
- Release-candidate smoke needs one top-level verdict artifact. `scripts/real-world-smoke.sh` now writes `real-world-smoke-manifest.json` when `QUILLCODE_REAL_WORLD_SMOKE_ARTIFACT_DIR` is set, recording deterministic/live status, live skip or failure detail, the artifact root, deterministic artifact file summaries, and the nested live TrustedRouter manifest when present. This keeps the release lane reviewable from one JSON file while preserving the deeper sub-suite artifacts for diagnosis.
- Successful live TrustedRouter smoke needs a reviewable artifact contract, not only pass/fail terminal output. `scripts/live-tr-smoke.sh` now writes `live-smoke-manifest.json` with scenario counts, workspace files, and persisted thread summaries, and copies the manifest/report/stdout/stderr bundle when `QUILLCODE_LIVE_SMOKE_ARTIFACT_DIR` is set. `scripts/real-world-smoke.sh` forwards `QUILLCODE_REAL_WORLD_SMOKE_ARTIFACT_DIR` into deterministic and live subfolders so release-candidate runs have one auditable evidence root without exposing API keys.
- Live TrustedRouter smoke needs scenario-level observability because real-provider failures are workflow failures, not just command failures. `scripts/live-tr-smoke.sh` records one JSONL row per scenario with model, base URL, prompt, duration, stdout/stderr byte counts, and artifact paths, and failure output names the scenario, prompt, stdout/stderr tails, and report summary. This keeps paid/network smoke opt-in while making “empty command”, passive-promise, missing-file, and transcript-integrity failures immediately actionable.

## 2026-06-28

- Rendered click targets must declare three pieces of intent: target kind, target action, and source. Source markup/primitives should produce non-`auto` `data-hit-target-kind`, `data-hit-target-action`, and `data-hit-target-source`; the runtime normalizer may label fallback controls as `auto-*`, but broad Playwright audits fail those so primary UI cannot pass by inference after render.
- Click-target quality includes collision budget between adjacent controls. Interactive SwiftUI clusters should use `QuillCodeMetrics.controlClusterSpacing` or `QuillCodeMetrics.denseControlClusterSpacing`; numeric point spacing is acceptable for passive visual chips but not for button/control groups. The native source audit fails raw numeric clusters that contain controls so future UI polish cannot accidentally create edge-miss targets.
- Project-local marketplace catalogs reuse extension manifests instead of introducing a second install runtime. QuillCode scans `.quillcode/marketplace/*.json` with the same byte/count/symlink/root bounds as installed extensions, requires each catalog row to declare `kind`, marks those rows as `Available`, filters them out once the matching installed manifest ID exists, and runs Install through the existing audited `host.shell.run` path. Signed remote catalogs and executable plugin packaging remain separate future layers on top of this deterministic contract.
- Session-dismissed Activity instruction diagnostics are workspace UI state, while project-level Instruction Review dismissals are durable `ProjectInstructionDiagnosticResolution` records. In both cases Dismiss hides only the current active diagnostic from Instruction Review and Sources. Resolving the actual rule conflict goes through normal audited file editing: either a user/model source edit, or an exact two-reference `Keep ...` quick fix that emits `host.apply_patch` and then refreshes metadata so resolved-by-edit audit history is recorded when the diagnostic disappears.

## 2026-06-27

- Click-target quality includes affordance and compression behavior, not only geometry. Non-disabled clickable rendered targets should expose a pointer cursor unless they are text-entry/select controls, and compact layouts should wrap before text inputs shrink below the 44 px target. The transcript find bar uses the same rule in both rendered HTML and SwiftUI (`ViewThatFits` for native, wrapped grid rows for the harness).
- Rendered command-palette pull-request actions should mirror `WorkspacePullRequestCommandCatalog`, not a hand-picked subset. Draft-style commands should prepare and focus the composer through `usePromptAsDraft`, concrete read actions should execute normal tool-card flows, and tests should click exact `data-command-id` targets. Palette search should also support token-wise matching across title, ID, category, and keywords so users can type intent phrases without exact contiguous wording.
- High-risk click targets should be declared in a named rendered registry, not only checked incidentally during broad sweeps. Primary chrome, top-bar overflow, model picker row actions, command palette, settings auth, terminal, browser, and transcript tool-card disclosures all need explicit `expectCriticalTargetRegistry` coverage so interaction drift is reviewable.
- Click-target quality is measured by real hittability, not only visual size. The Playwright interaction audit samples a 3x3 interior grid for each visible control, reports visible non-disabled controls with `pointer-events: none`, ignores pointer ownership only for semantically disabled controls, and treats generic dialogs as active interaction layers. This keeps compact Codex-style controls visually calm while making dead or edge-blocked targets fail CI.
- Native SwiftUI buttons must use shared hit-target helpers plus an explicit press/platform style. Text-entry controls must be tested by clicking interior edge points and then typing, not only by checking visibility. This prevents regressions where search, command palette, terminal, browser, or settings fields look correct but lose focus or route taps to nearby chrome.
- Native SwiftUI source gates inspect the owning control scope, not a broad source window. A target helper on a sibling control or inside Menu content cannot satisfy the trigger that opens the Menu. Link/artifact previews should put the shared target on the Link label itself so the clickable element owns its contract.
- Real-world smoke coverage is a release lane, not a normal PR requirement. `./scripts/real-world-smoke.sh` runs the deterministic suite first and then runs `./scripts/live-tr-smoke.sh` when a TrustedRouter key is available through `QUILLCODE_API_KEY`, `TRUSTEDROUTER_API_KEY`, or `~/.quill.code.keyfile`. Normal CI stays deterministic, while parser, prompt, safety, and runtime changes can be tested against a real cheap model before shipping.
- Live TrustedRouter smoke artifacts are preserved on failure. Model regressions such as empty shell arguments, passive “I'll do it” replies, missing file side effects, or bad transcript tool events need stdout/stderr/thread JSON left on disk so the failure can be diagnosed instead of disappearing in cleanup.

## 2026-06-26

- Composer sends record the user turn before the async agent run starts. `WorkspaceAgentSendStartPlanner` owns the optimistic user message/event/title update, and `WorkspaceAgentSendSession` can run with `recordsUserMessage: false` so the agent does not duplicate that turn. Desktop surfaces are snapshot-based, so `QuillCodeDesktopComposerCoordinator` must refresh on the model's `onStarted` and progress callbacks; otherwise the model state is correct but the macOS window does not paint the user bubble or thinking indicator until the run finishes.

## 2026-06-23

- Active sidebar chats are grouped by relative recency through `SidebarSurface.recentSections(now:calendar:)`, not renderer-specific date logic. Native SwiftUI, static HTML, and Playwright should use the same sections: Today, Yesterday, Previous 7 days, Older. Rows sort newest-first inside each bucket. Pinned and Archived remain explicit sections because they are user/workflow state, not recency buckets.
- Codex-style workspace chrome should keep model selection and approval mode as separate controls near the composer, not in the top bar. Model is a long-lived preference, while approval mode is an autonomy/safety posture users may change at send time. The model picker should only select models; Auto/Review/Read-only lives in a compact mode control beside it. Instruction files, memories, Computer Use readiness, and runtime issues remain accessible in the status popover and transcript/settings surfaces, but they should not occupy permanent top-bar width. This keeps the first read calmer while preserving diagnostics and Playwright coverage.
- TrustedRouter prompt/message construction lives in `TrustedRouterPromptBuilder`, not the network client. The builder owns system prompt copy, tool schema formatting, project instruction context, memory context, message-history projection, tool-output projection, and the history limit. `TrustedRouterLLMClient` owns SDK calls and stream collection.
- TrustedRouter API-key resolution lives in `TrustedRouterAPIKeyResolver`. Developer override precedence, whitespace trimming, session-store fallback, and the actionable missing-key error should stay there so action and safety clients cannot drift.
- TrustedRouter action and safety transports are separate files. `TrustedRouterLLMClient` owns action streaming; `TrustedRouterSafetyModelClient` owns Auto-review model calls. They share API-key resolution through `TrustedRouterAPIKeyResolver` and JSON response payloads through `TrustedRouterChatParameters` so neither transport depends on the other.
- Static Auto safety fallback policy lives in `StaticSafetyPolicy`, not `StaticSafetyReviewer`. The reviewer owns mode behavior, hard-deny precedence, low-risk approval, and model-backed fallback orchestration; the policy owns table-driven hard-deny patterns, generic user-intent rules, and pull-request-specific intent routing.
- Static Auto safety intent rules must be tool-limited. Broad user words like `run`, `execute`, `disk`, `storage`, `whoami`, and `openclaw` should approve the bounded tool families that satisfy that request, not any append/destructive tool the model happens to propose.
- Core domain models live in focused files rather than a general `Models.swift` bucket. `AgentMode.swift`, `ChatModels.swift`, `AgentPlanModels.swift`, `SubagentModels.swift`, `ApprovalModels.swift`, `ThreadEventModels.swift`, `MemoryModels.swift`, `ChatThread.swift`, and `JSONHelpers.swift` own the general thread/chat/memory domain; parity gates prevent the old umbrella file from returning.
- TrustedRouter model defaults and catalog normalization live in focused core files. `TrustedRouterDefaults.swift` owns provider IDs, branded aliases, bundled fallback rows, Nike/Zeus/Prometheus/Socrates/Aristotle/Plato branding, and sort/category policy; `ModelInfo.swift` owns the catalog value records.
- App configuration is a focused core boundary. `AppConfig.swift` owns persisted model/mode/base-URL settings, OAuth/developer-override compatibility, signed-in TrustedRouter account metadata, and favorite-model normalization; general chat/thread/project models should not own settings compatibility rules.
- Core tool records are a focused schema boundary made of single-purpose files. `ToolDefinition.swift`, `ToolCall.swift`, `ToolResult.swift`, `CoreToolDefinitions.swift`, `BrowserInspectionToolOutput.swift`, and `MemoryRememberToolOutput.swift` own tool schema records, redaction, built-in tool definitions, and tool-specific output compatibility; general chat/thread/project models and broad catch-all tool files should not own tool payload compatibility rules.
- Core automation records are a focused scheduling boundary. `AutomationModels.swift` owns automation kind/status/schedule enums, recurrence interval semantics, next-run calculation, and display sorting; general chat/thread/project models should not own recurring-workflow scheduling rules.
- Core project records are a focused workspace boundary made of single-purpose files. `ProjectConnection.swift`, `ProjectRef.swift`, `ProjectInstruction.swift`, `LocalEnvironmentAction.swift`, and `ProjectExtensionManifest.swift` own local/SSH connection parsing and display, project refs, instructions, local environment actions, and project extension manifests; general thread/message models and broad catch-all project files should not own workspace connection or extension compatibility.
- Tool-router feature families should delegate before they sprawl. `ToolRouter` owns the common shell/file/patch entry point and composes git definitions from `GitToolCallDispatcher`; local git, GitHub PR, and worktree tool-call argument mapping lives in that dispatcher. This keeps the shared router small while preserving one public `ToolRouter.execute` API for the agent runtime.
- Shell request policy is a tool-family concern. `ShellToolCallDispatcher` owns `host.shell.run` definitions, cwd containment, timeout bounds, environment override validation, and `ShellExecutionRequest` construction; `ToolRouter` only delegates shell calls before handling file and patch primitives.
- SSH Remote project integration coverage lives in `WorkspaceRemoteProjectIntegrationTests`, not `WorkspaceModelTests`. SSH project creation, remote context refresh, remote-safe tool exposure, shell/file/git/GitHub/worktree execution through SSH, and remote path safety cross the workspace model, SSH executor, tool cards, surfaces, and transcript events; keep those flows together while low-level remote command builders stay in their focused tests.
- Worktree integration coverage lives in `WorkspaceWorktreeIntegrationTests`, not `WorkspaceModelTests`. Local and SSH Remote worktree listing, worktree command prefill, local worktree create/open/remove, remote SSH worktree creation/opening, focused thread/project switching, tool cards, and worktree artifacts cross workspace model, git tools, SSH Remote execution, transcript events, project state, and top-bar state; keep those flows together while pure worktree command planning and open-thread construction stay in focused unit tests.
- Pull request workflow integration coverage lives in `WorkspacePullRequestIntegrationTests`, not `WorkspaceModelTests`. SSH Remote PR workspace commands, `/pr ...` slash dispatch through fake GitHub CLI over SSH, command-prefill copy, tool cards, PR URL artifacts, and remote execution context chips cross workspace commands, slash routing, SSH execution, GitHub CLI behavior, and transcript surfaces; keep those flows together while primitive PR validation/execution stays in tool and remote-planner tests.

## 2026-06-20

- Product and repository name: **QuillCode**.
- License: Apache 2.0.
- Default model: Nike 1.0 (`trustedrouter/fast`). The named Recommended presets are Nike 1.0, Zeus 1.0, Prometheus 1.0 (`trustedrouter/fusion`), Socrates 1.0, Aristotle 1.0, and Plato 1.0. Raw model types such as synth are retired as named defaults and typed `/model` targets; they should only appear if the live TrustedRouter catalog exposes an actual provider/model entry.
- Auth: TrustedRouter OAuth first; hidden developer override for API key/base URL.
- Tool modes: `Read-only`, `Review`, `Auto`; do not use the label `Full Access`.
- Auto reviewer: primary `glm-5.2`, fallback `kimi-k2.6`.
- First implementation uses a deterministic mock LLM so tests do not require network or credits.
- Live TrustedRouter mode is exposed through `quill-code --live`; native UI should use the same `LLMClient` and `SafetyModelClient` protocols.
- QuillUI is the UI direction, but core tests must not depend on a dirty local QuillUI checkout.
- Platform-specific code belongs in adapter packages, not the app target.
- The first desktop executable is `quill-code-desktop`, built with SwiftUI over the same `WorkspaceSurface` contract used by the HTML/Playwright harness. This keeps native UI work testable before the full QuillUI adapter exists.
- The desktop executable entry file is `QuillCodeDesktopApp.swift`, not `main.swift`. Swift treats `main.swift` as a top-level script entry in multi-file executable targets, so the native `@main` app lives in a named app file while commands, menu-bar UI, OAuth loopback, notifications, browser fetching, and task coordination stay in focused desktop adapter files.
- Desktop runtime selection defaults to mock LLM for no-key demos, switches to live TrustedRouter when an environment or stored secret key exists, and supports `QUILLCODE_USE_MOCK_LLM=true` for deterministic test runs.
- The desktop model picker is data-driven from the TrustedRouter catalog. It keeps Nike 1.0 (`trustedrouter/fast`) first, shows only the branded Recommended presets above, groups all live options by category/provider, and refreshes live catalog data only when an env or stored key exists.
- TrustedRouter model defaults, provider/model aliases, bundled fallback catalog entries, API base URL, display-name normalization, and sort keys live in `QuillCodeCore`. The live TrustedRouter adapter and app picker both merge sparse catalogs with those bundled defaults, so the default/next-option ordering is consistent across CLI, SwiftUI, and Playwright harness surfaces.
- Model picking uses the same provider/category/model search semantics in SwiftUI and the Playwright harness. Filtering is term-based across provider, category, model ID, display name, branded summary, and capability text so users can type things like `moon k2`, `oss coding`, or `deep research` without knowing the exact provider string.
- Model picker rows carry deterministic metadata from the catalog and workspace state: provider, category, model ID, current selection, favorite, recent, default, and recommended status. `WorkspaceModelCatalogSurfaceBuilder` owns label/category construction from value inputs so SwiftUI, Playwright harness search, and older surface-payload decoding stay aligned.
- Model picker detail browsing is deterministic but can now include live TrustedRouter capability metadata. `TrustedRouterModelCatalogDecoding` owns flexible `/models` response parsing for context window, pricing, input/output modalities, capability tags, status, and summaries. `ModelInfo` stores normalized `ModelCapabilities`, and the app projects those claims into structured metadata rows/search terms rather than prose summaries so ordinary queries like `coding` do not match every recommended model just because a sentence mentions coding.
- TrustedRouter model-catalog freshness is a root-state status, not a per-row capability. `ModelCatalogStatus` records bundled fallback, live TrustedRouter fetches, and fallback-after-refresh-failure with fetch age and bounded failure detail; the model picker and Settings render that shared label while individual `ModelInfo.capabilities.status` remains the provider/model health row. This keeps catalog-source diagnostics visible without repeating a global freshness badge on every model.
- Provider health summaries are catalog-derived until TrustedRouter publishes a stable provider-status endpoint. `ModelProviderHealthSummary` groups live `ModelInfo.capabilities.status` values by canonical provider and feeds the picker/Settings header. Proactive desktop refresh polls the keyed TrustedRouter model catalog at startup and on a bounded stale interval, then derives provider health from that single catalog source instead of inventing a second status loop.
- The first project UX is a native project rail backed by explicit selected-project state and `~/.quillcode/projects.json`. Ordinary desktop launch waits for explicit project selection; only an explicit launch workspace is registered. `Open project` uses a desktop folder picker while the surface contract keeps the project action as a platform-neutral command.
- Project registry mutation rules live in `WorkspaceProjectEngine`. The workspace model owns loaders, stores, terminal synchronization, and top-bar refresh, while the engine owns local/SSH project upsert, selected-project thread selection, project removal cleanup, metadata application, timestamp touches, and default naming. This keeps Codex-style project/worktree/remote behavior testable without booting the whole workspace model.
- Native developer settings save the TrustedRouter API base URL in `config.toml` and the local API key through `QuillSecretStore`. Saving settings rebuilds the active desktop runtime immediately so the user does not need to relaunch to switch from mock to live mode.
- TrustedRouter authentication has an explicit persisted mode. `oauth` is the default user-facing path, while `developer-override` is an intentional settings choice that reveals API key/base URL controls and preserves compatibility with older `developer_override_enabled` configs.
- The OAuth settings path starts a localhost `http://localhost:3000/callback` listener, opens TrustedRouter authorization with PKCE `S256`, exchanges the returned code through `/auth/keys`, stores the scoped key through `QuillSecretStore`, and rebuilds the desktop runtime without a relaunch.
- OAuth sign-in persists only non-secret TrustedRouter identity metadata, such as user id, subject, email, and wallet address, in `config.toml`. The delegated key remains exclusively in `QuillSecretStore`, and developer override mode clears OAuth account metadata so settings never imply the wrong signed-in user.
- QuillCode owns a small pure TrustedRouter OAuth client for now: PKCE `S256`, authorize URL construction, callback state/code parsing, `/auth/keys` exchange, and `/auth/userinfo`. Desktop loopback capture uses this client instead of duplicating endpoint logic.
- The first review surface is derived from completed `host.git.diff` tool cards rather than separate mutable UI state. That keeps the Codex-style review pane replayable from the thread event log and lets stage/revert controls build on the same parsed diff summary later.
- Slash commands are handled by the workspace model before agent dispatch. They are local app controls, not model turns, so `/new`, `/mode`, `/model`, `/status`, and `/help` stay deterministic and do not consume TrustedRouter requests.
- Git stage/restore tools run `git` through process arguments, not shell strings, and resolve requested paths back into the workspace before execution. Review-pane hunk controls should reuse the same path guard.
- Review-pane Stage/Restore controls append normal tool queued/running/completed events and immediately run `host.git.diff` afterward. The UI does not keep a separate review mutation log; the visible review pane remains reconstructed from the latest diff tool result.
- Review scope is part of the replayable Git-diff contract. Unstaged and Staged map to explicit `host.git.diff` arguments, and every mutation refreshes the scope that initiated it rather than falling back to an implicit working-tree diff. A successful empty diff remains visible with scope-specific copy so an action has an observable completion state.
- Staged review is intentionally non-destructive. Its file and hunk actions unstage content while preserving working-tree edits; Restore is offered only in Unstaged review. Commit and Branch comparisons are historical and therefore expose no mutation actions: Commit uses `git show --format=` for one validated reference, while Branch uses `git diff base...HEAD` so Git computes the merge base. The same typed `GitDiffOptions` builds local process arguments and SSH commands, rejects conflicting selectors, and keeps references out of ad hoc shell interpolation.
- Last turn review is derived from the most recent user turn's recorded `apply_patch` calls, not from the current working-tree diff. Repeated patches are coalesced per file for presentation while reverse application retains chronological patch order. An empty newest turn stays empty instead of falling back to older edits, non-patch mutations produce an explicit partial-provenance warning, and SSH Remote projects expose the view without a misleading local revert action.
- Whole-diff actions are bounded to the file paths currently visible in Review. Stage all, Revert all, and Unstage all carry an explicit validated path array through local or SSH Git execution rather than using `.`; one unsafe path rejects the entire call. Last turn Revert all routes to the existing atomic reverse-patch engine rather than synthesizing a Git restore.
- Hunk Stage/Restore uses selected unified-diff patches and `git apply` through process arguments: `--cached` for staging and `--reverse` for restoring. The tool rejects patch metadata that points at a different path than the selected review hunk.
- Review notes are stored as `reviewComment` thread events and folded into the latest diff-derived review pane by path. Optional line/range metadata attaches comments to the matching changed line or first line of the matching range in the latest diff; notes for files or ranges that are no longer present remain in the transcript event log but are hidden from the current review pane.
- Successful `host.apply_patch` calls automatically run `host.git.diff` next. Patch editing and review are therefore connected through the same replayable tool-card/event path as explicit review actions, and the visible review pane always comes from a real git diff rather than separate optimistic UI state.
- Local git commit support is intentionally limited to already staged changes and a required message. Push, PR creation, and remote writes remain separate tools so safety and review can gate them differently.
- Git push support is limited to named remotes and safe branch names, defaulting to `origin` and the current branch. The first implementation intentionally excludes arbitrary refspecs and URL remotes so normal branch publishing works without broad remote-write ambiguity.
- GitHub pull request creation is a structured `host.git.pr.create` tool backed by `gh pr create` through process arguments for local projects and a shell-quoted remote `gh pr create` command for SSH Remote projects. The tool requires a title unless `fill` is explicitly enabled, validates base/head refs with the same conservative ref-name guard as push, and returns the created PR URL as an artifact when the GitHub CLI prints one.
- GitHub pull request reading is split into two read-risk tools: `host.git.pr.view` for `gh pr view --comments` and `host.git.pr.checks` for `gh pr checks`. Both accept an optional conservative selector, run locally or through the selected SSH Remote project's GitHub CLI, and keep PR URLs in `ToolResult.artifacts` so transcript cards render the link as a normal artifact chip instead of relying on stdout parsing in the UI.
- GitHub pull request diff is a separate read-risk `host.git.pr.diff` tool backed by `gh pr diff`. It reuses the same conservative PR selector guard and local/SSH Remote routing as PR view/checks so review-oriented workflows do not fall back to ad hoc shell commands.
- GitHub pull request checkout is a separate append-risk `host.git.pr.checkout` tool backed by `gh pr checkout`. It validates the optional selector with the same conservative PR selector guard and validates optional local branch names with the shared git-name guard before changing the selected local or SSH Remote workspace branch.
- GitHub pull request commenting is a separate append-risk `host.git.pr.comment` tool rather than a shell recipe. It validates the optional selector with the same conservative PR selector guard, requires a non-empty body, runs through local `gh pr comment` or the selected SSH Remote project's GitHub CLI, and returns any printed PR URL as a normal artifact.
- GitHub pull request reviews are a separate append-risk `host.git.pr.review` tool backed by `gh pr review`. The tool accepts explicit `approve`, `comment`, or `request_changes` actions, requires review body text for comment/request-changes reviews, validates optional selectors with the same PR selector guard, and runs through local or SSH Remote GitHub CLI paths. This keeps review submissions distinct from top-level conversation comments.
- GitHub pull request inline review comments, inline review replies, and review-thread resolve/unresolve actions reuse the structured PR tool family. Current-PR metadata lookup lives in `GitHubPullRequestMetadataResolver`; the resolver owns `gh pr view` / `gh repo view` JSON decoding and validation, while `GitHubPullRequestToolExecutor` owns `gh api` argument construction and result artifacts.
- GitHub pull request reviewer changes are a separate append-risk `host.git.pr.reviewers` tool backed by `gh pr edit --add-reviewer/--remove-reviewer`. It accepts optional PR selectors plus explicit add/remove reviewer arrays, validates GitHub usernames, `org/team` reviewers, and `@copilot`, rejects empty requests, and runs locally or through the selected SSH Remote project's GitHub CLI path.
- GitHub pull request label changes are a separate append-risk `host.git.pr.labels` tool backed by `gh pr edit --add-label/--remove-label`. It accepts optional PR selectors plus explicit add/remove label arrays, preserves labels with spaces, rejects empty/comma/control-character/flag-like labels, deduplicates labels while preserving order, and runs locally or through the selected SSH Remote project's GitHub CLI path.
- GitHub pull request merge/automerge is a destructive-risk `host.git.pr.merge` tool backed by `gh pr merge`. It accepts only conservative selectors, merge methods (`squash`, `merge`, or `rebase`), optional GitHub auto-merge, and optional branch deletion. The default method is `squash`, and Auto safety approves it only when the latest user request explicitly asks to merge or auto-merge a PR.
- Search stays local and deterministic for now. Sidebar items carry a capped visible transcript/tool-card search index derived from persisted thread messages and events, so users can find prior chats by content without a separate background indexer yet. Internal agent continuation messages with the `tool` role are excluded from sidebar search, fork seeds, and compaction summaries because they are model feedback, not user-facing transcript content.
- The first command palette is a filtered view over `WorkspaceCommandSurface`, not a separate command registry. Native menus, sidebar buttons, top-bar overflow, and palette entries must route to the same command IDs so keyboard and visible actions stay consistent.
- The first integrated terminal is command-history based rather than a persistent PTY. It runs workspace-scoped shell commands through the same local shell executor as `host.shell.run`, consumes stdout/stderr as process events so long-running commands show live output, persists the shell's final working directory across commands, and stores exported/unset environment changes as per-project deltas from QuillCode's launch environment. Full PTY job control and interactive curses-style programs remain later adapter milestones.
- Running terminal commands accept explicit line-oriented stdin through the same command field. The visible action changes from Run to Send while a process is active, history recall stays disabled during the run, and Stop All cancels the active shell session handle rather than only marking UI state. This is intentionally not full PTY emulation; it covers common prompt/read flows while keeping job control as a later adapter milestone.
- Git worktree creation accepts only paths inside the selected project's parent directory so Codex-style sibling worktrees are possible without arbitrary filesystem targets. Opening or removing a worktree is stricter: the path must also appear in `git worktree list --porcelain` before QuillCode can switch to it or remove it.
- Worktree create/open/remove UI uses dedicated dialogs that dispatch structured `host.git.worktree.*` tool calls rather than stuffing commands into the chat composer. This keeps app-initiated workspace actions replayable in the transcript in the same shape as agent tool calls.
- A successful worktree create or open keeps the source thread's tool audit trail, then registers the worktree as a local project or SSH Remote project and opens a selected `Worktree: ...` thread inside it. This matches the Codex expectation that branch workspace creation or switching immediately hands the user into the checkout without losing replayable provenance.
- Project instruction loading starts with `AGENTS.md`, `.quillcode/rules.md`, and `.quillcode/instructions.md`. Instructions are bounded, stored on the project, copied into thread context before agent runs, and sent as hidden system context rather than visible transcript messages.
- Nested project instruction discovery walks project directories with scan, file, and byte caps, skips generated and hidden dependency folders, and orders files from broadest to most specific so deeper `AGENTS.md` or `.quillcode` rules can override project-wide defaults in the prompt contract. Each instruction record also carries a derived applicability scope (`.` for whole-project files, or the containing directory for nested files) so prompts and Activity sources can distinguish whole-project rules from subtree-only rules. Scope diagnostics are intentionally structural: QuillCode flags duplicate scopes and nested override relationships in Activity, but does not claim prose-level semantic contradictions until a dedicated conflict-review UI exists.
- Local environment actions are discovered from project-local `.quillcode/actions/*.sh` and `.quillcode/local-env/*.sh` files, capped at 16 actions, and exposed through the command palette, `/env`, and a contextual top-bar **Actions** group. The top bar keeps one permanent overflow trigger rather than adding one button per task; native and HTML surfaces filter the shared command catalog to runnable `local-env:` commands and dispatch the original command ID, so no execution or safety path is duplicated. Symlinks and resolved paths must stay inside the selected project root. Optional JSON sidecars next to each script, such as `.quillcode/actions/bootstrap.json`, may provide `title`, `description`, `order`, bounded `environment` metadata, a project-relative `workingDirectory`, and bounded `timeoutSeconds`; they cannot override which script executes. Environment keys must be ASCII shell-style identifiers, values are length-limited and single-line, and only key names enter command search so values do not become visible UI metadata. Working directories must exist, resolve inside the project root, and are passed as structured workspace-relative `cwd` tool arguments. Environment overrides and timeouts are passed as structured `host.shell.run` arguments rather than shell-quoted command prefixes. Transcript/tool-card payloads preserve environment key names but redact values; reruns use current project action metadata instead of recovering secrets from thread history. Actions run through `host.shell.run` so they are transcripted and governed by the same tool-card path as agent shell commands. Direct shell `cwd` arguments are also normalized and rejected unless they resolve inside the selected workspace; direct shell `timeoutSeconds` values use the same 1-1800 second bounds, and direct shell `environment` overrides use the same key/value policy.
- Browser preview starts as workspace state and surface contract, not a platform WebView embedded directly in the app module. `WorkspaceBrowserLocationResolver` normalizes `http`, `https`, `file`, localhost, domain shorthand, absolute files, and project-relative file targets, while the model owns history mutation, snapshot refresh, and comment side effects. UI/harness surfaces provide the address bar, browser comments, Back/Forward/Reload snapshot-history controls, and an instant bounded metadata snapshot. Local HTML snapshots extract title, first heading, simple element counts, a visible element outline, and a bounded text snippet; reachable `http`/`https` pages can then upgrade the snapshot through a bounded HTML fetch behind a `BrowserPageFetching` adapter. Fetch failures keep the metadata snapshot and add a detail note rather than breaking the preview. Browser navigation history intentionally tracks model-level preview snapshots and truncates forward history on new opens; native rendering, live DOM session history, and richer live DOM inspection adapters should live behind a platform/browser adapter layer later. Every snapshot carries explicit inspection depth (`metadata_only`, `file_metadata`, `static_html_snapshot`, `network_html_snapshot`, or future `live_dom_snapshot`) so the UI and `host.browser.inspect` tool do not overclaim what was inspected.
- The macOS top-bar widget starts as a native SwiftUI `MenuBarExtra` over the same desktop controller as the main window. It displays current workspace/model/mode/status/Computer Use state and routes quick actions back through the shared controller so menu-bar behavior does not fork app state.
- Computer Use platform code lives in `QuillComputerUseKit`. Backend selection also lives in the kit through `ComputerUseBackendFactory.platformDefault()`: macOS installs the native screen-capture/Accessibility-backed adapter, Linux installs a helper-backed adapter when the detected graphical session has the required tools (`grim` + `ydotool`/`wtype` on Wayland, `import`/`scrot` + `xdotool` on X11), and unsupported or under-provisioned platforms share the same unavailable backend with actionable helper/status copy. The desktop app owns a backend instance, but the workspace surface receives only `ComputerUseStatus`, so UI labels stay platform-neutral and permission-specific (`Needs Screen Recording`, `Needs Accessibility`, ready, or a platform capability reason) without app-target conditionals. Settings owns the permission-onboarding card, while desktop handles macOS System Settings URLs behind shared `WorkspaceCommandSurface` command IDs. Agent tool execution overrides are async so Computer Use screenshot/input calls can run through the same structured tool-card path as shell/MCP without blocking platform APIs. Screenshot tool cards store images as artifacts and keep stdout metadata-only so transcripts stay responsive.
- Stop All is owned by the desktop controller because that is where native send and terminal tasks are created. The workspace model exposes a platform-neutral `cancelActiveWork()` state transition, and terminal execution has a cancellable async shell path that terminates the active child process.
- Terminal command history entries carry explicit `running`, `done`, `failed`, and `stopped` lifecycle state. Stop All and terminal-local Stop update running entries in place instead of deleting them, so replayed surfaces never imply a command is still active after cancellation.
- Terminal Clear history is intentionally session-preserving: it only removes finished scrollback, keeps the pane visible, preserves the selected project's terminal cwd and environment deltas, and refuses to clear while a command is running. The same action is available from the pane, command palette, and `/terminal clear`.
- Context pressure warnings use a conservative local estimate until the TrustedRouter streaming runtime reports exact model token usage. The banner is reconstructed from the selected thread surface, offers New thread and Fork from last commands, and the fork copies only the latest user turn onward so users can keep momentum without carrying the whole transcript.
- Context fork choices stay visible in the pressure banner instead of hiding behind an overflow menu. `fork-from-last` remains the lightweight default, `fork-with-summary` creates a deterministic summary plus the latest visible turn, and `fork-full-context` carries the whole visible transcript; all three use the same thread creation engine and continue to hide internal tool-continuation messages.
- Context compaction and `fork-with-summary` use a runtime-provided `WorkspaceContextSummaryGenerating` service. TrustedRouter runtimes install an LLM-backed summarizer that asks for a `say` action with no tools, while mock/offline runtimes keep the deterministic summary. If model summarization fails, the thread creation engine falls back to deterministic text rather than blocking recovery from context pressure.
- Context summary source and fallback are replayable thread events. The source thread records model-summary completion or deterministic fallback, and the created continuation thread stores a bounded `WorkspaceContextSummaryTelemetry` payload with `model` vs `deterministic_fallback`, summary length, and redacted failure diagnostics. This keeps context recovery auditable in Activity without coupling UI surfaces to transient status copy.
- Sidebar pinned/recent grouping is computed from existing thread pin state instead of persisted as separate sections. That keeps pin/archive behavior cheap to replay and avoids migrations while matching Codex's visible pinned-chat affordance.
- Keyboard shortcuts are registered by command ID in `WorkspaceShortcutRegistry`. Surfaces use the registry for display labels, and the desktop menu resolves native SwiftUI shortcuts from the same registry so visible command names and actual bindings do not drift.
- Keyboard shortcut discoverability is also command-driven. `Keyboard shortcuts` is a first-class command with `Cmd+/`, and the sheet renders only commands that carry shortcut labels from `WorkspaceCommandSurface`; it does not maintain a separate shortcut table.
- Command palette ranking lives beside `WorkspaceCommandSurface`, with category and keyword metadata carried by each command. SwiftUI and the Playwright harness both consume that metadata so grouping, selected-row navigation, and shortcut/title/keyword matching stay aligned.
- Command palette mode prefixes are treated as discoverability shortcuts, not separate palettes. Empty palette search remains action-only, `>` scopes to workspace actions, `/` scopes to slash-command templates, and non-empty bare queries include both actions and slash commands. Selecting a slash entry inserts the command skeleton into the composer and refocuses the composer instead of executing an incomplete command.
- Slash commands should route to the same workspace actions as visible UI and the command palette whenever possible. `/terminal`, `/browser`, `/browser [target]`, `/worktrees`, `/pr`, and `/env [name]` now share model/tool paths instead of becoming a separate command system. Browser target opens use the same URL/file resolver as the address bar and `host.browser.open`; bare `/browser` remains a quick show/hide toggle.
- Slash command discovery uses `SlashCommandCatalog.swift` for `/help`, command-palette templates, and composer suggestions, while `SlashCommand.swift` owns parser control flow and structured tool-call construction. The catalog suggests only commands the workspace model can execute or prepare today; transient presentation-only actions such as active Find stay in visible buttons, shortcuts, and the command palette until there is a model-to-view presentation request channel. Suggestions are keyboard-first: arrow keys move the active row, Enter accepts incomplete suggestions while exact commands still submit, and Tab always accepts the active suggestion.
- Structured pull request review-thread actions must be discoverable through the same visible command surfaces as older PR actions. `WorkspaceGitCommandCatalog`, `SlashCommandCatalog`, `WorkspaceCommandPlan`, and `QuillCodeCommandIconCatalog` carry `review-reply`, read-only `review-threads`, and `review-thread` rows so users can discover IDs, reply, and resolve without memorizing raw tool names.
- Tool results produce two different views: the tool card keeps the full structured raw output, while the assistant chat bubble contains a human final answer for common actions and truncates very long output. This avoids the QuillConnect failure mode where users see raw JSON/cards but no clear answer.
- Tool cards carry an explicit shared density contract: queued and running cards use `peek`, successful completed cards use `collapsed`, and failed or safety-review cards use `expanded`. Renderers may still keep raw JSON in the DOM/surface for copy and diagnostics, but the first visual read should prioritize the conversation and task result over transport data.
- Agent runs publish incremental thread snapshots through an async progress callback. `WorkspaceAgentSendProgressPlanner` owns the live-progress acceptance rule and UI status planning, so only snapshots for the original run thread update the workspace while user turns, live TrustedRouter streaming status, safe assistant drafts, queued tools, running tools, safety blocks, and final results remain visible before the full run returns. TrustedRouter action text is consumed as a stream, and only structured `say` action text is allowed into the transcript before finalization; tool JSON stays hidden until it becomes a normal tool card.
- Agent turns can run a bounded sequence of tools before returning the final assistant answer. Each completed tool step appends a hidden `tool` role message containing compact structured feedback for the next model step, with a duplicate-call guard and max-step limit to prevent loops. Renderers, sidebar search, fork-from-last, and context compaction hide those continuation messages so multi-step reasoning does not pollute the visible chat.
- TrustedRouter action parsing is canonical but forgiving. The system prompt still requires exact tool names and schema keys, and live action/safety calls request JSON-object responses from the API. The parser normalizes common near-miss aliases such as shell `command` to `cmd`, file `filename` to `path`, and file `text` to `content`, and it can recover the first valid QuillCode action object when cheap models prepend prose before JSON. This prevents obvious model-format slips from becoming empty-command failures while keeping tool cards on the canonical QuillCode schema.
- Transcript rendering is chronological and event-driven. `TranscriptTimelineItemSurface` interleaves user messages, tool cards, safety checks, and assistant answers from the thread event log so renderers never concatenate all messages first and all tools afterward.
- Tool-result artifacts are first-class card metadata derived from `ToolResult.artifacts`. SwiftUI, static HTML, and the Playwright harness render them as compact file/URL chips while preserving the full raw JSON output. Labels are filename-based for local paths and host-plus-path for web URLs so PR links, created files, and generated media stay scannable without tool-specific rendering branches. Local source/text artifacts also render bounded UTF-8 previews with extension, byte, line, and binary guards so ordinary created/read files are inspectable without opening raw JSON. Image-like artifacts (`file`, `http`, `https`, and inline `data:image/...`) render bounded visual previews with shared `Image · EXT`, filename, and source-detail metadata below the chips so screenshots and generated images feel like first-class Codex-style artifacts without making every tool card a custom view. Appshot bundles (`.appshot` and `.appshot.json`) use the structured artifact-preview path instead of raw JSON text previews so UI captures get a stable Appshot card with type, source detail, and open link.
- Successful tool cards should optimize for the user's task result, not raw transport data. Artifact previews stay visible, while raw input/output JSON lives behind a details disclosure by default; failed and safety-review cards open details by default so debugging and review remain immediate.
- Native SwiftUI tool cards use a stable header rhythm: icon, verb/target title, execution-context chip, and semantic status badge are grouped into a fixed-height header; completed cards use a quieter stroke plus a thin success rail; and raw input/output blocks are capped with two-axis scrolling. This keeps ordinary successful runs scannable while preserving copyable detail for debugging.
- A Claude CLI design pass reinforced the same first-read rule for the Codex-like UI: tool and approval cards should lead with verb plus target, stay collapsed to one or two lines by default, expose persistent approve/reject/edit actions, use risk-colored iconography, and keep exact commands/diffs copyable in monospace when expanded. Workspace chrome should keep model, project, branch, thread, and connection state persistent, while visual tests should cover streaming scroll anchoring, input latency during generation, tool-card expand/collapse reflow, and cold-start-to-first-token timing.
- Transcript scroll intent is a first-class UX invariant. Re-rendering the workspace should preserve the user's current document/timeline scroll position when they are reading earlier messages, but stay pinned to the bottom when they were already at the bottom before new messages, tool cards, or streaming events append.
- The Activity pane is a derived read-only surface over the selected thread's event log, tool cards, active instructions, memories, artifacts, and latest assistant answer. It intentionally does not persist a second mutable task list, so SwiftUI, static HTML, Playwright, transcript replay, and future agent state stay aligned from one source of truth.
- Activity task plans can now be model-authored through a structured `host.plan.update` tool. Successful plan updates are stored as normal tool-completed thread events, and the Activity pane prefers the newest successful authored plan before falling back to the deterministic five-step summary. This preserves one replayable event-log source of truth while letting the model show Codex-style task intent.
- Activity pane sections are first-class shared surface records with stable section IDs and `activity-toggle-section:*` command IDs. The model owns collapsed section state, while SwiftUI, static HTML, and Playwright only render the section contract and dispatch commands, keeping future task planning and handoff summaries from forking per renderer.
- Activity handoff summaries can now be model-authored through a structured `host.handoff.update` tool. Successful handoff updates are stored as normal tool-completed thread events, and the Activity pane prefers the newest successful authored handoff before falling back to deterministic derived text. This keeps handoff state replayable from the event log while allowing Codex-style continuation summaries when the model has richer task context.
- Subagent progress starts as a replayable Activity event contract, not hidden scheduler state. The structured `host.subagents.update` tool records the visible status of explicitly requested parallel-agent workflows as normal tool-completed thread events, and the Activity pane projects the newest successful update into a Subagents section. Future real worker execution should emit the same schema so SwiftUI, static HTML, Playwright, and transcript replay stay aligned.
- The first real subagent runtime uses that same event contract. `/subagents objective | Name: role` parses a bounded explicit worker list, `WorkspaceSubagentScheduler` fans out injectable workers with Swift task groups, and `WorkspaceSubagentSlashCommandRunner` records queued/running/completed progress through `host.subagents.update` tool events before adding a concise assistant summary. Model-backed worker sessions should plug into the scheduler's worker closure instead of adding a second progress channel.
- Active agent runs expose cancellation in the composer, not only through the top bar. While the agent is running, Send becomes a visible Stop button that routes through the same `stop-all` command path as the top bar. A stopped queued/running tool is closed as a failed `Stopped by user` card before the cancellation notice so transcripts never leave a tool visually running forever.
- Transcript copy actions live beside messages and tool cards rather than inside the primary content. The shared SwiftUI surface accepts a platform-neutral copy callback, while desktop owns the pasteboard adapter and a short `Copied` status. Static HTML and the Playwright harness render the same affordance so UX regressions are testable.
- User-message reuse is a composer draft action, not transcript mutation. `Use as draft` copies a prior user turn into the composer and focuses it, preserving the event log while giving users a Codex-like way to revise or rerun a request.
- Empty-state starter cards are direct actions, not draft presets. They still route through the normal composer send path by placing their prompt in the draft and submitting on the next main-queue turn, so first-run suggestions feel immediate while message-level `Use as draft` remains the explicit edit-before-rerun affordance.
- Assistant response feedback controls are intentionally absent. QuillCode does not send thumbs-up/down ratings anywhere, so transcript actions stay focused on local utility: Copy, Use as draft, Revert this turn's edits, and Retry. Historic `messageFeedback` events may remain readable in old threads but are ignored by current transcript surfaces.
- Assistant Retry is shown only on the latest assistant response and dispatches the existing `retry-last-turn` command. This keeps the visible action Codex-like while preserving the normal composer path for slash handling, tool dispatch, safety review, persistence, and cancellation.
- Workspace check automations share the same deterministic quick-schedule and natural-language schedule parser as thread follow-ups. Visible buttons, command palette entries, and `/workspace-check ...` all persist concrete `nextRunAt` values through one workspace-schedule creation path. Simple recurrence (`hourly`, `daily`, `weekly`, and `every N minutes/hours/days/weeks`) is persisted on the automation record and advances `nextRunAt` after each run.
- TrustedRouter runtime failures normalize into a shared `RuntimeIssueSurface` rather than renderer-specific strings. `WorkspaceRuntimeIssueBuilder` owns failure classification and diagnostics. The top bar, menu bar, settings sheet, static HTML renderer, and Playwright harness consume the same severity/title/message/action data for missing sign-in, missing developer key, rejected key, rate limits, provider outages, network failure, empty response, malformed model actions, and generic run failures. Local provider-outage diagnostics include the selected provider plus any parsed 5xx status code or request ID; live provider-health polling remains deferred until TrustedRouter exposes a stable status surface.
- Runtime issue retry is a command, not a view-only callback. The Retry action prepares the latest non-empty user turn from the selected transcript and submits it through the normal composer path, so slash commands, tool dispatch, safety review, persistence, and future telemetry stay identical to a user pressing Send again.
- Runtime issue recovery actions should take the user directly to the corrective control. Malformed model/tool responses and provider rate limits use `Switch model` to open the same searchable composer model picker and focus model search, instead of introducing a second recovery modal or leaving the user to find the picker manually.
- Runtime key detection is shared by runtime creation and catalog refresh. Env-provided `TRUSTEDROUTER_API_KEY`/`QUILLCODE_API_KEY` and stored delegated/developer keys both count as catalog-refresh credentials, so live smoke, developer override, and OAuth sign-in keep the same model-picker freshness behavior.
- Runtime issue recovery routing lives in `RuntimeIssueRecoveryPlanner`. Views render the action returned by the planner, while the planner owns which action labels map to Settings, Retry, or the model picker and filters out disabled command targets. This keeps sign-in/key/rate-limit/network recovery behavior testable without opening a SwiftUI workspace.
- Model picker presentation is built by `WorkspaceModelCatalogSurfaceBuilder`. It owns label/category construction, selected/default badge comparison, favorite/recent deduping, current-model fallback insertion, and row badge construction; `WorkspaceSurface.swift` only supplies catalog/config/thread-history inputs and consumes the finished label/categories.
- Top-bar and model-picker surface contracts live in `QuillCodeTopBarSurface.swift`. `TopBarSurface`, model category rows, model metadata rows, option compatibility decoding, option metadata copy, and searchable model filtering stay beside the top-bar/model-picker UI boundary; `WorkspaceSurface.swift` should only carry the aggregate `topBar` payload and assemble it through the focused catalog builder.
- Command palette presentation is built by `WorkspaceCommandSurfaceBuilder`. `WorkspaceSurface.swift` supplies selected thread/project/sidebar/runtime facts, `WorkspaceCommandSurfaceBuilder` owns command rows, categories, availability, and search keywords, and `WorkspaceCommandPlan` remains the separate action reducer that maps command IDs to model mutations and tool dispatch.
- Review diff presentation is built by `WorkspaceReviewSurfaceBuilder`. `WorkspaceSurface.swift` supplies tool cards and thread events, while the builder owns latest successful `host.git.diff` selection, diff parsing, file/line review comment attachment, timestamp ordering, and line-kind filtering.
- Context pressure presentation is built by `WorkspaceContextBannerBuilder`. `WorkspaceSurface.swift` supplies the selected thread, while the builder owns empty-thread hiding, context estimate calculation, warning thresholds, full-context copy, and New/Fork/Compact command surfaces.
- Transcript projection is built by `WorkspaceTranscriptSurfaceBuilder`. `WorkspaceModel` supplies selected threads and enriches project execution context after projection, while the builder owns visible message filtering, feedback reduction, tool-card construction, safety-review cards, artifact projection, and message/tool timeline interleaving.
- Transcript surface contracts live in `QuillCodeTranscriptSurface.swift`. `TranscriptSurface`, timeline rows, `ContextBannerSurface`, `MessageSurface`, and `ComposerSurface` own empty-state copy, timeline IDs, compatibility decoding, message accessibility labels, sendability, and slash suggestions; `WorkspaceSurface.swift` should only carry the aggregate transcript/context/composer payloads and assemble them through the focused builders.
- Runtime issue diagnostics are generated from current runtime state, not hardcoded per error. Settings shows the API base URL, authentication mode, key state, model, agent status, rate-limit metadata when present, and a redacted last-error snippet when present. Secret-like `sk-...` and bearer tokens are redacted before they reach the surface.
- Context pressure recovery is a thread action, not only a warning. The first compaction path creates a new `Compact:` thread that preserves project/mode/model/instructions/memories, adds a bounded assistant summary of older turns, and keeps the latest actionable turn. This keeps behavior deterministic while leaving room for a TrustedRouter-backed compactor later.
- Thread archive is reversible and distinct from delete. Archived chats move to an Archived sidebar section, remain searchable, and can be unarchived back into the active thread list. Delete removes the thread from memory and the JSON thread store. Rename uses an explicit title field in the native UI, while duplicate creates an unpinned active `Copy:` thread that preserves the transcript and event audit.
- Thread lifecycle mutations live in `WorkspaceThreadLifecycleEngine`. The workspace model owns stores, selected-project validation, terminal sync, and top-bar refresh, while the engine owns rename trimming, pin toggles, single and bulk archive/unarchive state, delete removal, newest-thread fallback selection, and agent-run thread upsert/fallback-selection decisions.
- Thread creation records live in `WorkspaceThreadCreationEngine`. New chat, fork, compact, and duplicate construction share one value boundary, while `WorkspaceModelThreads.swift` stays the thin creation coordinator. Created-thread insertion, composer draft switching, selected-thread updates, project touch, terminal sync, and top-bar refresh live in `WorkspaceModelThreadSelection.swift`; rename/pin/archive/unarchive/delete side effects live in `WorkspaceModelThreadLifecycleActions.swift`. Fork and compact still delegate visible-message slicing and compact-summary copy to `WorkspaceThreadSeedBuilder`. Model-backed fork/compact continuation orchestration, context-summary requests, fallback recording, and continuation telemetry live in `WorkspaceModelContextContinuations.swift` so ordinary thread lifecycle APIs do not own asynchronous summary work.
- Sidebar bulk selection is transient workspace state, not persisted thread metadata. `WorkspaceSidebarSelectionEngine` owns activation, clear, select-all, toggle, stale-ID pruning, and sidebar-order resolution. `WorkspaceSidebarBulkActionPlanner` owns selection-only command planning, visible-order target resolution, and post-mutation selection intent. `WorkspaceModel` stores selection state, applies the planned side effects, and persists thread/project changes. Rows expose `isBulkSelected` through the shared `WorkspaceSurface`, and bulk operations are command IDs (`thread-bulk-*`) just like single-thread actions.
- Sidebar and project surface contracts live in `QuillCodeSidebarSurface.swift`. Project rows, thread rows, action labels, action IDs, bulk command IDs, search filtering, pinned/recent/archived grouping, and compatibility decoding stay beside the SwiftUI/HTML sidebar boundary; `WorkspaceSurface.swift` should only carry aggregate `projects` and `sidebar` payloads assembled from model state.
- Sidebar command presentation has one source of truth in `QuillCodeSidebarCommandPresentation`. It owns visible primary/sidebar utility command ordering plus a single command metadata table for display labels, native SF Symbol overrides, HTML icon tokens, and Playwright test IDs so the SwiftUI sidebar and static HTML harness cannot drift as the Codex-like rail evolves.
- Project row actions mirror thread row actions: the rail stays scannable, and New chat, Refresh context, Rename, and Remove from list live behind an ellipsis menu plus matching command-palette and slash routes. Removing a project forgets the project registry entry and detaches chats from that workspace root, but it never deletes files or thread transcripts.
- Project connections are typed metadata, not path string conventions. Local projects use `Local`; registered SSH projects use `SSH Remote` everywhere in sidebar badges, command-palette titles, slash suggestions, and disabled-action explanations. SSH Remote rows can be registered with `/ssh user@host:/path` or `Project: Add SSH Remote...`. The first remote executor is noninteractive SSH: integrated-terminal commands, agent-authored `host.shell.run`, bounded `host.file.read`/`host.file.list`/`host.file.write`, `host.apply_patch`, `host.git.status`/`host.git.diff`, file/hunk `host.git.stage`/`host.git.restore`, `host.git.commit`, `host.git.push`, `host.git.pr.create`/`view`/`checks`/`checkout`/`comment`/`review`/`reviewers`/`labels`/`merge`, and `host.git.worktree.*` calls run through `ssh -T -o BatchMode=yes` from the selected remote root. SSH Remote projects intentionally offer the agent only remote-safe base tools (`host.shell.run`, bounded file read/list/write, apply-patch, git status/diff/stage/restore/commit/push/PR/worktree, plus app/plan/browser-style tools); environment tools are withheld until remote adapters exist, and unexpected local-only tool calls fail in the transcript instead of falling back to the desktop workspace.
- SSH Remote project tool execution lives in `WorkspaceRemoteProjectToolExecutor.swift`. The workspace model owns selected-project orchestration and transcript side effects, while the executor owns the remote-safe tool catalog, agent override construction, command construction, path normalization, artifact labeling, and unsupported-tool errors. Future QuillCloud relay or alternate remote transports should add an adapter behind this boundary instead of adding remote command branches back to `WorkspaceModel.swift`.
- SSH Remote context refresh is a read-only SSH probe, not a sync layer. It reads bounded `AGENTS.md`, `.quillcode/rules.md`, `.quillcode/instructions.md`, and project `.quillcode/memories` files from the remote root into the normal project/thread context models, using hex-encoded records so paths and content with spaces survive the shell transport. Direct remote file read/list/write is limited to normalized project-relative paths through the SSH executor; remote file listing uses a POSIX shell transport and returns the same bounded `FileListToolOutput` JSON as local listing so UI, final answers, and artifact previews stay transport-neutral. Remote apply-patch reuses the same unsafe diff-path scan and then runs `git apply --check` before `git apply` remotely. Remote hunk stage/restore reuses the git patch path-mismatch scan and `git apply --check` before applying over SSH. Remote commit trims and validates commit messages before running `git commit -m`; remote push reuses the local git-name validator for explicit refs and validates discovered current branches before pushing; remote PR creation delegates to the remote GitHub CLI after validating base/head refs; remote PR read/check/checkout/comment/review/reviewer-update/label-update/merge operations delegate to `gh pr view`, `gh pr checks`, `gh pr checkout`, `gh pr comment`, `gh pr review`, `gh pr edit`, and `gh pr merge` after validating selectors, checkout branch names, review actions, reviewer names, label names, merge methods, and body requirements; remote worktree create/open/remove uses the same sibling-of-project path boundary and verifies open/remove targets with remote `git worktree list --porcelain`. Plugin and local-environment actions still need explicit remote adapters rather than local fallbacks.
- Execution context is shared surface metadata, not renderer guesswork. Project-bound tool cards and terminal history entries carry an optional `ExecutionContextSurface`; local contexts stay visually muted, while SSH Remote contexts render a compact chip plus a thin left rail in SwiftUI, static HTML, and the Playwright harness. This keeps old transcript scrollback clear even after the user switches projects and leaves room for future QuillCloud/relay contexts to reuse the same contract.
- Tool-card execution-context enrichment lives in `WorkspaceExecutionContextSurfaceBuilder`. The workspace model supplies selected-project and project-list state, but the builder owns thread-project fallback, project-execution tool classification, and timeline/tool-card enrichment so future relay or remote context metadata does not spread through model mutation code.
- Runtime issue and execution-context surface contracts live in `QuillCodeRuntimeSurface.swift`, not in the aggregate `WorkspaceSurface.swift`. `WorkspaceSurface` should keep only the composed `runtimeIssue` payload and delegate construction to runtime/execution builders, while renderers consume the shared severity, diagnostic, and execution-context records directly. Future QuillCloud relay or additional remote execution contexts should extend this contract file first instead of adding renderer-local enums.
- Fork, compact, and cancelled-send title seeding lives in `WorkspaceThreadSeedBuilder`. The workspace model owns thread creation, selection, stores, and top-bar refresh, while the builder owns visible-message filtering, latest-turn seed selection, compact summary formatting, and first-prompt title derivation. Prompt titles split on all whitespace so cancelled whitespace-only prompts cannot create invisible chat titles.
- SSH Remote terminal continuity uses marker metadata over the existing noninteractive shell stream. The remote wrapper captures baseline env, applies persisted terminal env deltas, runs the user command, then emits final cwd/env markers that are stripped before the entry is stored. This keeps the first implementation compatible with plain SSH while preserving `cd`, `export`, and `unset` across terminal commands.
- Terminal session contracts live in `WorkspaceTerminalState.swift`, terminal lifecycle reducers live in `WorkspaceTerminalEngine.swift`, and command wrapping/marker parsing live in `WorkspaceTerminalSessionAdapter.swift`. The workspace model owns async orchestration, project selection, persistence, and top-bar updates; the terminal state file owns command/session DTOs and execution-context payloads; the terminal engine owns state mutation; the terminal session adapter owns local/remote wrapping, shell quoting, marker parsing, cwd persistence, environment deltas, and marker cleanup. This keeps terminal continuity testable as local, SSH Remote, and future relay execution contexts grow.
- A second Claude CLI design pass emphasized persistent execution context, immediate tool-card feedback, low-drama safety states, and bounded long-output handling. Remote cards and terminal entries should visually inherit their execution context, queued tools should appear immediately, routine safety checks should stay neutral/green or low-amber rather than scary red, and long stdout should keep head/tail plus explicit expansion instead of pushing the user out of the conversation.
- A follow-up Claude CLI design pass prioritized native-feeling density over decorative chrome: unified local/remote execution-context pills in the composer and cards, thin state accent rails instead of full-card tinting, auto-collapsed successful tool cards, capped long stdout with explicit expansion, command-palette mode prefixes, debounced streaming repaints, and an `NSTextView`-grade composer for large pastes.
- Active-chat Find is ephemeral UI state. `Cmd+F` opens a transcript-local bar with focused input, counts, previous/next navigation, and active-result highlighting, but the query and selected result are not persisted to thread JSON because they are editor/navigation state rather than conversation state.
- Browser-harness UI polish follows the `make-interfaces-feel-better` checklist: root font smoothing, balanced headings, pretty short text, tabular dynamic numbers, 44px minimum hit areas, `scale(0.96)` press feedback, explicit transition properties, pure-white dark image outlines, and concentric panel radii. Playwright checks these primitives directly so visual quality does not depend on manual memory.
- The first-run empty transcript should feel connected to the composer, not like a disconnected landing page. A Claude CLI design critique called out the detached empty panel, missing sidebar affordance icons, placeholder Settings glyph, raw model-picker chevron, and weak empty heading. The HTML harness and SwiftUI shell now place the empty state in the flexible transcript region just above the composer, use explicit sidebar/action symbols, render Settings as a gear, and make the empty heading stronger while keeping the chrome Codex-like and quiet.
- Workspace chrome should stay Codex-like rather than dashboard-like. The persistent left rail exposes the same first-read actions as the Codex reference: New chat, Search, Plugins, and Automations. Command Palette, Terminal, Browser, Memories, Activity, and Settings live in a compact Tools/Settings footer instead of a second full-height nav list. Chats appear before Projects so recent work is the first scannable list, inactive bulk selection stays as a small Chats header action, model/mode live beside the composer where send-time decisions happen, and the main top bar uses one bounded overflow menu for Command Palette, Computer Use setup, Settings, and Keyboard Shortcuts while long project/context labels remain metadata. Stop remains a command and `Esc` shortcut, but the visible top-bar Stop button appears only while active work is running.
- Sidebar hierarchy uses progressive disclosure. The Chats header exposes one filter menu containing stable filters, saved searches, saved-search management, and the inactive Select chats command; selection mode replaces that command with one visible Done action. Thread rows show title plus compact relative activity, while model metadata stays available to search, accessibility, and hover help. Project rows show one identity line, keep full paths in accessibility/help, and use the whole row as the drag target instead of a permanent handle. Thread/project action menus stay visually quiet until hover, focus, selection, or open state while retaining their audited interaction geometry and clearance from neighboring controls. Native SwiftUI, static HTML, and the Playwright harness share this hierarchy.
- Mixed command-palette search prioritizes concrete workspace actions over slash-command templates. Prefixing the query with `/` scopes the palette to slash templates, so users can discover command syntax without plain searches like "checks" or "approve pr" returning insert-only commands ahead of executable actions.
- The sidebar's secondary tool surface is a single Tools disclosure plus a quiet Settings button. Terminal, Browser, Memories, Activity, and Command Palette are still one click away after opening Tools, but they no longer compete visually with the Codex-like primary navigation and thread list. Static HTML, SwiftUI, and Playwright share the same command IDs so this is a presentation simplification, not a second routing layer.
- The native composer is a separate SwiftUI control instead of another private block inside `WorkspaceSwiftUIView`. Composer focus, send/stop actions, slash suggestions, and keyboard navigation now stay together, and the suggestion rows follow the shared polish contract: 44 pt minimum hit area, `0.96` press feedback, bounded command chips for long slash syntax, and quiet inline keyboard hints.
- The native model picker is split by responsibility instead of living in the top bar or a single mixed picker file. `QuillCodeModelPickerView` owns the trigger, popover search text, search focus, keyboard highlight, empty/search states, and final model selection. `QuillCodeModelPickerRows.swift` owns category sections, option rows, favorite/detail actions, badges, expanded metadata, shared 44 pt hit targets, shared `0.96` press feedback, and middle truncation for long provider/model metadata. Approval mode stays in a neighboring composer control so model choice and autonomy stay separate.
- The native top bar is a separate SwiftUI control. Workspace layout owns where the chrome sits, while `QuillCodeTopBarView` owns thread identity, runtime status, and the bounded utility overflow. Model/mode access lives with the composer so send-time controls do not crowd the title row. The ellipsis uses the shared 44 pt hit target and `0.96` press feedback so the quiet Codex-like chrome still feels tactile.
- The native sidebar is a separate SwiftUI control. The workspace shell decides width and placement, while `QuillCodeSidebarView` owns primary navigation, thread sections, bulk selection, project rows, and the compact Tools/Settings footer. Sidebar commands still route through shared `WorkspaceCommandSurface` IDs, and high-frequency sidebar controls follow the same 44 pt hit target and `0.96` press feedback contract as other chrome.
- The native review pane is a separate SwiftUI control. `QuillCodeReviewPaneView` owns review summary, file rows, hunk rows, inline comments, range notes, and review action buttons, while the workspace shell only decides when the review surface appears. Review controls use the shared 44 pt hit target and `0.96` press feedback contract so diff-review actions stay compact but tactile.
- Desktop chrome routes are product-smoke tested through `quill-code-desktop --native-render-smoke`, not only by source parity gates. The smoke exercises the real desktop command planner/coordinator for Command Palette, Keyboard Shortcuts, Settings, Terminal, and Browser before the agent prompt runs, then records the top-bar state and command IDs in a rendered chrome evidence panel. Offscreen rendering of raw `MenuBarExtra` menu content is intentionally not used as proof because SwiftUI paints menu buttons as unavailable glyphs outside a real AppKit menu session; packaged-window/menu-bar click automation remains the next native coverage layer.
- Review surface contracts live in `QuillCodeReviewSurface.swift`. `WorkspaceReviewSurface`, file/hunk/line/comment rows, line/action enums, and stage/restore action records own review totals, labels, action IDs, and symbols; `WorkspaceSurface.swift` should only carry the aggregate `review` payload and assemble it through `WorkspaceReviewSurfaceBuilder`.
- Automations and Activity are separate surfaces. Activity is the current thread's live execution log: task plan, tools, sources, artifacts, and latest answer. Automations is for persisted or scheduled future work: thread follow-ups, workspace schedules, monitors, and later subagents. Planned workflow rows remain visible only when no configured automations exist, so the Automations pane can teach the shape of upcoming runtime work without inventing fake jobs.
- Automation records persist as a single `~/.quillcode/automations.json` array of `QuillAutomation` values. The workspace model loads those records at bootstrap and projects them into the Automations pane, falling back to planned workflow templates only when no jobs exist. The scheduler/runner is intentionally separate from this store so heartbeat, cron, monitor, and notification execution can be added without changing the visible surface contract.
- Automation management is command-driven. `automation-create-thread-follow-up` creates a persisted follow-up for the selected thread, `automation-create-workspace-schedule` creates a persisted schedule for the selected project, `automation-run:<id>` manually wakes runnable jobs, and row actions use `automation-pause:<id>`, `automation-resume:<id>`, and `automation-delete:<id>`. SwiftUI, static HTML, and Playwright render those command IDs from the same surface records instead of owning separate automation reducers.
- Recurring automations store an optional `QuillAutomationRecurrence` beside the next concrete run date. Interval schedules use `interval` plus `unit`; calendar schedules add optional normalized weekday and clock fields instead of introducing a second recurrence model or a storage migration. The runner always evaluates due jobs against a concrete `nextRunAt`, then advances recurring jobs from the scheduler's `now` instead of trying to catch up every missed interval. This keeps the first scheduler pass deterministic, avoids tight loops after sleep/offline periods, and lets parser-level grammar grow incrementally.
- Calendar recurrence parsing requires explicit recurring language (`every Monday at noon`) or plural recurring terms (`weekdays at 6 PM`, `fridays at 1 PM`). Bare weekday phrases such as `Friday afternoon` remain one-off schedules, which keeps natural-language automation predictable and avoids surprising weekly jobs.
- Due automation execution is conservative. The desktop app runs a launch-time and periodic tick that wakes active thread-follow-up, workspace-schedule, and configured monitor automations with a concrete `nextRunAt` in the past. Thread follow-ups create selected follow-up threads from the original conversation. Workspace schedules create selected `Scheduled check: ...` threads that seed a project-status prompt with the selected project's instructions and memories. Monitors create selected `Monitor: ...` threads from their watch condition and optional project context, leaving actual agent execution explicit and auditable. Event monitors can also carry a structured file-change source: local project-relative paths are resolved inside the project root, absolute paths are allowed for explicit machine-local monitors, remote-relative paths are rejected until SSH/relay event adapters exist, and the trigger description is recorded in the generated monitor thread. Full cron syntax, broader event-source adapters, and subagents remain separate milestones.
- Due runnable automations emit `AutomationRunReport` values from the platform-neutral workspace model. The desktop adapter consumes those reports through a small notification boundary: macOS posts local `UserNotifications`, silently no-oping when notification permission is denied, while Linux selects `LinuxAutomationNotifier` from `DesktopAutomationNotifierFactory` and delivers through the platform-neutral `notify-send` argv planner plus isolated `LinuxNotificationCommandRunner` in `QuillCodeApp`. Notification text stays separate from process launching, and the runner calls `/usr/bin/env notify-send ...` without shell interpolation so fake-helper tests can prove the exact argv. Richer notification controls stay separate.
- Scheduled follow-up creation started with explicit quick actions. The Automations pane and command palette can create selected-thread follow-ups for 10 minutes, 1 hour, or tomorrow at 9:00 AM, each persisted with a concrete `nextRunAt`. This keeps the scheduler testable while richer recurrence parsing grows in separate slices.
- Natural-language follow-up scheduling is deterministic before it is broad. `/follow-up ...` and `/workspace-check ...` support relative delays such as `in 30 minutes`, today/tonight/tomorrow clock phrases, upcoming weekdays such as `Friday afternoon`, interval recurrence such as `daily` or `every 2 hours`, and wall-clock calendar recurrence such as `daily at 9 AM`, `weekdays at 6 PM`, `weekends at 10 AM`, and `every Monday at noon`, then store the same concrete `nextRunAt` as quick actions. Full cron syntax, locale-heavy calendar phrases, and LLM-assisted parsing remain deferred.
- Model picker favorites are explicit user preferences stored as ordered repeated `favorite_model` entries in `~/.quillcode/config.toml`. Favorites render before Recents, stay editable from the picker star control, and are deduplicated before they reach the surface.
- Model picker recents are derived from actual thread history instead of a separate preference store. The picker prepends a Recent section only when there is history, excludes favorite models from Recents, badges current/default/recommended/favorite state on rows, and suppresses Favorites/Recent duplicates during ordinary search unless the user explicitly searches for `favorite` or `recent`.
- Project-local extension manifests stay bounded and explicit. QuillCode scans `.quillcode/plugins/*.json`, `.quillcode/skills/*.json`, and `.quillcode/mcp/*.json` with byte/count caps, rejects symlinks and paths outside the selected project root, persists the metadata on `ProjectRef`, and surfaces it through the Extensions pane, command palette, static HTML renderer, Playwright harness, and macOS menu bar. Bundled marketplace entries may add small discoverable records such as BurstyRouter, but project-installed manifests and project marketplace records with the same ID shadow bundled records. MCP stdio servers can be started and stopped only through explicit user commands, use structured `command` plus `args` fields instead of shell splitting, and record session notices. A started MCP server must pass a bounded `initialize` and `tools/list` probe before the UI shows Ready, and only Ready servers expose callable tools to the agent.
- Project extension directory selection must go through `ProjectExtensionManifestLoader.manifestDirectory`. Loader callers pass relative directory contracts, not resolved URLs; the loader rejects absolute paths, `.`/`..` components, symlink escapes, and out-of-root resolved directories before reading any manifest files.

- Extension update lifecycle is manifest-owned and auditable. A manifest may declare optional `version`, `source` or `homepage`, `updateCommand`, and `updateTimeoutSeconds` fields. QuillCode shows that metadata in the Extensions pane and command palette, and `Update <extension>` runs the declared command as a normal `host.shell.run` tool card before refreshing project metadata. This keeps early plugin/skill/MCP updates reviewable and project-local while leaving signed remote marketplace install/update for a later milestone.
- MCP tool execution starts with one generic `host.mcp.call` tool instead of generating a dynamic app tool for every remote MCP tool. The generic tool description lists Ready server IDs plus advertised tool names, and runtime execution rejects calls to non-running servers or tools absent from the latest `tools/list` result. This keeps the UX bounded and explainable while preserving room for richer per-tool schemas, resource handling, prompts, streaming results, and signed remote marketplace lifecycle later.
- MCP tool schema metadata is summarized, not replayed as arbitrary JSON. The probe stores bounded tool descriptors with name, description, required/optional argument names, and compact type summaries from `inputSchema`. Extensions UI and the dynamic `host.mcp.call` description consume the same descriptors so users and models see required arguments without generating one QuillCode tool per MCP tool or persisting unbounded schemas.
- MCP resource and prompt discovery now feeds read-only agent tools. If a server advertises `resources` or `prompts` in `initialize`, QuillCode performs bounded optional `resources/list` and `prompts/list` probes, stores resource display names plus URIs, surfaces the counts and first names in Extensions, and ignores probe failures so an otherwise healthy MCP server is not hidden. Ready servers expose `host.mcp.resource.read` and `host.mcp.prompt.get` only for advertised resource identifiers and prompt names, keeping resource/prompt consumption read-risk and separate from append-risk generic `host.mcp.call`.
- Shared visual primitives live in `QuillCodeDesignSystem.swift`, not in individual feature views or the workspace shell. Palette constants, hit-target metrics, `0.96` press feedback, animation helpers, reusable surfaces, and image outlines should be extended there first so extracted SwiftUI controls stay visually consistent without depending on `WorkspaceSwiftUIView.swift`.
- Transcript message controls live in `QuillCodeTranscriptMessageView.swift`. User and assistant message bubbles, retry/use-as-draft/revert actions, and the shared transcript copy button should evolve there; `WorkspaceSwiftUIView.swift` should only decide where timeline items are placed. Tool-card and artifact-preview rendering remains the next transcript family to extract.
- Tool-card composition lives in `QuillCodeToolCardView.swift`, while its subfamilies have focused owners: `QuillCodeToolCardControls.swift` owns action rows, status badges, and shared execution-context chips/rails; artifact preview rendering is split across `QuillCodeArtifactChip.swift`, `QuillCodeArtifactTextPreview.swift`, `QuillCodeArtifactDocumentPreview.swift`, and `QuillCodeArtifactImagePreview.swift`; `QuillCodeToolCardDetailsView.swift` owns raw JSON detail blocks. `WorkspaceSwiftUIView.swift` should only decide where timeline items are placed and how copy actions are wired.
- Settings sheet ownership is split by role. `QuillCodeSettingsView.swift` owns the sheet shell and authentication controls, `QuillCodeComputerUseSettingsCard.swift` owns Computer Use permission onboarding, `QuillCodeRuntimeIssueView.swift` owns the reusable diagnostics callout, and `QuillCodeSettingsDraft.swift` owns draft-to-update projection. `WorkspaceSwiftUIView.swift` should only present the sheet and apply the resulting settings update.
- Settings surface contracts are split by payload role. `QuillCodeSettingsSurface.swift` owns the aggregate
  `WorkspaceSettingsSurface` contract and backwards-compatible decoding, `QuillCodeComputerUseSettingsSurface.swift`
  owns Computer Use requirement rows plus permission/approval copy, and `QuillCodeSettingsUpdate.swift` owns the
  settings mutation payload. `WorkspaceSurface.swift` should only carry the aggregate `settings` payload and pass
  current runtime state into it.
- Terminal and browser utility panes live in `QuillCodeTerminalBrowserPaneView.swift`. Terminal history rows, browser navigation, page snapshots, comments, and pane-local draft state should evolve there; `WorkspaceSwiftUIView.swift` should only decide when the panes are visible and route the resulting actions.
- Terminal surface contracts live in `QuillCodeTerminalSurface.swift`. `TerminalSurface` and `TerminalCommandSurface` own run/clear availability, cwd labels, command lifecycle labels, and execution-context propagation; `WorkspaceSurface.swift` should only carry the aggregate `terminal` payload and assemble it from terminal state.
- Secondary utility pane chrome lives in `QuillCodeSecondaryPanesView.swift`. Extensions, Memories, and Automations each have focused native view files: `QuillCodeExtensionsPaneView.swift`, `QuillCodeMemoriesPaneView.swift`, and `QuillCodeAutomationsPaneView.swift`. Automation create-menu routing lives in `QuillCodeAutomationCreateMenu.swift`, workflow card/action rendering lives in `QuillCodeAutomationWorkflowCard.swift`, and shared count/status pills and empty states should evolve in the chrome file; `WorkspaceSwiftUIView.swift` should only decide pane placement and route commands.
- Secondary pane surface contracts live in `QuillCodeSecondaryPaneSurface.swift`. `WorkspaceExtensionsSurface`, `WorkspaceMemoriesSurface`, `WorkspaceAutomationsSurface`, extension manifest rows, memory rows, and automation workflow rows should evolve beside the secondary-pane native and HTML renderers; `WorkspaceSurface.swift` should only carry the aggregate slots and assemble them from model state.
- Workspace modal presentation lives in `QuillCodeWorkspaceSheets.swift`, while each dialog family has a named owner: `QuillCodeCommandPaletteDialog.swift` owns command palette rows and icon mapping, `QuillCodeSearchAndShortcutDialogs.swift` owns chat search and keyboard shortcuts, `QuillCodeWorktreeDialogs.swift` owns worktree create/open/remove/prune sheet composition, `QuillCodeWorktreeDrafts.swift` owns worktree sheet value state and request projection, `QuillCodeWorktreeDialogChrome.swift` owns shared worktree choice/status rows and frame chrome, `QuillCodeWorkspaceDialogs.swift` owns rename sheets, and `QuillCodeDialogChrome.swift` owns general shared dialog header, section, empty-state, and labeled-field primitives. `WorkspaceSwiftUIView.swift` should only decide when sheets are presented and route completed actions.
- Workspace view command routing is planned by `WorkspaceViewCommandPlanner`. The planner owns command-ID to view-action mapping, selected thread/project rename lookup, worktree sheet intents, and composer focus rules. `WorkspaceSwiftUIView.swift` should execute typed `WorkspaceViewCommandAction` values and avoid growing another command-ID switch as Codex-parity commands expand.
- Sidebar row actions are planned by `WorkspaceSidebarRowActionPlanner`. The planner owns thread/project rename lookups and maps non-rename row menu choices to typed `WorkspaceThreadRowMutation` and `WorkspaceProjectRowMutation` values. SwiftUI should only open rename sheets or forward typed mutations, while the desktop controller should execute those mutations through `WorkspaceSidebarRowMutationExecutor` instead of switching over row action enums.
- Sidebar bulk actions are split into three layers: `WorkspaceSidebarSelectionEngine` owns selection state, `WorkspaceSidebarBulkActionPlanner` maps commands to mutation plans, and `WorkspaceSidebarBulkActionExecutor` applies those plans to thread/project selection values. `WorkspaceModel.swift` should keep persistence, terminal sync, and top-bar refresh side effects, but it should not inline pin/archive/delete mutation logic.
- Desktop app bootstrap lives in `QuillCodeDesktopApp.swift` and should remain declarative. Native commands, menu-bar layout, OAuth loopback capture, browser fetching, automation notifications, and controller orchestration live in separate desktop files. Parity gates intentionally scan the whole `Sources/quill-code-desktop` folder so extraction can continue without pushing implementation details back into scene composition.
- Desktop controllers should route UI and apply workspace state, not own protocol flows or cancellable task bookkeeping. TrustedRouter sign-in lives in `QuillCodeDesktopSignInCoordinator`, and send/terminal/browser/automation task slots live in `QuillCodeDesktopTaskCoordinator`. Parity gates check those boundaries so OAuth exchange and raw task IDs do not drift back into `QuillCodeDesktopController.swift`.
- Desktop settings persistence lives in `QuillCodeDesktopSettingsCoordinator`. The controller applies settings results and runtime refreshes, while the coordinator owns TrustedRouter key replacement/clear rules, OAuth account reset rules, and config persistence. macOS Computer Use System Settings URLs live in `MacSystemSettingsOpener`, keeping platform URL routing out of the controller and out of settings persistence.
- Desktop command planning lives in `QuillCodeDesktopCommandPlanner`, and typed command action dispatch lives in `QuillCodeDesktopCommandCoordinator`. The desktop controller plans a command, delegates dispatch, and keeps only the concrete UI/workspace capabilities that command actions invoke. Native-only command IDs such as Computer Use system-settings links and workspace-command fallbacks stay out of controller switches.
- Desktop transcript copy behavior lives in `QuillCodeDesktopCopyCoordinator`. The controller owns only the visible copied-item state, while the coordinator owns blank-copy rejection, pasteboard mutation through `QuillCodePasteboardWriting`, and the transient feedback duration. This keeps AppKit pasteboard details out of workspace routing.
- Desktop project import result handling lives in `QuillCodeDesktopProjectImportCoordinator`. The controller owns only SwiftUI importer presentation state, while the coordinator owns `fileImporter` result parsing, URL normalization, and real directory validation before the controller adds a project.
- Desktop project/thread navigation lives in `QuillCodeDesktopNavigationCoordinator`. The controller owns published UI state and refresh, while the coordinator owns new-chat, thread/project selection, rename routing, sidebar row action dispatch, and project creation calls into the workspace model.
- Desktop worktree routing lives in `QuillCodeDesktopWorktreeCoordinator`. The controller owns only refresh and published UI state, while the coordinator owns create/open/remove/prune calls, choice/prune-preview load request construction, async loading, and active workspace root fallback.
- Tool-card and artifact presentation models live in `QuillCodeToolCardSurface.swift`, not in `WorkspaceModel.swift`. `WorkspaceModel` may assemble tool cards from events, but status/density, artifact kind detection, document/image/text-preview metadata, and default expansion behavior are surface concerns with their own parity gate.
- Static HTML tool-card rendering lives in `WorkspaceHTMLToolCardRenderer.swift`. `WorkspaceHTMLRenderer.swift` remains the composition point for the Playwright/static harness, while artifact chips, text previews, image/document previews, raw detail blocks, and copy labels stay beside the tool-card HTML renderer. Shared HTML escaping and execution-context chip markup live in `WorkspaceHTMLPrimitives.swift` so terminal rows and tool cards cannot drift.
- Static HTML terminal rendering lives in `WorkspaceHTMLTerminalRenderer.swift`. `WorkspaceHTMLRenderer.swift` delegates terminal pane/entry markup and status-class mapping, while `WorkspaceHTMLPrimitives` remains the single source for escaping and execution-context chip markup shared by terminal rows and tool cards.
- Static HTML browser rendering lives in `WorkspaceHTMLBrowserRenderer.swift`. `WorkspaceHTMLRenderer.swift` delegates browser pane, preview, snapshot, outline, text snippet, and comment markup while staying responsible for only the whole-workspace harness composition.
- Static HTML secondary pane rendering uses `WorkspaceHTMLSecondaryPaneRenderer.swift` as a stable facade. `WorkspaceHTMLRenderer.swift` delegates Extensions, Memories, Activity, and Automations pane markup through that facade, while `WorkspaceHTMLExtensionsPaneRenderer.swift`, `WorkspaceHTMLMemoriesPaneRenderer.swift`, `WorkspaceHTMLActivityPaneRenderer.swift`, and `WorkspaceHTMLAutomationsPaneRenderer.swift` own their pane-specific markup. Shared secondary-pane count labels, escaping, and command-button forwarding live in `WorkspaceHTMLSecondaryPanePrimitives.swift`.
- Static HTML review rendering lives in `WorkspaceHTMLReviewRenderer.swift`. `WorkspaceHTMLRenderer.swift` delegates Git review pane, file, hunk, line, inline comment, and action markup while staying responsible for transcript placement.
- GitHub PR review-thread browse/select is also replayed from tool-card state. Completed `host.git.pr.review_threads` results feed the same review surface as diffs, while Resolve/Unresolve buttons execute `host.git.pr.review_thread` and immediately refresh `host.git.pr.review_threads`. The app does not keep a separate mutable PR-review session store; richer reply/edit composition should continue to append normal tool events and derive visible state from those events.
- PR review-thread replies are composed inline inside the review-thread row instead of drafting a slash command into the global composer. Posting still records normal `host.git.pr.review_reply` and follow-up `host.git.pr.review_threads` tool events, so transcript replay remains the source of truth. Reply, resolve, cancel, and post controls use the shared 44 pt hit-target helpers in SwiftUI and matching harness classes in Playwright.
- PR review submissions from the command palette open a structured review draft in the review pane instead of pre-filling the global composer. The draft records approve/comment/request-changes, optional selector, and review body; submit creates the existing `host.git.pr.review` tool call so local and SSH Remote routing remain shared with `/pr review`. When the visible diff has saved line/range review notes, the draft snapshots those notes into a pending inline-note queue, lets the user include, skip, and edit each note, validates that selected notes have text, posts each selected note through `host.git.pr.review_comment`, and only then submits the final review. Submit summaries and inline-note reordering are derived from the same draft state and surface action, target, body, inline-note counts, blocked/ready state, and selected comment order in SwiftUI, static HTML, and Playwright without becoming persisted state. Slash-command review submission remains available for fast typed workflows.
- Static HTML sidebar rendering lives in `WorkspaceHTMLSidebarRenderer.swift`. `WorkspaceHTMLRenderer.swift` delegates project rows, thread groups, bulk-selection controls, primary actions, and the tools/settings footer while staying responsible for whole-workspace shell composition.
- Static HTML top-bar rendering lives in `WorkspaceHTMLTopBarRenderer.swift`. `WorkspaceHTMLRenderer.swift` delegates title identity, status, runtime issue pill, Computer Use status, and overflow command markup while staying responsible for whole-workspace shell composition.
- Static HTML transcript rendering lives in `WorkspaceHTMLTranscriptRenderer.swift`. `WorkspaceHTMLRenderer.swift` delegates transcript empty state, context banner, runtime issue panel, review placement, message timeline rows, tool-card row handoff, and composer/model/mode markup while staying responsible only for composing the whole static harness document.
- Browser state and presentation contracts live in `QuillCodeBrowserSurface.swift`. `BrowserState`, `BrowserSnapshotState`, `BrowserCommentState`, `BrowserSurface`, `BrowserSnapshotSurface`, and `BrowserCommentSurface` evolve together; browser address resolution lives in `WorkspaceBrowserLocationResolver.swift`; and browser history/page/comment state transitions live in `WorkspaceBrowserEngine`. The workspace model owns async fetch orchestration, `lastError`, and top-bar refreshes, while reusable browser state contracts, URL-resolution rules, and pure state transitions stay focused and guarded by parity tests.
- Browser tabs are a state/surface contract, not a WebKit-only detail. `BrowserTabState` stores the same address/current URL/history/title/status/snapshot/comment projection as the selected browser page, `WorkspaceBrowserEngine` snapshots and restores that projection on tab create/select/close, and async browser fetch requests carry the originating tab ID so stale results cannot repaint a different selected tab. Visible browser adapters consume `BrowserSessionSyncSnapshot`, which filters navigable tabs and names the active tab without leaking AppKit/WebKit into the app model. Reverse visible-session updates use `BrowserSessionUpdate`/`BrowserSessionTabUpdate`, so the macOS WebKit presenter can report tab selection, title, and URL changes back into `WorkspaceBrowserEngine.applySessionUpdate` without desktop types entering the app model. The macOS visible session renders synchronized native WebKit tabs sharing the persistent browser profile; richer Linux/browser-process adapters should plug into the same snapshot/update seam.
- Review comment payload state and event planning live in `WorkspaceReviewCommentPlanner.swift`, not in `WorkspaceModel.swift`. The planner owns path/text trimming, visible review-file validation, line-range normalization, line-kind checks, summary copy, and payload encoding. The workspace model owns only selected-thread validation, event append, persistence, and top-bar refresh.
- Review action run planning lives in `WorkspaceReviewActionToolCallPlanner.swift`, not as extensions on review surface values or inline in `WorkspaceModel.swift`. The planner owns the canonical file/hunk stage and restore `host.git.*` argument shape, the mandatory follow-up `host.git.diff` refresh call, and final status derivation from action plus refresh results. The workspace model owns only executing the planned calls, recording tool cards, persistence, and top-bar application.
- Production Swift sources should avoid `try!`, `as!`, and force unwraps. Startup, OAuth sign-in, local project scanning, and extension discovery must fail through typed errors or ignored unsafe records rather than crashing the process. `ProjectExtensionManifestLoader` normalizes extension directories by safe path components and skips unsafe custom directories without blocking later valid directories.
- Agent action parsing keeps transport, JSON scanning, malformed-output recovery, and argument normalization separated. `TrustedRouterLLMClient` streams/collects actions, `AgentActionJSONExtractor` strips code fences and finds balanced JSON objects in prose, `AgentShellCommandRecovery` owns conservative explicit shell-command recovery, and `AgentActionJSONParser` owns action routing plus canonical tool argument validation.
- Agent tool execution override composition lives in `WorkspaceToolExecutionOverrideCombiner.swift`, not in `WorkspaceModel.swift`. The combiner owns the precedence order Plan, Remote Project, Browser, Computer Use, Memory, MCP, while the workspace model only creates each optional executor and assigns the combined override to the runner.
- MCP extension surface state lives in `QuillCodeMCPSurface.swift`, MCP tool/resource/prompt JSON request parsing lives in `WorkspaceMCPRequests.swift`, MCP subprocess lifecycle and session routing live in `WorkspaceMCPRuntime.swift`, concrete stdio launch/prober construction lives behind `WorkspaceMCPServerLaunching` in `WorkspaceMCPServerLauncher.swift`, stdio probe DTOs and errors live in `MCPStdioModels.swift`, MCP tool definitions live in `MCPToolDefinitions.swift`, stdio frame parsing lives in `MCPStdioMessageCodec.swift`, MCP stdio response/result mapping lives in `MCPStdioResultMapper.swift`, and Ready-server dynamic tool catalog generation lives in `WorkspaceMCPToolCatalog.swift`. `WorkspaceModel` owns selected-project manifest lookup, UI notices, top-bar status, and state application; surface labels, probe-summary compatibility, request aliases, nested-argument normalization, process/session launch seams, process handles, public MCP contracts, stdio framing, result mapping, and catalog text stay in focused helpers with parity gates.
- Workspace command IDs reduce through `WorkspaceCommandPlan` and execute through `WorkspaceCommandPlanExecutor` before touching `WorkspaceModel` side effects. The planner owns prefix parsing, draft-prefill mapping, static action mapping, automation quick recurrence parsing, and canonical command-ID-to-tool-name mapping. The executor owns the parsed-plan switch, while `WorkspaceModel` owns the underlying mutations and tool dispatch helpers. This keeps command palette rows, slash-command templates, automation row actions, MCP lifecycle actions, memory actions, and git shortcuts from drifting as the command set grows.
- Workspace command actions reduce through `WorkspaceCommandActionPlanner` before touching `WorkspaceModel` side effects. The planner owns selected project/thread preconditions, rename draft construction, sidebar bulk command mapping, and action-to-effect routing. `WorkspaceModel` should execute typed `WorkspaceCommandActionEffect` values and keep actor-bound persistence, top-bar refresh, and store synchronization rather than growing another selected-state switch.
- Command palette surface behavior lives in `WorkspaceCommandPaletteSurface.swift`. Command records, top-bar overflow projection, automation and Computer Use command factories, category ordering, slash/action query scoping, and ranking/scoring stay beside the command contract instead of inside the aggregate `WorkspaceSurface.swift` payload.
- Command palette row ownership is split by command family. `WorkspaceCommandSurfaceBuilder` composes rows from `WorkspaceThreadCommandCatalog`, `WorkspaceCommandStaticCatalog`, `WorkspaceGitCommandCatalog`, and `WorkspaceProjectCommandCatalog`; it should not grow private command arrays for new features. New command families should get a focused catalog when they carry their own availability rules, keyword derivation, or project/runtime inputs.
- Automation record construction and due-run draft creation live in `WorkspaceAutomationEngine.swift`, not inside `WorkspaceModel`. `WorkspaceAutomationFactory` owns concrete `QuillAutomation` records and schedule helpers, `WorkspaceAutomationRunner` owns due filtering, recurrence advancement, and generated thread drafts, and `WorkspaceModel` applies those drafts to UI selection, project refresh, stores, and notification reports. This keeps scheduler behavior testable without pulling project persistence or top-bar state into pure automation tests.
- Automation state mutation lives in `WorkspaceAutomationStateReducer`, not inline in `WorkspaceModel`. Sorting, append/create, status updates, deletion, replacement, and automation-pane visibility changes are pure reducer outputs; the workspace model owns applying the resulting state to persistence and UI side effects.
- Multi-agent collaboration should happen through pull requests and a serialized merge train rather than direct pushes to `main`. CI runs on `pull_request`, `push`, and `merge_group` events. The train watches `merge-train` and `automerge` labels, ignores draft or `do-not-merge` PRs, processes only the oldest eligible PR, updates behind branches before merging, and merges only after all non-train checks are successful. This keeps Codex/agent work reviewable while preserving a green mainline.
- The first memories slice is auditable and user-authored. QuillCode loads bounded `.md`, `.txt`, and `.json` notes from `~/.quillcode/memories` and project `.quillcode/memories`, rejects symlinks and paths outside the memory root, truncates oversized notes with visible labels, snapshots loaded memories onto threads, injects them into TrustedRouter as non-command background context, and surfaces the count/sources through the top bar, Memories pane, static HTML renderer, Playwright harness, slash command, and macOS menu bar. Users can explicitly save global memories with `/remember text`, the Add memory command-palette action, or a model-authored `host.memory.remember` tool call when they ask QuillCode to remember a stable preference/fact; saved notes create transcript/tool audit records, refresh memory context immediately, and reject obvious credentials, tokens, passwords, and private keys. Rejected sensitive memory attempts redact transcript/tool/thread-title payloads and appear as Memories-pane review rows with Add safe memory actions. Global memories can be forgotten from the Memories pane and produce a transcript notice. Project memories stay read-only in-app because they are project-owned files. Idle Chronicle jobs, richer project-memory review, conflict resolution, deeper redaction workflows, and fully autonomous inference of memories without explicit user intent are separate safety/UX milestones.
- Workspace configuration transitions live in `WorkspaceConfigurationEngine`, not inline in `WorkspaceModel`. Mode/model selection, model ID normalization, favorite-model mutation, catalog normalization, settings application, and selected-thread config syncing are pure state rules that need direct tests and parity gates. The workspace model owns user-facing orchestration: when to refresh the top bar, persist stores, or route UI commands.
- Workspace configuration integration coverage lives in `WorkspaceConfigurationIntegrationTests`, not `WorkspaceModelTests`. Mode/model top-bar propagation, favorite model config/surface projection, apply-settings thread/surface sync, persisted bootstrap loading, automation bootstrap surfacing, and TrustedRouter API key persistence cross the workspace model, stores, bootstrap, and surfaces; keep those flows grouped outside the model monolith while pure configuration state rules stay in `WorkspaceConfigurationEngineTests`.
- Workspace activity integration coverage lives in focused feature suites, not `WorkspaceModelTests`. `WorkspaceActivityIntegrationTests` owns surface/context projection, `WorkspaceActivityInstructionIntegrationTests` owns source and instruction-review projection, `WorkspaceActivityPlanHandoffIntegrationTests` owns plan and handoff tool flows, and `WorkspaceActivitySubagentIntegrationTests` owns subagent progress flows. Keep these cross-cutting activity behaviors outside the model monolith while pure tool routing stays in lower-level executor tests.
- Workspace tool-card integration coverage lives in `WorkspaceToolCardIntegrationTests`, not `WorkspaceModelTests`. Actionable approval-card projection, approval execution, transcript/tool audit records, and stopped-tool card projection cross transcript surface building, model actions, tool execution, and surfaces; keep those flows grouped outside the model monolith while pure tool-card surface derivation stays in focused surface tests.
- `WorkspaceModelTests.swift` is intentionally retired as an empty marker. New workspace integration coverage should land in a named feature suite, or create a new focused suite first; parity tests assert the historical catch-all stays empty.
- Tool audit event construction lives in `WorkspaceToolEventRecorder`, not inline in `WorkspaceModel`. Queued/running/completed/failed tool events, redacted call payloads, and result payload JSON are transcript contracts shared by native tool cards, static HTML, activity, and tests. The workspace model owns only when a tool run should be recorded.
- Tool-call execution routing lives in `WorkspaceToolCallExecutor`. Browser inspect, plan update, SSH Remote project dispatch, local `ToolRouter` fallback, and successful apply-patch review-diff follow-up share one tested routing boundary. `WorkspaceModel` owns context refresh, event recording, persistence, and top-bar status, not tool-name routing branches.
- Project metadata loading lives in `WorkspaceProjectMetadataLoader`, not inline in `WorkspaceModel`. Local project refresh aggregates instructions, local environment actions, extension manifests, and project memories through one loader; SSH Remote refresh converts remote context into the same metadata contract with local-only actions/extensions cleared. `WorkspaceModel` owns selection, thread-context application, persistence, and top-bar refresh after metadata is loaded.
- Pure project loader coverage lives in focused test files, not `WorkspaceModelTests`. Direct tests for `ProjectInstructionLoader`, `LocalEnvironmentActionLoader`, `ProjectExtensionManifestLoader`, and `MemoryNoteLoader` should stay in their matching test files; `WorkspaceModelTests` should prove workspace integration only.
- Workspace memory integration coverage lives in `WorkspaceMemoryIntegrationTests`, not `WorkspaceModelTests`. Global/project memory loading, `/remember`, agent memory tool execution, credential-like memory rejection, memory deletion, and the memory-add command are one feature group and should stay tested together outside the model monolith.
- Workspace MCP integration coverage lives in `WorkspaceMCPIntegrationTests`, not `WorkspaceModelTests`. MCP lifecycle, dynamic tool catalog exposure, tool/resource/prompt execution from agent turns, and rejection of unadvertised MCP tools cross the workspace model, MCP runtime, tool cards, transcript events, and surfaces; keep those flows together outside the model monolith while lower-level MCP launcher/catalog/request tests stay in their focused files.
- Workspace project integration coverage lives in `WorkspaceProjectIntegrationTests`, not `WorkspaceModelTests`. Project registry persistence, project selection, next-chat workspace context, rename/refresh/new-chat/remove actions, and project instruction snapshotting cross the workspace model, stores, metadata loader, thread context, agent submission, commands, persistence, and surfaces; keep those flows outside the model monolith while direct instruction parsing stays in focused loader tests.
- Runtime factory coverage lives in `WorkspaceRuntimeFactoryTests`, not `WorkspaceModelTests`. Tests for environment key detection, stored secret detection, deterministic mock override selection, and no-key model-catalog fallback should stay with the factory boundary; `WorkspaceModelTests` should cover runtime state only when the model applies or surfaces it.
- Workspace project extension integration coverage lives in `WorkspaceProjectExtensionIntegrationTests`, not `WorkspaceModelTests`. Extension manifest loading into project/secondary-pane surfaces, update-command execution, metadata refresh, and success/failure transcript notices cross the workspace model and project metadata loader; keep those flows together outside the model monolith while low-level manifest parsing and shell-call shape tests stay focused.
- Workspace slash-command integration coverage lives in `WorkspaceSlashCommandIntegrationTests`, not `WorkspaceModelTests`. Command-palette slash prefills, core slash dispatch, local environment action slash execution, local model/mode/thread lifecycle commands, context compaction, and status transcript assertions cross composer submission, command dispatch, workspace surfaces, and transcript creation; keep those flows together while pure transcript copy stays in `WorkspaceSlashCommandTranscriptPlannerTests` and remote/automation-specific slash flows stay with their broader owning features until extracted.
- Workspace local environment integration coverage lives in `WorkspaceLocalEnvironmentIntegrationTests`, not `WorkspaceModelTests`. Local environment action loading into project state, command-palette execution, metadata-backed environment redaction, bounded working directories, and timeouts cross the workspace model, metadata loader, shell-call planner, and tool cards; keep those flows together outside the model monolith while direct loader behavior stays focused. `/env` transcript behavior belongs to `WorkspaceSlashCommandIntegrationTests` with the rest of slash-command routing.
- Workspace automation integration coverage is split by workflow family, not collected in `WorkspaceModelTests` or one oversized automation suite. `WorkspaceAutomationIntegrationTests` owns command/persistence flows, `WorkspaceAutomationSchedulingIntegrationTests` owns concrete, natural-language, recurring, and slash scheduling flows, and `WorkspaceAutomationRunIntegrationTests` owns manual and due-run execution, recurrence advancement, reports, and limits. Shared fixtures live in `WorkspaceAutomationIntegrationTestSupport`, while pure automation record and run-draft logic stays in `WorkspaceAutomationEngineTests`.
- Workspace terminal integration coverage lives in `WorkspaceTerminalIntegrationTests`, not `WorkspaceModelTests`. Local terminal execution, SSH Remote terminal execution, streaming output, cwd/environment persistence, clear-history behavior, selected-project resets, cancellation, and stop-all behavior cross the workspace model, terminal engine, shell/SSH runners, terminal surface, and async task lifecycle; keep those flows together outside the model monolith while pure terminal state transitions stay in `WorkspaceTerminalEngineTests`.
- Shared workspace integration fixtures live in `WorkspaceModelIntegrationTestSupport` only while they are genuinely cross-domain. Fake SSH, fake GitHub CLI, temporary git repositories, and fixed/recording LLM clients are common enough to share, but new broad helpers should move to domain-specific support files once they become owned by one integration cluster.
- Focused workspace unit suites should use `makeQuillCodeTestDirectory()` instead of private temporary-directory helpers. The shared helper registers teardown cleanup, keeps fixture policy in one place, and avoids small leaks when focused tests are split out of broader integration suites.
- Worktree request values, tool-call construction, cleanup, and handoff transcript records live outside `WorkspaceModel`. `WorkspaceWorktreeRequests` owns the public create/open/remove/prune request structs used by dialogs, SwiftUI, slash commands, and desktop controllers. `WorkspaceWorktreeToolCallPlanner` owns canonical `host.git.worktree.create`, `host.git.worktree.open`, `host.git.worktree.remove`, and `host.git.worktree.prune` argument JSON, including branch/base trimming, force flags, and prune dry-run/verbose flags. `WorkspaceWorktreeOpenEngine` owns the pure local/SSH Remote `Worktree: ...` thread construction, notice payloads, and display labels; its handoff context stores neutral path/branch values so create and open flows share the engine without pretending every handoff was created in that turn. The workspace model owns only tool dispatch, local/SSH project registration, selection, persistence, and top-bar refresh after a worktree is created or opened.
- Workspace status copy and context labels live in `WorkspaceStatusTextBuilder`. `/status`, slash mode confirmations, top-bar subtitles, instruction labels, memory labels, and mode labels must use the same helper so transcript copy, SwiftUI surfaces, static HTML, and menu-bar surfaces do not drift. `WorkspaceModel` owns when to emit a status response; the builder owns what the status response says.
- Top-bar status semantics live in `QuillCodeTopBarStatusPresentation`, not in SwiftUI or HTML renderers. Agent status tone, indicator visibility, accessibility text, and runtime issue tone are shared presentation values so native UI and static UI harness snapshots stay visually and semantically aligned.
- Top-bar lifecycle status labels live in `TopBarAgentStatusLabel`. `WorkspaceModel`, `WorkspaceAgentStatusBuilder`, `WorkspaceMCPRuntime`, and root-state defaults should use those constants instead of raw `Idle`, `Running`, `Failed`, `Stopped`, or `Terminal` strings so UX copy, tests, and presentation semantics stay synchronized.
- Runtime/auth status labels live in `QuillCodeRuntimeStatusLabel`, separate from lifecycle labels. `RuntimeFactory`, `WorkspaceRuntimeIssueBuilder`, and the desktop sign-in controller should use those constants for mock, sign-in-needed, developer-key-needed, signed-in, ready, and sign-in-failed statuses so runtime issue detection does not depend on scattered string sentinels.
- Agent progress status copy lives in `WorkspaceAgentStatusBuilder`. `WorkspaceModel` owns when agent progress arrives and when the top bar refreshes, while the builder owns event-kind-to-status labels such as Queued, Running, Review, Streaming, Finishing, and Failed so progress copy stays directly tested and aligned with top-bar presentation semantics.
- Slash-command local transcript copy lives in `WorkspaceSlashCommandTranscriptPlanner`. `WorkspaceModel` still owns command side effects such as renaming, scheduling, SSH project creation, memory writes, local environment action execution, and tool dispatch, but the user-visible success/failure records for `/help`, `/status`, `/mode`, `/model`, `/rename`, `/project rename`, `/ssh`, `/follow-up`, `/workspace-check`, `/env`, invalid commands, and unknown commands are pure planner outputs with focused tests.
- Slash-command dispatch is split into parser, planner, and executor stages. `SlashCommandParser` and its family parsers turn text into parsed commands, `WorkspaceSlashCommandDispatchPlanner` maps parsed commands to typed `WorkspaceSlashCommandDispatchAction` values, and `WorkspaceSlashCommandActionExecutor` applies those typed actions through the workspace model. `WorkspaceModel.handleSlashCommand` should stay as lifecycle coordination only: plan, execute, clear send state, and refresh the top bar.
- Pull request slash-command parsing lives in `SlashPullRequestCommandParser`. `SlashCommandParser` owns only the top-level `/pr` delegation, while PR subcommands, selector/body splitting, reviewer and label argument construction, and merge flags stay beside focused parser tests.
- Thread lifecycle slash-command parsing lives in `SlashThreadCommandParser`. `SlashCommandParser` owns only top-level thread alias delegation, while `/new`, `/clear`, `/compact`, `/fork last|summary|full`, `/rename`, `/duplicate`, `/pin`, `/unpin`, `/archive`, `/unarchive`, `/delete` aliases, command IDs, and thread rename/fork usage copy stay beside focused parser tests.
- Memory slash-command parsing lives in `SlashMemoryCommandParser`. `SlashCommandParser` owns only top-level memory alias delegation, while `/memory`, `/memories`, `/remember`, memory pane command IDs, and remember-content trimming stay beside focused parser tests.
- Workspace utility slash-command parsing lives in `SlashWorkspaceCommandParser`. `SlashCommandParser` owns only top-level workspace alias delegation, while `/browser`, `/preview`, `/worktree`, `/worktrees`, `/wt`, and their workspace command IDs stay beside focused parser tests.
- Local environment slash-command parsing lives in `SlashEnvironmentCommandParser`. `SlashCommandParser` owns only top-level environment alias delegation, while `/env`, `/environment`, `/local-env`, list-vs-run query semantics, and query trimming stay beside focused parser tests.
- Local environment slash-command execution planning lives in `WorkspaceEnvironmentSlashCommandPlanner`, and local environment action alias matching lives in `LocalEnvironmentActionMatcher`. `WorkspaceModel` refreshes project metadata and executes the resulting transcript or action ID, while list/not-found transcript choice, query trimming, title/path/normalized alias matching, and action-ID lookup stay in focused helpers with direct tests.
- Project slash-command parsing lives in `SlashProjectCommandParser`. `SlashCommandParser` owns only the top-level `/project` delegation, while project aliases, rename validation, project command IDs, and project-specific usage/error copy stay beside focused parser tests.
- Terminal slash-command parsing lives in `SlashTerminalCommandParser`. `SlashCommandParser` owns only top-level `/terminal`, `/term`, and `/shell` delegation, while toggle/clear aliases, command IDs, and terminal-specific usage copy stay beside focused parser tests.
- Mode slash-command parsing lives in `SlashModeCommandParser`. `SlashCommandParser` owns only top-level `/mode` delegation, while Auto/Review/Read-only aliases, mode-specific usage copy, and unknown-mode copy stay beside focused parser tests.
- Model slash-command parsing lives in `SlashModelCommandParser`. `SlashCommandParser` owns only top-level `/model` delegation, while model argument trimming and user-facing usage copy stay beside focused parser tests.
- SSH Remote slash-command parsing lives in `SlashRemoteProjectCommandParser`. `SlashCommandParser` owns only top-level `/ssh` and `/remote` delegation, while remote address trimming and remote-project usage copy stay beside focused parser tests.
- Scheduling slash-command parsing lives in `SlashSchedulingCommandParser`. `SlashCommandParser` owns only top-level `/follow-up` and `/workspace-check` alias delegation, while schedule argument trimming and scheduling-specific usage copy stay beside focused parser tests.
- Memory command orchestration lives in `WorkspaceMemoryEngine`, not inline in `WorkspaceModel`. Transcript copy lives in `WorkspaceMemoryCommandTranscriptPlanner`, write/delete error copy goes through `WorkspaceMemoryErrorMessageBuilder`, and thread refresh events go through `WorkspaceMemoryContextUpdatePlanner`. The engine owns global memory write/delete outcomes, global reloads, transcript mutations, and context-update intents; `WorkspaceModel` owns only applying those intents to actor-isolated workspace state, persistence, and top-bar refreshes.
- Per-turn agent runner configuration lives in `WorkspaceAgentRunContextBuilder`. `WorkspaceModel` selects the current project/browser/memory/MCP/Computer Use state and asks the builder for a configured `AgentRunner`; the builder owns local versus SSH Remote base tools, optional plan/browser/Computer Use/memory/MCP tool definitions, and override composition. Memory tool execution and saved-memory event detection live together in `WorkspaceMemoryRememberToolExecutor`.
- Per-turn agent send execution lives in `WorkspaceAgentSendSession`, with runner/session composition in `WorkspaceAgentSendSessionFactory`, thread preparation in `WorkspaceModel.prepareAgentSendThread()`, start intent in `WorkspaceAgentSendStartPlanner`, progress intent in `WorkspaceAgentSendProgressPlanner`, and terminal send intent in `WorkspaceAgentSendTerminalPlanner`. `WorkspaceModel` still owns composer state, actor-isolated thread updates, throwing persistence, and top-bar side effects, while the session owns cancellation checks, the `AgentRunner.send` call, progress handler handoff, and the saved-memory signal returned from the completed thread.
- Tool argument JSON construction lives in `ToolArguments` in `QuillCodeCore`. App-layer code may build heterogeneous argument dictionaries for existing tool schemas, but it should use `ToolArguments.json(...)` rather than private `JSONSerialization` helpers so parsing and serialization evolve together.
- Local environment action and project extension update shell calls live in `WorkspaceShellToolCallPlanner`. `WorkspaceModel` owns project metadata refresh, dispatch, notices, and persistence, but the canonical `host.shell.run` argument shape for command, environment, and timeout belongs in the planner with direct tests.
- Asynchronous agent progress and completion must update their captured thread through `WorkspaceThreadLifecycleEngine.applyAgentRunThreadUpdate`, preserving the user's current selected thread when it still exists. Opening a new chat during a run is an explicit navigation choice; late progress, completion, or cancellation cleanup may mutate and persist the original thread, but must not steal focus back to it. `WorkspaceModel` owns only the side effects that follow fallback selection, such as terminal sync and project persistence.
- Composer cancellation transcript mutation lives in `WorkspaceComposerCancellationPlanner`. `WorkspaceModel` may reset composer state, persist the target thread, and refresh the top bar, but cancelled-send prompt backfill, “Stopped by user” copy, pending-tool failure conversion, and duplicate notice suppression are pure planner behavior with direct tests.
- Composer submission planning lives in `WorkspaceComposerSubmissionPlanner`. The planner owns draft trimming plus the first routing decision: ignore blank drafts, dispatch slash commands with their trimmed original prompt, or send a trimmed agent prompt. `WorkspaceModel` owns the resulting side effects, not raw prompt normalization.
- Transcript timeline layout lives in `QuillCodeTranscriptView`, not the workspace shell. The workspace shell decides whether the transcript pane is visible and routes callbacks; the transcript view owns Find bar placement, empty state, context banner/runtime issue/review placement, message and tool-card timeline rows, active Find highlighting, scroll-to-match behavior, and tool-card copy fallback. `WorkspaceSwiftUIView.swift` should stay focused on chrome composition, modal presentation, and typed command routing.
- Workspace sheet presentation lives in `QuillCodeWorkspaceSheetsModifier`, not the workspace shell. `WorkspaceSwiftUIView.swift` owns the presentation state bindings and routes typed callbacks; the sheet presenter owns settings, search, keyboard shortcuts, command palette, worktree create/open/remove, and thread/project rename sheet composition plus their save/cancel dismissal wiring.
- Approval-card action planning lives in `WorkspaceApprovalActionPlanner`. The planner owns pending approval request lookup, approval/deny decision event construction, rationale copy, run-versus-skip intent, and skip notice text; `WorkspaceModel` owns only applying the plan, executing approved tools, persistence, and top-bar refresh.
- Approval-card Edit is not an approval decision. It stays in `WorkspaceApprovalActionPlanner`, produces a composer draft from the pending tool call, and leaves the original approval request unresolved so the revised user instruction goes through normal planning and safety review again.
- Tool-result final-answer copy lives in `AgentFinalAnswerBuilder`, not in `AgentRunner`. `AgentRunner.finalAnswer(...)` remains the compatibility entry point, but shell/browser/file/patch/MCP/Computer Use response wording belongs in the focused builder with direct tests and parity gates.
- Deterministic mock model behavior lives in `MockLLMClient.swift`, not in `Agent.swift`. The mock client can keep local smoke-test and harness heuristics, but the main agent file should stay focused on agent contracts, streaming preview helpers, execution orchestration, and run result types.
- Streaming action collection and partial assistant-preview parsing live in `AgentActionStreaming.swift`, not in `Agent.swift`. `AgentRunner` and `TrustedRouterLLMClient` should delegate to `AgentActionStreamCollector`, and draft assistant text should go through `AgentActionStreamPreview` so incomplete streaming JSON, raw stream accumulation, and duplicate preview suppression are handled in one tested helper.
- Sidebar action hierarchy should stay sparse while matching the Codex first-read rail. The visible primary rail keeps `New chat`, `Search`, `Plugins`, and `Automations` as primary actions; Command Palette, Terminal, Browser, Memories, and Activity live in the shared Tools menu driven by `QuillCodeSidebarCommandPresentation.utilityCommandGroups`. This preserves quick access to the Codex-like entry points while preventing native SwiftUI, static HTML, and Playwright from drifting on secondary tool order.
- SSH Remote project execution should keep command routing, path validation, and command planning in separate seams. `WorkspaceRemoteProjectToolExecutor` owns only tool routing and SSH execution, `WorkspaceRemoteProjectPath` owns remote path normalization/artifact labels, and `WorkspaceRemoteGitToolRequestPlanner` owns Git/GitHub/worktree command construction plus URL/artifact intent. This keeps remote support testable as SSH, QuillCloud relay, and future remote transports expand.
- Claude design critique on 2026-06-23 identified the next high-impact UI cleanup: keep the top bar quiet, move model selection and approval mode to the composer, simplify the sidebar into composer/threads/projects/footer zones, replace noisy bulk-action grids with transient horizontal actions, replace the flat Tools popover with a structured activity surface, teach Auto/Review/Read-only as first-class controls in the empty state, and make approvals a persistent inline queue banner instead of a modal-feeling interruption. The first slice moved model/mode into composer controls, hid the empty Chats header, balanced the Tools/Settings footer, and added native/static/Playwright coverage; the remaining items stay as UX roadmap inputs.
- Tool-step execution lives in `AgentToolStepRunner.swift`, not in `Agent.swift`. `AgentRunner.send` owns the high-level model/tool loop and repeated-call fallback; the extracted runner owns safety review, tool lifecycle event emission, unavailable-tool results, apply-patch diff follow-up execution, and tool feedback serialization.
- Git tool schema declarations live in focused definition catalogs, not in `GitToolExecutor.swift`. Local git, GitHub PR overview/metadata/review/merge, worktree, schema-building, and definition-construction concerns stay in their own files. The executor owns process execution and safety validation; the definition catalogs own tool names, descriptions, JSON schemas, host, and risk metadata.
- GitHub pull request execution lives in `GitHubPullRequestToolExecutor.swift`, and raw git/gh process launching lives in `GitProcessRunner.swift`. `GitToolExecutor` remains the compatibility facade used by the tool router and remote planners, but PR command construction, PR-specific input validation, URL artifact extraction, and raw `Process` management should stay out of that facade.
- Git worktree execution lives in `GitWorktreeToolExecutor.swift`. Worktree sibling-path validation, registered-worktree lookup, create/remove command construction, and worktree artifact reporting should stay beside that executor; `GitToolExecutor` remains a compatibility facade for existing tool-router call sites.
- Shared git input validation lives in `GitInputValidator.swift`. Focused executors and SSH Remote git planning should use that neutral helper for trimming, git-name validation, and local relative-path validation instead of reaching back into `GitToolExecutor`; the facade may keep delegating compatibility wrappers only.
- Git hunk patch execution lives in `GitPatchToolExecutor.swift`, and git tool errors live in `GitToolError.swift`. Hunk staging/restoring, patch temp-file handling, and patch-path metadata parsing should stay beside the patch executor; local and SSH Remote hunk planning should reuse `GitPatchToolExecutor.mismatchedPatchPath` instead of adding patch parsers to facades or remote planners.
- Local git execution lives in `GitLocalToolExecutor.swift`. Status, diff, stage, restore, commit, push, path validation, and current-branch lookup should stay beside the local executor; `GitToolExecutor` remains only the compatibility facade over local, patch, worktree, and GitHub PR executors.
- GitHub PR input validation and output parsing live outside PR command execution. `GitHubPullRequestInputValidator.swift` owns selector, reviewer, label, review-action, and merge-method normalization for both local and SSH Remote PR planning, while `GitHubPullRequestOutputParser.swift` owns URL artifact extraction. `GitHubPullRequestToolExecutor.swift` should stay focused on `gh pr` command construction and execution.
- SSH Remote GitHub PR command construction lives in `WorkspaceRemoteGitHubPullRequestCommandBuilder.swift`. `WorkspaceRemoteGitToolRequestPlanner.swift` should route to that builder and keep generic git, hunk, worktree, and artifact intent planning separate so local PR validation, SSH Remote command assembly, and future QuillCloud remote transports do not drift.
- SSH Remote git worktree command construction lives in `WorkspaceRemoteGitWorktreeCommandBuilder.swift`. Worktree list/create/open/remove command assembly, sibling path normalization, registered-worktree verification, and worktree-artifact reporting should stay in that builder while `WorkspaceRemoteGitToolRequestPlanner.swift` remains a generic router for remote git command families.
- SSH Remote git hunk command construction lives in `WorkspaceRemoteGitHunkCommandBuilder.swift`. Stage/restore hunk patch validation, base64 patch transport, temporary-file cleanup, and `git apply` check/apply command assembly should stay in that builder while `WorkspaceRemoteGitToolRequestPlanner.swift` remains a generic router for remote git command families.
- SSH Remote git push command construction lives in `WorkspaceRemoteGitPushCommandBuilder.swift`. Explicit branch pushes, current-branch detection, current-branch safety guards, upstream flags, and remote/branch validation should stay in that builder while `WorkspaceRemoteGitToolRequestPlanner.swift` remains a generic router for remote git command families.
- SSH Remote basic git command construction lives in `WorkspaceRemoteGitBasicCommandBuilder.swift`. Status, diff, file stage/restore, and commit command assembly should stay in that builder so `WorkspaceRemoteGitToolRequestPlanner.swift` remains a pure router across basic git, hunk, push, PR, and worktree command families.
- Terminal command lifecycle mutation lives in `WorkspaceTerminalEngine`, not inline in `WorkspaceModel`. Input normalization, run-entry creation, streaming event application, missing execution-context failure, cancellation/stopped cleanup, marker cleanup, and completed-run cwd/environment persistence should stay in the terminal engine; `WorkspaceModel` owns selected-project sync, async shell streaming orchestration, top-bar updates, and user-facing errors.
- Workspace command action planning and execution are separate boundaries. `WorkspaceCommandActionPlanner` maps command IDs and selected context to typed `WorkspaceCommandActionEffect` values, while `WorkspaceCommandActionExecutor` applies those effects through `QuillCodeWorkspaceModel` methods. `WorkspaceModel.runWorkspaceCommand` remains the command-plan entry point, but it should not own selected-state command action planning or the command-action effect switch.
- Approval-card presentation keeps raw machine state separate from user-facing copy. Tool cards may remain `status == .review` for automation, tests, and action routing, while `ToolCardReviewState` carries the semantic review substate. Routine approvals display as `Ready` / `Ready to run` with `Run` and `Skip` actions. Only denied or policy-blocked review cards display `Needs review`. Native SwiftUI, static HTML, and the Playwright harness must read this copy from the tool-card surface instead of exposing raw safety jargon.
- Browser integration coverage lives in `WorkspaceBrowserIntegrationTests`, not `WorkspaceModelTests`. Browser URL normalization, static and fetched HTML snapshots, fetch-failure fallback, comments, history/reload, invalid-address errors, and composer-driven `host.browser.inspect` cross browser engine state, workspace surfaces, tool cards, and transcript events; keep those flows together while pure URL resolution and browser engine reducers stay in focused unit tests.
- Workspace review integration coverage lives in `WorkspaceReviewIntegrationTests`, not `WorkspaceModelTests`. Apply-patch review diff refresh, local and SSH Remote stage/restore actions, hunk staging, review comments, tool cards, and review-surface visibility cross the workspace model, git tools, remote SSH executor, transcript events, and review surface; keep those flows together while pure review comment planning and git command construction stay in focused unit tests.
- Composer integration coverage lives in `WorkspaceComposerIntegrationTests`, not `WorkspaceModelTests`. Composer submit, tool-card creation, artifact surfacing, Computer Use dispatch, queued-tool progress, streaming assistant drafts, cancellation notices, empty-draft no-ops, and selection races cross the workspace model, agent runner, transcript events, tool cards, and top-bar status; keep those flows together while pure submission/cancellation planning stays in focused planner tests.
- Artifact preview coverage should stay out of `WorkspaceModelTests`. Pure `ToolArtifactState` image/document/text preview derivation lives in `QuillCodeToolCardSurfaceTests` because it is value-type surface behavior independent of workspace state.
- Runtime issue integration coverage lives in `WorkspaceRuntimeIssueIntegrationTests`, not `WorkspaceModelTests`. Applying runtime status, projecting runtime issues into top-bar/settings surfaces, diagnostic redaction, and retry-last-turn mutation cross runtime state, workspace surfaces, commands, and composer state; keep pure issue construction in `WorkspaceRuntimeIssueBuilderTests` and recovery-action mapping in `QuillCodeRuntimeIssueRecoveryPlannerTests`.
- Thread lifecycle integration coverage lives in `WorkspaceThreadLifecycleIntegrationTests`, not `WorkspaceModelTests`. New chat selection, fork/compact context, project-thread fallback selection, pin/archive persistence, and rename/duplicate/unarchive/delete flows cross the workspace model, stores, sidebar ordering, selected project, and top-bar state; keep pure mutation algorithms in `WorkspaceThreadLifecycleEngineTests`.
- Pull request command integration coverage lives in `WorkspacePullRequestIntegrationTests`, not `WorkspaceModelTests`. Remote PR view/checks/diff execution through SSH, slash `/pr` command dispatch, and PR command composer prefills cross workspace commands, slash parsing, SSH remote execution, tool cards, and composer state; keep pure GitHub CLI argument construction in tool tests and remote git builder tests.
- Workspace activity surface derivation lives in `WorkspaceActivitySurfaceBuilder`, while section and item DTOs live in `WorkspaceActivitySectionSurface.swift`. `WorkspaceActivitySurface.swift` should remain the Codable root payload and delegate plan rows, recent event rows, tool/source/artifact summaries, final-answer snippets, handoff summary copy, and section assembly to the focused builder so native SwiftUI, static HTML, and Playwright continue sharing one activity contract.
- Tool artifact state and preview derivation live in `QuillCodeToolArtifactSurface.swift`, not in `QuillCodeToolCardSurface.swift`. Tool cards own status, actions, density, review substates, and card-level artifact grouping; artifact kind detection, image/document preview metadata, href/detail labels, and bounded text preview extraction evolve beside the artifact DTO so transcript projection, activity, native cards, and static HTML share one artifact contract.
- Sidebar thread list derivation lives in `QuillCodeSidebarThreadListBuilder.swift`, not in the aggregate `SidebarSurface` DTO. `SidebarSurface` keeps the stable public API consumed by native SwiftUI, static HTML, and search dialogs, while filtering, pinned/recent/archived partitioning, and date-bucket sectioning stay in the focused helper.
- Native sidebar command payloads are built through `QuillCodeSidebarCommandAdapter.swift`. SwiftUI row and bulk-action views should not construct `WorkspaceCommandSurface` values inline; selection toggles and bulk actions share the same adapter so command IDs, titles, categories, and enabled state stay consistent.
- Sidebar saved filters and custom saved searches are peer sidebar scopes. All/Pinned/Recent/Archived expose stable `sidebar-filter:*` command IDs and count all chats; typed custom searches expose `sidebar-saved-search:*` command IDs, count query matches across all chats, and use the same visible-row/section/select-all/bulk-action pipeline. Changing either scope clears transient selection so hidden rows cannot be mutated. User-authored saved searches persist through `sidebar-saved-searches.json`, create through an explicit text-entry dialog, select through a wide capsule target, reorder through explicit `sidebar-saved-search-move-up/down:*` commands with disabled edge controls, and delete through a separate icon target so destructive controls never share the row-sized selection hit area.
- Static HTML browser snapshots live in `BrowserHTMLSnapshotBuilder`; `BrowserInspector` remains the URL/file/fetched-page adapter and delegates title/count/outline/snippet extraction to the focused builder.
- Streaming shell command lifecycle lives in `ShellStreamingProcessRunner`; `ShellToolExecutor` remains the public shell facade for blocking, cancellable, and streaming entry points while the runner owns async stdout/stderr readers, timeout termination, cancellation, and final streamed `ToolResult` emission.
- Top-bar parity gates live in `ParityTopBarGateTests`, not the broad `ParityGateTests` catch-all. Presentation semantics, lifecycle status labels, runtime/auth labels, model-catalog projection, and top-bar surface contract gates should stay together so top-bar UX can evolve without inflating the main architecture-gate file.
- Model picker search semantics live in `ModelCategorySearchFilter`, not `TopBarSurface` or the SwiftUI picker. `TopBarSurface.filteredModelCategories(matching:)` remains the compatibility entry point, while query normalization, Favorites/Recent visibility, metadata haystack construction, and State-row search behavior stay directly testable beside the filter.
- Slash parser architecture gates live in `ParitySlashGateTests`, not the broad `ParityGateTests` catch-all. PR, project, terminal, and mode delegation checks should stay together so slash-command parser extraction work does not keep inflating the main architecture-gate file.
- App integration test temp fixtures use `XCTestCase.makeTempDirectory()` from `WorkspaceModelIntegrationTestSupport`, which delegates to `makeQuillCodeTestDirectory()` for teardown cleanup. Focused suites should not add private `makeTempDirectory()` helpers or raw `NSTemporaryDirectory()` fixture roots; shared git fixtures should use the same app integration support.
- Tool execution transcript recording lives in `WorkspaceToolEventRecorder`, including primary and follow-up tool calls. `WorkspaceModel.runToolCall` should execute tools and apply model state, but should not manually sequence queued/running/completed event triplets for each follow-up.
- Scheduling slash-command execution stays behind named `WorkspaceModel` helpers instead of inline switch bodies. `/follow-up` and `/workspace-check` still mutate workspace state, but their automation creation and transcript success/failure plumbing should not be re-expanded inside `handleSlashCommand`.
- Slash-command dispatch planning lives in `WorkspaceSlashCommandDispatchPlanner`. Parsed `SlashCommand` cases map to typed `WorkspaceSlashCommandDispatchAction` values outside `WorkspaceModel`; the model applies those actions because it owns state, persistence, tool execution, and top-bar sequencing.
- Worktree slash-command execution must route through the same typed workspace model flow as visible workspace actions. `/worktree create|open|remove|prune` should parse into `WorkspaceWorktree*Request` values, then call `createWorktree`, `openWorktree`, `removeWorktree`, or `pruneWorktrees` so local/SSH Remote execution, audit cards, top-bar updates, and thread selection stay identical across UI entry points. Command-palette worktree prune intentionally dispatches `--dry-run --verbose` by default; users can run `/worktree prune` when they explicitly want cleanup.
- Native command SF Symbol mapping lives in `QuillCodeCommandIconCatalog`. Sidebar presentation may keep sidebar-specific labels, HTML icon tokens, and deliberate compact-menu overrides, but command palette rows and sidebar rows should not grow separate native icon switches for the same command IDs.
- `FileSecretStore` is the fallback/dev implementation of `QuillSecretStore`, not the final platform secret backend. It must keep the secrets directory at `0700`, written secret files at `0600`, and sanitize secret keys into a single filename component. App and agent code should continue depending only on `QuillSecretStore` so Keychain, libsecret, or encrypted-file adapters can replace the fallback without changing call sites.
- TrustedRouter action parsing and tool-argument normalization are separate boundaries. `AgentActionJSONParser` owns extracting a single action object and constructing `AgentAction`; `AgentToolArgumentNormalizer` owns canonical argument keys, tolerated aliases, empty-shell-command repair from explicit nearby prose, and minimum-argument policy. Keep provider transport, JSON-object scanning, prose recovery, and tool schema alias policy in separate files so model-output robustness can improve without turning the parser into a tool registry.
- Tool-call wrapper dialects are normalized before execution. `AgentActionJSONParser` accepts QuillCode JSON plus common provider wrappers such as `choices[].message.tool_calls[].function`, `type:function_call`, `type:tool_use` with `input`, and Responses-style `output` arrays, then hands one canonical action object to `AgentToolArgumentNormalizer`. Stringified JSON `arguments`/`args`/`input` are decoded in the normalizer, so recoverable model drift does not become an empty shell command in the UI.
- Model responses that promise future executable work without returning a tool call are corrected inside `AgentRunner` before they become visible final transcript messages. `AgentPromisedWorkGuard` only detects future-tense work promises and asks the model to retry with the structured QuillCode action schema; it must not infer local commands or bypass TrustedRouter/tool selection.
- Created-thread insertion should go through `WorkspaceModel.insertCreatedThread` unless there is a documented reason not to. New chat, fork, compact, duplicate, worktree-open, and automation-run flows should share selection clearing, terminal sync, project touch, persistence, and top-bar refresh semantics so sidebar bulk-selection and project state do not drift by creation path.
- Browser workflow orchestration lives in `WorkspaceBrowserWorkflow`, not inline in `WorkspaceModel`. The workflow owns URL resolution calls, invalid-address copy, history/navigation delegation, snapshot fetch begin/complete semantics, stale-fetch protection, and browser-comment dispatch. `WorkspaceModel` owns actor-bound state, async page fetching, and top-bar refresh after workflow results.
- Public browser model APIs live in `WorkspaceModelBrowser.swift`, not inline in `WorkspaceModel`. `WorkspaceModel` owns only browser state storage plus the narrow `mutateBrowserState` helper needed by same-module extensions; browser action methods still route every transition through `WorkspaceBrowserWorkflow`.
- Browser parity gates live in `ParityBrowserGateTests`, not the broad `ParityGateTests` catch-all. Browser surface ownership, snapshot extraction, workflow state transitions, location resolving, browser integration-test ownership, and HTML browser-rendering boundaries should stay together so active browser work does not keep inflating the general architecture-gate file.
- Live DOM browser capture is an adapter contract, not a direct dependency from `WorkspaceModel` to a WebView. `BrowserLiveDOMCapturing` owns rendered-session capture, `BrowserLiveDOMSnapshotBuilder` translates bounded rendered title/outline/visible text into `BrowserSnapshotState`, `WorkspaceBrowserWorkflow` owns capture begin/success/failure semantics, and `WorkspaceBrowserEngine` applies final URL/history/title/status mutations. The macOS desktop implementation lives in `DesktopBrowserLiveDOMCapturer`, where an offscreen `WKWebView` renders HTTP(S) pages and evaluates a bounded DOM snapshot. It defaults to `DesktopBrowserLiveDOMProfile.persistent`, backed by WebKit's default website data store, so cookies and session state can be reused across captures; `.ephemeral` remains available for future tests/privacy controls. Visible user sign-in lives in `DesktopBrowserSessionPresenter`, which owns one reusable retained desktop `WKWebView` window with the same default website data store and shares `WorkspaceBrowserLocationResolver` with browser preview. The same visible-session action is exposed through the browser pane, menu bar, and command palette; SwiftUI routes it through an optional host capability so non-desktop surfaces do not gain WebKit dependencies. The desktop controller only injects the capturer/presenter and asks the model to refresh or opens the resolved session; it must not import WebKit, embed JavaScript, or manage visible browser window lifecycle. Multi-tab session management and Linux/browser-process backends should plug into the same seam without adding platform branches to the app model.
- Model and configuration parity gates live in `ParityModelGateTests`, not the broad `ParityGateTests` catch-all. Nike/Zeus/Prometheus/Socrates/Aristotle/Plato branding, TrustedRouter aliases, model catalog normalization, and app config boundaries should stay together so model naming and picker work can evolve without reintroducing raw model types as user-facing defaults.
- Top-bar Disconnect All is a real command, not a disabled placeholder. It shares the active-work stop path with Stop All, stops active MCP server processes, cancels active sends and terminal runs, and detaches the currently selected SSH Remote project context without removing the project from the sidebar. Agent tool calls may hold a persistent SSH-launched remote app-server session; workspace teardown closes all such sessions. Explicit terminal and UI tool actions keep their existing noninteractive one-shot SSH behavior.
- Workspace model-picker integration coverage lives in `WorkspaceModelPickerSurfaceIntegrationTests`, not the broad `WorkspaceSurfaceTests` catch-all. Category grouping, model search against workspace state, unknown selected models, recent/favorite ordering, and model badge metadata should stay together while pure DTO compatibility remains in `QuillCodeTopBarSurfaceTests` and pure builder behavior remains in `WorkspaceModelCatalogSurfaceBuilderTests`.
- HTML chrome renderer coverage lives in `WorkspaceHTMLChromeRendererTests`, not the broad `WorkspaceSurfaceTests` catch-all. Static HTML smoke coverage for primary regions, sidebar chrome, top-bar overflow, composer markup, context banners, runtime issues, and sidebar date buckets should stay together; tool-card, terminal, browser, secondary-pane, and review HTML coverage can be split into their own focused suites as those areas evolve.
- HTML renderer architecture gates live in `ParityHTMLGateTests`, not the broad `ParityGateTests` catch-all. Pure HTML renderer delegation checks for tool cards, top bar, terminal, secondary panes, review, transcript, and sidebar should stay together; browser-specific HTML rendering stays in `ParityBrowserGateTests`, and mixed native/composer/workspace surface gates remain in the broad suite until they have enough focused domain coverage to split cleanly.
- HTML tool-card renderer coverage lives in `WorkspaceHTMLToolCardRendererTests`, not the broad `WorkspaceSurfaceTests` catch-all. Tool-card output, approval actions, artifact chips, image/document/appshot previews, and transcript ordering should stay beside the focused renderer so artifact UI work does not inflate the generic workspace surface suite.
- HTML terminal renderer coverage lives in `WorkspaceHTMLTerminalRendererTests`, not the broad `WorkspaceSurfaceTests` catch-all. Visible terminal pane markup, command rows, clear controls, and running/stopped status labels should stay beside terminal HTML so terminal UI work can evolve without expanding generic surface projection tests.
- HTML review renderer coverage lives in `WorkspaceHTMLReviewRendererTests`, not the broad `WorkspaceSurfaceTests` catch-all. Static review-pane markup, review file/action/hunk/line/comment rendering, and review action data attributes should stay beside review HTML while review-surface data projection remains in focused workspace surface tests until it has a separate builder suite.
- HTML secondary-pane renderer coverage lives in `WorkspaceHTMLSecondaryPaneRendererTests`, not the broad `WorkspaceSurfaceTests` catch-all. Extensions, Memories, Activity, and Automations static HTML smoke tests should stay with the secondary-pane renderer family; browser HTML remains in browser-focused suites because the browser pane has a separate ownership boundary.
- HTML command routing uses one attribute contract: visible command buttons emit `data-command-id`, and click handlers read that same attribute. Secondary-pane extension, MCP resource/prompt, memory, automation, and activity controls should not use ad hoc attributes such as `data-command`, because those can pass size/visibility audits while sending no command to the router.
- Workspace automation model orchestration lives in `WorkspaceModelAutomations.swift`, not in the main `WorkspaceModel.swift` body. The extension owns public automation scheduling/run/delete APIs and delegates pure mutations to `WorkspaceAutomationStateReducer` and draft creation to `WorkspaceAutomationRunner`; the main model owns only shared actor-isolated helpers for persistence, project context refresh, thread insertion, errors, and top-bar refresh.
- Shell and SSH shell executor coverage lives in `ShellToolExecutorTests`, not in the mixed `ToolTests.swift` suite. Reusable temp directory, git repo, fake GitHub CLI, and fake SSH fixtures live in `ToolTestSupport.swift` so future focused tool suites can share setup without growing another broad catch-all test file.
- GitHub pull request tool coverage lives in focused command-family suites, not in the mixed `ToolTests.swift` suite or a single broad PR bucket. Base PR commands, reviewer/label/comment edits, review APIs, merges, router dispatch, and shared fake-`gh` setup each have named test ownership so GitHub workflow changes stay easy to localize.
- Active agent send task execution returns typed completed/cancelled/failed outcomes from `WorkspaceAgentSendTaskCoordinator`; `WorkspaceModel` applies visible workspace state but no longer classifies session cancellation or runtime errors inline.
- Review action execution sequencing lives in `WorkspaceReviewActionRunner`; `WorkspaceModel.runReviewAction` records the typed action/diff results and persists workspace state but no longer directly executes both review tools inline.
- Tool-run thread preparation lives in `WorkspaceToolRunPreparer`. `WorkspaceModel.runToolCall` still owns actor-isolated side effects, top-bar status, persistence, and execution orchestration, but effective project selection and selected-thread instruction/memory sync should stay in the focused preparer so command execution does not drift from thread-bound project context.
- Tool-run lifecycle status planning lives in `WorkspaceToolRunLifecyclePlanner`. `WorkspaceModel.runToolCall` still applies actor-isolated state, persistence, event recording, and browser/error mutation, but start error clearing and final idle/failed status selection should stay in the focused planner so command execution lifecycle rules remain directly testable.
- Generic tool-run sequencing lives in `WorkspaceToolRunCoordinator`. `WorkspaceModel.runToolCall` remains the public same-actor entry point, but first-thread creation, project metadata refresh, selected-thread context sync, lifecycle application, browser/error mutation, audit recording, thread persistence, and final top-bar refresh should stay grouped in the coordinator so new Codex-parity tools do not grow the model extension. Shared `WorkspaceToolCallExecutor` construction lives in `WorkspaceToolCallExecutorFactory` because review actions and generic tool runs must use the same selected-project/browser/SSH routing policy.
- Thread context preparation lives in `WorkspaceThreadContextPreparer`. Agent sends and generic tool runs both need the same effective-project selection and instruction/memory synchronization rules, so the low-level sync should not be duplicated in composer or tool-run code. `WorkspaceToolRunPreparer` may keep tool-run-specific result naming, but it should delegate to the shared preparer.
- Terminal run lifecycle status planning lives in `WorkspaceTerminalLifecyclePlanner`. `WorkspaceModel.runTerminalCommand` still owns async streaming, terminal entry mutation, session marker cleanup, and top-bar application, but started, missing-context, stopped, cancelled, and final idle/failed status selection should stay in the focused planner so terminal behavior stays aligned with tool-run lifecycle boundaries.
- Active-work Stop All and Disconnect All lifecycle status planning lives in `WorkspaceActiveWorkStopPlanner`. `WorkspaceModel` still owns cancelling MCP servers, send state, terminal state, remote-project detachment, and top-bar application, but cancel/disconnect error clearing plus stopped/idle status selection should stay in the focused planner so toolbar commands follow the same testable lifecycle boundary as tool and terminal runs.
- `WorkspaceModel.swift` owns stored app state, persistence handles, and shared mutation primitives. Read-side context queries live in `WorkspaceModelContext.swift`: selected thread/project, active workspace root, terminal current directory, current tool cards, current timeline items, and project lookup. Current transcript/tool-card projections still delegate execution-context enrichment to `WorkspaceExecutionContextSurfaceBuilder`.
- Thread mutation primitives live in `WorkspaceModelThreadMutation.swift`, not the root model body. The root model owns stored state and store handles; the extension owns selected-thread mutation, timestamped persistence mutation, sidebar selected-ID resolution, notice appending, valid-thread ID lookup, and explicit agent-run thread replacement while delegating pure transitions to `WorkspaceThreadLifecycleEngine`.
- Command routing must be explicit. `WorkspaceCommandRoutingCatalog` classifies host-owned commands such as Stop All and Computer Use permission actions separately from command IDs that `WorkspaceCommandPlan` can execute in the workspace model. SwiftUI and desktop planners reject unknown IDs instead of dispatching them into silent no-ops, and command-surface coverage proves every emitted command is either presentational or dispatchable.
- Click targets are a design-system contract. Native SwiftUI controls should use `quillCodeTextButtonTarget`, `quillCodeIconButtonTarget`, `quillCodeFullRowButtonTarget`, or `quillCodeCapsuleButtonTarget` for compact text, icon-only, full-row, and capsule actions instead of ad hoc `frame`/`contentShape` combinations. The HTML harness applies the same 44 px baseline to buttons, summaries, and semantic link targets so Playwright can measure rendered controls while native UI automation is still source-gated.
- Primary click targets are source-gated as well as measured in Playwright. The top bar, sidebar, composer, search, command palette, settings, transcript controls, Find, and generated HTML links must use shared hit-target helpers/classes, so future UI slices cannot quietly reintroduce literal clickable frames or small link targets. Native `Button` and `Link` declarations are both audited because text-only links create the same missed-click problem as tiny buttons.
- Click-target tests must measure what a user can actually hit, not only each element's layout box. The Playwright chrome audit includes semantic interactive roles, active popover/dialog layers, visible-rect intersection with viewport and clipping ancestors, hard-clipping failures, scroll-boundary sliver handling, center-point ownership, and visible peer-overlap detection across top bar, model picker, settings, search, command palette, shortcuts, secondary panes, review, worktree dialogs, transcript tools, and Find.
- Native click-target gates should audit every SwiftUI app `Button`, `Link`, `Menu` trigger, visible `Picker`, and text-entry control, plus visible desktop SwiftUI chrome such as the menu-bar popover, not only controls that already opted into compact or pressable styles. System `Menu`/`CommandMenu` item buttons are exempt because AppKit owns those rows, but visible app controls must carry a shared target helper near their label. The shared hit-target modifier itself is guarded for minimum frame sizing and explicit `contentShape` coverage so the primitive cannot regress while every call site still appears compliant. Compact Playwright coverage should include transient surfaces such as command palette rows, slash suggestions, and Find because these are common places where target regressions hide.
- Native click targets must declare intent, not just size. The low-level `quillCodeInteractiveTarget` primitive is design-system plumbing, and app chrome must choose a semantic helper such as icon, text, form action, row, capsule, switch row, segmented control, or text entry. Generic 44 pt targets are rejected because they hide whether the surrounding layout should reserve a compact, row-wide, or input-shaped hit surface.
- Native action buttons should not use compact platform button styles such as `.bordered`, `.borderedProminent`, `.borderless`, or `.plain` in visible QuillCode chrome. `QuillCodeActionButtonStyle` owns primary, secondary, and destructive action surfaces together with the 44 pt minimum target, rounded content shape, disabled treatment, and 0.96 press feedback, while `QuillCodePressableButtonStyle` remains for controls whose visible surface is already custom-built.
- Explicit click-target probes must verify the usable interior, not just the target rectangle. `expectHitTarget` samples the center and inset corners with `elementFromPoint`, requires an accessible name, and fails controls whose measured 44 px box is partially blocked by overlaying or clipped content.
- Interactive controls must not nest inside other interactive controls. The Playwright audit checks nested targets in addition to size, clipping, center ownership, and overlap, because nested buttons/links often pass simple 44 px checks while still stealing taps from the intended action. The one allowed nested case is an input inside its own associated label, because that is the HTML control's intended click surface; checkbox/radio labels are still audited as targets, while passive labels are ignored. New browser tabs use the same semantic `hit-target-capsule` and `hit-target-icon` classes as production HTML so tab strips do not become a one-off click-target system.
- Routed HTML buttons are a primitive, not feature-renderer string literals. `WorkspaceHTMLPrimitives.commandButton` owns `type`, `data-testid`, `data-command-id`, disabled/ARIA-disabled semantics, optional label/title/role, and the default text hit-target class. Feature renderers may use `buttonAttributes` only when the button needs nested visible markup, such as browser tab labels or activity section label/count rows. Parity gates reject raw `data-command-id` literals elsewhere so a future UI slice cannot create a visible button that looks clickable but fails command routing or target sizing.
- Rendered command targets are audited as part of click-target quality. A 44 px button that routes nowhere is still broken, so the Playwright harness exposes `__quillCodeCommandRoutingAudit` to report state commands and visible enabled `data-command-id` targets that cannot be routed. The broad interaction audit calls it after every opened chrome/panel/dialog state, and the harness dispatcher rejects unknown command IDs instead of silently re-rendering.
- Native and rendered command registries must stay in parity. App tests parse the rendered harness routing registry and compare it against a rich native `WorkspaceCommandSurfaceBuilder` command set plus every `WorkspacePullRequestCommandCatalog` descriptor, so adding a Swift command now requires adding the corresponding harness static ID or dynamic prefix before Playwright can pass.
- Local git, git hunk, git worktree, and git router coverage lives in focused QuillCodeTools suites, not the mixed `ToolTests.swift` catch-all. `GitLocalToolExecutorTests`, `GitPatchToolExecutorTests`, `GitWorktreeToolExecutorTests`, and `GitToolRouterTests` share fixtures from `ToolTestSupport.swift` so git behavior can evolve without turning one broad file into a failure triage bottleneck.
- `ToolTests.swift` is retired. File primitives, generic apply-patch primitives, shell router boundary checks, shell executor behavior, git tools, GitHub PR tools, and MCP probing each live in named focused suites, with `ParityToolGateTests` guarding the retirement of the broad catch-all.
- Inline GitHub pull request review comments are a first-class tool (`host.git.pr.review_comment`), not a raw shell workaround. Local execution resolves PR number/head commit with `gh pr view --json`, resolves the repository with `gh repo view --json`, and posts through `gh api`; SSH Remote execution uses the same validation but builds a quoted remote command with only resolved metadata variables expanded. Keep selector/path/line/side/body validation in `GitHubPullRequestInputValidator`, local API orchestration in `GitHubPullRequestToolExecutor`, and SSH command construction in `WorkspaceRemoteGitHubPullRequestCommandBuilder`.
- Static Auto safety argument-word fallback is read-only only. If a user word appears in a tool's JSON arguments, that can mark intent for read-only discovery, but append/destructive tools must match an explicit tool-specific intent rule such as shell run, file write, apply patch, git push, PR, or MCP. This prevents incidental words like `origin`, `disk`, or file names from approving state-changing actions.
- Static PR intent treats `PR` as a token, not just long-form `pull request`, but PR-specific rules must consider every matching verb before approving a tool. A request like `reply to review comment` should approve the reply tool even though it also contains `review`, while a request like `show PR 42` must not approve push or merge through the generic PR token.
- Static Auto intent matching treats nearby negation as a clarification boundary per phrase occurrence. Phrases like `do not run`, `don't apply this patch`, `do not push`, and `don't remember this` must not Auto-approve those tool families even if the underlying action word appears in the request, while `do not run whoami; run hostname` can still approve the affirmed command. The static layer does not try to infer an alternate command from negated text; it asks for review/clarification when only negated intent is present.
- Routine approval cards should use progressive disclosure. Ready-to-run cards keep `Run`, `Edit`, and `Skip` visible but stay in peek density with raw JSON details closed, while blocked/denied cards stay expanded as `Needs review`. This keeps Auto useful and calm without hiding the exact tool call.
- Desktop real-world smoke coverage has five layers before full packaged-window automation. `QuillCodeDesktopControllerSmokeTests` imports the desktop executable module and drives `QuillCodeDesktopController.send()` with temp state and a mock runtime so regressions in desktop draft clearing, task dispatch, refresh timing, tool-card projection, final answers, and side effects fail under normal `swift test`. `QuillCodeDesktopRenderedSmokeTests` renders the SwiftUI shell and result components inside the test process. `scripts/native-desktop-smoke.sh` runs the built `quill-code-desktop` product with `--native-render-smoke`, sends the same kind of real action through the product executable, writes a JSON report, verifies the file side effect, verifies transcript message/tool/timeline counts, captures a PNG of the desktop root view, captures a focused `result.png` that keeps the prompt, completed tool, final answer, and artifact name visible without depending on transcript scroll position, and writes rendered workspace HTML that must include the final answer/tool result. `scripts/packaged-macos-smoke.sh` builds a deterministic `QuillCode.app`, validates bundle metadata, reruns the same native render smoke against the bundled executable, and then reruns it through `open -W -n QuillCode.app --args ...` so Launch Services argument passing and release entrypoints fail in normal Darwin smoke. Native smoke artifacts are now a CI evidence contract: when the artifact env vars are set, smoke scripts copy `report.json`, `workspace.png`, `result.png`, `chrome.png`, `workspace.html`, `stdout.log`, `manifest.txt`, and packaged `Info.plist` into deterministic folders, and CI uploads them for PR/release review. Signing/notarization, Accessibility-driven `.app` automation, and appshot capture remain the next deeper layer.
- Generated HTML disclosure summaries are first-class click targets, not incidental browser controls. `WorkspaceHTMLPrimitives.summary` owns accessible-name and hit-target classes for `<summary>` rows and icon disclosures, the source gate now rejects raw generated summaries alongside buttons and links, and Playwright includes edge/interior click probes for top-bar, model-picker, sidebar, composer, and tool-card controls so a control cannot pass by only working at its center point.
- Native text entry, segmented controls, adjustable controls, and switch rows are also click-target primitives. SwiftUI call sites should use `quillCodeTextEntryTarget`, `quillCodeSegmentedControlTarget`, `quillCodeAdjustableControlTarget`, and `quillCodeSwitchRowTarget` instead of raw `frame(minHeight:)` sizing so text fields, search fields, settings controls, review inputs, browser inputs, composer input, sliders, steppers, and toggles share the same 44 pt target baseline and explicit content shapes as buttons and links.
- Click-target ownership is an explicit rendered contract, not just a geometry check. Visible interactive HTML controls must carry a shared target class such as `hit-target-owned`, `hit-target-text-entry`, `hit-target-icon`, `hit-target-text`, `hit-target-row`, `hit-target-capsule`, `hit-target-form-action`, or `hit-target-adjustable`; the harness normalizes dynamic markup after render while Swift source gates raw generated `button`, `summary`, `a`, `input`, `select`, and `textarea` usage. Passive text-field labels are not promoted to targets, while checkbox/radio labels remain auditable because they are intended tap surfaces.
- Click-target ownership also needs semantic classification, not only a shared-class marker. Dynamic rendered fallback targets classify by role and visible shape before using generic ownership, critical Playwright probes assert the intended class for high-risk controls, and non-button targets get the same visible focus ring as buttons and text fields. Full-row menu/options such as top-bar overflow items, model choices, and command-palette results should use row targets rather than text-button targets.
- Critical rendered click targets must declare their semantic contract in source markup rather than relying on post-render fallback normalization. The normalizer may still protect incidental or plugin-rendered controls, but the primary sidebar, top bar, composer, settings, search, command palette, terminal, browser, and transcript tool controls should carry explicit `hit-target-*` classes that resolve to non-`auto-*` `data-hit-target-kind` values in Playwright.
- Secondary-pane rendered click targets are part of the critical interaction contract, not lower-priority incidental chrome. Extensions, MCP resource/prompt actions, Memories, and Automations must carry explicit semantic `hit-target-*` classes in the harness and static renderer, appear in the named critical Playwright registry, and have edge-click behavior tests for common actions so plugin/memory/scheduler controls cannot pass only by fallback normalization or center clicks.
- Native SwiftUI click-target semantics are now also release-smoke evidence. The shared target helpers expose a `QuillCodeNativeHitTargetAudit` report covering semantic target kinds, minimum dimensions, press scale, required workspace command targets, and visible secondary-pane contracts. The desktop executable smoke fails if the report is invalid, while source gates and Playwright still own deeper source/rendered hit-area checks. This is stronger than source-only proof, but true packaged `.app` Accessibility frame sampling remains the next native A+ layer.
- Native button styling is not a semantic hit-target contract. `QuillCodeActionButtonStyle` owns tone, surface, disabled opacity, press feedback, and visible shape, but every interactive control still needs a semantic target helper such as `quillCodeFormActionTarget`, `quillCodeTextButtonTarget`, or `quillCodeIconButtonTarget`. The source gate rejects styled buttons without explicit target intent so compact footer, settings, browser, terminal, and dialog actions cannot pass only because they look like buttons.
- Decorative 44 pt chrome is explicit, not a hidden click-target convention. SwiftUI icon badges that are not controls should use `quillCodeDecorativeIconFrame`, while real controls must use semantic target helpers such as `quillCodeIconButtonTarget`, `quillCodeTextButtonTarget`, or `quillCodeTextEntryTarget`. The native source gate rejects raw `frame(width: QuillCodeMetrics.minimumHitTarget, height: QuillCodeMetrics.minimumHitTarget)` outside the design system so future changes cannot make a 44 pt view ambiguous. Rendered Playwright probes sample near-edge points as well as the center and mid-interior points because controls often fail only at the visible target edges where users actually tap.
- Native thinking traces are transcript controls, not text decorations. The trace expander uses a semantic capsule target with chevron, count, press feedback, and accessibility state, and it is part of `QuillCodeNativeHitTargetAudit` whenever trace lines are visible. Desktop sends also need a controller-level optimistic-paint regression: the user message and Thinking surface must be visible immediately after dispatch, before the async agent returns.
- Click targets have a named ownership model, not just a minimum size. Normal SwiftUI controls must use a semantic target helper (`quillCodeIconButtonTarget`, `quillCodeTextEntryTarget`, `quillCodeSwitchRowTarget`, etc.), decorative 44 pt chrome must use `quillCodeDecorativeIconFrame`, and the rare intentional custom gesture region must use `quillCodeOwnedGestureTarget` so it carries a 44 pt shape plus button accessibility traits. The native source gate now rejects raw `.contentShape(...)`, `.allowsHitTesting(...)`, and unnamed tap/long-press/priority gestures outside the design system, which keeps local click-area fixes from turning into unaudited dead zones.
- Links are their own click-target family, not text buttons with URLs. Native SwiftUI `Link` controls must use `quillCodeLinkTarget`, native smoke evidence includes the `link` target kind, and rendered HTML uses `hit-target-link` instead of the older generic `interactive-hit-target` class. This keeps external navigation, artifact opens, and document previews visually tactile while preserving a distinct `link` action for audits and future router behavior.
- Project instruction conflict analysis stays deterministic and scoped. `ProjectInstructionDiagnosticsBuilder` may flag explicit opposing rules over same/nested scopes, but it must not treat sibling folder rules as conflicts because those can intentionally differ. Keep richer or model-assisted rule review as a separate UX layer instead of letting prompt loading or WorkspaceModel infer semantic precedence.
- Instruction conflicts are promoted in Activity without adding new active diagnostic state. The Instruction Review section is derived from existing conflict source diagnostics, while Sources keeps the same audit rows. Conflict resolution must operate on project files or explicit user decisions rather than mutating derived Activity rows; exact two-reference `Keep ...` quick fixes satisfy that rule by applying a normal audited patch to the losing source line and letting metadata refresh prove whether the diagnostic disappeared.
- Instruction source actions are typed Activity item commands, not ad hoc links. Instruction source rows emit Open/Edit actions, conflict diagnostic rows emit Resolve actions, and SwiftUI/static HTML/Playwright all route those command IDs through the workspace command planner. Open dispatches the existing bounded `host.file.read` tool, while Edit and Resolve seed explicit composer drafts so users stay in the normal model/safety/file-edit flow instead of mutating project rules from a derived Activity row.
- Rendered HTML hit targets declare semantic intent through `WorkspaceHTMLHitTargetKind`, not by passing target CSS classes around feature renderers. `WorkspaceHTMLPrimitives` still owns the class mapping for CSS and compatibility, but production renderers should pass `hitTargetKind` or `hitTargetAttributes(kind:)`; Playwright critical probes assert `expectedKind` so regressions fail on intent, not only on box size or class spelling.
- Subagent cancellation is replayable progress, not a generic failure. `WorkspaceSubagentScheduler` maps `CancellationError` to `SubagentStatus.cancelled` in the same `host.subagents.update` schema as queued/running/completed/failed states so Activity can show interrupted workers accurately when Stop All or future worker timeouts land.
- Slash-command cancellation must not synthesize success. If a `/subagents` run is stopped, the model keeps the cancelled progress events, leaves the transcript without a final success summary, and preserves the stopped top-bar state instead of letting the normal slash-command completion path report idle.
- Click-target design starts from surface families before individual controls. `QuillCodeNativeHitTargetAudit` records both target kind and `QuillCodeInteractionSurfaceFamily`, with canonical coverage for persistent chrome, transient surfaces, secondary panes, command palette, search, settings, model picker, review, menu bar, context banners, transcript controls, and tool cards. Native smoke fails if a family disappears, so "everywhere" means an explicit inventory rather than hoping source-grep coverage caught every button.
- Native text entries also need named focus contracts. A generic `textEntry` target proves size and shape, but not that the Codex-critical inputs are represented. `QuillCodeNativeFocusTarget` now inventories composer message, search, command palette, model search, settings API base URL, terminal command, browser address/comment, and review body/reply fields, and native smoke fails if any required focus surface disappears.
- Icon-only native targets need discoverable names, not only 44 pt geometry. `quillCodeIconButtonTarget` call sites must sit inside a control scope with visible `Label(...)` text, `.accessibilityLabel(...)`, or `.help(...)`; source gates reject bare-image icon targets so ellipsis, find navigation, close, and row-action controls do not become physically hittable but semantically vague.
- Menu trigger icon names are scoped to the trigger label and outer menu modifiers. A named menu item inside the menu body, such as `Button("Rename")` or `.help("Rename thread")`, does not satisfy the compact ellipsis trigger; the trigger itself needs a visible `Label(...)`, `.accessibilityLabel(...)`, or `.help(...)` so menu item accessibility cannot mask an unnamed opener.
- Native hit-target smoke evidence must be debuggable, not just valid. Every reported contract needs a stable non-empty ID, surface, label, and source; icon targets need an explicit minimum width; duplicate contract IDs fail the report and the shell smoke parser. Future packaged Accessibility sampling should use these same IDs instead of inventing a second target registry.
- Native hit-target contract lists are organized by surface family, not by a single catch-all canonical file. Keep the persistent/canonical aggregator small, and put navigation/transcript/search, workspace pane, and extension/automation contract groups in focused files so UI agents can add targets without creating registry-level merge pressure.
- Native hit-target coverage is a surface policy, not a one-target-per-area checklist. `QuillCodeNativeSurfaceTargetPolicy` declares the required target-kind mix for each family, such as composer text entry/icon/capsule, browser text entry/text button/icon, review text entry/segmented/full-row/form action, settings text entry/form action, and model-picker text entry/full-row/icon. Native smoke fails on `missingRequiredSurfaceKinds`, so a screen cannot pass by keeping one 44 pt control while losing the rest of the interaction contract.
- Context compaction and fork summaries are Activity state, not generic recent-event noise. Source-thread TrustedRouter start/finish notices and continuation-thread `WorkspaceContextSummaryTelemetry` are projected into a dedicated Activity Context section so users can see whether recovery used a model summary or deterministic fallback without reading raw event logs. Keep the projection in `WorkspaceActivityContextSurfaceBuilder` instead of adding ad hoc checks to the Activity pane renderers.
- Activity click targets are two different families inside one dense pane: section toggles are full-row disclosure targets, while source/diagnostic actions are compact form-action buttons. The harness must emit explicit `data-hit-target-kind/action/source` for both instead of relying on post-render normalization, Activity action CSS must not inherit the full-width section-toggle layout, and Playwright critical probes should click Open/Edit/toggles from interior edge points so Activity cannot pass by center-only or generic secondary-pane coverage.
- Critical rendered click-target probes are grouped by interaction surface, not just by whichever controls a test happens to touch. `expectCriticalTargetSurfaceRegistry` requires each declared surface to include the expected target-kind mix, and every critical probe must declare a semantic kind or class before geometry is checked. This prevents a large but semantically wrong control, or a surface missing one class of target such as text-entry/capsule/icon, from satisfying the "click targets everywhere" contract.
- Subagent task dependencies are scheduler waves keyed by worker name, not a persisted graph model. `/subagents` workers declare prerequisites inline with `Name after Dep1, Dep2: role`; `WorkspaceSubagentScheduler` resolves those names to indices (case-insensitive, dropping unknown/self/duplicate edges), then runs ready jobs concurrently per wave, marks still-waiting jobs `blocked`, skips dependents whose prerequisite failed or was cancelled, and breaks dependency cycles by running the remaining jobs as roots so a run always terminates. No-dependency runs keep the original single-wave all-parallel behavior and progress contract, so existing scheduler/composer/integration coverage stays green. Nested plan presentation uses slash-path worker names (`Frontend/UX`) plus a separate `groupPath` in progress events, preserving full-path dependency identity without introducing a second graph model.
- Subagent dependency edges carry data forward, not just ordering. When the scheduler dispatches a job whose prerequisites have completed, it attaches those prerequisites' result summaries (`WorkspaceSubagentPriorResult`) to the job, and `WorkspaceSubagentPromptBuilder` renders them as a "Results from the prerequisite subagents you depend on" section. This keeps `Verifier after Builder` semantically meaningful for model-backed runs without changing the worker closure signature or the deterministic scheduler tests: root jobs get an empty list and an unchanged prompt, while the scheduler stays injectable for cancellation/ordering coverage.
- The PTY terminal foundation uses portable POSIX `posix_openpt`/`grantpt`/`unlockpt`/`ptsname` rather than `openpty`, because the latter's module exposure differs between Darwin and Glibc. `PTYProcessSession` attaches the child's stdin/stdout/stderr to the pty slave, closes the parent's slave copy so the master sees EOF on child exit, and reads the master with raw `read()` (not `FileHandle.availableData`) so the EIO that a closing slave raises on some platforms ends the loop cleanly instead of throwing. Output is a single `.stdout` stream because a tty merges stdout and stderr; it reuses the existing `ShellProcessEvent`/`ToolResult` contract so the workspace terminal can adopt PTY mode incrementally without a new event type. Live-terminal wiring, window-size propagation, and job control stay follow-up steps.
- Top-bar identity is aligned to the main workspace column, not centered across the full window. The sidebar owns its own column, `QuillCodeMetrics.sidebarWidth` is the native layout source of truth, and the HTML harness uses one `--workspace-sidebar-width` variable for both the grid and the top bar. The title and quiet context subtitle should stay together as one identity group so Codex-like chrome remains calm while still lining up with the transcript.
- Subagent bounded parallelism is a per-wave seed/refill, not a global semaphore. `WorkspaceSubagentRunRequest.maxConcurrentWorkers` caps how many ready workers run at once inside each dependency wave: the scheduler seeds that many tasks into the wave's task group and starts one more each time a worker finishes. `nil` keeps the original behavior (every runnable worker fans out together), so the existing progress contract and concurrency/ordering tests stay byte-identical; only the new bounded test exercises the cap. Jobs are still pre-marked `running` for the wave's progress publish even under a bound, because the cap governs execution, not the displayed readiness — surfacing a live "queued for a slot" state and a slash-command affordance are follow-ups.
- Subagent slash paths qualify local dependencies inside the current group. `Frontend/Tests after UX: run UI checks` resolves `UX` to `Frontend/UX`, while an explicit dependency path such as `Backend/API` is preserved as written. Activity shows the leaf title (`Tests`) with a `Path: Frontend / Tests` detail, and model-backed worker prompts include the nested path so grouped plans remain understandable without duplicating group names in every visible row.
- Native click-target contracts must be addressable by automation. Every non-design-system native target now declares a stable `testID`, routed `commandID`, or named focus target so smoke evidence can identify and click the same targets users see instead of only proving that a generic surface family exists somewhere.
- Common read-only workspace diagnostics are deterministic app behavior, not model discretion. `git status`/`git diff` intents are resolved before generic shell recovery, natural workspace-listing asks map to bounded `host.file.list`, and current-directory asks map to bounded `pwd`. Auto safety separately approves only those exact read-only command shapes when they match the user's words, so live model calls cannot turn a harmless diagnostic into either an over-blocked clarification or a blanket shell approval.
- Native `testID` values use the same `quillcode-...` prefix as SwiftUI `accessibilityIdentifier` values. The native hit-target report normalizes contract IDs to that prefix, and primary controls attach matching identifiers so future packaged Accessibility click sampling can move from report validation to real frame clicks without another naming migration.
- Native hit-target reports include an explicit click-probe plan for every addressable surface contract. Each probe records the matching test ID, command ID, or focus target, semantic kind/action, required minimum dimensions, and normalized interior sample points. The native smoke wrapper fails if any surface contract lacks a probe or if probe selectors drift from the contract, giving future packaged Accessibility sampling a stable contract for real frame and edge-click checks.
- Native click-probe validity belongs in Swift before shell smoke. `QuillCodeNativeHitTargetAudit` now emits `clickProbeValidationIssues` for selector drift, kind/action/family drift, undersized required probe dimensions, exact coordinate drift, and missing/out-of-bounds interior sample points. Shell smoke still double-checks the serialized report, but the typed audit is the source of truth that future packaged Accessibility automation should consume before resolving live frames.
- Packaged smoke must exercise live native SwiftUI chrome, not only command-line render modes. `--native-window-smoke` opens a packaged `QuillCode` root window when smoke-mode Launch Services does not materialize one, waits for the visible window, captures its content view, and writes `window-report.json` plus `window.png` from `scripts/packaged-macos-smoke.sh`. This is the bridge between render-smoke evidence and the future Accessibility runner that will resolve click-probe selectors into live frames.
- Packaged live-window reports must carry the native hit-target contract, not only pixel evidence. `window-report.json` embeds the same validated `nativeHitTargets` report as render smoke, and `scripts/packaged-macos-smoke.sh` runs the shared `native-click-probe-contracts.py validate` command against it. This keeps screenshot evidence, semantic surface coverage, and future Accessibility-frame sampling on one contract.
- Native SwiftUI source is now click-target gated before it reaches rendering. App `Button`, `Link`, and `NavigationLink` declarations in `Sources/QuillCodeApp` must carry a nearby semantic target helper such as `quillCodeFullRowButtonTarget` or `quillCodeLinkTarget`; platform-owned `Menu` row buttons must use `quillCodePlatformMenuItemTarget` with a reason, because AppKit owns those hidden row geometries while QuillCode owns and audits the visible trigger. This makes click-target review source-visible instead of depending only on rendered-state Playwright coverage.
- Native source click-target gates include input and chooser controls, not just button-like controls. `TextField`, `SecureField`, `TextEditor`, `Picker`, `Toggle`, `Slider`, `Stepper`, `Menu`, and `DisclosureGroup` declarations must also carry a nearby semantic target helper, while `Menu` specifically must prove the visible trigger has a QuillCode target instead of satisfying the audit with hidden platform menu rows. This keeps search fields, settings controls, review inputs, tool disclosures, and future adjustable controls inside the same interaction contract.
- Workspace commands are click targets too. `QuillCodeNativeHitTargetAudit` now creates a native hit-target contract for every `WorkspaceCommandSurface`, not only the primary sidebar/top-bar subset. Persistent commands keep their actual chrome family, while generated or palette-only commands use full-row command-palette semantics with their routed `commandID`. This means dynamic project, git, MCP, automation, memory, browser, terminal, and Computer Use commands cannot be added without a stable, addressable click contract.
- Workspace Back/Forward history is transient workspace UI state, not persisted project or thread state. `WorkspaceNavigationHistoryState` owns the pure reducer, `WorkspaceModelNavigationHistory` owns applying valid thread/project locations without recursively recording navigation, and top-bar buttons plus command-palette rows route through the same `workspace-back`/`workspace-forward` commands. Browser Back/Forward remains separate browser-tab history.
- Gesture-owned SwiftUI targets are exceptional and must declare ownership. Normal interactive surfaces should use `Button`, `Link`, text entry, picker, toggle, or another native control with the matching QuillCode target helper; custom `.onTapGesture`, `.onLongPressGesture`, `.gesture`, `.simultaneousGesture`, and `.highPriorityGesture` regions must use `quillCodeOwnedGestureTarget` so the source gate can prove a named 44 pt region, explicit content shape, and button accessibility traits exist. The fast native audit now scans visible desktop chrome as well as `QuillCodeApp`, while the broader parity gate still owns deeper style, label, overlap, and raw-hit-testing checks.
- Click-target release validators need executable positive and negative fixtures, not only source-string gates. Packaged-window click-probe validation must prove valid Accessibility frame samples write the expected manifest and that required unblocked sample points fail when Accessibility hit testing reports another owner, so overlay and stale-hit-region regressions fail before release smoke evidence is trusted.
- Recursive subagent delegation is part of the slash-command workflow, not just the scheduler primitive. A worker may emit bounded `[[DELEGATE: name | role]]` markers, the slash runner parses them into child workers through `WorkspaceSubagentSpawnDirectiveParser`, and Activity must preserve the nested path so delegated work stays replayable and auditable from the normal thread surface.
- Interactive SwiftUI containers must declare click-target spacing explicitly. `HStack`, `LazyHGrid`, and `LazyVGrid` clusters that contain multiple controls may not rely on SwiftUI's default spacing because that makes peer clearance an implicit local choice. The source gate now rejects both raw numeric spacing and omitted spacing for interactive clusters, while allowing one-control passive rows such as text plus a trailing Retry button.
- Sidebar visibility is workspace chrome state, not a secondary pane. `WorkspaceChromeState` is the model-owned source of truth, `WorkspaceChromeSurface` is projected into native SwiftUI/static HTML/Playwright, and `toggle-sidebar` routes through the same typed command plan/executor path as other workspace commands. Do not add one-off sidebar booleans in renderer or harness code; new chrome visibility controls should extend this contract.
- Playwright interaction auditing has a public façade plus focused implementation modules. Tests should keep importing from `interaction-audit-helpers.ts`, but new constants/types belong in `interaction-audit-contracts.ts`, browser-side geometry/a11y report logic belongs in `interaction-audit-report.ts`, and Playwright assertion/registry/click-probe helpers belong in `interaction-audit-targets.ts`. Keep `page.evaluate` browser code self-contained unless we intentionally introduce an injected browser-audit bundle.
- Sidebar parity gates are split by ownership. Selection/bulk reducer contracts stay in `ParityWorkspaceSidebarGateTests`, row mutations in `ParityWorkspaceSidebarRowActionGateTests`, native/HTML command presentation in `ParitySidebarCommandPresentationGateTests`, surface contracts in `ParityWorkspaceSidebarSurfaceGateTests`, and sidebar/project E2E placement in `ParityWorkspaceSidebarPlaywrightGateTests`. The focused-suite manifest must list every test in those files, including UI layout gates such as saved-filter wrapping.
- Project parity gates are split by ownership. Project metadata, WorkspaceModel project API, pure loader ownership, and instruction-scope contracts stay in `ParityWorkspaceProjectGateTests`; local/remote/PR integration-suite placement lives in `ParityWorkspaceProjectIntegrationGateTests`; worktree integration placement and worktree source contracts live in `ParityWorkspaceWorktreeGateTests`. The focused-suite manifest must include every test in those files, including project API and instruction-scope gates that were previously omitted.
- Workspace model thread parity gates are split by behavior family. Project-context refresh, seed/summary construction, creation records, lifecycle mutation/persistence, and configuration transitions each live in separate parity files. Keep new thread/configuration source-contract checks with the family they protect instead of re-growing a broad model/thread catch-all.
- HTML renderer delegation parity gates are split by renderer family. Tool-card, top-bar, terminal, secondary-pane, transcript/review, and sidebar HTML contracts each live in focused parity files, while `ParityHTMLGateTests` remains only the broad-suite sentinel. Add new HTML source-contract checks beside the renderer family they protect.
- Top-bar parity gates are split by presentation/status, native chrome, surface/model catalog, native model picker, and integration ownership. The focused-suite manifest must list every top-bar/model-picker gate; do not use a broad top-bar catch-all for unrelated status, UI chrome, DTO, and integration contracts.
- Workspace execution-tool parity gates are split by execution responsibility. Tool-event recording, tool-call routing/override precedence, generic tool-run lifecycle, and runtime terminal/active-work/shell planning each live in separate parity files. The focused-suite manifest now verifies that each listed test is defined by its registered file so stale suite ownership fails in CI.
- Workspace surface parity gates are split by UI/surface family. Secondary pane DTO/native placement checks, composer model/mode separation, and terminal/browser surface contracts live in separate parity files instead of a broad workspace-surface catch-all.
- Workspace integration parity gates are split by workflow family. MCP/review, feedback/runtime issues, thread/slash/local environment, automation/terminal, and runtime factory coverage each live in focused parity files instead of one broad workspace-integration catch-all.
- Agent parity gates are split by agent responsibility. Final-answer formatting, mock planning, streaming/cancellation, contracts/tool-step execution, and focused behavior-suite ownership each live in separate parity files instead of one broad agent catch-all.
- Workspace model parity gates are split by model boundary. Tool-card/artifact surface delegation, UI state/send lifecycle, review-card host wiring, and execution-context enrichment each live in separate parity files instead of one broad workspace-model catch-all.
- Workspace memory parity gates are split by memory responsibility. Storage/policy helpers, WorkspaceModelMemory orchestration, integration-suite ownership, and Playwright memory spec placement each live in separate parity files instead of one broad memory catch-all.
- Workspace model-state parity gates are split by state responsibility. Status copy, context resolving, agent progress, thread mutations, and pane visibility each live in separate parity files instead of one broad model-state catch-all.
- Automation parity gates are split by automation responsibility. Core records, state factory/reducer delegation, run planning/event-source triggers, event-source adapter coverage, surface building, and Playwright flow placement each live in separate files instead of one broad automation catch-all.
- Workspace command parity gates are split by command responsibility. Native command planning, command surface/catalog construction, command-palette/ranker contracts, and Playwright command flows each live in separate files instead of one broad command catch-all.
- Workspace execution-slash parity gates are split by execution responsibility. Slash transcript planning, command action planning, and command-plan execution each live in separate files instead of one broad execution-slash catch-all.
- TrustedRouter parity gates are split by transport boundary. Action parsing/normalization, prompt building, API-key resolution, safety transport, shared chat parameters, and adapter test-suite placement each live in separate files instead of one broad TrustedRouter catch-all.
- Interaction-target parity gates are split by rendered interaction responsibility. Playwright audit contracts, HTML primitive semantics, rendered command routing, critical target registry coverage, responsive/dynamic target contracts, and Swift HTML source-audit fixtures each live in separate files, with shared text loading in a support helper.
- Command-palette E2E specs are split by workflow. Core palette behavior, worktree commands, pull request commands, pull request review, and local environment actions each own a focused Playwright spec, while shared palette open/close/selection helpers live in `harness-helpers.ts`. Keep broad `core.spec.ts` free of command-palette workflow coverage.
- Activity source commands preserve source location as typed command data, not renderer-local string conventions. Path-only Open/Edit command IDs remain stable, while diagnostic source actions may use `activity-source-*-line:<line>:<path>` so `file:line` survives Activity rendering, command parsing, model fallback, and desktop routing. Native editor opening is a desktop-only convenience for readable local files inside the active workspace; remote projects, missing files, directories, absolute paths, and workspace escapes must fall back to the normal model/tool-card path.
- Project instruction scaffolding uses one command path. `/init` and `/project init` both route to the same `project-init` action, preserving the existing no-overwrite guard, selected-project requirement, tool-card audit, and context refresh. Namespaced project aliases should add discoverability without creating a second scaffolder or bypassing the hardened AGENTS.md checks.
- Instruction diagnostic keep-side fixes are intentionally narrow and deterministic. Activity may offer direct patch actions only for two-reference semantic conflicts where the referenced path is a safe generated patch target and the loaded instruction line still matches the diagnostic excerpt. The command removes the opposite conflicting line via `host.apply_patch` and refreshes project context; exact duplicate-scope cleanup, nested-overlap line removal, and exact explicit nested-override line removal use the same audited-tool boundary, while non-identical duplicate-scope and nested-override rewrites stay manual until a merge strategy can preserve user intent.
- GitHub pull request listing is a first-class read-only PR tool, not a shell workaround. `host.git.pr.list` owns optional state and limit arguments, `GitHubPullRequestInputValidator` normalizes/bounds those arguments for local execution, SSH Remote command planning, slash parsing, and tests, and command/palette/slash surfaces should expose `/pr list` before label commands for `/pr l` discoverability.
- Run-finished notifications are a workspace-model boundary separate from composer send orchestration. `WorkspaceModelComposer` owns submit/resume, send lifecycle, progress, and terminal outcome handling; `WorkspaceModelRunNotifications` owns notification gating, verification-action dispatch, and shell verification fallback. Keep future "notify me when done" behavior in the notification extension so the composer does not grow another cross-cutting concern.
- Destructive or context-copy chat actions are unavailable while that chat owns a live agent run. Clear, delete, duplicate, fork, compact, and turn-revert can otherwise invalidate the run's persisted owner or workspace context mid-turn. The model is the final guard, while sidebar rows, bulk actions, and command surfaces project the same rule so users get immediate disabled-state feedback.
- Computer Use app approval is an executor preflight, not UI-only state. `ComputerUseAppApprovalPolicy` stores normalized bundle-identifier and app-name allowlists from `AppConfig`, `ComputerUseToolExecutor` checks that policy after backend availability and permissions, and platform foreground-app discovery lives behind `ComputerUseForegroundApplicationProviding`. An empty allowlist remains unrestricted for existing users; configured allowlists must block before any screenshot/input action reaches the backend. The Settings quick-add action edits only the unsaved settings draft, prefers a foreground app's bundle identifier for stable macOS identity, falls back to app name for Linux/helper backends, and persists through the same Save path as manual approval edits.
- Computer Use screenshot context belongs in the structured screenshot result, not in presentation-only text. `ComputerUseToolExecutor` asks the same `ComputerUseForegroundApplicationProviding` backend used by approval preflight, writes only artifact path plus metadata to stdout, and includes `foregroundApplication`, optional backend-provided `accessibilitySnapshot`, and a bounded `visualSummary` descriptor in `ComputerScreenshotToolOutput` when available. macOS owns its accessibility snapshot through a bounded AX traversal of the focused window, while unsupported or untrusted backends simply omit it. Final-answer wording can then say which app was captured and which preview artifact was attached, transcripts stay free of raw base64, and future model follow-up can reuse the same structured result without scraping assistant copy.
- Tool errors should be recovery instructions, not opaque strings. Missing file reads use bounded sibling suggestions owned by `FilePathSuggester`, directory reads point to `host.file.list`, patch failures surface the relevant hunk/file diagnostic, and TrustedRouter streaming HTTP bodies are collapsed to a single bounded line with distinct 401 sign-in and 403 permission guidance. Diagnostics must be safe to render in chat/tool cards and safe to feed back to the model.
- Worktree setup selection is task state, not a transient dialog preference. New Worktree Task offers Automatic, No setup, and bounded `[local_environments.<id>]` entries from project config; `WorktreeBinding.setupSelection` persists the choice and legacy bindings decode as Automatic. Resolution happens from the materialized checkout so transferred local config participates. Missing named environments fail visibly and never fall back to an unrelated setup script.
- Auto safety reviewer route evidence belongs in core approval payloads, not only transient safety logs. `ApprovalReviewTelemetry` lives beside `ApprovalRequest`/`ApprovalDecision` so durable transcripts can explain whether a gate came from static policy, the primary reviewer model, the fallback reviewer model, or a persisted permission rule. `QuillCodeSafety` owns filling that telemetry, preserves attempted model lists through permission-rule asks, and stores only bounded single-line error summaries so provider failures are debuggable without leaking raw prompts or oversized bodies.
- Runtime recovery should be typed, not inferred from button copy. `RuntimeIssueSurface` carries `RuntimeRecoveryTelemetry` with a route, reason, and optional command ID so Settings, transcripts, HTML smoke, and recovery planners can prove whether the app will open Settings, retry the latest turn, or show the model picker without parsing localized action labels. Action-label routing remains only as a legacy fallback for older persisted payloads.
- Native chrome density should follow Codex's separation between visible affordance and interaction geometry. Sidebar rows use the shared `quillCodeSidebarRowChrome` helper to draw compact 27 pt selected/background capsules with 12 pt horizontal inset; command rows keep the global 40 pt semantic target, while dense thread/project icon controls use 34 pt sidebar icon targets. Sidebar ellipsis/selection controls use `quillCodeSidebarIconButtonTarget` so thread rows do not inherit mobile-sized button height. The top-bar token budget is a readable `Context` meter with 15-17 pt tabular text, one progress rail, and quota detail in the tooltip/secondary slot. Future polish should tune these design-system tokens rather than adding local row heights, raw padding, or smaller token text.
- Conversation export actions should be keyboard and menu reachable, not only visible inside the command palette. `copy-conversation` now owns a shared `Cmd+Shift+C` shortcut, routes through the same transcript Markdown exporter as manual copy/export, and has a desktop menu notification path. Keep future transcript-sharing actions attached to `WorkspaceShortcutRegistry` and the desktop command planner so the Keyboard Shortcuts panel, command palette, native menu, and SwiftUI workspace stay in sync.
- Project run hooks are shell tool-card executions, not hidden lifecycle callbacks. Local `.quillcode/hooks/before-agent-run/*.sh` and `.quillcode/hooks/after-agent-run/*.sh` scripts are discovered with the same metadata and path bounds as local environment actions, then dispatched through `host.shell.run` so transcripts, approvals, redaction, cancellation, and failure reporting stay visible. SSH Remote projects discover bounded default hook scripts during context refresh and execute them through the shared `WorkspaceToolCallExecutor`, so hook commands route over SSH with the same visible tool-card and failure semantics as manual remote shell calls. Before-run hook failure stops the agent run; after-run hook failure appends a visible failure message but preserves the completed agent answer.
- Appshot and PDF previews are artifact-renderer metadata, not text previews. `.appshot.json` artifacts stay out of raw UTF-8 text previewing; `ToolArtifactAppshotPreviewBuilder` reads only bounded regular local files, extracts title/app/summary/viewport/window/timestamp fields, and resolves only same-directory local image-like screenshot paths. `ToolArtifactPDFPreviewBuilder` reads only bounded regular local PDF files, extracts lightweight title/version/page-count/size metadata, and avoids remote fetching or full text extraction. SwiftUI, static HTML, and Playwright render that metadata as embedded appshot/PDF cards while docs/sheets/slides and full PDF page renderers remain structured open cards until real embedded renderers exist.
- Curated skill packs belong in the bundled marketplace, not the base prompt. LLM Advisor, Browser Use, OpenClaw Video Toolkit, and BurstyRouter are discoverable as available Extensions with compact summaries and auditable install commands. Command-palette install/update actions index those summaries too, so intent searches such as model selection, browser automation, video/media, or local-first routing find the relevant skill without adding full playbooks to every prompt. Installing one clones/copies only the bounded skill entry point into `.quillcode/skills/<name>/` and writes a matching `.quillcode/skills/<name>.json` manifest with the update command, so the available row is shadowed by the installed project skill after refresh and `host.skill.load` can load the full `SKILL.md` only when the user or task needs it.
- Skill slash commands should produce immediate tool intent, not a vague assistant promise. `/skill name` instructs the model to call `host.skill.load` with the canonical non-empty `name` argument before following the returned skill body, and the base prompt carries the same rule for natural-language skill requests.
- Composer drafts are thread state, but not transcript state. Persist non-empty per-thread drafts on `ChatThread.composerDraft` so half-written prompts survive relaunch, keep blank drafts as nil for clean legacy JSON, and save draft edits without bumping `updatedAt` so typing does not reorder the sidebar. Agent progress/completion snapshots must preserve the live model-owned draft value because those snapshots start from a stale send-start copy of the thread.
- Branded TrustedRouter model capability tags are curated product taxonomy, not guessed provider telemetry. Nike/Zeus/Prometheus/Socrates/Aristotle/Plato fallback rows carry stable summaries, text/tool modalities, and searchable capability tags so offline and fallback pickers keep useful search. Live TrustedRouter catalog duplicates still backfill concrete fields such as context window, pricing, status, release date, extra modalities, and provider capability tags without replacing the branded identity.
- Bundled provider discovery rows are not branded defaults. Keep Nike/Zeus/Prometheus/Socrates/Aristotle/Plato as the only Recommended product names, but the fallback catalog may include a small number of unbranded provider rows such as `minimax/minimax-m3` so offline and failed-refresh model search can still find common TrustedRouter catalog providers users expect.
- Local spend controls are user-visible Settings state, not hidden config-file only state. The top bar may show day/week/month cap rows from `run_spend_*_limit_usd`, while Settings owns the editable draft and must label these as local display/review controls rather than TrustedRouter account quotas. Provider-reported quota APIs remain a separate future integration.
- Project reordering is one command-dispatch path regardless of surface. Row-menu actions, command-palette rows, and `/project top|up|down|bottom` slash aliases all route through `WorkspaceCommandActionPlanner` and the existing `QuillCodeWorkspaceModel.moveProject*` APIs, so persistence, top-bar refresh, and boundary behavior stay identical across entry points.
- Skill browsing is a focused Extensions view, not a generic alias. `/skills` and the Skills command-palette row route to `show-skills`, which opens the existing Extensions pane filtered to `ProjectExtensionKind.skill`; `/extensions` and `/plugins` keep the all-extension toggle. Keep future plugin/MCP focused views on the same `ExtensionsState.focusedKind` path so counts, install actions, command routing, SwiftUI, and the HTML harness stay aligned.
- Image input is typed conversation state, not prompt text or an arbitrary file-path shortcut. `ChatAttachment` carries bounded metadata; `ImageAttachmentStore` is the only importer/reader and copies supported images into private `~/.quillcode/attachments/<thread-id>/` storage. The TrustedRouter prompt adapter must revalidate managed-root containment, regular-file status, exact byte count, and image magic bytes before producing OpenAI-compatible multimodal content, so hand-edited thread JSON or replaced symlinks cannot upload unrelated local files. Composer images persist separately from transcript messages until send, then move atomically onto the user turn or follow-up queue; agent snapshots preserve the live UI-owned composer attachment list just like drafts and queued follow-ups.
- Native terminal pointer capture is a platform-adapter responsibility. `QuillCodePlatformUI` owns AppKit mouse, hover, modifier, and scroll-wheel events and converts them into platform-neutral `TerminalMouseInputRequest` values. `QuillCodeApp` owns presentation and callback routing, while `QuillCodeTools` owns cell-independent protocol encoding and bounded wheel quantization. This keeps platform imports and conditionals out of the app layer and prevents native, static HTML, and Playwright surfaces from inventing different terminal escape semantics.
- Computer Use visual continuation reuses image-input ownership rather than adding a screenshot upload path. Per-send runners write screenshot artifacts directly under `~/.quillcode/attachments/<thread-id>/computer-use`, `ImageAttachmentStore` adopts that already-managed file without copying it, and `AgentRunner` attaches it only to hidden feedback for a successful `host.computer.screenshot` call. The TrustedRouter prompt adapter emits image-bearing tool feedback as a multimodal user continuation because OpenAI-compatible assistant messages do not accept image input, while text-only tools retain their existing assistant-shaped feedback. Prompt caching keeps its breakpoint on the latest eligible plain-text user request and never rewrites image blocks. Screenshot pixels are untrusted page content, not instructions.
- Native terminal keyboard capture follows the same adapter boundary as pointer input. `QuillCodePlatformUI` maps AppKit key events and clipboard paste into platform-neutral requests, while `QuillCodeTools` owns xterm sequence encoding plus shared incremental DEC private-mode parsing. The workspace accepts a request only when its captured application-cursor/bracketed-paste mode still matches the live PTY state, preventing a SwiftUI rerender or late event from sending bytes encoded for a stale terminal mode. Paste input is bounded and strips embedded bracketed-paste boundaries before framing.
- Agent task ownership is per chat, not global. Desktop task slots use the originating chat ID, `WorkspaceAgentRunRegistry` owns session-only live statuses, and every model send/resume/progress/finish path receives the explicit run chat ID. This allows multiple chats to work concurrently without a completion, retry notice, approval continuation, or notification mutating whichever chat the user currently has selected.
- A background run is pinned to the project/worktree recorded by its chat at launch. Context refresh, extension manifests, workspace root selection, and completion verification resolve from that chat rather than `selectedProject`; changing the visible chat or project cannot redirect an in-flight command.
- The selected composer reports only the selected chat's sending state. Background work is summarized in the top bar and shown as a compact live sidebar indicator, while the global Stop All command remains enabled whenever any chat owns an active run and cancels every per-chat send slot.
- Local/Worktree Handoff preserves one task and one stable managed-worktree association. `WorktreeBinding.location` selects the active checkout while legacy bindings decode as Worktree. Handoff is available only for detached managed tasks whose Local and Worktree checkouts belong to the same repository and whose worktree still exists. Matching commits retain the existing exact-snapshot behavior; when commits differ, Handoff advances a clean destination only when Git proves its commit is an ancestor of the source, using `git merge --ff-only` and restoring the original destination commit if a later transfer step fails. A destination that is ahead, dirty during a history move, or diverged fails without intentional mutation. Staged, unstaged, and nonignored untracked state is frozen, applied, and verified against both checkouts before source cleanup. Ignored files stay in place, and branch-owned managed worktrees remain outside Handoff because Git cannot check out one branch in both locations.
- **Create branch here** is a branch-ownership transition, not a new worktree or Handoff. It is offered only for an idle, resolvable, detached managed task running in its Worktree checkout; it validates the branch name, executes argv-only `git switch -c`, verifies the branch from Git, persists that owner on the existing `WorktreeBinding`, and keeps the same thread, project association, path, and execution location. Once a branch is owned, Create branch and Handoff disappear because Git cannot safely check out that branch in the Local checkout. Successful agent and terminal runs reconcile actual Git branch ownership so branch creation outside the dedicated dialog cannot leave stale UI state; app tool runs reconcile only branch-changing tools so Handoff and unrelated successful tools cannot accidentally claim ownership from another checkout.
- Managed worktree archive cleanup is an ownership-sensitive persistence transaction. Only an idle, unpinned, detached task running in an app-owned Worktree is disposable; pinned tasks, running tasks, Local handoffs, and named-branch worktrees remain untouched. `ManagedWorktreeSnapshotStore` writes staged/unstaged patches plus bounded safe local files to a private temporary directory, records repository identity and the exact HEAD, writes a versioned manifest, and atomically promotes that directory under `~/.quillcode/worktree-snapshots`. The thread persists only `WorktreeSnapshotReference` before the store re-captures and byte-compares the live commit, index, working tree, and local files at the removal boundary; concurrent mutation fails closed and keeps the worktree. Restore validates the manifest, original destination, repository common directory, payload files, and full captured commit, creates a detached checkout at that commit, applies the snapshot transactionally, byte-compares the restored state, and removes a partial checkout on failure. Snapshot deletion happens only after restored thread state is durably saved, and deleting a chat also deletes its snapshot payload.
## 2026-07-12: Managed worktrees use an app-owned root and snapshot-backed recent-task retention

- **Decision:** New managed worktrees live under `~/.quillcode/worktrees` by default. Settings can select another absolute or home-relative root, disable automatic cleanup, or change the default recent-task limit of 15.
- **Ownership boundary:** Every managed binding persists the root that authorized its checkout. Create/open/remove/snapshot/restore operations accept only registered paths inside that root (with legacy sibling-layout compatibility), reject the root itself, and resolve symlinks before boundary checks. Changing Settings does not broaden authority over older tasks.
- **Retention:** The planner counts only active, detached, app-owned Worktree tasks and removes the oldest eligible tasks until the limit is met. Pinned, selected, running, Local, named-branch, missing, already-snapshotted, and duplicate-path-bound tasks are protected. Duplicate ownership is checked after symlink resolution, and safety may keep the active count above the configured limit. Enforcement runs at startup, after managed creation, settings changes, unpinning, run completion, and thread selection changes.
- **Data safety:** Automatic removal uses the same transaction as archive cleanup: capture a repository-bound staged/unstaged/local-file snapshot, persist its reference on the thread, then re-capture and byte-compare the live state at the removal boundary before removing the registered checkout. Snapshot, persistence, verification, concurrent-change, or removal failure keeps the checkout. Reopening restores at the captured commit and verifies the restored bytes.
- **Why:** This matches the current Codex managed-worktree contract while keeping cleanup authority narrow, durable, and auditable.

## 2026-07-12: Managed worktree setup is project-local, platform-aware, and transcripted

- **Decision:** A newly created managed Worktree task automatically looks for `.quillcode/setup.macos.sh` or `.quillcode/setup.linux.sh`, then falls back to `.quillcode/setup.sh`. Projects may override those bounded relative `.sh` paths in `[worktree_setup]` inside `.quillcode/config.toml`.
- **Execution boundary:** Resolution happens from the newly materialized checkout, after local state and `.worktreeinclude` files have transferred. Symlink escapes, absolute paths, parent traversal, missing files, and non-shell files are ignored. Platform detection lives in `QuillCodeTools`, so the app target contains no platform conditionals.
- **Visibility and recovery:** Setup runs through the existing `host.shell.run` coordinator in the new worktree. The task transcript therefore preserves redacted inputs, stdout/stderr, timeout, success/failure, and the normal rerun path. Failure keeps the worktree intact for inspection instead of deleting useful diagnostics or silently starting in a half-understood environment.
- **Metadata:** A same-name JSON sidecar reuses the local-script environment, working-directory, and timeout policy. Environment values remain redacted in persisted tool-card inputs.
- **Why:** This matches Codex's automatic worktree setup behavior without introducing a hidden process runner or weakening QuillCode's workspace/path boundaries.
- **Configuration failures:** Conventional setup remains optional and quiet when no setup file exists. Once a project explicitly adds `[worktree_setup]`, invalid or missing paths fail closed with a task notice and repair guidance; an invalid override never falls back to a different conventional script. A setup process failure retains its shell card and also adds concise task-level recovery copy.

## 2026-07-13: Subagents are isolated configured agent sessions, not tool-free model calls

- **Decision:** Every production `/subagents` worker runs a fresh ephemeral `ChatThread` through `WorkspaceAgentSendSessionFactory` and the normal multi-step `AgentRunner`. The child inherits the parent chat's project, worktree, model, mode, instructions, memories, and durable goal; the factory supplies the same permissions, spend fuse, local/SSH routing, browser, Computer Use, memory, MCP, hooks, and LSP wiring as a normal turn.
- **Ownership:** The scheduler is constructed when the slash command starts, from the originating chat's immutable execution context. Test-only scheduler injection is explicit through `subagentSchedulerOverride`. Progress and the final summary are addressed by the originating thread ID rather than current UI selection, so switching chats cannot redirect a running delegation.
- **Safety:** A child never weakens the parent's mode. Auto-mode calls use the configured reviewer and permission rules. Review gates persist the exact unredacted held call in an owner-only store addressed by an opaque key; the parent keeps only compact approval metadata. Run requires an exact request/tool/generation match, consumes that payload once, executes through the normal router, and resumes without adding a duplicate user turn. Skip records synchronously before any await, deletes the payload, and serializes dependency cleanup behind any parent send.
- **Privacy and observability:** The parent receives bounded, credential-redacted summaries and compact transcript projections for quick Activity inspection. Full child transcripts remain isolated under a private child-thread root and load only for explicit drilldown. Compact parent manifests retain stable run, worker, child, dependency, status, and approval-phase identity without duplicating raw tool payloads.
- **Crash semantics:** A worker that was running at termination becomes Interrupted and is never replayed implicitly. A valid pending approval survives relaunch. A half-executed approval, mismatched payload, or child decision ahead of its parent checkpoint is reconciled to Interrupted and loses replay authority. Parent delete/clear removes child transcripts, raw approval payloads, and managed attachments; archive retains them.
- **Migration:** Older whole-session approval journals remain readable through an explicit compatibility adapter. New production runs never write that format, and stale legacy Running state is reconciled to Interrupted rather than queued for replay.
- **Verification:** Focused tests cover real file writes, continued model turns after a tool, inherited context/tool catalogs, Review-mode blocking, cancellation, chat switching, recursive delegation, SSH Remote shell routing, exact approval identity, one-shot execution, denial/dependent cancellation, deferred graph continuation, persistence permissions, relaunch reconciliation, historical Activity drilldown, and parent lifecycle cleanup.

## 2026-07-13: Side conversations are transient runtime forks

- **Decision:** `/side` and `/btw` create an in-memory `ChatThread` fork from the selected task's visible history. The fork inherits project, model, mode, instructions, memories, worktree context, and tool definitions, but it receives no durable goal and is never written by `ThreadPersistence` or projected into sidebar groups.
- **Runtime ownership:** The side conversation receives its own agent task slot, so an active parent task continues independently. The prompt appends a side-conversation boundary after inherited history: history is reference-only, mutations require an explicit request made inside the side conversation, subagents are unavailable, and the model must not claim it changed the parent.
- **Lifecycle:** A persistent banner names the parent, reports whether it is working or idle, and provides Return. Returning, selecting another task/project, or starting a new task removes the transient fork; desktop-owned cancellation stops any active side task first. Nested side conversations and normal rename, duplicate, pin, archive, clear, revert, compact, fork, and delete actions are unavailable.
- **Persistence boundary:** Runtime context is intentionally non-Codable. Legacy and current persisted threads always decode as standard tasks, and persistence rejects ephemeral saves even if a caller bypasses the workspace model.
- **Why:** This matches Codex's low-friction "ask without derailing the task" workflow while making the non-persistent and non-mutating boundary visible, testable, and impossible to confuse with a durable task branch.

## 2026-07-13: Subagent transcripts combine compact progress with private child state

- **Decision:** A worker returns a bounded `SubagentTranscriptEntry` projection for the normal `SubagentProgressItem` plus a stable private child-thread identity in the scheduler manifest. The compact projection keeps Activity immediately useful; the private child thread preserves the complete chronological timeline required for safe resume and support diagnostics.
- **Privacy boundary:** The projection includes only redacted tool-card milestones and assistant responses. It excludes generated prompts, raw tool payloads, system text, and tool-feedback messages. Full transcripts and held approval calls live in separate private stores and are loaded only by exact parent/run/worker identity.
- **Presentation:** Activity keeps the compact native/static transcript disclosure and adds a View action for every current or historical durable worker. The native drilldown reuses normal message, thinking, and tool-card surfaces and exposes Run/Skip only for the exact pending generation.
- **Compatibility:** Legacy progress records decode with an empty transcript, empty projections are omitted when encoding, and injectable summary-only scheduler workers keep their source-compatible initializer.
- **Why:** The dual representation preserves low-cost replay and cross-surface visibility without sacrificing exact approvals, restart recovery, or full diagnostic history.

## 2026-07-13: Subagent approvals use separate one-shot payloads

- **Decision:** A delegated worker that reaches an approval gate persists its child thread, compact parent checkpoint, and exact held tool call separately. Activity receives only bounded request/tool/reason metadata and generation-bound Run/Skip actions; executable arguments never enter the parent transcript.
- **Durability:** Child threads and raw calls use owner-only directories and `0600` files. Relaunch reconciliation requires matching parent/run/worker/generation/request identity before preserving an approval. Run consumes the exact payload once and resumes the existing child without duplicating its user turn; Skip records its decision and deletes the payload before graph continuation.
- **Replay safety:** A stale second action, missing payload, mismatched child decision, or half-executed approval cannot run again. Independent workers continue normally, and graph continuation affects only the paused worker and its dependents.
- **Compatibility:** `WorkspaceSubagentSessionStore` remains a migration reader for whole-session journals written by older builds. New runs use the compact manifest, private child, and separate payload stores exclusively.
- **Verification:** Agent and integration tests cover exact execution, duplicate rejection, relaunch, migration, denial, dependency continuation, current-thread independence, permissions, and action removal.

## 2026-07-13: Model-authored delegation is execution, not progress decoration

- **Decision:** Normal agent turns advertise `host.subagents.run`, a structured request containing one shared objective and a bounded worker graph. Executing it launches `WorkspaceSubagentScheduler`; `host.subagents.update` remains the replay/projection contract and explicit slash-command implementation detail, not a model-facing substitute for doing the work.
- **Thread ownership:** Some tools update durable state owned by the originating chat while they run. `AgentThreadToolExecutionOverride` is the narrow agent-layer boundary for those tools: it returns both the `ToolResult` and the updated thread snapshot. The app installs the subagent executor per configured send session and persists every scheduler checkpoint through the originating parent ID, independent of current UI selection.
- **Consolidation and privacy:** The parent model receives only the run ID, aggregate summary, bounded worker metadata, status, and redacted summaries. Full child messages, raw tool payloads, screenshots, and held approvals remain in private child/payload stores and are available only through explicit Activity drill-down. The parent continues in the same turn after the tool completes, so an ordinary request for parallel work produces one consolidated answer without a second user prompt.
- **Recursion boundary:** Child sessions do not receive `host.subagents.run`. Recursive work stays inside the scheduler's existing bounded depth/job controls through the parsed `[[DELEGATE: name | role]]` marker, preventing independent untracked scheduler trees while retaining deliberate nested delegation.
- **Wire contract:** Worker `name` and `role` are required. `dependsOn` and `groupPath` are optional and decode to empty arrays. Requests reject duplicate names, self/unknown dependencies, empty fields, excess workers, and invalid concurrency before any child starts.
- **Verification:** Native integration tests cover one-turn execution, live manifest persistence, private-transcript exclusion, and child recursion limits. Playwright covers the Running/Queued to Done transition, the real run-tool card, parent consolidation, worker transcript disclosure, approval actions, and the separate `/subagents` route. A parity source gate requires all of these ownership paths to remain wired.

## 2026-07-13: Standard plugin packages project into existing audited runtimes

- **Decision:** A local package under `.quillcode/plugins/<name>` may use the standard `.codex-plugin/plugin.json` entry point. QuillCode projects its package-relative `skills` and `mcpServers` references into ordinary `ProjectExtensionManifest` rows instead of creating a second plugin execution engine.
- **Discovery boundary:** Discovery reads only bounded regular JSON and `SKILL.md` files. Package directories, component references, and skill entries are symlink-resolved and must remain inside the project/package roots; discovery never starts a process. Direct project manifests shadow a package with the same plugin ID.
- **Skill precedence:** Direct project skills remain first, enabled plugin skill roots follow in deterministic package order, and global skills remain last. The live `host.skill.load` definition advertises the bounded available-name set so bundled skills are discoverable without injecting their full instructions into every prompt.
- **MCP execution:** Bundled MCP servers use the existing explicit Start/probe/Ready/call lifecycle. Stdio servers launch with direct argv from the revalidated package working directory; `${CODEX_PLUGIN_ROOT}` expands in command, args, and declared environment values without invoking a shell, and `CODEX_PLUGIN_ROOT` is passed explicitly.
- **Why:** Standard package compatibility should reuse QuillCode's existing safety, transcript, and lifecycle boundaries. One audited skill/MCP runtime is simpler and safer than plugin-specific execution paths.

## 2026-07-13: Standard repository marketplaces install local packages as data

- **Decision:** QuillCode discovers the official repo marketplace at `.agents/plugins/marketplace.json`, with `.claude-plugin/marketplace.json` as a lower-precedence legacy source. It accepts the standard plain-string and `{ "source": "local", "path": ... }` local forms, honors `NOT_AVAILABLE`, and filters IDs already claimed by installed or higher-precedence entries.
- **Acquisition boundary:** Only explicit `./` paths inside the selected project are eligible. Git, git-subdirectory, npm, and other remote sources remain unavailable until signed acquisition and provenance verification exist. Catalog loading never runs package or lifecycle code.
- **Install transaction:** Install is a dedicated internal tool, not a marketplace-provided shell command and not an agent-advertised tool. It revalidates the source, plugin identity, manifest size, package file/byte caps, absence of symlinks, and destination collision; copies to a private sibling staging directory; validates the staged copy again; then atomically moves it under `.quillcode/plugins/<id>`.
- **Presentation:** Available packages reuse the existing Plugins pane, command palette, tool-card recording, metadata refresh, and installed-package runtime. Once installed, the catalog row disappears and the discovered package plus its bounded skills/MCP components replace it.
- **Why:** Matching the Codex marketplace shape should not create an unaudited package manager. A data-only local path gives repo teams immediate compatibility while preserving a narrow, deterministic mutation boundary for future signed remote and reviewed hook support.

## 2026-07-13: Standard plugin hook trust follows the exact definition

- **Decision:** QuillCode discovers a package's manifest-relative `hooks` file or default `hooks/hooks.json`, parses every bounded standard hook definition for inspection, and executes only a deliberately supported subset after explicit trust. Trust and disable decisions are scoped to the canonical workspace and exact normalized definition hash, not merely the package or hook ID.
- **Execution boundary:** The executable subset is synchronous `command` handlers for `UserPromptSubmit`, `Stop`, `PreToolUse`, `PostToolUse`, `PermissionRequest`, `PreCompact`, `PostCompact`, `SessionStart`, `SubagentStart`, and `SubagentStop`. Each family enters through its typed runtime boundary so ordering relative to model context, safety review, approval, execution, compaction, and delegated-worker completion is invariant. Other event names, prompt/agent handlers, asynchronous handlers, invalid matchers, and missing commands remain visible and inert.
- **Persistence:** Hook decisions live in an owner-local atomic store. Missing, malformed, future-version, duplicate, or invalid records fail closed; a degraded store is never overwritten by a new trust action. Editing any trusted definition changes its hash and returns it to Review required.
- **Presentation:** `/hooks`, the command palette, native Extensions pane, static renderer, and Playwright harness share the same focused Hooks surface. Unsupported definitions explain why they cannot run and never offer a misleading Trust action.
- **Why:** Standard plugin compatibility must not create a hidden process lane. Exact-definition trust gives users a stable review boundary while reusing QuillCode's already-audited hook execution path.

## 2026-07-13: Standard hook commands receive one bounded execution envelope

- **Decision:** Every supported standard plugin command receives newline-terminated JSON on stdin. Common fields are `session_id`, nullable `transcript_path`, canonical `cwd`, `hook_event_name`, `model`, and `turn_id`; events that define it add mapped `permission_mode`. `UserPromptSubmit` adds `prompt`, while `Stop` adds `stop_hook_active` and `last_assistant_message`.
- **Plugin paths:** Package roots are revalidated inside the workspace for every invocation. `PLUGIN_ROOT`/`CLAUDE_PLUGIN_ROOT` point at that root, while `PLUGIN_DATA`/`CLAUDE_PLUGIN_DATA` point at a stable private directory isolated by canonical workspace and plugin ID. Package root is part of the trusted definition hash, so moving executable code invalidates prior trust.
- **Execution:** All matching synchronous command handlers launch concurrently as the standard contract requires. Notices and tool cards are projected in deterministic configuration order after completion, and the first configured failure retains the existing before/after failure policy.
- **Privacy and bounds:** Shell stdin is capped at 1 MiB, closes with EOF, and is redacted alongside environment values before any tool call reaches persisted transcript state. The non-streaming shell runner drains stdout and stderr while the process runs, preventing pipe-buffer deadlocks from chatty hooks.
- **Output boundary:** Output interpretation is limited to trusted standard plugin hooks. Existing QuillCode project scripts retain their exit-code-only behavior, so adopting the standard protocol does not reinterpret legacy script output.

## 2026-07-13: Standard hook output is typed, bounded, and loop-safe

- **UserPromptSubmit:** Plain stdout and matching `hookSpecificOutput.additionalContext` become bounded hidden system context before the model call. Common `systemMessage` fields become visible notice events without entering the chat transcript. A JSON `decision:block`, common `continue:false`, or exit code 2 prevents the model call with a concise reason.
- **Stop:** Successful stdout must be an object-shaped JSON response. A blocking decision or exit code 2 creates a new user continuation turn using the reason. That turn reruns UserPromptSubmit hooks, sends `stop_hook_active=true` to its Stop hooks, and cannot trigger a third automatic turn. The continuation marker binds to the generated user-message ID so an approval pause/resume keeps the correct prompt and loop guard. If any concurrent Stop hook returns `continue:false`, it overrides every continuation request.
- **Bounds and compatibility:** Context is capped per hook and in aggregate; warnings and reasons have smaller caps. Known fields with wrong types, mismatched event names, malformed Stop output, and blocking decisions without a reason fail closed. Unknown fields remain forward-compatible, and `suppressOutput` is type-checked but otherwise left inert to match the documented current behavior.
- **Presentation:** Semantic exit code 2 is recorded as a completed policy hook rather than a failed process. Hidden system/tool messages are excluded from transcript surfaces and exports, while warnings and control outcomes remain auditable through notices, tool cards, and explicit assistant explanations.
- **Why:** Hook output can alter model behavior and run control, so it needs one strict parser and one deterministic aggregation point. A durable, one-turn continuation marker preserves correctness across approval boundaries without introducing a second agent loop.

## 2026-07-13: Tool hooks intercept one stable agent lifecycle boundary

- **Ordering:** `PreToolUse` runs once after the model selects a known tool but before the queued event, safety review, approval hold, or execution. `PostToolUse` runs after the real execution result, including nonzero results and approval resumes, but before tool feedback is returned to the model.
- **Canonical adapters:** The app maps only shell, patch, and MCP calls into the standard names `Bash`, `apply_patch` with `Edit`/`Write` aliases, and normalized `mcp__server__tool`. A rewrite may replace only that call's command, patch, or MCP argument object; the agent independently rejects changes to the tool name or call ID.
- **Concurrent aggregation:** Matching trusted commands launch concurrently and their outcomes are folded in configuration order. Denial wins globally. The first valid input rewrite wins and later rewrites produce an auditable warning, making behavior deterministic without serializing independent hook processes.
- **Approval durability:** The effective rewritten call is the call stored in `AgentPendingApproval`. Resuming an approval executes that exact held call and runs only the post hook, so pre-hook side effects and policy decisions are never duplicated.
- **Feedback and privacy:** Post hooks can replace only model-facing feedback; they cannot change actual success, exit status, or artifacts and cannot claim that a completed side effect was undone. Hook context is stored as hidden system context for model continuity and is excluded from transcript rendering, export, fork, sidebar search, and compaction surfaces.
- **Remaining scope:** Other standard lifecycle events remain visible but inert until their owning runtime has an equally explicit boundary; session and subagent hooks use their separate typed coordinator described below.

## 2026-07-13: Permission hooks may resolve only approvable gates

- **Boundary:** `PermissionRequest` runs only after safety returns `clarify`. It never runs for already-approved calls or hard `deny` verdicts, so a plugin cannot weaken QuillCode's non-overridable safety policy.
- **Aggregation:** Matching trusted commands run concurrently and fold in configuration order. Any deny wins; otherwise any allow executes the exact effective call immediately; no decision, malformed output, timeout, or command failure preserves the ordinary durable approval UI.
- **Input:** Hooks receive the same canonical shell, patch, and MCP names and effective post-`PreToolUse` input. `tool_input.description` falls back to the safety rationale only when the tool did not supply one. Permission payloads deliberately omit `tool_use_id`, and permission output cannot rewrite input, permissions, or interrupt state.
- **Durability and audit:** Hook allow proceeds through normal running/result/`PostToolUse` ordering without creating an actionable approval card. Hook deny returns a failed tool result to the model without execution. Bounded notices identify allow, deny, warning, and failure outcomes without persisting command stdin or environment secrets.
- **Why:** Approval ownership belongs in the agent, not the view layer. A typed allow/deny/no-decision adapter keeps plugin JSON outside core orchestration while making failure behavior explicit and preserving the existing approval-resume invariant.

## 2026-07-13: Compaction hooks share one mutation boundary

- **Lifecycle:** `PreCompact` runs before summary generation or thread mutation. `PostCompact` runs only after `ThreadCompactor` reports a real compaction, never for `.noOlderTurns`. Both manual and automatic paths use the same typed `AgentCompactionHookOutcome`; plugin JSON remains in the app adapter.
- **Triggers and input:** Matchers receive only `manual` or `auto`. Stdin adds that `trigger` to the common turn-scoped fields and omits tool-specific and `permission_mode` fields, matching the documented event contract.
- **Stop semantics:** An explicit common `continue:false` before compaction leaves the original history intact. The same response after compaction preserves the compacted thread but prevents an automatic model retry. Manual compaction has no continuation to cancel, so it keeps the new thread and records the post-stop reason.
- **Failure semantics:** Matching commands launch concurrently and fold in configuration order. Any explicit stop wins, while command failures, timeouts, malformed output, and invalid common-field types become bounded visible warnings and compaction continues. Cancellation remains cancellation and is never downgraded.
- **Why:** Context recovery is a reliability mechanism. Plugins may deliberately gate it, but an accidental hook failure must not turn a recoverable overflow into a lost coding session.

## 2026-07-13: Session and subagent hooks bind to durable runtime identities

- **Session lifecycle:** An in-memory coordinator assigns one pending `SessionStart` source per thread. Persisted threads begin as `resume`; newly created threads use `startup`; clear re-arms the same thread ID as `clear`; compacted threads are registered explicitly as `compact`. Source is typed at creation rather than inferred from display text, and one coordinator spans every send-session factory in the workspace.
- **Subagent lifecycle:** `SubagentStart` runs before the first delegated model turn. `SubagentStop` runs after the worker's normal Stop hook and receives parent session/turn identity, stable scheduler worker ID/type, nullable private child-transcript path, the last assistant message, and a loop-active flag. Approval resume reconstructs the exact job identity and never reruns SubagentStart.
- **Output and loops:** SessionStart and SubagentStart may return plain or structured bounded context, stored as hidden system context. SubagentStart ignores common `continue:false` as documented. SubagentStop requires object JSON; `decision:block` or exit code 2 requests one user continuation, while common `continue:false` wins and a second request is recorded but ignored. The continuation marker is durable across an approval pause.
- **Failure boundary:** Matching trusted commands run concurrently and fold in configuration order. Invalid output, process failure, or timeout produces a bounded visible warning and leaves the session or worker running. No lifecycle hook can bypass ordinary safety review for tools selected during injected or continued turns.
- **Why:** Lifecycle compatibility is useful only if it cannot duplicate startup side effects, lose worker identity across approvals, or form an unbounded autonomous loop. Explicit typed ownership makes those invariants testable without spreading plugin JSON through the agent core.

## 2026-07-13: Finishing a managed task is a recoverable Local transition

- **Decision:** **Finish task in Local** is available only for an idle, local-project, detached managed task. It first runs the existing verified Handoff into the original Local checkout, switches the chat's execution location to Local, then asks Git to remove the associated worktree without force.
- **Durability:** The worktree binding is cleared only after Git confirms removal. If removal fails because the checkout changed concurrently, the transferred task remains in Local, the binding remains durable, and the command becomes **Finish worktree cleanup** so the user can inspect and retry. An already-missing checkout in the Local state clears only the stale binding.
- **Boundary:** Finish never invents a second transfer format and never broadens worktree-path authority. Handoff destinations must exactly match a path from `git worktree list --porcelain`; absolute app-owned roots and legacy relative sibling names both resolve to that registered path. Named-branch worktrees remain ineligible.
- **Presentation:** A confirmation sheet explains transfer, non-force cleanup, concurrent-edit preservation, and the Local destination. The command is discoverable in the command palette and appears in the top-bar overflow only while actionable, avoiding another persistent top-bar control.
- **Verification:** Real-repository tests cover committed plus staged/untracked transfer, managed roots outside the project parent, successful removal, non-force cleanup failure and retry, stale-binding cleanup, command availability, native/static rendering, and the complete Playwright confirmation/recovery flow.

## 2026-07-13: Publishing a named worktree branch is inspected, then audited

- **Decision:** An idle named local worktree exposes **Publish branch** in the top bar and command palette. The action verifies that the checkout still owns the persisted branch, then inspects dirty state, base progress, upstream tracking/divergence, and an existing pull request before choosing any mutation.
- **Safety boundary:** Dirty worktrees show a normal Git status card and stop. Branches behind their upstream stop before mutation. A branch with no committed progress beyond its known base and no PR also stops. Inspection never changes the checkout or remote.
- **Audit boundary:** Push, PR creation, and PR refresh all run through `QuillCodeWorkspaceModel.runToolCall`, so existing safety review, transcript cards, execution context, and failure behavior remain authoritative. The coordinator does not invoke a hidden mutation command.
- **Behavior:** A first publish pushes to the existing upstream remote or `origin`, sets tracking when needed, and opens a filled PR. Later publishes avoid redundant pushes and refresh the open PR. GitHub lookup warnings remain visible and the normal PR tool reports any actionable authentication failure.
- **Presentation:** The compact action appears only while publishable and retains the shared 40-point hit target, press feedback, help, accessibility label, and native/static/Playwright command ID parity.

## 2026-07-14: Pull request landing is durable and cleanup is exact

- **Durable identity:** Publishing stores the PR number, URL, base branch, head branch, exact head commit, lifecycle status, merge state, and refresh time on the task. Older task records decode without a PR, and side conversations inherit the parent task's link.
- **Authoritative refresh:** GitHub remains the source of truth. Refresh resolves the persisted PR by number and updates task state; queued, merged, and closed states are never inferred from a successful local command alone.
- **Landing boundary:** **Land pull request** is available only for an idle, clean, synchronized named worktree whose current branch and exact `HEAD` match the linked open PR. It requests squash auto-merge through the existing audited `host.git.pr.merge` tool and then refreshes the PR instead of silently deleting anything.
- **Cleanup boundary:** **Clean up merged worktree** appears only after GitHub reports the PR merged. Removal rechecks a clean registered checkout, exact branch, and exact merged head, calls non-force `host.git.worktree.remove`, and clears only the worktree binding after success. A missing checkout clears stale binding metadata; drift or local changes preserve the checkout for inspection.
- **Presentation and verification:** Sidebar and top bar show Draft/Open/Queued/Merged/Closed state with one lifecycle action at a time. Native, static HTML, and Playwright surfaces share command IDs, icons, 40-point targets, and the publish-to-queued-to-merged-to-cleaned flow while retaining task and PR history.

## 2026-07-14: Queued pull requests reconcile without background mutation

- **Decision:** Relaunching QuillCode or selecting a task with a nonterminal linked PR refreshes GitHub status off the main actor. Queued PRs poll every 15 seconds until they leave the queue; selecting another task cancels the prior monitor.
- **Mutation boundary:** Reconciliation may update durable PR metadata and may clear a merged worktree binding only when the checkout path is already absent. It never removes an existing checkout, invokes merge, or bypasses the explicit cleanup command.
- **Failure boundary:** Authentication, network, malformed-response, and identity-mismatch failures stay silent in the background and stop polling. Manual Refresh remains the visible diagnostic path, while stale async results are discarded unless task ID, PR number, and head branch still match.
- **Why:** Merge queues commonly finish after the user leaves the task or relaunches the app. The UI should become truthful without repeated manual refreshes, but background convenience must never broaden the exact-head and non-force cleanup safety boundary.

## 2026-07-14: New Chat is an immediate typing transition

- **Behavior:** Every rendered `new-chat` command creates and selects exactly one chat, then returns focus to the composer. A user can click New Chat and type without a second click; command-palette and keyboard routes keep the same shared command plan.
- **Native proof:** Packaged macOS smoke AX-presses the real New Chat control, compares typed thread-set snapshots, requires one newly selected ID, focuses `quillcode-composer-input`, performs reversible AXValue text entry, and removes only the temporary smoke chat before restoring the prior selection and draft.
- **Sequencing:** Accessibility activation contracts declare whether they mutate a transient surface or replace the workspace. Transient dialogs and panes run first; workspace-replacing actions run last and every target is resolved from a fresh AX tree. This prevents a valid view replacement from leaving later checks attached to stale native elements.
- **Why:** A large hit target does not prove an app is ready for input. Creation count, selection, focus, text entry, and restoration are one interaction contract and one release gate.

## 2026-07-14: Model catalog search is a packaged interaction contract

- **Behavior:** Opening the composer model control presents the picker and focuses model search immediately. Typing a branded model query must surface the corresponding catalog row without requiring another click.
- **State ownership:** Desktop model-picker presentation is owned beside the other desktop presentation bindings, rather than hidden as view-local state. This lets commands, recovery paths, and packaged smoke observe and restore one authoritative value.
- **Native proof:** Packaged macOS smoke AX-presses the real composer model control, enters `Prometheus` through AXValue, requires the identified `trustedrouter/fusion` row with a `Prometheus 1.0` label, clears the query, and closes the picker back to its baseline without changing the selected model.
- **Why:** Browser-level catalog tests cannot prove that a native popover focuses correctly or that its SwiftUI rows survive accessibility projection. Search, result identity, and reversible cleanup are one release gate.

## 2026-07-14: Settings is a rendered-and-dismissible packaged contract

- **Behavior:** Opening Settings must render recognizable dialog content and expose a direct close action; a Boolean presentation flag is not sufficient.
- **Native proof:** Packaged macOS smoke AX-presses Settings, requires the identified title and notifications control, presses the identified Close control through AXPress, and waits for the dialog to disappear.
- **State safety:** Smoke does not edit preferences, authentication, keys, spend caps, or Computer Use approvals; it restores the baseline presentation state.
- **Why:** Settings is a critical recovery and configuration surface. Release evidence must prove users can enter and leave it, not merely that command dispatch toggled state.

## 2026-07-14: Automations has one obvious reversible navigation path

- **Behavior:** The Automations pane exposes a compact Close action in its header; sidebar, shortcut, slash-command, and pane-close routes all use the same `toggle-automations` command.
- **Native proof:** Packaged macOS smoke AX-presses Automations, requires the identified title and Create control, presses the identified Close control, and waits for the pane to disappear.
- **State safety:** Verification creates, edits, runs, pauses, or deletes no automation. It restores the baseline visibility state.
- **Why:** A navigation surface should not require users to remember that the entry point is also the exit. Rendered content and reversible dismissal are one release contract.

## 2026-07-14: Extensions has one obvious reversible navigation path

- **Behavior:** The Extensions pane exposes identified Add and Close controls in its header; sidebar, shortcut, slash-command, and pane-close routes share `toggle-extensions`.
- **Native proof:** Packaged macOS smoke AX-presses Extensions, requires its identified title and Add control, presses Close with AXPress, and waits for disappearance.
- **State safety:** Verification installs, updates, starts, stops, trusts, disables, or records nothing. It restores baseline visibility.
- **Why:** Extension management is a recovery and capability surface. Users need an obvious exit, and release evidence must prove real content rather than a Boolean.

## 2026-07-14: Project config hooks share the standard hook trust boundary

- **Discovery:** QuillCode merges bounded hook definitions from project `.quillcode/hooks.json`, `.quillcode/config.toml`, `.codex/hooks.json`, and `.codex/config.toml` with installed plugin hooks. A single canonical decoder and definition builder owns JSON/TOML aliases, normalization, support classification, stable IDs, timeout bounds, and exact-definition hashes so source formats cannot drift.
- **Safety:** Discovery is data-only. Documents must be regular, non-symlink files inside the canonical workspace, each document is capped at 64 KiB, and the aggregate config-hook inventory is capped at 96 definitions. Malformed or unsafe sources fail closed without executing anything. Every supported non-managed command remains skipped until its exact normalized definition is trusted; changing an executable field invalidates that decision.
- **Compatibility:** Synchronous command handlers use the same typed prompt, stop, tool, permission, compaction, session, and subagent boundaries as plugin hooks. Async handlers and prompt/agent handlers remain visible but inert, matching current Codex behavior. Plugin-only root/data compatibility variables are added only when a package root exists.
- **Presentation and scope:** The shared surface says **Hooks** and identifies the actual source instead of calling config hooks plugins.

## 2026-07-14: Global and managed hook layers have explicit trust and execution scope

- **Discovery order:** QuillCode loads system, user, and managed-requirements documents through the same bounded JSON/TOML decoder as project hooks. Lower-precedence definitions remain additive. Managed documents are loaded first for capacity reservation but presented after ordinary layers in effective configuration order, so a large user file cannot starve mandatory policy.
- **Trust:** System and managed-requirements hooks are policy-trusted and immutable. User hooks use the same exact-definition review as project hooks, but decisions are stored against the Quill Cowork app home rather than duplicated per workspace. Legacy persisted definitions decode as workspace-scoped.
- **Policy:** Managed `allow_managed_hooks_only` removes user, project, plugin, and session hooks. Managed `[features].hooks = false` disables every source. Higher-precedence user feature settings may override system defaults but cannot override managed requirements.
- **Execution:** Workspace hooks follow the selected local or SSH Remote project. User and managed hooks were discovered on the current computer and always execute locally, even when the active workspace is remote. The trust scope is carried into before/after run hooks so routing cannot be inferred from mutable display names or paths.
- **Remaining boundary:** Local system and requirements files are implemented. Cloud and MDM delivery can inject additional managed requirement paths through the same typed path set, but those delivery adapters are not yet implemented.

## 2026-07-14: Memories is reachable and reversible through native controls

- **Behavior:** The Memories pane exposes identified Add and Close controls in its header; shortcut, slash-command, native menu, and pane-close routes share `toggle-memories`.
- **Native menu fallback:** Packaged activation prefers an identified control already visible in the workspace. When compact sidebar layout hides Memories inside Tools, the macOS adapter traverses the real Accessibility menu bar and AX-presses the titled native menu item. App-level code remains unaware of this platform detail.
- **Native proof:** Packaged macOS smoke opens Memories, requires its identified title and Add control, AX-presses its identified Close control, and waits for disappearance.
- **State safety:** Verification adds, edits, forgets, reconciles, or redacts no memory and restores baseline visibility.
- **Why:** A compact layout must not make a primary workspace pane untestable or undiscoverable. Native menu activation and visible dismissal form one reversible interaction contract.

## 2026-07-14: Activity dismissal restores working space

- **Behavior:** The Activity pane exposes an identified Close control in its header; sidebar, shortcut, slash-command, native-menu, and pane-close routes share `toggle-activity`.
- **Native proof:** Packaged macOS smoke opens Activity through AXPress, requires its identified title and task summary, AX-presses Close, waits for the pane to disappear, and measures the composer regaining at least 240 points of width.
- **State safety:** Verification does not collapse sections, change plans, resolve instruction diagnostics, approve workers, or mutate task state. It restores baseline pane visibility.
- **Why:** A Boolean visibility transition cannot prove a fixed-width side pane rendered, dismissed, or returned useful workspace area. Content, dismissal, and layout restoration are one release contract.

## 2026-07-14: Review discovery, visibility, and dismissal share one command

- **Behavior:** Review remains progressively disclosed in the compact Tools menu instead of adding another permanent sidebar row. Tools, shortcuts, native menus, HTML, and the pane Close action all route through `toggle-review-panel`.
- **Presentation state:** Review uses `automatic`, `visible`, and `hidden` presentation policies instead of overloading one Boolean. Automatic preserves content-driven presentation, visible allows an explicitly opened empty or failed review to render, and hidden keeps a dismissed diff closed until the user reopens it.
- **Empty and failed reviews:** The scope picker remains available before a successful diff exists. An empty pane explains how to choose a scope; a failed `host.git.diff` surfaces its failure reason without reviving stale diff content.
- **Viewport contract:** Opening Review scrolls its stable anchor into view and suspends transcript-tail following. Closing Review returns to the transcript tail and restores normal append-follow behavior.
- **Native proof:** Packaged macOS smoke first normalizes Review to hidden, AX-presses the real semantic command, requires the identified title and scope control, AX-presses Close, waits for disappearance, and restores the hidden baseline. State-only evidence is rejected.
- **Test isolation:** The packaged window smoke receives an explicit state root, uses a mock runtime, and records its app-state and workspace paths in the evidence report. It never treats an overridden process `HOME` as proof of isolation because macOS can still resolve `homeDirectoryForCurrentUser` to the signed-in user's real home.
- **Why:** A Review command that technically toggles an off-screen pane is not usable. Discovery, in-viewport presentation, explicit dismissal, and deterministic restoration are one interaction contract.

## 2026-07-14: Non-interactive execution is a module, not executable glue

- **Boundary:** `quill-code` is a thin process entry point over the independently testable
  `QuillCodeCLI` module. Argument parsing, stdin, output, persistence, event reporting, runtime
  construction, Git guarding, and schema validation have typed interfaces; tests inject the LLM and
  input/output boundaries without forking a process.
- **Output contract:** Plain runs reserve stdout for the final assistant message and stderr for human
  progress. JSON mode reserves stdout for one JSON object per line and emits a terminal
  `turn.completed` or `turn.failed`, never both, for completed and failed turns. A user interruption
  matches Codex JSONL by emitting neither terminal event and exiting 1. Resume establishes historical
  transcript state as a reporting baseline so old messages are not replayed as new automation events.
- **Safety:** Exec defaults to read-only and requires a Git workspace. Workspace-write must be
  explicit. The Git bypass is explicit and named. `danger-full-access` is parsed for compatibility but
  rejected until QuillCode can enforce it, because silently mapping it to Auto would make the CLI lie
  about its process boundary.
- **Bounds and durability:** Stdin and schema files are byte-capped, schema recursion is bounded,
  relative paths resolve against the supplied invocation directory, final-message writes are atomic,
  ephemeral runs never save tasks, and persistence failures turn the run into a visible failure.
- **Interruption boundary:** The executable owns one process-level SIGINT source; it races that source
  against the structured agent task, cancels cooperatively, waits for tool cleanup and the agent's
  `Stopped by user` progress snapshot, checks that persistence succeeded, then exits 1. It does not run
  schema validation or write a last-message file after interruption. Process-global POSIX constants and
  dispositions remain in the existing C platform adapter so macOS/Linux Swift code stays identical.
- **Verification:** Focused CLI tests cover parser, repository, schema, runtime, event, secret,
  interruption, and failure contracts. `scripts/cli-exec-smoke.sh` verifies the built process, including
  real SIGINT delivery during a running shell command, and is part of the aggregate smoke gate.

## 2026-07-15: Exec MCP startup is a shared, pre-persistence session boundary

- **Shared runtime:** Standalone exec and app-server turns use one `MCPAgentRunnerAdapter` over the
  existing MCP registry and catalog. Tool schemas, stable aliases, exact raw routes, safety metadata,
  and execution semantics therefore cannot drift between the two command surfaces.
- **Ordering:** Exec resolves global/project MCP configuration and initializes servers before model
  invocation, user-message mutation, reporter start events, or task persistence. Required startup
  failure exits 1 without invoking the model or leaving a task that never actually ran.
- **Failure policy:** Optional unavailable servers are omitted without blocking healthy tools.
  `required = true` failures are sorted and aggregated by configured server name. Project definitions
  override same-named global definitions. `--ignore-user-config` deliberately skips all configured MCP
  startup for an isolated run.
- **Cleanup:** The command owns one session object and awaits registry termination after success,
  ordinary failure, runner-construction failure, or cooperative interruption. Preparation failure also
  terminates any server started earlier in the deterministic probe sequence.
- **Verification:** Focused tests cover all ordering, override, routing, failure, and teardown paths.
  The process smoke starts a real stdio MCP child, proves a successful exec, checks that the child PID
  disappears, and proves a broken required server exits before task persistence.

## 2026-07-14: App-server parity starts with one typed, durable stdio core

- **Wire contract:** `quill-code app-server` uses Codex's newline-delimited JSON shape without a
  `jsonrpc` marker, preserves string and integer request IDs, requires `initialize` followed by the
  `initialized` notification, distinguishes malformed JSON from a valid invalid envelope, honors
  notification opt-outs, and caps each inbound message to four maximum-size encoded image inputs
  plus bounded JSON envelope overhead.
- **Lifecycle contract:** The first slice owns thread start/resume/fork/list/read/archive/unarchive/
  delete/name/goals and turn start/steer/interrupt. Turn responses precede streaming notifications;
  user, reasoning, assistant, shell, and dynamic-tool items project through typed Codex-shaped events;
  progress and completion persist through the existing thread store. Forks keep their own thread ID
  while sharing the root session ID, ordinary forks do not masquerade as subagent parents, and turns
  are populated only on the response families where the generated Codex schema promises them.
- **Safety contract:** New app-server threads inherit the configured QuillCode mode. Auto remains Auto;
  Review sends official `item/commandExecution/requestApproval` or
  `item/fileChange/requestApproval` server requests and awaits the client's response. Existing trusted
  permission hooks run first, danger-full-access is rejected, malformed approval responses deny, and
  interruption or client EOF resolves every waiter without executing an unapproved action. String and
  granular approval policies plus all documented reviewer identities round-trip without silently
  weakening or rewriting the client's policy.
- **Attachment contract:** Bounded `localImage` and Codex-shaped `image` inputs are accepted. `image`
  means a base64 `data:` URL, not an HTTP fetch; current Codex core also rejects remote HTTP(S) image
  URLs. Both paths validate MIME declarations against magic bytes, preserve image detail, and copy
  bytes into QuillCode-managed private storage before transcript persistence or TrustedRouter use.
  Multi-item parsing is transactional, interrupted queued steering removes unconsumed images, errors
  never echo source data or URL query secrets, and stored threads never contain inline base64. Skill
  references and mentions still fail explicitly rather than being ignored.
- **Platform boundary:** Incremental stdin uses the shared C adapter's EINTR-safe descriptor read plus
  a bounded readability wait. This avoids Foundation pipe buffering, lets stream cancellation end an
  idle reader whose peer keeps stdin open, and keeps macOS/Linux command code free of platform
  conditionals.
- **Verification:** Focused XCTest covers handshake, wire errors, persistence, steering, interruption,
  command projection, approval acceptance, EOF denial, granular-policy fidelity, strict list filters,
  local-image isolation, session-aware thread lifecycle, and goals. `scripts/app-server-smoke.sh` keeps
  stdin open while driving the built executable, proving the real process responds incrementally
  before EOF.

## 2026-07-14: App-server discovery distinguishes provider facts from local observations

- **Model contract:** `model/list` projects the normalized TrustedRouter catalog into the generated
  Codex 0.142.5 shape, caches one live/public fetch per app-server session, preserves QuillCode's
  selected default, and uses opaque deterministic offset cursors. Unsupported reasoning and service
  tiers remain empty instead of being invented.
- **Account contract:** `account/read` reports only whether a usable explicit, environment, or stored
  TrustedRouter credential exists. It returns the schema-compatible `apiKey` account kind but never
  serializes the credential itself; externally managed refresh requests are type-checked and ignored.
- **Usage contract:** `account/usage/read` aggregates only persisted local model-usage receipts into
  UTC daily buckets, streaks, and prompt/completion/context token totals. Legacy total-only receipts
  still contribute their total as context so old transcripts stay visible in accounting.
  `account/rateLimits/read` exposes configured QuillCode day/week/month spend controls under
  `quillcode-local-*` IDs and names every row as local. Neither method claims to represent
  TrustedRouter account history, balances, or provider quotas.
- **Config contract (superseded 2026-07-15):** This slice initially projected only effective model,
  reviewer, sandbox, and web-search state. The later structured-document decision above adds true
  per-key origins, raw user layers, and general value/batch mutation.
- **Code boundary:** Model, account/usage, config, and parameter support live in focused app-server
  files. Credential precedence is one shared CLI resolver used by both ordinary CLI execution and
  app-server discovery, so the two surfaces cannot drift.
- **Verification:** Seven focused JSON-RPC tests cover pagination and schema fields, capability truth,
  credential precedence and non-disclosure, UTC usage aggregation, local spend controls, config
  layers, and invalid inputs. The real app-server process smoke reads models, account state, and
  effective config before starting a turn. The CLI module and every new production/test file grade
  A+ under the repository quality gate.

## 2026-07-14: Model code review is a dedicated read-only workflow

- **Command boundary:** `/review` and the **Code review** command open a scope chooser for uncommitted work, a base-branch comparison, one commit, or custom review criteria. `/diff` remains the ordinary Git diff/review-pane route; the two commands no longer pretend to be aliases.
- **Execution boundary:** The workflow preflights the selected local or SSH Remote project with `host.git.status` before creating transcript state. A dedicated runner receives only bounded read/search/Git-inspection tools plus `host.review.submit`; it cannot write files, run arbitrary shell commands, mutate Git, invoke Computer Use, or inherit ordinary project tool breadth.
- **Completion boundary:** The reviewer must call `host.review.submit` exactly once with strict JSON. QuillCode validates paths, line ranges, priorities, unknown fields, finding count, duplicate findings, and a nonempty summary before merging only the typed report into the parent task. Internal investigation turns and tool feedback remain private.
- **Presentation boundary:** Findings render as P0-P3 comments in the normal Review surface and as a concise Markdown report in the transcript. A finding-only file exposes Open and review-note actions but never Stage, Restore, or whole-diff mutation controls; its badge says `finding`, never `0 hunks`.
- **Lifecycle boundary:** Current-task delivery refuses to overlap an active run. Detached delivery creates exactly one review task, including when no source task exists. Stop All cancels the dedicated task and leaves a visible stopped result. Model and current-versus-detached defaults live in Settings and persist through the normal config store.
- **Interaction proof:** Playwright drives the command palette and `/review`, validates all scope fields, types character by character without losing focus, requires the optimistic user turn and reviewer progress before completion, checks typed findings and mutation absence, and proves backdrop, Escape, and Stop behavior. Native tests cover local, non-Git, detached, cancellation, and SSH Remote execution; packaged macOS smoke remains the release-level SwiftUI gate.

## 2026-07-15: App-server MCP tools are native per-tool agent capabilities

- **Schema boundary:** `QuillCodeTools.MCPAgentToolCatalog` consumes the raw bounded MCP tool inventory and emits one normal `ToolDefinition` per enabled tool. It preserves the exact `inputSchema`, description, and raw server/tool route; annotations map `readOnlyHint` to read risk and `destructiveHint` to destructive risk, with unannotated calls treated as append risk.
- **Naming boundary:** Model-visible names use deterministic `mcp__server__tool` aliases restricted to ASCII letters, digits, and underscores. Sanitization collisions and names over 64 bytes receive a stable SHA-256-derived suffix. The transport never parses those aliases to recover authority: it executes only the catalog's exact route.
- **Runtime boundary:** App-server builds the catalog for each active turn from the thread's global/project configuration and composes it with the runner's existing definitions and execution override. Calls reuse `AppServerMCPRegistry` sessions and therefore share the direct status/tool/resource transport rather than creating a second MCP client. Existing safety review, permission hooks, tool hooks, transcript feedback, and cancellation remain in the ordinary agent path.
- **Lifecycle boundary:** A server configured with `required = true` must complete the lightweight initialize/tools probe before thread start, resume, or fork is persisted. Optional failures are omitted without suppressing healthy servers. `config/mcpServer/reload` tears down cached sessions, and the next turn reconstructs its inventory from current config. Progress projects exact raw identities as Codex-shaped `mcpToolCall` items; direct `mcpServer/tool/call` remains the lossless structured-result API.
- **Verification:** Focused catalog tests pin schemas, risks, malformed inventory, collision stability, and the 64-byte bound. App-server integration tests prove required failure leaves no thread, a scripted model discovers and executes a tool in one turn, exact arguments reach the fake MCP session, native lifecycle items complete, and replacement config takes effect after reload.

## 2026-07-15: Danger full access is one explicit host-tool policy

- **Supersedes:** The earlier exec and app-server decisions correctly rejected danger full access
  while no honest implementation existed. This decision replaces that temporary rejection.
- **Policy boundary:** `HostToolAccessScope` is the single source of truth for built-in host file
  and shell-working-directory reach. Desktop, read-only CLI, and workspace-write CLI keep
  `workspaceOnly`; only an explicit `danger-full-access` invocation selects `unrestricted`.
- **Composition boundary:** Exec and app-server apply invocation-owned policy after constructing an
  agent runner. Injected factories therefore cannot accidentally weaken or omit the requested scope,
  and every built-in router path, including approved-tool continuation, receives the same value.
- **Honest model contract:** Unrestricted runs adapt only the built-in path-bearing tool descriptions
  and schemas. Relative paths still anchor at the selected project, while absolute paths and `..`
  traversal are allowed. MCP providers retain ownership of their own schemas; patch and Git tools
  remain project-scoped.
- **Safety boundary:** Removing the workspace path boundary does not bypass review policy, trusted
  permission hooks, read-before-write guards, cancellation, output caps, or secret protections.
- **Verification:** Focused unit and integration tests prove workspace defaults remain bounded,
  unrestricted file read/write/list/search and external shell working directories work, exec and
  app-server persist external tool results, the app-server reports `:danger-full-access`, and the real
  CLI process accepts the flag.

## 2026-07-15: Personality is a per-chat prompt layer with a future-chat default

- **Product boundary:** QuillCode exposes the same Friendly, Pragmatic, and None choices as Codex.
  Pragmatic is the migration-safe default. Settings updates only the default for chats created later;
  `/personality friendly|pragmatic|none` updates only the selected chat and records a visible local
  transcript confirmation.
- **Prompt boundary:** Personality guidance is a separate system message between QuillCode's stable
  base contract and mode/project context. None omits that message entirely. This keeps the base tool
  schema cache-stable and prevents personality text from being duplicated in user content.
- **Capability boundary:** Live model catalogs may advertise `supports_personality`. An explicit
  `false` hides composer suggestions and rejects a typed change; missing metadata remains supported
  because QuillCode implements personalities in the prompt layer rather than depending on a
  provider-native request field.
- **Persistence boundary:** Config and thread decoders default missing legacy fields to Pragmatic.
  New project/worktree chats inherit the current default; fork, compact, duplicate, side-context,
  and worktree-open paths preserve the source chat's explicit value.
- **Verification:** Focused Core, Agent, Persistence, App, catalog, and Playwright tests cover parsing,
  old-state migration, round trips, prompt isolation, live capability decoding, Settings scope,
  slash confirmation, and unsupported-model behavior.

## 2026-07-15: Native and CLI code review share one typed engine

- **One domain:** `QuillCodeReview` owns review targets, validation, prompt construction, finding and
  report normalization, the dedicated runner, and `host.review.submit`. Native and CLI adapters supply
  transport and presentation only; they cannot evolve incompatible reviewer protocols.
- **CLI contract:** `quill-code review` requires exactly one uncommitted, base, commit, or custom target.
  A custom argument or `-` stdin value supplies criteria for the current uncommitted change set. Commit
  titles are bounded UTF-8 data and are valid only for commit reviews. The run is always ephemeral,
  final Markdown alone goes to stdout, and human progress alone goes to stderr.
- **Capability boundary:** The runner starts from a normal agent only long enough to reuse provider and
  transport plumbing, then replaces its catalog with bounded file read/list/search, Git status/diff/
  branch inspection, and the typed report sink. Shell, writes, patches, Git mutation, hooks, skills,
  web, LSP, Computer Use, subagents, attachments, and immediate-action planning are absent rather than
  relying on a prompt to avoid them.
- **Completion boundary:** Success requires exactly one schema-valid report submission. Missing,
  malformed, duplicate, or out-of-bounds findings fail closed. The same normalization gives native
  findings and CLI Markdown deterministic ordering and deduplication.
- **Process invariant:** A subprocess with piped output must drain stdout and stderr concurrently while
  waiting for exit. Git review diffs can exceed pipe capacity; waiting first can deadlock a healthy Git
  process. Shell and Git now share one completion waiter/output collector, with a real >128 KiB Git diff
  regression test.
- **Verification:** Parser and resolver tests cover every target and conflict; shared-domain and native
  integration tests prove capability filtering and report delivery; real temporary-repository CLI tests
  prove scoped diffs, cancellation, failure, and no persistence; and `scripts/cli-review-smoke.sh` proves
  the built public command inside the aggregate smoke gate.

## 2026-07-15: QuillCode exposes a Codex-compatible MCP tool bridge

- **Wire boundary:** `quill-code mcp-server` owns strict newline-delimited JSON-RPC 2.0 and negotiates
  the observed `2025-06-18` MCP protocol. The catalog intentionally contains only `codex` and
  `codex-reply`; unknown fields fail instead of being silently ignored.
- **Runtime boundary:** A start call resolves its cwd, model, sandbox, approval policy, allowlisted
  config overrides, and optional instructions into one durable app-server thread record. The
  allowlist accepts bounded Codex-style aliases for invocation-local review, spend, browser,
  Computer Use, notification, worktree, shortcut, skill, auth-mode, and API-base preferences while
  still rejecting unknown keys, account state, and direct developer-override toggles. Reply loads
  that exact record, so model and policy do not drift between turns. Custom compaction guidance is
  bounded and reaches the shared model-backed compactor without changing the main model selection.
- **Safety boundary:** Review-mode tool calls use `elicitation/create`; malformed, contradictory,
  cancelled, orphaned, or disconnected responses deny. Existing QuillCode hard safety and trusted
  permission hooks run before the client approval hook. `on-failure` starts shell commands inside the
  selected OS sandbox and only asks after a typed sandbox denial; approval permits one exact retry
  without that process sandbox. Ordinary nonzero exits, lookup failures, timeout, cancellation, and
  unavailable sandbox runtimes never become escalation requests.
- **Lifecycle boundary:** Request IDs and active thread turns are unique while running, client
  cancellation cooperatively stops work, progress persists incrementally, and EOF denies approval
  waiters then awaits active turns and MCP dependency shutdown.
- **Compatibility boundary:** Public tool names, input/output shapes, handshake, events, and approval
  transport follow observed Codex behavior. QuillCode does not claim the full native event union,
  arbitrary Codex config keys, or replacement of its stable structured tool contract by
  caller-provided base instructions.
- **Verification:** Focused wire/catalog/config/session/approval/compaction tests exercise the typed
  contract. `scripts/mcp-server-smoke.sh` drives the built process through initialize, discovery,
  `whoami`, durable reply, event and persistence inspection, leak rejection, and clean EOF; aggregate
  smoke records the step in its deterministic manifest.

## 2026-07-20: MCP on-failure is a typed OS-sandbox retry, not a generic failure retry

- **Shared enforcement boundary:** Agent-authored MCP shell calls and standalone app-server commands
  use one `ShellProcessSandbox` launcher. macOS uses Seatbelt, Linux uses bubblewrap, and a requested
  sandbox fails closed when neither runtime is available. Platform launch details do not leak into
  the agent or MCP protocol layers.
- **Escalation boundary:** Only a nonzero result from an active sandbox carrying a recognized denial
  signal is tagged `sandboxDenied`. Exit 126/127, ordinary test/build failures, malformed arguments,
  timeouts, cancellations, and sandbox setup failures remain terminal results and do not prompt.
- **Retry boundary:** `on-failure` with the user reviewer sends one `exec-approval` after the failed
  sandboxed attempt. Approval reruns the exact validated call once without the process sandbox; denial,
  malformed responses, disconnect, and cancellation preserve the failure and cannot retry. The shell
  CWD remains workspace-bounded on both attempts.
- **Concurrency boundary:** Both attempts use cancellable asynchronous shell execution. A long command
  does not block the MCP session actor from receiving cancellation or approval traffic.
- **Evidence:** Classifier tests cover active-sandbox, ordinary-failure, and command-lookup boundaries.
  A real Seatbelt integration writes inside the workspace while blocking an outside write. MCP session
  tests prove approve-once retry, deny-without-write, no prompt for exit 7, and cancellation before a
  trailing mutation.

## 2026-07-15: TrustedRouter balance is live account metadata, not a derived quota

- **Source of truth:** QuillCode fetches the authenticated current balance from TrustedRouter's
  `GET /v1/credits` endpoint through `trusted-router-swift`. It does not infer provider credit from
  local token receipts, model prices, rate-limit headers, or configured spend caps.
- **Presentation boundary:** The provider balance has its own top-bar chip and Settings card. Local
  Today/Week/Month receipts and user-configured caps remain in the token/spend surface; provider
  rate-limit and reset metadata remains in quota rows. Labels never merge these three concepts.
- **Freshness:** Desktop startup, a bounded five-minute cadence, credential changes, and the explicit
  Settings action can refresh the balance. A failed refresh retains the last successful in-memory
  snapshot with a stale warning and backs off before automatic retry; an initial failure shows no
  invented value.
- **Credential and persistence boundary:** The request uses the same resolved TrustedRouter
  credential as model traffic. Provider bodies and credentials are excluded from surfaced errors.
  Balance snapshots are intentionally not persisted, preventing one account's value from appearing
  after a credential change or on the next launch before authentication is revalidated.
- **Deferred facts:** Account transaction history and provider-owned day/week/month usage limits or
  reset windows remain absent until TrustedRouter exposes authoritative APIs for them.
- **Evidence:** Focused Core, Agent, App, and Desktop tests cover finite/currency normalization,
  `/v1/credits` authorization and redaction, stale retention, retry policy, deterministic formatting,
  command routing, and refresh coordination. Playwright covers the distinct top-bar balance and the
  eager Settings refresh transition without introducing balance state into unauthenticated fixtures.

## 2026-07-15: SSH projects are discovered and verified before registration

- **Single setup surface:** Sidebar, command-palette, and Settings entry points open the same native
  connection dialog. `/ssh user@host:/path` remains available for keyboard-first compatibility, but
  the visible product flow does not prefill a command and make the user repair it.
- **Discovery boundary:** QuillCode reads only regular OpenSSH config files through bounded recursive
  `Include` expansion with cycle, depth, file-count, byte-count, pattern-count, alias-count, and
  directory-entry limits. Only concrete `Host` aliases become rows. Effective display metadata comes
  from `ssh -G -F`, while persisted project metadata keeps the alias so OpenSSH still applies
  `ProxyJump`, `IdentityFile`, `Match`, and related settings at execution time.
- **Registration boundary:** Destination and folder are separate validated fields. URL credentials,
  embedded paths, query/fragment data, option-like hosts, relative folders, and invalid ports are
  rejected. A cancellable noninteractive SSH probe must enter the requested folder and return a
  marker plus an absolute `pwd` before the project can be persisted or selected.
- **Async and UX boundary:** Discovery and probe results are generation-bound to one presentation.
  Closing the sheet cancels active work and ignores late results; failures remain in place with a
  retryable error. Search, host rows, segmented mode selection, fields, close, cancel, refresh, and
  submit controls use the shared native hit-target contracts.
- **Evidence:** Core parsing, config scanner, effective-resolution, probe, draft, coordinator, project
  engine, desktop integration, rendered AppKit-hosted SwiftUI, source hit-target audit, and Playwright
  tests cover success, invalid input, bounds, cycles, missing files, failure/retry, cancellation, and
  post-registration terminal/Git/review/tool routing.

## 2026-07-15: MCP tool progress is a replayable per-call lifecycle

- **Transport boundary:** Every streaming `tools/call` carries an exact string or integer
  `_meta.progressToken`. Stdio, Streamable HTTP SSE, and legacy HTTP+SSE accept only matching,
  finite, nonnegative, strictly increasing `notifications/progress` updates; messages and update
  counts are bounded before entering agent state.
- **Agent boundary:** Streaming execution is an optional tool override that emits typed progress or
  exactly one terminal result. No result, duplicate results, transport errors, and cancellation fail
  closed through the ordinary tool lifecycle. Consecutive progress snapshots coalesce in the durable
  transcript while each accepted snapshot still publishes to live UI observers.
- **Presentation boundary:** One exact tool-call ID updates one active card. SwiftUI, static HTML,
  thinking/activity state, and CLI JSONL derive from the same event; completion, failure, and stop
  clear progress immediately. Determinate values use stable tabular percentages, while unknown totals
  remain honestly indeterminate.
- **Compatibility:** Existing synchronous MCP sessions keep their default adapter and do not invent
  progress. App-server turns project matching nonempty messages through Codex's exact
  `item/mcpToolCall/progress` schema; numeric-only MCP updates remain internal because that schema has
  no numeric fields. App-server startup progress and server-initiated elicitation remain separate
  wire-contract milestones rather than private notification names.
- **Evidence:** Focused Core, Agent, App, stdio, and HTTP tests cover validation, ordering, mapping,
  replay, cancellation, and terminal publication. Playwright drives the composer through a live
  progress card and its completed state, plus an accessible indeterminate fixture.

## 2026-07-16: App-server MCP startup has a response-aware lifecycle

- **Protocol boundary:** QuillCode emits Codex's exact thread-scoped
  `mcpServer/startupStatus/updated` method with typed `starting`, `ready`, `failed`, or `cancelled`
  state, nullable bounded error, and the current additive nullable `failureReason`. It does not
  invent app-global startup notifications or conflate server startup with per-tool progress.
- **Ordering boundary:** Required servers emit startup transitions and reach readiness before a new,
  resumed, or forked thread can persist or respond. Optional servers start only after the successful
  lifecycle response, preserving responsive thread creation while retaining observable readiness.
- **Cancellation boundary:** Reload cancels in-flight optional startup before clearing the shared
  registry. EOF cancels startup and suppresses output to the closed channel. A cancelled startup can
  never publish a later ready state, and every launched process still terminates through the registry.
- **Compatibility boundary:** Notification opt-outs suppress only wire output, never initialization.
  Already-ready scoped servers do not fabricate duplicate transitions. The additive failure-reason
  field remains null until the transport preserves a typed reauthentication failure instead of
  inferring one from user-facing text.
- **Evidence:** Focused integration tests prove required failure before persistence, exact payloads
  and ordering, optional startup, opt-out behavior, reload cancellation, process termination, and no
  stale readiness. A source parity gate binds the focused implementation, tests, and matrix claim.

## 2026-07-16: MCP elicitation is a bidirectional client capability

- **Wire boundary:** Stdio, Streamable HTTP, and legacy HTTP+SSE normalize standard form, URL, and
  OpenAI rich-form server requests into one bounded typed contract. Standard form schemas are
  validated against the renderable MCP subset before reaching the app; rich forms remain bounded
  opaque JSON owned by the negotiated extension. Transport-only `_meta.progressToken` never reaches
  the user-facing request.
- **Capability boundary:** App-server always advertises standard form elicitation to MCP servers.
  It advertises `extensions["openai/form"]` only when the connected app declared
  `capabilities.mcpServerOpenaiFormElicitation`. Unsupported or malformed requests receive `cancel`
  instead of being surfaced as a form the client cannot render.
- **Lifecycle boundary:** App-server emits the exact `mcpServer/elicitation/request` server request
  with thread, nullable turn, server, mode, message, schema or URL fields, and bounded metadata.
  Client `accept`, `decline`, or `cancel` content and metadata return losslessly to the MCP server.
  Direct tool calls carry a null turn; ordinary agent calls carry their active turn. Interrupt and
  disconnect cancel only the matching pending requests and emit `serverRequest/resolved` before a
  turn can complete.
- **Input-loop boundary:** A direct MCP call may wait for a client response, so the JSONL stdio reader
  dispatches that request concurrently while continuing to process response messages. Other methods
  retain input ordering. EOF cancels and joins the outstanding request before dependency teardown.
- **Evidence:** Schema, bridge, stdio, both HTTP transport, fake-session app-server, interruption,
  capability-gating, and malformed-response tests cover the typed boundaries. The real app-server
  smoke drives a newline-delimited child MCP request through the JSONL client response and verifies
  capability advertisement, metadata sanitization, resolved ordering, and the final accepted payload.

## 2026-07-16: MCP stdio uses canonical newline-delimited JSON

- **Outbound boundary:** Every stdio request, response, and notification is one bounded JSON object
  followed by a newline, matching MCP 2025-06-18 and Codex. HTTP sessions continue to use the same
  JSON body encoder without adding stdio framing.
- **Compatibility boundary:** The incremental decoder accepts both canonical JSONL and the legacy
  `Content-Length` frames emitted by early QuillCode builds. Compatibility is input-only; new clients
  cannot silently perpetuate the obsolete framing.
- **Identity and progress:** Initialization reports `quillcode-mcp-client`, the QuillCode product
  title, and its client version. Tool discovery carries a unique progress token, as do individual
  tool calls, so modern servers can associate progress without cross-request collisions.
- **Evidence:** Focused codec/session tests cover fragmented JSONL, blank separators, legacy input,
  client metadata, and discovery metadata. The real app-server smoke launches a strict JSONL-only MCP
  child and completes startup, tool calls, progress metadata, elicitation, and resource reads.

## 2026-07-16: Direct user shell is a host escape hatch with hidden durable context

- **Execution boundary:** `thread/shellCommand` bypasses model tool selection, approval, and thread
  sandboxing because the connected user explicitly supplied the command. It still validates nonempty
  input, uses only an executable absolute configured shell (falling back to `/bin/sh`), runs from the
  durable thread cwd, caps retained output, and enforces the observed one-hour timeout.
- **Lifecycle boundary:** The RPC response is emitted before work begins. Standalone requests own one
  active turn, and overlapping standalone commands share it. Commands submitted during an ordinary
  turn, review, or compaction reuse that turn. Every parent waits until attached commands finish;
  interruption and EOF cancel and drain them before turn completion.
- **Persistence boundary:** Shell output is durable model context, but direct command items are not
  ordinary transcript history. Standalone turn metadata is stored separately and projected as an empty
  turn for read/list/fork. Projection excludes its hidden tool message from adjacent conversation turns,
  and rollback durably removes both metadata and hidden output in the same repository mutation.
- **Reuse boundary:** Blocking and streaming shell execution accept the same selected-shell request.
  Streaming accumulation retains only a bounded byte/line tail, so direct shell cannot create an
  unbounded in-memory aggregate while still emitting live deltas.
- **Evidence:** Focused tests cover selected shells, output caps, response ordering, concurrent commands,
  model feedback, projection isolation, rollback, interruption, and slow-command overlap with ordinary,
  review, and compaction turns. The built app-server JSONL smoke verifies the public process contract.

## 2026-07-16: Standalone app-server commands are connection-owned sandboxed processes

- **Protocol boundary:** `command/exec` owns no thread or turn. Buffered commands may use an internal
  handle; PTY or streaming commands require a client process ID. The final response waits for process
  exit and output drain, follows every output delta, and never duplicates streamed bytes.
- **Lifecycle boundary:** Follow-up write, resize, and terminate requests address only the originating
  connection's active non-empty ID. PTY or streaming start requests also reject empty client process
  IDs instead of creating ambiguous registry keys. An ID is reusable after exit. EOF terminates every
  process, drains its event task, and suppresses deltas and deferred responses after the channel closes.
- **Sandbox boundary:** Built-in profiles and explicit legacy policies normalize existing writable
  roots before launch. macOS uses a closed-by-default Seatbelt profile derived from OpenAI Codex 0.142.5
  under Apache 2.0; Linux uses bubblewrap and fails closed when restrictive execution cannot be
  enforced. `/var` and `/tmp` rules include macOS `/private` aliases so allowed temporary/workspace
  writes work without broadening access. Danger full access deliberately launches directly.
- **Network boundary:** Managed `allow_upstream_proxy = false` strips proxy environment variables
  (`HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY`, and `NO_PROXY`, case-insensitively) after request overrides
  are applied, so both inherited and client-supplied upstream proxies are excluded from `command/exec`
  and lower-level process launches. Selected remote exec-server process starts also forward the
  structured managed-network profile with `enforceManagedNetwork`, leaving enforcement to the target
  exec server instead of silently dropping policy.
- **Compatibility boundary:** Arbitrary configured permission profiles, full managed proxy profiles
  with enforced local forwarding/domain routing, Windows restricted-token behavior, and a remotely
  disabled local environment are not fabricated; they remain explicit work in the broader app-server
  parity row.
- **Evidence:** Focused tests cover buffered and streaming execution, pipe and PTY control, output caps,
  timeout, validation including empty process IDs, ID lifecycle, disconnect teardown, managed upstream
  proxy stripping, and real Seatbelt denial/allow boundaries. The executable JSONL smoke proves streamed
  stdin/output ordering through the packaged protocol path.

## 2026-07-16: Global memory reset preserves project-owned memory

- **Ownership boundary:** `memory/reset` clears only the app-managed global memory root at
  `~/.quillcode/memories`. Project `.quillcode/memories` files remain workspace-owned content and are
  never inferred reset targets.
- **Filesystem boundary:** Reset preserves and re-secures the global root at owner-only permissions,
  removes its direct children recursively, removes child symlinks without following them, and rejects
  a root that is itself a file or symlink.
- **Lifecycle boundary:** The operation is idempotent and affects future memory loading. It cannot
  remove context already copied into an in-flight model request.
- **Evidence:** Persistence tests cover nested, hidden, linked, missing, repeated, and unsafe roots;
  app-server tests cover omitted parameters and project isolation; the executable JSONL smoke verifies
  the public request against the built process.

## 2026-07-16: Hook discovery has one shared data-only catalog boundary

- **Ownership boundary:** Hook decoding, layered project/global discovery, matcher validation, and
  trust resolution live in `QuillCodeHooks`. Desktop and CLI clients consume that module instead of
  maintaining app-specific parsers or importing UI ownership into protocol code.
- **Dependency boundary:** The catalog depends on Core models, Persistence path/trust models, the
  shared Tools SHA-256 primitive, and the TOML decoder. It does not depend on App and cannot execute
  hook commands during discovery.
- **Filesystem boundary:** Missing documents are quiet. Symlinked, non-regular, oversized, escaped,
  unreadable, or malformed documents fail closed with bounded diagnostics, while independent valid
  layers continue to load in deterministic order.
- **API boundary:** Plugin packages receive a narrow data-to-definition facade; internal decoder and
  builder models remain module-private so callers cannot couple to parser internals.
- **Evidence:** Dedicated catalog tests cover missing, malformed, symlinked, oversized, and regex
  inputs. Existing project, global, plugin-integration, trust, and execution suites remain green, and
  the parity gate enforces the module boundary and absence of discovery-time process execution.

## 2026-07-16: Unix app-server transport shares protocol behavior without sharing sessions

- **Transport boundary:** `stdio://`, `unix://`, and `unix:///absolute/path` feed one
  transport-neutral session driver. Unix clients now complete the same standard HTTP WebSocket
  upgrade and text-frame protocol as TCP clients; only stdio remains newline-delimited JSON.
- **Isolation boundary:** Every accepted Unix client creates an independent `AppServerSession`, so
  initialization, loaded threads, process handles, subscriptions, approval requests, and disconnect
  cleanup cannot leak between clients. Concurrent direct MCP calls remain connection-owned.
- **Filesystem boundary:** The default socket lives at
  `$QUILLCODE_HOME/app-server-control/app-server-control.sock` under a `0700` directory and is itself
  `0600`. Existing files, symlinks, other-user sockets, and active listeners are preserved. A stale
  same-user socket is removed only after a failed connect probe and a second device/inode identity
  check; close removes only the exact socket created by that listener.
- **Platform boundary:** Swift owns async cancellation, full-duplex connection lifetime, and protocol
  sessions. The C adapter owns only portable AF_UNIX, poll, descriptor, ownership, and inode operations,
  keeping app targets free of Linux conditionals.
- **Evidence:** Focused platform and CLI tests cover lifecycle, permissions, path validation, stale
  recovery, active-listener protection, and control-directory safety. The built-process smoke keeps two
  clients live, proves connection-local initialization, force-kills the server, and recovers on the
  stale path.

## 2026-07-16: App-server hook listing projects state without gaining execution authority

- **Protocol boundary:** `hooks/list` accepts only bounded absolute CWDs, defaults an empty request to
  the session CWD, and returns one independent result per input. Missing directories and malformed
  project documents become per-CWD errors instead of failing unrelated entries.
- **Repository boundary:** A normal checkout reads its own project hook documents. A linked worktree
  resolves `.git` and `commondir` through bounded, non-symlinked marker files and reads project config
  from the primary checkout, matching Codex without launching Git or repository-controlled code.
- **State boundary:** `hooks.state` is authoritative for enabled and trusted-hash projection. The
  existing exact-definition trust store remains a compatibility fallback until all desktop writes use
  the shared state table. Managed hooks remain enabled and trusted regardless of mutable user state.
- **Plugin boundary:** Codex and Claude plugin manifests, path/path-array references, inline hook
  objects, and the default `hooks/hooks.json` path use one bounded parser shared with desktop package
  loading. Escaped, symlinked, oversized, malformed, and unsupported definitions are isolated and
  never executed during discovery.
- **Evidence:** Catalog, plugin, worktree, and actor tests cover exact wire fields, project feature
  overrides, batch-written enabled/trust transitions, malformed independent layers, and a command
  sentinel. The built JSONL smoke repeats the sentinel assertion, and a parity gate binds runtime,
  tests, smoke, research, and matrix status.

## 2026-07-16: TCP and Unix app-server clients share one bounded WebSocket protocol

- **Wire boundary:** Every non-stdio client uses RFC 6455 text frames with client masking,
  fragmentation, ping/pong/close control handling, UTF-8 validation, and a shared message cap. Binary
  messages are consumed and ignored, matching Codex. Unix sockets do not retain a private JSONL
  dialect.
- **Backpressure boundary:** Ingress and egress queues are bounded. A dropped request receives exact
  JSON-RPC error `-32001` (`Server overloaded; retry later.`); a client that cannot consume bounded
  outbound work is disconnected. Concurrent request and accepted-connection pools have explicit caps.
- **HTTP boundary:** TCP exposes `GET /readyz` and `GET /healthz`. Any request carrying `Origin` is
  rejected before routing. Loopback may run without credentials; non-loopback refuses to start without
  configured authentication.
- **Authentication boundary:** Capability tokens are compared through constant-time SHA-256 digests.
  Signed bearer tokens require HS256, a secret of at least 32 bytes, `exp`, optional `nbf`, and optional
  exact issuer/audience checks with bounded clock skew. Authorization completes before the WebSocket
  upgrade and before app-server initialization.
- **Platform boundary:** Portable TCP/Unix descriptor operations remain in `CQuillPlatform`; HTTP,
  WebSocket, authentication, and session policy remain testable Swift with no app-level platform
  conditionals.
- **Evidence:** Focused parser, socket, framing, fragmentation, malformed-frame, capability-token, and
  signed-token tests run beside executable TCP health/auth and multi-client Unix crash/recovery smokes.

## 2026-07-16: Git diff-to-remote compares one bounded local snapshot

- **Protocol boundary:** `gitDiffToRemote` resolves the repository's current local upstream tip and
  returns that SHA with a direct working-tree diff. It does not fetch, infer a merge base, or mutate
  refs, the index, or files.
- **State boundary:** The diff intentionally combines committed-ahead, staged, unstaged, and untracked
  changes, excludes ignored files, and appends Git-ordered untracked binary patches after the tracked
  patch. A clean repository returns an empty diff.
- **Execution boundary:** Git runs with external diff and text conversion disabled. Patch output is
  written to private temporary files, then checked against aggregate byte limits before and after
  reading; untracked inventory bytes and file count are independently capped.
- **Failure boundary:** Missing, non-directory, non-Git, no-upstream, unsafe-path, timeout, and bound
  failures collapse to Codex's generic `-32600` request error without leaking Git stderr.
- **Evidence:** Real-Git actor tests cover clean, dirty, ahead, diverged, ignored, invalid, and bounded
  cases. The built JSONL smoke verifies tracked and untracked output against a real bare upstream, and
  a parity gate binds implementation, tests, smoke, research, and matrix status.

## 2026-07-16: Item cursors are anchored before optional turn filtering

- **Protocol boundary:** `thread/items/list` returns complete app-server item projections with their
  containing turn IDs. It shares the existing durable/active history projection instead of inventing
  a second transcript reconstruction path.
- **Cursor boundary:** Opaque cursors identify a stable turn/item pair in the complete ordered stream.
  Pagination locates that anchor before applying an optional turn filter, which keeps one cursor valid
  across filtered and unfiltered requests as required by Codex.
- **Integrity boundary:** Every projected turn and item must have a non-empty stable ID. Corrupt or
  incomplete internal projections fail with an internal error instead of emitting an unpageable item.
- **Compatibility boundary:** Current `thread/items/list` is implemented. The obsolete
  `thread/turns/items/list` spelling remains an explicit `-32601` response rather than silently
  changing meaning for old clients.
- **Evidence:** Actor tests cover full payloads, active history, cross-filter cursors, both directions,
  bounds, validation, and empty history. The built-process smoke pages and filters real persisted
  items, while a parity gate binds runtime, tests, smoke, research, and matrix status.

## 2026-07-16: Marketplace acquisition is data-only and transactionally registered

- **Protocol boundary:** `marketplace/add`, `marketplace/remove`, and `marketplace/upgrade` mirror the
  Codex 0.142.5 local marketplace contract. Sources may be external local directories, GitHub
  `owner/repo` shorthand, HTTP(S)/SSH Git URLs, or local Git repositories with optional refs and
  sparse paths. Credentials are never accepted in HTTP(S) source URLs.
- **Execution boundary:** Git uses argv, disables interactive credential prompts and LFS smudging,
  and never executes marketplace lifecycle code. Cloned trees have aggregate entry, file, and byte
  limits, reject symbolic and special entries, and must expose exactly one valid standard catalog.
- **Transaction boundary:** Managed clones activate through sibling staging and backup directories.
  Config persistence preserves unrelated TOML atomically; a failed config write restores the prior
  clone. Removal stages the clone before config mutation, and upgrade isolates failures per selected
  marketplace. External local source directories are registered but never copied or deleted.
- **Integrity boundary:** Repeated identical add is idempotent only after the installed catalog is
  revalidated. A replaced, missing, or damaged managed checkout fails closed. Successful mutation
  clears skill discovery and emits `skills/changed`.
- **Evidence:** Registry, materializer, and app-server actor tests cover preservation, bounds,
  idempotence, corruption, Git upgrade/no-op upgrade, validation, and removal. The built JSONL smoke
  repeats add/upgrade/remove against a real temporary Git repository, and a parity gate binds the
  runtime, tests, smoke, research, and matrix claim.

## 2026-07-16: SSH Remote agent tools reuse a remote app server without replaying ambiguity

- **Transport boundary:** Each remote project root owns at most one pooled SSH process running
  `quill-code app-server --stdio` through the remote user's login shell. The client performs the real
  initialize/initialized JSONL handshake and serializes bounded `command/exec` requests over that
  process. Ordinary terminal and explicit UI actions remain one-shot SSH operations.
- **Safety boundary:** QuillCode's normal local tool schema, mode, and approval review still decide
  whether a command may dispatch. The already-approved remote command requests the unrestricted
  app-server profile so it can perform the action the user approved; remote managed requirements may
  still reject that profile.
- **Retry boundary:** Failure to initialize is known to precede execution and may fall back to the
  established one-shot SSH executor. Any failure after the command request is written is reported as
  an unknown execution state and is never retried automatically. The user is told to inspect remote
  state before retrying, preventing duplicate file, Git, or shell mutations.
- **Architecture boundary:** One command plan and result transformer serve both transports, keeping
  path checks, shell timeouts, file-list decoding, artifacts, patch validation, and PR URL extraction
  identical. The workspace owns the pool lifecycle and disconnects all sessions on teardown.
- **Evidence:** Process-backed tests launch fake SSH and app-server executables to prove handshake,
  two-command connection reuse, nonzero exits, pre-dispatch unavailability, and post-dispatch loss.
  App tests prove artifact finalization, safe fallback, cwd/timeout forwarding, and no fallback after
  ambiguous execution. The remote parity source gate binds the client, pool, workspace wiring, tests,
  research, and matrix claim.

## 2026-07-16: Auto-review denials are durable and exactly retryable once

- **History boundary:** Every completed review records a typed outcome, bounded rationale, reviewer
  provenance, risk, authorization source, and a canonical redacted action identity. The Denials
  surface reconstructs its newest ten entries from durable thread events instead of maintaining a
  second mutable history store.
- **Retry boundary:** A denied action may be retried once only when its turn, workspace, safety mode,
  tool name, and canonical arguments still match. Retry creates fresh request and tool-call IDs and
  passes through Auto review again; it never converts a denial into approval or edits the call.
- **Privacy boundary:** Calls whose arguments could not be retained safely are visible as denials but
  are not replayable. The retry receipt is persisted before execution so a crash or relaunch cannot
  dispatch the same denied mutation twice.
- **Interaction boundary:** `/approve`, `/approvals`, and `/denials` open one calm control surface and
  do not add a user message or model turn. Available, reviewing, consumed, unavailable, and
  context-changed states are explicit, and a reviewer denial remains a denial after retry.
- **Circuit-breaker boundary:** Auto review pauses after three consecutive denials or ten denials in
  the newest fifty completed reviews. A non-denial resets the consecutive count; timeouts do not
  masquerade as safety denials.
- **Evidence:** Core history and retry-state tests, agent exact-replay/circuit-breaker tests, native
  persistence tests, command-routing tests, and Playwright lifecycle coverage prove denial, reopen,
  exact re-review, successful execution, durable consumption, and refusal of a second execution.

## 2026-07-16: Guardian denial approval reuses durable Auto review

- **Protocol boundary:** `thread/approveGuardianDeniedAction` accepts the current Codex Guardian event
  shape and acknowledges non-denied status without work. Started and completed Auto-review state uses
  the current dedicated notification methods instead of being inferred from generic tool cards.
- **Authority boundary:** The client event is never executable input. Its review, turn, target item,
  and normalized action must match one available durable denial exactly. QuillCode reconstructs the
  command, patch, or MCP call only from private persisted history and retains the original user text.
- **Execution boundary:** A matched denial goes through the existing exact one-shot retry primitive,
  receives a fresh Auto review, and persists the consumed receipt before dispatch. Forged, stale,
  redacted, context-changed, concurrent, or replayed requests fail closed.
- **Evidence:** A full actor test proves validation, response ordering, fresh review, exact shell side
  effect, durable consumption, and replay rejection. The built JSONL smoke proves the public method
  rejects an unknown review deterministically, and a parity gate binds all implementation evidence.

## 2026-07-16: App-server execution environments fail closed across every host path

- **Registry boundary:** One process-scoped registry serves every stdio, TCP WebSocket, and Unix
  WebSocket client. `environment/add` mutates it immediately, acknowledges without waiting, and starts
  connection in the background; replacement closes the old client, `environment/info` may recover a
  connection, and transport shutdown closes all remaining clients. Observation-only
  `environment/status` returns ready, pending, disconnected-with-error, or unknown-with-error without
  creating or recovering transport state.
- **Selection boundary:** Omitted environment arrays preserve the prior/default target, an empty array
  disables host access, and a nonempty array validates and selects its first entry. Selection persists
  with thread settings across start, resume, fork, and turn-level updates. Unknown IDs and malformed
  CWDs fail before a turn or direct command can dispatch.
- **Transport boundary:** Remote clients use a text-frame WebSocket, initialize/initialized handshake,
  resumable session ID, a persistent receive loop, request-ID-routed concurrent response ownership,
  bounded responses, and per-request deadlines. The receive loop observes closure even while idle; a
  ready status probe uses only the existing connection and has its own ten-second deadline.
  Process reads convert the exclusive `nextSeq` into the inclusive `afterSeq` cursor and continue
  through exit until output streams close, retaining late output without duplication or gaps. A failed
  request resets the connection but is never replayed; only a later independent request may reconnect.
  Cancellation of one long-poll read retires that exact request ID and drains a possible late reply
  without resetting the multiplexed connection. Duplicate pending request IDs and reuse before an
  abandoned response is drained fail closed instead of replacing a live continuation. Unknown response
  IDs still fail the protocol closed.
- **Lifecycle boundary:** Registry subscriptions compare source-observation instants rather than task
  delivery order, so a queued old transition cannot become a replay for a new subscriber. Every
  subscribed thread whose first selected environment matches receives future connected/disconnected
  notifications; current state, unselected threads, and unsubscribed threads stay silent.
- **Execution boundary:** Selected remote turns replace local shell/file/patch routing with the
  exec-server adapter and target-native workspace paths. Canonical containment blocks symlink escapes,
  existing files require a prior read before write/patch, temporary stdin and patch files are cleaned,
  and web search remains on the cloud-owned route. Environment context is XML-escaped and transient;
  it is placed immediately before the active user request and never enters durable transcript history.
- **No-fallback boundary:** Direct `thread/shellCommand` resolves the same selected environment before
  creating lifecycle state. Remote commands retain the one-hour user-shell timeout and execute only
  through exec-server; disabled access returns `-32600`. Neither path can silently execute on the
  app-server host.
- **Unified process boundary:** Local and remote user shells occupy one background-terminal registry.
  Local process IDs are their OS PIDs; remote sessions receive high descending signed-32-bit app-server
  IDs and report null `osPid`. Both stream output and support the same list, pagination, terminate,
  clean, interrupt, and disconnect lifecycle. Remote terminate is acknowledged before canceling its
  read loop so a canceled reader cannot suppress the remote RPC or tear down unrelated processes.
- **Sandbox boundary:** Each selected remote executor derives one immutable, target-native
  `FileSystemSandboxContext` from the thread's effective policy and remote workspace. Read-only grants
  root read access; workspace-write adds project roots, allowed temporary roots, explicit writable
  roots, and read-only project metadata; danger-full-access uses the protocol's disabled profile.
  Every process and filesystem request carries that context explicitly. Cross-drive Windows roots
  fail closed. Process launches forward the structured managed-network profile and
  `enforceManagedNetwork` when managed requirements define one, while enforcement remains target-owned
  rather than claimed by the local client.
- **Remote search boundary:** Remote `host.file.search` uses exec-server filesystem RPCs rather
  than target shell commands. The scanner canonicalizes the selected root, walks bounded directory
  entries, skips build/dependency directories plus oversized or non-UTF-8 files, and returns the same
  structured match payload for POSIX and Windows/PowerShell remotes without `rg`, `grep`, or host-local
  fallback.
- **Evidence:** Registry, target-path, tool-router, session, direct-shell, and real URLSession WebSocket
  tests cover status shapes, source-ordered future transitions, idle disconnect, selected-thread
  fanout, selection, replacement, concurrency, reconnection, multi-read cursors, late output, context,
  path, cross-platform remote search, exact sandbox serialization/forwarding, and no-fallback behavior. A built `quill-code
  app-server` smoke talks to a raw loopback
  exec-server, forces a disconnect and resumable reconnect, verifies lifecycle methods and multi-read
  remote output, asserts the read-only profile on filesystem and process requests, and uses local
  filesystem sentinels to prove remote and disabled commands never ran locally. It also launches two
  long-lived remote shells, proves output arrives before completion, verifies null OS PIDs, terminates
  one, cleans the other, asserts both operations reuse the established WebSocket, and locks the pending
  response registry against duplicate or prematurely reused request IDs.

## 2026-07-17: Remote environment registration validates WebSocket URLs before side effects

- **Decision:** `environment/add` trims and validates `execServerUrl` before constructing a client,
  mutating the process registry, or starting background connection work. Only nonempty `ws://` and
  `wss://` URLs with a host are accepted; disabled sentinel values and other URL schemes fail as
  `-32600` invalid requests.
- **Why:** The exec-server client and researched Codex contract are WebSocket-based. Letting malformed
  or non-WebSocket endpoints enter the registry made `environment/status` look like a real pending
  environment until the background client failed, and it could leave stale selectable targets.
- **Evidence:** `AppServerEnvironmentRegistryTests` proves invalid endpoints fail without factory
  creation, while `AppServerEnvironmentSessionTests` proves the public JSON-RPC shape leaves the
  environment unknown after rejection.

## 2026-07-17: MCP patch approvals expose path-keyed file-change metadata

- **Compatibility boundary:** `quill-code mcp-server` keeps the existing `elicitation/create`
  approval request and raw `codex_changes.arguments` payload, but patch approvals now also include a
  bounded path-keyed `codex_file_changes` map and the same map at `codex_changes.changes`.
- **Scope boundary:** The map is derived only from the already-redacted pending tool call before any
  approval response can execute work. `host.file.write` reports one `write` entry, while
  `host.apply_patch` reuses the shared patch path parser and classifies touched files as `create`,
  `delete`, or `modify` from unified-diff headers. The projection never reads or mutates the
  workspace, caps paths/counts, and excludes `/dev/null`.
- **Failure boundary:** Unknown future file-changing tools retain patch-approval behavior but produce
  an empty compatibility map instead of fabricating paths. Clients that only understand the previous
  raw-arguments payload continue to work unchanged.
- **Evidence:** `MCPServerSessionTests` now assert path-keyed metadata for both `host.file.write` and
  `host.apply_patch` approval requests, including create/modify classification and non-execution after
  denial.

## 2026-07-18: LCOV artifacts render bounded coverage summaries

- **Decision:** Local `lcov.info` and `.lcov` artifacts render as structured coverage-report cards
  instead of generic text/data files. The preview scans only the first 512 KB, parses standard LCOV
  record lines, and shows source-file count, line/branch/function coverage, file size, truncation
  state, and a capped source-file list.
- **Why:** Coding agents commonly produce coverage reports while fixing tests. Codex-style artifact
  handling should make the result immediately inspectable without asking the model to re-open the raw
  report, and without executing test tooling or expanding arbitrary report contents.
- **Boundary:** The parser is local-file-only, UTF-8-only, NUL-rejecting, and line-oriented. It never
  shells out, never follows report paths, and never fetches remote coverage URLs. Explicit LCOV totals
  (`LF`/`LH`, `BRF`/`BRH`, `FNF`/`FNH`) are preserved when present; per-line/function/branch records
  provide fallback counts for partial reports.
- **Evidence:** `QuillCodeToolCardSurfaceTests.testArtifactStateDerivesLCOVPreviewMetadata` covers
  classification, totals, fallback counts, source labels, invalid reports, and remote exclusion.
  `WorkspaceHTMLToolCardRendererTests.testHTMLRendererIncludesLCOVArtifactPreview` covers the static
  HTML selectors and rendered coverage metadata.

## 2026-07-18: SARIF artifacts render bounded static-analysis summaries

- **Decision:** Local `.sarif` and `.sarif.json` artifacts render as structured static-analysis
  report cards instead of generic JSON. The preview parses bounded SARIF JSON and shows SARIF
  version, run/result counts, level counts, file size, capped tool labels, and capped rule labels.
- **Why:** Coding agents often produce CodeQL, Semgrep, and other scanner reports while reviewing or
  hardening code. A Codex-style artifact surface should make those reports immediately scannable
  without requiring the model to re-open a large JSON document or invent a summary.
- **Boundary:** The parser is local-file-only, regular-file-only, NUL-rejecting, and capped at 512 KB.
  It never shells out, never follows SARIF result paths, and never fetches remote report URLs. Compound
  `.sarif.json` files are classified as SARIF before the generic JSON preview so only one truthful
  preview is shown.
- **Evidence:** `QuillCodeToolCardSurfaceTests.testArtifactStateDerivesSARIFPreviewMetadata` covers
  compound and direct extensions, version/count metadata, tool/rule labels, invalid reports, remote
  exclusion, and generic JSON suppression.
  `WorkspaceHTMLToolCardRendererTests.testHTMLRendererIncludesSARIFArtifactPreview` covers static HTML
  selectors and rendered SARIF metadata.

## 2026-07-18: JUnit XML artifacts render bounded test-report summaries

- **Decision:** Local `.xml` artifacts whose root element is `testsuite` or `testsuites` render as
  structured JUnit report cards instead of generic XML. The preview shows suite/test counts,
  failure/error/skipped counts, aggregate duration, file size, capped suite labels, and capped failing
  testcase labels.
- **Why:** Coding agents frequently create JUnit XML through test runners and CI jobs. A Codex-style
  artifact surface should make pass/fail shape immediately visible without asking the model to parse a
  raw XML tree or flood the transcript with testcase logs.
- **Boundary:** The parser is local-file-only, regular-file-only, NUL-rejecting, and capped at 512 KB.
  It never expands testcase stdout/stderr, never follows paths or classname references, and never
  fetches remote reports. Generic XML rendering is suppressed only when the JUnit root validates.
- **Evidence:** `QuillCodeToolCardSurfaceTests.testArtifactStateDerivesJUnitPreviewMetadata` covers
  aggregate attributes, testcase-observed fallback counts, failing labels, non-JUnit XML exclusion,
  and remote exclusion. `WorkspaceHTMLToolCardRendererTests.testHTMLRendererIncludesJUnitArtifactPreview`
  covers static HTML selectors, rendered metadata, and generic XML suppression.

## 2026-07-19: Cobertura XML artifacts render bounded coverage summaries

- **Decision:** Local `.xml` artifacts whose root element is `coverage` render as structured
  Cobertura coverage cards instead of generic XML. The preview shows package/class counts,
  line/branch coverage, file size, capped package labels, and capped class labels.
- **Why:** Coverage jobs commonly emit Cobertura XML even when LCOV is unavailable. Codex-style
  artifact handling should make coverage shape visible in one glance without requiring the agent to
  re-open raw XML or summarize a broad report tree in chat.
- **Boundary:** The parser is local-file-only, regular-file-only, NUL-rejecting, and capped at
  512 KB. It never executes coverage tools, never follows class filenames or source paths, never reads
  referenced files, and never fetches remote coverage URLs. Generic XML rendering is suppressed only
  after the Cobertura root validates.
- **Evidence:** `QuillCodeToolCardSurfaceTests.testArtifactStateDerivesCoberturaPreviewMetadata`
  covers count-based coverage, rate-only fallback, package/class labels, non-Cobertura XML exclusion,
  and remote exclusion.
  `WorkspaceHTMLToolCardRendererTests.testHTMLRendererIncludesCoberturaArtifactPreview` covers static
  HTML selectors, rendered coverage metadata, content lists, and generic XML suppression.

## 2026-07-19: Clover XML artifacts render bounded coverage summaries

- **Decision:** Local `.xml` artifacts whose root element is `coverage` and whose content has
  Clover-style project/metrics markers render as structured Clover coverage cards instead of generic
  XML. The preview shows package/file/class counts, element/method/statement/conditional coverage,
  file size, capped project labels, and capped file labels.
- **Why:** Clover and Cobertura both use a `coverage` root, but they encode coverage shape
  differently. Codex-style artifact handling should recognize both common CI report formats without
  treating one as the other or dumping a raw XML tree into the transcript.
- **Boundary:** The parser is local-file-only, regular-file-only, NUL-rejecting, and capped at
  512 KB. It never executes coverage tools, never follows file paths from `<file>` elements, never
  reads referenced source files, and never fetches remote coverage URLs. Cobertura detection now
  requires Cobertura-specific coverage attributes so Clover reports are not misclassified.
- **Evidence:** `QuillCodeToolCardSurfaceTests.testArtifactStateDerivesCloverPreviewMetadata` covers
  metric-derived coverage labels, project/file labels, non-Clover XML exclusion, Cobertura
  disambiguation, and remote exclusion.
  `WorkspaceHTMLToolCardRendererTests.testHTMLRendererIncludesCloverArtifactPreview` covers static
  HTML selectors, rendered coverage metadata, content lists, Cobertura suppression, and generic XML
  suppression.

## 2026-07-19: JaCoCo XML artifacts render bounded coverage summaries

- **Decision:** Local `.xml` artifacts whose root element is `report` and whose content has JaCoCo
  package/session/counter markers render as structured JaCoCo coverage cards instead of generic XML.
  The preview shows package/source/class counts, line/branch/method/class coverage, file size, capped
  package labels, and capped source-file labels.
- **Why:** Java and Kotlin projects often produce JaCoCo XML in CI. A Codex-style coding surface
  should make those coverage reports immediately scannable without requiring the model to parse raw
  XML or re-run coverage tooling.
- **Boundary:** The parser is local-file-only, regular-file-only, NUL-rejecting, and capped at
  512 KB. It records only root-level aggregate counters, never executes coverage tools, never follows
  package/source/class names as paths, never reads referenced source files, and never fetches remote
  coverage URLs. Generic XML rendering is suppressed only after the JaCoCo root validates.
- **Evidence:** `QuillCodeToolCardSurfaceTests.testArtifactStateDerivesJaCoCoPreviewMetadata` covers
  aggregate counters, package/source labels, non-JaCoCo XML exclusion, non-overlap with other XML
  report parsers, and remote exclusion.
  `WorkspaceHTMLToolCardRendererTests.testHTMLRendererIncludesJaCoCoArtifactPreview` covers static
  HTML selectors, rendered coverage metadata, content lists, and generic XML suppression.

## 2026-07-19: Istanbul JSON artifacts render bounded coverage summaries

- **Decision:** Local JSON artifacts that match Istanbul/nyc `coverage-final.json` or
  `coverage-summary.json` shapes render as structured Istanbul coverage cards instead of generic JSON.
  The preview shows source-file count, line/statement/branch/function coverage, file size, and capped
  source-file labels.
- **Why:** JavaScript and TypeScript projects commonly emit Istanbul/nyc JSON while coding agents fix
  test coverage. A Codex-style artifact surface should make the coverage shape visible without asking
  the model to inspect raw JSON or re-run project tooling.
- **Boundary:** The parser is local-file-only, regular-file-only, NUL-rejecting, and capped at
  512 KB. It reads only the artifact JSON, never executes coverage tools, never follows covered source
  paths, never reads referenced source files, and never fetches remote coverage URLs. Generic JSON
  rendering is suppressed only after an Istanbul coverage shape validates.
- **Evidence:** `QuillCodeToolCardSurfaceTests.testArtifactStateDerivesIstanbulPreviewMetadata`
  covers final-report counters, summary-report counters, source-file labels, generic JSON exclusion,
  and remote exclusion.
  `WorkspaceHTMLToolCardRendererTests.testHTMLRendererIncludesIstanbulArtifactPreview` covers static
  HTML selectors, rendered coverage metadata, content lists, and generic JSON suppression.

## 2026-07-19: Go coverage artifacts render bounded coverage summaries

- **Decision:** Local `cover.out` and `coverage.out` artifacts with a valid Go coverage `mode:`
  header render as structured Go coverage cards instead of generic `.out` files. The preview shows
  coverage mode, source-file count, block count, statement coverage, file size, truncation state, and
  capped source-file labels.
- **Why:** Go projects commonly produce coverage profiles through `go test -coverprofile=cover.out`.
  A Codex-style artifact surface should make those reports scannable in the transcript without
  requiring the agent to run `go tool cover` or infer coverage from raw profile lines.
- **Boundary:** The parser is local-file-only, regular-file-only, NUL-rejecting, and capped at
  512 KB. It accepts only `set`, `count`, and `atomic` modes, reads only the coverage profile,
  never executes Go tooling, never follows covered source paths, never reads referenced source files,
  and never fetches remote coverage URLs. Other `.out` files remain unclassified.
- **Evidence:** `QuillCodeToolCardSurfaceTests.testArtifactStateDerivesGoCoveragePreviewMetadata`
  covers mode parsing, aggregate statement coverage, source labels, `coverage.out`, generic `.out`
  exclusion, invalid-mode rejection, and remote exclusion.
  `WorkspaceHTMLToolCardRendererTests.testHTMLRendererIncludesGoCoverageArtifactPreview` covers
  static HTML selectors, rendered coverage metadata, and source-file lists.

## 2026-07-19: coverage.py JSON artifacts render bounded coverage summaries

- **Decision:** Local JSON artifacts with the coverage.py `meta`/`files`/`totals` shape render as
  structured Python coverage cards instead of generic JSON. The preview shows coverage.py version,
  source-file count, line/branch coverage, file size, and capped source-file labels.
- **Why:** Python projects commonly emit `coverage json` reports while agents debug failing tests and
  coverage regressions. A Codex-style artifact surface should make those reports immediately
  scannable without asking the model to inspect raw JSON or rerun coverage.py.
- **Boundary:** The parser is local-file-only, regular-file-only, NUL-rejecting, and capped at
  512 KB. It reads only the artifact JSON, never executes coverage.py, never follows covered source
  paths, never reads referenced source files, and never fetches remote coverage URLs. Generic JSON
  rendering is suppressed only after the coverage.py report shape validates.
- **Evidence:** `QuillCodeToolCardSurfaceTests.testArtifactStateDerivesCoveragePyPreviewMetadata`
  covers totals, source labels, generic JSON exclusion, and remote exclusion.
  `WorkspaceHTMLToolCardRendererTests.testHTMLRendererIncludesCoveragePyArtifactPreview` covers
  static HTML selectors, rendered coverage metadata, source-file lists, and generic JSON suppression.

## 2026-07-19: pytest JSON artifacts render bounded test summaries

- **Decision:** Local JSON artifacts with the pytest-json-report `summary`/`tests` shape render as
  structured pytest report cards instead of generic JSON. The preview shows exit code, duration,
  total/pass/fail/error/skip counts, file size, and capped failed/error test node IDs.
- **Why:** Python coding-agent loops often emit pytest JSON when narrowing failures. A Codex-style
  artifact surface should make failing tests visible immediately without requiring the model to read
  raw JSON or expand captured logs.
- **Boundary:** The parser is local-file-only, regular-file-only, NUL-rejecting, and capped at
  512 KB. It reads only the artifact JSON, never opens referenced source files, never expands
  captured stdout/stderr/tracebacks from test phases, and never fetches remote report URLs. Generic
  JSON rendering is suppressed only after the pytest report shape validates.
- **Evidence:** `QuillCodeToolCardSurfaceTests.testArtifactStateDerivesPytestJSONPreviewMetadata`
  covers summary counts, failing labels, generic JSON exclusion, and remote exclusion.
  `WorkspaceHTMLToolCardRendererTests.testHTMLRendererIncludesPytestJSONArtifactPreview` covers
  static HTML selectors, rendered report metadata, failure lists, and generic JSON suppression.

## 2026-07-19: TAP artifacts render bounded test summaries

- **Decision:** Local `.tap` artifacts that match Test Anything Protocol plan/assertion/bailout
  lines render as structured TAP report cards instead of generic data files. The preview shows plan,
  assertion count, pass/fail/skip/TODO counts, bailout reason, file size, and capped failing
  assertion labels.
- **Why:** TAP remains common in Node, Perl, and CI test output. A Codex-style artifact surface should
  make failing assertions scannable without forcing the agent to inspect raw test protocol text.
- **Boundary:** The parser is local-file-only, regular-file-only, NUL-rejecting, and capped at
  512 KB plus 20,000 lines. It reads only TAP protocol summary lines, never expands YAML-ish
  diagnostics, never opens referenced source files, and never fetches remote TAP reports.
- **Evidence:** `QuillCodeToolCardSurfaceTests.testArtifactStateDerivesTAPPreviewMetadata` covers
  plan parsing, pass/fail/skip/TODO counts, bailout labels, generic `.tap` exclusion, and remote
  exclusion. `WorkspaceHTMLToolCardRendererTests.testHTMLRendererIncludesTAPArtifactPreview` covers
  static HTML selectors, rendered report metadata, and failure lists.

## 2026-07-19: Jest JSON artifacts render bounded test summaries

- **Decision:** Local `.json` artifacts with Jest-compatible `numTotalTests`/`testResults` report
  shape render as structured Jest JSON report cards instead of generic JSON. The preview shows run
  result, runtime, test/suite counts, file size, and capped failing assertion labels.
- **Why:** TypeScript and JavaScript coding-agent loops commonly emit Jest or Vitest JSON reports.
  Showing the failing assertions inline keeps generated test artifacts useful without requiring a
  separate file open.
- **Boundary:** The parser is local-file-only, regular-file-only, NUL-rejecting, shape-gated, and
  capped at 512 KB. It reads only summary counts, suite runtime, and assertion titles, never expands
  failure messages/stacks, never opens referenced source files, and never fetches remote JSON.
- **Evidence:** `QuillCodeToolCardSurfaceTests.testArtifactStateDerivesJestJSONPreviewMetadata`
  covers result/count/runtime parsing, failing assertion labels, generic JSON exclusion, and remote
  exclusion. `WorkspaceHTMLToolCardRendererTests.testHTMLRendererIncludesJestJSONArtifactPreview`
  covers static HTML selectors, rendered report metadata, failure lists, and generic JSON
  suppression.

## 2026-07-19: TRX artifacts render bounded test summaries

- **Decision:** Local `.trx` artifacts whose XML root validates as `TestRun` and contains
  `UnitTestResult` entries render as structured Visual Studio TRX report cards. The preview shows
  run name, outcome counts, duration, file size, and capped failing test names.
- **Why:** .NET and Visual Studio test loops commonly emit TRX reports. A Codex-style artifact surface
  should make failed tests scannable without opening XML or asking the model to parse raw logs.
- **Boundary:** The parser is local-file-only, regular-file-only, NUL-rejecting, root-gated, and
  capped at 512 KB. It reads only `UnitTestResult` attributes, never expands failure output/stacks,
  never opens referenced files, and never fetches remote TRX reports.
- **Evidence:** `QuillCodeToolCardSurfaceTests.testArtifactStateDerivesTRXPreviewMetadata` covers
  run metadata, outcome counts, duration, failing labels, non-TRX exclusion, and remote exclusion.
  `WorkspaceHTMLToolCardRendererTests.testHTMLRendererIncludesTRXArtifactPreview` covers static HTML
  selectors, rendered report metadata, and failure lists.

## 2026-07-19: xUnit XML artifacts render bounded test summaries

- **Decision:** Local `.xml` artifacts whose root validates as `assemblies` or `assembly` render as
  structured xUnit.net report cards. The preview shows assembly, collection, test, pass, fail, and
  skip counts plus duration, file size, capped assembly names, and capped failing test names.
- **Why:** .NET projects commonly emit xUnit XML when TRX is not enabled. Showing a compact report
  keeps test artifacts useful in the transcript without asking the agent or user to inspect raw XML.
- **Boundary:** The parser is local-file-only, regular-file-only, NUL-rejecting, root-gated, and
  capped at 512 KB. It reads assembly/test attributes only, never expands failure output/stacks,
  never opens referenced assemblies or source files, and never fetches remote XML reports. Generic
  XML rendering is suppressed only after the xUnit report root validates.
- **Evidence:** `QuillCodeToolCardSurfaceTests.testArtifactStateDerivesXUnitPreviewMetadata` covers
  aggregate and per-test counts, duration, failing labels, non-xUnit exclusion, and remote exclusion.
  `WorkspaceHTMLToolCardRendererTests.testHTMLRendererIncludesXUnitArtifactPreview` covers static
  HTML selectors, rendered report metadata, assembly lists, failure lists, and generic XML
  suppression.

## 2026-07-19: NUnit XML artifacts render bounded test summaries

- **Decision:** Local `.xml` artifacts whose root validates as `test-run` render as structured NUnit
  report cards. The preview shows run name, test, pass, fail, inconclusive, and skip counts plus
  duration, file size, and capped failing test names.
- **Why:** NUnit is a common .NET test runner and often emits `TestResult.xml` instead of TRX or
  xUnit XML. A Codex-style artifact surface should make the useful result summary visible without
  asking the model to inspect raw XML.
- **Boundary:** The parser is local-file-only, regular-file-only, NUL-rejecting, root-gated, and
  capped at 512 KB. It reads run and `test-case` attributes only, never expands failure output,
  assertion messages, stack traces, source files, or referenced assemblies, and never fetches remote
  XML reports. Generic XML rendering is suppressed only after the NUnit root validates.
- **Evidence:** `QuillCodeToolCardSurfaceTests.testArtifactStateDerivesNUnitPreviewMetadata` covers
  aggregate and per-test counts, duration, failing labels, non-NUnit exclusion, and remote exclusion.
  `WorkspaceHTMLToolCardRendererTests.testHTMLRendererIncludesNUnitArtifactPreview` covers static
  HTML selectors, rendered report metadata, failure lists, and generic XML suppression.

## 2026-07-19: CycloneDX SBOM artifacts render bounded supply-chain summaries

- **Decision:** Local `.json` artifacts whose top-level `bomFormat` validates as `CycloneDX` render
  as structured SBOM cards. The preview shows spec version, serial number, root component,
  component/service/dependency counts, vulnerability severity counts, file size, and capped component
  labels.
- **Why:** Coding agents increasingly produce SBOMs during build, release, dependency audit, and
  security workflows. A Codex-style artifact surface should make the supply-chain shape immediately
  scannable without asking the model to read or summarize raw SBOM JSON.
- **Boundary:** The parser is local-file-only, regular-file-only, NUL-rejecting, and capped at
  512 KB. It validates `bomFormat: CycloneDX`, reads only shallow metadata, component labels,
  dependency counts, service counts, and vulnerability severities, and never expands license text,
  hashes, evidence, references, external references, advisories, or remote SBOM URLs. Generic JSON
  rendering is suppressed only after the CycloneDX shape validates.
- **Evidence:** `QuillCodeToolCardSurfaceTests.testArtifactStateDerivesCycloneDXPreviewMetadata`
  covers metadata extraction, vulnerability severity counts, component labels, generic JSON
  suppression, non-CycloneDX exclusion, and remote exclusion.
  `WorkspaceHTMLToolCardRendererTests.testHTMLRendererIncludesCycloneDXArtifactPreview` covers static
  HTML selectors, rendered SBOM metadata, component lists, and generic JSON suppression.

## 2026-07-19: SPDX JSON artifacts render bounded SBOM summaries

- **Decision:** Local `.json` artifacts whose top-level `spdxVersion` validates as an SPDX document
  render as structured SPDX SBOM cards. The preview shows spec version, document name, namespace,
  package/file/relationship counts, extracted-license count, creator count, file size, capped
  package labels, and capped license identifiers.
- **Why:** SPDX JSON is another common SBOM format for release, compliance, and dependency audit
  workflows. QuillCode should make SPDX outputs scannable as first-class coding artifacts rather than
  dropping users into raw JSON.
- **Boundary:** The parser is local-file-only, regular-file-only, NUL-rejecting, and capped at
  512 KB. It validates `spdxVersion` plus document/package/file shape, reads only shallow document,
  package, creator, relationship, and license identifier metadata, and never expands extracted
  license text, checksums, snippets, annotations, relationship bodies, external document references,
  or remote SBOM URLs. Generic JSON rendering is suppressed only after SPDX shape validates.
- **Evidence:** `QuillCodeToolCardSurfaceTests.testArtifactStateDerivesSPDXPreviewMetadata` covers
  metadata extraction, package labels, license labels, non-SPDX exclusion, and remote exclusion.
  `WorkspaceHTMLToolCardRendererTests.testHTMLRendererIncludesSPDXArtifactPreview` covers static HTML
  selectors, rendered SBOM metadata, package and license lists, extracted-text exclusion, and generic
  JSON suppression.

## 2026-07-19: npm lockfile artifacts render bounded dependency summaries

- **Decision:** Local `package-lock.json` artifacts render as structured npm lockfile cards. The
  preview shows lockfile version, root package, package/dependency/dev/optional counts, file size,
  capped package labels, and capped resolved registry hosts.
- **Why:** Coding agents frequently touch JavaScript dependency graphs, and npm lockfiles are too
  large and repetitive for raw text or generic JSON previews. A Codex-style artifact surface should
  make dependency changes scannable without asking the model to inspect the entire lockfile.
- **Boundary:** The parser is local-file-only, regular-file-only, NUL-rejecting, filename-gated to
  `package-lock.json`, and capped at 512 KB. It validates `lockfileVersion` plus `packages` or
  `dependencies`, reads only shallow package labels, counts, and resolved URL hosts, and never
  expands integrity hashes, package scripts, dependency bodies, funding metadata, or remote tarballs.
  Generic JSON rendering is suppressed only after the npm lockfile shape validates.
- **Evidence:** `QuillCodeToolCardSurfaceTests.testArtifactStateDerivesNPMLockfilePreviewMetadata`
  covers metadata extraction, package labels, registry host labels, non-lockfile exclusion, and remote
  exclusion. `WorkspaceHTMLToolCardRendererTests.testHTMLRendererIncludesNPMLockfileArtifactPreview`
  covers static HTML selectors, rendered npm metadata, package and source lists, and generic JSON
  suppression.

## 2026-07-19: SwiftPM Package.resolved artifacts render bounded pin summaries

- **Decision:** Local `Package.resolved` artifacts render as structured SwiftPM resolved-package
  cards. The preview shows schema version, pin count, versioned/branch/revision-only counts, file
  size, capped pin labels, and capped source hosts. `Package.resolved` is also classified as a data
  artifact despite having no extension.
- **Why:** QuillCode is a Swift project and Swift coding agents regularly review or update package
  pins. The useful question is which dependencies and source hosts changed, not the full raw JSON
  body or complete revisions.
- **Boundary:** The parser is local-file-only, regular-file-only, NUL-rejecting, filename-gated to
  `Package.resolved`, and capped at 512 KB. It validates the top-level `pins` array, reads only
  identity, location/repository URL, version, branch, and short revision metadata, and never expands
  full revisions, package manifests, dependency source bodies, or remote repositories.
- **Evidence:**
  `QuillCodeToolCardSurfaceTests.testArtifactStateDerivesSwiftPMPackageResolvedPreviewMetadata`
  covers filename-based document classification, metadata extraction, pin labels, source hosts,
  non-`Package.resolved` exclusion, and remote exclusion.
  `WorkspaceHTMLToolCardRendererTests.testHTMLRendererIncludesSwiftPMPackageResolvedArtifactPreview`
  covers static HTML selectors, rendered SwiftPM metadata, pin/source lists, and text-preview
  coexistence.

## 2026-07-19: Cargo.lock artifacts render bounded dependency summaries

- **Decision:** Local `Cargo.lock` artifacts render as structured Cargo lockfile cards. The preview
  shows package count, version/source/checksum counts, file size, capped package labels, and capped
  source labels. `Cargo.lock` is classified as a data artifact through filename-specific detection.
- **Why:** Rust dependency changes are common coding-agent artifacts, and raw Cargo lockfiles are
  repetitive. Users need a quick dependency/source summary before opening the full lockfile.
- **Boundary:** The parser is local-file-only, regular-file-only, NUL-rejecting, filename-gated to
  `Cargo.lock`, and capped at 512 KB. It reads shallow `[[package]]` fields for `name`, `version`,
  `source`, and `checksum`, and never expands dependency arrays, full checksums, manifests, crate
  metadata, registry indexes, or remote repositories.
- **Evidence:** `QuillCodeToolCardSurfaceTests.testArtifactStateDerivesCargoLockPreviewMetadata`
  covers filename-based document classification, package/version/source/checksum counts, package
  labels, source labels, non-`Cargo.lock` exclusion, and remote exclusion.
  `WorkspaceHTMLToolCardRendererTests.testHTMLRendererIncludesCargoLockArtifactPreview` covers static
  HTML selectors, rendered Cargo metadata, package/source lists, and text-preview coexistence.

## 2026-07-19: yarn.lock artifacts render bounded package summaries

- **Decision:** Local `yarn.lock` artifacts render as structured Yarn lockfile cards. The preview
  shows package count, version/resolution/integrity counts, file size, capped package labels, and
  capped resolved registry host labels. `yarn.lock` is classified as a data artifact through
  filename-specific detection.
- **Why:** JavaScript dependency changes often arrive as lockfile-only edits. A bounded package/source
  summary lets users inspect the dependency impact without reading repetitive lockfile entries.
- **Boundary:** The parser is local-file-only, regular-file-only, NUL-rejecting, filename-gated to
  `yarn.lock`, and capped at 512 KB. It reads shallow Yarn v1/v2-style descriptor blocks for
  `version`, `resolved`/`resolution`, `integrity`, and `checksum`, and never expands dependency graphs,
  integrity/checksum payloads, package manifests, registry indexes, or remote tarballs.
- **Evidence:** `QuillCodeToolCardSurfaceTests.testArtifactStateDerivesYarnLockfilePreviewMetadata`
  covers filename-based document classification, package/version/resolution/integrity counts, package
  labels, host labels, non-`yarn.lock` exclusion, and remote exclusion.
  `WorkspaceHTMLToolCardRendererTests.testHTMLRendererIncludesYarnLockfileArtifactPreview` covers
  static HTML selectors, rendered Yarn metadata, package/host lists, and text-preview coexistence.

## 2026-07-19: pnpm-lock.yaml artifacts render bounded package summaries

- **Decision:** Local `pnpm-lock.yaml` artifacts render as structured pnpm lockfile cards. The preview
  shows lockfile version, importer/package/dependency/integrity counts, file size, capped importer
  labels, capped package labels, and capped resolved registry host labels. `pnpm-lock.yaml` is
  classified as a data artifact through filename-specific detection.
- **Why:** pnpm monorepos often produce lockfiles with multiple importers and large package sections.
  A bounded importer/package/source summary makes dependency changes scannable without opening a
  repetitive YAML lockfile.
- **Boundary:** The parser is local-file-only, regular-file-only, NUL-rejecting, filename-gated to
  `pnpm-lock.yaml`, and capped at 512 KB. It validates `lockfileVersion`, reads shallow top-level
  `importers` and `packages` mappings plus package `resolution.integrity` and `resolution.tarball`,
  and never expands dependency graphs, integrity values, package manifests, registry indexes, or remote
  tarballs. Generic YAML rendering is suppressed only after the pnpm lockfile shape validates.
- **Evidence:** `QuillCodeToolCardSurfaceTests.testArtifactStateDerivesPNPMLockfilePreviewMetadata`
  covers filename-based document classification, lockfile version, importer/package/dependency/
  integrity counts, package labels, host labels, non-`pnpm-lock.yaml` exclusion, and remote exclusion.
  `WorkspaceHTMLToolCardRendererTests.testHTMLRendererIncludesPNPMLockfileArtifactPreview` covers
  static HTML selectors, rendered pnpm metadata, package/importer/host lists, YAML-preview suppression,
  and text-preview coexistence.

## 2026-07-19: composer.lock artifacts render bounded package summaries

- **Decision:** Local `composer.lock` artifacts render as structured Composer lockfile cards. The
  preview shows plugin API version, content-hash prefix, package/dev-package counts, file size, capped
  package labels, and capped source host labels. `composer.lock` is classified as a data artifact
  through filename-specific detection.
- **Why:** PHP dependency changes often produce large lockfile-only diffs. A bounded package/source
  summary lets users inspect dependency impact without reading repetitive Composer lockfile JSON.
- **Boundary:** The parser is local-file-only, regular-file-only, NUL-rejecting, filename-gated to
  `composer.lock`, and capped at 512 KB. It reads shallow top-level `packages`, `packages-dev`,
  `plugin-api-version`, and `content-hash`, plus package `name`, `version`, `source.url`, and
  `dist.url`; it never expands autoload metadata, scripts, full hashes, package manifests, Packagist
  metadata, source archives, or remote URLs. Generic JSON rendering is suppressed only after the
  Composer lockfile shape validates.
- **Evidence:** `QuillCodeToolCardSurfaceTests.testArtifactStateDerivesComposerLockfilePreviewMetadata`
  covers filename-based document classification, plugin API, content-hash prefix, package/dev counts,
  package labels, host labels, non-`composer.lock` exclusion, and remote exclusion.
  `WorkspaceHTMLToolCardRendererTests.testHTMLRendererIncludesComposerLockfileArtifactPreview` covers
  static HTML selectors, rendered Composer metadata, package/host lists, JSON-preview suppression, and
  text-preview coexistence.

## 2026-07-19: go.sum artifacts render bounded checksum summaries

- **Decision:** Local `go.sum` artifacts render as structured Go checksum cards. The preview shows
  module, version, checksum, and go.mod-checksum counts, file size, capped module labels, and capped
  source host labels. `go.sum` is classified as a data artifact through filename-specific detection.
- **Why:** Go dependency updates frequently produce checksum-only artifacts. Users need to see the
  module and source shape without reading a repetitive checksum file or asking the model to summarize
  it.
- **Boundary:** The parser is local-file-only, regular-file-only, NUL-rejecting, filename-gated to
  `go.sum`, and capped at 512 KB. It validates only the standard three-field `module version h1:...`
  line shape, records bounded module/version/host labels, and never expands hashes, runs Go tooling,
  contacts the Go checksum database, or fetches module sources.
- **Evidence:** `QuillCodeToolCardSurfaceTests.testArtifactStateDerivesGoSumPreviewMetadata` covers
  filename-based document classification, module/version/checksum/go.mod counts, module labels, host
  labels, non-`go.sum` exclusion, and remote exclusion.
  `WorkspaceHTMLToolCardRendererTests.testHTMLRendererIncludesGoSumArtifactPreview` covers static HTML
  selectors, rendered Go checksum metadata, module/host lists, and text-preview coexistence.

## 2026-07-19: requirements.txt artifacts render bounded Python dependency summaries

- **Decision:** Local `requirements.txt` and `requirements-*.txt` artifacts render as structured
  Python requirements cards. The preview shows package, pinned/ranged/editable/include/option/hash
  counts, file size, capped package labels, and capped source host labels. Matching requirements
  filenames are classified as data artifacts through filename-specific detection.
- **Why:** Python projects often expose dependency changes through requirements files rather than
  lockfiles. A bounded package/source summary makes those artifacts scannable without asking the model
  to read raw requirement lines.
- **Boundary:** The parser is local-file-only, regular-file-only, NUL-rejecting, filename-gated to
  `requirements.txt` and `requirements-*.txt`, and capped at 512 KB. It recognizes shallow pip
  requirement forms, editable installs, include/constraint lines, index/find-links options, hashes,
  environment markers, and direct URL host labels; it never runs pip, expands includes, validates
  hashes, reads package metadata, contacts package indexes, or fetches distributions.
- **Evidence:** `QuillCodeToolCardSurfaceTests.testArtifactStateDerivesPythonRequirementsPreviewMetadata`
  covers filename-based document classification, package/pinned/ranged/editable/include/option/hash
  counts, package labels, host labels, non-requirements exclusion, and remote exclusion.
  `WorkspaceHTMLToolCardRendererTests.testHTMLRendererIncludesPythonRequirementsArtifactPreview` covers
  static HTML selectors, rendered Python requirements metadata, package/host lists, and text-preview
  coexistence.

## 2026-07-19: poetry.lock artifacts render bounded Python lockfile summaries

- **Decision:** Local `poetry.lock` artifacts render as structured Poetry lockfile cards. The preview
  shows package, versioned-package, dev-package, optional-package, source, and hash counts, file size,
  capped package labels, and capped source labels. `poetry.lock` is classified as a data artifact
  through filename-specific detection.
- **Why:** Poetry lockfiles are common Python dependency artifacts. A bounded package/source/hash
  summary gives the user useful dependency impact at a glance without asking the model to scan raw
  lockfile text.
- **Boundary:** The parser is local-file-only, regular-file-only, NUL-rejecting, filename-gated to
  `poetry.lock`, and capped at 512 KB. It reads only shallow `[[package]]` sections and tracked scalar
  or inline values for `name`, `version`, `category`, `groups`, `optional`, `source`, and `files`; it
  never expands dependency tables, validates hashes, imports TOML package metadata, contacts package
  indexes, or fetches distributions.
- **Evidence:** `QuillCodeToolCardSurfaceTests.testArtifactStateDerivesPoetryLockPreviewMetadata`
  covers filename-based document classification, package/version/dev/optional/source/hash counts,
  package labels, source labels, non-`poetry.lock` exclusion, and remote exclusion.
  `WorkspaceHTMLToolCardRendererTests.testHTMLRendererIncludesPoetryLockArtifactPreview` covers static
  HTML selectors, rendered Poetry metadata, package/source lists, and text-preview coexistence.

## 2026-07-19: Pipfile.lock artifacts render bounded Python lockfile summaries

- **Decision:** Local `Pipfile.lock` artifacts render as structured Pipfile lockfile cards. The
  preview shows package, default-package, develop-package, pinned, editable, source, and hash counts,
  file size, capped package labels, and capped source labels. `Pipfile.lock` is classified as a data
  artifact through filename-specific detection.
- **Why:** Pipenv projects expose dependency impact through `Pipfile.lock`; a bounded summary keeps
  those artifacts scannable next to requirements and Poetry lockfiles without showing noisy raw JSON
  first.
- **Boundary:** The parser is local-file-only, regular-file-only, NUL-rejecting, filename-gated to
  `Pipfile.lock`, and capped at 512 KB. It reads only `_meta.sources`, shallow `default` and `develop`
  package maps, version/editable/hash/source fields, and URL hosts; it never expands dependency
  graphs, validates hashes, reads package metadata, contacts package indexes, or fetches
  distributions.
- **Evidence:** `QuillCodeToolCardSurfaceTests.testArtifactStateDerivesPipfileLockPreviewMetadata`
  covers filename-based document classification, default/develop/pinned/editable/source/hash counts,
  package labels, source labels, non-`Pipfile.lock` exclusion, and remote exclusion.
  `WorkspaceHTMLToolCardRendererTests.testHTMLRendererIncludesPipfileLockArtifactPreview` covers
  static HTML selectors, rendered Pipfile metadata, package/source lists, generic JSON suppression,
  and text-preview coexistence.

## 2026-07-19: uv.lock artifacts render bounded Python lockfile summaries

- **Decision:** Local `uv.lock` artifacts render as structured uv lockfile cards. The preview shows
  root Python requirement, package, versioned-package, dependency, source, and hash counts, file size,
  capped package labels, and capped source labels. `uv.lock` is classified as a data artifact through
  filename-specific detection.
- **Why:** uv is increasingly common in Python projects, and coding-agent dependency changes often
  produce `uv.lock` as the main review artifact. A bounded dependency/source/hash summary keeps the
  impact visible without rendering raw TOML-like lockfile content first.
- **Boundary:** The parser is local-file-only, regular-file-only, NUL-rejecting, filename-gated to
  `uv.lock`, and capped at 512 KB. It reads only the root `requires-python`, shallow `[[package]]`
  sections, package `name`/`version`, inline dependency entries, source URLs, and hash markers; it
  never expands dependency graphs, validates hashes, reads package metadata, contacts package
  indexes, or fetches distributions. Generic TOML rendering is suppressed only after the uv lockfile
  shape validates.
- **Evidence:** `QuillCodeToolCardSurfaceTests.testArtifactStateDerivesUVLockPreviewMetadata` covers
  filename-based document classification, Python requirement, package/version/dependency/source/hash
  counts, package labels, source labels, non-`uv.lock` exclusion, and remote exclusion.
  `WorkspaceHTMLToolCardRendererTests.testHTMLRendererIncludesUVLockArtifactPreview` covers static
  HTML selectors, rendered uv metadata, package/source lists, generic TOML suppression, and
  text-preview coexistence.

## 2026-07-19: Gemfile.lock artifacts render bounded Bundler summaries

- **Decision:** Local `Gemfile.lock` artifacts render as structured Bundler lockfile cards. The
  preview shows Bundler version, gem, dependency, platform, and source counts, file size, capped gem
  labels, and capped source labels. `Gemfile.lock` is classified as a data artifact through
  filename-specific detection.
- **Why:** Ruby projects often expose dependency changes through `Gemfile.lock`; a bounded gem/source
  summary keeps those artifacts scannable without forcing the user to inspect raw lockfile sections.
- **Boundary:** The parser is local-file-only, regular-file-only, NUL-rejecting, filename-gated to
  `Gemfile.lock`, and capped at 512 KB. It reads only shallow Bundler sections for `GEM`, `GIT`,
  `PATH`, `PLATFORMS`, `DEPENDENCIES`, and `BUNDLED WITH`; it never expands dependency graphs,
  validates checksums, reads gem metadata, contacts gem indexes, or fetches distributions.
- **Evidence:** `QuillCodeToolCardSurfaceTests.testArtifactStateDerivesGemfileLockPreviewMetadata`
  covers filename-based document classification, Bundler version, gem/dependency/platform/source
  counts, gem labels, source labels, non-`Gemfile.lock` exclusion, and remote exclusion.
  `WorkspaceHTMLToolCardRendererTests.testHTMLRendererIncludesGemfileLockArtifactPreview` covers
  static HTML selectors, rendered Bundler metadata, gem/source lists, and text-preview coexistence.

## 2026-07-19: Podfile.lock artifacts render bounded CocoaPods summaries

- **Decision:** Local `Podfile.lock` artifacts render as structured CocoaPods lockfile cards. The
  preview shows CocoaPods version, pod, dependency, source, and checksum counts, file size, capped
  pod labels, and capped source labels. `Podfile.lock` is classified as a data artifact through
  filename-specific detection.
- **Why:** iOS and Apple-platform projects commonly expose dependency changes through
  `Podfile.lock`; a bounded pod/source summary keeps those artifacts scannable without opening a
  long generated file.
- **Boundary:** The parser is local-file-only, regular-file-only, NUL-rejecting, filename-gated to
  `Podfile.lock`, and capped at 512 KB. It reads only shallow CocoaPods sections for `PODS`,
  `DEPENDENCIES`, `SPEC REPOS`, `EXTERNAL SOURCES`, `CHECKOUT OPTIONS`, `SPEC CHECKSUMS`, and
  `COCOAPODS`; it never runs CocoaPods, expands dependency graphs, validates checksums, reads
  podspecs, contacts spec repos, or fetches distributions.
- **Evidence:** `QuillCodeToolCardSurfaceTests.testArtifactStateDerivesPodfileLockPreviewMetadata`
  covers filename-based document classification, CocoaPods version, pod/dependency/source/checksum
  counts, pod labels, source labels, non-`Podfile.lock` exclusion, and remote exclusion.
  `WorkspaceHTMLToolCardRendererTests.testHTMLRendererIncludesPodfileLockArtifactPreview` covers
  static HTML selectors, rendered CocoaPods metadata, pod/source lists, and text-preview coexistence.

## 2026-07-19: deno.lock artifacts render bounded Deno dependency summaries

- **Decision:** Local `deno.lock` artifacts render as structured Deno lockfile cards. The preview
  shows lockfile version, remote module/npm/jsr package/specifier/redirect counts, file size, capped
  package labels, and capped source hosts. `deno.lock` is classified as a data artifact through
  filename-specific detection.
- **Why:** Deno projects often produce lockfiles containing remote modules plus npm/jsr package state;
  compact summaries make these outputs scannable without dumping full hashes or URL maps.
- **Boundary:** The parser is local-file-only, regular-file-only, NUL-rejecting, filename-gated to
  `deno.lock`, and capped at 512 KB. It reads only shallow top-level `version`, `remote`, `npm`,
  `jsr`, `specifiers`, and `redirects`; it never expands import graphs, validates integrity or
  hashes, reads manifests, contacts registries, or fetches remote modules/packages.
- **Evidence:** `QuillCodeToolCardSurfaceTests.testArtifactStateDerivesDenoLockPreviewMetadata`
  covers filename-based document classification, lockfile version, remote/npm/jsr/specifier/redirect
  counts, package labels, source hosts, non-`deno.lock` exclusion, and remote exclusion.
  `WorkspaceHTMLToolCardRendererTests.testHTMLRendererIncludesDenoLockArtifactPreview` covers static
  HTML selectors, rendered Deno metadata, package/source lists, generic JSON suppression, and
  text-preview coexistence.

## 2026-07-19: Bun lockfile artifacts render bounded dependency summaries

- **Decision:** Local text `bun.lock` and binary `bun.lockb` artifacts render as structured Bun
  lockfile cards. Text lockfiles show lockfile version, workspace/package/dependency/catalog counts,
  file size, capped package labels, and capped source hosts. Binary lockfiles show format and size
  only.
- **Why:** Bun 1.2+ writes text `bun.lock` by default, while older projects may still carry
  `bun.lockb`. Both are common coding-agent dependency artifacts, and users need to distinguish
  dependency impact from opaque binary lockfile presence without running project tooling.
- **Boundary:** The parser is local-file-only, regular-file-only, filename-gated to `bun.lock` or
  `bun.lockb`, and capped at 512 KB. Text `bun.lock` accepts bounded JSONC comments/trailing commas
  and reads only shallow `lockfileVersion`, `workspaces`, `packages`, `catalog`, and `catalogs`
  fields. Binary `bun.lockb` is not decoded or converted. The preview never runs Bun, expands
  package graphs, validates integrity values, reads package manifests, contacts registries, or
  fetches package tarballs.
- **Evidence:** `QuillCodeToolCardSurfaceTests.testArtifactStateDerivesBunLockfilePreviewMetadata`
  covers text JSONC parsing, filename-based document classification, workspace/package/dependency/
  catalog counts, package labels, source hosts, non-`bun.lock` exclusion, and remote exclusion.
  `QuillCodeToolCardSurfaceTests.testArtifactStateDerivesBinaryBunLockfilePreviewMetadataWithoutDecoding`
  covers binary `bun.lockb` classification without text/JSON decoding.
  `WorkspaceHTMLToolCardRendererTests.testHTMLRendererIncludesBunLockfileArtifactPreview` covers
  static HTML selectors, rendered Bun metadata, package/source lists, generic JSON suppression, and
  text-preview coexistence.

## 2026-07-19: BenchmarkDotNet JSON artifacts render bounded benchmark summaries

- **Decision:** Local `.json` artifacts with BenchmarkDotNet-compatible `Benchmarks` and
  `HostEnvironmentInfo` report shape render as structured BenchmarkDotNet report cards instead of
  generic JSON. The preview shows report title, benchmark count, runtime, architecture, operating
  system, file size, and capped benchmark labels.
- **Why:** .NET performance work commonly emits BenchmarkDotNet JSON. A Codex-style artifact surface
  should make benchmark artifacts scannable in the transcript without requiring the user or model to
  open raw JSON.
- **Boundary:** The parser is local-file-only, regular-file-only, NUL-rejecting, JSON-only, and
  capped at 512 KB. It reads only shallow report metadata and benchmark labels; it never executes
  benchmarks, interprets statistics as authoritative performance claims, opens referenced source
  files, reads generated logs, loads benchmark assemblies, or fetches remote reports.
- **Evidence:** `QuillCodeToolCardSurfaceTests.testArtifactStateDerivesBenchmarkDotNetJSONPreviewMetadata`
  covers BenchmarkDotNet shape detection, report metadata, benchmark labels, generic JSON
  suppression, empty-report exclusion, and remote exclusion.
  `WorkspaceHTMLToolCardRendererTests.testHTMLRendererIncludesBenchmarkDotNetJSONArtifactPreview`
  covers static HTML selectors, rendered metadata, benchmark lists, and generic JSON suppression.

## 2026-07-19: Hyperfine JSON artifacts render bounded benchmark summaries

- **Decision:** Local `.json` artifacts with Hyperfine-compatible top-level `results` entries render
  as structured Hyperfine report cards instead of generic JSON. The preview shows command count, the
  fastest command and mean duration when present, file size, and capped command labels.
- **Why:** Hyperfine is a common CLI benchmarking tool for coding-agent performance checks. A compact
  report card keeps benchmark artifacts scannable next to shell/file tool output without requiring
  raw JSON inspection.
- **Boundary:** The parser is local-file-only, regular-file-only, NUL-rejecting, JSON-only, and capped
  at 512 KB. It reads only shallow result command and timing fields; it never executes commands,
  re-runs benchmarks, treats measurements as independently verified claims, expands parameterized
  commands, reads scripts, opens source files, or fetches remote reports.
- **Evidence:** `QuillCodeToolCardSurfaceTests.testArtifactStateDerivesHyperfineJSONPreviewMetadata`
  covers Hyperfine shape detection, command count, fastest command/mean rendering, generic JSON
  suppression, incomplete-result exclusion, and remote exclusion.
  `WorkspaceHTMLToolCardRendererTests.testHTMLRendererIncludesHyperfineJSONArtifactPreview` covers
  static HTML selectors, rendered metadata, command lists, and generic JSON suppression.

## 2026-07-19: npm audit JSON artifacts render bounded security summaries

- **Decision:** Local `.json` artifacts with npm audit-compatible `auditReportVersion`, `metadata`,
  and `vulnerabilities`/`advisories` entries render as structured npm audit cards instead of generic
  JSON. The preview shows total vulnerability count, severity counts, dependency count, file size,
  and capped vulnerable package labels.
- **Why:** `npm audit --json` is common coding-agent output during dependency cleanup. A compact
  summary lets users triage the artifact beside tool output without expanding raw JSON.
- **Boundary:** The parser is local-file-only, regular-file-only, NUL-rejecting, JSON-only, and capped
  at 512 KB. It reads only shallow metadata, severity counts, and package labels; it never reads
  package files, expands advisory details, opens lockfiles, follows dependency paths, verifies
  exploitability, or fetches remote advisories.
- **Evidence:** `QuillCodeToolCardSurfaceTests.testArtifactStateDerivesNPMAuditJSONPreviewMetadata`
  covers npm audit shape detection, severity/dependency/package metadata, generic JSON suppression,
  incomplete-report exclusion, and remote exclusion.
  `WorkspaceHTMLToolCardRendererTests.testHTMLRendererIncludesNPMAuditJSONArtifactPreview` covers
  static HTML selectors, rendered metadata, package lists, and generic JSON suppression.

## 2026-07-19: cargo audit JSON artifacts render bounded Rust security summaries

- **Decision:** Local `.json` artifacts with `cargo audit --json`-compatible `vulnerabilities`
  reports render as structured cargo audit cards instead of generic JSON. The preview shows
  vulnerability count, yanked/unmaintained warning counts, file size, capped package labels, and
  capped RustSec advisory labels.
- **Why:** Rust dependency security work commonly produces `cargo audit --json` output. A compact
  artifact card lets users triage RustSec findings next to command output without opening raw JSON
  or rerunning cargo tooling.
- **Boundary:** The parser is local-file-only, regular-file-only, NUL-rejecting, JSON-only, and
  capped at 512 KB. It reads only shallow vulnerability, package, warning, and advisory labels; it
  never opens `Cargo.lock`, expands dependency graphs, verifies exploitability, downloads the RustSec
  database, follows advisory URLs, or fetches remote reports.
- **Evidence:** `QuillCodeToolCardSurfaceTests.testArtifactStateDerivesCargoAuditJSONPreviewMetadata`
  covers cargo audit shape detection, vulnerability/warning/package/advisory metadata, generic JSON
  suppression, incomplete-report exclusion, and remote exclusion.
  `WorkspaceHTMLToolCardRendererTests.testHTMLRendererIncludesCargoAuditJSONArtifactPreview` covers
  static HTML selectors, rendered metadata, package/advisory lists, and generic JSON suppression.

## 2026-07-19: pip-audit JSON artifacts render bounded Python security summaries

- **Decision:** Local `.json` artifacts with `pip-audit --format json`-compatible dependency entries
  render as structured pip-audit cards instead of generic JSON. The preview shows dependency count,
  vulnerable package count, vulnerability count, fixable vulnerability count, file size, capped
  package labels, and capped vulnerability labels with aliases/fix versions when available.
- **Why:** Python dependency security cleanup commonly emits pip-audit JSON. A Codex-style artifact
  surface should make those findings scannable beside command output without requiring raw JSON
  expansion or another tool run.
- **Boundary:** The parser is local-file-only, regular-file-only, NUL-rejecting, JSON-only, and
  capped at 512 KB. It reads only shallow `dependencies`, `name`, `version`, `vulns`, `id`,
  `aliases`, and `fix_versions` fields; it never imports Python packages, opens requirements or lock
  files, resolves dependency graphs, verifies exploitability, contacts vulnerability services, or
  fetches remote reports.
- **Evidence:** `QuillCodeToolCardSurfaceTests.testArtifactStateDerivesPipAuditJSONPreviewMetadata`
  covers pip-audit shape detection, dependency/package/vulnerability/fix metadata, generic JSON
  suppression, incomplete-report exclusion, and remote exclusion.
  `WorkspaceHTMLToolCardRendererTests.testHTMLRendererIncludesPipAuditJSONArtifactPreview` covers
  static HTML selectors, rendered metadata, package/vulnerability lists, and generic JSON
  suppression.

## 2026-07-27: packaged browser coworker smoke is a release artifact

- **Decision:** Packaged macOS smoke writes `packaged-browser-workflow.json` beside the existing
  packaged click-probe, Accessibility, scheduled-coworker, and multi-file artifact manifests. The
  validator reads the direct packaged executable and Launch Services reports, then compares semantic
  CRM-like and shared-sheet-like browser workflow evidence.
- **Why:** Office coworker tasks depend heavily on browser/SaaS surfaces. Burying browser workflow
  proof inside two `report.json` files made release review too easy to miss and let packaged launch
  drift hide behind passing native smoke. A first-class manifest makes the release boundary explicit.
- **Boundary:** The smoke still uses deterministic local HTML pages, not a signed-in live SaaS
  account. It proves `host.browser.type`, `host.browser.click`, `host.browser.script`, and
  `host.browser.inspect` keep canonical arguments and live-DOM edited state through packaging. Real
  SaaS rows remain gated until a signed-in browser/Computer Use smoke proves the same workflow.
- **Evidence:** `scripts/native_click_probe_contracts/browser_workflow.py` validates both
  `browserWorkflowSmoke` and `browserSpreadsheetWorkflowSmoke`.
  `scripts/packaged-macos-smoke.sh` writes and preserves `packaged-browser-workflow.json`.
  `ParityPackagedMacOSSmokeGateTests` requires the validator, manifest, and CLI wiring.

## 2026-07-27: packaged Computer Use setup evidence is explicit

- **Decision:** Packaged macOS smoke writes `packaged-computer-use.json` after the live-window
  Accessibility frame manifest. The validator records recognized direct executable and Launch
  Services Computer Use top-bar statuses, requires the packaged window surface to expose Computer Use
  setup, Screen Recording settings, Accessibility settings, and refresh commands, and verifies those
  command contracts are present in the packaged click-probe and Accessibility frame manifests.
- **Why:** Computer Use is a major Codex parity surface and a prerequisite for browser/SaaS coworker
  tasks. Before claiming live app control, release artifacts should at least make the setup/status
  entry points explicit and fail when packaging hides or deroutes them.
- **Boundary:** This is not a real-app-control smoke. It proves setup/status/permission command
  availability and command-contract coverage at the package boundary. Direct executable and Launch
  Services status labels may differ because macOS Screen Recording and Accessibility permissions are
  app-identity-specific. Future work must still add a live Computer Use action smoke against a
  controlled app or signed-in SaaS surface.
- **Evidence:** `scripts/native_click_probe_contracts/computer_use.py`,
  `scripts/packaged-macos-smoke.sh`, `QuillCodeDesktopWindowSmokeSurfaceReport.requiredCommandIDs`,
  and `ParityPackagedMacOSSmokeGateTests`.

## 2026-07-27: packaged Computer Use action evidence is explicit

- **Decision:** Desktop native smoke now runs a deterministic Computer Use action sequence through
  the real `ComputerUseToolExecutor`, and packaged macOS smoke preserves the result as
  `packaged-computer-use-action.json`. The action smoke dispatches `host.computer.screenshot`,
  `host.computer.click`, `host.computer.type`, `host.computer.scroll`, `host.computer.move`, and
  `host.computer.key` with canonical non-empty arguments, records the backend action sequence, and
  requires screenshot artifact, foreground-app, and accessibility-summary evidence.
- **Why:** Setup/status evidence alone can pass while the actual action path is broken. Office
  coworker tasks that depend on QuillCode controlling another app need a release artifact proving
  packaged action dispatch still routes through the same executor as agent turns.
- **Boundary:** This is deterministic backend evidence, not a signed-in SaaS or arbitrary-app smoke.
  The validator compares semantic direct executable and Launch Services evidence while allowing
  temporary screenshot paths to differ. Real SaaS rows remain gated until the same action path drives
  a signed-in browser/app surface.
- **Evidence:** `QuillCodeDesktopSmokeRunner.runComputerUseActionSmoke`,
  `QuillCodeDesktopComputerUseActionSmokeReport`,
  `scripts/native_click_probe_contracts/computer_use_action.py`,
  `scripts/packaged-macos-smoke.sh`, and `ParityPackagedMacOSSmokeGateTests`.

## 2026-07-27: browser workflow smoke includes authenticated session state

- **Decision:** The packaged browser workflow manifest now validates
  `browserAuthenticatedWorkflowSmoke` in addition to the CRM-like and shared-sheet-like workflows.
  The authenticated smoke opens a login-like workspace page, types a workspace key, clicks Sign in,
  and requires both script output and live DOM inspection to preserve `signed-in=true` plus the
  selected workspace.
- **Why:** Browser/SaaS coworker tasks often depend on being signed in, not just typing into a form.
  Before using fragile external SaaS credentials in CI, QuillCode should at least prove that its
  visible browser-session tool path can carry authenticated-session state through packaged direct and
  Launch Services entrypoints.
- **Boundary:** The page is deterministic local HTML presented through the same visible-session tool
  override path, not a live external SaaS account. Real SaaS rows remain gated until a signed-in
  live SaaS smoke proves equivalent behavior on an actual service.
- **Evidence:** `QuillCodeDesktopSmokeRunner.runBrowserAuthenticatedWorkflowSmoke`,
  `SmokeBrowserSessionPresenter`, `scripts/native_click_probe_contracts/browser_workflow.py`,
  `scripts/packaged-macos-smoke.sh`, and `ParityPackagedMacOSSmokeGateTests`.

## 2026-07-27: live SaaS coworker rows use an explicit optional evidence contract

- **Decision:** Real signed-in SaaS coworker validation now has a separate optional gate:
  `scripts/live-saas-smoke.sh` delegates to `native-click-probe-contracts.py live-saas`, validates a
  captured live SaaS evidence JSON file, and writes a `live-saas-manifest.json` only when the evidence
  proves signed-in state, HTTPS URL, live DOM inspection, and real browser/Computer Use action tools.
- **Why:** The deterministic packaged smoke should stay stable and should not require private
  Salesforce, HubSpot, Google Sheets, or other third-party credentials. At the same time, the coworker
  spreadsheet needs a concrete acceptance artifact before a live SaaS row can move from "gated" to
  "covered". A typed validator gives manual/secure-environment SaaS runs the same reviewable manifest
  shape as packaged smoke.
- **Boundary:** This is not run in default CI and does not itself prove any external service works.
  It is the acceptance contract for evidence captured from a real signed-in service. Rows remain gated
  until such a manifest is produced for the relevant service/task.
- **Safety:** The validator rejects common captured secrets, including TrustedRouter/QuillCloud keys,
  private keys, and obvious password/token/secret fields, before writing the manifest.
- **Evidence:** `scripts/native_click_probe_contracts/live_saas.py`,
  `scripts/native_click_probe_contracts/cli.py`, `scripts/live-saas-smoke.sh`, and
  `ParityLiveSaaSSmokeGateTests`.

## 2026-07-27: live local-app Computer Use rows use an explicit optional evidence contract

- **Decision:** Arbitrary foreground-app coworker validation has a separate optional gate:
  `scripts/live-app-computer-use-smoke.sh` delegates to
  `native-click-probe-contracts.py live-app-computer-use`, validates a captured local-app evidence
  JSON file, and writes `live-app-computer-use-manifest.json` only when the evidence proves exact
  spreadsheet row IDs, matching app/foreground names, screenshot plus a real Computer Use action,
  visible before/after state change, completed result evidence, and an existing screenshot/appshot
  artifact.
- **Why:** Packaged Computer Use action smoke proves executor routing, but office coworker rows often
  depend on private desktop apps or signed-in native tools that default CI cannot open. A typed
  optional contract lets secure/manual captures graduate exact spreadsheet rows without conflating
  deterministic backend proof with real local-app task completion.
- **Boundary:** This is not run in default CI and does not itself prove arbitrary app parity. It is
  the acceptance contract for evidence captured from a real foreground app. Rows remain gated until
  such a manifest exists for the relevant task.
- **Safety:** The validator rejects raw prompts/messages and common captured secrets, including
  TrustedRouter/QuillCloud keys, private keys, and obvious password/token/secret fields, before
  writing the manifest.
- **Evidence:** `scripts/native_click_probe_contracts/live_app_computer_use.py`,
  `scripts/native_click_probe_contracts/live_app_computer_use_template.py`,
  `scripts/live-app-computer-use-smoke.sh`, `scripts/live-app-computer-use-template.sh`, and
  `ParityLiveAppComputerUseSmokeGateTests`.

## 2026-08-07: published downloads are verified as a public consumer

- **Decision:** Every non-skipped **Download Builds** run has a read-only post-publish job that
  resolves the release tag, validates the release/manifest/updater contract, downloads every public
  asset with strict aggregate and per-file bounds, and checks GitHub API digests, manifest digests,
  `SHASUMS256.txt`, and `BUILD_INFO.txt`. Stable manifests identify the same moving
  `releases/latest` feed embedded in stable apps; tester manifests identify `tester-latest`.
- **Why:** Pre-upload package checks cannot prove that GitHub serves a coherent public release. The
  previous stable manifest also reported its immutable tag URL while the app embedded the moving
  stable URL, causing the updater's exact-feed defense to reject a legitimate stable manifest.
- **Recovery:** Scheduled deduplication skips only when the tester manifest is structurally valid and
  its exact **Download Builds** run completed successfully on the same commit. Failed, partial, or
  mismatched publications are rebuilt instead of becoming a permanently skipped state.
- **Evidence:** `scripts/verify-published-release.py`, `scripts/release_verification_contract.py`,
  `scripts/release_verification_files.py`, `scripts/build-download-manifest.py`,
  `scripts/plan-download-build.sh`, `.github/workflows/download-builds.yml`,
  `ParityPublishedReleaseVerificationGateTests`, `ParityDownloadBuildPlanGateTests`, and
  `ParityDownloadBuildsGateTests`.

## 2026-08-07: automatic update scheduling survives long-running app sessions

- **Decision:** The desktop updater owns one weakly captured automatic scheduler separately from its
  foreground check/download/install task. The scheduler remains active for the app lifetime, checks
  the persisted successful-check timestamp at every wake, and uses channel cadence plus bounded
  failure and visible-UI deferrals. Foreground commands cannot cancel or overwrite an active update,
  and activation is non-cancellable after the helper boundary.
- **Why:** A one-shot launch check misses updates when Quill Cowork remains open for days. Sharing that
  task with menu checks also allowed a repeated command to cancel a download or strand an activation
  attempt. Re-reading the due time prevents a successful manual check from being followed by a
  duplicate scheduled request.
- **Memory and UX:** The sleeping task does not retain the controller between checks. Background
  failures remain quiet, visible failures preserve bounded scrollable diagnostics, and failures tied
  to a known release offer a direct retry without discarding the browser-download fallback.
- **Evidence:** `QuillCodeDesktopUpdateSchedule`, `QuillCodeDesktopUpdateController`,
  `QuillCodeDesktopUpdateView`, and `QuillCodeDesktopUpdateControllerTests` cover repeated in-session
  checks, retry backoff, manual rescheduling, visible-state deferral, task deallocation, reentrant menu
  commands, and non-cancellable activation.

## 2026-08-07: downloads wait for successful exact-main CI before packaging

- **Decision:** The **Download Builds** release-policy job validates its ref, then waits up to 30
  minutes for a successful `CI` workflow run with the exact requested commit, `main` as its head
  branch, and a `push` or `workflow_dispatch` event before planning or packaging any release.
- **Why:** Merge-train dispatches CI and downloads independently. Build 629 demonstrated that
  packaging and publication could finish while exact-main CI was still running and temporarily red,
  even though branch CI and the eventual rerun were green. Public updater state must never outrun the
  authoritative main test result.
- **Failure behavior:** Missing, active, failed, cancelled, or mismatched runs remain non-authorizing.
  The bounded gate reports state changes without log spam and fails closed at timeout; a later green
  CI result requires a new or rerun Download Builds attempt.
- **Evidence:** `scripts/wait-for-successful-ci.sh`, `.github/workflows/download-builds.yml`,
  `ParityDownloadBuildCIGateTests`, and `ParityDownloadBuildsGateTests`.

## 2026-08-07: published macOS builds carry native performance evidence

- **Decision:** The packaged live-window smoke captures app-entry-to-window-ready time, resident
  memory, and thread count directly from the native process before screenshot and
  Accessibility sampling. Default release budgets are three seconds and 256 MiB resident memory.
- **Why:** Functional smoke alone cannot protect Quill Cowork's native speed and memory advantage.
  Measuring the release-configured `.app` makes large startup or footprint regressions fail before
  publication and gives future optimization work a durable baseline rather than anecdotes.
- **Boundary:** This is an initial empty-workspace measurement, not a claim about long-running peak
  memory or arbitrary project sizes. The first budgets retain broad headroom across GitHub macOS
  runners; daily-driving and workload evidence should tighten them without making CI hardware noise
  the product metric.
- **Evidence:** `QuillCodeDesktopPerformanceSnapshot`, the window-smoke performance object,
  `scripts/native_click_probe_contracts/performance.py`, `scripts/packaged-macos-performance-smoke.sh`,
  packaged smoke artifacts, and the public architecture-specific `PERFORMANCE.json` release asset.

## 2026-08-07: human installation uses a verified disk image

- **Decision:** macOS releases publish a compressed read-only DMG containing the already signed
  `Quill Cowork.app` and a standard `/Applications` shortcut. Packaging mounts the completed image,
  validates both entries, and verifies the embedded app signature before upload.
- **Updater boundary:** The DMG is the recommended human installation artifact. The ZIP remains the
  updater's declared `macOSAppAsset`, preserving the existing bounded download, SHA-256, extraction,
  staged-swap, launch-handshake, and rollback contract.
- **Why:** A drag-to-Applications image gives testers the normal macOS install flow without coupling
  installer presentation to the security-critical updater archive or weakening stable signing and
  notarization requirements.
- **Evidence:** `scripts/create-macos-disk-image.sh`, macOS download packaging, manifest
  classification, public download docs, and `ParityDownloadBuildsGateTests`.

## 2026-08-07: release performance uses a majority of fresh processes

- **Decision:** macOS release packaging runs three independent live-window measurements with
  isolated state roots. At least two launches must remain within the three-second budget, every
  resident-memory sample must remain within 256 MiB, and the median attempt is the headline value.
- **Why:** Builds 638 and 639 showed 3.1-3.3 second first samples immediately after 6-8 minutes of
  compiler saturation while the same optimized app repeatedly measured 229-339 ms on physical
  hardware. One hosted sample was not a stable product metric, but raising the budget would hide a
  real regression. A majority gate keeps the limit and fails sustained regressions closed.
- **Evidence:** The public performance manifest records every attempt, pass counts, aggregation,
  the selected median-launch attempt, and budgets; `ParityPackagedPerformanceGateTests` covers
  passing and failing majorities.

## 2026-08-07: packaged source provenance is end-to-end verified

- **Decision:** Every packaged macOS app embeds its exact lowercase 40-character Git commit in
  `QuillCodeBuildCommit`. Public release verification requires the updater ZIP's bounded
  `Info.plist` identity, version, build, commit, update channel, feed URLs, minimum system version,
  and optional signing team to agree with the public manifest.
- **Updater boundary:** The downloaded-app validator and detached activation helper both require the
  incoming app's embedded commit to equal the selected release. The currently installed app is not
  required to carry the new key, preserving upgrades from earlier tester builds while preventing a
  manifest and replacement app from naming different source revisions.
- **Support boundary:** **Report an Issue...** opens the public GitHub issue form with only bounded
  version, build, commit, channel, macOS, and architecture metadata. It does not collect logs,
  transcripts, project paths, or credentials.
- **Evidence:** `build-macos-app.sh`, `package-macos-downloads.sh`, packaged smoke,
  `release_verification_files.py`, `QuillCodeDesktopDownloadedApplicationValidator`,
  `QuillCodeDesktopUpdateHelper`, `QuillCodeDesktopIssueReporter`, and their focused parity and unit
  tests.
## 2026-08-05: file-mention indexing never blocks desktop startup or project switching

- **Decision:** `QuillCodeWorkspaceModel` builds file-mention indexes in a cancellable detached
  utility task. Each refresh carries a generation and standardized active-root check, and only the
  latest matching result may update the model. Cancellation is forwarded to the detached scan, and
  the indexer checks it during enumeration. The desktop controller refreshes its rendered surface
  when that asynchronous result arrives.
- **Why:** A normally signed-in app stalled before its first window while the main actor enumerated
  the persisted selected project. Directory enumeration is filesystem I/O; fast local-repository
  timings do not make synchronous startup scans safe.
- **Boundary:** Mention suggestions can be briefly empty after launch or a project switch. Agent work,
  project selection, and the rest of the desktop UI remain immediately available while indexing runs.
- **Evidence:** `WorkspaceFileMentionIntegrationTests/testSlowFileMentionIndexingDoesNotBlockTheMainActor`,
  `WorkspaceFileIndexerTests/testIndexingThePackageWorkspaceCompletesPromptly`, and the packaged plus
  normally launched app UI smokes.

## 2026-08-05: automatic project-context freshness runs after first-window initialization

- **Decision:** Workspace bootstrap restores persisted project metadata but does not rescan the
  selected project before returning its model. The desktop controller schedules fresh local project
  metadata in a cancellable detached utility task after publishing initial state. Only the latest
  generation for the still-selected project and standardized root may apply its result, persist it,
  synchronize non-confidential thread context, and refresh the rendered surface.
- **Why:** Sampling the signed-in process after file-mention indexing moved off the main actor exposed
  a second startup traversal in `ProjectInstructionLoader`. Bounded directory counts do not bound
  filesystem latency, so automatic freshness cannot be a prerequisite for creating the first window.
- **Boundary:** Restored context may remain visible briefly while freshness loads. Explicit Refresh
  Project Context keeps its synchronous completion contract, and remote SSH refresh behavior is
  unchanged. The automatic loader observes cancellation; a blocking operating-system filesystem call
  may still return only when the OS releases it, but its stale result cannot mutate current state.
- **Evidence:**
  `WorkspaceProjectIntegrationTests/testScheduledProjectContextRefreshDoesNotBlockTheMainActor`,
  `WorkspaceProjectIntegrationTests/testScheduledProjectContextRefreshDropsAStaleSelectionResult`,
  `ParityWorkspaceProjectGateTests/testWorkspaceModelDelegatesProjectMetadataLoading`, process stack
  sampling of the original stall, and the normally launched signed-in desktop UI smoke.

## 2026-08-06: cheap cross-domain live evals use bounded objective evidence

- **Decision:** QuillCode keeps a versioned 12-case synthetic eval catalog and runner for
  cybersecurity, biology, AI, evaluator robustness, and short multi-file agent tasks. Live runs pin
  the task model to `deepseek/deepseek-v4-flash-0731`, default to two trials, and refuse more than 24
  paid invocations.
- **Why:** A small pass/fail smoke proves transport but does not measure reliable task completion.
  Reproducible exact-file, exact-JSON, protected-input, and executable-test graders provide a useful
  score without paying for a large benchmark or relying on an LLM judge.
- **Boundary:** Results are QuillCode catalog scores, not reproduced vendor benchmark claims.
  Cybersecurity data is inert and defensive; biology data is synthetic and non-clinical. Production
  tool-safety review stays enabled and is separate from the pinned task-model route.
- **Safety:** Each case uses an isolated workspace and ephemeral home. The API key is supplied only
  through the child environment, never command arguments or manifests. Stored output is redacted and
  the entire artifact tree is scanned before the run can pass.
- **Evidence:** `docs/cheap-agentic-eval-catalog.json`, `scripts/cheap-agentic-evals.py`,
  `Tests/Fixtures/CheapAgenticEvals/mixed-domain.json`, and
  `ParityCheapAgenticEvalsGateTests`.

## 2026-08-06: TAU3 banking and BFCL stay bounded compatibility contracts

- **Decision:** QuillCode keeps six synthetic stateful banking cases and eight function-calling cases
  as objective compatibility fixtures. Live runs require the exact
  `deepseek/deepseek-v4-flash-0731` task model and derive a hard paid-invocation fuse from the selected
  cases, capped at 24 for the complete catalog.
- **Why:** Stateful verification and mutation flows catch agent-continuation failures that isolated
  tool parsing misses. Exact simple, multiple, parallel, nested, array, and no-tool graders catch
  function-selection and argument regressions without an LLM judge.
- **Boundary:** These fixtures track relevant TAU3 banking and BFCL contracts but do not run the full
  upstream harnesses and must never be reported as official benchmark scores. Banking identities,
  accounts, and transactions are synthetic and remain in memory.
- **Safety:** The TrustedRouter key is loaded from environment or a private local key file, is never a
  command-line value, and is redacted from the artifact tree before success. Catalog validation,
  offline self-tests, exact-model enforcement, per-case step ceilings, and the aggregate invocation
  fuse run before or during any paid execution.
- **Evidence:** `docs/tau3-banking-eval-catalog.json`, `docs/bfcl-eval-catalog.json`,
  `scripts/benchmark-compat-evals.py`, `BenchmarkCompatibilityActionParserTests`, and
  `ParityBenchmarkCompatibilityEvalsTests`. The 2026-08-07 exact-model live run passed TAU3 banking
  6/6 and BFCL 8/8 with all 24 bounded paid invocations successful; the redacted local manifest is
  `.build/quillcode-validation/benchmark-compat/live-r1/manifest.json`.

## 2026-08-11: tester publication retries are idempotent and state-probed

- **Incident:** Tester build 729 packaged successfully on every platform, but its first publish job
  received `release not found` while uploading a candidate and then a transient GitHub API TLS
  certificate error while checking rollback. The transaction preserved the complete prior public
  build, and a failed-job retry published and verified 729 successfully.
- **Decision:** Read-only and idempotent GitHub publication operations retry only recognized TLS,
  DNS, connection, timeout, rate-limit, and 5xx failures, using five attempts and capped exponential
  backoff. Permanent policy, validation, and malformed-response failures remain immediate.
- **Upload boundary:** A candidate upload never retries blindly after an ambiguous response. The
  publisher first reads the live release and accepts the operation only when the exact transaction
  alias exists in uploaded state with the expected byte count and SHA-256 digest. Conflicting remote
  content fails closed into the existing verified rollback. A temporary `release not found` result
  retries only when that probe independently confirms the canonical release still exists.
- **Cleanup boundary:** Asset deletion is idempotent. A retry that observes the asset already absent
  treats the original deletion as complete, preventing a lost success response from turning a
  correct committed release into a false failure.
- **Evidence:** `tester_publication/remote.py`, `publisher.py`, `initial.py`, and
  `ParityTransactionalTesterPublicationTests` cover transient reads, pre- and post-mutation upload
  failures, conflicting bytes, bounded exhaustion, PATCH/tag retries, deletion response loss,
  permanent failures, exact rollback, and tag-last success ordering.

## 2026-08-11: stable candidates prove native updates before promotion

- **Decision:** A versioned stable release remains a non-latest prerelease candidate through public
  asset verification and updater/relaunch smoke on native arm64 and Intel runners. Promotion to
  latest stable requires both updater matrix entries to pass.
- **Why:** Promoting before updater validation briefly exposed an unproven release through
  `releases/latest` and the moving stable feed. Drafting it after a failure restored the prior feed,
  but could not eliminate that avoidable exposure window.
- **Recovery boundary:** Candidate verification or updater failure returns only the new candidate to
  draft while the previous stable release and feed remain untouched. Post-promotion verification is
  now limited to proving GitHub's latest-release and moving-feed views; a failure still drafts the
  new release so GitHub falls back to the previous stable version.
- **Evidence:** `download-builds.yml`, `ParityDownloadBuildsGateTests`,
  `ParityPackagedUpdaterGateTests`, and the stable publication contract in `docs/DOWNLOADS.md`.
