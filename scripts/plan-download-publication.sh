#!/usr/bin/env bash
set -euo pipefail

REF_TYPE="${GITHUB_REF_TYPE:?GITHUB_REF_TYPE is required}"
REF_NAME="${GITHUB_REF_NAME:?GITHUB_REF_NAME is required}"
COMMIT="${GITHUB_SHA:?GITHUB_SHA is required}"
OUTPUT_PATH="${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"

CHECKED_OUT_COMMIT="$(git rev-parse --verify "${COMMIT}^{commit}")"
if [[ "$CHECKED_OUT_COMMIT" != "$COMMIT" ]]; then
  echo "Download publication commit did not resolve exactly: $COMMIT" >&2
  exit 2
fi

if [[ "$REF_TYPE" == "branch" ]]; then
  if [[ "$REF_NAME" != "main" ]]; then
    echo "Tester downloads may only be published from main, not $REF_NAME." >&2
    exit 2
  fi

  git fetch --no-tags --prune origin \
    +refs/heads/main:refs/remotes/origin/main
  MAIN_COMMIT="$(git rev-parse --verify 'refs/remotes/origin/main^{commit}')"
  if [[ "$COMMIT" != "$MAIN_COMMIT" ]]; then
    printf 'publish-required=false\n' >> "$OUTPUT_PATH"
    echo "Skipping superseded tester build $COMMIT; current main is $MAIN_COMMIT."
    exit 0
  fi

  printf 'publish-required=true\n' >> "$OUTPUT_PATH"
  echo "Tester build $COMMIT is still current main and may be published."
  exit 0
fi

if [[ "$REF_TYPE" != "tag" ]] ||
   [[ ! "$REF_NAME" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "Download publication requires main or a canonical stable version tag." >&2
  exit 2
fi

REMOTE_TAG_ROW="$(git ls-remote --refs origin "refs/tags/$REF_NAME")"
IFS=$'\t' read -r TAG_COMMIT TAG_REF <<< "$REMOTE_TAG_ROW"
if [[ "$TAG_REF" != "refs/tags/$REF_NAME" ]] || [[ "$TAG_COMMIT" != "$COMMIT" ]]; then
  echo "Stable tag $REF_NAME no longer resolves to workflow commit $COMMIT." >&2
  exit 2
fi

printf 'publish-required=true\n' >> "$OUTPUT_PATH"
echo "Immutable stable tag $REF_NAME may be published."
