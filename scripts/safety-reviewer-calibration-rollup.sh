#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -lt 2 ]]; then
  echo "usage: scripts/safety-reviewer-calibration-rollup.sh <output.json> <manifest.json> [manifest.json ...]" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_PATH="$1"
shift

"$ROOT_DIR/scripts/native-click-probe-contracts.py" safety-reviewer-calibration-rollup \
  "$@" \
  --output "$OUTPUT_PATH"

echo "QuillCode safety reviewer calibration rollup validated: $OUTPUT_PATH"
