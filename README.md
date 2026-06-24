# QuillCode

QuillCode is a Swift and QuillUI coding agent inspired by Codex workflows and backed by TrustedRouter. The long-term target is a public, cross-platform macOS/Linux app with local project chat, tool execution, Computer Use, worktrees, plugins, automations, and browser-assisted development.

This initial repository contains the compile-stable foundation:

- core thread, tool, approval, project, model, and config types
- shell, file, and git tool executors
- Auto safety review policy with `glm-5.2` and `kimi-k2.6` model slots
- TrustedRouter LLM and safety-model adapters
- JSON thread/project persistence and a single secret-store protocol
- Computer Use backend protocol and stub backend
- deterministic mock LLM agent runner
- `quill-code` CLI harness
- `quill-code-desktop` SwiftUI workspace shell with persisted config/thread bootstrap, project rail, grouped model picker, and developer settings
- Playwright mock UI harness (test-only; any `node_modules` lives under `E2E/playwright` and is ignored)
- parity, roadmap, decision, and test-plan docs

## Try It

```bash
swift test
./scripts/smoke.sh
swift run quill-code "run whoami"
swift run quill-code "make a file that says hello world"
swift run quill-code auth status
swift run quill-code-desktop
cd E2E/playwright && npm install && npx playwright install chromium && npm test
```

`./scripts/smoke.sh` runs the Swift tests, exercises the mock CLI in a temporary workspace, verifies that file creation works without dirtying the repo, and runs Playwright automatically when `E2E/playwright/node_modules` is present.

Agent PRs should merge through the repo merge train instead of racing direct pushes to `main`. Open a PR, wait for CI, then add the `merge-train` label. See [Merge Train](docs/MERGE_TRAIN.md).

The CLI and desktop shell use a deterministic mock LLM by default so tests and local demos do not require a TrustedRouter account. The desktop shell switches to live TrustedRouter automatically when `QUILLCODE_API_KEY` or `TRUSTEDROUTER_API_KEY` is present, or when an API key is stored in the QuillCode secret store. With a key, the desktop shell also refreshes the TrustedRouter model catalog and groups provider/category/model choices in the top bar. The desktop Settings sheet can save, replace, or clear the local developer key and API base URL. Set `QUILLCODE_USE_MOCK_LLM=true` to force deterministic mock mode.

The default user-facing model is Nike 1.0 (`trustedrouter/fast`). Synth (`/synth`, `tr/synth`) is the next Recommended option for deeper coding and review turns, followed by Synth Code (`/synth-code`, `tr/synth-code`) for code-focused work. Legacy `trustedrouter/fusion`, `tr/fusion`, `/fusion`, `fusion-code`, and `/fusion-code` IDs remain valid aliases; new configs, slash commands, and picker surfaces prefer Synth naming.

To exercise the live TrustedRouter adapter:

```bash
export TRUSTEDROUTER_API_KEY=sk-tr-v1-...
swift run quill-code --live "run whoami"
swift run quill-code --live --model trustedrouter/fast "make a file that says hello world"
swift run quill-code-desktop
```

The live adapter asks the model for a strict QuillCode action JSON object, then routes that through the same safety and tool executor path as the mock harness.

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
- [Merge Train](docs/MERGE_TRAIN.md)
