#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SMOKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/quillcode-live-smoke.XXXXXX")"
SMOKE_HOME="$SMOKE_ROOT/home"
SMOKE_WORKSPACE="$SMOKE_ROOT/workspace"
KEY_FILE="${QUILLCODE_LIVE_KEY_FILE:-$HOME/.quill.code.keyfile}"
RAW_MODEL="${QUILLCODE_LIVE_MODEL:-deepseekv4flash}"
BASE_URL="${QUILLCODE_LIVE_BASE_URL:-https://api.trustedrouter.com/v1}"

case "$RAW_MODEL" in
  deepseekv4flash|deepseek-v4-flash)
    MODEL="deepseek/deepseek-v4-flash"
    ;;
  *)
    MODEL="$RAW_MODEL"
    ;;
esac

cleanup() {
  rm -rf "$SMOKE_ROOT"
}
trap cleanup EXIT

trim() {
  awk '{$1=$1; print}'
}

configured_key() {
  if [[ -n "${QUILLCODE_API_KEY:-}" ]]; then
    printf '%s' "$QUILLCODE_API_KEY" | trim
    return
  fi
  if [[ -n "${TRUSTEDROUTER_API_KEY:-}" ]]; then
    printf '%s' "$TRUSTEDROUTER_API_KEY" | trim
    return
  fi
  if [[ -f "$KEY_FILE" ]]; then
    trim < "$KEY_FILE"
    return
  fi
}

API_KEY="$(configured_key || true)"
if [[ -z "$API_KEY" ]]; then
  echo "No TrustedRouter key found. Set QUILLCODE_API_KEY, TRUSTEDROUTER_API_KEY, or create $KEY_FILE." >&2
  exit 2
fi

mkdir -p "$SMOKE_HOME" "$SMOKE_WORKSPACE"
cd "$ROOT_DIR"

run_live_prompt() {
  local prompt="$1"
  local output_file="$2"
  local stderr_file="$3"

  swift run quill-code \
    --live \
    --api-key "$API_KEY" \
    --base-url "$BASE_URL" \
    --model "$MODEL" \
    --home "$SMOKE_HOME" \
    --cwd "$SMOKE_WORKSPACE" \
    "$prompt" \
    >"$output_file" \
    2>"$stderr_file"
}

assert_useful_output() {
  local output_file="$1"
  local stderr_file="$2"
  local expected="$3"

  if [[ ! -s "$output_file" ]]; then
    echo "live smoke returned no stdout" >&2
    cat "$stderr_file" >&2 || true
    exit 1
  fi
  if grep -qi "No shell command was specified" "$output_file"; then
    echo "live smoke regressed into an empty shell command" >&2
    cat "$output_file" >&2
    exit 1
  fi
  if grep -Eq "I'?ll (run|check|do)" "$output_file"; then
    echo "live smoke returned a passive promise instead of executing" >&2
    cat "$output_file" >&2
    exit 1
  fi
  if ! grep -Fq "$expected" "$output_file"; then
    echo "live smoke output did not contain expected text: $expected" >&2
    cat "$output_file" >&2
    exit 1
  fi
}

echo "==> Running live TrustedRouter shell-action smoke with $MODEL"
RUN_OUTPUT="$SMOKE_ROOT/run.stdout"
RUN_ERROR="$SMOKE_ROOT/run.stderr"
run_live_prompt "Run \`printf quillcode_live_smoke\`" "$RUN_OUTPUT" "$RUN_ERROR"
assert_useful_output "$RUN_OUTPUT" "$RUN_ERROR" "quillcode_live_smoke"

echo "==> Running live TrustedRouter diagnostic-question smoke with $MODEL"
DIAG_OUTPUT="$SMOKE_ROOT/diag.stdout"
DIAG_ERROR="$SMOKE_ROOT/diag.stderr"
run_live_prompt "whoami?" "$DIAG_OUTPUT" "$DIAG_ERROR"
assert_useful_output "$DIAG_OUTPUT" "$DIAG_ERROR" "$(id -un)"

echo "QuillCode live TrustedRouter smoke passed."
