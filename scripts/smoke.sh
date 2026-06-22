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

echo "==> Running Swift test suite"
swift test

echo "==> Running mock CLI shell command"
whoami_output="$(swift run quill-code --home "$SMOKE_HOME" --cwd "$SMOKE_WORKSPACE" "run whoami")"
if [[ -z "$whoami_output" ]]; then
  echo "quill-code did not return output for run whoami" >&2
  exit 1
fi

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

if [[ -d "$ROOT_DIR/E2E/playwright/node_modules" ]]; then
  echo "==> Running Playwright E2E suite"
  (cd "$ROOT_DIR/E2E/playwright" && npm test)
else
  echo "==> Skipping Playwright E2E; run npm install in E2E/playwright to include it"
fi

echo "QuillCode smoke passed."
