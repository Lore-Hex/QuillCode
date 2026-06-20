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
| Tools | Git status/diff/stage/restore/commit/worktrees | Partial | Status/diff, file-level stage/restore, hunk-level stage/restore, local commit, and worktree list/create/remove are implemented with workspace path, patch, and registered-worktree checks. Push/PR pending. |
| Safety | Read-only/Review/Auto modes | Implemented | Auto can use static or model reviewer; SwiftUI shell can switch and persist modes. |
| Safety | Reviewer model call | Partial | TrustedRouter client and native developer settings exist; OAuth wiring pending. |
| UX | Tool cards | Partial | Tool-card presentation model, HTML harness, and SwiftUI shell render queued/running/done/failed/review states; QuillUI polish pending. |
| UX | Review pane | Partial | Latest completed `host.git.diff` is summarized into a changed-file pane in SwiftUI and the Playwright harness; file-level and hunk-level Stage/Restore controls execute workspace-scoped git tools and refresh the diff. Inline comments pending. |
| UX | Top bar widget | Partial | Top-bar presentation state, HTML harness, and SwiftUI shell track thread, project, model, mode, status, and Computer Use; native menu bar widget pending. |
| UX | Keyboard shortcuts/slash commands | Partial | Local slash command parser handles `/help`, `/status`, `/new`, `/mode`, and `/model` with Swift and Playwright coverage; Search opens a finder over thread title, model, pinned state, and indexed transcript/tool content. A command palette over workspace commands exists in SwiftUI and the Playwright harness; richer ranking and full shortcut registry pending. |
| Workspace | Integrated terminal | Partial | Workspace-scoped terminal pane, command history, native SwiftUI surface, static HTML rendering, and Playwright coverage exist; full interactive PTY/session streaming pending. |
| Workspace | Worktrees | Partial | Core `git worktree` list/create/remove tools, shared command-palette actions, and create/remove dialogs exist. Codex-style worktree thread UI and branch handoff flows pending. |
| Browser | In-app browser | Deferred | Requires QuillUI/browser surface. |
| Computer Use | Backend protocol | Implemented | Stub backend exists; platform backends pending. |
| Plugins | Skills/plugins/MCP | Deferred | Manifest tests planned. |
| Long-running | Automations/subagents | Deferred | Planned after stable thread runtime. |
| Memory | Memories/Chronicle | Deferred | Requires redaction and idle jobs. |
| Remote | Phone/SSH remote | Deferred | QuillCloud/SSH design pending. |
| Artifacts | PDF/docs/sheets/images | Deferred | Preview adapters pending. |
