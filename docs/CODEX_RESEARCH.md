# Codex Research Notes

QuillCode tracks Codex workflow parity without copying private implementation or visual trade dress. These notes capture why each feature exists and how QuillCode should implement the equivalent.

## Current Research Inputs

- Codex app-server 0.142.5 `thread/inject_items` accepts one nonempty list of raw Responses API
  `ResponseItem` values and returns `{}` without a notification. The items are persisted as model-only
  history: before the first turn they follow standard context and precede the first user prompt; later
  injections follow the last durable transcript item and precede the next prompt. Injection remains
  legal while a turn is active and must survive that turn's eventual snapshot. Empty arrays, malformed
  response items, unknown/archived tasks, and remote image URLs fail with `-32600`; inline `data:` images
  and forward-compatible message roles are accepted. Public 0.142.5 integration tests confirm that raw
  injected items reach the next Responses request but never become visible transcript turns. Because
  TrustedRouter uses chat-completions input, QuillCode maps message text/inline images to equivalent
  chat messages and preserves every other response-item variant as canonical model-visible JSON rather
  than inventing executable tool calls. Sources: generated 0.142.5 schemas, isolated local
  `codex-cli 0.142.5` success/error/active-turn probes, and public `openai/codex` thread processor and
  integration tests, audited 2026-07-16.
- Current Codex `main` at `18110b810f0a328147f6cd85e6f1ab6414927366` exposes experimental
  `thread/backgroundTerminals/list`, `thread/backgroundTerminals/terminate`, and
  `thread/backgroundTerminals/clean`. Listing loads the thread, returns active unified-exec processes
  sorted by process id, exposes item id, process id, command, cwd, and nullable resource metrics, and
  uses the last PID as an opaque forward cursor. Termination parses one signed 32-bit process id and
  is idempotent; clean terminates every background process owned by that thread. QuillCode maps this
  contract to its existing thread-owned user-shell lifecycle rather than creating a second process
  registry. Source: public `openai/codex` app-server protocol and thread processor, audited 2026-07-16.
- Codex app-server 0.142.5 exposes `thread/search`, `thread/loaded/list`, and
  `thread/turns/list`. Isolated JSONL probes show that search requires a non-whitespace term, searches
  transcript text rather than a renamed title, returns the matching snippet, and accepts a zero limit
  as a one-item page. Loaded threads are connection-local and appear after start. Turn history defaults
  to descending `summary`, accepts `full` and `notLoaded`, and uses JSON anchor cursors shaped like
  `{turnId, includeAnchor}` for reverse navigation. Empty collections ignore malformed cursors because
  there is no anchor to resolve. Although generated schemas include `thread/turns/items/list`, the
  0.142.5 runtime returns `-32601` with `thread/turns/items/list is not supported yet`; QuillCode
  deliberately mirrors that explicit boundary. Sources: generated 0.142.5 schemas, local
  `codex-cli 0.142.5` process probes, and public `openai/codex` thread processor source, audited
  2026-07-16.
- Codex app-server 0.142.5 treats task loading, detailed-event subscription, transient elicitation
  pause state, and durable task settings as separate concerns. `thread/unsubscribe` returns
  `unsubscribed`, `notSubscribed`, or `notLoaded`, keeps the task in `thread/loaded/list`, suppresses
  detailed `turn/*` and `item/*` notifications while leaving task-level notifications visible, and
  `thread/resume` subscribes again. `thread/increment_elicitation` and
  `thread/decrement_elicitation` maintain a connection-local count plus `paused` boolean and reject a
  decrement at zero. `thread/metadata/update` patches omitted/string/null Git fields independently.
  `thread/settings/update` persists model, effort, cwd, approval, sandbox/profile, personality,
  service-tier, summary, and collaboration settings; emits `thread/settings/updated` only when state
  changes and only after the RPC response; treats most explicit nulls as no-ops while
  `serviceTier: null` selects `default`; and rejects a direct sandbox policy combined with a named
  permissions profile. `thread/memoryMode/set` persists enabled/disabled mode; disabled mode removes
  durable notes from model context without deleting them. Sources: generated 0.142.5 schemas and
  isolated local `codex-cli 0.142.5` success, error, null-semantics, notification-order, unsubscribe,
  and reconnect probes, audited 2026-07-16.
- Codex app-server 0.142.5 `thread/shellCommand` is an explicit local-host, full-access shell
  escape hatch rather than a normal model-authored tool call. It trims the required command, rejects
  empty input with `-32600 command must not be empty`, returns `{}` before lifecycle events, uses
  the configured user shell in login-command mode from the thread cwd, and allows one hour. A
  standalone request opens a normal active/turn/item/completion/idle lifecycle; concurrent standalone
  commands share that turn. During an ordinary turn, review, or compaction it reuses the existing turn
  and emits no second turn pair. The command item has source `userShell`, null process ID, streamed
  output, final status/output/exit code, and a parsed action that may remain one honest `unknown`
  command. Output remains model-visible, but persisted thread reads/lists/forks expose only an empty
  standalone turn and never replay command items; rollback removes that empty turn and its hidden
  output. Interruption cancels the command, background terminal inventory is unchanged, and
  unsubscribe suppresses detailed lifecycle while retaining task-level status. Sources: generated
  0.142.5 schemas, public `openai/codex` thread processor/user-shell task/integration tests, and
  isolated local lifecycle, active-task, history, rollback, unsubscribe, and background-terminal
  probes, audited 2026-07-16.
- Codex app-server 0.142.5 experimental `command/exec` runs an argv vector outside any thread and
  defers its response until process exit and output drain. A client process ID is optional for
  buffered compatibility but required by PTY, stdin streaming, output streaming, and every follow-up
  operation. `tty` implies both streams; output deltas are base64, connection-scoped, emitted before
  the response, and omitted from final stdout/stderr. IDs may be reused after exit, EOF terminates
  active processes without a late response, and timeout exits 124. Relative cwd joins the server cwd;
  environment values override inheritance while null removes a variable. Explicit sandbox policy and
  named permission profile are mutually exclusive. Sources: generated 0.142.5 schemas, public
  `openai/codex` command-exec processor/manager/integration tests, and QuillCode executable protocol
  probes, audited 2026-07-16.
- Codex app-server 0.142.5 exposes client configuration discovery through
  `permissionProfile/list`, experimental `collaborationMode/list`, and `configRequirements/read`.
  The permission catalog is the ordered built-in `:read-only`, `:workspace`, and
  `:danger-full-access` set; pagination uses numeric string offsets, clamps a zero limit to one, and
  returns an empty page at the exact end. Collaboration discovery returns Plan then Default and
  requires the initialize-time experimental API capability. Requirements are null when no managed
  document exists. Managed requirement layers merge low to high, recursively merge tables, replace
  scalar/list values, constrain both profile IDs and their sandbox modes, and require one valid
  effective default when a profile allowlist exists. Stable responses omit experimental reviewer,
  hook, and network fields. Sources: generated stable/experimental 0.142.5 schemas, isolated local
  `codex-cli 0.142.5` success/error/pagination probes, and public `openai/codex` requirements stack,
  processor, and config-requirements source, audited 2026-07-16.
- Current Codex app-server exposes `hooks/list` with `{cwds}` input; an empty list uses the session
  CWD. Each result retains its CWD plus discovered hooks, string warnings, and structured path/message
  errors. Hook rows include stable source-derived keys, event and handler metadata, nullable matcher,
  command and status message, timeout, absolute source path, source layer, nullable plugin ID,
  deterministic display order, enabled/managed flags, exact-definition hash, and
  `managed`/`untrusted`/`trusted`/`modified` trust. `hooks.state` controls enabled and trusted-hash
  values without executing commands. Plugin path arrays and inline hook files participate in the
  same catalog; unsupported async, empty, prompt, and agent handlers remain warnings and inert.
  Linked worktrees deliberately load project hooks from the primary checkout. Sources: public
  `openai/codex` app-server protocol, hook configuration, plugin resolver, and integration tests,
  audited 2026-07-16.
- Codex app-server 0.142.5 `gitDiffToRemote` requires one `cwd` and returns the current local upstream
  tip as `sha` plus a direct binary Git diff from that tip to the complete working tree. It includes
  local commits ahead of upstream, staged changes, unstaged changes, and untracked files; excludes
  ignored files; emits tracked patches before Git-ordered untracked patches; and deliberately uses
  the current upstream tip rather than a merge base when histories diverge. Clean repositories return
  an empty diff. Missing CWD, non-repositories, and repositories without an upstream fail with
  `-32600`. QuillCode mirrors that local-ref behavior without fetching, while adding byte/file bounds
  and disabling external diff and text-conversion hooks. Sources: generated 0.142.5 schemas and
  isolated local `codex-cli 0.142.5` clean, dirty, ahead, diverged, binary, ignored, and invalid-repo
  probes, audited 2026-07-16.
- Codex app: projects, worktrees, automations, Git review, in-app browser, Computer Use, artifact previews.
- Codex Review treats Unstaged, Staged, Commit, Branch, and Last turn as distinct scopes, with whole-diff Stage all/Revert all controls. QuillCode should preserve that information architecture while keeping historical comparisons read-only and deriving Last turn from auditable turn-owned edits instead of guessing from the current working tree.
- Official managed-worktree behavior: new Worktree tasks start at detached HEAD from the selected branch, can carry current uncommitted changes, copy normally ignored files only when selected by `.worktreeinclude`, automatically copy ignored `AGENTS.override.md`, and keep a stable task/worktree association. Codex stores managed worktrees under `$CODEX_HOME/worktrees` by default, lets users choose another root, and automatically retains the 15 most recent managed tasks unless cleanup is disabled or the limit is changed. Handoff moves a task and its code between Local and that same worktree; managed cleanup saves restorable snapshots before deletion. Pinned, selected, still-running, Local, and permanent/named-branch worktrees are excluded from automatic removal, while reopening a task whose disposable worktree was removed offers restoration. Source: current Codex manual, Worktrees section (`environments/git-worktrees`).
- Codex keeps two deliberate exit paths from a detached managed task. **Create branch here** stays in the worktree and creates a branch owned by that checkout; **Hand off** moves the task and code to Local. Git permits one checkout to own a branch, so QuillCode must reject an existing or already-checked-out branch before promotion and explain that Handoff is the right path when the user needs the branch locally.
- The current Codex Worktrees manual says a named worktree task may remain in place, push its branch, and open a GitHub pull request. It also says task history remains available after a managed worktree is deleted, but it does not define an in-app merge-queue action. QuillCode therefore treats Land as an explicit audited extension: persist exact PR identity, queue squash auto-merge through the ordinary GitHub tool, refresh authoritative status, and remove only a clean exact-head worktree without force while retaining task and PR history.
- Codex commands: command menu, keyboard shortcuts, thread search, slash commands.
- Codex non-interactive automation keeps the final answer on stdout and progress on stderr, offers
  JSONL thread/turn/item/error events, accepts a prompt plus piped context or `-` for a full stdin
  prompt, resumes the latest or an exact saved task, supports ephemeral runs and final-message/schema
  files, defaults to read-only, and requires a Git repository unless explicitly bypassed. Current
  Codex names its disabled filesystem permission profile `:danger-full-access`; QuillCode mirrors that
  explicit opt-in by removing the built-in workspace path boundary for shell working directories and
  file tools while preserving safety review, output bounds, edit guards, and secret protections. Exec
  and app-server thread start/resume/fork initialize required MCP servers
  before model invocation or persistence, expose ready schemas as normal model tools, tolerate optional
  startup failures, aggregate required failures by configured name, and await registry teardown on every
  terminal path. Exec honors `--ignore-user-config` by skipping MCP configuration. Broader
  account/model/config/plugin methods and websocket transport remain separate slices. Sources: current
  Codex manual, Non-interactive mode, and `openai/codex`
  `codex-rs/protocol/src/permissions.rs`, `codex-rs/exec/tests/suite/mcp_required_exit.rs` plus
  `codex-rs/mcp-server/src/connection_manager.rs`, audited 2026-07-15.
- Codex 0.142.5 `mcp-server` is a distinct JSON-RPC 2.0 stdio surface for embedding a coding agent as
  MCP tools. An isolated process probe negotiated protocol `2025-06-18`, advertised only `codex` and
  `codex-reply`, returned text plus `{threadId, content}` structured output, streamed `codex/event`
  notifications carrying request/thread metadata, and requested command or patch approval through
  `elicitation/create`. The run tool accepts approval policy, base/compaction/developer instructions,
  config overrides, cwd, model, prompt, and sandbox; reply accepts `threadId` (plus a deprecated
  conversation alias) and prompt. QuillCode mirrors that public contract while keeping its stable
  structured action/tool instructions intact. Exact Codex-native event variants, native patch
  `FileChange` metadata, and OS-sandbox retry semantics remain separate compatibility work. Sources:
  local `codex-cli 0.142.5` protocol probes and public `openai/codex` MCP server approval/message
  runners, audited 2026-07-15.
- Current Codex exec installs a one-shot Ctrl-C listener, sends `turn/interrupt`, waits for the
  interrupted turn acknowledgement, and exits 1. Its JSONL event processor emits neither
  `turn.completed` nor `turn.failed` for `TurnStatus::Interrupted`, and suppresses final-message output.
  QuillCode follows that observable contract while persisting its local `Stopped by user` transcript
  marker before returning. Source: `openai/codex`, `codex-rs/exec/src/lib.rs` and
  `event_processor_with_jsonl_output.rs`, audited 2026-07-14.
- Codex 0.142.5 exposes a stable `doctor` command with `--json`, `--summary`, `--all`, `--no-color`,
  and `--ascii`. An isolated real run showed a versioned JSON report with `generatedAt`,
  `overallStatus`, and a keyed check map whose entries carry category, status, summary, details,
  remediation, issues, and duration. Human output groups environment, configuration, updates,
  connectivity, and background-server checks and returns nonzero for failures. QuillCode preserves
  that support-tool contract while adapting provider checks to TrustedRouter, adding bounded MCP/task
  inspection, and refusing to emit secrets or task contents. Source: current Codex manual and locally
  installed `codex-cli 0.142.5`, audited 2026-07-15.
- Codex 0.142.5 exposes `review` as a dedicated non-interactive workflow rather than an `exec`
  prompt convention. Its targets are mutually exclusive: uncommitted changes, changes against a base
  branch, one commit with an optional title, or custom review instructions supplied as an argument or
  complete stdin prompt. QuillCode follows that command shape while requiring typed
  `host.review.submit` completion, keeping the run ephemeral, and reusing the desktop review engine
  under a capability-filtered read-only tool catalog. Custom instructions review the current
  uncommitted change set; they do not silently broaden into arbitrary shell execution. Source: current
  Codex manual and locally installed `codex-cli 0.142.5`, audited 2026-07-15.
- Codex 0.142.5 app-server `review/start` takes a thread plus one uncommitted/base-branch/commit/custom
  target and defaults to inline delivery. Inline review returns the source thread id, streams a normal
  turn plus entered/exited review-mode items, and exposes the final review as an assistant item.
  Detached review forks a durable child, emits `thread/started` before the response, and streams the
  review there. Detached review cannot use an ephemeral/paginated parent. QuillCode maps this wire
  contract to its existing typed, read-only review runner and never initializes MCP for the reviewer.
  Sources: generated schemas, official app-server README, public `openai/codex` search results, and
  isolated local `codex-cli 0.142.5` JSONL probes, audited 2026-07-15.
- Current Codex app-server account mutation uses `account/login/start`, `account/login/cancel`, and
  `account/logout`, with asynchronous `account/login/completed` and `account/updated` notifications.
  API-key start returns `{type: "apiKey"}`; browser start returns a login ID and authorization URL;
  cancellation distinguishes `canceled` from `notFound`. QuillCode preserves those observable shapes
  while adapting browser login to TrustedRouter OAuth. Because the resulting durable credential is a
  delegated TrustedRouter API key, QuillCode reports `apiKey`/`apikey` after completion instead of
  inventing a ChatGPT plan or identity. Source: generated app-server schemas and public `openai/codex`
  `app-server-protocol/src/protocol/v2.rs`, audited 2026-07-15.
- Codex desktop keyboard parity is a command-routing contract, not just menu decoration. The documented set includes Command Palette (`Cmd+K`, `Cmd+Shift+P`), Settings (`Cmd+,`), Keyboard Shortcuts (`Cmd+Shift+/`), Open Folder (`Cmd+O`), workspace Back/Forward (`Cmd+[` / `Cmd+]`), text scale (`Cmd++` / `Cmd+-`), Sidebar (`Cmd+B`), Open Review (`Ctrl+Shift+G`), Review panel (`Cmd+Option+B`), Bottom panel (`Cmd+J`), Terminal (`Ctrl+backtick`), Clear Terminal (`Ctrl+L`), Quick Chat (`Cmd+Option+N`), New Task (`Cmd+N`, `Cmd+Shift+O`), Search Tasks (`Cmd+G`), Find in Task (`Cmd+F`), Previous/Next Task (`Cmd+Shift+[` / `Cmd+Shift+]`), and Dictation (`Ctrl+Shift+D`). Codex also exposes searchable Action/Keystroke shortcut customization and reset controls. QuillCode maps Task to Chat in user-facing copy while preserving each behavior.
- Codex Settings offers **Import from other agents** as a reviewable migration rather than an invisible compatibility scan. The import covers supported setup and recent work, lets the user customize what will be imported, is additive instead of destructive, and leaves provider credentials or trust decisions for explicit follow-up. QuillCode follows that product contract for Claude Code while applying stricter source-root, symlink, size, secret-redaction, and destination-receipt boundaries.
- Codex `/side` (alias `/btw`) starts an ephemeral conversation from the active task's history while the parent task keeps running. Inherited history is reference-only, side conversations are excluded from the sidebar and durable task history, and Return discards the side branch. The side branch keeps the parent task's tool permissions, but it must not mutate files or other external state unless the user explicitly asks after entering the side conversation. Sources: official Codex slash-command reference (`learn.chatgpt.com/docs/reference/slash-commands`) and the public Codex TUI side-conversation implementation (`openai/codex`, `codex-rs/tui/src/app/side.rs`).
- Sandbox and Auto-review: enforce boundaries first, route eligible review requests through a reviewer model.
- Remote connections: phone/host pairing, remote approvals, host-local files and tools.
- Plugins, skills, MCP: reusable workflows and external tools; first expose project-local manifests clearly before enabling install/process lifecycle.
- Codex/Open Agent Skills use progressive disclosure: only validated name/description metadata enters
  discovery, and `SKILL.md` bodies load on demand. Repository discovery walks `.agents/skills` from
  the active directory through the Git root, then user `~/.agents/skills`, admin, and bundled/system
  scopes; user-authored repo/user/admin skill-directory symlinks are followed with cycle and size
  bounds. Optional `agents/openai.yaml` supplies interface and tool-dependency metadata. The 0.142.5
  app-server exposes this catalog through `skills/list`, allows bounded per-session roots through
  `skills/extraRoots/set`, persistently enables/disables exact paths or names through
  `skills/config/write`, and sends invalidation-only `skills/changed` notifications when configuration
  or watched roots change. Source: current Codex manual, generated app-server schemas, and
  `openai/codex` catalog processor, config rules, edit helper, skill loader, and watcher audited
  2026-07-15.
- Codex 0.142.5 app-server filesystem requests are direct connected-client operations, distinct from
  model-authored sandboxed tools. The nine-method surface uses absolute paths and base64 file payloads;
  reads stop at 512 MiB; metadata follows symlink targets while reporting the link itself; directory
  copy requires explicit recursion, merges existing trees, overwrites regular files, preserves links,
  skips special children, and rejects standalone special files plus self/descendant copies. Watches are
  scoped to the client connection, allow missing file targets, debounce for 200 ms, sort changed paths,
  and guarantee no later notification after `fs/unwatch`. Source: generated 0.142.5 schemas plus
  `openai/codex` `fs_processor.rs`, `local_file_system.rs`, `fs_watch.rs`, and v2 filesystem tests,
  audited 2026-07-15.
- Codex Record & Replay is a macOS Computer Use workflow launched from Plugins > + > **Record a skill**. It pre-fills a composer request, asks once for recording permission, observes a focused demonstration until the user stops from the app/menu bar or says they are done, then drafts a reusable skill containing purpose, variable inputs, steps, and verification. The capture should remain focused and avoid secrets; stable team distribution belongs in a plugin instead. QuillCode follows that same information architecture while making consent non-bypassable by Auto review or saved permission rules and keeping raw capture telemetry out of the visible transcript. Source: current Codex manual, [Record & Replay](https://learn.chatgpt.com/docs/extend/record-and-replay.md).
- Standard Codex plugin packages use `.codex-plugin/plugin.json` as the required entry point and may reference package-relative `skills/` and `.mcp.json` components. QuillCode treats discovery as data-only, projects bundled components into its existing audited skill/MCP lanes, and resolves package paths again at use time. Source: current Codex manual, Build plugins and Model Context Protocol sections.
- Standard hooks are discovered from `hooks.json`, inline `[hooks]` tables in `config.toml`, and plugin manifest/default `hooks/hooks.json` files. Multiple sources merge instead of overriding one another. QuillCode discovers project, user, and system `.quillcode` plus Codex-compatible `.codex` JSON/TOML sources through one canonical bounded decoder, and reads managed requirements from `/etc/codex/requirements.toml` and `/etc/quillcode/requirements.toml`. System and managed requirements hooks are policy-trusted and immutable; user and project definitions require exact-definition review. `allow_managed_hooks_only` removes user, project, session, and plugin hooks, while managed `[features].hooks` can pin the feature off. User and managed hooks execute locally even when the active project is SSH Remote; workspace hooks follow the selected local/SSH execution target. Cloud/MDM delivery of additional managed requirement documents remains an adapter follow-up. Editing a non-managed event, matcher, handler, command, timeout, async flag, or package root returns that hook to review. QuillCode executes trusted synchronous command handlers for `UserPromptSubmit`, `Stop`, `PreToolUse`, `PostToolUse`, `PermissionRequest`, `PreCompact`, `PostCompact`, `SessionStart`, `SubagentStart`, and `SubagentStop`; unsupported events, prompt/agent handlers, asynchronous commands, and invalid matchers remain visible and inert. Matching commands launch concurrently and aggregate in configuration order. Every command receives newline-terminated JSON on stdin with `session_id`, nullable `transcript_path`, `cwd`, `hook_event_name`, and `model`; turn-scoped events also receive `turn_id`, and events that define it receive `permission_mode`. Tool hooks add canonical `tool_name` and `tool_input`; pre/post hooks also carry `tool_use_id`, and post adds `tool_response`. Permission requests add a non-destructive `tool_input.description` fallback from the safety rationale. Compaction hooks add `trigger` (`manual` or `auto`) and deliberately omit tool and permission fields. Session start matchers receive `startup`, `resume`, `clear`, or `compact`; the event omits `turn_id`. Subagent matchers receive `agent_type`; their payloads retain the parent session/turn identity and include the worker ID, while stop also includes nullable child transcript/last-message fields and `stop_hook_active`. Plain or structured start output becomes bounded hidden context. SubagentStop requires JSON and can request exactly one continuation through `decision:block` or exit code 2; `continue:false` overrides continuation. Plugin commands additionally receive `PLUGIN_ROOT`, `PLUGIN_DATA`, `CLAUDE_PLUGIN_ROOT`, and `CLAUDE_PLUGIN_DATA`; plugin data is private, stable, and isolated by canonical workspace and plugin. Source: current Codex manual, Hooks and Build plugins > Hooks.
- Repository plugin marketplaces use `.agents/plugins/marketplace.json` (with `.claude-plugin/marketplace.json` as the legacy location). Local sources must begin with `./`, resolve from the marketplace repository root, stay within that root, and may be declared as a string or `{ "source": "local", "path": "./..." }`. QuillCode now follows that local contract, preserves modern-catalog precedence, honors `NOT_AVAILABLE`, and deliberately skips git/npm sources until signed remote acquisition is implemented. Source: current Codex manual, Build plugins > Install a local plugin manually and Marketplace metadata.
- Codex app-server `plugin/install` accepts exactly one local `marketplacePath` or `remoteMarketplaceName` plus `pluginName`, returns `authPolicy` and `appsNeedingAuth`, and installs local packages into `CODEX_HOME/plugins/cache/<marketplace>/<plugin>`. `plugin/uninstall` accepts the composite `pluginId`, returns an empty object, and is idempotent. QuillCode implements the local contract with bounded transactional copies, immediate skill/hook cache invalidation, and explicit remote-source errors; it does not claim remote acquisition. Source: `openai/codex` app-server protocol `v2/plugin.rs` and request processor `plugins.rs`, audited 2026-07-16.
- Codex 0.142.5 app-server `marketplace/add`, `marketplace/remove`, and `marketplace/upgrade`
  manage durable user marketplace registrations separately from individual plugin installation. Add
  accepts a local directory, GitHub `owner/repo`, HTTP(S)/SSH Git URL, optional ref, and optional sparse
  paths; repeated identical add is idempotent. Upgrade can select one configured Git marketplace or all
  Git marketplaces and reports independent per-marketplace errors. Remove deletes the registration and
  any managed clone, but never deletes an external local source directory. QuillCode mirrors this with
  prompt-disabled Git, bounded data-only catalog validation, staged filesystem activation, atomic TOML
  preservation, rollback, cache invalidation, focused actor tests, and an executable JSONL lifecycle
  smoke. Provider-hosted catalogs and sharing remain a distinct remote plugin service boundary. Source:
  `openai/codex` `v2/plugin.rs`, `marketplace_processor.rs`, and `marketplace_add/remove/upgrade` suites,
  audited 2026-07-16.
- Memories and Chronicle: local recall layer, not a replacement for checked-in project rules. The first shippable slice should make loaded memory visible and auditable; explicit `/remember text` writes and explicit Forget actions are acceptable with clear transcript feedback and credential rejection before enabling autonomous writes.
- Codex 0.142.5 app-server exposes parameterless `memory/reset` as a global reset for app-managed memory,
  rather than a request to mutate repository files. QuillCode maps that boundary to the contents of
  `~/.quillcode/memories`, preserves the private root, and leaves project `.quillcode/memories`
  untouched. Reset changes future loads; it does not pretend to recall context already injected into
  an active turn. Source: generated 0.142.5 app-server TypeScript bindings and public `openai/codex`
  memory RPC routing, audited 2026-07-16.
- Codex 0.142.5 app-server relays MCP server-initiated interaction through
  `mcpServer/elicitation/request`. Every request carries `threadId`, nullable `turnId`, and
  `serverName`, plus one of standard `form`, extension `openai/form`, or `url` fields; responses use
  `accept`, `decline`, or `cancel`, and `serverRequest/resolved` precedes terminal turn publication.
  Standard forms are supported independently of the optional rich-form capability
  `capabilities.mcpServerOpenaiFormElicitation`; downstream MCP initialize advertises the rich
  extension only when that app capability is true. Malformed typed schemas are canceled before UI
  projection, client errors decline, and turn transition or disconnect cancels. Sources: generated
  0.142.5 schemas, the official app-server README, and public `openai/codex`
  `app-server-protocol`, MCP connection manager, elicitation processor, and integration tests,
  audited 2026-07-16.
- Current Codex app-server transport behavior uses JSONL only for stdio. `ws://IP:PORT` sends one
  JSON-RPC message per WebSocket text frame, while `unix://` performs the same HTTP Upgrade over the
  Unix socket before entering the shared WebSocket connection loop. TCP exposes `/readyz` and
  `/healthz`, rejects any request with `Origin`, drops binary frames, answers ping with pong, and uses
  bounded queues with exact `-32001` request-overload errors. Unauthenticated non-loopback listeners
  are refused. Capability-token auth accepts a token file or SHA-256 digest; signed bearer auth uses
  HS256 plus required expiry and optional not-before/issuer/audience checks. Sources: current Codex
  manual app-server transport section and public `openai/codex` `app-server-transport` transport,
  websocket, Unix-socket, and auth implementations, audited 2026-07-16.

- Current Codex app-server experimental `thread/items/list` pages complete stored `ThreadItem`
  payloads without resuming a thread. The request requires `threadId`, accepts nullable `turnId` and
  cursor, defaults to ascending order and 25 items, and clamps a requested page to 1...100. Each
  response entry carries its containing `turnId`; `nextCursor` continues after the page and
  `backwardsCursor` includes the page head when the client reverses direction. Cursors belong to the
  complete item stream rather than a turn-filtered substream, so clients may reuse one cursor with or
  without `turnId`. Stores without item pagination return `-32601` and exact message
  `thread/items/list is not supported yet`. QuillCode's local JSON store can provide the contract and
  retains the older `thread/turns/items/list` spelling only as an explicit unsupported compatibility
  boundary. Sources: official app-server README, generated v2 schemas, request processor, and remote
  thread-store tests at public `openai/codex` commit `3151954`, audited 2026-07-16.

## Product Translation

- QuillCode should feel like a fast native coding workspace.
- The first screen is the real workspace, not a landing page.
- A simple user request should either execute directly or show a precise review reason; it should not say “I will do it” and then stall.
- Record & Replay should feel like one continuous workflow: describe the goal, confirm once with explicit cloud-processing disclosure, demonstrate, stop, and receive the created skill. Stop must never depend on a reviewer model, current app permissions, or which task happens to be selected. Stop All must end capture too, and a duration cap must become a visible stopped-capture state instead of silently discarding later activity.
- Importing another agent should be understandable before mutation: show detected projects and item categories, let the user deselect either, explain previously imported items, and finish with concrete setup follow-ups rather than silently activating foreign credentials or hooks.
- A side question should never interrupt, rename, persist, or otherwise mutate its parent task. Its boundary and Return action must remain visible until the user returns.
- Review UI should be calm and specific. Safety language should avoid scary labels for approved low-risk commands.
- Tool outputs should end with a clear chat answer, not only raw JSON cards.
- Memory context should be inspectable from the workspace chrome. Users should be able to tell what background notes the agent can see, and the agent must treat those notes as context rather than commands.
- App-managed global memory needs reversible UX before autonomous memory is considered. Project memories are files and should stay under project ownership unless QuillCode is explicitly editing those files.
- Browser preview should give immediate inspection context even before a full native WebView exists. A bounded metadata snapshot is useful for local HTML review and avoids pretending QuillCode has loaded a signed-in browser profile.

## Claude CLI Design Review Notes

- Tool cards should have three density states: collapsed, peek, and expanded. Completed successful tools should collapse by default so the transcript reads like a conversation, while queued/running cards peek and failed/review cards stay more open for diagnosis. QuillCode now carries this as explicit surface data so native and harness renderers stay aligned.
- The top bar must use fixed-width numeric/status zones with tabular digits so token counts, model names, and connection status never cause layout jitter.
- Codex local-environment Actions appear in the desktop top bar for quick access. QuillCode follows that interaction without adding another permanent header button: runnable project actions live in one contextual **Actions** group inside the existing top-bar overflow and route through the same command/tool-card pipeline as the palette and `/env`.
- Safety review should be inline and calm. Approved low-risk actions should read as ordinary progress, while red and modal treatment should be reserved for actual denials or destructive actions.
- MCP schemas should default to a compact name/description/argument-count presentation, with richer argument detail available on expansion. Dense schema text is useful, but it should not dominate the first view.
- Native feel depends on restraint: hairline borders over heavy shadows, short ease-out disclosure animations, optimistic message rendering, and direct keyboard access for model picker, find, stop, and command palette actions.
- The latest Claude CLI UI passes called out structural pressure points: top-bar pill overflow should not compete with thread identity, model/mode should live at the composer where send-time decisions happen, the sidebar plus Activity pane should not consume most of the window before the transcript gets space, and the HTML harness composer needed to become a multiline textarea so Playwright parity does not lie about native composer behavior. The top bar now uses quiet identity/status/action clusters with bounded context labels, model/mode live in composer controls across SwiftUI/static HTML/Playwright, and the composer uses textarea semantics with Shift+Enter for newlines and Enter to send.
- The same pass flagged renderer drift as the main architecture risk. SwiftUI and HTML need shared surface data for every visible concept, and tests should assert the data users see, not just that a tag exists. Image artifacts now follow that rule with shared type, extension, filename, and source metadata.
