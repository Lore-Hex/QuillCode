#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SMOKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/quillcode-exec-smoke.XXXXXX")"
WORKSPACE="$SMOKE_ROOT/workspace"
HOME_DIR="$SMOKE_ROOT/home"
EPHEMERAL_HOME="$SMOKE_ROOT/ephemeral-home"
STDIN_HOME="$SMOKE_ROOT/stdin-home"
INTERRUPT_HOME="$SMOKE_ROOT/interrupt-home"
trap 'rm -rf "$SMOKE_ROOT"' EXIT

mkdir -p "$WORKSPACE" "$HOME_DIR" "$EPHEMERAL_HOME" "$STDIN_HOME" "$INTERRUPT_HOME"
git -C "$WORKSPACE" init -q
git -C "$WORKSPACE" config user.email quillcode-exec-smoke@example.com
git -C "$WORKSPACE" config user.name "QuillCode Exec Smoke"
printf 'exec smoke\n' > "$WORKSPACE/README.md"
git -C "$WORKSPACE" add README.md
git -C "$WORKSPACE" commit -qm "Create exec smoke fixture"

cd "$ROOT_DIR"
swift build --product quill-code >/dev/null
CLI="$ROOT_DIR/.build/debug/quill-code"
[[ -x "$CLI" ]] || { echo "Built quill-code executable is missing" >&2; exit 1; }

echo "==> Checking exec stdout/stderr and output file"
PLAIN_STDERR="$SMOKE_ROOT/plain.stderr"
FINAL_FILE="$SMOKE_ROOT/final.txt"
PLAIN_OUTPUT="$("$CLI" \
  --home "$HOME_DIR" \
  exec --mock --sandbox workspace-write --cwd "$WORKSPACE" \
  --output-last-message "$FINAL_FILE" \
  "run printf quill_exec_smoke" \
  2>"$PLAIN_STDERR")"
grep -Fq "quill_exec_smoke" <<<"$PLAIN_OUTPUT"
grep -Fq "quill_exec_smoke" "$FINAL_FILE"
grep -Fq "Thread " "$PLAIN_STDERR"

echo "==> Checking JSONL and ephemeral execution"
JSON_OUTPUT="$("$CLI" \
  --home "$EPHEMERAL_HOME" \
  exec --mock --json --ephemeral --cwd "$WORKSPACE" \
  "inspect the repository")"
JSON_OUTPUT="$JSON_OUTPUT" python3 -c '
import json, os
records = [json.loads(line) for line in os.environ["JSON_OUTPUT"].splitlines()]
types = [record.get("type") for record in records]
assert types[0] == "thread.started", types
assert "turn.started" in types, types
assert "item.completed" in types, types
assert types[-1] == "turn.completed", types
'
if [[ -d "$EPHEMERAL_HOME/threads" ]] \
  && [[ -n "$(find "$EPHEMERAL_HOME/threads" -name '*.json' -print -quit)" ]]; then
  echo "Ephemeral exec persisted a thread" >&2
  exit 1
fi

echo "==> Checking stdin prompt"
printf 'piped-smoke-context' | "$CLI" \
  --home "$STDIN_HOME" \
  exec --mock --cwd "$WORKSPACE" - >/dev/null
grep -RFq "piped-smoke-context" "$STDIN_HOME/threads"

echo "==> Checking persisted resume"
"$CLI" --home "$HOME_DIR" exec --mock --cwd "$WORKSPACE" "first turn" >/dev/null
"$CLI" --home "$HOME_DIR" exec resume --last --mock --cwd "$WORKSPACE" "second turn" >/dev/null
THREAD_COUNT="$(find "$HOME_DIR/threads" -name '*.json' -type f | wc -l | tr -d ' ')"
[[ "$THREAD_COUNT" == "2" ]] || {
  echo "Expected the shell run plus resumed chat to produce two thread files; found $THREAD_COUNT" >&2
  exit 1
}

echo "==> Checking Git repository guard"
NON_REPOSITORY="$SMOKE_ROOT/not-a-repository"
mkdir -p "$NON_REPOSITORY"
if "$CLI" --home "$HOME_DIR" exec --mock --cwd "$NON_REPOSITORY" "inspect" \
  >"$SMOKE_ROOT/git-guard.stdout" 2>"$SMOKE_ROOT/git-guard.stderr"; then
  echo "Exec unexpectedly accepted a non-Git workspace" >&2
  exit 1
fi
grep -Fq "not inside a Git repository" "$SMOKE_ROOT/git-guard.stderr"

echo "==> Checking SIGINT cancellation and partial-run persistence"
INTERRUPT_STDOUT="$SMOKE_ROOT/interrupt.stdout"
INTERRUPT_STDERR="$SMOKE_ROOT/interrupt.stderr"
INTERRUPT_FINAL="$SMOKE_ROOT/interrupted-final.txt"
"$CLI" \
  --home "$INTERRUPT_HOME" \
  exec --mock --sandbox workspace-write --cwd "$WORKSPACE" \
  --output-last-message "$INTERRUPT_FINAL" \
  "run exec sleep 30" \
  >"$INTERRUPT_STDOUT" 2>"$INTERRUPT_STDERR" &
INTERRUPT_PID=$!
for _ in {1..200}; do
  grep -Fq "host.shell.run" "$INTERRUPT_STDERR" && break
  kill -0 "$INTERRUPT_PID" 2>/dev/null || {
    echo "Exec exited before the interrupt smoke could signal it" >&2
    exit 1
  }
  sleep 0.05
done
grep -Fq "host.shell.run" "$INTERRUPT_STDERR"
kill -INT "$INTERRUPT_PID"
set +e
wait "$INTERRUPT_PID"
INTERRUPT_STATUS=$?
set -e
[[ "$INTERRUPT_STATUS" == "1" ]] || {
  echo "Interrupted exec returned $INTERRUPT_STATUS instead of 1" >&2
  exit 1
}
grep -Fq "Run interrupted." "$INTERRUPT_STDERR"
[[ ! -e "$INTERRUPT_FINAL" ]]
grep -RFq "Stopped by user" "$INTERRUPT_HOME/threads"

echo "quill-code exec smoke passed"
