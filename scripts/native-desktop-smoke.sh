#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SMOKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/quillcode-native-desktop-smoke.XXXXXX")"
REPORT_PATH="$SMOKE_ROOT/report.json"
RENDER_PATH="$SMOKE_ROOT/workspace.png"
RESULT_RENDER_PATH="$SMOKE_ROOT/result.png"
CHROME_RENDER_PATH="$SMOKE_ROOT/chrome.png"
HTML_PATH="$SMOKE_ROOT/workspace.html"
STDOUT_PATH="$SMOKE_ROOT/stdout.log"
TARGET_LABEL="${QUILLCODE_NATIVE_DESKTOP_SMOKE_LABEL:-native desktop executable}"
DESKTOP_EXECUTABLE="${QUILLCODE_DESKTOP_EXECUTABLE:-}"
DESKTOP_APP_BUNDLE="${QUILLCODE_DESKTOP_APP_BUNDLE:-}"
ARTIFACT_DIR="${QUILLCODE_NATIVE_DESKTOP_SMOKE_ARTIFACT_DIR:-}"
KEEP_ARTIFACTS="${QUILLCODE_NATIVE_DESKTOP_SMOKE_KEEP_ARTIFACTS:-}"

cleanup() {
  local status=$?
  set +e

  if [[ -n "$ARTIFACT_DIR" ]]; then
    mkdir -p "$ARTIFACT_DIR"
    for artifact_path in "$REPORT_PATH" "$RENDER_PATH" "$RESULT_RENDER_PATH" "$CHROME_RENDER_PATH" "$HTML_PATH" "$STDOUT_PATH"; do
      if [[ -e "$artifact_path" ]]; then
        cp "$artifact_path" "$ARTIFACT_DIR/$(basename "$artifact_path")"
      fi
    done
    {
      printf 'label=%s\n' "$TARGET_LABEL"
      printf 'status=%s\n' "$status"
      printf 'source=%s\n' "$SMOKE_ROOT"
      printf 'report=report.json\n'
      printf 'workspace_png=workspace.png\n'
      printf 'result_png=result.png\n'
      printf 'chrome_png=chrome.png\n'
      printf 'workspace_html=workspace.html\n'
      printf 'stdout=stdout.log\n'
    } > "$ARTIFACT_DIR/manifest.txt"
    echo "QuillCode $TARGET_LABEL smoke artifacts: $ARTIFACT_DIR"
  fi

  if [[ "$KEEP_ARTIFACTS" == "1" ]]; then
    echo "QuillCode $TARGET_LABEL temporary smoke root preserved: $SMOKE_ROOT"
  else
    rm -rf "$SMOKE_ROOT"
  fi

  exit "$status"
}
trap cleanup EXIT

cd "$ROOT_DIR"

if [[ -n "$DESKTOP_EXECUTABLE" && -n "$DESKTOP_APP_BUNDLE" ]]; then
  echo "Set only one of QUILLCODE_DESKTOP_EXECUTABLE or QUILLCODE_DESKTOP_APP_BUNDLE." >&2
  exit 2
fi

if [[ -n "$DESKTOP_APP_BUNDLE" ]]; then
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "QUILLCODE_DESKTOP_APP_BUNDLE launch smoke requires macOS." >&2
    exit 2
  fi
  if [[ ! -d "$DESKTOP_APP_BUNDLE" ]]; then
    echo "Configured desktop app bundle is missing: $DESKTOP_APP_BUNDLE" >&2
    exit 1
  fi
  COMMAND=(open -W -n "$DESKTOP_APP_BUNDLE" --args)
elif [[ -n "$DESKTOP_EXECUTABLE" ]]; then
  if [[ ! -x "$DESKTOP_EXECUTABLE" ]]; then
    echo "Configured desktop executable is missing or not executable: $DESKTOP_EXECUTABLE" >&2
    exit 1
  fi
  COMMAND=("$DESKTOP_EXECUTABLE")
else
  COMMAND=(swift run quill-code-desktop)
fi

echo "==> Running $TARGET_LABEL render smoke"
"${COMMAND[@]}" \
  --native-render-smoke \
  --smoke-workspace "$SMOKE_ROOT" \
  --smoke-report "$REPORT_PATH" \
  --smoke-render "$RENDER_PATH" \
  --smoke-result-render "$RESULT_RENDER_PATH" \
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
if [[ ! -s "$RESULT_RENDER_PATH" ]]; then
  echo "quill-code-desktop native smoke did not write a result evidence PNG" >&2
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
if ! grep -q '"followUpToolName" : "host.file.read"' "$REPORT_PATH"; then
  echo "quill-code-desktop native smoke did not execute the expected follow-up file-read tool" >&2
  cat "$REPORT_PATH" >&2
  exit 1
fi
if ! grep -Fq '"toolNames" : [' "$REPORT_PATH" \
  || ! grep -q '"host.file.write"' "$REPORT_PATH" \
  || ! grep -q '"host.file.read"' "$REPORT_PATH"; then
  echo "quill-code-desktop native smoke did not report both write and read tool names" >&2
  cat "$REPORT_PATH" >&2
  exit 1
fi
if ! grep -q '"resultRenderPath"' "$REPORT_PATH"; then
  echo "quill-code-desktop native smoke did not report the result evidence image" >&2
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

duplicate_ids = native_targets.get("duplicateContractIDs")
if duplicate_ids != []:
    raise SystemExit(f"quill-code-desktop native smoke reported duplicate native hit target IDs: {duplicate_ids}")

if native_targets.get("minimumHitTarget") != 44:
    raise SystemExit("quill-code-desktop native smoke reported unexpected native minimum hit target")

press_scale = native_targets.get("pressScale")
if not isinstance(press_scale, (int, float)) or not math.isclose(press_scale, 0.96, rel_tol=0.0, abs_tol=1e-9):
    raise SystemExit("quill-code-desktop native smoke reported unexpected native press scale")

contracts = native_targets.get("designSystemContracts", []) + native_targets.get("surfaceContracts", [])
for contract in contracts:
    if not isinstance(contract, dict):
        raise SystemExit("quill-code-desktop native smoke reported malformed native hit target contract")
    for field in ("id", "label", "source", "surface", "collisionScope"):
        value = contract.get(field)
        if not isinstance(value, str) or not value.strip():
            raise SystemExit(f"quill-code-desktop native smoke reported native hit target with empty {field}: {contract}")
    for optional_field in ("testID", "commandID"):
        value = contract.get(optional_field)
        if value is not None and (not isinstance(value, str) or not value.strip()):
            raise SystemExit(f"quill-code-desktop native smoke reported native hit target with empty {optional_field}: {contract}")
    for boolean_field in ("allowsNestedInteractiveChildren", "requiresUnblockedInterior"):
        if not isinstance(contract.get(boolean_field), bool):
            raise SystemExit(f"quill-code-desktop native smoke reported native hit target with malformed {boolean_field}: {contract}")
    if contract.get("family") != "design-system" and not any(contract.get(field) for field in ("focusTarget", "testID", "commandID")):
        raise SystemExit(f"quill-code-desktop native smoke reported unaddressable native hit target: {contract}")

surface_contracts = native_targets.get("surfaceContracts", [])
surface_test_ids = {contract.get("testID") for contract in surface_contracts if isinstance(contract, dict) and contract.get("testID")}
surface_command_ids = {contract.get("commandID") for contract in surface_contracts if isinstance(contract, dict) and contract.get("commandID")}
required_test_ids = {
    "quillcode-send-button", "quillcode-model-picker-button", "quillcode-mode-picker-button",
    "quillcode-top-bar-overflow", "quillcode-sidebar-tools-button", "quillcode-command-palette-input",
    "quillcode-search-input", "quillcode-browser-address", "quillcode-browser-action",
    "quillcode-terminal-action", "quillcode-automation-create"
}
missing_test_ids = sorted(required_test_ids - surface_test_ids)
if missing_test_ids:
    raise SystemExit(f"quill-code-desktop native smoke did not include stable native test IDs: {', '.join(missing_test_ids)}")

required_command_contract_ids = {"new-chat", "search", "toggle-terminal", "toggle-browser", "settings"}
missing_command_contract_ids = sorted(required_command_contract_ids - surface_command_ids)
if missing_command_contract_ids:
    raise SystemExit(f"quill-code-desktop native smoke did not include native command IDs: {', '.join(missing_command_contract_ids)}")

contract_kinds = {contract.get("kind") for contract in contracts if isinstance(contract, dict)}
required_kinds = {"icon", "textButton", "formAction", "link", "textEntry", "segmentedControl", "adjustableControl", "switchRow", "ownedGesture", "fullRow", "capsule"}
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

missing_surface_kinds = native_targets.get("missingRequiredSurfaceKinds")
if missing_surface_kinds != []:
    raise SystemExit(f"quill-code-desktop native smoke reported incomplete surface target policies: {missing_surface_kinds}")

surface_policies = native_targets.get("surfacePolicies")
if not isinstance(surface_policies, list) or not surface_policies:
    raise SystemExit("quill-code-desktop native smoke did not include surface target policies")
policy_by_family = {}
for policy in surface_policies:
    if not isinstance(policy, dict):
        raise SystemExit(f"quill-code-desktop native smoke reported malformed surface target policy: {policy}")
    family = policy.get("family")
    required_kinds = policy.get("requiredKinds")
    required_actions = policy.get("requiredActions")
    required_focus_targets = policy.get("requiredFocusTargets")
    if not isinstance(family, str) or not family:
        raise SystemExit(f"quill-code-desktop native smoke reported surface policy with missing family: {policy}")
    if not isinstance(required_kinds, list) or not all(isinstance(kind, str) for kind in required_kinds):
        raise SystemExit(f"quill-code-desktop native smoke reported surface policy with malformed requiredKinds: {policy}")
    if not isinstance(required_actions, list) or not all(isinstance(action, str) for action in required_actions):
        raise SystemExit(f"quill-code-desktop native smoke reported surface policy with malformed requiredActions: {policy}")
    if not isinstance(required_focus_targets, list) or not all(isinstance(target, str) for target in required_focus_targets):
        raise SystemExit(f"quill-code-desktop native smoke reported surface policy with malformed requiredFocusTargets: {policy}")
    policy_by_family[family] = {
        "kinds": set(required_kinds),
        "actions": set(required_actions),
        "focusTargets": set(required_focus_targets),
    }
expected_policy_kinds = {
    "composer": {"textEntry", "icon", "capsule"},
    "top-bar": {"icon", "fullRow"},
    "settings": {"textEntry", "formAction"},
    "model-picker": {"textEntry", "fullRow", "icon"},
    "review": {"textEntry", "segmentedControl", "fullRow", "formAction"},
    "terminal": {"textEntry", "textButton"},
    "browser": {"textEntry", "textButton", "icon"},
    "extensions": {"formAction", "capsule"},
    "memories": {"formAction", "icon"},
}
for family, required_policy_kinds in expected_policy_kinds.items():
    covered_kinds = policy_by_family.get(family, {}).get("kinds", set())
    if not required_policy_kinds.issubset(covered_kinds):
        missing_policy_kinds = sorted(required_policy_kinds - covered_kinds)
        raise SystemExit(f"quill-code-desktop native smoke surface policy for {family} is missing: {', '.join(missing_policy_kinds)}")

expected_policy_actions = {
    "composer": {"text-input", "press"},
    "settings": {"text-input", "press"},
    "model-picker": {"text-input", "press"},
    "review": {"text-input", "press"},
    "terminal": {"text-input", "press"},
    "browser": {"text-input", "press"},
}
for family, required_policy_actions in expected_policy_actions.items():
    covered_actions = policy_by_family.get(family, {}).get("actions", set())
    if not required_policy_actions.issubset(covered_actions):
        missing_policy_actions = sorted(required_policy_actions - covered_actions)
        raise SystemExit(f"quill-code-desktop native smoke surface policy for {family} is missing actions: {', '.join(missing_policy_actions)}")

expected_policy_focus_targets = {
    "composer": {"composer.message"},
    "settings": {"settings.trustedrouter-base-url"},
    "model-picker": {"model-picker.search"},
    "review": {"review.body", "review.thread-reply"},
    "terminal": {"terminal.command"},
    "browser": {"browser.address", "browser.comment"},
}
for family, required_policy_focus_targets in expected_policy_focus_targets.items():
    covered_focus_targets = policy_by_family.get(family, {}).get("focusTargets", set())
    if not required_policy_focus_targets.issubset(covered_focus_targets):
        missing_policy_focus_targets = sorted(required_policy_focus_targets - covered_focus_targets)
        raise SystemExit(f"quill-code-desktop native smoke surface policy for {family} is missing focus targets: {', '.join(missing_policy_focus_targets)}")

for field in ("missingRequiredSurfaceKinds", "missingRequiredSurfaceActions", "missingRequiredSurfaceFocusTargets"):
    if native_targets.get(field) != []:
        raise SystemExit(f"quill-code-desktop native smoke reported incomplete surface target policy field {field}: {native_targets.get(field)}")

covered_focus_targets = set(native_targets.get("coveredFocusTargets", []))
required_focus_targets = {
    "browser.address", "browser.comment", "command-palette.search", "composer.message",
    "model-picker.search", "review.body", "review.thread-reply", "search.chats",
    "settings.trustedrouter-base-url", "terminal.command"
}
missing_focus_targets = sorted(required_focus_targets - covered_focus_targets)
if missing_focus_targets:
    raise SystemExit(f"quill-code-desktop native smoke did not include native focus targets: {', '.join(missing_focus_targets)}")
PY
"$ROOT_DIR/scripts/native-click-probe-contracts.py" validate "$REPORT_PATH"

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
if ! grep -q 'Contents of `hello.txt`:' "$REPORT_PATH" || ! grep -q 'hello world' "$REPORT_PATH"; then
  echo "quill-code-desktop native smoke did not produce the expected follow-up file-read answer" >&2
  cat "$REPORT_PATH" >&2
  exit 1
fi
if ! grep -q 'Wrote `hello.txt`.' "$HTML_PATH" \
  || ! grep -q 'Contents of `hello.txt`:' "$HTML_PATH" \
  || ! grep -q 'hello world' "$HTML_PATH" \
  || ! grep -q 'host.file.write' "$HTML_PATH" \
  || ! grep -q 'host.file.read' "$HTML_PATH"; then
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
if [[ "$(wc -c < "$RESULT_RENDER_PATH" | tr -d ' ')" -lt 4096 ]]; then
  echo "quill-code-desktop native smoke rendered a suspiciously small result evidence PNG" >&2
  ls -l "$RESULT_RENDER_PATH" >&2
  cat "$REPORT_PATH" >&2
  exit 1
fi
if [[ "$(wc -c < "$CHROME_RENDER_PATH" | tr -d ' ')" -lt 2048 ]]; then
  echo "quill-code-desktop native smoke rendered a suspiciously small desktop chrome PNG" >&2
  ls -l "$CHROME_RENDER_PATH" >&2
  cat "$REPORT_PATH" >&2
  exit 1
fi

echo "QuillCode $TARGET_LABEL smoke passed."
