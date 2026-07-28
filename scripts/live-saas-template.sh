#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -lt 2 ]]; then
  echo "usage: scripts/live-saas-template.sh <output.json> <catalog-task-id> [catalog-task-id ...]" >&2
  echo "optional env: QUILLCODE_LIVE_SAAS_SERVICE_NAME, QUILLCODE_LIVE_SAAS_TASK_NAME, QUILLCODE_LIVE_SAAS_URL" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_PATH="$1"
shift

ARGS=(
  "live-saas-template"
  "$@"
  "--output"
  "$OUTPUT_PATH"
)

if [[ -n "${QUILLCODE_LIVE_SAAS_SERVICE_NAME:-}" ]]; then
  ARGS+=("--service-name" "$QUILLCODE_LIVE_SAAS_SERVICE_NAME")
fi
if [[ -n "${QUILLCODE_LIVE_SAAS_TASK_NAME:-}" ]]; then
  ARGS+=("--task-name" "$QUILLCODE_LIVE_SAAS_TASK_NAME")
fi
if [[ -n "${QUILLCODE_LIVE_SAAS_URL:-}" ]]; then
  ARGS+=("--url" "$QUILLCODE_LIVE_SAAS_URL")
fi

"$ROOT_DIR/scripts/native-click-probe-contracts.py" "${ARGS[@]}"
