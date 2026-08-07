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
    if published_metadata="$(python3 - "$manifest_path" "$REPOSITORY" <<'PY'
import json
import re
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        manifest = json.load(handle)
except (OSError, ValueError):
    raise SystemExit(1)

repository = sys.argv[2]
commit = manifest.get("commit")
workflow_run_url = manifest.get("workflowRunURL")
expected_manifest_url = (
    f"https://github.com/{repository}/releases/download/"
    "tester-latest/latest-tester-build.json"
)
updater = manifest.get("updater")
if (
    manifest.get("schemaVersion") != 1
    or manifest.get("product") != "Quill Cowork"
    or manifest.get("channel") != "tester"
    or manifest.get("tag") != "tester-latest"
    or not isinstance(commit, str)
    or re.fullmatch(r"[0-9a-f]{40}", commit) is None
    or not isinstance(workflow_run_url, str)
    or re.fullmatch(
        rf"https://github\.com/{re.escape(repository)}/actions/runs/([0-9]+)",
        workflow_run_url,
    ) is None
    or not isinstance(updater, dict)
    or updater.get("channel") != "tester"
    or updater.get("manifestURL") != expected_manifest_url
):
    raise SystemExit(1)
run_id = workflow_run_url.rsplit("/", 1)[1]
print(f"{commit}\t{run_id}\t{workflow_run_url}")
PY
    )"; then
      IFS=$'\t' read -r published_commit published_run_id published_run_url <<< "$published_metadata"
      if [[ "$published_commit" == "$COMMIT" ]]; then
        published_run="$(gh run view "$published_run_id" \
          --repo "$REPOSITORY" \
          --json status,conclusion,headSha,url,name \
          --jq '[.status, .conclusion, .headSha, .url, .name] | @tsv' 2>/dev/null || true)"
        IFS=$'\t' read -r run_status run_conclusion run_commit run_url run_name <<< "$published_run"
        if [[ "$run_status" == "completed" &&
              "$run_conclusion" == "success" &&
              "$run_commit" == "$COMMIT" &&
              "$run_url" == "$published_run_url" &&
              "$run_name" == "Download Builds" ]]; then
          build_required=false
          reason="tester manifest already publishes verified commit $COMMIT"
        else
          reason="tester manifest run is unavailable, incomplete, failed, or mismatched; rebuilding"
        fi
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
