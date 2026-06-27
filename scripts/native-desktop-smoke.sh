#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SMOKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/quillcode-native-desktop-smoke.XXXXXX")"
REPORT_PATH="$SMOKE_ROOT/report.json"
RENDER_PATH="$SMOKE_ROOT/workspace.png"
HTML_PATH="$SMOKE_ROOT/workspace.html"
STDOUT_PATH="$SMOKE_ROOT/stdout.log"

cleanup() {
  rm -rf "$SMOKE_ROOT"
}
trap cleanup EXIT

cd "$ROOT_DIR"

echo "==> Running native desktop executable render smoke"
swift run quill-code-desktop \
  --native-render-smoke \
  --smoke-workspace "$SMOKE_ROOT" \
  --smoke-report "$REPORT_PATH" \
  --smoke-render "$RENDER_PATH" \
  --smoke-html "$HTML_PATH" \
  >"$STDOUT_PATH"

if [[ ! -s "$REPORT_PATH" ]]; then
  echo "quill-code-desktop native smoke did not write a JSON report" >&2
  exit 1
fi
if [[ ! -s "$RENDER_PATH" ]]; then
  echo "quill-code-desktop native smoke did not write a rendered PNG" >&2
  cat "$REPORT_PATH" >&2 || true
  exit 1
fi
if [[ ! -s "$HTML_PATH" ]]; then
  echo "quill-code-desktop native smoke did not write rendered workspace HTML" >&2
  cat "$REPORT_PATH" >&2 || true
  exit 1
fi
if ! grep -q '"ok" : true' "$REPORT_PATH"; then
  echo "quill-code-desktop native smoke did not report ok=true" >&2
  cat "$REPORT_PATH" >&2
  exit 1
fi
if ! grep -q '"toolName" : "host.file.write"' "$REPORT_PATH"; then
  echo "quill-code-desktop native smoke did not execute the expected file-write tool" >&2
  cat "$REPORT_PATH" >&2
  exit 1
fi
if ! grep -Eq '"messageCount" : [2-9][0-9]*' "$REPORT_PATH"; then
  echo "quill-code-desktop native smoke did not record enough transcript messages" >&2
  cat "$REPORT_PATH" >&2
  exit 1
fi
if ! grep -Eq '"timelineItemCount" : [3-9][0-9]*' "$REPORT_PATH"; then
  echo "quill-code-desktop native smoke did not record enough timeline items" >&2
  cat "$REPORT_PATH" >&2
  exit 1
fi
if ! grep -q 'Wrote `hello.txt`.' "$REPORT_PATH"; then
  echo "quill-code-desktop native smoke did not produce the expected final answer" >&2
  cat "$REPORT_PATH" >&2
  exit 1
fi
if ! grep -q 'Wrote `hello.txt`.' "$HTML_PATH" || ! grep -q 'host.file.write' "$HTML_PATH"; then
  echo "quill-code-desktop native smoke rendered HTML did not contain the result transcript" >&2
  cat "$REPORT_PATH" >&2
  exit 1
fi
if [[ "$(wc -c < "$RENDER_PATH" | tr -d ' ')" -lt 4096 ]]; then
  echo "quill-code-desktop native smoke rendered a suspiciously small PNG" >&2
  ls -l "$RENDER_PATH" >&2
  cat "$REPORT_PATH" >&2
  exit 1
fi

echo "QuillCode native desktop smoke passed."
