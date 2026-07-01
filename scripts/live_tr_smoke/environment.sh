# Runtime setup helpers for the live TrustedRouter smoke.

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required tool not found: $1" >&2
    exit 2
  fi
}

trim() {
  awk '{$1=$1; print}'
}

load_live_smoke_api_key() {
  if [[ -n "${QUILLCODE_API_KEY:-}" ]]; then
    API_KEY="$(printf '%s' "$QUILLCODE_API_KEY" | trim)"
    API_KEY_SOURCE="env:QUILLCODE_API_KEY"
  elif [[ -n "${TRUSTEDROUTER_API_KEY:-}" ]]; then
    API_KEY="$(printf '%s' "$TRUSTEDROUTER_API_KEY" | trim)"
    API_KEY_SOURCE="env:TRUSTEDROUTER_API_KEY"
  elif [[ -s "$KEY_FILE" ]]; then
    API_KEY="$(trim < "$KEY_FILE")"
    API_KEY_SOURCE="key-file"
  else
    API_KEY=""
  fi
  if [[ -z "$API_KEY" ]]; then
    echo "No TrustedRouter key found. Set QUILLCODE_API_KEY, TRUSTEDROUTER_API_KEY, or create $KEY_FILE." >&2
    exit 2
  fi
}

prepare_git_workspace() {
  git -C "$SMOKE_WORKSPACE" init >/dev/null
  git -C "$SMOKE_WORKSPACE" config user.email quillcode-smoke@example.com
  git -C "$SMOKE_WORKSPACE" config user.name "QuillCode Smoke"
  printf 'before\n' > "$SMOKE_WORKSPACE/tracked.txt"
  git -C "$SMOKE_WORKSPACE" add tracked.txt
  git -C "$SMOKE_WORKSPACE" commit -m "Add tracked smoke file" >/dev/null
  printf 'after\n' > "$SMOKE_WORKSPACE/tracked.txt"
}

run_live_prompt() {
  local prompt="$1"
  local output_file="$2"
  local stderr_file="$3"

  CURRENT_STDOUT="$output_file"
  CURRENT_STDERR="$stderr_file"

  if swift run quill-code \
    --live \
    --api-key "$API_KEY" \
    --base-url "$BASE_URL" \
    --model "$MODEL" \
    --home "$SMOKE_HOME" \
    --cwd "$SMOKE_WORKSPACE" \
    "$prompt" \
    >"$output_file" \
    2>"$stderr_file"; then
    return
  else
    local status=$?
    fail_smoke "quill-code exited with status $status" "$output_file" "$stderr_file" "$status"
  fi
}

begin_scenario() {
  CURRENT_SCENARIO="$1"
  CURRENT_PROMPT="$2"
  CURRENT_SCENARIO_START="$(date +%s)"
  echo "==> [$CURRENT_SCENARIO] $3"
}

finish_scenario() {
  local output_file="$1"
  local stderr_file="$2"
  record_scenario "pass" "completed" "$output_file" "$stderr_file"
  CURRENT_SCENARIO=""
  CURRENT_PROMPT=""
  CURRENT_SCENARIO_START=0
  CURRENT_STDOUT=""
  CURRENT_STDERR=""
}

run_scenario() {
  local scenario="$1"
  local prompt="$2"
  local description="$3"
  local validator="$4"
  shift 4

  local output_file="$SMOKE_ROOT/$scenario.stdout"
  local stderr_file="$SMOKE_ROOT/$scenario.stderr"

  begin_scenario "$scenario" "$prompt" "$description"
  run_live_prompt "$prompt" "$output_file" "$stderr_file"
  "$validator" "$output_file" "$stderr_file" "$@"
  finish_scenario "$output_file" "$stderr_file"
}
