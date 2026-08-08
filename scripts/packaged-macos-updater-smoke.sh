#!/usr/bin/env bash
set -euo pipefail

APP_ZIP=""
MANIFEST_PATH=""
ARTIFACT_DIR="${QUILLCODE_UPDATER_SMOKE_ARTIFACT_DIR:-}"
TEMP_ROOT="${TMPDIR:-/tmp}"
SMOKE_ROOT="$(mktemp -d "${TEMP_ROOT%/}/quillcode-packaged-updater.XXXXXX")"
APP_PARENT="$SMOKE_ROOT/application"
REPORT_PATH="$SMOKE_ROOT/updater-stage.json"
LOG_PATH="$SMOKE_ROOT/updater.log"
UPDATED_PID=""

cleanup() {
  local status=$?
  set +e
  if [[ -n "$UPDATED_PID" ]]; then
    kill "$UPDATED_PID" 2>/dev/null || true
    wait "$UPDATED_PID" 2>/dev/null || true
  fi
  if [[ -n "$ARTIFACT_DIR" ]]; then
    mkdir -p "$ARTIFACT_DIR"
    [[ -f "$REPORT_PATH" ]] && cp "$REPORT_PATH" "$ARTIFACT_DIR/updater-stage.json"
    [[ -f "$LOG_PATH" ]] && cp "$LOG_PATH" "$ARTIFACT_DIR/updater.log"
    printf 'status=%s\n' "$status" > "$ARTIFACT_DIR/manifest.txt"
  fi
  rm -rf "$SMOKE_ROOT"
  exit "$status"
}
trap cleanup EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-zip)
      APP_ZIP="$2"
      shift 2
      ;;
    --manifest)
      MANIFEST_PATH="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "packaged-macos-updater-smoke.sh must run on macOS." >&2
  exit 2
fi
if [[ ! -f "$APP_ZIP" || ! -f "$MANIFEST_PATH" ]]; then
  echo "Usage: packaged-macos-updater-smoke.sh --app-zip APP_ZIP --manifest MANIFEST_JSON" >&2
  exit 2
fi

EXPECTED_VERSION="$(plutil -extract version raw "$MANIFEST_PATH")"
EXPECTED_BUILD="$(plutil -extract build raw "$MANIFEST_PATH")"
EXPECTED_COMMIT="$(plutil -extract commit raw "$MANIFEST_PATH")"
EXPECTED_CHANNEL="$(plutil -extract channel raw "$MANIFEST_PATH")"
if [[ ! "$EXPECTED_BUILD" =~ ^[0-9]+$ ]] || (( EXPECTED_BUILD < 2 )); then
  echo "Published updater smoke requires a numeric build greater than one." >&2
  exit 2
fi
if [[ ! "$EXPECTED_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Published updater smoke manifest has an invalid commit." >&2
  exit 2
fi

mkdir -p "$APP_PARENT" "$SMOKE_ROOT/home"
ditto -x -k "$APP_ZIP" "$APP_PARENT"
APP_CANDIDATES=("$APP_PARENT"/*.app)
if [[ ${#APP_CANDIDATES[@]} -ne 1 || ! -d "${APP_CANDIDATES[0]}" ]]; then
  echo "Updater archive must contain exactly one top-level app bundle." >&2
  exit 1
fi
APP_BUNDLE="${APP_CANDIDATES[0]}"
APP_BASE_NAME="$(basename "$APP_BUNDLE" .app)"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST")"
APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
SOURCE_BUILD=$((EXPECTED_BUILD - 1))

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $SOURCE_BUILD" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :QuillCodeBuildCommit 0000000000000000000000000000000000000000" "$INFO_PLIST"
codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "==> Updating packaged Quill Cowork $EXPECTED_VERSION ($SOURCE_BUILD) to ($EXPECTED_BUILD)"
CFFIXED_USER_HOME="$SMOKE_ROOT/home" HOME="$SMOKE_ROOT/home" \
  "$APP_EXECUTABLE" \
    --native-updater-smoke \
    --updater-smoke-report "$REPORT_PATH" \
    >"$LOG_PATH" 2>&1 &
SMOKE_PID="$!"

elapsed=0
while kill -0 "$SMOKE_PID" 2>/dev/null; do
  if (( elapsed >= 180 )); then
    echo "Packaged updater smoke timed out while staging after 180 seconds." >&2
    kill "$SMOKE_PID" 2>/dev/null || true
    wait "$SMOKE_PID" 2>/dev/null || true
    exit 124
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done
if ! wait "$SMOKE_PID"; then
  cat "$LOG_PATH" >&2
  [[ -f "$REPORT_PATH" ]] && cat "$REPORT_PATH" >&2
  exit 1
fi

if [[ "$(plutil -extract ok raw "$REPORT_PATH")" != "true" ]] ||
   [[ "$(plutil -extract sourceBuild raw "$REPORT_PATH")" != "$SOURCE_BUILD" ]] ||
   [[ "$(plutil -extract targetBuild raw "$REPORT_PATH")" != "$EXPECTED_BUILD" ]] ||
   [[ "$(plutil -extract targetCommit raw "$REPORT_PATH")" != "$EXPECTED_COMMIT" ]]; then
  echo "Packaged updater smoke stage report disagrees with the public manifest." >&2
  cat "$REPORT_PATH" >&2
  exit 1
fi

elapsed=0
while true; do
  ACTUAL_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST" 2>/dev/null || true)"
  ACTUAL_COMMIT="$(/usr/libexec/PlistBuddy -c 'Print :QuillCodeBuildCommit' "$INFO_PLIST" 2>/dev/null || true)"
  STAGING_APPS=("$APP_PARENT"/."$APP_BASE_NAME".update-*.app)
  if [[ "$ACTUAL_BUILD" == "$EXPECTED_BUILD" &&
        "$ACTUAL_COMMIT" == "$EXPECTED_COMMIT" &&
        ! -e "${STAGING_APPS[0]}" ]]; then
    break
  fi
  if (( elapsed >= 60 )); then
    echo "Packaged updater helper did not activate and clean up within 60 seconds." >&2
    cat "$LOG_PATH" >&2
    exit 124
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done

ACTUAL_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
ACTUAL_CHANNEL="$(/usr/libexec/PlistBuddy -c 'Print :QuillCodeUpdateChannel' "$INFO_PLIST")"
if [[ "$ACTUAL_VERSION" != "$EXPECTED_VERSION" || "$ACTUAL_CHANNEL" != "$EXPECTED_CHANNEL" ]]; then
  echo "Activated app metadata disagrees with the public updater manifest." >&2
  exit 1
fi
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

UPDATED_PID="$(pgrep -f "$APP_EXECUTABLE --quillcode-update-handshake" | head -n 1 || true)"
if [[ -z "$UPDATED_PID" ]]; then
  echo "Updated app did not remain running after its launch handshake." >&2
  exit 1
fi

echo "Verified packaged Quill Cowork updater: $SOURCE_BUILD -> $EXPECTED_BUILD ($EXPECTED_COMMIT)."
