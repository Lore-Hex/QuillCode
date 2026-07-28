#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -lt 2 ]]; then
  echo "usage: scripts/safety-reviewer-calibration-rollup.sh <output.json> <manifest.json> [manifest.json ...]" >&2
  echo "optional env: QUILLCODE_SAFETY_REVIEWER_CALIBRATION_MARKDOWN_OUTPUT" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_PATH="$1"
shift

ARGS=(
  "safety-reviewer-calibration-rollup"
  "$@"
  "--output"
  "$OUTPUT_PATH"
)

if [[ -n "${QUILLCODE_SAFETY_REVIEWER_CALIBRATION_MARKDOWN_OUTPUT:-}" ]]; then
  ARGS+=("--markdown-output" "$QUILLCODE_SAFETY_REVIEWER_CALIBRATION_MARKDOWN_OUTPUT")
fi

"$ROOT_DIR/scripts/native-click-probe-contracts.py" "${ARGS[@]}"

echo "QuillCode safety reviewer calibration rollup validated: $OUTPUT_PATH"
