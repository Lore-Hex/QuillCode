#!/usr/bin/env bash
set -euo pipefail

DMG=""
EXPECTED_ARCHITECTURE=""

usage() {
  cat <<'USAGE'
Usage: scripts/packaged-macos-relocation-smoke.sh --dmg PATH --expected-architecture ARCH

Mounts the packaged DMG read-only, moves Quill Cowork through its production
first-install helper, and requires a verified stable relaunch.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dmg)
      DMG="${2:-}"
      shift 2
      ;;
    --expected-architecture)
      EXPECTED_ARCHITECTURE="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$DMG" || ! -f "$DMG" ]]; then
  echo "A packaged DMG is required." >&2
  exit 2
fi
case "$EXPECTED_ARCHITECTURE" in
  arm64|x86_64) ;;
  *)
    echo "Expected architecture must be arm64 or x86_64." >&2
    exit 2
    ;;
esac
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "packaged-macos-relocation-smoke.sh must run on macOS." >&2
  exit 2
fi

SMOKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/quill-cowork-relocation.XXXXXX")"
MOUNT_POINT="$SMOKE_ROOT/mount"
APPLICATIONS="$SMOKE_ROOT/Applications"
HOME_ROOT="$SMOKE_ROOT/home"
PROCESS_TMP="$SMOKE_ROOT/tmp"
REPORT="$SMOKE_ROOT/relocation-report.json"
SOURCE_LOG="$SMOKE_ROOT/source.log"
MOUNTED=false
DESTINATION_EXECUTABLE="$APPLICATIONS/Quill Cowork.app/Contents/MacOS/Quill Cowork"

cleanup() {
  local status=$?
  set +e
  pkill -f "$DESTINATION_EXECUTABLE" >/dev/null 2>&1 || true
  if [[ "$MOUNTED" == true ]]; then
    hdiutil detach "$MOUNT_POINT" -force >/dev/null 2>&1 || true
  fi
  if [[ "$status" -ne 0 ]]; then
    cat "$SOURCE_LOG" >&2 2>/dev/null || true
    cat "$REPORT" >&2 2>/dev/null || true
  fi
  rm -rf "$SMOKE_ROOT"
  exit "$status"
}
trap cleanup EXIT

mkdir -p "$MOUNT_POINT" "$APPLICATIONS" "$HOME_ROOT" "$PROCESS_TMP"
hdiutil attach "$DMG" -readonly -nobrowse -mountpoint "$MOUNT_POINT" >/dev/null
MOUNTED=true

SOURCE_APP="$MOUNT_POINT/Quill Cowork.app"
SOURCE_EXECUTABLE="$SOURCE_APP/Contents/MacOS/Quill Cowork"
SOURCE_INFO="$SOURCE_APP/Contents/Info.plist"
if [[ ! -x "$SOURCE_EXECUTABLE" || ! -f "$SOURCE_INFO" ]]; then
  echo "Mounted DMG does not contain an executable Quill Cowork app." >&2
  exit 1
fi

echo "==> Verifying read-only DMG relocation and relaunch ($EXPECTED_ARCHITECTURE)"
CFFIXED_USER_HOME="$HOME_ROOT" \
HOME="$HOME_ROOT" \
TMPDIR="$PROCESS_TMP/" \
  "$SOURCE_EXECUTABLE" \
    --native-relocation-smoke \
    --relocation-smoke-applications "$APPLICATIONS" \
    --relocation-smoke-report "$REPORT" \
    >"$SOURCE_LOG" 2>&1 &
SOURCE_PID="$!"

elapsed=0
while kill -0 "$SOURCE_PID" 2>/dev/null; do
  if [[ "$elapsed" -ge 45 ]]; then
    echo "Mounted app did not hand off installation within 45 seconds." >&2
    kill "$SOURCE_PID" 2>/dev/null || true
    wait "$SOURCE_PID" 2>/dev/null || true
    exit 1
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done
if ! wait "$SOURCE_PID"; then
  echo "Mounted app failed during relocation staging." >&2
  exit 1
fi

if [[ ! -s "$REPORT" ]]; then
  echo "Relocation smoke did not write its report." >&2
  exit 1
fi
REPORT_STATUS="$(plutil -extract status raw -o - "$REPORT")"
if [[ "$REPORT_STATUS" != "helper-launched" ]]; then
  echo "Relocation helper was not launched successfully: $REPORT_STATUS" >&2
  exit 1
fi
RESULT_PATH="$(plutil -extract resultPath raw -o - "$REPORT")"
DESTINATION_APP="$(plutil -extract destinationApplicationPath raw -o - "$REPORT")"

elapsed=0
while [[ ! -s "$RESULT_PATH" ]]; do
  if [[ "$elapsed" -ge 60 ]]; then
    echo "Installation helper did not publish a result within 60 seconds." >&2
    exit 1
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done
RESULT_STATUS="$(plutil -extract status raw -o - "$RESULT_PATH")"
if [[ "$RESULT_STATUS" != "success" ]]; then
  echo "Installation helper reported failure: $RESULT_STATUS" >&2
  cat "$RESULT_PATH" >&2
  exit 1
fi

EXPECTED_DESTINATION_APP="$(cd "$APPLICATIONS" && pwd -P)/Quill Cowork.app"
REPORTED_DESTINATION_APP="$(
  cd "$(dirname "$DESTINATION_APP")"
  printf '%s/%s' "$(pwd -P)" "$(basename "$DESTINATION_APP")"
)"
if [[ "$REPORTED_DESTINATION_APP" != "$EXPECTED_DESTINATION_APP" ]]; then
  echo "Relocation report declared an unexpected destination: $DESTINATION_APP" >&2
  exit 1
fi

DESTINATION_INFO="$DESTINATION_APP/Contents/Info.plist"
if [[ ! -x "$DESTINATION_EXECUTABLE" || ! -f "$DESTINATION_INFO" ]]; then
  echo "Relocation did not produce a complete app bundle." >&2
  exit 1
fi
codesign --verify --deep --strict --verbose=2 "$DESTINATION_APP"
ARCHITECTURES="$(lipo -archs "$DESTINATION_EXECUTABLE")"
if [[ " $ARCHITECTURES " != *" $EXPECTED_ARCHITECTURE "* ]]; then
  echo "Relocated app does not contain $EXPECTED_ARCHITECTURE: $ARCHITECTURES" >&2
  exit 1
fi

SOURCE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SOURCE_INFO")"
SOURCE_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$SOURCE_INFO")"
SOURCE_COMMIT="$(/usr/libexec/PlistBuddy -c 'Print :QuillCodeBuildCommit' "$SOURCE_INFO")"
DESTINATION_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DESTINATION_INFO")"
DESTINATION_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$DESTINATION_INFO")"
DESTINATION_COMMIT="$(/usr/libexec/PlistBuddy -c 'Print :QuillCodeBuildCommit' "$DESTINATION_INFO")"
if [[ "$DESTINATION_VERSION" != "$SOURCE_VERSION" ||
      "$DESTINATION_BUILD" != "$SOURCE_BUILD" ||
      "$DESTINATION_COMMIT" != "$SOURCE_COMMIT" ]]; then
  echo "Relocated app identity does not match the mounted source." >&2
  exit 1
fi
if [[ ! "$DESTINATION_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Relocated app does not declare a canonical source commit." >&2
  exit 1
fi

echo "Quill Cowork packaged relocation smoke passed."
