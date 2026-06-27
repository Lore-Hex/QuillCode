#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEY_FILE="${QUILLCODE_LIVE_KEY_FILE:-$HOME/.quill.code.keyfile}"
REQUIRE_LIVE="${QUILLCODE_REQUIRE_LIVE_SMOKE:-0}"

cd "$ROOT_DIR"

has_live_key() {
  if [[ -n "${QUILLCODE_API_KEY:-}" || -n "${TRUSTEDROUTER_API_KEY:-}" ]]; then
    return 0
  fi
  [[ -s "$KEY_FILE" ]]
}

echo "==> Running deterministic QuillCode smoke suite"
"$ROOT_DIR/scripts/smoke.sh"

if has_live_key; then
  echo "==> Running live TrustedRouter real-world smoke suite"
  "$ROOT_DIR/scripts/live-tr-smoke.sh"
  echo "QuillCode real-world smoke passed."
  exit 0
fi

if [[ "$REQUIRE_LIVE" == "1" || "$REQUIRE_LIVE" == "true" ]]; then
  echo "Live TrustedRouter smoke was required, but no key was found." >&2
  echo "Set QUILLCODE_API_KEY, TRUSTEDROUTER_API_KEY, or create $KEY_FILE." >&2
  exit 2
fi

echo "No TrustedRouter key found; skipped live TrustedRouter smoke."
echo "Set QUILLCODE_REQUIRE_LIVE_SMOKE=1 to make that a hard release gate."
echo "QuillCode deterministic smoke passed."
