# Downloadable Builds

Quill Cowork publishes automated tester builds from GitHub Actions.

## What To Send Testers

Send ordinary Mac testers to the public website:

- [Quill Cowork](https://cowork.quillos.cloud/)

The website's primary download always uses the universal installer and works without JavaScript.
When GitHub's public release API is reachable, the page additionally shows the release update date
only after validating the release name, tester tag and state, exact commit shape, and the sole
universal installer's upload state, URL, size, and SHA-256 digest. A malformed, rate-limited, or
unavailable response leaves the known-good moving link and static installation guidance intact.

Send technical testers this moving prerelease link for provenance and secondary artifacts:

- [Quill Cowork Tester Build](https://github.com/Lore-Hex/QuillCode/releases/tag/tester-latest)

Direct asset links for the current tester channel:

- [Recommended Mac installer: `Quill-Cowork-macOS-universal.dmg`](https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/Quill-Cowork-macOS-universal.dmg)
  runs natively on Apple silicon and Intel.
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
commit-pinned product screenshot, one universal Mac installer, optional architecture-specific
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
version, signing/notarization status, the universal installer, and exact arm64
and x86_64 updater assets.
The legacy arm64 field remains present so already-installed tester builds continue
to update. The universal DMG is the recommended human installation path; the ZIP
remains the machine-verified updater payload so installation ergonomics cannot
change update semantics.
Every macOS `BUILD_INFO` also records `symbolsStripped=true` and the exact uncompressed
app-executable byte size. Release builds remove debug and local symbols before any ad-hoc or
Developer ID signature is applied. Public verification compares the declared size with the Mach-O
inside each downloaded app ZIP, so a skipped strip step, stale metadata, or post-sign mutation
cannot pass publication.

The website source lives in `website/` on `main`. `scripts/build-website.py` stages only its explicit
asset inventory plus the reviewed product screenshot, and `scripts/verify-website.py` rejects thin
architecture-specific primary installers, missing assets, unvalidated release metadata, custom-domain
drift, broken local references, symlinks, or payload growth beyond the static-site budget. Pull
request CI runs those contracts, and the Website workflow deploys the exact staged artifact through
GitHub's official Pages actions after the change reaches `main`.

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

## Tester Recovery: Unsaved Settings

If Quill Cowork reports that a settings change is not saved, keep the app open and retry the
change after checking available disk space and write access to the app-data directory. The app
keeps quick preference changes usable for the current session and protects the previous durable
configuration and TrustedRouter credential whenever recovery is possible. A successful retry for
the affected data clears the warning; an unrelated successful save does not hide it.

For a bug report, include the warning title, affected data labels, app version, and build number.
Do not include API keys, account details, filesystem paths, URLs, or raw private content. The
in-app diagnostic is deliberately content-free and should report `Private content included: No`.

## Credential Storage

Developer ID builds store desktop TrustedRouter credentials and MCP OAuth tokens in macOS Keychain.
Before enabling Keychain or migrating data, the app independently validates its running macOS code
signature and requires its team identifier to match the sealed packaging metadata. Missing,
invalid, or mismatched identity data keeps the hardened private-file backend active.
On first access, the app copies an existing private-file credential into Keychain only after the
protected write succeeds, then attempts to remove the old copy. A transient cleanup failure does not
hide the valid credential and cleanup is retried on the next read. Replacing or clearing a credential
follows the same ordered migration boundary so interruption cannot silently lose or restore a key.

The `tester-latest` app is currently ad-hoc signed. Because an ad-hoc identity changes with each
binary, tester builds intentionally retain the update-safe private `0600` file backend rather than
creating a Keychain item that the next build cannot access silently. The standalone CLI also keeps
an independent private store; configure it with `quill-code auth set-key KEY`. Keychain migration
activates automatically for the desktop when the Apple Developer ID signing secrets are configured
and the packaged identity passes runtime attestation.

When a signed-out user presses Send on a model-backed task, Quill Cowork preserves the complete draft
and any image attachments, then starts TrustedRouter sign-in instead of creating a failed transcript
turn. Local slash commands remain usable while signed out. Sign-in is single-flight, so repeated
buttons or Return presses reuse the active browser flow rather than starting competing loopback
listeners.

## Tester Recovery: Unexpected Exit

Packaged builds keep one private, content-free active-launch marker. A normal Quit or updater-driven
termination clears the matching marker. Update and Move & Relaunch exits synchronously flush pending
composer text and clear that marker before their bounded termination fallback. If the process
disappears after it was ready, the next launch shows **Quill Cowork closed unexpectedly** and warns
that an in-progress command may be incomplete. Choose **Continue** to return to the workspace or
**Report Issue...** to open a prefilled
crash report.

Packaged apps require graceful macOS termination rather than opting into sudden process death. This
ensures normal logout, shutdown, automatic termination, and explicit Quit cross the same marker-clearing
boundary; macOS cannot skip that cleanup and make an ordinary system action look like a crash.

If the process disappears before reaching its first-window startup boundary, the next launch opens
the saved workspace in recovery mode. Managed-worktree retention, pull-request reconciliation,
project indexing, due automations, account refreshes, and optional Computer Use driver discovery stay
paused instead of immediately repeating the same startup work. **Keep Background Work Paused** leaves
that work off for the current launch; **Resume Background Work** starts the normal idempotent service
set. Draft protection, updates, issue reporting, installation recovery, and explicit user actions
remain available in either choice.

The marker and report include only launch phase/time plus version, build, source commit, channel,
architecture, and macOS version. They do not include project paths, filenames, prompts, transcripts,
tool output, account details, or credentials. Live-process, stale, future-dated, unsafe, and graceful
termination records are ignored to avoid false crash notices.

Ordinary composer typing uses a private per-chat checkpoint after a 350-millisecond quiet interval.
Leaving Quill Cowork or quitting flushes pending text immediately. The checkpoint is a bounded small
record rather than a rewrite of the chat transcript, so long conversations do not turn autosave into
typing or memory pressure. A delayed checkpoint carries the chat identity from the keystroke boundary
and is rejected after a selection change, while a durable tombstone prevents sent or cleared text from
returning after relaunch. A first message without a chat owner has its own pending record and moves to
the created chat on send. Confidential and side-conversation drafts remain memory-only.

Parent-chat runs also carry a content-free generation checkpoint containing only a run identifier,
start time, and message/event boundaries. Tool and approval boundaries are saved durably, while
continuous tool output is coalesced so recovery does not turn streaming into a disk-write loop. If
the process disappears mid-run, bootstrap clears the dead generation, closes any Running tool card
as Failed, records one durable interruption notice, and offers **Review and retry** with a cautious
continuation prompt. A completed assistant answer or still-undecided approval gate is preserved
without a false failure. The packaged release smoke starts a real shell tool, kills the app with
`SIGKILL`, and relaunches the same bundle to verify this path end to end. Packaged shells run through
a tiny native supervisor that places the command and its descendants in an owned process group. A
Stop, timeout, terminal cancellation, or unexpected app exit terminates that whole group, with a
bounded `SIGKILL` fallback. The crash smoke records the live shell PID before killing the app and
refuses to pass recovery while that process is still alive, so transcript repair cannot hide an
orphaned side-effecting command.

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
builds are published. Immediately before changing that moving release, the
publisher fetches `origin/main` again. If another merge has superseded the
packaged commit, the run exits successfully without touching the tag, manifest,
or assets; the already queued run for the newer commit becomes the next publisher.
Immutable stable version tags are unaffected by this tester-channel freshness gate.

Tester asset replacement is also recoverable after the freshness decision. The publisher uploads
every candidate under a run-scoped temporary name, then requires GitHub's recorded size, upload
state, and SHA-256 digest to match the local artifact before any canonical download name changes.
Existing assets are renamed to rollback aliases instead of deleted; verified candidates take their
canonical names with the updater manifest swapped last. Release notes and target commit change only
after the complete asset inventory is present, and `tester-latest` moves last. A failure during
upload, asset exchange, metadata update, or tag push deletes candidates and restores the prior
asset names, release metadata, and remote tag, then verifies that restored snapshot. Rollback assets
are deleted with bounded retries only after the new metadata and tag both agree. This keeps a
transport or GitHub API failure from stranding an unrecoverable half-published tester channel.

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
runners. Before publication can begin, a read-only job captures the current public
manifest and both architecture-specific updater archives, verifies their GitHub and
manifest size/SHA-256 contracts, and stores them outside the release-asset input set.
After publication, each native runner launches that untouched previous public app
against the newly live feed. The gate requires the app
to stream, verify, unpack, validate, atomically replace, and relaunch itself; it
then checks the exact source and target metadata, activated version and source
commit, code signature, first-window-ready launch handshake, post-handshake process
stability, and staging cleanup. The acknowledgement is parsed at process entry but
is not written until the native workspace crosses the same ready boundary used for
unexpected-exit classification, so a replacement that hangs during bootstrap keeps
the previous build available for rollback. A channel with no
previous release uses an explicitly recorded synthetic one-build-behind fallback;
once a public source exists, metadata rewriting and re-signing are not allowed.
This catches cross-version compatibility failures that a self-update of newly built
code, manifest-only checks, and unit-level updater tests cannot prove.

The release-configured macOS app must also open a real native window within 2.5
seconds and remain below 128 MiB of resident memory at that initial-window
boundary. Each attempt atomically seeds and verifies one project with 100 saved
chats and a 200-message active transcript before timing the real packaged launch.
Release packaging measures three fresh processes with isolated state, requires at
least two launches to meet the time budget, and requires every memory sample to
meet its budget. The workload identity, median-launch attempt, every attempt,
thread counts, and enforced budgets ship as both architecture-specific
`PERFORMANCE.json` assets.

Each process then completes the packaged native interaction sweep twice, including
reversible navigation, sheet, search, model-picker, and text-entry checks. The gate
samples the same process after a one-second settling interval following each pass.
Both interaction snapshots must remain below 128 MiB, the first may retain no more
than 64 MiB above the initial-window sample, and the repeated pass may add no more
than another 16 MiB or 2 additional threads. All samples must stay at or below 32 threads.
After the repeated pass settles, each process also measures a two-second idle
window from macOS process user-plus-system CPU counters. Idle work must remain below
5% CPU, may retain no more than another 8 MiB, and may add no more than 2 threads.
The public performance asset records every raw snapshot, timing boundary, and signed
delta so a release cannot hide resource regressions behind a fast first frame,
one-time UI warming, or a background busy loop.
The post-publication verifier downloads both exact performance assets after their
checksums pass, requires the production schema and three-process aggregation,
recomputes every CPU/memory/thread delta and budget result, checks the median headline,
and rejects missing evidence or weakened production limits. Publication therefore
proves the public JSON's meaning as well as its bytes.
These native-baseline budgets leave operating headroom while catching regressions without
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

Startup recovery waits two minutes before removing abandoned updater staging apps. Starting a fresh
foreground update cancels and fully joins that recovery first, so cleanup can never remove the new
installer's live staging bundle.

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
direct **Move to Applications** action instead. It reuses the verified transactional
first-install helper, relaunches the current build from `/Applications`, waits for
the helper's launch-stability result, and automatically resumes the update check.
A short-lived, build-scoped continuation survives rollback so a restored source
copy can offer the move again even after an earlier reminder was dismissed. If
that relocation cannot be offered, the fallback uses only an architecture-matching
DMG whose bounded metadata and GitHub release URL passed the same manifest scope
checks. Its URL must use the declared `.dmg` filename exactly and cannot carry a
query or fragment; older manifests fall back to the release page.
The installer repeats the destination checks immediately before staging, so a
permission change after preflight still fails without replacing the app.

Every macOS download build also mounts its finished DMG read-only and drives the
production first-install helper into an isolated Applications directory. Publication
requires the detached helper to report a successful stable relaunch, preserve exact
version/build/commit identity, retain the expected native architecture, and pass a
strict recursive code-signature check.

Installation stages the verified app beside the running bundle, then uses a
detached helper for the final rename. It opens that exact bundle through Launch
Services as a new foreground instance, with running-app substitution disabled.
The new app must complete a
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

The update sheet's **Remind Me Tomorrow** action persists a bounded record for only the exact
channel, commit, version, and build being dismissed. Automatic checks keep their normal cadence so
a different build can appear immediately, while the same build stays quiet for 24 hours across app
restarts. At the deadline, the app presents the cached verified release without making a redundant
request. A user-initiated **Check for Updates...** clears the reminder. Expired, malformed,
oversized, mismatched, and implausibly future-dated records fail open and cannot suppress updates.
The reminder record contains public release identity only, never project or account data.

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
notarization declaration. Both native updater runners then install the previous
stable app, consume the candidate's versioned manifest, and prove update,
activation, relaunch, and launch stability while the candidate remains
non-latest. Only after both architectures pass does GitHub promote the candidate
to the stable latest feed. A final verifier requires GitHub's `releases/latest`
API object to identify the same release and requires the moving
`latest-stable-build.json` bytes to match the versioned manifest exactly.

If candidate verification or either native updater gate fails, the workflow
returns the new release to draft without changing the previous stable feed. If
the final feed verification fails after promotion, the workflow also returns the
new release to draft so GitHub falls back to the previous stable feed. Inspect
and delete that failed draft before retrying; an existing stable release is never
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

Before a stable workflow waits for CI or starts native packaging, its
`release-policy` job runs `scripts/validate-apple-distribution-credentials.sh`.
The preflight decodes credentials only inside a private temporary directory,
never prints their values, and removes every decoded file on success or failure.
It verifies the `.p12` password, certificate/private-key match, exact Developer
ID Application common name, code-signing usage, at least seven days of remaining
certificate validity, and an unencrypted PKCS#8 P-256 App Store Connect key. The
signing identity may be that exact certificate name or its 40-character SHA-1
identity hash; both remain pinned to `APPLE_TEAM_ID`. Base64 secrets must use
canonical unwrapped encoding. Legacy-encrypted Keychain `.p12` exports remain
supported without weakening the downstream identity checks.
Maintainers can run the same script locally with the seven variables above set
before uploading or rotating repository secrets.

This material check is deliberately separate from Apple authorization. GitHub
does not expose stored secret values to the release starter, and only Apple's
`notarytool` can prove that a configured key ID and issuer are still authorized.
The macOS runner therefore retains its private-keychain identity/team check and
the packaging jobs retain the real notarization, stapling, and validation gate.

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
