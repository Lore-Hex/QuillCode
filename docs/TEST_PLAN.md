# Test Plan

QuillCode uses unit, functional, integration, Playwright, and native smoke tests.

## Unit Tests

- Config parsing, model catalog, auth state, secret store.
- Project connection parsing, typed local/SSH Remote persistence, legacy project decoding, and remote display labels.
- Thread reducers, tool schemas, shell/file/path safety, and SSH Remote command request quoting/validation.
- Workspace activity reduction from thread events, tool cards, instructions, memories, artifacts, latest assistant answers, deterministic task plans, deterministic handoff summaries, and collapsible shared section state.
- Multi-step agent tool continuation, hidden tool-feedback serialization, duplicate tool-call loop guards, max-step fallback, and user-visible filtering for sidebar search/fork/compaction.
- Patch parser, diff parser, file/line/range review comments, Auto reviewer JSON, sandbox policy.
- Project instruction discovery, nested precedence, symlink/root bounds, and byte/file caps.
- Shortcut registry, command-derived shortcut discoverability, plugin/skill/MCP manifest discovery, MCP structured launch command/args, stdio `Content-Length` framing, bounded MCP `initialize`/`tools/list` probes, MCP `tools/call` request/response parsing, symlink/root bounds, duplicate ID handling, byte/count caps, malformed manifest skips.
- Computer Use status labeling for all permission combinations, deterministic stub backend action recording, structured tool definitions, and executor argument validation.
- Memory discovery from global and project roots, extension allow-listing, symlink/root bounds, unsupported file skips, count/file/total byte caps, truncation labels, explicit `/remember text` global writes, agent-callable `host.memory.remember` writes, global memory deletion, credential/token/password/private-key rejection, thread snapshotting, TrustedRouter prompt injection as background context, and future memory redaction.
- Browser snapshot extraction, local HTML outline/text-snippet parsing, browser comment filtering, structured `host.browser.inspect` output, and browser inspection final-answer rendering.

## Functional Tests

- Mock TrustedRouter, mock LLM, fake shell, fake filesystem, fake git repo.
- Cover login, model switch, searchable model picker, persistent favorite model toggles, recent model sections, current/default/recommended/favorite model badges, provider/category/model/default/recommended/favorite metadata rows, inline model detail browsing, duplicate-free model search over metadata, new thread, thread rename/duplicate/archive/unarchive/delete, sidebar bulk select/select-all/pin/unpin/archive/unarchive/delete, project new-chat/refresh/rename/remove lifecycle, SSH Remote registration, SSH Remote context refresh of bounded remote AGENTS/rules/instructions/memories through a fake noninteractive SSH binary, SSH terminal execution through the same fake binary, SSH Remote terminal cwd/env persistence across commands, SSH Remote agent shell execution plus bounded file read/write, apply-patch with remote diff refresh, and read-only git status/diff through the same fake binary, SSH Remote agent tool filtering, explicit rejection of unavailable local-only and mutating tools inside remote projects, local-only disabled action states, and per-item execution-context metadata for project-bound tool cards plus terminal history, context compaction, project instruction and memory refresh before runs, explicit slash and agent-callable memory writes and forgetting, project extension manifest refresh, MCP start/probe/stop lifecycle state, MCP tool invocation from an agent turn, Computer Use screenshot/input invocation from an agent turn, browser inspection from an open preview, multi-step agent runs that chain tools before a final answer, incremental run progress, chronological transcript ordering, transcript scroll anchoring while reading older turns versus bottom-pinned appends, derived Activity pane task-plan/task/source/tool/artifact/latest-answer/handoff rendering, Activity section collapse/expand commands, active-chat find state, transcript copy actions, user-message draft reuse, assistant response feedback, latest-assistant retry, multiline composer editing with Shift+Enter newlines and Enter-to-send, tool cards, stopped queued/running tool-card resolution, terminal live stdout/stderr streaming, per-project cwd and environment persistence for local and SSH Remote projects, remote terminal command output, and running/done/failed/stopped lifecycle, artifact preview chips, text artifact previews, image artifact previews, collapsed successful-tool details, file edit, post-patch review refresh, review comments, command failure, rate-limit recovery, redacted runtime diagnostics, cancellation, approvals, settings, clustered top bar labels/status/action layout, search, keyboard shortcut panel, command-palette `>` action scoping, command-palette `/` slash scoping, slash-template composer focus, slash command catalog/help/suggestions, slash-to-workspace-action routing, and worktree project/thread handoff.

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
- interface polish primitives: root font smoothing, balanced headings, pretty short text, tabular dynamic numbers, 40px hit areas, explicit transitions without `all`, tactile `scale(0.96)` press feedback, concentric panel radii, and image outlines
- open project, rename it, refresh context, start a project-scoped chat, and remove it from the project list
- add an SSH Remote from `Project: Add SSH Remote...`, complete `/ssh user@host:/path`, verify sidebar badge/path/top-bar context, refresh remote context from mock AGENTS/rules/memories, verify mutating git/worktree actions are disabled with a reason, run `pwd` in the integrated terminal against the remote mock, run read-only git status/diff from the command palette, verify terminal and tool-card execution-context chips/rails say `SSH Remote`, and verify chat-driven `whoami` uses `host.shell.run` while remote file read/write and apply-patch requests use `host.file.read`/`host.file.write`/`host.apply_patch` over SSH instead of local file tools
- find within the active chat with `Cmd+F`, focused input, result counts, next/previous navigation, and close behavior
- search and select a model, including current/default/recommended badges, provider/category/model metadata rows, metadata-backed search, and duplicate-free search results
- run shell
- surface file/URL artifacts from tool-card output, with source/text preview metadata visible and raw successful-tool JSON collapsed until opened
- open the Activity pane and verify the deterministic task plan, current task, recent events, tools, sources, artifacts, latest answer, handoff summary, and collapsible section state are reconstructed from the same transcript state
- render image artifacts from screenshot/generated-media tool output as bounded previews with visible type, extension, and source metadata below the artifact chips
- chronological user/tool/answer transcript rendering
- hidden agent tool-feedback messages never render as transcript bubbles, sidebar search hits, fork seed messages, or compaction summary content
- bulk-select multiple chats from the sidebar, archive selected chats, select all across recent/archived sections, and delete selected chats through the shared command path
- copy user/assistant messages and tool outputs with visible `Copied` feedback
- reuse a user message as the focused composer draft without mutating transcript history
- mark assistant responses Helpful or Not helpful and preserve the selected state after rerender
- retry the latest assistant answer and verify it reuses the latest user turn without duplicating Retry buttons on older answers
- edit file
- review diff, post-patch review refresh, and file/line/range review notes
- Auto approve/deny/clarify
- browser preview
- browser source snapshots for localhost/web/file URLs, including bounded local HTML metadata, visible outlines, text snippets, and structured browser inspection output
- extension manifest discovery, with plugin/skill/MCP counts and disabled-state display
- memories pane discovery, global/project labels, truncation status, top-bar memory pill, sidebar toggle, command-palette toggle, command-palette Add memory prefill, `/memories` slash command, `/remember text` save flow with refreshed counts, agent-callable memory write flow with refreshed counts, and global Forget action with refreshed counts/transcript
- plugin install
- settings, runtime issue diagnostics, and secret redaction
- Computer Use top-bar status labels for ready and missing-permission states, plus the Settings permission card and setup buttons
- top-bar model/mode, context/status, and action clusters under long labels without horizontal overflow
- top bar stop-all and composer Stop during active runs
- `Cmd+/` Keyboard Shortcuts panel, plus command-palette access to the same panel
- slash commands for mode, compact context, terminal, browser, worktrees, and PR prep, plus command-palette `>` and `/` scope badges, slash-template insertion into the focused composer, multiline composer behavior, Shift+Enter newline handling, Enter-to-send, composer slash suggestion filtering, selected-row keyboard navigation, Enter/Tab accept behavior, click-to-insert, focus retention, and send-through-existing-command-path behavior
- worktree create handoff into the selected worktree project and thread
- remote-pairing mock, SSH Remote registration mock, SSH Remote context-refresh mock, SSH Remote terminal mock, and SSH Remote chat shell mock

## Native Smoke Tests

- `./scripts/smoke.sh` runs Swift tests, mock CLI `run whoami`, mock CLI file creation in a temp workspace, and Playwright E2E when local node modules are installed.
- Packaged macOS and Linux app launch.
- Login/dev override.
- Open repo, chat, run `whoami`, create file, confirm the created file appears as a tool-card artifact and text preview, capture or mock a screenshot artifact and confirm the image preview renders, confirm raw successful-tool details can be opened, review diff, add an SSH Remote, run a noninteractive remote terminal `pwd` smoke, then run `cd` plus `export` and confirm the next remote terminal command inherits both.
- Terminal toggle, Memories toggle, Activity toggle, Add memory and Forget memory flows, Extensions toggle, settings, Keyboard Shortcuts, top bar widget, quit/relaunch persistence.
- Computer Use menu-bar status, System Settings setup affordance, and a permission-gated screenshot/input smoke pass on development machines with Screen Recording and Accessibility already granted.

## Release Gates

- GitHub Actions runs macOS `swift test` and the app-level Linux-conditional guard on each push and PR.
- GitHub Actions runs Playwright mock-LLM E2E for core agent, tools, approvals, settings, top bar, and browser harness on each push and PR.
- GitHub Actions runs `./scripts/smoke.sh` from a clean checkout after installing E2E dependencies.
- All unit tests pass on macOS and Linux before a stable release.
- Native app smoke tests pass on packaged macOS and Linux builds.
- No app target contains `#if linux`; CI enforces this.
- `docs/CODEX_PARITY_MATRIX.md` marks each feature as implemented, deferred with reason, or not applicable.
