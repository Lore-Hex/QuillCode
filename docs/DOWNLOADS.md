# Downloadable Builds

Quill Cowork publishes automated tester builds from GitHub Actions.

## What To Send Testers

Send testers this moving prerelease link:

- [Quill Cowork Tester Build](https://github.com/Lore-Hex/QuillCode/releases/tag/tester-latest)

Direct asset links for the current tester channel:

- [Apple silicon installer: `Quill-Cowork-macOS-arm64.dmg`](https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/Quill-Cowork-macOS-arm64.dmg)
- [Intel installer: `Quill-Cowork-macOS-x86_64.dmg`](https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/Quill-Cowork-macOS-x86_64.dmg)
- [Apple silicon updater archive: `Quill-Cowork-macOS-arm64.zip`](https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/Quill-Cowork-macOS-arm64.zip)
- [Intel updater archive: `Quill-Cowork-macOS-x86_64.zip`](https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/Quill-Cowork-macOS-x86_64.zip)
- [Apple silicon performance evidence: `Quill-Cowork-macOS-arm64-PERFORMANCE.json`](https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/Quill-Cowork-macOS-arm64-PERFORMANCE.json)
- [Intel performance evidence: `Quill-Cowork-macOS-x86_64-PERFORMANCE.json`](https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/Quill-Cowork-macOS-x86_64-PERFORMANCE.json)
- [Apple silicon CLI: `quill-code-macOS-arm64.tar.gz`](https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/quill-code-macOS-arm64.tar.gz)
- [Intel CLI: `quill-code-macOS-x86_64.tar.gz`](https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/quill-code-macOS-x86_64.tar.gz)
- [Linux CLI: `quill-code-linux-x86_64.tar.gz`](https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/quill-code-linux-x86_64.tar.gz)
- [Checksums: `SHASUMS256.txt`](https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/SHASUMS256.txt)
- [Tester manifest: `latest-tester-build.json`](https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/latest-tester-build.json)
- [Stable manifest: `latest-stable-build.json`](https://github.com/Lore-Hex/QuillCode/releases/latest/download/latest-stable-build.json)

The GitHub release page is generated from the packaged app's validated
`BUILD_INFO.txt`, not maintained as free-form workflow copy. It leads with a
commit-pinned product screenshot, explicit Apple silicon and Intel installer
links, the minimum macOS version, installation and Gatekeeper steps, automatic
update behavior, signing status, and exact source/build provenance. Secondary
CLI, updater, checksum, manifest, and performance assets remain available in a
collapsed section. Publication fails before a release is edited when the page's
channel, commit, version, build, platform, architecture, or signing claims do not
match the packaged app.

The build manifest is the app updater, website, and support script contract. It
records the build channel, tag, commit, workflow run URL, version, build number,
per-asset download URL, size, platform, architecture, and SHA-256 digest. It also
includes an `updater` object with the feed URL, bundle identifier, minimum macOS
version, signing/notarization status, and exact arm64 and x86_64 updater assets.
The legacy arm64 field remains present so already-installed tester builds continue
to update. The DMG is the recommended human installation path; the ZIP remains the
machine-verified updater payload so installation ergonomics cannot change update semantics.
Every macOS `BUILD_INFO` also records `symbolsStripped=true` and the exact uncompressed
app-executable byte size. Release builds remove debug and local symbols before any ad-hoc or
Developer ID signature is applied. Public verification compares the declared size with the Mach-O
inside each downloaded app ZIP, so a skipped strip step, stale metadata, or post-sign mutation
cannot pass publication.

When Quill Cowork is launched directly from the read-only DMG or another
non-replaceable location outside `/Applications`, it offers **Move & Relaunch**.
The app copies itself to `/Applications`, verifies its bundle identity, source
commit, architecture, and code signature, then quits and activates the copy through
the same detached helper used for updates. An existing Quill Cowork copy is swapped
atomically and restored if the new copy does not complete its launch handshake or
remain stable. A first install that fails is removed and the known-good mounted copy
reopens. Finder remains available as manual recovery. Dismissing the reminder
suppresses it for the current build; a newer build may remind the user again.
Writable installed copies do not show it. Installation guidance and available-update
state use one coordinated sheet, so they cannot overlap.

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

DMG construction is transactional and stage-aware. The packager creates each
candidate beside the destination, then verifies, mounts, inspects, signature-checks,
and detaches it before an atomic replacement. Transient macOS disk-image service
failures during create, verify, or attach receive up to three bounded attempts with
the exact failed stage in the log. Bundle-content and code-signature failures never
retry, and an exhausted attempt set leaves any prior installer untouched.

After publishing, a separate read-only job consumes the release through the
same public GitHub API and download URLs users receive. It resolves the release
tag to the expected commit, checks the exact release inventory and updater feed
contract, then downloads every declared asset with bounded streaming and
verifies GitHub's digest, manifest size/SHA-256, `SHASUMS256.txt`, and both native
build-info files. It reads each updater ZIP's bounded `Info.plist` and thin Mach-O
header, then requires the product identity, architecture, version, build, exact
source commit, channel, feed URLs, minimum macOS version, and signing team to agree
with the public manifest. A publication is not green until this consumer check passes.

A separate native post-publication gate runs on Apple silicon and Intel macOS
runners. Each downloads its matching public app archive, re-signs an isolated copy
with its build number set one revision behind, and launches the packaged updater
against the live feed. The gate requires the app
to stream, verify, unpack, validate, atomically replace, and relaunch itself; it
then checks the activated version and source commit, code signature, launch
handshake, and staging cleanup. This catches failures that manifest-only and
unit-level updater checks cannot prove.

The release-configured macOS app must also open a real native window within three
seconds and remain below 256 MiB of resident memory at that initial-window
boundary. Release packaging measures three fresh processes with isolated state,
requires at least two launches to meet the time budget, and requires every memory
sample to meet its budget. The median-launch attempt, every attempt, thread
counts, and enforced budgets ship as both architecture-specific `PERFORMANCE.json` assets.

Each process then completes the packaged native interaction sweep twice, including
reversible navigation, sheet, search, model-picker, and text-entry checks. The gate
samples the same process after a one-second settling interval following each pass.
Both interaction snapshots must remain below 256 MiB, the first may retain no more
than 80 MiB above the initial-window sample, and the repeated pass may add no more
than another 16 MiB or 4 additional threads. All three samples must stay at or below
64 threads. The public performance asset records every raw snapshot and signed delta
so a release cannot hide resource regressions behind a fast first frame or one-time
UI warming.
The post-publication verifier downloads both exact performance assets after their
checksums pass, requires the production schema and three-process aggregation,
recomputes every memory/thread delta and budget result, checks the median headline,
and rejects missing evidence or weakened production limits. Publication therefore
proves the public JSON's meaning as well as its bytes.
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
identifier, one exact current-architecture updater asset, and signing identity,
downloads on demand, and verifies
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

Every macOS download build also mounts its finished DMG read-only and drives the
production first-install helper into an isolated Applications directory. Publication
requires the detached helper to report a successful stable relaunch, preserve exact
version/build/commit identity, retain the expected native architecture, and pass a
strict recursive code-signature check.

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

If a saved-chat write or delete fails, the workspace shows a durability warning until a full
snapshot for each affected chat succeeds. The warning includes only the affected-chat count, never
the chat title, transcript, filesystem path, underlying error text, or credentials. Testers should
keep the app open while they free disk space, restore application-data permissions, or compact an
oversized chat, then make another change so Quill Cowork can retry the complete snapshot.

Project, automation, and saved-search write failures use the same durable-warning pattern. The
warning names only the affected data types and remains visible until each registry writes a complete
snapshot successfully. Testers should keep the app open, restore disk space or application-data
permissions, then change each affected data type again. Reports must not include private project
names, automation details, saved-search queries, filesystem paths, raw errors, or credentials.

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
asset, and exposes it first as a non-latest prerelease candidate. The public
consumer verifier must accept the candidate's exact inventory, hashes, bundle
metadata, CPU architectures, performance evidence, signing identity, and
notarization declaration before GitHub promotes it to the stable latest feed.
Both native updater runners then install and relaunch through that live feed.
A final verifier requires GitHub's `releases/latest` API object to identify the
same release and requires the moving `latest-stable-build.json` bytes to match
the versioned manifest exactly.

If candidate verification fails, the workflow returns the new release to draft
without changing the previous stable feed. If either native updater gate or the
final feed verification fails after promotion, the workflow also returns the new
release to draft so GitHub falls back to the previous stable feed. Inspect and
delete that failed draft before retrying; an existing stable release is never
edited or clobbered automatically. Treat a versioned release as announced only
after the complete **Download Builds** run is green.
Pre-existing stable releases remain untouched throughout this recovery flow.

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
and deletes temporary credential files. `APPLE_TEAM_ID` and
`APPLE_NOTARY_KEY_ID` must be their 10-character uppercase Apple identifiers;
`APPLE_NOTARY_ISSUER_ID` must be the App Store Connect issuer UUID. The imported
Developer ID identity must resolve inside the private build keychain and belong
to `APPLE_TEAM_ID`.

Partial configuration and malformed identifiers fail before decoded files are
created. Once files can exist, any setup failure deletes the private keychain and
complete signing directory locally; only successful setup transfers cleanup
ownership to the workflow's unconditional cleanup step. Missing secrets still
permit ad-hoc tester builds, but stable `v*` tags fail before packaging.

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
The macOS script packages the current machine architecture; the GitHub release
workflow runs it independently on native Apple silicon and Intel runners.
