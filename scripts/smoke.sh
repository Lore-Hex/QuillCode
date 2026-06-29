#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SMOKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/quillcode-smoke.XXXXXX")"
SMOKE_HOME="$SMOKE_ROOT/home"
SMOKE_WORKSPACE="$SMOKE_ROOT/workspace"

cleanup() {
  rm -rf "$SMOKE_ROOT"
}
trap cleanup EXIT

mkdir -p "$SMOKE_HOME" "$SMOKE_WORKSPACE"
cd "$ROOT_DIR"

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
swift test

echo "==> Running mock CLI shell command"
whoami_output="$(swift run quill-code --home "$SMOKE_HOME" --cwd "$SMOKE_WORKSPACE" "run whoami")"
assert_cli_no_action_regression "$whoami_output" "run whoami"

echo "==> Running mock CLI natural diagnostic prompts"
whoami_question_output="$(swift run quill-code --home "$SMOKE_HOME" --cwd "$SMOKE_WORKSPACE" "whoami?")"
assert_cli_output_contains "$whoami_question_output" "$(id -un)" "whoami?"

disk_output="$(swift run quill-code --home "$SMOKE_HOME" --cwd "$SMOKE_WORKSPACE" "How much hd?")"
assert_cli_output_contains "$disk_output" "Disk usage" "How much hd?"

openclaw_output="$(swift run quill-code --home "$SMOKE_HOME" --cwd "$SMOKE_WORKSPACE" "Do you have openclaw?")"
assert_cli_output_contains "$openclaw_output" "openclaw" "Do you have openclaw?"

echo "==> Running mock CLI file creation"
swift run quill-code --home "$SMOKE_HOME" --cwd "$SMOKE_WORKSPACE" "make a file that says hello world" >/dev/null
if [[ ! -f "$SMOKE_WORKSPACE/hello.txt" ]]; then
  echo "quill-code did not create hello.txt in the smoke workspace" >&2
  exit 1
fi
if [[ "$(tr -d '\r' < "$SMOKE_WORKSPACE/hello.txt")" != "hello world" ]]; then
  echo "hello.txt did not contain the expected smoke content" >&2
  exit 1
fi

echo "==> Running mock CLI local download"
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

echo "==> Verifying CLI live-mode errors are readable"
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

"$ROOT_DIR/scripts/native-desktop-smoke.sh"

if [[ "$(uname -s)" == "Darwin" ]]; then
  "$ROOT_DIR/scripts/packaged-macos-smoke.sh"
fi

if [[ -d "$ROOT_DIR/E2E/playwright/node_modules" ]]; then
  echo "==> Running Playwright E2E suite"
  (cd "$ROOT_DIR/E2E/playwright" && npm test)
else
  echo "==> Skipping Playwright E2E; run npm install in E2E/playwright to include it"
fi

echo "QuillCode smoke passed."
