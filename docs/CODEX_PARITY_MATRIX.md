# Codex Parity Matrix

| Area | Feature | Status | Notes |
| --- | --- | --- | --- |
| Core | Threads and transcript persistence | Implemented | JSON thread store and mock agent runner. |
| Core | Project picker/sidebar | Partial | State models exist; QuillUI view pending. |
| Core | TrustedRouter model picker | Partial | Catalog model exists; live catalog pending. |
| Tools | Shell commands | Implemented | `host.shell.run` with empty-command guard. |
| Tools | File read/write | Implemented | Workspace-scoped UTF-8 files. |
| Tools | Apply patch | Deferred | Planned after diff/review pane. |
| Tools | Git status/diff | Implemented | Read-only shell-backed git tool. |
| Safety | Read-only/Review/Auto modes | Implemented | Auto can use static or model reviewer. |
| Safety | Reviewer model call | Partial | Protocol and parser exist; TrustedRouter client pending. |
| UX | Tool cards | Partial | Event model exists; UI pending. |
| UX | Top bar widget | Partial | State model exists; native menu widget pending. |
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

