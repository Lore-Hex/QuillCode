#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SMOKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/quillcode-live-smoke.XXXXXX")"
SMOKE_HOME="$SMOKE_ROOT/home"
SMOKE_WORKSPACE="$SMOKE_ROOT/workspace"
REPORT_FILE="$SMOKE_ROOT/live-smoke-report.jsonl"
MANIFEST_FILE="$SMOKE_ROOT/live-smoke-manifest.json"
KEY_FILE="${QUILLCODE_LIVE_KEY_FILE:-$HOME/.quill.code.keyfile}"
RAW_MODEL="${QUILLCODE_LIVE_MODEL:-deepseekv4flash}"
BASE_URL="${QUILLCODE_LIVE_BASE_URL:-https://api.trustedrouter.com/v1}"
KEEP_ARTIFACTS="${QUILLCODE_LIVE_KEEP_ARTIFACTS:-0}"
ARTIFACT_DIR="${QUILLCODE_LIVE_SMOKE_ARTIFACT_DIR:-}"
API_KEY_SOURCE="missing"
CURRENT_SCENARIO=""
CURRENT_PROMPT=""
CURRENT_SCENARIO_START=0
CURRENT_STDOUT=""
CURRENT_STDERR=""
ARTIFACTS_COPIED=0
PASSIVE_ACTION_PATTERN="No shell command was specified|(I'?ll|I will) (run|check|do|download|create|write|execute|inspect|list|show|review|read|fetch|save)"

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
  local status=$?
  set +e

  if type write_artifact_manifest >/dev/null 2>&1; then
    write_artifact_manifest "$status" "exit status $status"
  fi
  if type copy_live_artifacts >/dev/null 2>&1; then
    copy_live_artifacts "$status"
  fi

  if [[ "$status" -eq 0 && "$KEEP_ARTIFACTS" != "1" ]]; then
    rm -rf "$SMOKE_ROOT"
    return
  fi

  if [[ "$status" -eq 0 ]]; then
    echo "Live smoke artifacts kept at $SMOKE_ROOT"
  else
    echo "Live smoke failed; artifacts kept at $SMOKE_ROOT" >&2
  fi
}
trap cleanup EXIT

require_tool jq
require_tool git

trim() {
  awk '{$1=$1; print}'
}

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

mkdir -p "$SMOKE_HOME" "$SMOKE_WORKSPACE"
SMOKE_WORKSPACE_PHYSICAL="$(cd "$SMOKE_WORKSPACE" && pwd -P)"
cd "$ROOT_DIR"

prepare_git_workspace() {
  git -C "$SMOKE_WORKSPACE" init >/dev/null
  git -C "$SMOKE_WORKSPACE" config user.email quillcode-smoke@example.com
  git -C "$SMOKE_WORKSPACE" config user.name "QuillCode Smoke"
  printf 'before\n' > "$SMOKE_WORKSPACE/tracked.txt"
  git -C "$SMOKE_WORKSPACE" add tracked.txt
  git -C "$SMOKE_WORKSPACE" commit -m "Add tracked smoke file" >/dev/null
  printf 'after\n' > "$SMOKE_WORKSPACE/tracked.txt"
}

prepare_git_workspace

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

record_scenario() {
  local status="$1"
  local detail="$2"
  local output_file="$3"
  local stderr_file="$4"
  local finished_at
  local duration
  local stdout_bytes=0
  local stderr_bytes=0

  finished_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  if [[ "$CURRENT_SCENARIO_START" -gt 0 ]]; then
    duration="$(( $(date +%s) - CURRENT_SCENARIO_START ))"
  else
    duration="0"
  fi
  if [[ -f "$output_file" ]]; then
    stdout_bytes="$(wc -c < "$output_file" | tr -d ' ')"
  fi
  if [[ -f "$stderr_file" ]]; then
    stderr_bytes="$(wc -c < "$stderr_file" | tr -d ' ')"
  fi

  jq -n \
    --arg scenario "$CURRENT_SCENARIO" \
    --arg prompt "$CURRENT_PROMPT" \
    --arg status "$status" \
    --arg detail "$detail" \
    --arg model "$MODEL" \
    --arg baseURL "$BASE_URL" \
    --arg finishedAt "$finished_at" \
    --arg stdout "$output_file" \
    --arg stderr "$stderr_file" \
    --argjson durationSeconds "$duration" \
    --argjson stdoutBytes "$stdout_bytes" \
    --argjson stderrBytes "$stderr_bytes" \
    '{
      scenario: $scenario,
      status: $status,
      detail: $detail,
      model: $model,
      baseURL: $baseURL,
      finishedAt: $finishedAt,
      durationSeconds: $durationSeconds,
      stdoutBytes: $stdoutBytes,
      stderrBytes: $stderrBytes,
      stdout: $stdout,
      stderr: $stderr,
      prompt: $prompt
    }' >> "$REPORT_FILE"
}

print_report_summary() {
  if [[ ! -s "$REPORT_FILE" ]]; then
    return
  fi
  echo "Live smoke scenario report:"
  jq -rs '
    (
      ["status", "scenario", "duration", "stdout", "stderr", "detail"],
      (.[] | [.status, .scenario, ((.durationSeconds | tostring) + "s"), (.stdoutBytes | tostring), (.stderrBytes | tostring), .detail])
    )
    | @tsv
  ' "$REPORT_FILE"
}

write_artifact_manifest() {
  local status="${1:-0}"
  local detail="${2:-completed}"
  local scenarios_json="$SMOKE_ROOT/scenarios.json"
  local workspace_files_json="$SMOKE_ROOT/workspace-files.json"
  local threads_json="$SMOKE_ROOT/thread-summaries.json"
  local generated_at

  generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  if [[ -s "$REPORT_FILE" ]]; then
    jq -s '.' "$REPORT_FILE" > "$scenarios_json"
  else
    printf '[]\n' > "$scenarios_json"
  fi

  if [[ -d "$SMOKE_WORKSPACE" ]]; then
    find "$SMOKE_WORKSPACE" \
      -path "$SMOKE_WORKSPACE/.git" -prune -o \
      -maxdepth 5 -type f -print | sort | while IFS= read -r file_path; do
      local relative_path
      local byte_count
      relative_path="${file_path#$SMOKE_WORKSPACE/}"
      byte_count="$(wc -c < "$file_path" | tr -d ' ')"
      jq -n \
        --arg path "$relative_path" \
        --argjson bytes "$byte_count" \
        '{path: $path, bytes: $bytes}'
    done | jq -s '.' > "$workspace_files_json"
  else
    printf '[]\n' > "$workspace_files_json"
  fi

  if [[ -d "$SMOKE_HOME/threads" ]]; then
    find "$SMOKE_HOME/threads" -maxdepth 1 -type f -name '*.json' -print | sort | while IFS= read -r thread_path; do
      jq \
        --arg path "$thread_path" \
        --arg basename "$(basename "$thread_path")" \
        '{
          path: $path,
          file: $basename,
          id: .id,
          title: .title,
          model: .model,
          messageCount: (.messages | length),
          queuedToolCount: ([.events[]? | select(.kind == "toolQueued")] | length),
          completedToolCount: ([.events[]? | select(.kind == "toolCompleted")] | length),
          failedToolCount: ([.events[]? | select(.kind == "toolFailed")] | length)
        }' "$thread_path"
    done | jq -s '.' > "$threads_json"
  else
    printf '[]\n' > "$threads_json"
  fi

  jq -n \
    --arg generatedAt "$generated_at" \
    --arg status "$status" \
    --arg detail "$detail" \
    --arg rawModel "$RAW_MODEL" \
    --arg model "$MODEL" \
    --arg baseURL "$BASE_URL" \
    --arg keySource "$API_KEY_SOURCE" \
    --arg root "$SMOKE_ROOT" \
    --arg home "$SMOKE_HOME" \
    --arg workspace "$SMOKE_WORKSPACE" \
    --arg report "$REPORT_FILE" \
    --slurpfile scenarios "$scenarios_json" \
    --slurpfile workspaceFiles "$workspace_files_json" \
    --slurpfile threads "$threads_json" \
    '{
      generatedAt: $generatedAt,
      status: ($status | tonumber),
      detail: $detail,
      transport: "TrustedRouter",
      rawModel: $rawModel,
      normalizedModel: $model,
      model: $model,
      baseURL: $baseURL,
      keySource: $keySource,
      secretFree: true,
      smokeRoot: $root,
      home: $home,
      workspace: $workspace,
      report: $report,
      scenarioCount: ($scenarios[0] | length),
      passedScenarioCount: ([$scenarios[0][] | select(.status == "pass")] | length),
      failedScenarioCount: ([$scenarios[0][] | select(.status == "fail")] | length),
      workspaceFileCount: ($workspaceFiles[0] | length),
      threadCount: ($threads[0] | length),
      scenarios: $scenarios[0],
      workspaceFiles: $workspaceFiles[0],
      threads: $threads[0]
    }' > "$MANIFEST_FILE"
}

copy_live_artifacts() {
  local status="${1:-0}"
  if [[ -z "$ARTIFACT_DIR" ]]; then
    return
  fi
  if [[ "$ARTIFACTS_COPIED" == "1" ]]; then
    return
  fi

  mkdir -p "$ARTIFACT_DIR"
  for artifact_path in "$REPORT_FILE" "$MANIFEST_FILE" "$SMOKE_ROOT"/*.stdout "$SMOKE_ROOT"/*.stderr; do
    if [[ -e "$artifact_path" ]]; then
      cp "$artifact_path" "$ARTIFACT_DIR/$(basename "$artifact_path")"
    fi
  done
  {
    printf 'status=%s\n' "$status"
    printf 'source=%s\n' "$SMOKE_ROOT"
    printf 'manifest=live-smoke-manifest.json\n'
    printf 'report=live-smoke-report.jsonl\n'
    printf 'model=%s\n' "$MODEL"
    printf 'base_url=%s\n' "$BASE_URL"
  } > "$ARTIFACT_DIR/manifest.txt"
  ARTIFACTS_COPIED=1
  echo "QuillCode live TrustedRouter smoke artifacts: $ARTIFACT_DIR"
}

fail_smoke() {
  local message="$1"
  local output_file="${2:-$CURRENT_STDOUT}"
  local stderr_file="${3:-$CURRENT_STDERR}"
  local exit_code="${4:-1}"

  if [[ -n "$CURRENT_SCENARIO" ]]; then
    record_scenario "fail" "$message" "$output_file" "$stderr_file"
  fi

  echo "Live smoke failed in scenario: ${CURRENT_SCENARIO:-unknown}" >&2
  echo "$message" >&2
  if [[ -n "$CURRENT_PROMPT" ]]; then
    echo "Prompt: $CURRENT_PROMPT" >&2
  fi
  if [[ -n "$output_file" ]]; then
    echo "stdout: $output_file" >&2
    if [[ -s "$output_file" ]]; then
      echo "--- stdout tail ---" >&2
      tail -n 80 "$output_file" >&2
    fi
  fi
  if [[ -n "$stderr_file" ]]; then
    echo "stderr: $stderr_file" >&2
    if [[ -s "$stderr_file" ]]; then
      echo "--- stderr tail ---" >&2
      tail -n 80 "$stderr_file" >&2
    fi
  fi
  print_report_summary >&2
  exit "$exit_code"
}

fail_workspace_assertion() {
  local message="$1"
  local max_depth="$2"
  record_scenario "fail" "$message" "$CURRENT_STDOUT" "$CURRENT_STDERR"
  echo "Live smoke failed in scenario: ${CURRENT_SCENARIO:-unknown}" >&2
  echo "$message" >&2
  echo "Workspace files:" >&2
  find "$SMOKE_WORKSPACE" -maxdepth "$max_depth" -type f -print >&2
  print_report_summary >&2
  exit 1
}

assert_useful_output() {
  local output_file="$1"
  local stderr_file="$2"
  local expected="$3"

  assert_no_action_regression "$output_file" "$stderr_file"
  if ! grep -Fq "$expected" "$output_file"; then
    fail_smoke "live smoke output did not contain expected text: $expected" "$output_file" "$stderr_file"
  fi
}

assert_no_action_regression() {
  local output_file="$1"
  local stderr_file="$2"

  if [[ ! -s "$output_file" ]]; then
    fail_smoke "live smoke returned no stdout" "$output_file" "$stderr_file"
  fi
  if grep -qi "No shell command was specified" "$output_file"; then
    fail_smoke "live smoke regressed into an empty shell command" "$output_file" "$stderr_file"
  fi
  if grep -Eiq "$PASSIVE_ACTION_PATTERN" "$output_file"; then
    fail_smoke "live smoke returned a passive promise instead of executing" "$output_file" "$stderr_file"
  fi
}

assert_workspace_file_contains_exactly() {
  local relative_path="$1"
  local expected_content="$2"
  local file_path="$SMOKE_WORKSPACE/$relative_path"

  if [[ ! -f "$file_path" ]]; then
    fail_workspace_assertion "live smoke did not create expected workspace file: $relative_path" 2
  fi

  local actual_content
  actual_content="$(tr -d '\r' < "$file_path")"
  actual_content="${actual_content%$'\n'}"
  if [[ "$actual_content" != "$expected_content" ]]; then
    record_scenario "fail" "live smoke file content mismatch for $relative_path" "$CURRENT_STDOUT" "$CURRENT_STDERR"
    echo "Live smoke failed in scenario: ${CURRENT_SCENARIO:-unknown}" >&2
    echo "live smoke file content mismatch for $relative_path" >&2
    printf 'expected: %s\nactual: %s\n' "$expected_content" "$actual_content" >&2
    print_report_summary >&2
    exit 1
  fi
}

assert_workspace_file_nonempty() {
  local relative_path="$1"
  local file_path="$SMOKE_WORKSPACE/$relative_path"

  if [[ ! -s "$file_path" ]]; then
    fail_workspace_assertion "live smoke expected a non-empty workspace file: $relative_path" 3
  fi
}

assert_workspace_file_absent() {
  local relative_path="$1"
  local file_path="$SMOKE_WORKSPACE/$relative_path"

  if [[ -e "$file_path" ]]; then
    fail_workspace_assertion "live smoke created forbidden workspace file despite explicit negative intent: $relative_path" 3
  fi
}

assert_output_matches() {
  local output_file="$1"
  local stderr_file="$2"
  local pattern="$3"
  local description="$4"

  assert_no_action_regression "$output_file" "$stderr_file"
  if ! grep -Eiq "$pattern" "$output_file"; then
    fail_smoke "live smoke output did not match expected $description" "$output_file" "$stderr_file"
  fi
}

assert_saved_transcripts_match_live_smoke_expectations() {
  local minimum_actionable_thread_count="${1:-3}"
  local minimum_negative_thread_count="${2:-0}"
  local threads_dir="$SMOKE_HOME/threads"

  if [[ ! -d "$threads_dir" ]]; then
    fail_smoke "live smoke did not persist any thread directory" "" ""
  fi

  local actionable_thread_count
  local negative_thread_count
  actionable_thread_count="$(
    jq -s '
      def has_negative_action_prompt:
        [.messages[]?
          | select(.role == "user")
          | .content
          | select(test("(do not|don'\''t|dont|never).*(run|write|download)"; "i"))]
        | length > 0;
      [.[] | select(has_negative_action_prompt | not)] | length
    ' "$threads_dir"/*.json
  )"
  negative_thread_count="$(
    jq -s '
      def has_negative_action_prompt:
        [.messages[]?
          | select(.role == "user")
          | .content
          | select(test("(do not|don'\''t|dont|never).*(run|write|download)"; "i"))]
        | length > 0;
      [.[] | select(has_negative_action_prompt)] | length
    ' "$threads_dir"/*.json
  )"

  if [[ "$actionable_thread_count" -lt "$minimum_actionable_thread_count" ]]; then
    record_scenario "fail" "live smoke expected at least $minimum_actionable_thread_count actionable transcripts, found $actionable_thread_count" "" ""
    echo "Live smoke failed in scenario: ${CURRENT_SCENARIO:-unknown}" >&2
    echo "live smoke expected at least $minimum_actionable_thread_count actionable transcripts, found $actionable_thread_count" >&2
    find "$threads_dir" -maxdepth 1 -type f -name '*.json' -print >&2
    print_report_summary >&2
    exit 1
  fi

  if [[ "$negative_thread_count" -lt "$minimum_negative_thread_count" ]]; then
    record_scenario "fail" "live smoke expected at least $minimum_negative_thread_count negative-intent transcripts, found $negative_thread_count" "" ""
    echo "Live smoke failed in scenario: ${CURRENT_SCENARIO:-unknown}" >&2
    echo "live smoke expected at least $minimum_negative_thread_count negative-intent transcripts, found $negative_thread_count" >&2
    find "$threads_dir" -maxdepth 1 -type f -name '*.json' -print >&2
    print_report_summary >&2
    exit 1
  fi

  jq -s -e --arg passiveActionPattern "$PASSIVE_ACTION_PATTERN" '
    def has_negative_action_prompt:
      [.messages[]?
        | select(.role == "user")
        | .content
        | select(test("(do not|don'\''t|dont|never).*(run|write|download)"; "i"))]
      | length > 0;
    def queued_calls:
      [.events[]? | select(.kind == "toolQueued") | .payloadJSON | fromjson];
    def queued_arguments:
      [queued_calls[] | .argumentsJSON | fromjson];
    def bad_empty_argument_calls:
      [queued_calls[]
        | select(.name != "host.git.status" and .name != "host.git.diff")
        | select((.argumentsJSON | fromjson | length) == 0)];
    def completed_results:
      [.events[]? | select(.kind == "toolCompleted") | .payloadJSON | fromjson];
    def bad_assistant_promises:
      [.messages[]?
        | select(.role == "assistant")
        | .content
        | select(test($passiveActionPattern; "i"))];
    def actionable_transcript_ok:
      (
        (.messages | length) >= 2
        and (bad_assistant_promises | length) == 0
        and (queued_calls | length) >= 1
        and (queued_arguments | length) == (queued_calls | length)
        and all(queued_calls[]; (.name | type == "string") and (.name | length) > 0)
        and all(queued_calls[]; (.argumentsJSON | type == "string") and (.argumentsJSON | length) >= 2)
        and all(queued_arguments[]; type == "object")
        and (bad_empty_argument_calls | length) == 0
        and ([.events[]? | select(.kind == "toolFailed")] | length) == 0
        and (completed_results | length) >= 1
        and all(completed_results[]; .ok == true)
      );
    def negative_transcript_ok:
      (
        (.messages | length) >= 2
        and (queued_calls | length) == 0
        and ([.events[]? | select(.kind == "toolFailed")] | length) == 0
        and (completed_results | length) == 0
      );

    all(.[]; if has_negative_action_prompt then negative_transcript_ok else actionable_transcript_ok end)
  ' "$threads_dir"/*.json >/dev/null || {
    record_scenario "fail" "live smoke persisted transcript integrity check failed" "" ""
    echo "Live smoke failed in scenario: ${CURRENT_SCENARIO:-unknown}" >&2
    echo "live smoke persisted transcript integrity check failed" >&2
    jq '. | {title, messages, events}' "$threads_dir"/*.json >&2 || true
    print_report_summary >&2
    exit 1
  }
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

validate_expected_output() {
  assert_useful_output "$1" "$2" "$3"
}

validate_output_pattern() {
  assert_output_matches "$1" "$2" "$3" "$4"
}

validate_two_expected_outputs() {
  assert_useful_output "$1" "$2" "$3"
  assert_useful_output "$1" "$2" "$4"
}

validate_three_expected_outputs() {
  assert_useful_output "$1" "$2" "$3"
  assert_useful_output "$1" "$2" "$4"
  assert_useful_output "$1" "$2" "$5"
}

validate_exact_workspace_file() {
  assert_no_action_regression "$1" "$2"
  assert_workspace_file_contains_exactly "$3" "$4"
}

validate_nonempty_workspace_file() {
  assert_output_matches "$1" "$2" "$3" "$4"
  assert_workspace_file_nonempty "$5"
}

validate_absent_output() {
  local output_file="$1"
  local stderr_file="$2"
  local forbidden="$3"

  if [[ ! -s "$output_file" ]]; then
    fail_smoke "live smoke returned no stdout" "$output_file" "$stderr_file"
  fi
  if grep -Fq "$forbidden" "$output_file"; then
    fail_smoke "live smoke output contained forbidden text despite explicit negative intent: $forbidden" "$output_file" "$stderr_file"
  fi
}

validate_nonempty_noop_output() {
  local output_file="$1"
  local stderr_file="$2"

  if [[ ! -s "$output_file" ]]; then
    fail_smoke "live smoke returned no stdout" "$output_file" "$stderr_file"
  fi
}

validate_no_workspace_file() {
  validate_absent_output "$1" "$2" "$4"
  assert_workspace_file_absent "$3"
}

run_scenario \
  "shell-action" \
  "Run \`printf quillcode_live_smoke\`" \
  "Running live TrustedRouter shell-action smoke with $MODEL" \
  validate_expected_output \
  "quillcode_live_smoke"

run_scenario \
  "shell-action-now" \
  "Please run \`printf quillcode_live_now_smoke\` now and report the output." \
  "Running live TrustedRouter shell-action-now smoke with $MODEL" \
  validate_expected_output \
  "quillcode_live_now_smoke"

run_scenario \
  "shell-action-polite-bare" \
  "Can you run printf quillcode_live_polite_smoke?" \
  "Running live TrustedRouter shell-action-polite-bare smoke with $MODEL" \
  validate_expected_output \
  "quillcode_live_polite_smoke"

run_scenario \
  "diagnostic-question" \
  "whoami?" \
  "Running live TrustedRouter diagnostic-question smoke with $MODEL" \
  validate_expected_output \
  "$(id -un)"

run_scenario \
  "disk-usage" \
  "How much hd?" \
  "Running live TrustedRouter disk-usage smoke with $MODEL" \
  validate_output_pattern \
  "Disk usage|available|used|[0-9]+%" \
  "disk usage result"

run_scenario \
  "git-status" \
  "git status" \
  "Running live TrustedRouter git-status smoke with $MODEL" \
  validate_two_expected_outputs \
  "Git status:" \
  "tracked.txt"

run_scenario \
  "git-status-polite" \
  "Please check git status." \
  "Running live TrustedRouter polite git-status smoke with $MODEL" \
  validate_two_expected_outputs \
  "Git status:" \
  "tracked.txt"

run_scenario \
  "git-diff" \
  "what changed?" \
  "Running live TrustedRouter git-diff smoke with $MODEL" \
  validate_three_expected_outputs \
  "Git diff:" \
  "tracked.txt" \
  "+after"

run_scenario \
  "file-write-explicit" \
  "Create \`live-smoke.txt\` in this workspace with exactly this content: \`quillcode_live_file_smoke\`." \
  "Running live TrustedRouter file-write smoke with $MODEL" \
  validate_exact_workspace_file \
  "live-smoke.txt" \
  "quillcode_live_file_smoke"

run_scenario \
  "file-write-natural" \
  "Can you write \`hello-world.txt\` with exactly this content: \`hello world\`?" \
  "Running live TrustedRouter natural file-write smoke with $MODEL" \
  validate_exact_workspace_file \
  "hello-world.txt" \
  "hello world"

run_scenario \
  "workspace-list-followup" \
  "Run \`ls -1\` in this workspace and tell me whether \`live-smoke.txt\` and \`hello-world.txt\` are present." \
  "Running live TrustedRouter workspace-list follow-up smoke with $MODEL" \
  validate_two_expected_outputs \
  "live-smoke.txt" \
  "hello-world.txt"

run_scenario \
  "workspace-list-natural" \
  "Can you list the files here?" \
  "Running live TrustedRouter natural workspace-list smoke with $MODEL" \
  validate_two_expected_outputs \
  "live-smoke.txt" \
  "hello-world.txt"

run_scenario \
  "workspace-pwd-natural" \
  "Can you show me the current directory?" \
  "Running live TrustedRouter natural current-directory smoke with $MODEL" \
  validate_expected_output \
  "$SMOKE_WORKSPACE_PHYSICAL"

run_scenario \
  "workspace-read-followup" \
  "Read \`hello-world.txt\` and tell me its exact content." \
  "Running live TrustedRouter workspace-read follow-up smoke with $MODEL" \
  validate_expected_output \
  "hello world"

run_scenario \
  "openclaw-discovery" \
  "Do you have openclaw?" \
  "Running live TrustedRouter OpenClaw discovery smoke with $MODEL" \
  validate_output_pattern \
  "openclaw|not found" \
  "OpenClaw discovery result"

run_scenario \
  "download" \
  "Download https://example.com into \`downloads/example.html\` in this workspace." \
  "Running live TrustedRouter download smoke with $MODEL" \
  validate_nonempty_workspace_file \
  "downloads/example\\.html|download" \
  "download result" \
  "downloads/example.html"

run_scenario \
  "negative-shell-action" \
  "Do not run \`printf quillcode_live_forbidden_shell\`." \
  "Running live TrustedRouter negative shell-action smoke with $MODEL" \
  validate_nonempty_noop_output

run_scenario \
  "negative-file-write" \
  "Do not write \`forbidden-live.txt\` with content \`nope\`." \
  "Running live TrustedRouter negative file-write smoke with $MODEL" \
  validate_no_workspace_file \
  "forbidden-live.txt" \
  "Wrote \`forbidden-live.txt\`"

run_scenario \
  "negative-download" \
  "Don't download https://example.com into \`downloads/forbidden-live.html\`." \
  "Running live TrustedRouter negative download smoke with $MODEL" \
  validate_no_workspace_file \
  "downloads/forbidden-live.html" \
  "Downloaded to \`downloads/forbidden-live.html\`"

begin_scenario "transcript-integrity" "Validate persisted thread transcripts" "Checking persisted live smoke transcripts"
assert_saved_transcripts_match_live_smoke_expectations 16 3
finish_scenario "" ""

write_artifact_manifest 0 "completed"
copy_live_artifacts 0
print_report_summary
echo "QuillCode live TrustedRouter smoke passed."
