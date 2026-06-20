# Test Plan

QuillCode uses unit, functional, integration, Playwright, and native smoke tests.

## Unit Tests

- Config parsing, model catalog, auth state, secret store.
- Thread reducers, tool schemas, shell/file/path safety.
- Patch parser, diff parser, Auto reviewer JSON, sandbox policy.
- Shortcut registry, plugin/skill/MCP manifests, memory redaction.

## Functional Tests

- Mock TrustedRouter, mock LLM, fake shell, fake filesystem, fake git repo.
- Cover login, model switch, new thread, tool cards, file edit, command failure, cancellation, approvals, settings, top bar, search, slash commands.

## Integration Tests

- Real filesystem, git, shell, terminal PTY.
- OAuth loopback/dev override.
- QuillUI secret-store adapter.
- macOS Computer Use permission detection and Linux backend detection.
- Worktree creation, local env actions, MCP stdio server.

## Playwright E2E

Drive the QuillCode test harness with mock LLM:

- first run
- login
- open project
- run shell
- edit file
- review diff
- Auto approve/deny/clarify
- browser preview
- plugin install
- settings
- top bar stop-all
- remote-pairing mock

## Native Smoke Tests

- Packaged macOS and Linux app launch.
- Login/dev override.
- Open repo, chat, run `whoami`, create file, review diff.
- Terminal toggle, settings, top bar widget, quit/relaunch persistence.

## Release Gates

- All unit tests pass on macOS and Linux.
- Playwright mock-LLM E2E passes for core agent, tools, approvals, settings, top bar, and browser harness.
- Native app smoke tests pass on packaged macOS and Linux builds.
- No app target contains `#if linux`; CI enforces this.
- `docs/CODEX_PARITY_MATRIX.md` marks each feature as implemented, deferred with reason, or not applicable.

