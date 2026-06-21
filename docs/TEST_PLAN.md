# Test Plan

QuillCode uses unit, functional, integration, Playwright, and native smoke tests.

## Unit Tests

- Config parsing, model catalog, auth state, secret store.
- Thread reducers, tool schemas, shell/file/path safety.
- Patch parser, diff parser, Auto reviewer JSON, sandbox policy.
- Project instruction discovery, nested precedence, symlink/root bounds, and byte/file caps.
- Shortcut registry, plugin/skill/MCP manifests, memory redaction.

## Functional Tests

- Mock TrustedRouter, mock LLM, fake shell, fake filesystem, fake git repo.
- Cover login, model switch, new thread, project instruction refresh before runs, incremental run progress, chronological transcript ordering, tool cards, file edit, command failure, cancellation, approvals, settings, top bar, search, slash commands, and slash-to-workspace-action routing.

## Integration Tests

- Real filesystem, git, shell, terminal PTY.
- OAuth PKCE generation, authorize URL construction, callback state validation, loopback callback capture, key exchange, delegated key persistence, non-secret account persistence, userinfo fetch, runtime refresh, loopback/dev override.
- QuillUI secret-store adapter.
- macOS Computer Use permission detection and Linux backend detection.
- Worktree creation, local env actions, MCP stdio server.

## Playwright E2E

Drive the QuillCode test harness with mock LLM:

- first run
- login
- open project
- run shell
- chronological user/tool/answer transcript rendering
- edit file
- review diff
- Auto approve/deny/clarify
- browser preview
- plugin install
- settings
- top bar stop-all
- slash commands for mode, terminal, browser, worktrees, and PR prep
- remote-pairing mock

## Native Smoke Tests

- `./scripts/smoke.sh` runs Swift tests, mock CLI `run whoami`, mock CLI file creation in a temp workspace, and Playwright E2E when local node modules are installed.
- Packaged macOS and Linux app launch.
- Login/dev override.
- Open repo, chat, run `whoami`, create file, review diff.
- Terminal toggle, settings, top bar widget, quit/relaunch persistence.

## Release Gates

- GitHub Actions runs macOS `swift test` and the app-level Linux-conditional guard on each push and PR.
- GitHub Actions runs Playwright mock-LLM E2E for core agent, tools, approvals, settings, top bar, and browser harness on each push and PR.
- GitHub Actions runs `./scripts/smoke.sh` from a clean checkout after installing E2E dependencies.
- All unit tests pass on macOS and Linux before a stable release.
- Native app smoke tests pass on packaged macOS and Linux builds.
- No app target contains `#if linux`; CI enforces this.
- `docs/CODEX_PARITY_MATRIX.md` marks each feature as implemented, deferred with reason, or not applicable.
