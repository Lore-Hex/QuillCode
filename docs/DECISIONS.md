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
- The first project UX is a native project rail backed by explicit selected-project state and `~/.quillcode/projects.json`. The desktop app seeds the launch working directory as the initial project; native folder picking remains a separate adapter milestone.
- Native developer settings save the TrustedRouter API base URL in `config.toml` and the local API key through `QuillSecretStore`. Saving settings rebuilds the active desktop runtime immediately so the user does not need to relaunch to switch from mock to live mode.
- The first review surface is derived from completed `host.git.diff` tool cards rather than separate mutable UI state. That keeps the Codex-style review pane replayable from the thread event log and lets stage/revert controls build on the same parsed diff summary later.
- Slash commands are handled by the workspace model before agent dispatch. They are local app controls, not model turns, so `/new`, `/mode`, `/model`, `/status`, and `/help` stay deterministic and do not consume TrustedRouter requests.
- Git stage/restore tools run `git` through process arguments, not shell strings, and resolve requested paths back into the workspace before execution. Review-pane hunk controls should reuse the same path guard.
- Review-pane Stage/Restore controls append normal tool queued/running/completed events and immediately run `host.git.diff` afterward. The UI does not keep a separate review mutation log; the visible review pane remains reconstructed from the latest diff tool result.
- Hunk Stage/Restore uses selected unified-diff patches and `git apply` through process arguments: `--cached` for staging and `--reverse` for restoring. The tool rejects patch metadata that points at a different path than the selected review hunk.
