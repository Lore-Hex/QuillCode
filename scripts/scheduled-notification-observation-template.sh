#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -lt 2 ]]; then
  echo "usage: scripts/scheduled-notification-observation-template.sh <output.json> <catalog-task-id> [catalog-task-id ...]" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_PATH="$1"
shift

"$ROOT_DIR/scripts/native-click-probe-contracts.py" scheduled-notification-observation-template \
  "$@" \
  --output "$OUTPUT_PATH"
