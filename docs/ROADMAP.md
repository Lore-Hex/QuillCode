# Roadmap

## Milestone 0: Compile-Stable Foundation

- SwiftPM package, docs, CI skeleton.
- Core models, mock agent, shell/file/git tools.
- Auto safety policy and reviewer protocol.
- Persistence and secret-store API.
- Unit tests for direct command execution and safety behavior.

## Milestone 1: Native Workspace UI

- QuillUI shell with sidebar, top bar, composer, transcript, and tool cards.
- Project picker and model picker.
- Settings with OAuth/dev override and mode selection.
- Native smoke tests.
- Current status: testable workspace state model and HTML surface contract exist for sidebar, composer, top bar, transcript, and tool-card presentation.

## Milestone 2: TrustedRouter Runtime

- OAuth PKCE and delegated key storage.
- Streaming chat client.
- Live model catalog native UI.
- Auto reviewer using `glm-5.2` with `kimi-k2.6` fallback in the native app.
- Current status: non-streaming live TrustedRouter CLI adapter exists behind `--live`.

## Milestone 3: Codex Workflow Parity

- Review pane, apply patch, integrated terminal, worktrees, local env actions.
- Browser preview and comments.
- Computer Use platform backends and app approvals.
- Plugins, skills, MCP, memories, and automations.
