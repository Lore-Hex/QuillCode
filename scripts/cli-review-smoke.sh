#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SMOKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/quillcode-review-smoke.XXXXXX")"
WORKSPACE="$SMOKE_ROOT/workspace"
HOME_DIR="$SMOKE_ROOT/home"
NON_REPOSITORY="$SMOKE_ROOT/not-a-repository"
trap 'rm -rf "$SMOKE_ROOT"' EXIT

mkdir -p "$WORKSPACE" "$HOME_DIR" "$NON_REPOSITORY"
git -C "$WORKSPACE" init -q
git -C "$WORKSPACE" config user.email quillcode-review-smoke@example.com
git -C "$WORKSPACE" config user.name "QuillCode Review Smoke"
printf 'initial\n' > "$WORKSPACE/README.md"
git -C "$WORKSPACE" add README.md
git -C "$WORKSPACE" commit -qm "Initial review fixture"
BASE_BRANCH="$(git -C "$WORKSPACE" branch --show-current)"
git -C "$WORKSPACE" switch -qc review-feature
printf 'feature\n' > "$WORKSPACE/Feature.swift"
git -C "$WORKSPACE" add Feature.swift
git -C "$WORKSPACE" commit -qm "Add review feature"
printf 'uncommitted\n' >> "$WORKSPACE/README.md"
printf 'untracked\n' > "$WORKSPACE/Untracked.swift"

cd "$ROOT_DIR"
swift build --product quill-code >/dev/null
CLI="$ROOT_DIR/.build/debug/quill-code"
[[ -x "$CLI" ]] || { echo "Built quill-code executable is missing" >&2; exit 1; }

run_review() {
  local label="$1"
  shift
  local stdout="$SMOKE_ROOT/$label.stdout"
  local stderr="$SMOKE_ROOT/$label.stderr"
  "$CLI" --home "$HOME_DIR" review --mock "$@" --cwd "$WORKSPACE" >"$stdout" 2>"$stderr"
  grep -Fq "## Code review" "$stdout"
  grep -Fq "No actionable findings." "$stdout"
  grep -Fq "host.review.submit" "$stderr"
  if grep -Fq "✗" "$stderr"; then
    echo "Review smoke $label reported a failed tool" >&2
    cat "$stderr" >&2
    exit 1
  fi
}

echo "==> Checking uncommitted review"
run_review uncommitted --uncommitted
grep -Fq "host.git.status" "$SMOKE_ROOT/uncommitted.stderr"
[[ "$(grep -Fc "✓ host.git.diff" "$SMOKE_ROOT/uncommitted.stderr")" == "2" ]]

echo "==> Checking base and commit reviews"
run_review base --base "$BASE_BRANCH"
run_review commit --commit HEAD --title "Add review feature"
grep -Fq "## Code review: Add review feature" "$SMOKE_ROOT/commit.stdout"

echo "==> Checking stdin custom review"
printf 'Focus on cancellation and cleanup.\n' | "$CLI" \
  --home "$HOME_DIR" review --mock - --cwd "$WORKSPACE" \
  >"$SMOKE_ROOT/stdin.stdout" 2>"$SMOKE_ROOT/stdin.stderr"
grep -Fq "## Code review" "$SMOKE_ROOT/stdin.stdout"
grep -Fq "✓ host.review.submit" "$SMOKE_ROOT/stdin.stderr"

echo "==> Checking help and fail-closed guards"
"$CLI" review --help >"$SMOKE_ROOT/help.stdout"
grep -Fq "quill-code review --uncommitted" "$SMOKE_ROOT/help.stdout"
if "$CLI" --home "$HOME_DIR" review --mock --cwd "$WORKSPACE" \
  >"$SMOKE_ROOT/missing.stdout" 2>"$SMOKE_ROOT/missing.stderr"; then
  echo "Review unexpectedly accepted a missing target" >&2
  exit 1
fi
grep -Fq "Choose exactly one review target" "$SMOKE_ROOT/missing.stderr"
if "$CLI" --home "$HOME_DIR" review --mock --uncommitted --cwd "$NON_REPOSITORY" \
  >"$SMOKE_ROOT/non-git.stdout" 2>"$SMOKE_ROOT/non-git.stderr"; then
  echo "Review unexpectedly accepted a non-Git workspace" >&2
  exit 1
fi
grep -Fq "not inside a Git repository" "$SMOKE_ROOT/non-git.stderr"

if [[ -d "$HOME_DIR/threads" ]] \
  && [[ -n "$(find "$HOME_DIR/threads" -name '*.json' -print -quit)" ]]; then
  echo "Review persisted an ephemeral review thread" >&2
  exit 1
fi

echo "quill-code review smoke passed"
