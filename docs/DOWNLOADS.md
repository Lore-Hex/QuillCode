# Downloadable Builds

QuillCode publishes automated tester builds from GitHub Actions.

## What To Send Testers

Send testers this moving prerelease link:

- [QuillCode Tester Build](https://github.com/Lore-Hex/QuillCode/releases/tag/tester-latest)

Direct asset links for the current tester channel:

- [macOS app: `QuillCode-macOS-arm64.zip`](https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/QuillCode-macOS-arm64.zip)
- [macOS CLI: `quill-code-macOS-arm64.tar.gz`](https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/quill-code-macOS-arm64.tar.gz)
- [Linux CLI: `quill-code-linux-x86_64.tar.gz`](https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/quill-code-linux-x86_64.tar.gz)
- [Checksums: `SHASUMS256.txt`](https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/SHASUMS256.txt)
- [Build manifest: `latest-tester-build.json`](https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/latest-tester-build.json)

The build manifest is intended for the website, updater experiments, and support
scripts. It records the build channel, tag, commit, workflow run URL, version,
build number, and per-asset download URL, size, platform, architecture, and
SHA-256 digest.

## Build Cadence

The tester release is refreshed:

- after every successful push to `main`
- after merge-train PR merges, which explicitly dispatch **Download Builds**
- every night from the scheduled **Download Builds** workflow
- whenever a maintainer runs **Download Builds** manually from GitHub Actions

The workflow updates the stable `tester-latest` tag and replaces release assets
in place, so the links above do not change as new builds are published.

## Tester Install Notes

The macOS tester app is ad-hoc signed but not notarized yet. Testers may need to
right-click **Open** the first time. Computer Use still requires normal macOS
Screen Recording and Accessibility permissions.

The app is still a tester build, so ask testers to include:

- their operating system and CPU architecture
- the `BUILD_INFO.txt` or `BUILD_INFO-linux-*.txt` asset contents
- what they clicked or typed before the issue
- a screenshot when the issue is visual

## Versioned Releases

Push a tag such as `v0.1.0` to create a versioned release with the same assets:

```bash
git tag v0.1.0
git push origin v0.1.0
```

Use versioned releases for public announcements. Use `tester-latest` for quick
iteration with early testers.

## Manual Build Refresh

Maintainers can refresh the tester channel without a code change:

```bash
gh workflow run download-builds.yml --repo Lore-Hex/QuillCode --ref main
```

Then watch it:

```bash
gh run list --repo Lore-Hex/QuillCode --workflow download-builds.yml --limit 1
```

The workflow publishes the same `latest-tester-build.json` schema for manual,
scheduled, `main`, and `v*` tag builds. For `v*` tags, the channel is `stable`;
for `tester-latest`, the channel is `tester`.

## Local Packaging

macOS app plus macOS CLI:

```bash
scripts/package-macos-downloads.sh
```

Linux CLI:

```bash
scripts/package-linux-downloads.sh
```

Both scripts write assets under `.build/downloads/.../assets` unless
`QUILLCODE_DOWNLOAD_DIST_DIR` is set.
