# Codex Parity Matrix

| Area | Feature | Status | Notes |
| --- | --- | --- | --- |
| Core | Threads and transcript persistence | Implemented | JSON thread store and mock agent runner. |
| Core | Project picker/sidebar | Partial | Workspace state model and native sidebar exist with selection, pin, archive, and sorting; project picker pending. |
| Core | TrustedRouter model picker | Partial | Catalog model and live fetch adapter exist; native UI pending. |
| Tools | Shell commands | Implemented | `host.shell.run` with empty-command guard. |
| Tools | File read/write | Implemented | Workspace-scoped UTF-8 files. |
| Tools | Apply patch | Implemented | Workspace-scoped unified diff application through `git apply`. |
| Tools | Git status/diff | Implemented | Read-only shell-backed git tool. |
| Safety | Read-only/Review/Auto modes | Implemented | Auto can use static or model reviewer. |
| Safety | Reviewer model call | Partial | TrustedRouter client exists; OAuth/UI wiring pending. |
| UX | Tool cards | Partial | Tool-card presentation model, HTML harness, and SwiftUI shell render queued/running/done/failed/review states; QuillUI polish pending. |
| UX | Top bar widget | Partial | Top-bar presentation state, HTML harness, and SwiftUI shell track thread, project, model, mode, status, and Computer Use; native menu bar widget pending. |
| UX | Keyboard shortcuts/slash commands | Deferred | Documented in test plan. |
| Workspace | Integrated terminal | Deferred | PTY integration pending. |
| Workspace | Worktrees | Deferred | Requires git worktree manager. |
| Browser | In-app browser | Deferred | Requires QuillUI/browser surface. |
| Computer Use | Backend protocol | Implemented | Stub backend exists; platform backends pending. |
| Plugins | Skills/plugins/MCP | Deferred | Manifest tests planned. |
| Long-running | Automations/subagents | Deferred | Planned after stable thread runtime. |
| Memory | Memories/Chronicle | Deferred | Requires redaction and idle jobs. |
| Remote | Phone/SSH remote | Deferred | QuillCloud/SSH design pending. |
| Artifacts | PDF/docs/sheets/images | Deferred | Preview adapters pending. |
