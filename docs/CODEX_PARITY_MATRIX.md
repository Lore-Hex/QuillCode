# Codex Parity Matrix

| Area | Feature | Status | Notes |
| --- | --- | --- | --- |
| Core | Threads and transcript persistence | Implemented | JSON thread store, desktop bootstrap loading, and mock agent runner. |
| Core | Project picker/sidebar | Partial | Workspace state model, persisted project registry, selected-project context, native project rail, visible New chat/Search/Open project/Terminal actions, desktop folder picker, current-directory desktop project seed, thread selection, visible pin/archive controls, and Playwright coverage exist; richer project/thread actions pending. |
| Core | TrustedRouter runtime | Partial | CLI and desktop can use live TrustedRouter when an env or stored secret key exists; CLI auth key management and native developer settings exist; desktop refreshes the live model catalog when keyed; OAuth flow pending. |
| Core | TrustedRouter model picker | Partial | Catalog model, live fetch adapter, grouped provider/category/model SwiftUI picker, and Playwright coverage exist; richer search/filter browser pending. |
| Tools | Shell commands | Implemented | `host.shell.run` with empty-command guard. |
| Tools | File read/write | Implemented | Workspace-scoped UTF-8 files. |
| Tools | Apply patch | Implemented | Workspace-scoped unified diff application through `git apply`. |
| Tools | Git status/diff/stage/restore/commit/push/PR/worktrees | Partial | Status/diff, file-level stage/restore, hunk-level stage/restore, local commit, conservative named-remote branch push, GitHub PR creation via structured `gh pr create`, and worktree list/create/remove are implemented with workspace path, patch, ref-name, and registered-worktree checks. Rich GitHub issue/PR review workflows pending. |
| Safety | Read-only/Review/Auto modes | Implemented | Auto can use static or model reviewer; SwiftUI shell can switch and persist modes. |
| Safety | Reviewer model call | Partial | TrustedRouter client and native developer settings exist; OAuth wiring pending. |
| UX | Tool cards | Partial | Tool-card presentation model, HTML harness, and SwiftUI shell render queued/running/done/failed/review states; QuillUI polish pending. |
| UX | Review pane | Partial | Latest completed `host.git.diff` is summarized into a changed-file pane in SwiftUI and the Playwright harness; file-level and hunk-level Stage/Restore controls execute workspace-scoped git tools and refresh the diff; file-scoped review notes are replayed from thread events and hidden when stale. Rich inline line/range comments pending. |
| UX | Top bar widget | Partial | Top-bar presentation state, HTML harness, SwiftUI shell, and macOS `MenuBarExtra` track thread/project/model/mode/status/Computer Use and expose quick New Chat, Open Project, Command Palette, Terminal, Browser, Settings, Stop All, and disabled Disconnect All affordances. Stop All cancels active sends and integrated-terminal commands. Rich live progress, agent-router process cancellation, remote connection controls, and Linux tray adapter pending. |
| UX | Context and rate banners | Partial | Estimated context pressure banner appears near the local budget and offers New thread plus Fork from last. Exact provider token accounting, rate-limit banners, and richer fork context controls pending. |
| UX | Keyboard shortcuts/slash commands | Partial | Local slash command parser handles `/help`, `/status`, `/new`, `/mode`, and `/model` with Swift and Playwright coverage; Search opens a finder over thread title, model, pinned state, and indexed transcript/tool content. A command palette over workspace commands exists in SwiftUI and the Playwright harness; richer ranking and full shortcut registry pending. |
| Workspace | Integrated terminal | Partial | Workspace-scoped terminal pane, command history, cancellable command execution, native SwiftUI surface, static HTML rendering, and Playwright coverage exist; full interactive PTY/session streaming pending. |
| Workspace | Worktrees | Partial | Core `git worktree` list/create/remove tools, shared command-palette actions, and create/remove dialogs exist. Codex-style worktree thread UI and branch handoff flows pending. |
| Workspace | Local environment actions | Partial | Project-local `.quillcode/actions/*.sh` and `.quillcode/local-env/*.sh` scripts are discovered with symlink/root bounds and exposed in the command palette as `Run ...` actions that dispatch through `host.shell.run`. Setup config metadata, scheduling, and richer local-env orchestration pending. |
| Workspace | AGENTS/rules instructions | Partial | Project-local `AGENTS.md`, `.quillcode/rules.md`, and `.quillcode/instructions.md` are bounded, persisted on project refs, copied into thread context, injected into TrustedRouter as hidden system context, and surfaced as a top-bar status. Nested directory precedence, per-file rule scopes, and richer conflict display pending. |
| Browser | In-app browser | Partial | Workspace browser panel, address normalization for web/localhost/file/project-relative targets, browser comments, SwiftUI surface, HTML renderer, and Playwright coverage exist. Native WebView/rendering adapter, browser DOM inspection, and signed-in browser profile support pending. |
| Computer Use | Backend protocol | Implemented | Stub backend exists; platform backends pending. |
| Plugins | Skills/plugins/MCP | Deferred | Manifest tests planned. |
| Long-running | Automations/subagents | Deferred | Planned after stable thread runtime. |
| Memory | Memories/Chronicle | Deferred | Requires redaction and idle jobs. |
| Remote | Phone/SSH remote | Deferred | QuillCloud/SSH design pending. |
| Artifacts | PDF/docs/sheets/images | Deferred | Preview adapters pending. |
