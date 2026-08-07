# Downloadable Builds

Quill Cowork publishes automated tester builds from GitHub Actions.

## What To Send Testers

Send testers this moving prerelease link:

- [Quill Cowork Tester Build](https://github.com/Lore-Hex/QuillCode/releases/tag/tester-latest)

Direct asset links for the current tester channel:

- [macOS app: `Quill-Cowork-macOS-arm64.zip`](https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/Quill-Cowork-macOS-arm64.zip)
- [macOS CLI: `quill-code-macOS-arm64.tar.gz`](https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/quill-code-macOS-arm64.tar.gz)
- [Linux CLI: `quill-code-linux-x86_64.tar.gz`](https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/quill-code-linux-x86_64.tar.gz)
- [Checksums: `SHASUMS256.txt`](https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/SHASUMS256.txt)
- [Tester manifest: `latest-tester-build.json`](https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/latest-tester-build.json)
- [Stable manifest: `latest-stable-build.json`](https://github.com/Lore-Hex/QuillCode/releases/latest/download/latest-stable-build.json)

The build manifest is the app updater, website, and support script contract. It
records the build channel, tag, commit, workflow run URL, version, build number,
per-asset download URL, size, platform, architecture, and SHA-256 digest. It also
includes an `updater` object with the feed URL, bundle identifier, minimum macOS
version, signing/notarization status, and current macOS app asset.

## Build Cadence

The tester release is refreshed:

- after every successful push to `main`
- after merge-train PR merges, which explicitly dispatch **Download Builds**
- every night from the scheduled **Download Builds** workflow
- whenever a maintainer runs **Download Builds** manually from GitHub Actions

The workflow updates the stable `tester-latest` tag and replaces release assets
in place, so the links above do not change as new builds are published.

## Auto-Update Contract

The packaged macOS app embeds update metadata in `Info.plist`:

- `QuillCodeUpdateChannel`
- `QuillCodeUpdateManifestURL`
- `QuillCodeStableUpdateManifestURL`
- `QuillCodeTesterUpdateManifestURL`

The tester feed is:

```text
https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/latest-tester-build.json
```

The stable feed is:

```text
https://github.com/Lore-Hex/QuillCode/releases/latest/download/latest-stable-build.json
```

The macOS app checks this feed after launch, no more than every six hours on the
tester channel or daily on stable. **Check for Updates...** in the app menu runs
an immediate check. The updater compares `CFBundleShortVersionString` plus
`CFBundleVersion`, requires the configured repository, product, channel, bundle
identifier, architecture, and signing identity, downloads on demand, and verifies
the exact size, SHA-256 digest, app identity, version, architecture, and macOS code
signature before installation.

Installation stages the verified app beside the running bundle, then uses a
detached helper for the final rename and relaunch. The new app must complete a
launch handshake within 45 seconds. Otherwise the helper restores and reopens the
previous bundle. Background check failures stay quiet; user-initiated failures
remain visible and retain a direct browser-download fallback.

## Tester Install Notes

The macOS tester app is ad-hoc signed but not notarized yet. Testers may need to
right-click **Open** the first time. Computer Use still requires normal macOS
Screen Recording and Accessibility permissions.

Tester builds support the same user-initiated update and rollback flow. A stable
tag cannot publish a macOS app unless Developer ID signing and Apple notarization
are configured.

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

## Apple Distribution Credentials

The **Download Builds** workflow uses these repository secrets when present:

- `APPLE_DEVELOPER_ID_CERTIFICATE_BASE64`
- `APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD`
- `APPLE_DEVELOPER_ID_APPLICATION_IDENTITY`
- `APPLE_TEAM_ID`
- `APPLE_NOTARY_KEY_ID`
- `APPLE_NOTARY_ISSUER_ID`
- `APPLE_NOTARY_PRIVATE_KEY_BASE64`

The certificate secret is a base64-encoded Developer ID Application `.p12`. The
notary key secret is a base64-encoded App Store Connect API `.p8`. The workflow
imports both into a temporary runner-only signing area, enables the hardened
runtime, submits the zipped app to `notarytool`, staples and validates the ticket,
and deletes temporary credential files. Partial secret configuration fails the
macOS job. Missing secrets still permit ad-hoc tester builds, but stable `v*` tags
fail before packaging.

## Manual Build Refresh

Maintainers can refresh the tester channel without a code change:

```bash
gh workflow run download-builds.yml --repo Lore-Hex/QuillCode --ref main
```

Then watch it:

```bash
gh run list --repo Lore-Hex/QuillCode --workflow download-builds.yml --limit 1
```

The workflow publishes the same manifest schema for manual, scheduled, `main`,
and `v*` tag builds. For `v*` tags, the channel is `stable` and the asset is
`latest-stable-build.json`; for `tester-latest`, the channel is `tester` and the
asset is `latest-tester-build.json`.

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
