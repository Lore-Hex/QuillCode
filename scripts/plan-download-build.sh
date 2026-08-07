#!/usr/bin/env bash
set -euo pipefail

EVENT_NAME="${GITHUB_EVENT_NAME:?GITHUB_EVENT_NAME is required}"
REF_TYPE="${GITHUB_REF_TYPE:?GITHUB_REF_TYPE is required}"
COMMIT="${GITHUB_SHA:?GITHUB_SHA is required}"
REPOSITORY="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
OUTPUT_FILE="${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"

build_required=true
reason="${EVENT_NAME} runs always produce a fresh build"

if [[ "$EVENT_NAME" == "schedule" && "$REF_TYPE" == "branch" ]]; then
  download_directory="$(mktemp -d)"
  trap 'rm -rf "$download_directory"' EXIT
  manifest_path="$download_directory/latest-tester-build.json"

  if gh release download tester-latest \
    --repo "$REPOSITORY" \
    --pattern latest-tester-build.json \
    --dir "$download_directory" >/dev/null 2>&1; then
    if published_commit="$(python3 - "$manifest_path" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        manifest = json.load(handle)
except (OSError, ValueError):
    raise SystemExit(1)

commit = manifest.get("commit")
if not isinstance(commit, str) or not commit:
    raise SystemExit(1)
print(commit)
PY
    )"; then
      if [[ "$published_commit" == "$COMMIT" ]]; then
        build_required=false
        reason="tester manifest already publishes commit $COMMIT"
      else
        reason="tester manifest publishes $published_commit instead of $COMMIT"
      fi
    else
      reason="tester manifest is malformed; rebuilding to repair it"
    fi
  else
    reason="tester manifest is unavailable; rebuilding to restore it"
  fi
fi

printf 'build-required=%s\n' "$build_required" >> "$OUTPUT_FILE"
printf 'Download build required: %s (%s).\n' "$build_required" "$reason"
