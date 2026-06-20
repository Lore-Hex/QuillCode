# QuillCode Decisions

## 2026-06-20

- Product and repository name: **QuillCode**.
- License: Apache 2.0.
- Default model: `trustedrouter/fusion`.
- Auth: TrustedRouter OAuth first; hidden developer override for API key/base URL.
- Tool modes: `Read-only`, `Review`, `Auto`; do not use the label `Full Access`.
- Auto reviewer: primary `glm-5.2`, fallback `kimi-k2.6`.
- First implementation uses a deterministic mock LLM so tests do not require network or credits.
- Live TrustedRouter mode is exposed through `quill-code --live`; native UI should use the same `LLMClient` and `SafetyModelClient` protocols.
- QuillUI is the UI direction, but core tests must not depend on a dirty local QuillUI checkout.
- Platform-specific code belongs in adapter packages, not the app target.
- The first desktop executable is `quill-code-desktop`, built with SwiftUI over the same `WorkspaceSurface` contract used by the HTML/Playwright harness. This keeps native UI work testable before the full QuillUI adapter exists.
- Desktop runtime selection defaults to mock LLM for no-key demos, switches to live TrustedRouter when an environment or stored secret key exists, and supports `QUILLCODE_USE_MOCK_LLM=true` for deterministic test runs.
- The desktop model picker is data-driven from the TrustedRouter catalog. It keeps `trustedrouter/fusion` as the deterministic fallback, groups options by category, and refreshes live catalog data only when an env or stored key exists.
- The first project UX is a native project rail backed by explicit selected-project state and `~/.quillcode/projects.json`. The desktop app seeds the launch working directory as the initial project, and `Open project` uses a desktop folder picker while the surface contract keeps the project action as a platform-neutral command.
- Native developer settings save the TrustedRouter API base URL in `config.toml` and the local API key through `QuillSecretStore`. Saving settings rebuilds the active desktop runtime immediately so the user does not need to relaunch to switch from mock to live mode.
- The first review surface is derived from completed `host.git.diff` tool cards rather than separate mutable UI state. That keeps the Codex-style review pane replayable from the thread event log and lets stage/revert controls build on the same parsed diff summary later.
- Slash commands are handled by the workspace model before agent dispatch. They are local app controls, not model turns, so `/new`, `/mode`, `/model`, `/status`, and `/help` stay deterministic and do not consume TrustedRouter requests.
- Git stage/restore tools run `git` through process arguments, not shell strings, and resolve requested paths back into the workspace before execution. Review-pane hunk controls should reuse the same path guard.
- Review-pane Stage/Restore controls append normal tool queued/running/completed events and immediately run `host.git.diff` afterward. The UI does not keep a separate review mutation log; the visible review pane remains reconstructed from the latest diff tool result.
- Hunk Stage/Restore uses selected unified-diff patches and `git apply` through process arguments: `--cached` for staging and `--reverse` for restoring. The tool rejects patch metadata that points at a different path than the selected review hunk.
- Review notes are stored as `reviewComment` thread events and folded into the latest diff-derived review pane by path. Notes for files that are no longer present in the active diff remain in the transcript event log but are hidden from the current review pane.
- Local git commit support is intentionally limited to already staged changes and a required message. Push, PR creation, and remote writes remain separate tools so safety and review can gate them differently.
- Git push support is limited to named remotes and safe branch names, defaulting to `origin` and the current branch. The first implementation intentionally excludes arbitrary refspecs and URL remotes so normal branch publishing works without broad remote-write ambiguity.
- GitHub pull request creation is a structured `host.git.pr.create` tool backed by `gh pr create` through process arguments. The tool requires a title unless `fill` is explicitly enabled, validates base/head refs with the same conservative ref-name guard as push, and returns the created PR URL as an artifact when the GitHub CLI prints one.
- Search stays local and deterministic for now. Sidebar items carry a capped transcript/tool search index derived from persisted thread messages and events, so users can find prior chats by content without a separate background indexer yet.
- The first command palette is a filtered view over `WorkspaceCommandSurface`, not a separate command registry. Native menus, sidebar buttons, top-bar overflow, and palette entries must route to the same command IDs so keyboard and visible actions stay consistent.
- The first integrated terminal is command-history based rather than a persistent PTY. It runs workspace-scoped shell commands through the same local shell executor as `host.shell.run`, which makes it immediately useful and testable while leaving streaming PTY/session control as a later adapter milestone.
- Git worktree creation accepts only paths inside the selected project's parent directory so Codex-style sibling worktrees are possible without arbitrary filesystem targets. Worktree removal is stricter: the path must also appear in `git worktree list --porcelain` before `git worktree remove` can run.
- Worktree create/remove UI uses dedicated dialogs that dispatch structured `host.git.worktree.*` tool calls rather than stuffing commands into the chat composer. This keeps app-initiated workspace actions replayable in the transcript in the same shape as agent tool calls.
- Project instruction loading starts with `AGENTS.md`, `.quillcode/rules.md`, and `.quillcode/instructions.md`. Instructions are bounded, stored on the project, copied into thread context before agent runs, and sent as hidden system context rather than visible transcript messages.
- Local environment actions are discovered from project-local `.quillcode/actions/*.sh` and `.quillcode/local-env/*.sh` files, capped at 16 actions, and exposed as command-palette entries. Symlinks and resolved paths must stay inside the selected project root. Actions run through `host.shell.run` so they are transcripted and governed by the same tool-card path as agent shell commands.
- Browser preview starts as workspace state and surface contract, not a platform WebView embedded directly in the app module. The model normalizes `http`, `https`, `file`, localhost, and project-relative file targets, while the UI/harness provide the address bar and browser comments. Native rendering adapters should live behind a platform/browser adapter layer later.
