#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE=""
MANIFEST_PATH=""
MAX_LAUNCH_READY_MILLISECONDS="${QUILLCODE_MAX_LAUNCH_READY_MILLISECONDS:-2500}"
MAX_RESIDENT_MEMORY_BYTES="${QUILLCODE_MAX_RESIDENT_MEMORY_BYTES:-134217728}"
MAX_RESIDENT_MEMORY_GROWTH_BYTES="${QUILLCODE_MAX_RESIDENT_MEMORY_GROWTH_BYTES:-67108864}"
MAX_REPEATED_RESIDENT_MEMORY_GROWTH_BYTES="${QUILLCODE_MAX_REPEATED_RESIDENT_MEMORY_GROWTH_BYTES:-16777216}"
MAX_THREAD_COUNT="${QUILLCODE_MAX_THREAD_COUNT:-32}"
MAX_REPEATED_RETAINED_THREAD_GROWTH="${QUILLCODE_MAX_REPEATED_RETAINED_THREAD_GROWTH:-2}"
MAX_IDLE_CPU_PERCENT="${QUILLCODE_MAX_IDLE_CPU_PERCENT:-5}"
MAX_IDLE_RESIDENT_MEMORY_GROWTH_BYTES="${QUILLCODE_MAX_IDLE_RESIDENT_MEMORY_GROWTH_BYTES:-8388608}"
MAX_IDLE_THREAD_GROWTH="${QUILLCODE_MAX_IDLE_THREAD_GROWTH:-2}"
ATTEMPT_TIMEOUT_SECONDS="${QUILLCODE_PACKAGED_PERFORMANCE_ATTEMPT_TIMEOUT_SECONDS:-180}"
ARTIFACT_DIR="${QUILLCODE_PACKAGED_PERFORMANCE_ARTIFACT_DIR:-}"
SMOKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/quillcode-packaged-performance.XXXXXX")"
PERFORMANCE_ATTEMPT_COUNT=3
SMOKE_PID=""

terminate_smoke_process() {
  if [[ -z "$SMOKE_PID" ]]; then
    return
  fi

  if kill -0 "$SMOKE_PID" 2>/dev/null; then
    kill "$SMOKE_PID" 2>/dev/null || true
    for ((shutdown_attempt = 0; shutdown_attempt < 5; shutdown_attempt += 1)); do
      if ! kill -0 "$SMOKE_PID" 2>/dev/null; then
        break
      fi
      sleep 1
    done
    if kill -0 "$SMOKE_PID" 2>/dev/null; then
      kill -KILL "$SMOKE_PID" 2>/dev/null || true
    fi
  fi
  wait "$SMOKE_PID" 2>/dev/null || true
  SMOKE_PID=""
}

cleanup() {
  terminate_smoke_process
  if [[ -n "$ARTIFACT_DIR" && -d "$ARTIFACT_DIR" ]]; then
    for ((artifact_attempt = 1; artifact_attempt <= PERFORMANCE_ATTEMPT_COUNT; artifact_attempt += 1)); do
      if [[ -f "$SMOKE_ROOT/window-report-$artifact_attempt.json" ]]; then
        cp "$SMOKE_ROOT/window-report-$artifact_attempt.json" \
          "$ARTIFACT_DIR/window-report-$artifact_attempt.json"
      fi
      if [[ -f "$SMOKE_ROOT/window-$artifact_attempt.png" ]]; then
        cp "$SMOKE_ROOT/window-$artifact_attempt.png" "$ARTIFACT_DIR/window-$artifact_attempt.png"
      fi
    done
  fi
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
if [[ ! "$ATTEMPT_TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
  echo "QUILLCODE_PACKAGED_PERFORMANCE_ATTEMPT_TIMEOUT_SECONDS must be a positive integer." >&2
  exit 2
fi
if [[ -n "$ARTIFACT_DIR" ]]; then
  if [[ -e "$ARTIFACT_DIR" || -L "$ARTIFACT_DIR" ]]; then
    echo "QUILLCODE_PACKAGED_PERFORMANCE_ARTIFACT_DIR must not already exist." >&2
    exit 2
  fi
  mkdir -p "$ARTIFACT_DIR"
fi

INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST")"
APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
if [[ ! -x "$APP_EXECUTABLE" ]]; then
  echo "Packaged app executable is missing: $APP_EXECUTABLE" >&2
  exit 1
fi

echo "==> Measuring packaged Quill Cowork launch and physical footprint"
REPORT_PATHS=()
for ((attempt = 1; attempt <= PERFORMANCE_ATTEMPT_COUNT; attempt += 1)); do
  REPORT_PATH="$SMOKE_ROOT/window-report-$attempt.json"
  SCREENSHOT_PATH="$SMOKE_ROOT/window-$attempt.png"
  STATE_ROOT="$SMOKE_ROOT/window-state-$attempt"
  echo "==> Packaged performance attempt $attempt/$PERFORMANCE_ATTEMPT_COUNT"
  "$APP_EXECUTABLE" \
    --seed-daily-driver-window-smoke \
    --window-smoke-state-root "$STATE_ROOT" \
    >/dev/null
  "$APP_EXECUTABLE" \
    --native-window-smoke \
    --window-smoke-report "$REPORT_PATH" \
    --window-smoke-screenshot "$SCREENSHOT_PATH" \
    --window-smoke-state-root "$STATE_ROOT" \
    --window-smoke-performance-workload "daily-driver-100-chats" \
    >/dev/null &
  SMOKE_PID="$!"

  elapsed=0
  while kill -0 "$SMOKE_PID" 2>/dev/null; do
    if [[ "$elapsed" -ge "$ATTEMPT_TIMEOUT_SECONDS" ]]; then
      echo "Packaged performance attempt $attempt exceeded its ${ATTEMPT_TIMEOUT_SECONDS}s wall-clock guard." >&2
      terminate_smoke_process
      exit 124
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  wait "$SMOKE_PID"
  SMOKE_PID=""
  REPORT_PATHS+=("$REPORT_PATH")
done

"$ROOT_DIR/scripts/native-click-probe-contracts.py" performance \
  "${REPORT_PATHS[@]}" \
  --manifest "$MANIFEST_PATH" \
  --max-launch-ready-milliseconds "$MAX_LAUNCH_READY_MILLISECONDS" \
  --max-resident-memory-bytes "$MAX_RESIDENT_MEMORY_BYTES" \
  --max-resident-memory-growth-bytes "$MAX_RESIDENT_MEMORY_GROWTH_BYTES" \
  --max-repeated-resident-memory-growth-bytes "$MAX_REPEATED_RESIDENT_MEMORY_GROWTH_BYTES" \
  --max-thread-count "$MAX_THREAD_COUNT" \
  --max-repeated-retained-thread-growth "$MAX_REPEATED_RETAINED_THREAD_GROWTH" \
  --max-idle-cpu-percent "$MAX_IDLE_CPU_PERCENT" \
  --max-idle-resident-memory-growth-bytes "$MAX_IDLE_RESIDENT_MEMORY_GROWTH_BYTES" \
  --max-idle-thread-growth "$MAX_IDLE_THREAD_GROWTH"
