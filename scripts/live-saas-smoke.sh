#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVIDENCE_PATH="${1:-${QUILLCODE_LIVE_SAAS_EVIDENCE:-}}"
MANIFEST_PATH="${2:-${QUILLCODE_LIVE_SAAS_MANIFEST:-}}"

if [[ -z "$EVIDENCE_PATH" ]]; then
  echo "usage: scripts/live-saas-smoke.sh <evidence.json> [manifest.json]" >&2
  echo "or set QUILLCODE_LIVE_SAAS_EVIDENCE and optional QUILLCODE_LIVE_SAAS_MANIFEST." >&2
  exit 2
fi

if [[ -z "$MANIFEST_PATH" ]]; then
  MANIFEST_PATH="$(dirname "$EVIDENCE_PATH")/live-saas-manifest.json"
fi

"$ROOT_DIR/scripts/native-click-probe-contracts.py" live-saas \
  "$EVIDENCE_PATH" \
  --manifest "$MANIFEST_PATH"

echo "QuillCode live SaaS smoke evidence validated: $MANIFEST_PATH"
