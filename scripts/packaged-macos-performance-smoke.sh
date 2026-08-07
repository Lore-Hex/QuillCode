#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE=""
MANIFEST_PATH=""
MAX_LAUNCH_READY_MILLISECONDS="${QUILLCODE_MAX_LAUNCH_READY_MILLISECONDS:-3000}"
MAX_RESIDENT_MEMORY_BYTES="${QUILLCODE_MAX_RESIDENT_MEMORY_BYTES:-268435456}"
SMOKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/quillcode-packaged-performance.XXXXXX")"
REPORT_PATH="$SMOKE_ROOT/window-report.json"
SCREENSHOT_PATH="$SMOKE_ROOT/window.png"
STATE_ROOT="$SMOKE_ROOT/window-state"

cleanup() {
  rm -rf "$SMOKE_ROOT"
}
trap cleanup EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP_BUNDLE="$2"
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
  echo "packaged-macos-performance-smoke.sh must run on macOS." >&2
  exit 2
fi
if [[ ! -d "$APP_BUNDLE" || -z "$MANIFEST_PATH" ]]; then
  echo "Usage: packaged-macos-performance-smoke.sh --app APP_BUNDLE --manifest OUTPUT_JSON" >&2
  exit 2
fi

INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST")"
APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
if [[ ! -x "$APP_EXECUTABLE" ]]; then
  echo "Packaged app executable is missing: $APP_EXECUTABLE" >&2
  exit 1
fi

echo "==> Measuring packaged Quill Cowork launch and resident memory"
"$APP_EXECUTABLE" \
  --native-window-smoke \
  --window-smoke-report "$REPORT_PATH" \
  --window-smoke-screenshot "$SCREENSHOT_PATH" \
  --window-smoke-state-root "$STATE_ROOT" \
  >/dev/null &
SMOKE_PID="$!"

elapsed=0
while kill -0 "$SMOKE_PID" 2>/dev/null; do
  if [[ "$elapsed" -ge 60 ]]; then
    echo "Packaged performance smoke timed out after 60s." >&2
    kill "$SMOKE_PID" 2>/dev/null || true
    wait "$SMOKE_PID" 2>/dev/null || true
    exit 124
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done
wait "$SMOKE_PID"

"$ROOT_DIR/scripts/native-click-probe-contracts.py" performance \
  "$REPORT_PATH" \
  --manifest "$MANIFEST_PATH" \
  --max-launch-ready-milliseconds "$MAX_LAUNCH_READY_MILLISECONDS" \
  --max-resident-memory-bytes "$MAX_RESIDENT_MEMORY_BYTES"
