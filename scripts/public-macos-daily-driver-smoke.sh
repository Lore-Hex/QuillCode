#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPOSITORY=""
EXPECTED_COMMIT=""
EXPECTED_ARCHITECTURE=""
EVIDENCE_DIR=""
GH_BIN="${GH_BIN:-gh}"
HDIUTIL_BIN="${HDIUTIL_BIN:-hdiutil}"
CODESIGN_BIN="${CODESIGN_BIN:-codesign}"
LIPO_BIN="${LIPO_BIN:-lipo}"
PLUTIL_BIN="${PLUTIL_BIN:-plutil}"
PLIST_BUDDY_BIN="${PLIST_BUDDY_BIN:-/usr/libexec/PlistBuddy}"
SHASUM_BIN="${SHASUM_BIN:-shasum}"
MAXIMUM_INSTALLER_BYTES=536870912

usage() {
  cat <<'USAGE'
Usage: scripts/public-macos-daily-driver-smoke.sh \
  --repo OWNER/REPOSITORY \
  --commit SHA \
  --expected-architecture arm64|x86_64 \
  --evidence-dir PATH

Downloads the public tester manifest and universal DMG, verifies their exact
identity and integrity, then runs the packaged 100-chat daily-driver workload.
USAGE
}

fail() {
  echo "$1" >&2
  exit "${2:-1}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPOSITORY="${2:-}"
      shift 2
      ;;
    --commit)
      EXPECTED_COMMIT="${2:-}"
      shift 2
      ;;
    --expected-architecture)
      EXPECTED_ARCHITECTURE="${2:-}"
      shift 2
      ;;
    --evidence-dir)
      EVIDENCE_DIR="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      fail "Unknown argument: $1" 2
      ;;
  esac
done

[[ "$(uname -s)" == "Darwin" ]] || fail "Public macOS daily-driver smoke must run on macOS." 2
[[ "$REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || \
  fail "Repository must use owner/name syntax." 2
[[ "$EXPECTED_COMMIT" =~ ^[0-9a-f]{40}$ ]] || \
  fail "Expected commit must be a lowercase 40-character SHA." 2
case "$EXPECTED_ARCHITECTURE" in
  arm64|x86_64) ;;
  *) fail "Expected architecture must be arm64 or x86_64." 2 ;;
esac
[[ "$(uname -m)" == "$EXPECTED_ARCHITECTURE" ]] || \
  fail "Runner architecture $(uname -m) does not match $EXPECTED_ARCHITECTURE." 2
[[ -n "$EVIDENCE_DIR" ]] || fail "An evidence directory is required." 2
[[ ! -e "$EVIDENCE_DIR" && ! -L "$EVIDENCE_DIR" ]] || \
  fail "Evidence directory must not already exist." 2

SMOKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/quill-cowork-public-daily-driver.XXXXXX")"
DOWNLOAD_DIR="$SMOKE_ROOT/downloads"
MOUNT_POINT="$SMOKE_ROOT/mount"
MOUNTED=false

cleanup() {
  local status=$?
  set +e
  if [[ "$MOUNTED" == true ]]; then
    "$HDIUTIL_BIN" detach "$MOUNT_POINT" -force >/dev/null 2>&1 || true
  fi
  rm -rf "$SMOKE_ROOT"
  exit "$status"
}
trap cleanup EXIT

mkdir -p "$DOWNLOAD_DIR" "$MOUNT_POINT" "$EVIDENCE_DIR"
"$GH_BIN" release download tester-latest \
  --repo "$REPOSITORY" \
  --pattern latest-tester-build.json \
  --dir "$DOWNLOAD_DIR"
"$GH_BIN" release download tester-latest \
  --repo "$REPOSITORY" \
  --pattern Quill-Cowork-macOS-universal.dmg \
  --dir "$DOWNLOAD_DIR"

MANIFEST_PATH="$DOWNLOAD_DIR/latest-tester-build.json"
DMG_PATH="$DOWNLOAD_DIR/Quill-Cowork-macOS-universal.dmg"
[[ -f "$MANIFEST_PATH" && ! -L "$MANIFEST_PATH" ]] || \
  fail "Public tester manifest was not downloaded as a regular file."
[[ -f "$DMG_PATH" && ! -L "$DMG_PATH" ]] || \
  fail "Public universal installer was not downloaded as a regular file."

manifest_value() {
  "$PLUTIL_BIN" -extract "$1" raw -o - "$MANIFEST_PATH"
}

assert_manifest_value() {
  local key="$1"
  local expected="$2"
  local actual
  actual="$(manifest_value "$key")" || fail "Public manifest is missing $key."
  [[ "$actual" == "$expected" ]] || \
    fail "Public manifest $key is $actual instead of $expected."
}

assert_manifest_value schemaVersion 1
assert_manifest_value product "Quill Cowork"
assert_manifest_value channel tester
assert_manifest_value tag tester-latest
assert_manifest_value commit "$EXPECTED_COMMIT"
assert_manifest_value updater.channel tester
assert_manifest_value updater.bundleIdentifier co.lorehex.QuillCowork
assert_manifest_value updater.macOSUniversalInstaller.name Quill-Cowork-macOS-universal.dmg
assert_manifest_value updater.macOSUniversalInstaller.platform macOS
assert_manifest_value updater.macOSUniversalInstaller.arch universal
assert_manifest_value updater.macOSUniversalInstaller.kind installer
assert_manifest_value updater.macOSUniversalInstaller.install dmg-app
assert_manifest_value updater.macOSUniversalInstaller.url \
  "https://github.com/$REPOSITORY/releases/download/tester-latest/Quill-Cowork-macOS-universal.dmg"

EXPECTED_VERSION="$(manifest_value version)"
EXPECTED_BUILD="$(manifest_value build)"
MINIMUM_SYSTEM_VERSION="$(manifest_value updater.minimumSystemVersion)"
EXPECTED_DMG_SIZE="$(manifest_value updater.macOSUniversalInstaller.sizeBytes)"
EXPECTED_DMG_SHA256="$(manifest_value updater.macOSUniversalInstaller.sha256)"
[[ "$EXPECTED_VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || \
  fail "Public manifest version is not canonical."
[[ "$EXPECTED_BUILD" =~ ^[1-9][0-9]*$ ]] || fail "Public manifest build is not positive."
[[ "$MINIMUM_SYSTEM_VERSION" =~ ^[0-9]+\.[0-9]+$ ]] || \
  fail "Public manifest minimum macOS version is invalid."
[[ "$EXPECTED_DMG_SIZE" =~ ^[1-9][0-9]*$ ]] || fail "Public installer size is invalid."
(( EXPECTED_DMG_SIZE <= MAXIMUM_INSTALLER_BYTES )) || fail "Public installer exceeds its size limit."
[[ "$EXPECTED_DMG_SHA256" =~ ^[0-9a-f]{64}$ ]] || fail "Public installer SHA-256 is invalid."

ACTUAL_DMG_SIZE="$(stat -f '%z' "$DMG_PATH")"
read -r ACTUAL_DMG_SHA256 _ < <("$SHASUM_BIN" -a 256 "$DMG_PATH")
[[ "$ACTUAL_DMG_SIZE" == "$EXPECTED_DMG_SIZE" ]] || \
  fail "Downloaded public installer size disagrees with its manifest."
[[ "$ACTUAL_DMG_SHA256" == "$EXPECTED_DMG_SHA256" ]] || \
  fail "Downloaded public installer SHA-256 disagrees with its manifest."

cp "$MANIFEST_PATH" "$EVIDENCE_DIR/public-manifest.json"
"$HDIUTIL_BIN" verify "$DMG_PATH" >/dev/null
"$HDIUTIL_BIN" attach "$DMG_PATH" -readonly -nobrowse -mountpoint "$MOUNT_POINT" >/dev/null
MOUNTED=true

APP_BUNDLE="$MOUNT_POINT/Quill Cowork.app"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/Quill Cowork"
SUPERVISOR="$APP_BUNDLE/Contents/Helpers/quill-code-process-supervisor"
[[ -d "$APP_BUNDLE" && ! -L "$APP_BUNDLE" ]] || fail "Public DMG has no regular Quill Cowork app."
[[ -f "$INFO_PLIST" && ! -L "$INFO_PLIST" ]] || fail "Public app has no regular Info.plist."
[[ -f "$APP_EXECUTABLE" && -x "$APP_EXECUTABLE" && ! -L "$APP_EXECUTABLE" ]] || \
  fail "Public app has no executable Quill Cowork binary."
[[ -f "$SUPERVISOR" && -x "$SUPERVISOR" && ! -L "$SUPERVISOR" ]] || \
  fail "Public app has no executable process supervisor."
[[ -L "$MOUNT_POINT/Applications" && "$(readlink "$MOUNT_POINT/Applications")" == "/Applications" ]] || \
  fail "Public DMG has no canonical Applications shortcut."
UNSAFE_ENTRY="$(find "$APP_BUNDLE" \( -type l -o \( ! -type d ! -type f \) \) -print -quit)" || \
  fail "Public app bundle could not be inspected."
if [[ -n "$UNSAFE_ENTRY" ]]; then
  fail "Public app contains a symlink or special filesystem entry."
fi
find "$APP_BUNDLE" -print0 > "$SMOKE_ROOT/app-inventory.bin" || \
  fail "Public app bundle inventory could not be read."
while IFS= read -r -d '' path; do
  [[ "$path" != *$'\n'* && "$path" != *$'\r'* ]] || fail "Public app contains an unsafe path."
done < "$SMOKE_ROOT/app-inventory.bin"

"$CODESIGN_BIN" --verify --deep --strict --verbose=2 "$APP_BUNDLE"
"$LIPO_BIN" "$APP_EXECUTABLE" -verify_arch arm64 x86_64
"$LIPO_BIN" "$SUPERVISOR" -verify_arch arm64 x86_64

plist_value() {
  "$PLIST_BUDDY_BIN" -c "Print :$1" "$INFO_PLIST"
}

assert_plist_value() {
  local key="$1"
  local expected="$2"
  local actual
  actual="$(plist_value "$key")" || fail "Public app Info.plist is missing $key."
  [[ "$actual" == "$expected" ]] || fail "Public app $key is $actual instead of $expected."
}

assert_plist_value CFBundleName "Quill Cowork"
assert_plist_value CFBundleDisplayName "Quill Cowork"
assert_plist_value CFBundleIdentifier co.lorehex.QuillCowork
assert_plist_value CFBundleExecutable "Quill Cowork"
assert_plist_value CFBundleShortVersionString "$EXPECTED_VERSION"
assert_plist_value CFBundleVersion "$EXPECTED_BUILD"
assert_plist_value LSMinimumSystemVersion "$MINIMUM_SYSTEM_VERSION"
assert_plist_value QuillCodeBuildCommit "$EXPECTED_COMMIT"
assert_plist_value QuillCodeUpdateChannel tester
assert_plist_value QuillCodeUpdateManifestURL \
  "https://github.com/$REPOSITORY/releases/download/tester-latest/latest-tester-build.json"

PERFORMANCE_PATH="$EVIDENCE_DIR/performance.json"
QUILLCODE_PACKAGED_PERFORMANCE_ARTIFACT_DIR="$EVIDENCE_DIR/attempts" \
  "$ROOT_DIR/scripts/packaged-macos-performance-smoke.sh" \
    --app "$APP_BUNDLE" \
    --manifest "$PERFORMANCE_PATH"

[[ "$("$PLUTIL_BIN" -extract ok raw -o - "$PERFORMANCE_PATH")" == "true" ]] || \
  fail "Public app daily-driver performance evidence is not successful."
[[ "$("$PLUTIL_BIN" -extract withinBudget raw -o - "$PERFORMANCE_PATH")" == "true" ]] || \
  fail "Public app daily-driver performance evidence exceeds its budget."
[[ "$("$PLUTIL_BIN" -extract product raw -o - "$PERFORMANCE_PATH")" == "Quill Cowork" ]] || \
  fail "Public app daily-driver evidence has the wrong product."
[[ "$("$PLUTIL_BIN" -extract workload raw -o - "$PERFORMANCE_PATH")" == "daily-driver-100-chats" ]] || \
  fail "Public app daily-driver evidence has the wrong workload."

LAUNCH_MILLISECONDS="$("$PLUTIL_BIN" -extract launchReadyMilliseconds raw -o - "$PERFORMANCE_PATH")"
INITIAL_MEMORY_MIB="$("$PLUTIL_BIN" -extract residentMemoryMiB raw -o - "$PERFORMANCE_PATH")"
REPEATED_MEMORY_MIB="$("$PLUTIL_BIN" -extract repeatedInteractionResidentMemoryMiB raw -o - "$PERFORMANCE_PATH")"
IDLE_CPU_PERCENT="$("$PLUTIL_BIN" -extract idleCPUPercent raw -o - "$PERFORMANCE_PATH")"
echo "Verified public Quill Cowork $EXPECTED_VERSION ($EXPECTED_BUILD) daily-driver runtime on $EXPECTED_ARCHITECTURE at $EXPECTED_COMMIT."
echo "Public daily-driver performance: ${LAUNCH_MILLISECONDS}ms launch-ready, ${INITIAL_MEMORY_MIB} MiB initial, ${REPEATED_MEMORY_MIB} MiB repeated, ${IDLE_CPU_PERCENT}% idle CPU."
