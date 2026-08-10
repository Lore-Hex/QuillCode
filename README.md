# Quill Cowork

[![CI](https://github.com/Lore-Hex/QuillCode/actions/workflows/ci.yml/badge.svg)](https://github.com/Lore-Hex/QuillCode/actions/workflows/ci.yml)
[![Download Builds](https://github.com/Lore-Hex/QuillCode/actions/workflows/download-builds.yml/badge.svg)](https://github.com/Lore-Hex/QuillCode/actions/workflows/download-builds.yml)

**A 100% Swift coding agent and AI coworker for real project work.**

[Download for Apple silicon](https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/Quill-Cowork-macOS-arm64.dmg) · [Download for Intel](https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/Quill-Cowork-macOS-x86_64.dmg) · [Release notes and checksums](https://github.com/Lore-Hex/QuillCode/releases/tag/tester-latest)

![Quill Cowork showing a code review with TrustedRouter billing limits expanded](docs/images/quill-cowork-desktop.png)

Quill Cowork combines project-aware chat, local tools, Git workflows, Computer Use, automations,
plugins, and a full workspace terminal in one SwiftUI desktop app. The desktop app and agent runtime
are written entirely in Swift, with no Electron or web-app shell. Bounded background work,
persistent local state, and a verified updater with automatic rollback are built into that Swift
architecture.

## What You Can Do

- Build Swift projects with a coding agent whose application and agent runtime are themselves Swift.
- Work across multiple projects and chats with project instructions, memories, and context.
- Read, search, edit, and review files; run shell commands; inspect Git changes; and manage branches,
  worktrees, commits, pushes, and pull requests.
- Use the integrated terminal, browser session, screenshots, and macOS Computer Use controls.
- Run concurrent chats, side conversations, code reviews, scheduled automations, and reusable
  recorded workflows.
- Add skills, plugins, hooks, and MCP servers while keeping approvals and workspace boundaries
  visible.
- Choose from the live TrustedRouter model catalog or use Quill Cowork's named model profiles.
- Track TrustedRouter usage across daily, weekly, monthly, and total limits, then set a **Task Limit**
  directly from the top bar before a long-running task spends more than intended.

## Install on macOS

The current desktop build requires **macOS 14 or later** and supports Apple silicon and Intel Macs.

1. Download the latest Quill Cowork disk image for [Apple silicon](https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/Quill-Cowork-macOS-arm64.dmg) or [Intel](https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/Quill-Cowork-macOS-x86_64.dmg).
2. Open the disk image and drag **Quill Cowork.app** onto **Applications**, then eject it.
3. For the current tester build, right-click the app and choose **Open** on first launch if macOS
   blocks it. Tester builds are ad-hoc code-signed but are not Apple-notarized yet.
4. Sign in with TrustedRouter from the welcome screen, or add a developer key in **Settings**.

The [Apple silicon ZIP](https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/Quill-Cowork-macOS-arm64.zip)
and [Intel ZIP](https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/Quill-Cowork-macOS-x86_64.zip)
remain available as manual fallbacks and verified auto-update payloads.

Quill Cowork checks for updates automatically and also provides **Check for Updates...** in the app
menu. Downloads are size- and SHA-256-verified, the app identity and code signature are checked before
installation, the packaged source commit must match the public manifest, activation is atomic, and
the previous build is restored if the new build cannot finish launching. Use **Report an Issue...**
in the app menu to open a prefilled GitHub report with bounded build and system information; it does
not attach project paths, transcripts, or credentials. After an unexpected exit, the next successful
launch identifies whether the prior session ended during startup or while running, warns that active
command work may be incomplete, and offers the same privacy-safe report path.

## Downloads

| Platform | Artifact | Status |
| --- | --- | --- |
| macOS arm64 | [Quill Cowork app](https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/Quill-Cowork-macOS-arm64.dmg) | Tester preview |
| macOS x86_64 | [Quill Cowork app](https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/Quill-Cowork-macOS-x86_64.dmg) | Tester preview |
| macOS arm64 | [Quill Cowork CLI](https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/quill-code-macOS-arm64.tar.gz) | Tester preview |
| macOS x86_64 | [Quill Cowork CLI](https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/quill-code-macOS-x86_64.tar.gz) | Tester preview |
| Linux x86_64 | [Quill Cowork CLI](https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/quill-code-linux-x86_64.tar.gz) | Tester preview |

The moving `tester-latest` release is refreshed after verified main-branch changes. A scheduled
recovery check rebuilds only when the public manifest is missing, malformed, stale, or points at a
different commit. Direct links, the machine-readable build manifest, checksums, channel behavior,
and signing details are in [Downloadable Builds](docs/DOWNLOADS.md).

## Release Status

- **Tester:** public, automatically built from verified `main`, ad-hoc signed, self-updating.
- **Stable:** immutable versioned publication, Developer ID signing, notarization, and stable update
  feeds are implemented; the first stable release awaits the repository's Apple distribution
  credentials.

## Build from Source

Quill Cowork uses Swift 6 and Swift Package Manager.

```bash
swift test
swift run quill-code-desktop
swift run quill-code --mock "summarize this repository"
swift run quill-code doctor --summary
```

`quill-code` defaults to live TrustedRouter where the command requires a model. Pass `--mock` for a
deterministic local run, or configure a developer key with `swift run quill-code auth set-key KEY`.
The desktop app supports browser sign-in and developer-key management directly in Settings.

For the complete process-level test suite:

```bash
./scripts/smoke.sh
```

Agent changes merge through the serialized [Merge Train](docs/MERGE_TRAIN.md), which reruns CI and
publishes an exact-main tester build after every successful merge.

## Documentation

- [Downloadable Builds](docs/DOWNLOADS.md)
- [Roadmap](docs/ROADMAP.md)
- [Codex Parity Matrix](docs/CODEX_PARITY_MATRIX.md)
- [Test Plan](docs/TEST_PLAN.md)
- [Architecture Decisions](docs/DECISIONS.md)
- [Worktree Setup](docs/WORKTREE_SETUP.md)
- [Merge Train](docs/MERGE_TRAIN.md)
- [Support](SUPPORT.md)
- [Security Policy](SECURITY.md)
- [Contributing](CONTRIBUTING.md)

Quill Cowork is an independent open-source project inspired by the best workflows in Codex, Claude
Code, Cline, and other modern coding agents. It is licensed under the
[Apache License 2.0](LICENSE).
