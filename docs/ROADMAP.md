# Roadmap

## Milestone 0: Compile-Stable Foundation

- SwiftPM package, docs, CI skeleton.
- Core models, mock agent, shell/file/git tools.
- Auto safety policy and reviewer protocol.
- Persistence and secret-store API.
- Unit tests for direct command execution and safety behavior.
- Current status: shell, file read/write, apply patch, git status/diff, file/hunk-level git stage/restore, local git commit, named-remote git push, GitHub PR creation, and git worktree list/create/remove are implemented with unit coverage.

## Milestone 1: Native Workspace UI

- QuillUI shell with sidebar, top bar, composer, transcript, and tool cards.
- Project picker and model picker.
- Settings with OAuth/dev override and mode selection.
- Native smoke tests.
- Current status: testable workspace state model, persisted config/thread/project bootstrap, bounded broad-to-specific project instruction loading from root and nested `AGENTS.md`/`.quillcode` rules, bounded memory loading from `~/.quillcode/memories` and project `.quillcode/memories`, explicit `/remember text` global memory writes and Memories-pane Forget action with basic credential rejection, bounded project-local extension manifest discovery for plugins, skills, and MCP servers, explicit MCP stdio server start/stop lifecycle controls with bounded `initialize`/`tools/list` readiness probes, generic allowlisted MCP `tools/call` routing for Ready servers, HTML surface contract, Playwright harness, smoke script, and SwiftUI desktop shell exist for project rail, visible New chat/Search/Open project/Browser/Terminal/Memories/Extensions/Activity sidebar actions, desktop folder picking, project row actions for New chat/Refresh context/Rename/Remove from list, thread rename/duplicate/pin/archive/unarchive/delete controls, bulk chat select/select-all/pin/unpin/archive/unarchive/delete controls, pinned/recent/archived chat grouping, thread search that excludes hidden tool-feedback state, active-chat `Cmd+F` transcript Find, grouped/ranked command palette with keyboard navigation, registry-backed primary keyboard shortcuts, command-derived `Cmd+/` Keyboard Shortcuts discoverability, local environment action commands from `.quillcode/actions` and `.quillcode/local-env`, browser preview state/comments/snapshots with bounded HTTP(S) HTML fetch upgrades, explicit inspection-depth labels, and structured browser inspection, composer with shared-catalog keyboard-navigable slash suggestions and active-run Stop, in-app top bar with instruction and memory context status, native macOS menu-bar widget, derived right-side Activity pane for deterministic or model-authored task-plan/current-task/source/tool/artifact/latest-answer/handoff state with command-driven collapsible sections, chronological event-driven transcript, transcript copy actions with visible copied feedback, user-message Use as draft, assistant response feedback actions backed by thread events, latest-assistant Retry action over the shared retry command, estimated context pressure banner with Compact context/New thread/Fork from last actions, deterministic compact-context continuation threads, incremental agent-run progress, bounded multi-step agent tool continuation, tool-card presentation with human final-answer bubbles, stopped-tool cleanup, artifact preview chips plus bounded image previews, and collapsed raw details for successful tools, integrated workspace terminal command history with live stdout/stderr streaming, persistent per-project cwd and environment deltas, running/done/failed/stopped lifecycle, and Stop controls, git diff review summaries with post-patch refresh, file/hunk Stage/Restore controls, and file-scoped review notes, git worktree command-palette actions, create/remove dialogs, and create-time worktree project/thread handoff, slash commands for core workspace actions, project management, memory visibility/writing/forgetting, context compaction, thread lifecycle, and local environment scripts, searchable grouped model selection with persistent favorites, recent-model surfacing, current/default/recommended/favorite badges, deterministic model metadata rows, inline model detail browsing, mode switching, and native developer settings. The desktop app seeds the current working directory as the initial project and runs tools from the selected project path.

## Milestone 2: TrustedRouter Runtime

- OAuth PKCE and delegated key storage.
- Streaming chat client.
- Live model catalog native UI.
- Auto reviewer using `glm-5.2` with `kimi-k2.6` fallback in the native app.
- Current status: live TrustedRouter adapter exists behind CLI `--live`; desktop env/secret-key runtime selection, OAuth-first auth mode state, native loopback PKCE sign-in, pure authorize/exchange/userinfo OAuth client, automatic delegated key storage, non-secret signed-in account display, secondary developer key/base-URL settings, live model-catalog refresh, CLI key-management commands, incremental agent progress callbacks, bounded multi-step tool continuation, streamed action-text transport, visible Streaming status, safe streamed assistant drafts for `say` actions, shared actionable runtime issue UI for sign-in/key/rate-limit/network/empty-response/malformed-action failures, Retry-last-turn recovery from transient runtime failures, malformed-response and rate-limit recovery through the searchable model picker, and redacted runtime diagnostics with parsed rate-limit metadata in Settings are implemented. Account recovery telemetry and provider status diagnostics beyond local runtime state remain the next runtime polish.

## Milestone 3: Codex Workflow Parity

- Full PTY terminal sessions with job control and TUI handling, richer worktree branch lifecycle polish, local env orchestration, and richer GitHub review workflows.
- Per-file project-instruction scopes and visible conflict diagnostics.
- Browser rendering adapter, live DOM/page inspection for dynamic pages, and richer browser comments.
- Computer Use platform backends, app approvals, and agent wiring. macOS now has permission-aware status, screenshot/input primitives, Settings onboarding actions, and structured agent tools for screenshot/click/type/scroll/move/key dispatch through the active backend; Linux backend, richer onboarding, and multi-step model feedback over screenshot results remain.
- Richer non-image artifact previews, plugin/skill install and execution lifecycle, richer MCP per-tool schemas, resource reads, prompt execution, and streaming beyond the generic verified-server call path. MCP resource/prompt discovery is surfaced today so richer consumption can build on a tested UI contract. Autonomous memory writes/richer redaction/Chronicle jobs, memory editing, and automations.
