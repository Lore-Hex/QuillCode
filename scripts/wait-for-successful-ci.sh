#!/usr/bin/env bash
set -euo pipefail

REPOSITORY="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
COMMIT="${GITHUB_SHA:?GITHUB_SHA is required}"
BASE_BRANCH="main"
WAIT_SECONDS="${DOWNLOAD_BUILD_CI_WAIT_SECONDS:-1800}"
ACTIVE_GRACE_SECONDS="${DOWNLOAD_BUILD_CI_ACTIVE_GRACE_SECONDS:-1800}"
POLL_SECONDS="${DOWNLOAD_BUILD_CI_POLL_SECONDS:-15}"

fail() {
  echo "$*" >&2
  exit 2
}

[[ "$REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] ||
  fail "Invalid GitHub repository slug: $REPOSITORY"
[[ "$COMMIT" =~ ^[0-9a-f]{40}$ ]] ||
  fail "Exact-main CI requires a full lowercase commit SHA."
[[ "$WAIT_SECONDS" =~ ^[0-9]+$ ]] ||
  fail "DOWNLOAD_BUILD_CI_WAIT_SECONDS must be a non-negative integer."
[[ "$ACTIVE_GRACE_SECONDS" =~ ^[0-9]+$ ]] ||
  fail "DOWNLOAD_BUILD_CI_ACTIVE_GRACE_SECONDS must be a non-negative integer."
[[ "$POLL_SECONDS" =~ ^[1-9][0-9]*$ ]] ||
  fail "DOWNLOAD_BUILD_CI_POLL_SECONDS must be a positive integer."
WAIT_SECONDS=$((10#$WAIT_SECONDS))
ACTIVE_GRACE_SECONDS=$((10#$ACTIVE_GRACE_SECONDS))
POLL_SECONDS=$((10#$POLL_SECONDS))
(( WAIT_SECONDS <= 3600 )) ||
  fail "DOWNLOAD_BUILD_CI_WAIT_SECONDS must not exceed 3600."
(( ACTIVE_GRACE_SECONDS <= 3600 )) ||
  fail "DOWNLOAD_BUILD_CI_ACTIVE_GRACE_SECONDS must not exceed 3600."
(( WAIT_SECONDS + ACTIVE_GRACE_SECONDS <= 3600 )) ||
  fail "The combined exact-main CI wait and active grace must not exceed 3600 seconds."
(( POLL_SECONDS <= 300 )) ||
  fail "DOWNLOAD_BUILD_CI_POLL_SECONDS must not exceed 300."

deadline=$((SECONDS + WAIT_SECONDS))
previous_state=""
active_grace_used=false
has_seen_active_run=false

while true; do
  query_succeeded=true
  if ! run_rows="$(
    gh run list \
      --repo "$REPOSITORY" \
      --workflow ci.yml \
      --commit "$COMMIT" \
      --branch "$BASE_BRANCH" \
      --limit 20 \
      --json databaseId,status,conclusion,headSha,headBranch,event,url \
      --jq '
        .[] |
        [
          (.databaseId | tostring),
          .status,
          (.conclusion // ""),
          .headSha,
          (.headBranch // ""),
          .event,
          .url
        ] |
        join("\u001f")
      ' 2>/dev/null
  )"; then
    query_succeeded=false
    run_rows=""
  fi

  matching_count=0
  active_count=0
  terminal_count=0
  successful_url=""

  while IFS=$'\x1f' read -r run_id status conclusion head_sha head_branch event url; do
    [[ -n "$run_id" ]] || continue
    [[ "$head_sha" == "$COMMIT" && "$head_branch" == "$BASE_BRANCH" ]] || continue
    [[ "$event" == "push" || "$event" == "workflow_dispatch" ]] || continue

    matching_count=$((matching_count + 1))
    if [[ "$status" == "completed" && "$conclusion" == "success" ]]; then
      successful_url="$url"
      break
    fi
    if [[ "$status" == "completed" ]]; then
      terminal_count=$((terminal_count + 1))
    else
      active_count=$((active_count + 1))
    fi
  done <<< "$run_rows"

  if [[ -n "$successful_url" ]]; then
    echo "Validated successful exact-main CI for $COMMIT: $successful_url"
    exit 0
  fi

  if (( active_count > 0 )); then
    has_seen_active_run=true
  fi

  if [[ "$query_succeeded" != "true" ]]; then
    current_state="the GitHub CI query is temporarily unavailable"
  elif (( matching_count == 0 )); then
    current_state="no matching main-branch CI run exists yet"
  elif (( active_count > 0 )); then
    current_state="$active_count matching CI run(s) are still active"
  else
    current_state="$terminal_count matching CI run(s) completed without success"
  fi
  if [[ "$current_state" != "$previous_state" ]]; then
    echo "Waiting for successful exact-main CI for $COMMIT: $current_state."
    previous_state="$current_state"
  fi

  if (( SECONDS >= deadline )); then
    active_grace_eligible=false
    if (( active_count > 0 )); then
      active_grace_eligible=true
    elif [[ "$query_succeeded" != "true" && "$has_seen_active_run" == "true" ]]; then
      active_grace_eligible=true
    fi

    deadline_extended=false
    if [[ "$active_grace_used" == "false" && "$active_grace_eligible" == "true" ]] &&
      (( ACTIVE_GRACE_SECONDS > 0 )); then
      active_grace_used=true
      deadline=$((deadline + ACTIVE_GRACE_SECONDS))
      if (( SECONDS < deadline )); then
        deadline_extended=true
        echo "Extending exact-main CI wait once by up to ${ACTIVE_GRACE_SECONDS}s because $current_state."
      fi
    fi

    if [[ "$deadline_extended" != "true" ]]; then
      total_wait_seconds="$WAIT_SECONDS"
      if [[ "$active_grace_used" == "true" ]]; then
        total_wait_seconds=$((total_wait_seconds + ACTIVE_GRACE_SECONDS))
      fi
      failure_message="Commit $COMMIT did not produce a successful exact-main CI run"
      fail "$failure_message within ${total_wait_seconds}s; $current_state."
    fi
  fi

  remaining=$((deadline - SECONDS))
  sleep_seconds="$POLL_SECONDS"
  if (( sleep_seconds > remaining )); then
    sleep_seconds="$remaining"
  fi
  sleep "$sleep_seconds"
done
