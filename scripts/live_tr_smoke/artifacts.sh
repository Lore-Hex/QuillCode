# Artifact, report, and failure helpers for the live TrustedRouter smoke.

cleanup() {
  local status=$?
  set +e

  if type write_artifact_manifest >/dev/null 2>&1; then
    write_artifact_manifest "$status" "exit status $status"
  fi
  if type copy_live_artifacts >/dev/null 2>&1; then
    copy_live_artifacts "$status"
  fi

  if [[ "$status" -eq 0 && "$KEEP_ARTIFACTS" != "1" ]]; then
    rm -rf "$SMOKE_ROOT"
    return
  fi

  if [[ "$status" -eq 0 ]]; then
    echo "Live smoke artifacts kept at $SMOKE_ROOT"
  else
    echo "Live smoke failed; artifacts kept at $SMOKE_ROOT" >&2
  fi
}

install_live_smoke_cleanup_trap() {
  trap cleanup EXIT
}

record_scenario() {
  local status="$1"
  local detail="$2"
  local output_file="$3"
  local stderr_file="$4"
  local finished_at
  local duration
  local stdout_bytes=0
  local stderr_bytes=0

  finished_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  if [[ "$CURRENT_SCENARIO_START" -gt 0 ]]; then
    duration="$(( $(date +%s) - CURRENT_SCENARIO_START ))"
  else
    duration="0"
  fi
  if [[ -f "$output_file" ]]; then
    stdout_bytes="$(wc -c < "$output_file" | tr -d ' ')"
  fi
  if [[ -f "$stderr_file" ]]; then
    stderr_bytes="$(wc -c < "$stderr_file" | tr -d ' ')"
  fi

  jq -n \
    --arg scenario "$CURRENT_SCENARIO" \
    --arg prompt "$CURRENT_PROMPT" \
    --arg status "$status" \
    --arg detail "$detail" \
    --arg model "$MODEL" \
    --arg baseURL "$BASE_URL" \
    --arg finishedAt "$finished_at" \
    --arg stdout "$output_file" \
    --arg stderr "$stderr_file" \
    --argjson durationSeconds "$duration" \
    --argjson stdoutBytes "$stdout_bytes" \
    --argjson stderrBytes "$stderr_bytes" \
    '{
      scenario: $scenario,
      status: $status,
      detail: $detail,
      model: $model,
      baseURL: $baseURL,
      finishedAt: $finishedAt,
      durationSeconds: $durationSeconds,
      stdoutBytes: $stdoutBytes,
      stderrBytes: $stderrBytes,
      stdout: $stdout,
      stderr: $stderr,
      prompt: $prompt
    }' >> "$REPORT_FILE"
}

print_report_summary() {
  if [[ ! -s "$REPORT_FILE" ]]; then
    return
  fi
  echo "Live smoke scenario report:"
  jq -rs '
    (
      ["status", "scenario", "duration", "stdout", "stderr", "detail"],
      (.[] | [
        .status,
        .scenario,
        ((.durationSeconds | tostring) + "s"),
        (.stdoutBytes | tostring),
        (.stderrBytes | tostring),
        .detail
      ])
    )
    | @tsv
  ' "$REPORT_FILE"
}

write_artifact_manifest() {
  local status="${1:-0}"
  local detail="${2:-completed}"
  local scenarios_json="$SMOKE_ROOT/scenarios.json"
  local workspace_files_json="$SMOKE_ROOT/workspace-files.json"
  local threads_json="$SMOKE_ROOT/thread-summaries.json"
  local generated_at

  generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  if [[ -s "$REPORT_FILE" ]]; then
    jq -s '.' "$REPORT_FILE" > "$scenarios_json"
  else
    printf '[]\n' > "$scenarios_json"
  fi

  if [[ -d "$SMOKE_WORKSPACE" ]]; then
    find "$SMOKE_WORKSPACE" \
      -path "$SMOKE_WORKSPACE/.git" -prune -o \
      -maxdepth 5 -type f -print | sort | while IFS= read -r file_path; do
      local relative_path
      local byte_count
      relative_path="${file_path#$SMOKE_WORKSPACE/}"
      byte_count="$(wc -c < "$file_path" | tr -d ' ')"
      jq -n \
        --arg path "$relative_path" \
        --argjson bytes "$byte_count" \
        '{path: $path, bytes: $bytes}'
    done | jq -s '.' > "$workspace_files_json"
  else
    printf '[]\n' > "$workspace_files_json"
  fi

  if [[ -d "$SMOKE_HOME/threads" ]]; then
    find "$SMOKE_HOME/threads" \
      -maxdepth 1 \
      -type f \
      -name '*.json' \
      -print | sort | while IFS= read -r thread_path; do
      jq \
        --arg path "$thread_path" \
        --arg basename "$(basename "$thread_path")" \
        '{
          path: $path,
          file: $basename,
          id: .id,
          title: .title,
          model: .model,
          messageCount: (.messages | length),
          queuedToolCount: ([.events[]? | select(.kind == "toolQueued")] | length),
          completedToolCount: ([.events[]? | select(.kind == "toolCompleted")] | length),
          failedToolCount: ([.events[]? | select(.kind == "toolFailed")] | length)
        }' "$thread_path"
    done | jq -s '.' > "$threads_json"
  else
    printf '[]\n' > "$threads_json"
  fi

  jq -n \
    --arg generatedAt "$generated_at" \
    --arg status "$status" \
    --arg detail "$detail" \
    --arg rawModel "$RAW_MODEL" \
    --arg model "$MODEL" \
    --arg baseURL "$BASE_URL" \
    --arg keySource "$API_KEY_SOURCE" \
    --arg root "$SMOKE_ROOT" \
    --arg home "$SMOKE_HOME" \
    --arg workspace "$SMOKE_WORKSPACE" \
    --arg report "$REPORT_FILE" \
    --slurpfile scenarios "$scenarios_json" \
    --slurpfile workspaceFiles "$workspace_files_json" \
    --slurpfile threads "$threads_json" \
    '{
      generatedAt: $generatedAt,
      status: ($status | tonumber),
      detail: $detail,
      transport: "TrustedRouter",
      rawModel: $rawModel,
      normalizedModel: $model,
      model: $model,
      baseURL: $baseURL,
      keySource: $keySource,
      secretFree: true,
      smokeRoot: $root,
      home: $home,
      workspace: $workspace,
      report: $report,
      scenarioCount: ($scenarios[0] | length),
      passedScenarioCount: ([$scenarios[0][] | select(.status == "pass")] | length),
      failedScenarioCount: ([$scenarios[0][] | select(.status == "fail")] | length),
      workspaceFileCount: ($workspaceFiles[0] | length),
      threadCount: ($threads[0] | length),
      scenarios: $scenarios[0],
      workspaceFiles: $workspaceFiles[0],
      threads: $threads[0]
    }' > "$MANIFEST_FILE"
}

copy_live_artifacts() {
  local status="${1:-0}"
  if [[ -z "$ARTIFACT_DIR" ]]; then
    return
  fi
  if [[ "$ARTIFACTS_COPIED" == "1" ]]; then
    return
  fi

  mkdir -p "$ARTIFACT_DIR"
  for artifact_path in "$REPORT_FILE" "$MANIFEST_FILE" "$SMOKE_ROOT"/*.stdout "$SMOKE_ROOT"/*.stderr; do
    if [[ -e "$artifact_path" ]]; then
      cp "$artifact_path" "$ARTIFACT_DIR/$(basename "$artifact_path")"
    fi
  done
  {
    printf 'status=%s\n' "$status"
    printf 'source=%s\n' "$SMOKE_ROOT"
    printf 'manifest=live-smoke-manifest.json\n'
    printf 'report=live-smoke-report.jsonl\n'
    printf 'model=%s\n' "$MODEL"
    printf 'base_url=%s\n' "$BASE_URL"
  } > "$ARTIFACT_DIR/manifest.txt"
  ARTIFACTS_COPIED=1
  echo "QuillCode live TrustedRouter smoke artifacts: $ARTIFACT_DIR"
}

fail_smoke() {
  local message="$1"
  local output_file="${2:-$CURRENT_STDOUT}"
  local stderr_file="${3:-$CURRENT_STDERR}"
  local exit_code="${4:-1}"

  if [[ -n "$CURRENT_SCENARIO" ]]; then
    record_scenario "fail" "$message" "$output_file" "$stderr_file"
  fi

  echo "Live smoke failed in scenario: ${CURRENT_SCENARIO:-unknown}" >&2
  echo "$message" >&2
  if [[ -n "$CURRENT_PROMPT" ]]; then
    echo "Prompt: $CURRENT_PROMPT" >&2
  fi
  if [[ -n "$output_file" ]]; then
    echo "stdout: $output_file" >&2
    if [[ -s "$output_file" ]]; then
      echo "--- stdout tail ---" >&2
      tail -n 80 "$output_file" >&2
    fi
  fi
  if [[ -n "$stderr_file" ]]; then
    echo "stderr: $stderr_file" >&2
    if [[ -s "$stderr_file" ]]; then
      echo "--- stderr tail ---" >&2
      tail -n 80 "$stderr_file" >&2
    fi
  fi
  print_report_summary >&2
  exit "$exit_code"
}

fail_workspace_assertion() {
  local message="$1"
  local max_depth="$2"
  record_scenario "fail" "$message" "$CURRENT_STDOUT" "$CURRENT_STDERR"
  echo "Live smoke failed in scenario: ${CURRENT_SCENARIO:-unknown}" >&2
  echo "$message" >&2
  echo "Workspace files:" >&2
  find "$SMOKE_WORKSPACE" -maxdepth "$max_depth" -type f -print >&2
  print_report_summary >&2
  exit 1
}
