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

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required tool not found: $1" >&2
    exit 2
  fi
}

cleanup() {
  rm -rf "$SMOKE_ROOT"
}
trap cleanup EXIT

require_tool jq

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

  assert_no_action_regression "$output_file" "$stderr_file"
  if ! grep -Fq "$expected" "$output_file"; then
    echo "live smoke output did not contain expected text: $expected" >&2
    cat "$output_file" >&2
    exit 1
  fi
}

assert_no_action_regression() {
  local output_file="$1"
  local stderr_file="$2"

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
}

assert_workspace_file_contains_exactly() {
  local relative_path="$1"
  local expected_content="$2"
  local file_path="$SMOKE_WORKSPACE/$relative_path"

  if [[ ! -f "$file_path" ]]; then
    echo "live smoke did not create expected workspace file: $relative_path" >&2
    find "$SMOKE_WORKSPACE" -maxdepth 2 -type f -print >&2
    exit 1
  fi

  local actual_content
  actual_content="$(tr -d '\r' < "$file_path")"
  actual_content="${actual_content%$'\n'}"
  if [[ "$actual_content" != "$expected_content" ]]; then
    echo "live smoke file content mismatch for $relative_path" >&2
    printf 'expected: %s\nactual: %s\n' "$expected_content" "$actual_content" >&2
    exit 1
  fi
}

assert_workspace_file_nonempty() {
  local relative_path="$1"
  local file_path="$SMOKE_WORKSPACE/$relative_path"

  if [[ ! -s "$file_path" ]]; then
    echo "live smoke expected a non-empty workspace file: $relative_path" >&2
    find "$SMOKE_WORKSPACE" -maxdepth 3 -type f -print >&2
    exit 1
  fi
}

assert_output_matches() {
  local output_file="$1"
  local stderr_file="$2"
  local pattern="$3"
  local description="$4"

  assert_no_action_regression "$output_file" "$stderr_file"
  if ! grep -Eiq "$pattern" "$output_file"; then
    echo "live smoke output did not match expected $description" >&2
    cat "$output_file" >&2
    exit 1
  fi
}

assert_saved_transcripts_are_actionable() {
  local minimum_thread_count="${1:-3}"
  local threads_dir="$SMOKE_HOME/threads"

  if [[ ! -d "$threads_dir" ]]; then
    echo "live smoke did not persist any thread directory" >&2
    exit 1
  fi

  local thread_count
  thread_count="$(find "$threads_dir" -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ')"
  if [[ "$thread_count" -lt "$minimum_thread_count" ]]; then
    echo "live smoke expected at least $minimum_thread_count persisted thread transcripts, found $thread_count" >&2
    find "$threads_dir" -maxdepth 1 -type f -name '*.json' -print >&2
    exit 1
  fi

  jq -s -e '
    def queued_calls:
      [.events[]? | select(.kind == "toolQueued") | .payloadJSON | fromjson];
    def queued_arguments:
      [queued_calls[] | .argumentsJSON | fromjson];
    def completed_results:
      [.events[]? | select(.kind == "toolCompleted") | .payloadJSON | fromjson];
    def bad_assistant_promises:
      [.messages[]?
        | select(.role == "assistant")
        | .content
        | select(test("No shell command was specified|I'\''?ll (run|check|do)"; "i"))];

    all(.[]; (
      (.messages | length) >= 2
      and (bad_assistant_promises | length) == 0
      and (queued_calls | length) >= 1
      and (queued_arguments | length) == (queued_calls | length)
      and all(queued_calls[]; (.name | type == "string") and (.name | length) > 0)
      and all(queued_calls[]; (.argumentsJSON | type == "string") and (.argumentsJSON | length) > 2)
      and all(queued_arguments[]; (type == "object") and (length > 0))
      and ([.events[]? | select(.kind == "toolFailed")] | length) == 0
      and (completed_results | length) >= 1
      and all(completed_results[]; .ok == true)
    ))
  ' "$threads_dir"/*.json >/dev/null || {
    echo "live smoke persisted transcript integrity check failed" >&2
    jq '. | {title, messages, events}' "$threads_dir"/*.json >&2 || true
    exit 1
  }
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

echo "==> Running live TrustedRouter file-write smoke with $MODEL"
FILE_OUTPUT="$SMOKE_ROOT/file.stdout"
FILE_ERROR="$SMOKE_ROOT/file.stderr"
run_live_prompt "Create \`live-smoke.txt\` in this workspace with exactly this content: \`quillcode_live_file_smoke\`." "$FILE_OUTPUT" "$FILE_ERROR"
assert_no_action_regression "$FILE_OUTPUT" "$FILE_ERROR"
assert_workspace_file_contains_exactly "live-smoke.txt" "quillcode_live_file_smoke"

echo "==> Running live TrustedRouter OpenClaw discovery smoke with $MODEL"
OPENCLAW_OUTPUT="$SMOKE_ROOT/openclaw.stdout"
OPENCLAW_ERROR="$SMOKE_ROOT/openclaw.stderr"
run_live_prompt "Do you have openclaw?" "$OPENCLAW_OUTPUT" "$OPENCLAW_ERROR"
assert_output_matches "$OPENCLAW_OUTPUT" "$OPENCLAW_ERROR" "openclaw|not found" "OpenClaw discovery result"

echo "==> Running live TrustedRouter download smoke with $MODEL"
DOWNLOAD_OUTPUT="$SMOKE_ROOT/download.stdout"
DOWNLOAD_ERROR="$SMOKE_ROOT/download.stderr"
run_live_prompt "Download https://example.com into \`downloads/example.html\` in this workspace." "$DOWNLOAD_OUTPUT" "$DOWNLOAD_ERROR"
assert_output_matches "$DOWNLOAD_OUTPUT" "$DOWNLOAD_ERROR" "downloads/example\\.html|download" "download result"
assert_workspace_file_nonempty "downloads/example.html"

assert_saved_transcripts_are_actionable 5

echo "QuillCode live TrustedRouter smoke passed."
