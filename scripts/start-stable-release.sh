#!/usr/bin/env bash
set -euo pipefail

export LC_ALL=C

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPOSITORY="${GITHUB_REPOSITORY:-Lore-Hex/QuillCode}"
REMOTE="${QUILLCODE_RELEASE_REMOTE:-origin}"
BASE_BRANCH="${QUILLCODE_RELEASE_BASE_BRANCH:-main}"
CHECK_ONLY=false

usage() {
  cat <<'USAGE'
Usage: scripts/start-stable-release.sh [--check-only] vMAJOR.MINOR.PATCH

Validates the exact public, tested main commit and Apple distribution secret names.
Without --check-only, creates and pushes one annotated, immutable stable tag.
USAGE
}

fail() {
  echo "$*" >&2
  exit 2
}

version_greater_than() {
  local lhs="$1"
  local rhs="$2"
  local lhs_major lhs_minor lhs_patch rhs_major rhs_minor rhs_patch
  IFS=. read -r lhs_major lhs_minor lhs_patch <<< "$lhs"
  IFS=. read -r rhs_major rhs_minor rhs_patch <<< "$rhs"
  local lhs_parts=("$lhs_major" "$lhs_minor" "$lhs_patch")
  local rhs_parts=("$rhs_major" "$rhs_minor" "$rhs_patch")
  local index lhs_part rhs_part

  for index in 0 1 2; do
    lhs_part="${lhs_parts[$index]}"
    rhs_part="${rhs_parts[$index]}"
    if (( ${#lhs_part} > ${#rhs_part} )); then
      return 0
    fi
    if (( ${#lhs_part} < ${#rhs_part} )); then
      return 1
    fi
    if [[ "$lhs_part" > "$rhs_part" ]]; then
      return 0
    fi
    if [[ "$lhs_part" < "$rhs_part" ]]; then
      return 1
    fi
  done
  return 1
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi
if [[ "${1:-}" == "--check-only" ]]; then
  CHECK_ONLY=true
  shift
fi
if [[ "$#" -ne 1 ]]; then
  usage >&2
  exit 2
fi

TAG="$1"
if [[ ! "$TAG" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  fail "Stable releases require a canonical vMAJOR.MINOR.PATCH tag."
fi
if [[ ! "$REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  fail "Invalid GitHub repository slug: $REPOSITORY"
fi
VERSION="${TAG#v}"

for command in git gh; do
  command -v "$command" >/dev/null 2>&1 || fail "Required command is unavailable: $command"
done

cd "$ROOT_DIR"

REMOTE_URL="$(git remote get-url "$REMOTE")"
NORMALIZED_REMOTE_URL="${REMOTE_URL%.git}"
case "$NORMALIZED_REMOTE_URL" in
  "https://github.com/$REPOSITORY"|"git@github.com:$REPOSITORY"|"ssh://git@github.com/$REPOSITORY") ;;
  *) fail "Git remote $REMOTE does not point to https://github.com/$REPOSITORY." ;;
esac

CURRENT_BRANCH="$(git symbolic-ref --quiet --short HEAD || true)"
if [[ "$CURRENT_BRANCH" != "$BASE_BRANCH" ]]; then
  fail "Stable releases must start from the $BASE_BRANCH branch, not ${CURRENT_BRANCH:-detached HEAD}."
fi
if [[ -n "$(git status --porcelain=v1 --untracked-files=normal)" ]]; then
  fail "Stable releases require a clean worktree, including no untracked files."
fi

git fetch --no-tags --prune "$REMOTE" \
  "+refs/heads/$BASE_BRANCH:refs/remotes/$REMOTE/$BASE_BRANCH"

HEAD_COMMIT="$(git rev-parse --verify 'HEAD^{commit}')"
MAIN_COMMIT="$(git rev-parse --verify "refs/remotes/$REMOTE/$BASE_BRANCH^{commit}")"
if [[ "$HEAD_COMMIT" != "$MAIN_COMMIT" ]]; then
  fail "Local $BASE_BRANCH is not exact $REMOTE/$BASE_BRANCH ($MAIN_COMMIT)."
fi
if git show-ref --verify --quiet "refs/tags/$TAG"; then
  fail "Local tag $TAG already exists."
fi

REMOTE_VERSION_TAGS="$(git ls-remote --tags --refs "$REMOTE" 'refs/tags/v*')"
LATEST_VERSION=""
while IFS=$'\t' read -r _ ref; do
  [[ -z "$ref" ]] && continue
  remote_tag="${ref#refs/tags/}"
  if [[ "$remote_tag" == "$TAG" ]]; then
    fail "Remote tag $TAG already exists and will not be moved."
  fi
  if [[ "$remote_tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    remote_version="${remote_tag#v}"
    if [[ -z "$LATEST_VERSION" ]] || version_greater_than "$remote_version" "$LATEST_VERSION"; then
      LATEST_VERSION="$remote_version"
    fi
  fi
done <<< "$REMOTE_VERSION_TAGS"
if [[ -n "$LATEST_VERSION" ]] && ! version_greater_than "$VERSION" "$LATEST_VERSION"; then
  fail "Stable version $VERSION must be newer than the latest tag, $LATEST_VERSION."
fi

TESTER_TAG_ROW="$(git ls-remote --refs "$REMOTE" refs/tags/tester-latest)"
TESTER_COMMIT="$(awk 'NR == 1 { print $1 }' <<< "$TESTER_TAG_ROW")"
if [[ "$TESTER_COMMIT" != "$HEAD_COMMIT" ]]; then
  fail "Current main must already be published and exercised as tester-latest before a stable release."
fi

VISIBILITY="$(gh repo view "$REPOSITORY" --json visibility --jq '.visibility')"
if [[ "$VISIBILITY" != "PUBLIC" ]]; then
  fail "Stable releases require the GitHub repository to be public."
fi

RELEASE_ROWS="$(
  gh release list \
    --repo "$REPOSITORY" \
    --limit 1000 \
    --json tagName,isPrerelease \
    --jq '.[] | [.tagName, .isPrerelease] | @tsv'
)"
TESTER_RELEASE_FOUND=false
while IFS=$'\t' read -r release_tag is_prerelease; do
  [[ -z "$release_tag" ]] && continue
  if [[ "$release_tag" == "$TAG" ]]; then
    fail "Stable release $TAG already exists and is immutable."
  fi
  if [[ "$release_tag" == "tester-latest" && "$is_prerelease" == "true" ]]; then
    TESTER_RELEASE_FOUND=true
  fi
done <<< "$RELEASE_ROWS"
if [[ "$TESTER_RELEASE_FOUND" != "true" ]]; then
  fail "The public tester-latest prerelease is missing."
fi

CI_RUN_URL="$(
  gh run list \
    --repo "$REPOSITORY" \
    --workflow ci.yml \
    --commit "$HEAD_COMMIT" \
    --status success \
    --limit 1 \
    --json url \
    --jq '.[0].url // empty'
)"
if [[ -z "$CI_RUN_URL" ]]; then
  fail "Commit $HEAD_COMMIT does not have a successful exact-commit CI run."
fi

REQUIRED_SECRETS=(
  APPLE_DEVELOPER_ID_CERTIFICATE_BASE64
  APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD
  APPLE_DEVELOPER_ID_APPLICATION_IDENTITY
  APPLE_TEAM_ID
  APPLE_NOTARY_KEY_ID
  APPLE_NOTARY_ISSUER_ID
  APPLE_NOTARY_PRIVATE_KEY_BASE64
)
SECRET_NAMES="$(
  gh secret list \
    --repo "$REPOSITORY" \
    --app actions \
    --json name \
    --jq '.[].name'
)"
for required_secret in "${REQUIRED_SECRETS[@]}"; do
  if ! grep -Fxq "$required_secret" <<< "$SECRET_NAMES"; then
    fail "Missing GitHub Actions secret: $required_secret"
  fi
done

echo "Stable release preflight passed."
echo "Repository: $REPOSITORY"
echo "Tag: $TAG"
echo "Commit: $HEAD_COMMIT"
echo "Tester release: exact commit"
echo "CI: $CI_RUN_URL"
echo "Apple distribution secret names: ${#REQUIRED_SECRETS[@]}/${#REQUIRED_SECRETS[@]}"

if [[ "$CHECK_ONLY" == "true" ]]; then
  exit 0
fi

git tag -a "$TAG" -m "Quill Cowork $VERSION" "$HEAD_COMMIT"
if ! git push "$REMOTE" "refs/tags/$TAG:refs/tags/$TAG"; then
  git tag -d "$TAG" >/dev/null 2>&1 || true
  fail "Failed to push $TAG; the newly created local tag was removed."
fi

echo "Stable release started: https://github.com/$REPOSITORY/actions/workflows/download-builds.yml"
