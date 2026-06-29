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
CLI_SHELL_STATUS="not-run"
CLI_DIAGNOSTICS_STATUS="not-run"
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
    "$CLI_SHELL_STATUS" \
    "$CLI_DIAGNOSTICS_STATUS" \
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
    cli_shell_status,
    cli_diagnostics_status,
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

requires_playwright = require_playwright.lower() in {"1", "true", "yes"}

manifest = {
    "generatedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "startedAt": started_at,
    "exitCode": int(exit_code),
    "detail": detail,
    "requiresPlaywright": requires_playwright,
    "artifactRoot": artifact_root,
    "steps": {
        "swiftTests": {"status": swift_tests_status},
        "cliShell": {"status": cli_shell_status},
        "cliNaturalDiagnostics": {"status": cli_diagnostics_status},
        "cliFileCreation": {"status": cli_file_creation_status},
        "cliWorkspaceFollowUp": {"status": cli_workspace_followup_status},
        "cliLocalDownload": {"status": cli_download_status},
        "liveModeMissingKeyError": {"status": live_error_status},
        "nativeDesktop": {"status": native_desktop_status},
        "packagedMacOS": {
            "status": packaged_macos_status,
            "detail": packaged_macos_detail,
        },
        "playwright": {
            "status": playwright_status,
            "detail": playwright_detail,
        },
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
  if grep -Eqi "No shell command was specified|I'?ll (run|check|do|download|create|write)" <<<"$output"; then
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

echo "==> Running Swift test suite"
SWIFT_TESTS_STATUS="running"
FINAL_DETAIL="Swift test suite failed"
swift test
SWIFT_TESTS_STATUS="passed"

echo "==> Running mock CLI shell command"
CLI_SHELL_STATUS="running"
FINAL_DETAIL="mock CLI shell command failed"
whoami_output="$(swift run quill-code --home "$SMOKE_HOME" --cwd "$SMOKE_WORKSPACE" "run whoami")"
assert_cli_no_action_regression "$whoami_output" "run whoami"
do_it_now_output="$(swift run quill-code --home "$SMOKE_HOME" --cwd "$SMOKE_WORKSPACE" "Please run \`printf quillcode_now_smoke\` now and report the output.")"
assert_cli_output_contains "$do_it_now_output" "quillcode_now_smoke" "run command now"
polite_bare_output="$(swift run quill-code --home "$SMOKE_HOME" --cwd "$SMOKE_WORKSPACE" "Can you run printf quillcode_polite_smoke?")"
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
assert_cli_output_contains "$list_files_output" "Output:" "list files"

current_directory_output="$(swift run quill-code --home "$SMOKE_HOME" --cwd "$SMOKE_WORKSPACE" "Can you show me the current directory?")"
assert_cli_output_contains "$current_directory_output" "$SMOKE_WORKSPACE_PHYSICAL" "current directory"

openclaw_output="$(swift run quill-code --home "$SMOKE_HOME" --cwd "$SMOKE_WORKSPACE" "Do you have openclaw?")"
assert_cli_output_contains "$openclaw_output" "openclaw" "Do you have openclaw?"
CLI_DIAGNOSTICS_STATUS="passed"

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
list_output="$(swift run quill-code --home "$SMOKE_HOME" --cwd "$SMOKE_WORKSPACE" "Run \`ls -1\` and tell me whether hello.txt is present")"
assert_cli_output_contains "$list_output" "hello.txt" "list created hello.txt"

read_output="$(swift run quill-code --home "$SMOKE_HOME" --cwd "$SMOKE_WORKSPACE" "Read \`hello.txt\` and tell me its exact content")"
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
  (cd "$ROOT_DIR/E2E/playwright" && npm test)
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
