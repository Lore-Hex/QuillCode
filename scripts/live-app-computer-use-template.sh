#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -lt 2 ]]; then
  echo "usage: scripts/live-app-computer-use-template.sh <output.json> <catalog-task-id> [catalog-task-id ...]" >&2
  echo "optional env: QUILLCODE_LIVE_APP_NAME, QUILLCODE_LIVE_APP_TASK_NAME" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_PATH="$1"
shift

ARGS=(
  "live-app-computer-use-template"
  "$@"
  "--output"
  "$OUTPUT_PATH"
)

if [[ -n "${QUILLCODE_LIVE_APP_NAME:-}" ]]; then
  ARGS+=("--app-name" "$QUILLCODE_LIVE_APP_NAME")
fi
if [[ -n "${QUILLCODE_LIVE_APP_TASK_NAME:-}" ]]; then
  ARGS+=("--task-name" "$QUILLCODE_LIVE_APP_TASK_NAME")
fi

"$ROOT_DIR/scripts/native-click-probe-contracts.py" "${ARGS[@]}"
