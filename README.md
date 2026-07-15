# QuillCode

[![CI](https://github.com/Lore-Hex/QuillCode/actions/workflows/ci.yml/badge.svg)](https://github.com/Lore-Hex/QuillCode/actions/workflows/ci.yml)
[![Download Builds](https://github.com/Lore-Hex/QuillCode/actions/workflows/download-builds.yml/badge.svg)](https://github.com/Lore-Hex/QuillCode/actions/workflows/download-builds.yml)
[Download tester build](https://github.com/Lore-Hex/QuillCode/releases/tag/tester-latest)

QuillCode is a Swift and QuillUI coding agent inspired by Codex workflows and backed by TrustedRouter. The long-term target is a public, cross-platform macOS/Linux app with local project chat, tool execution, Computer Use, worktrees, plugins, automations, and browser-assisted development.

This initial repository contains the compile-stable foundation:

- core thread, tool, approval, project, model, and config types
- shell, file read/list/write/search, and git tool executors
- Auto safety review policy with `glm-5.2` and `kimi-k2.6` model slots
- TrustedRouter LLM and safety-model adapters
- JSON thread/project persistence and a single secret-store protocol
- Computer Use screenshot/input backends with private visual model feedback
- deterministic mock LLM agent runner
- testable `quill-code exec` automation CLI with JSONL events, stdin context, resume, ephemeral
  runs, final-message files, structured output, and fail-closed Git/workspace guards
- redacted, read-only `quill-code doctor` diagnostics for installation, config, auth, Git, terminal,
  MCP, saved tasks, connectivity, and app-server health
- Codex-compatible `quill-code review` for uncommitted changes, base-branch comparisons, individual
  commits, or custom criteria, backed by the same typed read-only reviewer as the desktop app
- Codex-compatible `quill-code app-server` stdio JSONL core with strict initialization, durable
  thread lifecycle, streamed turns, steering, interruption, managed local images, approvals,
  model/provider discovery, non-secret account/local usage state, API-key and browser OAuth account
  login/cancel/logout, config reads/writes, local plugin
  marketplace and installed-state discovery, Open Agent Skills discovery with per-session extra
  roots, binary-safe host filesystem read/write/metadata/directory/copy/remove and connection-scoped
  watch methods, plus MCP status/reload/tool/resource methods backed by shared stdio and HTTP clients
- `quill-code-desktop` SwiftUI workspace shell with persisted config/thread bootstrap, project rail, grouped model picker, and developer settings
- Playwright mock UI harness (test-only; any `node_modules` lives under `E2E/playwright` and is ignored)
- parity, roadmap, decision, and test-plan docs

## Try It

Download the latest automated tester build from
[QuillCode Tester Build](https://github.com/Lore-Hex/QuillCode/releases/tag/tester-latest).
The tester release is refreshed after every successful `main` push and nightly;
see [Downloadable Builds](docs/DOWNLOADS.md) for direct app/CLI links, the
machine-readable build manifest, and tester notes.

```bash
swift test
./scripts/smoke.sh
swift run quill-code "run whoami"
swift run quill-code "make a file that says hello world"
swift run quill-code exec --mock --json --ephemeral "inspect this repository"
git diff | swift run quill-code exec --mock "summarize these changes"
swift run quill-code doctor --summary
swift run quill-code review --uncommitted --mock
swift run quill-code review --base main --mock
swift run quill-code auth status
swift run quill-code-desktop
cd E2E/playwright && npm install && npx playwright install chromium && npm test
```

`./scripts/smoke.sh` runs the Swift tests, exercises the exec, doctor, and review CLI process contracts
in temporary workspaces, verifies that file creation plus list/read follow-up works without dirtying
the repo, runs native/packaged desktop smoke with the same create-then-read follow-through, and runs
Playwright automatically when `E2E/playwright/node_modules` is present. Set
`QUILLCODE_SMOKE_ARTIFACT_DIR` to preserve native smoke screenshots and a
`deterministic-smoke-manifest.json` that records which deterministic sub-suites ran.

Agent PRs should merge through the repo merge train instead of racing direct pushes to `main`. Open a PR, wait for CI, then add the `merge-train` label. See [Merge Train](docs/MERGE_TRAIN.md).

The legacy CLI invocation and desktop shell use a deterministic mock LLM by default so tests and local demos do not require a TrustedRouter account. `quill-code exec` is the automation surface and defaults to live TrustedRouter; pass `--mock` for deterministic local runs. The desktop shell switches to live TrustedRouter automatically when `QUILLCODE_API_KEY` or `TRUSTEDROUTER_API_KEY` is present, or when an API key is stored in the QuillCode secret store. With a key, the desktop shell also refreshes the TrustedRouter model catalog and groups provider/category/model choices in the top bar. The desktop Settings sheet can save, replace, or clear the local developer key and API base URL. Set `QUILLCODE_USE_MOCK_LLM=true` to force deterministic mock mode.

`quill-code exec` writes only the final answer to stdout and progress to stderr. `--json` switches
stdout to JSON Lines lifecycle events; `--ephemeral` disables transcript persistence; `exec resume
--last` or `exec resume THREAD_ID` continues a saved task; `-o` writes the final message atomically;
and `--output-schema` validates bounded JSON output. Exec starts read-only and requires a Git
workspace unless `--skip-git-repo-check` is explicitly supplied. Explicit `danger-full-access`
removes the built-in workspace boundary for shell working directories and file tools while retaining
safety review, edit guards, output bounds, and secret protections. Exec also initializes MCP servers from the
global config plus workspace `.codex/config.toml` and `.quillcode/config.toml`, exposes discovered
tools under deterministic `mcp__server__tool` names, and terminates every MCP process or connection
after success, failure, or interruption. A server marked `required = true` fails the run before model
invocation or persistence if it cannot initialize; optional failures do not hide healthy tools.
`--ignore-user-config` skips both user and project MCP configuration. Run `quill-code help` for the
complete option set.

`quill-code doctor` performs bounded, read-only health checks without creating `~/.quillcode` or
rewriting existing state. Human output supports `--summary`, `--all`, `--ascii`, and `--no-color`;
`--json` emits a stable redacted report for support tooling. Reports identify credential and proxy
sources but never include credential values, proxy URLs, MCP headers/environment values, or malformed
config contents. The command exits nonzero only when at least one check fails; warnings remain useful
in CI and redirected terminals without making the report unusable.

`quill-code review` runs live TrustedRouter by default; `--mock` selects the deterministic local
reviewer. Every invocation selects exactly one target: `--uncommitted`, `--base BRANCH`,
`--commit SHA`, a custom criteria prompt, or `-` for bounded stdin criteria. `--title` is accepted only
with `--commit`. The command writes only the validated Markdown review report to stdout and progress
to stderr, never persists a task transcript, and gives the reviewer only bounded file/search/Git-read
tools plus the typed `host.review.submit` report sink. Shell execution, file mutation, Git mutation,
Computer Use, subagents, hooks, skills, and project write tools are absent from that capability set.

`quill-code app-server --mock` starts the deterministic stdio app server; omit `--mock` for the live
TrustedRouter runtime. The implemented core follows Codex's newline-delimited wire shape without a
`jsonrpc` marker: initialize/initialized, thread start/resume/fork/list/read/archive/name/delete/goal,
turn start/steer/interrupt, item and assistant deltas, command/file approval requests, and durable
transcript persistence. Clients can also list models, read provider capabilities, detect account
presence without receiving credentials, read locally observed UTC token usage and explicitly local
spend controls, inspect effective config, atomically update the user config through Codex-compatible
`config/value/write` and `config/batchWrite` with content-version conflict detection, and use
`plugin/list`, `plugin/installed`, and local `plugin/read` to inspect bounded repository/home
marketplaces, QuillCode-installed packages, and package skill/hook/app/MCP summaries without
executing marketplace code or loading skill bodies. Remote plugin and remote skill reads return an
explicit unsupported-service error until QuillCode has a real remote catalog backend. Clients can also use
Codex-compatible `fs/readFile`, `fs/writeFile`,
`fs/createDirectory`, `fs/getMetadata`, `fs/readDirectory`, `fs/remove`, `fs/copy`, `fs/watch`, and
`fs/unwatch` methods. Files are binary-safe base64 payloads, reads use Codex's 512 MiB bound, recursive
copy preserves symlinks while skipping special children, and watches emit sorted, 200 ms-debounced
`fs/changed` notifications until unwatch or disconnect. These methods represent the connected
app-server client's direct host authority; model-authored file tools still use QuillCode's workspace
and safety boundaries. Input messages are capped at 1 MiB, local images are copied into managed
storage, unsupported transports are rejected, and explicit danger-full-access uses the same honest
unrestricted built-in host-tool scope as exec. Client EOF resolves pending approvals and filesystem
watches instead of leaving work stranded.

Account clients can start API-key or browser-based TrustedRouter sign-in through
`account/login/start`, cancel an outstanding browser flow through `account/login/cancel`, and clear
the managed credential through `account/logout`. Responses are emitted before the matching
`account/login/completed` and `account/updated` notifications. Account reads and notifications expose
only the compatible account kind and auth mode; delegated keys never appear on the protocol wire.

App-server clients can also use Codex-compatible `mcpServerStatus/list`,
`config/mcpServer/reload`, `mcpServer/tool/call`, and `mcpServer/resource/read`. MCP configuration is
read from global `mcp_servers` tables plus the selected thread workspace's `.codex/config.toml` and
`.quillcode/config.toml`. Stdio and HTTP transports share the desktop's bounded MCP session runtime;
status preserves raw tool/resource metadata, while `toolsAndAuthOnly` skips the heavier resource and
prompt inventory. Reload and disconnect terminate cached sessions. App-server MCP OAuth
returns a real authorization URL, persists refreshable per-server credentials, emits asynchronous
thread-aware completion, and reloads the MCP registry after successful sign-in.

Skill discovery follows the Codex/Open Agent Skills layout without putting full skill instructions in
the base prompt: repository `.agents/skills` directories from the working directory through the Git
root, user `~/.agents/skills`, admin/system roots, and legacy QuillCode/Codex roots. `skills/list`
returns validated frontmatter plus optional `agents/openai.yaml` interface/tool metadata;
`skills/extraRoots/set` updates bounded per-session roots and emits `skills/changed`.
`skills/config/write` persistently enables or disables an exact manifest path or every skill sharing
a name. Desktop and CLI agents enforce the same selectors. Once a client lists skills, one bounded,
recursive session watcher invalidates cached catalogs and emits `skills/changed` when roots or files
change; it is cancelled at disconnect.

Nike 1.0 (`trustedrouter/fast`) is the default model. The only named presets are QuillCode’s branded TrustedRouter profiles: Nike 1.0 for fast everyday work, Zeus 1.0 for deep research, Prometheus 1.0 (`trustedrouter/fusion`) for freedom-oriented OSS deep research, Socrates 1.0 for coding-agent work, Aristotle 1.0 for smart general reasoning, and Plato 1.0 for freedom-oriented OSS coding. The picker searches the live TrustedRouter catalog when signed in, so raw provider/model IDs remain selectable without turning raw model types like synth into named defaults.

To exercise the live TrustedRouter adapter:

```bash
export TRUSTEDROUTER_API_KEY=sk-tr-v1-...
swift run quill-code --live "run whoami"
swift run quill-code --live --model trustedrouter/fast "make a file that says hello world"
swift run quill-code --live --model google/gemini-2.5-flash-lite --image screenshot.png "explain this UI"
swift run quill-code-desktop
```

Image attachments require a model whose TrustedRouter catalog metadata includes image input; QuillCode
keeps the selected model explicit rather than silently routing the image through a different model. The
live adapter asks the model for a strict QuillCode action JSON object, then routes that through the same
safety and tool executor path as the mock harness.

To store or clear the local developer key used by the desktop shell:

```bash
swift run quill-code auth set-key sk-tr-v1-...
swift run quill-code auth status
swift run quill-code auth clear
```

## Design Principles

- QuillCode is a standalone public repo, not private QuillConnect code.
- UI should use QuillUI/SwiftUI and keep platform differences behind adapter packages.
- App-facing code should not contain `#if linux`.
- “Full Access” is named **Auto** and uses reviewer-model gating instead of blind trust.
- Simple user commands must execute in one turn when policy allows.

## Docs

- [Decisions](docs/DECISIONS.md)
- [Codex Research](docs/CODEX_RESEARCH.md)
- [Parity Matrix](docs/CODEX_PARITY_MATRIX.md)
- [Roadmap](docs/ROADMAP.md)
- [Test Plan](docs/TEST_PLAN.md)
- [Worktree Setup](docs/WORKTREE_SETUP.md)
- [Merge Train](docs/MERGE_TRAIN.md)
- [Downloadable Builds](docs/DOWNLOADS.md)
