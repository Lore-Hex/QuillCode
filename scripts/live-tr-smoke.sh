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
PASSIVE_ACTION_VERBS="run|check|do|download|create|write|execute|inspect|list|show|review|read|fetch|save"
PASSIVE_ACTION_PATTERN="No shell command was specified|(I'?ll|I will) ($PASSIVE_ACTION_VERBS)"

case "$RAW_MODEL" in
  deepseekv4flash|deepseek-v4-flash)
    MODEL="deepseek/deepseek-v4-flash"
    ;;
  *)
    MODEL="$RAW_MODEL"
    ;;
esac

source "$ROOT_DIR/scripts/live_tr_smoke/environment.sh"
source "$ROOT_DIR/scripts/live_tr_smoke/artifacts.sh"
source "$ROOT_DIR/scripts/live_tr_smoke/assertions.sh"
source "$ROOT_DIR/scripts/live_tr_smoke/transcript_assertions.sh"

install_live_smoke_cleanup_trap

require_tool jq
require_tool git
load_live_smoke_api_key

mkdir -p "$SMOKE_HOME" "$SMOKE_WORKSPACE"
SMOKE_WORKSPACE_PHYSICAL="$(cd "$SMOKE_WORKSPACE" && pwd -P)"
cd "$ROOT_DIR"

prepare_git_workspace

run_scenario \
  "shell-action" \
  "Run \`printf quillcode_live_smoke\`" \
  "Running live TrustedRouter shell-action smoke with $MODEL" \
  validate_expected_outputs \
  "quillcode_live_smoke"

run_scenario \
  "shell-action-now" \
  "Please run \`printf quillcode_live_now_smoke\` now and report the output." \
  "Running live TrustedRouter shell-action-now smoke with $MODEL" \
  validate_expected_outputs \
  "quillcode_live_now_smoke"

run_scenario \
  "shell-action-polite-bare" \
  "Can you run printf quillcode_live_polite_smoke?" \
  "Running live TrustedRouter shell-action-polite-bare smoke with $MODEL" \
  validate_expected_outputs \
  "quillcode_live_polite_smoke"

run_scenario \
  "diagnostic-question" \
  "whoami?" \
  "Running live TrustedRouter diagnostic-question smoke with $MODEL" \
  validate_expected_outputs \
  "$(id -un)"

run_scenario \
  "disk-usage" \
  "How much hd?" \
  "Running live TrustedRouter disk-usage smoke with $MODEL" \
  assert_output_matches \
  "Disk usage|available|used|[0-9]+%" \
  "disk usage result"

run_scenario \
  "git-status" \
  "git status" \
  "Running live TrustedRouter git-status smoke with $MODEL" \
  validate_expected_outputs \
  "Git status:" \
  "tracked.txt"

run_scenario \
  "git-status-polite" \
  "Please check git status." \
  "Running live TrustedRouter polite git-status smoke with $MODEL" \
  validate_expected_outputs \
  "Git status:" \
  "tracked.txt"

run_scenario \
  "git-diff" \
  "what changed?" \
  "Running live TrustedRouter git-diff smoke with $MODEL" \
  validate_expected_outputs \
  "Git diff:" \
  "tracked.txt" \
  "+after"

run_scenario \
  "git-branch-list" \
  "List git branches in this repo." \
  "Running live TrustedRouter git-branch-list smoke with $MODEL" \
  validate_expected_outputs \
  "quillcode-smoke-branch"

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
  validate_expected_outputs \
  "live-smoke.txt" \
  "hello-world.txt"

run_scenario \
  "workspace-list-natural" \
  "Can you list the files here?" \
  "Running live TrustedRouter natural workspace-list smoke with $MODEL" \
  validate_expected_outputs \
  "live-smoke.txt" \
  "hello-world.txt"

run_scenario \
  "workspace-pwd-natural" \
  "Can you show me the current directory?" \
  "Running live TrustedRouter natural current-directory smoke with $MODEL" \
  validate_expected_outputs \
  "$SMOKE_WORKSPACE_PHYSICAL"

run_scenario \
  "workspace-read-followup" \
  "Read \`hello-world.txt\` and tell me its exact content." \
  "Running live TrustedRouter workspace-read follow-up smoke with $MODEL" \
  validate_expected_outputs \
  "hello world"

run_scenario \
  "workspace-read-natural" \
  "What is in live-smoke.txt?" \
  "Running live TrustedRouter natural file-read smoke with $MODEL" \
  validate_expected_outputs \
  "quillcode_live_file_smoke"

run_scenario \
  "workspace-search-natural" \
  "Where is quillcode_live_file_smoke defined?" \
  "Running live TrustedRouter natural file-search smoke with $MODEL" \
  validate_expected_outputs \
  "live-smoke.txt"

run_scenario \
  "openclaw-discovery" \
  "Do you have openclaw?" \
  "Running live TrustedRouter OpenClaw discovery smoke with $MODEL" \
  assert_output_matches \
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

begin_scenario \
  "transcript-integrity" \
  "Validate persisted thread transcripts" \
  "Checking persisted live smoke transcripts"
assert_saved_transcripts_match_live_smoke_expectations 18 3
finish_scenario "" ""

write_artifact_manifest 0 "completed"
copy_live_artifacts 0
print_report_summary
echo "QuillCode live TrustedRouter smoke passed."
