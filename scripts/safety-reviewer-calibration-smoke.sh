#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -lt 1 || "$#" -gt 2 ]]; then
  echo "usage: scripts/safety-reviewer-calibration-smoke.sh <evidence.json> [manifest.json]" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVIDENCE_PATH="$1"
if [[ "$#" -eq 2 ]]; then
  MANIFEST_PATH="$2"
else
  MANIFEST_PATH="$(dirname "$EVIDENCE_PATH")/safety-reviewer-calibration-manifest.json"
fi

"$ROOT_DIR/scripts/native-click-probe-contracts.py" safety-reviewer-calibration \
  "$EVIDENCE_PATH" \
  --manifest "$MANIFEST_PATH"
