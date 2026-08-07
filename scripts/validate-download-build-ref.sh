#!/usr/bin/env bash
set -euo pipefail

REF_TYPE="${GITHUB_REF_TYPE:?GITHUB_REF_TYPE is required}"
REF_NAME="${GITHUB_REF_NAME:?GITHUB_REF_NAME is required}"
COMMIT="${GITHUB_SHA:?GITHUB_SHA is required}"
REPOSITORY="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"

git fetch --no-tags --prune origin \
  +refs/heads/main:refs/remotes/origin/main

MAIN_COMMIT="$(git rev-parse --verify 'refs/remotes/origin/main^{commit}')"
CHECKED_OUT_COMMIT="$(git rev-parse --verify "${COMMIT}^{commit}")"
if [[ "$CHECKED_OUT_COMMIT" != "$COMMIT" ]]; then
  echo "Download build commit did not resolve exactly: $COMMIT" >&2
  exit 2
fi

if [[ "$REF_TYPE" == "branch" ]]; then
  if [[ "$REF_NAME" != "main" ]]; then
    echo "Tester downloads may only be published from main, not $REF_NAME." >&2
    exit 2
  fi
  if [[ "$COMMIT" != "$MAIN_COMMIT" ]]; then
    echo "Refusing to publish a stale tester build; origin/main is $MAIN_COMMIT." >&2
    exit 2
  fi
  echo "Validated tester download build at current main commit $COMMIT."
  exit 0
fi

if [[ "$REF_TYPE" != "tag" ]]; then
  echo "Download builds require the main branch or a stable version tag." >&2
  exit 2
fi
if [[ ! "$REF_NAME" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "Stable release tags must use canonical vMAJOR.MINOR.PATCH form." >&2
  exit 2
fi

TAG_COMMIT="$(git rev-parse --verify "refs/tags/${REF_NAME}^{commit}")"
if [[ "$TAG_COMMIT" != "$COMMIT" ]]; then
  echo "Stable tag $REF_NAME does not resolve to workflow commit $COMMIT." >&2
  exit 2
fi
if ! git merge-base --is-ancestor "$COMMIT" refs/remotes/origin/main; then
  echo "Stable tag $REF_NAME must point to a commit on main." >&2
  exit 2
fi

SUCCESSFUL_CI_RUNS="$(
  gh run list \
    --repo "$REPOSITORY" \
    --workflow ci.yml \
    --commit "$COMMIT" \
    --status success \
    --limit 1 \
    --json databaseId \
    --jq 'length'
)"
if [[ ! "$SUCCESSFUL_CI_RUNS" =~ ^[1-9][0-9]*$ ]]; then
  echo "Stable tag $REF_NAME requires a successful CI run for commit $COMMIT." >&2
  exit 2
fi
if gh release view "$REF_NAME" --repo "$REPOSITORY" >/dev/null 2>&1; then
  echo "Stable release $REF_NAME already exists and is immutable." >&2
  exit 2
fi

echo "Validated immutable stable release $REF_NAME at main commit $COMMIT."
