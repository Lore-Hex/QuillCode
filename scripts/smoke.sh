#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SMOKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/quillcode-smoke.XXXXXX")"
SMOKE_HOME="$SMOKE_ROOT/home"
SMOKE_WORKSPACE="$SMOKE_ROOT/workspace"
ARTIFACT_DIR="${QUILLCODE_SMOKE_ARTIFACT_DIR:-}"
REQUIRE_PLAYWRIGHT="${QUILLCODE_REQUIRE_PLAYWRIGHT_SMOKE:-0}"
STARTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
FINAL_DETAIL="interrupted"
SWIFT_TESTS_STATUS="not-run"
APP_SERVER_STATUS="not-run"
CLI_DOCTOR_STATUS="not-run"
CLI_REVIEW_STATUS="not-run"
CLI_SHELL_STATUS="not-run"
CLI_DIAGNOSTICS_STATUS="not-run"
CLI_GIT_READ_STATUS="not-run"
CLI_FILE_READ_STATUS="not-run"
CLI_FILE_SEARCH_STATUS="not-run"
CLI_NEGATIVE_ACTION_STATUS="not-run"
CLI_FILE_CREATION_STATUS="not-run"
CLI_WORKSPACE_FOLLOWUP_STATUS="not-run"
CLI_DOWNLOAD_STATUS="not-run"
LIVE_ERROR_STATUS="not-run"
NATIVE_DESKTOP_STATUS="not-run"
PACKAGED_MACOS_STATUS="skipped"
PACKAGED_MACOS_DETAIL="not Darwin"
PLAYWRIGHT_STATUS="not-run"
PLAYWRIGHT_DETAIL="not-started"

if [[ -n "$ARTIFACT_DIR" ]]; then
  mkdir -p "$ARTIFACT_DIR"
  ARTIFACT_DIR="$(cd "$ARTIFACT_DIR" && pwd)"
fi

write_manifest() {
  local exit_code="$1"
  local detail="$2"

  if [[ -z "$ARTIFACT_DIR" ]]; then
    return 0
  fi

  python3 - "$ARTIFACT_DIR/deterministic-smoke-manifest.json" \
    "$exit_code" \
    "$detail" \
    "$STARTED_AT" \
    "$REQUIRE_PLAYWRIGHT" \
    "$ARTIFACT_DIR" \
    "$SMOKE_WORKSPACE" \
    "$SWIFT_TESTS_STATUS" \
    "$APP_SERVER_STATUS" \
    "$CLI_DOCTOR_STATUS" \
    "$CLI_REVIEW_STATUS" \
    "$CLI_SHELL_STATUS" \
    "$CLI_DIAGNOSTICS_STATUS" \
    "$CLI_GIT_READ_STATUS" \
    "$CLI_FILE_READ_STATUS" \
    "$CLI_FILE_SEARCH_STATUS" \
    "$CLI_NEGATIVE_ACTION_STATUS" \
    "$CLI_FILE_CREATION_STATUS" \
    "$CLI_WORKSPACE_FOLLOWUP_STATUS" \
    "$CLI_DOWNLOAD_STATUS" \
    "$LIVE_ERROR_STATUS" \
    "$NATIVE_DESKTOP_STATUS" \
    "$PACKAGED_MACOS_STATUS" \
    "$PACKAGED_MACOS_DETAIL" \
    "$PLAYWRIGHT_STATUS" \
    "$PLAYWRIGHT_DETAIL" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone

(
    manifest_path,
    exit_code,
    detail,
    started_at,
    require_playwright,
    artifact_root,
    smoke_workspace,
    swift_tests_status,
    app_server_status,
    cli_doctor_status,
    cli_review_status,
    cli_shell_status,
    cli_diagnostics_status,
    cli_git_read_status,
    cli_file_read_status,
    cli_file_search_status,
    cli_negative_action_status,
    cli_file_creation_status,
    cli_workspace_followup_status,
    cli_download_status,
    live_error_status,
    native_desktop_status,
    packaged_macos_status,
    packaged_macos_detail,
    playwright_status,
    playwright_detail,
) = sys.argv[1:]

def collect_files(root, limit=200):
    if not root or not os.path.isdir(root):
        return []
    files = []
    for current_root, directories, names in os.walk(root):
        directories.sort()
        for name in sorted(names):
            path = os.path.join(current_root, name)
            try:
                stat = os.stat(path)
            except OSError:
                continue
            files.append({
                "path": os.path.relpath(path, root),
                "bytes": stat.st_size,
            })
            if len(files) >= limit:
                return files
    return files

def load_json(path):
    if not path or not os.path.isfile(path):
        return None
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, json.JSONDecodeError) as error:
        return {"error": str(error)}

def relative_artifact_path(path):
    if not artifact_root or not path:
        return path
    try:
        return os.path.relpath(path, artifact_root)
    except ValueError:
        return path

requires_playwright = require_playwright.lower() in {"1", "true", "yes"}
playwright_real_world_manifest_path = os.path.join(
    artifact_root,
    "playwright-real-world",
    "playwright-real-world-actions-manifest.json",
)
playwright_real_world_manifest = load_json(playwright_real_world_manifest_path)
playwright_step = {
    "status": playwright_status,
    "detail": playwright_detail,
}
if playwright_real_world_manifest is not None:
    playwright_step["realWorldActions"] = {
        "status": "present",
        "manifestPath": relative_artifact_path(playwright_real_world_manifest_path),
        "scenarioCount": playwright_real_world_manifest.get("scenarioCount"),
        "promptCount": playwright_real_world_manifest.get("promptCount"),
        "regressionGuardCount": playwright_real_world_manifest.get("regressionGuardCount"),
        "manifest": playwright_real_world_manifest,
    }
elif playwright_status == "passed" and artifact_root:
    playwright_step["realWorldActions"] = {
        "status": "missing",
        "manifestPath": relative_artifact_path(playwright_real_world_manifest_path),
    }

manifest = {
    "generatedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "startedAt": started_at,
    "exitCode": int(exit_code),
    "detail": detail,
    "requiresPlaywright": requires_playwright,
    "artifactRoot": artifact_root,
    "steps": {
        "swiftTests": {"status": swift_tests_status},
        "appServer": {"status": app_server_status},
        "cliDoctor": {"status": cli_doctor_status},
        "cliReview": {"status": cli_review_status},
        "cliShell": {"status": cli_shell_status},
        "cliNaturalDiagnostics": {"status": cli_diagnostics_status},
        "cliGitRead": {"status": cli_git_read_status},
        "cliFileRead": {"status": cli_file_read_status},
        "cliFileSearch": {"status": cli_file_search_status},
        "cliNegativeActions": {"status": cli_negative_action_status},
        "cliFileCreation": {"status": cli_file_creation_status},
        "cliWorkspaceFollowUp": {"status": cli_workspace_followup_status},
        "cliLocalDownload": {"status": cli_download_status},
        "liveModeMissingKeyError": {"status": live_error_status},
        "nativeDesktop": {"status": native_desktop_status},
        "packagedMacOS": {
            "status": packaged_macos_status,
            "detail": packaged_macos_detail,
        },
        "playwright": playwright_step,
    },
    "artifactFiles": collect_files(artifact_root),
    "workspaceFiles": collect_files(smoke_workspace),
}

with open(manifest_path, "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
}

cleanup() {
  local status=$?
  set +e
  write_manifest "$status" "$FINAL_DETAIL"
  if [[ -n "$ARTIFACT_DIR" ]]; then
    echo "QuillCode deterministic smoke artifacts: $ARTIFACT_DIR"
  fi
  rm -rf "$SMOKE_ROOT"
  trap - EXIT
  exit "$status"
}
trap cleanup EXIT

mkdir -p "$SMOKE_HOME" "$SMOKE_WORKSPACE"
SMOKE_WORKSPACE_PHYSICAL="$(cd "$SMOKE_WORKSPACE" && pwd -P)"
cd "$ROOT_DIR"

PASSIVE_ACTION_PATTERN="No shell command was specified|"
PASSIVE_ACTION_PATTERN+="(I'?ll|I will) "
PASSIVE_ACTION_PATTERN+="(run|check|do|download|create|write|execute|inspect|list|show|review|read|fetch|save)"

is_truthy() {
  case "$1" in
    1|true|TRUE|yes|YES)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

assert_cli_no_action_regression() {
  local output="$1"
  local label="$2"

  if [[ -z "$output" ]]; then
    echo "quill-code returned no output for $label" >&2
    exit 1
  fi
  if grep -Eqi "$PASSIVE_ACTION_PATTERN" <<<"$output"; then
    echo "quill-code regressed into passive or empty-tool output for $label" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
}

assert_cli_output_contains() {
  local output="$1"
  local expected="$2"
  local label="$3"

  assert_cli_no_action_regression "$output" "$label"
  if ! grep -Fqi "$expected" <<<"$output"; then
    echo "quill-code output for $label did not contain expected text: $expected" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
}

assert_playwright_real_world_manifest() {
  if [[ -z "$ARTIFACT_DIR" ]]; then
    return 0
  fi

  local manifest_path="$ARTIFACT_DIR/playwright-real-world/playwright-real-world-actions-manifest.json"
  "$ROOT_DIR/scripts/validate-playwright-real-world-manifest.py" "$manifest_path"
}

prepare_git_workspace() {
  git -C "$SMOKE_WORKSPACE" init >/dev/null
  git -C "$SMOKE_WORKSPACE" config user.email quillcode-smoke@example.com
  git -C "$SMOKE_WORKSPACE" config user.name "QuillCode Smoke"
  printf 'before\n' > "$SMOKE_WORKSPACE/tracked.txt"
  git -C "$SMOKE_WORKSPACE" add tracked.txt
  git -C "$SMOKE_WORKSPACE" commit -m "Add tracked smoke file" >/dev/null
  printf '# QuillCode smoke README\n\nNatural file reads should use host.file.read.\n' > "$SMOKE_WORKSPACE/README.md"
  mkdir -p "$SMOKE_WORKSPACE/Sources"
  printf 'struct SmokeSearchSymbol {\n  let value = "needle"\n}\n' > "$SMOKE_WORKSPACE/Sources/SmokeSearch.swift"
  printf 'after\n' > "$SMOKE_WORKSPACE/tracked.txt"
}

FINAL_DETAIL="mock CLI git fixture setup failed"
prepare_git_workspace

echo "==> Running Swift test suite"
SWIFT_TESTS_STATUS="running"
FINAL_DETAIL="Swift test suite failed"
swift test
SWIFT_TESTS_STATUS="passed"

echo "==> Running non-interactive CLI process smoke"
FINAL_DETAIL="non-interactive CLI process smoke failed"
"$ROOT_DIR/scripts/cli-exec-smoke.sh"

echo "==> Running CLI doctor process smoke"
CLI_DOCTOR_STATUS="running"
FINAL_DETAIL="CLI doctor process smoke failed"
"$ROOT_DIR/scripts/cli-doctor-smoke.sh"
CLI_DOCTOR_STATUS="passed"

echo "==> Running CLI review process smoke"
CLI_REVIEW_STATUS="running"
FINAL_DETAIL="CLI review process smoke failed"
"$ROOT_DIR/scripts/cli-review-smoke.sh"
CLI_REVIEW_STATUS="passed"

echo "==> Running app-server protocol smoke"
APP_SERVER_STATUS="running"
FINAL_DETAIL="app-server protocol smoke failed"
"$ROOT_DIR/scripts/app-server-smoke.sh"
APP_SERVER_STATUS="passed"

echo "==> Running mock CLI shell command"
CLI_SHELL_STATUS="running"
FINAL_DETAIL="mock CLI shell command failed"
whoami_output="$(swift run quill-code --home "$SMOKE_HOME" --cwd "$SMOKE_WORKSPACE" "run whoami")"
assert_cli_no_action_regression "$whoami_output" "run whoami"
do_it_now_output="$(swift run quill-code \
  --home "$SMOKE_HOME" \
  --cwd "$SMOKE_WORKSPACE" \
  "Please run \`printf quillcode_now_smoke\` now and report the output.")"
assert_cli_output_contains "$do_it_now_output" "quillcode_now_smoke" "run command now"
polite_bare_output="$(swift run quill-code \
  --home "$SMOKE_HOME" \
  --cwd "$SMOKE_WORKSPACE" \
  "Can you run printf quillcode_polite_smoke?")"
assert_cli_output_contains "$polite_bare_output" "quillcode_polite_smoke" "polite bare command"
CLI_SHELL_STATUS="passed"

echo "==> Running mock CLI natural diagnostic prompts"
CLI_DIAGNOSTICS_STATUS="running"
FINAL_DETAIL="mock CLI natural diagnostic prompts failed"
whoami_question_output="$(swift run quill-code --home "$SMOKE_HOME" --cwd "$SMOKE_WORKSPACE" "whoami?")"
assert_cli_output_contains "$whoami_question_output" "$(id -un)" "whoami?"

disk_output="$(swift run quill-code --home "$SMOKE_HOME" --cwd "$SMOKE_WORKSPACE" "How much hd?")"
assert_cli_output_contains "$disk_output" "Disk usage" "How much hd?"

list_files_output="$(swift run quill-code --home "$SMOKE_HOME" --cwd "$SMOKE_WORKSPACE" "Can you list the files here?")"
assert_cli_output_contains "$list_files_output" "README.md" "list files"
assert_cli_output_contains "$list_files_output" "Sources/" "list files"
assert_cli_output_contains "$list_files_output" "contains" "list files"

current_directory_output="$(swift run quill-code \
  --home "$SMOKE_HOME" \
  --cwd "$SMOKE_WORKSPACE" \
  "Can you show me the current directory?")"
assert_cli_output_contains "$current_directory_output" "$SMOKE_WORKSPACE_PHYSICAL" "current directory"

openclaw_output="$(swift run quill-code --home "$SMOKE_HOME" --cwd "$SMOKE_WORKSPACE" "Do you have openclaw?")"
assert_cli_output_contains "$openclaw_output" "openclaw" "Do you have openclaw?"
CLI_DIAGNOSTICS_STATUS="passed"

echo "==> Running mock CLI git read prompts"
CLI_GIT_READ_STATUS="running"
FINAL_DETAIL="mock CLI git read prompts failed"
git_status_output="$(swift run quill-code --home "$SMOKE_HOME" --cwd "$SMOKE_WORKSPACE" "Please check git status.")"
assert_cli_output_contains "$git_status_output" "Git status:" "Please check git status"
assert_cli_output_contains "$git_status_output" "tracked.txt" "Please check git status"

git_diff_output="$(swift run quill-code --home "$SMOKE_HOME" --cwd "$SMOKE_WORKSPACE" "what changed?")"
assert_cli_output_contains "$git_diff_output" "Git diff:" "what changed?"
assert_cli_output_contains "$git_diff_output" "tracked.txt" "what changed?"
assert_cli_output_contains "$git_diff_output" "+after" "what changed?"
CLI_GIT_READ_STATUS="passed"

echo "==> Running mock CLI natural file read prompt"
CLI_FILE_READ_STATUS="running"
FINAL_DETAIL="mock CLI natural file read prompt failed"
file_read_output="$(swift run quill-code --home "$SMOKE_HOME" --cwd "$SMOKE_WORKSPACE" "What is in README.md?")"
assert_cli_output_contains "$file_read_output" 'Contents of `README.md`' "What is in README.md"
assert_cli_output_contains "$file_read_output" "QuillCode smoke README" "What is in README.md"
CLI_FILE_READ_STATUS="passed"

echo "==> Running mock CLI natural file search prompt"
CLI_FILE_SEARCH_STATUS="running"
FINAL_DETAIL="mock CLI natural file search prompt failed"
file_search_output="$(swift run quill-code \
  --home "$SMOKE_HOME" \
  --cwd "$SMOKE_WORKSPACE" \
  "Where is SmokeSearchSymbol defined?")"
assert_cli_output_contains \
  "$file_search_output" \
  'Found 1 match for `SmokeSearchSymbol`' \
  "Where is SmokeSearchSymbol defined"
assert_cli_output_contains "$file_search_output" 'Sources/SmokeSearch.swift:1' "Where is SmokeSearchSymbol defined"
CLI_FILE_SEARCH_STATUS="passed"

echo "==> Running mock CLI negative action prompts"
CLI_NEGATIVE_ACTION_STATUS="running"
FINAL_DETAIL="mock CLI negative action prompts failed"
negated_run_output="$(swift run quill-code --home "$SMOKE_HOME" --cwd "$SMOKE_WORKSPACE" "Do not run whoami.")"
assert_cli_output_contains "$negated_run_output" "won't take that action" "Do not run whoami"
if grep -Fqi "You are" <<<"$negated_run_output"; then
  echo "quill-code ran whoami despite explicit negative intent" >&2
  printf '%s\n' "$negated_run_output" >&2
  exit 1
fi

negated_write_output="$(swift run quill-code \
  --home "$SMOKE_HOME" \
  --cwd "$SMOKE_WORKSPACE" \
  "Do not write \`forbidden.txt\` with content \`nope\`.")"
assert_cli_output_contains "$negated_write_output" "won't take that action" "Do not write forbidden.txt"
if [[ -e "$SMOKE_WORKSPACE/forbidden.txt" ]]; then
  echo "quill-code created forbidden.txt despite explicit negative intent" >&2
  exit 1
fi

negated_download_output="$(swift run quill-code \
  --home "$SMOKE_HOME" \
  --cwd "$SMOKE_WORKSPACE" \
  "Don't download https://example.com into \`downloads/forbidden.html\`.")"
assert_cli_output_contains "$negated_download_output" "won't take that action" "Don't download forbidden.html"
if [[ -e "$SMOKE_WORKSPACE/downloads/forbidden.html" ]]; then
  echo "quill-code downloaded forbidden.html despite explicit negative intent" >&2
  exit 1
fi
CLI_NEGATIVE_ACTION_STATUS="passed"

echo "==> Running mock CLI file creation"
CLI_FILE_CREATION_STATUS="running"
FINAL_DETAIL="mock CLI file creation failed"
swift run quill-code --home "$SMOKE_HOME" --cwd "$SMOKE_WORKSPACE" "make a file that says hello world" >/dev/null
if [[ ! -f "$SMOKE_WORKSPACE/hello.txt" ]]; then
  echo "quill-code did not create hello.txt in the smoke workspace" >&2
  exit 1
fi
if [[ "$(tr -d '\r' < "$SMOKE_WORKSPACE/hello.txt")" != "hello world" ]]; then
  echo "hello.txt did not contain the expected smoke content" >&2
  exit 1
fi
CLI_FILE_CREATION_STATUS="passed"

echo "==> Running mock CLI workspace follow-up"
CLI_WORKSPACE_FOLLOWUP_STATUS="running"
FINAL_DETAIL="mock CLI workspace follow-up failed"
list_output="$(swift run quill-code \
  --home "$SMOKE_HOME" \
  --cwd "$SMOKE_WORKSPACE" \
  "Run \`ls -1\` and tell me whether hello.txt is present")"
assert_cli_output_contains "$list_output" "hello.txt" "list created hello.txt"

read_output="$(swift run quill-code \
  --home "$SMOKE_HOME" \
  --cwd "$SMOKE_WORKSPACE" \
  "Read \`hello.txt\` and tell me its exact content")"
assert_cli_output_contains "$read_output" "hello world" "read created hello.txt"
CLI_WORKSPACE_FOLLOWUP_STATUS="passed"

echo "==> Running mock CLI local download"
CLI_DOWNLOAD_STATUS="running"
FINAL_DETAIL="mock CLI local download failed"
DOWNLOAD_SOURCE="$SMOKE_ROOT/source.html"
printf '<!doctype html><title>QuillCode smoke</title>\n' > "$DOWNLOAD_SOURCE"
download_output="$(swift run quill-code \
  --home "$SMOKE_HOME" \
  --cwd "$SMOKE_WORKSPACE" \
  "Download file://$DOWNLOAD_SOURCE into \`downloads/example.html\` in this workspace.")"
assert_cli_output_contains "$download_output" "downloads/example.html" "local file download"
if [[ ! -s "$SMOKE_WORKSPACE/downloads/example.html" ]]; then
  echo "quill-code did not create downloads/example.html in the smoke workspace" >&2
  find "$SMOKE_WORKSPACE" -maxdepth 3 -type f -print >&2
  exit 1
fi
if ! grep -q "QuillCode smoke" "$SMOKE_WORKSPACE/downloads/example.html"; then
  echo "downloads/example.html did not contain the expected downloaded content" >&2
  cat "$SMOKE_WORKSPACE/downloads/example.html" >&2
  exit 1
fi
CLI_DOWNLOAD_STATUS="passed"

echo "==> Verifying CLI live-mode errors are readable"
LIVE_ERROR_STATUS="running"
FINAL_DETAIL="CLI live-mode missing-key error check failed"
LIVE_ERROR_STDOUT="$SMOKE_ROOT/live-error.stdout"
LIVE_ERROR_STDERR="$SMOKE_ROOT/live-error.stderr"
if env -u QUILLCODE_API_KEY -u TRUSTEDROUTER_API_KEY swift run quill-code \
  --live \
  --home "$SMOKE_ROOT/live-home" \
  --cwd "$SMOKE_WORKSPACE" \
  "reply with hello" \
  >"$LIVE_ERROR_STDOUT" \
  2>"$LIVE_ERROR_STDERR"; then
  echo "quill-code --live unexpectedly succeeded without a TrustedRouter key" >&2
  exit 1
fi
if ! grep -q "quill-code:" "$LIVE_ERROR_STDERR"; then
  echo "quill-code --live did not print a readable CLI error prefix" >&2
  cat "$LIVE_ERROR_STDERR" >&2
  exit 1
fi
if grep -q "Fatal error" "$LIVE_ERROR_STDERR"; then
  echo "quill-code --live crashed instead of returning a readable error" >&2
  cat "$LIVE_ERROR_STDERR" >&2
  exit 1
fi
LIVE_ERROR_STATUS="passed"

NATIVE_DESKTOP_STATUS="running"
FINAL_DETAIL="native desktop smoke failed"
QUILLCODE_NATIVE_DESKTOP_SMOKE_ARTIFACT_DIR="${ARTIFACT_DIR:+$ARTIFACT_DIR/native-desktop}" \
  "$ROOT_DIR/scripts/native-desktop-smoke.sh"
NATIVE_DESKTOP_STATUS="passed"

if [[ "$(uname -s)" == "Darwin" ]]; then
  PACKAGED_MACOS_STATUS="running"
  PACKAGED_MACOS_DETAIL="running"
  FINAL_DETAIL="packaged macOS smoke failed"
  QUILLCODE_PACKAGED_MACOS_SMOKE_ARTIFACT_DIR="${ARTIFACT_DIR:+$ARTIFACT_DIR/packaged-macos}" \
    "$ROOT_DIR/scripts/packaged-macos-smoke.sh"
  PACKAGED_MACOS_STATUS="passed"
  PACKAGED_MACOS_DETAIL="completed"
fi

if [[ -d "$ROOT_DIR/E2E/playwright/node_modules" ]]; then
  echo "==> Running Playwright E2E suite"
  PLAYWRIGHT_STATUS="running"
  PLAYWRIGHT_DETAIL="running"
  FINAL_DETAIL="Playwright E2E failed"
  (
    cd "$ROOT_DIR/E2E/playwright"
    QUILLCODE_PLAYWRIGHT_REAL_WORLD_ARTIFACT_DIR="${ARTIFACT_DIR:+$ARTIFACT_DIR/playwright-real-world}" \
      npm test
  )
  assert_playwright_real_world_manifest
  PLAYWRIGHT_STATUS="passed"
  PLAYWRIGHT_DETAIL="completed"
elif is_truthy "$REQUIRE_PLAYWRIGHT"; then
  PLAYWRIGHT_STATUS="missing-dependencies"
  PLAYWRIGHT_DETAIL="E2E/playwright/node_modules is missing"
  FINAL_DETAIL="Playwright E2E dependencies are missing"
  echo "Playwright E2E was required, but E2E/playwright/node_modules is missing." >&2
  echo "Run npm ci in E2E/playwright before running this smoke gate." >&2
  exit 2
else
  PLAYWRIGHT_STATUS="skipped"
  PLAYWRIGHT_DETAIL="E2E/playwright/node_modules is missing and Playwright is not required"
  echo "==> Skipping Playwright E2E; run npm install in E2E/playwright to include it"
fi

FINAL_DETAIL="completed"
echo "QuillCode smoke passed."
