#!/usr/bin/env bash
set -euo pipefail

APP_ZIP=""
MANIFEST_PATH=""
SOURCE_MANIFEST_PATH=""
ARTIFACT_DIR="${QUILLCODE_UPDATER_SMOKE_ARTIFACT_DIR:-}"
TEMP_ROOT="${TMPDIR:-/tmp}"
SMOKE_ROOT="$(mktemp -d "${TEMP_ROOT%/}/quillcode-packaged-updater.XXXXXX")"
APP_PARENT="$SMOKE_ROOT/application"
REPORT_PATH="$SMOKE_ROOT/updater-stage.json"
LOG_PATH="$SMOKE_ROOT/updater.log"
UPDATED_PID=""

cleanup() {
  local status=$?
  local install_result_path
  local -a helper_log_candidates
  set +e
  if [[ -n "$UPDATED_PID" ]]; then
    kill "$UPDATED_PID" 2>/dev/null || true
    wait "$UPDATED_PID" 2>/dev/null || true
  fi
  if [[ -n "$ARTIFACT_DIR" ]]; then
    mkdir -p "$ARTIFACT_DIR"
    [[ -f "$REPORT_PATH" ]] && cp "$REPORT_PATH" "$ARTIFACT_DIR/updater-stage.json"
    [[ -f "$LOG_PATH" ]] && cp "$LOG_PATH" "$ARTIFACT_DIR/updater.log"
    [[ -n "$SOURCE_MANIFEST_PATH" && -f "$SOURCE_MANIFEST_PATH" ]] &&
      cp "$SOURCE_MANIFEST_PATH" "$ARTIFACT_DIR/source-manifest.json"
    install_result_path="$SMOKE_ROOT/home/Library/Application Support/co.lorehex.QuillCowork/UpdateResult.json"
    [[ -f "$install_result_path" ]] &&
      cp "$install_result_path" "$ARTIFACT_DIR/install-result.json"
    helper_log_candidates=(
      "$SMOKE_ROOT"/home/Library/Caches/co.lorehex.QuillCowork/Updates/*/install-*.log
    )
    if [[ ${#helper_log_candidates[@]} -eq 1 && -f "${helper_log_candidates[0]}" ]]; then
      cp "${helper_log_candidates[0]}" "$ARTIFACT_DIR/install-helper.log"
    fi
    printf 'status=%s\nsource_mode=%s\n' \
      "$status" "${SOURCE_MODE:-unknown}" > "$ARTIFACT_DIR/manifest.txt"
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
    --source-manifest)
      SOURCE_MANIFEST_PATH="$2"
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
if [[ ! -f "$APP_ZIP" || ! -f "$MANIFEST_PATH" ||
      ( -n "$SOURCE_MANIFEST_PATH" && ! -f "$SOURCE_MANIFEST_PATH" ) ]]; then
  echo "Usage: packaged-macos-updater-smoke.sh --app-zip APP_ZIP --manifest TARGET_JSON [--source-manifest SOURCE_JSON]" >&2
  exit 2
fi
if [[ "$MANIFEST_PATH" != /* ]]; then
  echo "Packaged updater smoke requires an absolute candidate manifest path." >&2
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

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

if [[ -n "$SOURCE_MANIFEST_PATH" ]]; then
  SOURCE_MODE="previous-public-build"
  SOURCE_VERSION="$(plutil -extract version raw "$SOURCE_MANIFEST_PATH")"
  SOURCE_BUILD="$(plutil -extract build raw "$SOURCE_MANIFEST_PATH")"
  SOURCE_COMMIT="$(plutil -extract commit raw "$SOURCE_MANIFEST_PATH")"
  SOURCE_CHANNEL="$(plutil -extract channel raw "$SOURCE_MANIFEST_PATH")"
  if [[ ! "$SOURCE_BUILD" =~ ^[0-9]+$ ]] || (( SOURCE_BUILD >= EXPECTED_BUILD )); then
    echo "Previous public updater source must have a lower numeric build." >&2
    exit 2
  fi
  if [[ ! "$SOURCE_COMMIT" =~ ^[0-9a-f]{40}$ || "$SOURCE_CHANNEL" != "$EXPECTED_CHANNEL" ]]; then
    echo "Previous public updater source has an invalid commit or channel." >&2
    exit 2
  fi
  ACTUAL_SOURCE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
  ACTUAL_SOURCE_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
  ACTUAL_SOURCE_COMMIT="$(/usr/libexec/PlistBuddy -c 'Print :QuillCodeBuildCommit' "$INFO_PLIST")"
  ACTUAL_SOURCE_CHANNEL="$(/usr/libexec/PlistBuddy -c 'Print :QuillCodeUpdateChannel' "$INFO_PLIST")"
  if [[ "$ACTUAL_SOURCE_VERSION" != "$SOURCE_VERSION" ||
        "$ACTUAL_SOURCE_BUILD" != "$SOURCE_BUILD" ||
        "$ACTUAL_SOURCE_COMMIT" != "$SOURCE_COMMIT" ||
        "$ACTUAL_SOURCE_CHANNEL" != "$SOURCE_CHANNEL" ]]; then
    echo "Previous public app metadata disagrees with its captured manifest." >&2
    exit 1
  fi
else
  SOURCE_MODE="synthetic-first-release"
  SOURCE_VERSION="$EXPECTED_VERSION"
  SOURCE_BUILD=$((EXPECTED_BUILD - 1))
  SOURCE_COMMIT="0000000000000000000000000000000000000000"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $SOURCE_BUILD" "$INFO_PLIST"
  /usr/libexec/PlistBuddy -c "Set :QuillCodeBuildCommit $SOURCE_COMMIT" "$INFO_PLIST"
  codesign --force --deep --sign - "$APP_BUNDLE"
  codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
fi

echo "==> Updating $SOURCE_MODE Quill Cowork $SOURCE_VERSION ($SOURCE_BUILD) to $EXPECTED_VERSION ($EXPECTED_BUILD)"
CFFIXED_USER_HOME="$SMOKE_ROOT/home" HOME="$SMOKE_ROOT/home" \
  "$APP_EXECUTABLE" \
    --native-updater-smoke \
    --updater-smoke-report "$REPORT_PATH" \
    --updater-smoke-manifest "$MANIFEST_PATH" \
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
   [[ "$(plutil -extract sourceVersion raw "$REPORT_PATH")" != "$SOURCE_VERSION" ]] ||
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

UPDATED_PIDS="$(pgrep -f "$EXECUTABLE_NAME --quillcode-update-handshake" || true)"
PUBLIC_APP_PARENT="${APP_PARENT#/private}"
for candidate_pid in $UPDATED_PIDS; do
  candidate_command="$(ps -p "$candidate_pid" -o command= 2>/dev/null || true)"
  if [[ "$candidate_command" == *"$APP_PARENT"* ||
        "$candidate_command" == *"$PUBLIC_APP_PARENT"* ]]; then
    UPDATED_PID="$candidate_pid"
    break
  fi
done
if [[ -z "$UPDATED_PID" ]] || ! kill -0 "$UPDATED_PID" 2>/dev/null; then
  echo "Updated app did not remain running after its launch handshake." >&2
  exit 1
fi

echo "Verified $SOURCE_MODE Quill Cowork updater: $SOURCE_BUILD -> $EXPECTED_BUILD ($EXPECTED_COMMIT)."
