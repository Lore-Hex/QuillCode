# Test Plan

QuillCode uses unit, functional, integration, Playwright, and native smoke tests.

## Unit Tests

- Config parsing, model catalog, auth state, secret store.
- Thread reducers, tool schemas, shell/file/path safety.
- Multi-step agent tool continuation, hidden tool-feedback serialization, duplicate tool-call loop guards, max-step fallback, and user-visible filtering for sidebar search/fork/compaction.
- Patch parser, diff parser, file/line/range review comments, Auto reviewer JSON, sandbox policy.
- Project instruction discovery, nested precedence, symlink/root bounds, and byte/file caps.
- Shortcut registry, command-derived shortcut discoverability, plugin/skill/MCP manifest discovery, MCP structured launch command/args, stdio `Content-Length` framing, bounded MCP `initialize`/`tools/list` probes, MCP `tools/call` request/response parsing, symlink/root bounds, duplicate ID handling, byte/count caps, malformed manifest skips.
- Computer Use status labeling for all permission combinations, deterministic stub backend action recording, structured tool definitions, and executor argument validation.
- Memory discovery from global and project roots, extension allow-listing, symlink/root bounds, unsupported file skips, count/file/total byte caps, truncation labels, explicit `/remember text` global writes, global memory deletion, credential/token/password/private-key rejection, thread snapshotting, TrustedRouter prompt injection as background context, and future memory redaction.

## Functional Tests

- Mock TrustedRouter, mock LLM, fake shell, fake filesystem, fake git repo.
- Cover login, model switch, searchable model picker, persistent favorite model toggles, recent model sections, current/default/recommended/favorite model badges, duplicate-free model search, new thread, thread rename/duplicate/archive/unarchive/delete, project new-chat/refresh/rename/remove lifecycle, context compaction, project instruction and memory refresh before runs, explicit memory writes and forgetting, project extension manifest refresh, MCP start/probe/stop lifecycle state, MCP tool invocation from an agent turn, Computer Use screenshot/input invocation from an agent turn, multi-step agent runs that chain tools before a final answer, incremental run progress, chronological transcript ordering, active-chat find state, transcript copy actions, user-message draft reuse, assistant response feedback, latest-assistant retry, tool cards, stopped queued/running tool-card resolution, terminal live stdout/stderr streaming, per-project cwd persistence, and running/done/failed/stopped lifecycle, artifact preview chips, image artifact previews, collapsed successful-tool details, file edit, post-patch review refresh, review comments, command failure, rate-limit recovery, redacted runtime diagnostics, cancellation, approvals, settings, top bar, search, keyboard shortcut panel, slash command catalog/help/suggestions, slash-to-workspace-action routing, and worktree project/thread handoff.

## Integration Tests

- Real filesystem, git, shell, terminal PTY.
- OAuth PKCE generation, authorize URL construction, callback state validation, loopback callback capture, key exchange, delegated key persistence, non-secret account persistence, userinfo fetch, runtime refresh, loopback/dev override.
- QuillUI secret-store adapter.
- macOS Computer Use permission detection, permission-denied behavior, screenshot capture, and input primitives; Linux backend detection.
- Worktree creation plus selected-project/thread handoff, local env actions, MCP stdio server lifecycle, MCP readiness probes, and MCP tool routing through advertised `tools/call` allowlists.

## Playwright E2E

Drive the QuillCode test harness with mock LLM:

- first run
- login
- open project, rename it, refresh context, start a project-scoped chat, and remove it from the project list
- find within the active chat with `Cmd+F`, focused input, result counts, next/previous navigation, and close behavior
- search and select a model, including current/default/recommended badges and duplicate-free search results
- run shell
- surface file/URL artifacts from tool-card output, with preview metadata visible and raw successful-tool JSON collapsed until opened
- render image artifacts from screenshot/generated-media tool output as bounded previews below the artifact chips
- chronological user/tool/answer transcript rendering
- hidden agent tool-feedback messages never render as transcript bubbles, sidebar search hits, fork seed messages, or compaction summary content
- copy user/assistant messages and tool outputs with visible `Copied` feedback
- reuse a user message as the focused composer draft without mutating transcript history
- mark assistant responses Helpful or Not helpful and preserve the selected state after rerender
- retry the latest assistant answer and verify it reuses the latest user turn without duplicating Retry buttons on older answers
- edit file
- review diff, post-patch review refresh, and file/line/range review notes
- Auto approve/deny/clarify
- browser preview
- browser source snapshots for localhost/web/file URLs, including bounded local HTML metadata
- extension manifest discovery, with plugin/skill/MCP counts and disabled-state display
- memories pane discovery, global/project labels, truncation status, top-bar memory pill, sidebar toggle, command-palette toggle, command-palette Add memory prefill, `/memories` slash command, `/remember text` save flow with refreshed counts, and global Forget action with refreshed counts/transcript
- plugin install
- settings, runtime issue diagnostics, and secret redaction
- Computer Use top-bar status labels for ready and missing-permission states, plus the Settings permission card and setup buttons
- top bar stop-all and composer Stop during active runs
- `Cmd+/` Keyboard Shortcuts panel, plus command-palette access to the same panel
- slash commands for mode, compact context, terminal, browser, worktrees, and PR prep, plus composer slash suggestion filtering, selected-row keyboard navigation, Enter/Tab accept behavior, click-to-insert, focus retention, and send-through-existing-command-path behavior
- worktree create handoff into the selected worktree project and thread
- remote-pairing mock

## Native Smoke Tests

- `./scripts/smoke.sh` runs Swift tests, mock CLI `run whoami`, mock CLI file creation in a temp workspace, and Playwright E2E when local node modules are installed.
- Packaged macOS and Linux app launch.
- Login/dev override.
- Open repo, chat, run `whoami`, create file, confirm the created file appears as a tool-card artifact preview, capture or mock a screenshot artifact and confirm the image preview renders, confirm raw successful-tool details can be opened, review diff.
- Terminal toggle, Memories toggle, Add memory and Forget memory flows, Extensions toggle, settings, Keyboard Shortcuts, top bar widget, quit/relaunch persistence.
- Computer Use menu-bar status, System Settings setup affordance, and a permission-gated screenshot/input smoke pass on development machines with Screen Recording and Accessibility already granted.

## Release Gates

- GitHub Actions runs macOS `swift test` and the app-level Linux-conditional guard on each push and PR.
- GitHub Actions runs Playwright mock-LLM E2E for core agent, tools, approvals, settings, top bar, and browser harness on each push and PR.
- GitHub Actions runs `./scripts/smoke.sh` from a clean checkout after installing E2E dependencies.
- All unit tests pass on macOS and Linux before a stable release.
- Native app smoke tests pass on packaged macOS and Linux builds.
- No app target contains `#if linux`; CI enforces this.
- `docs/CODEX_PARITY_MATRIX.md` marks each feature as implemented, deferred with reason, or not applicable.
