# Downloadable Builds

Quill Cowork publishes automated tester builds from GitHub Actions.

## What To Send Testers

Send testers this moving prerelease link:

- [Quill Cowork Tester Build](https://github.com/Lore-Hex/QuillCode/releases/tag/tester-latest)

Direct asset links for the current tester channel:

- [macOS installer: `Quill-Cowork-macOS-arm64.dmg`](https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/Quill-Cowork-macOS-arm64.dmg)
- [macOS updater archive: `Quill-Cowork-macOS-arm64.zip`](https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/Quill-Cowork-macOS-arm64.zip)
- [macOS performance evidence: `Quill-Cowork-macOS-arm64-PERFORMANCE.json`](https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/Quill-Cowork-macOS-arm64-PERFORMANCE.json)
- [macOS CLI: `quill-code-macOS-arm64.tar.gz`](https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/quill-code-macOS-arm64.tar.gz)
- [Linux CLI: `quill-code-linux-x86_64.tar.gz`](https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/quill-code-linux-x86_64.tar.gz)
- [Checksums: `SHASUMS256.txt`](https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/SHASUMS256.txt)
- [Tester manifest: `latest-tester-build.json`](https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/latest-tester-build.json)
- [Stable manifest: `latest-stable-build.json`](https://github.com/Lore-Hex/QuillCode/releases/latest/download/latest-stable-build.json)

The build manifest is the app updater, website, and support script contract. It
records the build channel, tag, commit, workflow run URL, version, build number,
per-asset download URL, size, platform, architecture, and SHA-256 digest. It also
includes an `updater` object with the feed URL, bundle identifier, minimum macOS
version, signing/notarization status, and current macOS updater asset. The DMG
is the recommended human installation path; the ZIP remains the machine-verified
updater payload so installation ergonomics cannot change update semantics.

When Quill Cowork is launched directly from the read-only DMG or another
non-replaceable location outside `/Applications`, it immediately offers to open
`/Applications`. Dismissing that reminder suppresses it for the current build; a
newer build may remind the user again. Installed copies already in `/Applications`
do not show it. Installation guidance and available-update state use one coordinated
sheet, so they cannot overlap.

## Build Cadence

The tester release is refreshed:

- after every successful push to `main`
- after merge-train PR merges, which explicitly dispatch **Download Builds**
- from the nightly **Download Builds** recovery check when the published tester
  manifest is missing, malformed, stale, points to another `main` commit, or
  names a publishing run that is unavailable, incomplete, failed, or mismatched
- whenever a maintainer runs **Download Builds** manually from GitHub Actions

Before packaging starts, **Download Builds** waits up to 30 minutes for a
successful **CI** run whose commit and branch are exactly the requested `main`
build. Pull-request CI, another branch, another commit, or a failed/cancelled run
cannot authorize publication. The gate also covers merge-train, push, scheduled,
manual, and stable-tag entrypoints, so a red or untested main commit cannot race
ahead into the public updater feed.

The nightly check skips packaging only when the live manifest publishes the
current `main` commit and its exact **Download Builds** run completed successfully
on that commit. This avoids no-op build-number updates and unnecessary updater
prompts without treating a partial publication as healthy.
When a build is required, the workflow updates the stable `tester-latest` tag
and replaces release assets in place, so the links above do not change as new
builds are published.

After publishing, a separate read-only job consumes the release through the
same public GitHub API and download URLs users receive. It resolves the release
tag to the expected commit, checks the exact release inventory and updater feed
contract, then downloads every declared asset with bounded streaming and
verifies GitHub's digest, manifest size/SHA-256, `SHASUMS256.txt`, and
`BUILD_INFO.txt`. It also reads the updater ZIP's bounded `Info.plist` and requires
the product identity, version, build, exact source commit, channel, feed URLs,
minimum macOS version, and signing team to agree with the public manifest. A
publication is not green until this consumer check passes.

A separate macOS post-publication gate downloads that exact public app archive,
re-signs an isolated copy with its build number set one revision behind, and
launches the packaged updater against the live feed. The gate requires the app
to stream, verify, unpack, validate, atomically replace, and relaunch itself; it
then checks the activated version and source commit, code signature, launch
handshake, and staging cleanup. This catches failures that manifest-only and
unit-level updater checks cannot prove.

The release-configured macOS app must also open a real native window within three
seconds and remain below 256 MiB of resident memory at that initial-window
boundary. Release packaging measures three fresh processes with isolated state,
requires at least two launches to meet the time budget, and requires every memory
sample to meet its budget. The median-launch attempt, every attempt, thread
counts, and enforced budgets ship as the architecture-specific `PERFORMANCE.json` asset.

Each process then completes the packaged native interaction sweep twice, including
reversible navigation, sheet, search, model-picker, and text-entry checks. The gate
samples the same process after a one-second settling interval following each pass.
Both interaction snapshots must remain below 256 MiB, the first may retain no more
than 80 MiB above the initial-window sample, and the repeated pass may add no more
than another 16 MiB or 4 additional threads. All three samples must stay at or below
64 threads. The public performance asset records every raw snapshot and signed delta
so a release cannot hide resource regressions behind a fast first frame or one-time
UI warming.
These intentionally conservative first budgets catch major regressions without
turning one loaded-runner outlier into the product metric.

## Auto-Update Contract

The packaged macOS app embeds update metadata in `Info.plist`:

- `QuillCodeBuildCommit`
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

The manifest's `updater.manifestURL` is the same moving channel feed embedded
in the app: `tester-latest` for tester builds and `releases/latest` for stable
builds. Manifest generation fails when `BUILD_INFO.txt` and this feed identity
disagree, because the app intentionally rejects a manifest from any other URL.

The macOS app starts checking this feed after launch and remains scheduled while
the app stays open: every six hours on the tester channel or daily on stable.
**Check for Updates...** in the app menu runs an immediate check and resets the
next automatic due time when it succeeds. Quiet background failures retry after
30 minutes; visible update UI or an active foreground update defers background
work for five minutes. The updater compares `CFBundleShortVersionString` plus
`CFBundleVersion`, requires the configured repository, product, channel, bundle
identifier, architecture, and signing identity, downloads on demand, and verifies
the exact size, SHA-256 digest, app identity, version, embedded source commit,
architecture, and macOS code signature before installation. The detached helper
checks that same commit again immediately before the atomic swap.

Signing metadata is also a payload requirement, not only a feed label. Ad-hoc
updates must contain an actual ad-hoc signature with no team. A Developer ID
update must declare a valid team, be notarized, contain a Developer ID Application
authority for that same team, and pass Gatekeeper assessment. The first such
update from an ad-hoc tester pins its embedded team; signed builds reject later
ad-hoc downgrades and any other team.

Archive bytes stream directly to an updater-owned partial file instead of being
buffered in memory. A declared oversized response is rejected immediately; a
chunked response is cancelled at the first chunk that would exceed the manifest
size. Cancellation and failure remove the partial file. The update sheet reports
bounded determinate byte progress, then identifies the verification, unpacking,
and app-validation phases separately.

Before downloading, the app verifies that its running bundle exists beside a
writable destination and has a runnable helper executable. Copies launched from
the read-only DMG, App Translocation, or another non-replaceable location show a
direct **Download Installer** action instead. That action uses only an
architecture-matching DMG whose bounded metadata and GitHub release URL passed
the same manifest scope checks. Its URL must use the declared `.dmg` filename
exactly and cannot carry a query or fragment; older manifests fall back to the release page.
The installer repeats the destination checks immediately before staging, so a
permission change after preflight still fails without replacing the app.

Installation stages the verified app beside the running bundle, then uses a
detached helper for the final rename and relaunch. The new app must complete a
launch handshake within 45 seconds and remain running for a three-second startup
observation window. If either check fails, the helper restores and reopens the
previous bundle. The one-shot install result is read only when it is a regular,
non-symlink file no larger than 64 KiB; malformed or unexpected entries are
discarded. Background check failures stay quiet; user-initiated failures remain
visible and retain direct retry and browser-download actions. Repeated menu checks
cannot cancel an active download or the non-cancellable activation phase, and a
background result never replaces update UI that is already visible. Failed or
cancelled preparation removes its cache workspace immediately. After a two-minute
active-helper grace period on launch, the app also removes only its exact hidden
`.Quill Cowork.update-<lowercase UUID>.app` sibling directories left by an
interrupted install; symlinks, lookalikes, and unexpected app identities are never
treated as updater-owned staging.

## Tester Install Notes

The macOS tester app is ad-hoc signed but not notarized yet. Testers may need to
right-click **Open** the first time. Computer Use still requires normal macOS
Screen Recording and Accessibility permissions.

Tester builds support the same user-initiated update and rollback flow. A stable
tag cannot publish a macOS app unless Developer ID signing and Apple notarization
are configured.

The app is still a tester build. **Report an Issue...** in the app menu opens a
GitHub report prefilled only with the app version, build, source commit, channel,
macOS version, and architecture. It does not include workspace paths, transcripts,
or credentials. Ask testers to add:

- what they clicked or typed before the issue
- a screenshot when the issue is visual

## Versioned Releases

Stable releases are immutable and must use a canonical `vMAJOR.MINOR.PATCH` tag
pointing to a commit on `main` with a successful **CI** run. Use the fail-closed
release starter instead of creating a tag by hand:

```bash
git switch main
git pull --ff-only origin main
scripts/start-stable-release.sh --check-only v0.1.0
scripts/start-stable-release.sh v0.1.0
```

The preflight verifies the canonical and monotonically increasing version, exact
clean `origin/main`, expected GitHub remote and public repository, successful
exact-commit CI, a `tester-latest` tag and prerelease at the same commit, no
existing local/remote tag or release, and all required Apple distribution secret
names. The final command creates one annotated tag and pushes it without force.
If that push fails, the command removes only the local tag it just created.

The workflow rejects tags that are malformed, off `main`, missing successful CI,
or already published. It creates the stable release as a draft, uploads every
asset, and only then publishes it as the latest release. If a stable publish
fails after creating its draft, inspect and delete that draft before retrying;
an existing stable release is never edited or clobbered automatically.

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

To re-run the public consumer verification for a known publication:

```bash
scripts/verify-published-release.py \
  --repo Lore-Hex/QuillCode \
  --tag tester-latest \
  --channel tester \
  --commit "$COMMIT" \
  --workflow-run-url "$WORKFLOW_RUN_URL"
```

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
