#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVIDENCE_PATH="${1:-${QUILLCODE_SCHEDULED_NOTIFICATION_EVIDENCE:-}}"
MANIFEST_PATH="${2:-${QUILLCODE_SCHEDULED_NOTIFICATION_MANIFEST:-}}"

if [[ -z "$EVIDENCE_PATH" ]]; then
  echo "usage: scripts/scheduled-notification-observation-smoke.sh <evidence.json> [manifest.json]" >&2
  echo "or set QUILLCODE_SCHEDULED_NOTIFICATION_EVIDENCE and optional QUILLCODE_SCHEDULED_NOTIFICATION_MANIFEST." >&2
  exit 2
fi

if [[ -z "$MANIFEST_PATH" ]]; then
  MANIFEST_PATH="$(dirname "$EVIDENCE_PATH")/scheduled-notification-observation-manifest.json"
fi

"$ROOT_DIR/scripts/native-click-probe-contracts.py" scheduled-notification-observation \
  "$EVIDENCE_PATH" \
  --manifest "$MANIFEST_PATH"

echo "QuillCode scheduled notification observation evidence validated: $MANIFEST_PATH"
