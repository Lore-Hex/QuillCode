# Roadmap

## Milestone 0: Compile-Stable Foundation

- SwiftPM package, docs, CI skeleton.
- Core models, mock agent, shell/file/git tools.
- Auto safety policy and reviewer protocol.
- Persistence and secret-store API.
- Unit tests for direct command execution and safety behavior.
- Current status: shell, file read/write, apply patch, git status/diff, file/hunk-level git stage/restore, local git commit, and git worktree list/create/remove are implemented with unit coverage.

## Milestone 1: Native Workspace UI

- QuillUI shell with sidebar, top bar, composer, transcript, and tool cards.
- Project picker and model picker.
- Settings with OAuth/dev override and mode selection.
- Native smoke tests.
- Current status: testable workspace state model, persisted config/thread/project bootstrap, bounded project instruction loading from `AGENTS.md` and `.quillcode` rules, HTML surface contract, Playwright harness, and SwiftUI desktop shell exist for project rail, visible New chat/Search/Open project/Browser/Terminal sidebar actions, desktop folder picking, thread pin/archive controls, thread search, command palette, local environment action commands from `.quillcode/actions` and `.quillcode/local-env`, browser preview state and comments, composer, top bar, transcript, tool-card presentation, integrated workspace terminal command history, git diff review summaries with file and hunk Stage/Restore controls, git worktree command-palette actions and create/remove dialogs, slash commands, grouped model selection, mode switching, and native developer settings. The desktop app seeds the current working directory as the initial project and runs tools from the selected project path.

## Milestone 2: TrustedRouter Runtime

- OAuth PKCE and delegated key storage.
- Streaming chat client.
- Live model catalog native UI.
- Auto reviewer using `glm-5.2` with `kimi-k2.6` fallback in the native app.
- Current status: non-streaming live TrustedRouter adapter exists behind CLI `--live`; desktop env/secret-key runtime selection, native key/base-URL settings, live model-catalog refresh, and CLI key-management commands are implemented.

## Milestone 3: Codex Workflow Parity

- Inline review comments, apply patch review integration, full PTY terminal sessions, worktree thread UI, local env actions.
- Nested project-instruction precedence and visible conflict diagnostics.
- Browser rendering adapter, DOM/page inspection, and richer browser comments.
- Computer Use platform backends and app approvals.
- Plugins, skills, MCP, memories, and automations.
