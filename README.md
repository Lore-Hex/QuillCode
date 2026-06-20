# QuillCode

QuillCode is a Swift and QuillUI coding agent inspired by Codex workflows and backed by TrustedRouter. The long-term target is a public, cross-platform macOS/Linux app with local project chat, tool execution, Computer Use, worktrees, plugins, automations, and browser-assisted development.

This initial repository contains the compile-stable foundation:

- core thread, tool, approval, project, model, and config types
- shell, file, and git tool executors
- Auto safety review policy with `glm-5.2` and `kimi-k2.6` model slots
- TrustedRouter LLM and safety-model adapters
- JSON thread persistence and a single secret-store protocol
- Computer Use backend protocol and stub backend
- deterministic mock LLM agent runner
- `quill-code` CLI harness
- `quill-code-desktop` SwiftUI workspace shell with persisted config/thread bootstrap
- Playwright mock UI harness
- parity, roadmap, decision, and test-plan docs

## Try It

```bash
swift test
swift run quill-code "run whoami"
swift run quill-code "make a file that says hello world"
swift run quill-code-desktop
cd E2E/playwright && npm install && npx playwright install chromium && npm test
```

The CLI and desktop shell use a deterministic mock LLM by default so tests and local demos do not require a TrustedRouter account.

To exercise the live TrustedRouter adapter:

```bash
export TRUSTEDROUTER_API_KEY=sk-tr-v1-...
swift run quill-code --live "run whoami"
swift run quill-code --live --model trustedrouter/fusion "make a file that says hello world"
```

The live adapter asks the model for a strict QuillCode action JSON object, then routes that through the same safety and tool executor path as the mock harness.

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
