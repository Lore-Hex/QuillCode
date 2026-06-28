#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SMOKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/quillcode-native-desktop-smoke.XXXXXX")"
REPORT_PATH="$SMOKE_ROOT/report.json"
RENDER_PATH="$SMOKE_ROOT/workspace.png"
CHROME_RENDER_PATH="$SMOKE_ROOT/chrome.png"
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
  --smoke-chrome-render "$CHROME_RENDER_PATH" \
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
if [[ ! -s "$CHROME_RENDER_PATH" ]]; then
  echo "quill-code-desktop native smoke did not write a desktop chrome rendered PNG" >&2
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
if ! grep -q '"appName" : "QuillCode"' "$REPORT_PATH"; then
  echo "quill-code-desktop native smoke did not validate the desktop chrome surface" >&2
  cat "$REPORT_PATH" >&2
  exit 1
fi
python3 - "$REPORT_PATH" <<'PY'
import json
import math
import sys

report_path = sys.argv[1]
with open(report_path, "r", encoding="utf-8") as report_file:
    report = json.load(report_file)

native_targets = report.get("nativeHitTargets")
if not isinstance(native_targets, dict):
    raise SystemExit("quill-code-desktop native smoke did not include native hit target contracts")

if native_targets.get("isValid") is not True:
    raise SystemExit("quill-code-desktop native smoke did not validate native hit target contracts")

if native_targets.get("minimumHitTarget") != 44:
    raise SystemExit("quill-code-desktop native smoke reported unexpected native minimum hit target")

press_scale = native_targets.get("pressScale")
if not isinstance(press_scale, (int, float)) or not math.isclose(press_scale, 0.96, rel_tol=0.0, abs_tol=1e-9):
    raise SystemExit("quill-code-desktop native smoke reported unexpected native press scale")

contracts = native_targets.get("designSystemContracts", []) + native_targets.get("surfaceContracts", [])
contract_kinds = {contract.get("kind") for contract in contracts if isinstance(contract, dict)}
required_kinds = {"icon", "textButton", "formAction", "textEntry", "segmentedControl", "adjustableControl", "switchRow", "ownedGesture", "fullRow", "capsule"}
missing_kinds = sorted(required_kinds - contract_kinds)
if missing_kinds:
    raise SystemExit(f"quill-code-desktop native smoke did not include native target kinds: {', '.join(missing_kinds)}")

contract_families = {contract.get("family") for contract in contracts if isinstance(contract, dict)}
required_families = {
    "design-system", "workspace-chrome", "sidebar", "sidebar-thread-list", "top-bar",
    "composer", "transcript", "tool-card", "context-banner", "command-palette",
    "search", "settings", "model-picker", "review", "secondary-pane", "terminal",
    "browser", "extensions", "memories", "automations", "menu-bar"
}
missing_families = sorted(required_families - contract_families)
if missing_families:
    raise SystemExit(f"quill-code-desktop native smoke did not include native target surface families: {', '.join(missing_families)}")
PY
for command_id in command-palette keyboard-shortcuts settings toggle-terminal toggle-browser; do
  if ! grep -q "$command_id" "$REPORT_PATH"; then
    echo "quill-code-desktop native smoke did not exercise chrome command: $command_id" >&2
    cat "$REPORT_PATH" >&2
    exit 1
  fi
done
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
if [[ "$(wc -c < "$CHROME_RENDER_PATH" | tr -d ' ')" -lt 2048 ]]; then
  echo "quill-code-desktop native smoke rendered a suspiciously small desktop chrome PNG" >&2
  ls -l "$CHROME_RENDER_PATH" >&2
  cat "$REPORT_PATH" >&2
  exit 1
fi

echo "QuillCode native desktop smoke passed."
