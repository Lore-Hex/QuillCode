# Test Plan

QuillCode uses unit, functional, integration, Playwright, and native smoke tests.

## Unit Tests

- Config parsing, model catalog, auth state, secret store.
- Thread reducers, tool schemas, shell/file/path safety.
- Patch parser, diff parser, file/line/range review comments, Auto reviewer JSON, sandbox policy.
- Project instruction discovery, nested precedence, symlink/root bounds, and byte/file caps.
- Shortcut registry, plugin/skill/MCP manifest discovery, MCP structured launch command/args, stdio `Content-Length` framing, bounded MCP `initialize`/`tools/list` probes, MCP `tools/call` request/response parsing, symlink/root bounds, duplicate ID handling, byte/count caps, malformed manifest skips.
- Memory discovery from global and project roots, extension allow-listing, symlink/root bounds, unsupported file skips, count/file/total byte caps, truncation labels, explicit `/remember text` global writes, global memory deletion, credential/token/password/private-key rejection, thread snapshotting, TrustedRouter prompt injection as background context, and future memory redaction.

## Functional Tests

- Mock TrustedRouter, mock LLM, fake shell, fake filesystem, fake git repo.
- Cover login, model switch, searchable model picker, new thread, project instruction and memory refresh before runs, explicit memory writes and forgetting, project extension manifest refresh, MCP start/probe/stop lifecycle state, MCP tool invocation from an agent turn, incremental run progress, chronological transcript ordering, tool cards, artifact preview chips, collapsed successful-tool details, file edit, post-patch review refresh, review comments, command failure, cancellation, approvals, settings, top bar, search, slash commands, slash-to-workspace-action routing, and worktree project/thread handoff.

## Integration Tests

- Real filesystem, git, shell, terminal PTY.
- OAuth PKCE generation, authorize URL construction, callback state validation, loopback callback capture, key exchange, delegated key persistence, non-secret account persistence, userinfo fetch, runtime refresh, loopback/dev override.
- QuillUI secret-store adapter.
- macOS Computer Use permission detection and Linux backend detection.
- Worktree creation plus selected-project/thread handoff, local env actions, MCP stdio server lifecycle, MCP readiness probes, and MCP tool routing through advertised `tools/call` allowlists.

## Playwright E2E

Drive the QuillCode test harness with mock LLM:

- first run
- login
- open project
- search and select a model
- run shell
- surface file/URL artifacts from tool-card output, with preview metadata visible and raw successful-tool JSON collapsed until opened
- chronological user/tool/answer transcript rendering
- edit file
- review diff, post-patch review refresh, and file/line/range review notes
- Auto approve/deny/clarify
- browser preview
- browser source snapshots for localhost/web/file URLs, including bounded local HTML metadata
- extension manifest discovery, with plugin/skill/MCP counts and disabled-state display
- memories pane discovery, global/project labels, truncation status, top-bar memory pill, sidebar toggle, command-palette toggle, command-palette Add memory prefill, `/memories` slash command, `/remember text` save flow with refreshed counts, and global Forget action with refreshed counts/transcript
- plugin install
- settings
- top bar stop-all
- slash commands for mode, terminal, browser, worktrees, and PR prep
- worktree create handoff into the selected worktree project and thread
- remote-pairing mock

## Native Smoke Tests

- `./scripts/smoke.sh` runs Swift tests, mock CLI `run whoami`, mock CLI file creation in a temp workspace, and Playwright E2E when local node modules are installed.
- Packaged macOS and Linux app launch.
- Login/dev override.
- Open repo, chat, run `whoami`, create file, confirm the created file appears as a tool-card artifact preview, confirm raw successful-tool details can be opened, review diff.
- Terminal toggle, Memories toggle, Add memory and Forget memory flows, Extensions toggle, settings, top bar widget, quit/relaunch persistence.

## Release Gates

- GitHub Actions runs macOS `swift test` and the app-level Linux-conditional guard on each push and PR.
- GitHub Actions runs Playwright mock-LLM E2E for core agent, tools, approvals, settings, top bar, and browser harness on each push and PR.
- GitHub Actions runs `./scripts/smoke.sh` from a clean checkout after installing E2E dependencies.
- All unit tests pass on macOS and Linux before a stable release.
- Native app smoke tests pass on packaged macOS and Linux builds.
- No app target contains `#if linux`; CI enforces this.
- `docs/CODEX_PARITY_MATRIX.md` marks each feature as implemented, deferred with reason, or not applicable.
