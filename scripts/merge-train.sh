#!/usr/bin/env bash
set -euo pipefail

repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
base_branch="${MERGE_TRAIN_BASE_BRANCH:-main}"
train_label="${MERGE_TRAIN_LABEL:-merge-train}"
alt_label="${MERGE_TRAIN_ALT_LABEL:-automerge}"
block_label="${MERGE_TRAIN_BLOCK_LABEL:-do-not-merge}"
merge_method="${MERGE_TRAIN_METHOD:-squash}"
delete_branch="${MERGE_TRAIN_DELETE_BRANCH:-true}"
ignored_check_re="${MERGE_TRAIN_IGNORED_CHECK_RE:-^(Merge Train|train)$}"
post_merge_workflows_raw="${MERGE_TRAIN_POST_MERGE_WORKFLOWS:-${MERGE_TRAIN_POST_MERGE_WORKFLOW:-}}"
dry_run="${MERGE_TRAIN_DRY_RUN:-false}"
update_behind_branches="${MERGE_TRAIN_UPDATE_BEHIND_BRANCHES:-false}"

case "$merge_method" in
  merge|squash|rebase) ;;
  *)
    echo "Unsupported MERGE_TRAIN_METHOD: $merge_method" >&2
    exit 2
    ;;
esac

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required tool not found: $1" >&2
    exit 2
  }
}

require_tool gh
require_tool jq

echo "Merge train for $repo base=$base_branch labels=$train_label,$alt_label"

prs_json="$(gh pr list \
  --repo "$repo" \
  --base "$base_branch" \
  --state open \
  --json number,title,url,isDraft,createdAt,mergeStateStatus,statusCheckRollup,labels,headRefName,headRepositoryOwner \
  --limit 100)"

candidate_json="$(jq -c \
  --arg train "$train_label" \
  --arg alt "$alt_label" \
  --arg block "$block_label" \
  'sort_by(.createdAt)
   | map(select([.labels[].name] as $labels | ($labels | index($train)) or ($labels | index($alt))))
   | map(select(.isDraft | not))
   | map(select([.labels[].name] | index($block) | not))
   | first // empty' <<<"$prs_json")"

if [[ -z "$candidate_json" ]]; then
  echo "No eligible PRs in the merge train."
  exit 0
fi

number="$(jq -r '.number' <<<"$candidate_json")"
title="$(jq -r '.title' <<<"$candidate_json")"
url="$(jq -r '.url' <<<"$candidate_json")"
merge_state="$(jq -r '.mergeStateStatus // "UNKNOWN"' <<<"$candidate_json")"

echo "Train head: #$number $title"
echo "$url"
echo "mergeStateStatus=$merge_state"

checks_json="$(jq -c --arg re "$ignored_check_re" '
  [(.statusCheckRollup // [])[]
   | . as $check
   | (($check.name // $check.context // $check.workflowName // "unknown") | tostring) as $name
   | select(($name | test($re)) | not)
   | {
       name: $name,
       status: (($check.status // "") | tostring | ascii_downcase),
       conclusion: (($check.conclusion // $check.state // "") | tostring | ascii_downcase)
     }]
' <<<"$candidate_json")"

check_count="$(jq 'length' <<<"$checks_json")"
if [[ "$check_count" -eq 0 ]]; then
  echo "PR #$number has no completed CI checks yet; waiting."
  exit 0
fi

failed_checks="$(jq -r '
  .[]
  | select(.conclusion as $c | ["failure","failed","error","cancelled","timed_out","action_required"] | index($c))
  | "\(.name)=\(.conclusion)"
' <<<"$checks_json")"

pending_checks="$(jq -r '
  .[]
  | select((.conclusion == "" or .conclusion == "null") and (.status != "completed" and .status != "success"))
  | "\(.name)=\(.status)"
' <<<"$checks_json")"

if [[ -n "$failed_checks" ]]; then
  echo "PR #$number has failed checks:"
  echo "$failed_checks"
  exit 0
fi

if [[ -n "$pending_checks" ]]; then
  echo "PR #$number still has pending checks:"
  echo "$pending_checks"
  exit 0
fi

if [[ "$merge_state" == "BEHIND" ]]; then
  if [[ "$update_behind_branches" != "true" ]]; then
    echo "PR #$number is behind $base_branch; waiting for the branch author to rebase or merge $base_branch and push."
    echo "Automatic branch updates are disabled by default because updates made with GitHub Actions' GITHUB_TOKEN do not reliably produce normal pull_request CI checks."
    echo "Set MERGE_TRAIN_UPDATE_BEHIND_BRANCHES=true only when the train token can trigger required PR checks."
    exit 0
  fi

  echo "PR #$number is behind $base_branch; updating branch and waiting for fresh CI."
  if [[ "$dry_run" == "true" ]]; then
    echo "DRY RUN: gh pr update-branch $number --repo $repo"
  else
    gh pr update-branch "$number" --repo "$repo"
  fi
  exit 0
fi

case "$merge_state" in
  CLEAN|HAS_HOOKS|UNSTABLE) ;;
  *)
    echo "PR #$number is not mergeable yet: $merge_state"
    exit 0
    ;;
esac

merge_args=(pr merge "$number" --repo "$repo" "--$merge_method")
if [[ "$delete_branch" == "true" ]]; then
  merge_args+=(--delete-branch)
fi

echo "Merging train head PR #$number with method=$merge_method."
if [[ "$dry_run" == "true" ]]; then
  printf 'DRY RUN: gh'
  printf ' %q' "${merge_args[@]}"
  printf '\n'
else
  gh "${merge_args[@]}"
fi

if [[ -n "$post_merge_workflows_raw" ]]; then
  IFS=$' \t\n,' read -r -a post_merge_workflows <<<"$post_merge_workflows_raw"
  for post_merge_workflow in "${post_merge_workflows[@]}"; do
    if [[ -z "$post_merge_workflow" ]]; then
      continue
    fi

    echo "Dispatching post-merge workflow $post_merge_workflow on $base_branch."
    if [[ "$dry_run" == "true" ]]; then
      echo "DRY RUN: gh workflow run $post_merge_workflow --repo $repo --ref $base_branch"
    else
      gh workflow run "$post_merge_workflow" --repo "$repo" --ref "$base_branch"
    fi
  done
fi
