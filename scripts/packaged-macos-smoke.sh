#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SMOKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/quillcode-packaged-macos-smoke.XXXXXX")"
APP_OUTPUT_DIR="$SMOKE_ROOT/app"
APP_CONFIGURATION="${QUILLCODE_PACKAGED_MACOS_SMOKE_CONFIGURATION:-release}"
DIRECT_SMOKE_ARTIFACT_DIR="$SMOKE_ROOT/direct-executable"
LAUNCH_SERVICES_SMOKE_ARTIFACT_DIR="$SMOKE_ROOT/launch-services"
CLICK_PROBE_MANIFEST="$SMOKE_ROOT/packaged-click-probes.json"
ACCESSIBILITY_READINESS_MANIFEST="$SMOKE_ROOT/packaged-accessibility-readiness.json"
ACCESSIBILITY_FRAMES_MANIFEST="$SMOKE_ROOT/packaged-accessibility-frames.json"
SCHEDULED_COWORKER_MANIFEST="$SMOKE_ROOT/packaged-scheduled-coworker.json"
MULTI_FILE_ARTIFACT_MANIFEST="$SMOKE_ROOT/packaged-multi-file-artifact.json"
ONE_TURN_COWORKER_MANIFEST="$SMOKE_ROOT/packaged-one-turn-coworker.json"
BROWSER_WORKFLOW_MANIFEST="$SMOKE_ROOT/packaged-browser-workflow.json"
COMPUTER_USE_MANIFEST="$SMOKE_ROOT/packaged-computer-use.json"
COMPUTER_USE_ACTION_MANIFEST="$SMOKE_ROOT/packaged-computer-use-action.json"
PERFORMANCE_MANIFEST="$SMOKE_ROOT/packaged-performance.json"
PERFORMANCE_WINDOW_REPORT_PATH="$SMOKE_ROOT/performance-window-report.json"
PERFORMANCE_WINDOW_SCREENSHOT_PATH="$SMOKE_ROOT/performance-window.png"
PERFORMANCE_WINDOW_STATE_ROOT="$SMOKE_ROOT/performance-window-state"
COMPOSER_DRAFT_CRASH_STATE_ROOT="$SMOKE_ROOT/composer-draft-crash-state"
COMPOSER_DRAFT_CRASH_WRITE_LOG="$SMOKE_ROOT/composer-draft-crash-write.log"
COMPOSER_DRAFT_CRASH_VERIFY_LOG="$SMOKE_ROOT/composer-draft-crash-verify.log"
WINDOW_REPORT_PATH="$SMOKE_ROOT/window-report.json"
WINDOW_SCREENSHOT_PATH="$SMOKE_ROOT/window.png"
WINDOW_STATE_ROOT="$SMOKE_ROOT/window-state"
ARTIFACT_DIR="${QUILLCODE_PACKAGED_MACOS_SMOKE_ARTIFACT_DIR:-}"
WINDOW_SMOKE_TIMEOUT_SECONDS="${QUILLCODE_PACKAGED_WINDOW_SMOKE_TIMEOUT_SECONDS:-90}"

cleanup() {
  local status=$?
  set +e

  if [[ -n "$ARTIFACT_DIR" ]]; then
    mkdir -p "$ARTIFACT_DIR"
    if [[ -n "${INFO_PLIST:-}" && -e "$INFO_PLIST" ]]; then
      cp "$INFO_PLIST" "$ARTIFACT_DIR/Info.plist"
    fi
    if [[ -d "$DIRECT_SMOKE_ARTIFACT_DIR" ]]; then
      rm -rf "$ARTIFACT_DIR/direct-executable"
      cp -R "$DIRECT_SMOKE_ARTIFACT_DIR" "$ARTIFACT_DIR/direct-executable"
    fi
    if [[ -d "$LAUNCH_SERVICES_SMOKE_ARTIFACT_DIR" ]]; then
      rm -rf "$ARTIFACT_DIR/launch-services"
      cp -R "$LAUNCH_SERVICES_SMOKE_ARTIFACT_DIR" "$ARTIFACT_DIR/launch-services"
    fi
    if [[ -e "$CLICK_PROBE_MANIFEST" ]]; then
      cp "$CLICK_PROBE_MANIFEST" "$ARTIFACT_DIR/packaged-click-probes.json"
    fi
    if [[ -e "$ACCESSIBILITY_READINESS_MANIFEST" ]]; then
      cp "$ACCESSIBILITY_READINESS_MANIFEST" "$ARTIFACT_DIR/packaged-accessibility-readiness.json"
    fi
    if [[ -e "$ACCESSIBILITY_FRAMES_MANIFEST" ]]; then
      cp "$ACCESSIBILITY_FRAMES_MANIFEST" "$ARTIFACT_DIR/packaged-accessibility-frames.json"
    fi
    if [[ -e "$SCHEDULED_COWORKER_MANIFEST" ]]; then
      cp "$SCHEDULED_COWORKER_MANIFEST" "$ARTIFACT_DIR/packaged-scheduled-coworker.json"
    fi
    if [[ -e "$MULTI_FILE_ARTIFACT_MANIFEST" ]]; then
      cp "$MULTI_FILE_ARTIFACT_MANIFEST" "$ARTIFACT_DIR/packaged-multi-file-artifact.json"
    fi
    if [[ -e "$ONE_TURN_COWORKER_MANIFEST" ]]; then
      cp "$ONE_TURN_COWORKER_MANIFEST" "$ARTIFACT_DIR/packaged-one-turn-coworker.json"
    fi
    if [[ -e "$BROWSER_WORKFLOW_MANIFEST" ]]; then
      cp "$BROWSER_WORKFLOW_MANIFEST" "$ARTIFACT_DIR/packaged-browser-workflow.json"
    fi
    if [[ -e "$COMPUTER_USE_MANIFEST" ]]; then
      cp "$COMPUTER_USE_MANIFEST" "$ARTIFACT_DIR/packaged-computer-use.json"
    fi
    if [[ -e "$COMPUTER_USE_ACTION_MANIFEST" ]]; then
      cp "$COMPUTER_USE_ACTION_MANIFEST" "$ARTIFACT_DIR/packaged-computer-use-action.json"
    fi
    if [[ -e "$PERFORMANCE_MANIFEST" ]]; then
      cp "$PERFORMANCE_MANIFEST" "$ARTIFACT_DIR/packaged-performance.json"
    fi
    if [[ -e "$PERFORMANCE_WINDOW_REPORT_PATH" ]]; then
      cp "$PERFORMANCE_WINDOW_REPORT_PATH" "$ARTIFACT_DIR/performance-window-report.json"
    fi
    if [[ -e "$PERFORMANCE_WINDOW_SCREENSHOT_PATH" ]]; then
      cp "$PERFORMANCE_WINDOW_SCREENSHOT_PATH" "$ARTIFACT_DIR/performance-window.png"
    fi
    if [[ -e "$COMPOSER_DRAFT_CRASH_WRITE_LOG" ]]; then
      cp "$COMPOSER_DRAFT_CRASH_WRITE_LOG" "$ARTIFACT_DIR/composer-draft-crash-write.log"
    fi
    if [[ -e "$COMPOSER_DRAFT_CRASH_VERIFY_LOG" ]]; then
      cp "$COMPOSER_DRAFT_CRASH_VERIFY_LOG" "$ARTIFACT_DIR/composer-draft-crash-verify.log"
    fi
    if [[ -e "$WINDOW_REPORT_PATH" ]]; then
      cp "$WINDOW_REPORT_PATH" "$ARTIFACT_DIR/window-report.json"
    fi
    if [[ -e "$WINDOW_SCREENSHOT_PATH" ]]; then
      cp "$WINDOW_SCREENSHOT_PATH" "$ARTIFACT_DIR/window.png"
    fi
    {
      printf 'label=packaged macOS app\n'
      printf 'status=%s\n' "$status"
      printf 'source=%s\n' "$SMOKE_ROOT"
      if [[ -n "${APP_BUNDLE:-}" ]]; then
        printf 'app_bundle=%s\n' "$APP_BUNDLE"
      fi
      printf 'direct_smoke=direct-executable\n'
      printf 'launch_services_smoke=launch-services\n'
      printf 'click_probe_manifest=packaged-click-probes.json\n'
      printf 'accessibility_readiness_manifest=packaged-accessibility-readiness.json\n'
      printf 'accessibility_frames_manifest=packaged-accessibility-frames.json\n'
      printf 'scheduled_coworker_manifest=packaged-scheduled-coworker.json\n'
      printf 'multi_file_artifact_manifest=packaged-multi-file-artifact.json\n'
      printf 'one_turn_coworker_manifest=packaged-one-turn-coworker.json\n'
      printf 'browser_workflow_manifest=packaged-browser-workflow.json\n'
      printf 'computer_use_manifest=packaged-computer-use.json\n'
      printf 'computer_use_action_manifest=packaged-computer-use-action.json\n'
      printf 'performance_manifest=packaged-performance.json\n'
      printf 'performance_window_report=performance-window-report.json\n'
      printf 'performance_window_screenshot=performance-window.png\n'
      printf 'composer_draft_crash_write=composer-draft-crash-write.log\n'
      printf 'composer_draft_crash_verify=composer-draft-crash-verify.log\n'
      printf 'window_smoke=window-report.json\n'
      printf 'window_screenshot=window.png\n'
    } > "$ARTIFACT_DIR/manifest.txt"
    echo "Quill Cowork packaged macOS app smoke artifacts: $ARTIFACT_DIR"
  fi

  rm -rf "$SMOKE_ROOT"
  exit "$status"
}
trap cleanup EXIT

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "packaged-macos-smoke.sh must run on macOS." >&2
  exit 2
fi
if [[ ! "$WINDOW_SMOKE_TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
  echo "QUILLCODE_PACKAGED_WINDOW_SMOKE_TIMEOUT_SECONDS must be a positive integer." >&2
  exit 2
fi

cd "$ROOT_DIR"

echo "==> Building packaged macOS app"
APP_BUNDLE="$(
  "$ROOT_DIR/scripts/build-macos-app.sh" \
    --output "$APP_OUTPUT_DIR" \
    --configuration "$APP_CONFIGURATION"
)"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/Quill Cowork"
EXPECTED_BUILD_COMMIT="$(git rev-parse HEAD)"

assert_plist_value() {
  local key="$1"
  local expected="$2"
  local actual
  actual="$(/usr/libexec/PlistBuddy -c "Print :$key" "$INFO_PLIST")"
  if [[ "$actual" != "$expected" ]]; then
    echo "Packaged app Info.plist $key expected '$expected' but found '$actual'." >&2
    exit 1
  fi
}

wait_for_smoke_process() {
  local pid="$1"
  local timeout_seconds="$2"
  local label="$3"
  local elapsed=0

  while kill -0 "$pid" 2>/dev/null; do
    if [[ "$elapsed" -ge "$timeout_seconds" ]]; then
      echo "$label timed out after ${timeout_seconds}s." >&2
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  wait "$pid"
}

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Packaged app bundle was not created: $APP_BUNDLE" >&2
  exit 1
fi
if [[ ! -x "$APP_EXECUTABLE" ]]; then
  echo "Packaged app executable is missing or not executable: $APP_EXECUTABLE" >&2
  exit 1
fi

plutil -lint "$INFO_PLIST" >/dev/null
assert_plist_value CFBundleName "Quill Cowork"
assert_plist_value CFBundleDisplayName "Quill Cowork"
assert_plist_value CFBundleExecutable "Quill Cowork"
assert_plist_value CFBundleIdentifier co.lorehex.QuillCowork
assert_plist_value CFBundlePackageType APPL
assert_plist_value QuillCodeBuildCommit "$EXPECTED_BUILD_COMMIT"
assert_plist_value LSApplicationCategoryType public.app-category.developer-tools
assert_plist_value NSPrincipalClass NSApplication
assert_plist_value NSSupportsSuddenTermination false
assert_plist_value QuillCodeUpdateChannel tester
assert_plist_value QuillCodeUpdateManifestURL https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/latest-tester-build.json
assert_plist_value QuillCodeStableUpdateManifestURL https://github.com/Lore-Hex/QuillCode/releases/latest/download/latest-stable-build.json
assert_plist_value QuillCodeTesterUpdateManifestURL https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/latest-tester-build.json

echo "==> Running packaged composer draft SIGKILL recovery smoke"
"$APP_EXECUTABLE" \
  --composer-draft-crash-smoke \
  --composer-draft-crash-phase write \
  --composer-draft-crash-state-root "$COMPOSER_DRAFT_CRASH_STATE_ROOT" \
  >"$COMPOSER_DRAFT_CRASH_WRITE_LOG" 2>&1 &
COMPOSER_DRAFT_CRASH_PID="$!"
set +e
wait_for_smoke_process \
  "$COMPOSER_DRAFT_CRASH_PID" \
  15 \
  "Packaged composer draft SIGKILL writer"
COMPOSER_DRAFT_CRASH_STATUS="$?"
set -e
if [[ "$COMPOSER_DRAFT_CRASH_STATUS" -ne 137 ]]; then
  echo "Packaged composer draft writer expected SIGKILL status 137 but found $COMPOSER_DRAFT_CRASH_STATUS." >&2
  cat "$COMPOSER_DRAFT_CRASH_WRITE_LOG" >&2
  exit 1
fi

(
  "$APP_EXECUTABLE" \
    --composer-draft-crash-smoke \
    --composer-draft-crash-phase verify \
    --composer-draft-crash-state-root "$COMPOSER_DRAFT_CRASH_STATE_ROOT" \
    >"$COMPOSER_DRAFT_CRASH_VERIFY_LOG" 2>&1
) &
COMPOSER_DRAFT_VERIFY_PID="$!"
if ! wait_for_smoke_process \
  "$COMPOSER_DRAFT_VERIFY_PID" \
  15 \
  "Packaged composer draft recovery verifier"
then
  cat "$COMPOSER_DRAFT_CRASH_VERIFY_LOG" >&2
  exit 1
fi

QUILLCODE_DESKTOP_EXECUTABLE="$APP_EXECUTABLE" \
QUILLCODE_NATIVE_DESKTOP_SMOKE_LABEL="packaged macOS app" \
QUILLCODE_NATIVE_DESKTOP_SMOKE_ARTIFACT_DIR="$DIRECT_SMOKE_ARTIFACT_DIR" \
  "$ROOT_DIR/scripts/native-desktop-smoke.sh"

QUILLCODE_DESKTOP_APP_BUNDLE="$APP_BUNDLE" \
QUILLCODE_NATIVE_DESKTOP_SMOKE_LABEL="packaged macOS app Launch Services" \
QUILLCODE_NATIVE_DESKTOP_SMOKE_ARTIFACT_DIR="$LAUNCH_SERVICES_SMOKE_ARTIFACT_DIR" \
  "$ROOT_DIR/scripts/native-desktop-smoke.sh"

"$ROOT_DIR/scripts/native-click-probe-contracts.py" compare \
  "$DIRECT_SMOKE_ARTIFACT_DIR/report.json" \
  "$LAUNCH_SERVICES_SMOKE_ARTIFACT_DIR/report.json" \
  --manifest "$CLICK_PROBE_MANIFEST"

"$ROOT_DIR/scripts/native-click-probe-contracts.py" readiness \
  "$SMOKE_ROOT" \
  --manifest "$ACCESSIBILITY_READINESS_MANIFEST"

"$ROOT_DIR/scripts/native-click-probe-contracts.py" scheduled-coworker \
  "$DIRECT_SMOKE_ARTIFACT_DIR/report.json" \
  "$LAUNCH_SERVICES_SMOKE_ARTIFACT_DIR/report.json" \
  --manifest "$SCHEDULED_COWORKER_MANIFEST"

"$ROOT_DIR/scripts/native-click-probe-contracts.py" multi-file-artifact \
  "$DIRECT_SMOKE_ARTIFACT_DIR/report.json" \
  "$LAUNCH_SERVICES_SMOKE_ARTIFACT_DIR/report.json" \
  --manifest "$MULTI_FILE_ARTIFACT_MANIFEST"

"$ROOT_DIR/scripts/native-click-probe-contracts.py" one-turn-coworker \
  "$DIRECT_SMOKE_ARTIFACT_DIR/report.json" \
  "$LAUNCH_SERVICES_SMOKE_ARTIFACT_DIR/report.json" \
  --manifest "$ONE_TURN_COWORKER_MANIFEST"

"$ROOT_DIR/scripts/native-click-probe-contracts.py" browser-workflow \
  "$DIRECT_SMOKE_ARTIFACT_DIR/report.json" \
  "$LAUNCH_SERVICES_SMOKE_ARTIFACT_DIR/report.json" \
  --manifest "$BROWSER_WORKFLOW_MANIFEST"

echo "==> Running packaged macOS app live-window smoke"
(
  "$APP_EXECUTABLE" \
    --native-window-smoke \
    --window-smoke-report "$WINDOW_REPORT_PATH" \
    --window-smoke-screenshot "$WINDOW_SCREENSHOT_PATH" \
    --window-smoke-state-root "$WINDOW_STATE_ROOT" \
    >/dev/null
) &
WINDOW_SMOKE_PID="$!"
if ! wait_for_smoke_process \
  "$WINDOW_SMOKE_PID" \
  "$WINDOW_SMOKE_TIMEOUT_SECONDS" \
  "Packaged app live-window smoke"
then
  cat "$WINDOW_REPORT_PATH" >&2 2>/dev/null || true
  exit 1
fi

if [[ ! -s "$WINDOW_REPORT_PATH" ]]; then
  echo "Packaged app live-window smoke did not write a JSON report" >&2
  exit 1
fi
if [[ ! -s "$WINDOW_SCREENSHOT_PATH" ]]; then
  echo "Packaged app live-window smoke did not write a screenshot" >&2
  cat "$WINDOW_REPORT_PATH" >&2 || true
  exit 1
fi
"$ROOT_DIR/scripts/native-click-probe-contracts.py" frames \
  "$WINDOW_REPORT_PATH" \
  "$WINDOW_SCREENSHOT_PATH" \
  --click-probe-manifest "$CLICK_PROBE_MANIFEST" \
  --manifest "$ACCESSIBILITY_FRAMES_MANIFEST"

echo "==> Running packaged macOS app daily-driver performance window smoke"
"$APP_EXECUTABLE" \
  --seed-daily-driver-window-smoke \
  --window-smoke-state-root "$PERFORMANCE_WINDOW_STATE_ROOT" \
  >/dev/null
(
  "$APP_EXECUTABLE" \
    --native-window-smoke \
    --window-smoke-report "$PERFORMANCE_WINDOW_REPORT_PATH" \
    --window-smoke-screenshot "$PERFORMANCE_WINDOW_SCREENSHOT_PATH" \
    --window-smoke-state-root "$PERFORMANCE_WINDOW_STATE_ROOT" \
    --window-smoke-performance-workload "daily-driver-100-chats" \
    >/dev/null
) &
PERFORMANCE_WINDOW_SMOKE_PID="$!"
if ! wait_for_smoke_process \
  "$PERFORMANCE_WINDOW_SMOKE_PID" \
  "$WINDOW_SMOKE_TIMEOUT_SECONDS" \
  "Packaged app daily-driver performance window smoke"
then
  cat "$PERFORMANCE_WINDOW_REPORT_PATH" >&2 2>/dev/null || true
  exit 1
fi

if [[ ! -s "$PERFORMANCE_WINDOW_REPORT_PATH" ]]; then
  echo "Packaged app daily-driver performance smoke did not write a JSON report" >&2
  exit 1
fi
if [[ ! -s "$PERFORMANCE_WINDOW_SCREENSHOT_PATH" ]]; then
  echo "Packaged app daily-driver performance smoke did not write a screenshot" >&2
  cat "$PERFORMANCE_WINDOW_REPORT_PATH" >&2 || true
  exit 1
fi

"$ROOT_DIR/scripts/native-click-probe-contracts.py" performance \
  "$PERFORMANCE_WINDOW_REPORT_PATH" \
  --manifest "$PERFORMANCE_MANIFEST"

"$ROOT_DIR/scripts/native-click-probe-contracts.py" computer-use \
  "$DIRECT_SMOKE_ARTIFACT_DIR/report.json" \
  "$LAUNCH_SERVICES_SMOKE_ARTIFACT_DIR/report.json" \
  "$WINDOW_REPORT_PATH" \
  --click-probe-manifest "$CLICK_PROBE_MANIFEST" \
  --accessibility-frames-manifest "$ACCESSIBILITY_FRAMES_MANIFEST" \
  --manifest "$COMPUTER_USE_MANIFEST"

"$ROOT_DIR/scripts/native-click-probe-contracts.py" computer-use-action \
  "$DIRECT_SMOKE_ARTIFACT_DIR/report.json" \
  "$LAUNCH_SERVICES_SMOKE_ARTIFACT_DIR/report.json" \
  --manifest "$COMPUTER_USE_ACTION_MANIFEST"

echo "Quill Cowork packaged macOS app smoke passed."
