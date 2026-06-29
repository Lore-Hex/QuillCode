#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEY_FILE="${QUILLCODE_LIVE_KEY_FILE:-$HOME/.quill.code.keyfile}"
REQUIRE_LIVE="${QUILLCODE_REQUIRE_LIVE_SMOKE:-0}"
REQUIRE_PLAYWRIGHT="${QUILLCODE_REAL_WORLD_REQUIRE_PLAYWRIGHT:-1}"
ARTIFACT_DIR="${QUILLCODE_REAL_WORLD_SMOKE_ARTIFACT_DIR:-}"
STARTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
DETERMINISTIC_STATUS="not-run"
DETERMINISTIC_DETAIL="not-started"
LIVE_STATUS="not-run"
LIVE_DETAIL="not-started"
FINAL_DETAIL="interrupted"
LIVE_KEY_SOURCE="missing"
LIVE_MODEL="${QUILLCODE_LIVE_MODEL:-deepseekv4flash}"
LIVE_BASE_URL="${QUILLCODE_LIVE_BASE_URL:-https://api.trustedrouter.com/v1}"

cd "$ROOT_DIR"

if [[ -n "$ARTIFACT_DIR" ]]; then
  mkdir -p "$ARTIFACT_DIR"
  ARTIFACT_DIR="$(cd "$ARTIFACT_DIR" && pwd)"
fi

has_live_key() {
  if [[ -n "${QUILLCODE_API_KEY:-}" || -n "${TRUSTEDROUTER_API_KEY:-}" ]]; then
    return 0
  fi
  [[ -s "$KEY_FILE" ]]
}

live_key_source() {
  if [[ -n "${QUILLCODE_API_KEY:-}" ]]; then
    printf 'env:QUILLCODE_API_KEY'
    return
  fi
  if [[ -n "${TRUSTEDROUTER_API_KEY:-}" ]]; then
    printf 'env:TRUSTEDROUTER_API_KEY'
    return
  fi
  if [[ -s "$KEY_FILE" ]]; then
    printf 'key-file'
    return
  fi
  printf 'missing'
}

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

playwright_dependencies_ready() {
  [[ -d "$ROOT_DIR/E2E/playwright/node_modules" ]]
}

assert_deterministic_real_world_evidence() {
  if [[ -z "$ARTIFACT_DIR" ]] || ! is_truthy "$REQUIRE_PLAYWRIGHT"; then
    return 0
  fi

  local deterministic_dir="$ARTIFACT_DIR/deterministic"
  local real_world_manifest="$deterministic_dir/playwright-real-world/playwright-real-world-actions-manifest.json"
  "$ROOT_DIR/scripts/validate-playwright-real-world-manifest.py" "$real_world_manifest"

  python3 - "$deterministic_dir/deterministic-smoke-manifest.json" <<'PY'
import json
import sys

manifest_path = sys.argv[1]
with open(manifest_path, "r", encoding="utf-8") as handle:
    manifest = json.load(handle)

errors = []
steps = manifest.get("steps")
if not isinstance(steps, dict):
    errors.append(f"steps should be an object, got {type(steps).__name__}")
    steps = {}

playwright_step = steps.get("playwright")
if not isinstance(playwright_step, dict):
    errors.append(f"steps.playwright should be an object, got {type(playwright_step).__name__}")
    playwright_step = {}

real_world = playwright_step.get("realWorldActions")
if not isinstance(real_world, dict):
    errors.append(f"steps.playwright.realWorldActions should be an object, got {type(real_world).__name__}")
    real_world = {}

if playwright_step.get("status") != "passed":
    errors.append(f"playwright status should be passed, got {playwright_step.get('status')!r}")
if real_world.get("status") != "present":
    errors.append(f"realWorldActions status should be present, got {real_world.get('status')!r}")
if real_world.get("manifestPath") != "playwright-real-world/playwright-real-world-actions-manifest.json":
    errors.append(f"unexpected realWorldActions manifestPath: {real_world.get('manifestPath')!r}")
scenario_count = real_world.get("scenarioCount")
prompt_count = real_world.get("promptCount")
regression_guard_count = real_world.get("regressionGuardCount")
if not isinstance(scenario_count, int) or scenario_count < 5:
    errors.append(f"scenarioCount should be at least 5, got {scenario_count!r}")
if not isinstance(prompt_count, int) or prompt_count < 13:
    errors.append(f"promptCount should be at least 13, got {prompt_count!r}")
if not isinstance(regression_guard_count, int) or regression_guard_count < 15:
    errors.append(
        f"regressionGuardCount should be at least 15, got {regression_guard_count!r}"
    )

if errors:
    print("Deterministic smoke manifest is missing Playwright real-world evidence:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    sys.exit(1)
PY
}

write_manifest() {
  local exit_code="$1"
  local detail="$2"

  if [[ -z "$ARTIFACT_DIR" ]]; then
    return 0
  fi

  python3 - "$ARTIFACT_DIR/real-world-smoke-manifest.json" \
    "$exit_code" \
    "$detail" \
    "$STARTED_AT" \
    "$DETERMINISTIC_STATUS" \
    "$DETERMINISTIC_DETAIL" \
    "$LIVE_STATUS" \
    "$LIVE_DETAIL" \
    "$LIVE_KEY_SOURCE" \
    "$LIVE_MODEL" \
    "$LIVE_BASE_URL" \
    "$REQUIRE_PLAYWRIGHT" \
    "$ARTIFACT_DIR" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone

(
    manifest_path,
    exit_code,
    detail,
    started_at,
    deterministic_status,
    deterministic_detail,
    live_status,
    live_detail,
    live_key_source,
    live_model,
    live_base_url,
    require_playwright,
    artifact_root,
) = sys.argv[1:]

def load_json(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except FileNotFoundError:
        return None

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

deterministic_dir = os.path.join(artifact_root, "deterministic")
live_dir = os.path.join(artifact_root, "live-trustedrouter")
deterministic_manifest = load_json(os.path.join(deterministic_dir, "deterministic-smoke-manifest.json"))
live_manifest = load_json(os.path.join(live_dir, "live-smoke-manifest.json"))
requires_playwright = require_playwright.lower() in {"1", "true", "yes"}
deterministic_real_world_actions = None
if isinstance(deterministic_manifest, dict):
    steps = deterministic_manifest.get("steps")
    playwright_step = steps.get("playwright") if isinstance(steps, dict) else None
    if isinstance(playwright_step, dict):
        real_world_actions = playwright_step.get("realWorldActions")
        if isinstance(real_world_actions, dict):
            deterministic_real_world_actions = real_world_actions

manifest = {
    "generatedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "startedAt": started_at,
    "exitCode": int(exit_code),
    "detail": detail,
    "artifactRoot": artifact_root,
    "deterministic": {
        "status": deterministic_status,
        "detail": deterministic_detail,
        "requiresPlaywright": requires_playwright,
        "artifactDir": deterministic_dir if os.path.isdir(deterministic_dir) else None,
        "realWorldActions": deterministic_real_world_actions,
        "manifest": deterministic_manifest,
        "artifactFiles": collect_files(deterministic_dir),
    },
    "liveTrustedRouter": {
        "status": live_status,
        "detail": live_detail,
        "configured": {
            "transport": "TrustedRouter",
            "rawModel": live_model,
            "baseURL": live_base_url,
            "keySource": live_key_source,
            "secretFree": True,
        },
        "artifactDir": live_dir if os.path.isdir(live_dir) else None,
        "manifest": live_manifest,
        "artifactFiles": collect_files(live_dir),
    },
}

with open(manifest_path, "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
}

finish() {
  local status=$?
  set +e
  write_manifest "$status" "$FINAL_DETAIL"
  if [[ -n "$ARTIFACT_DIR" ]]; then
    echo "QuillCode real-world smoke artifacts: $ARTIFACT_DIR"
  fi
  exit "$status"
}
trap finish EXIT

if is_truthy "$REQUIRE_PLAYWRIGHT" && ! playwright_dependencies_ready; then
  DETERMINISTIC_STATUS="missing-playwright-dependencies"
  DETERMINISTIC_DETAIL="Playwright E2E dependencies are required, but E2E/playwright/node_modules is missing"
  FINAL_DETAIL="$DETERMINISTIC_DETAIL"
  echo "$DETERMINISTIC_DETAIL." >&2
  echo "Run npm ci in E2E/playwright, or set QUILLCODE_REAL_WORLD_REQUIRE_PLAYWRIGHT=0 for a lighter local run." >&2
  exit 2
fi

echo "==> Running deterministic QuillCode smoke suite"
if QUILLCODE_REQUIRE_PLAYWRIGHT_SMOKE="$REQUIRE_PLAYWRIGHT" \
  QUILLCODE_SMOKE_ARTIFACT_DIR="${ARTIFACT_DIR:+$ARTIFACT_DIR/deterministic}" \
  "$ROOT_DIR/scripts/smoke.sh"; then
  DETERMINISTIC_STATUS="validating-real-world-evidence"
  DETERMINISTIC_DETAIL="validating deterministic real-world evidence"
  if assert_deterministic_real_world_evidence; then
    DETERMINISTIC_STATUS="passed"
    DETERMINISTIC_DETAIL="completed"
  else
    status=$?
    DETERMINISTIC_STATUS="failed"
    DETERMINISTIC_DETAIL="deterministic real-world evidence validation failed"
    FINAL_DETAIL="$DETERMINISTIC_DETAIL"
    exit "$status"
  fi
else
  status=$?
  DETERMINISTIC_STATUS="failed"
  DETERMINISTIC_DETAIL="deterministic smoke failed"
  FINAL_DETAIL="deterministic smoke failed"
  exit "$status"
fi

if has_live_key; then
  LIVE_KEY_SOURCE="$(live_key_source)"
  echo "==> Running live TrustedRouter real-world smoke suite"
  if QUILLCODE_LIVE_SMOKE_ARTIFACT_DIR="${ARTIFACT_DIR:+$ARTIFACT_DIR/live-trustedrouter}" \
    "$ROOT_DIR/scripts/live-tr-smoke.sh"; then
    LIVE_STATUS="passed"
    LIVE_DETAIL="completed"
  else
    status=$?
    LIVE_STATUS="failed"
    LIVE_DETAIL="live TrustedRouter smoke failed"
    FINAL_DETAIL="live TrustedRouter smoke failed"
    exit "$status"
  fi
  FINAL_DETAIL="completed"
  echo "QuillCode real-world smoke passed."
  exit 0
fi

if [[ "$REQUIRE_LIVE" == "1" || "$REQUIRE_LIVE" == "true" ]]; then
  LIVE_STATUS="missing-required-key"
  LIVE_DETAIL="live TrustedRouter smoke was required, but no key was found"
  FINAL_DETAIL="$LIVE_DETAIL"
  echo "Live TrustedRouter smoke was required, but no key was found." >&2
  echo "Set QUILLCODE_API_KEY, TRUSTEDROUTER_API_KEY, or create $KEY_FILE." >&2
  exit 2
fi

LIVE_STATUS="skipped"
LIVE_DETAIL="no TrustedRouter key found"
FINAL_DETAIL="deterministic smoke passed; live TrustedRouter smoke skipped"
echo "No TrustedRouter key found; skipped live TrustedRouter smoke."
echo "Set QUILLCODE_REQUIRE_LIVE_SMOKE=1 to make that a hard release gate."
echo "QuillCode deterministic smoke passed."
