#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SMOKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/quillcode-doctor-smoke.XXXXXX")"
HOME_DIR="$SMOKE_ROOT/home"
PORT_FILE="$SMOKE_ROOT/port"
SERVER_LOG="$SMOKE_ROOT/server.log"
SERVER_PID=""

print_server_log() {
  if [[ -s "$SERVER_LOG" ]]; then
    echo "Doctor HTTP fixture diagnostics:" >&2
    cat "$SERVER_LOG" >&2
  fi
}

cleanup() {
  if [[ -n "$SERVER_PID" ]]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$SMOKE_ROOT"
}
trap cleanup EXIT

mkdir -p "$HOME_DIR"
cd "$ROOT_DIR"
swift build --product quill-code >/dev/null
CLI="$ROOT_DIR/.build/debug/quill-code"
[[ -x "$CLI" ]] || { echo "Built quill-code executable is missing" >&2; exit 1; }

API_KEY="doctor-process-private-key"
QUERY_SECRET="doctor-query-private-value"
PROXY_SECRET="doctor-proxy-private-value"
QUILLCODE_DOCTOR_EXPECTED_TOKEN="$API_KEY" \
  python3 "$ROOT_DIR/scripts/fixtures/doctor-http-server.py" "$PORT_FILE" \
  >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!
for _ in {1..300}; do
  [[ -s "$PORT_FILE" ]] && break
  kill -0 "$SERVER_PID" 2>/dev/null || {
    echo "Doctor HTTP fixture exited before publishing its port" >&2
    print_server_log
    exit 1
  }
  sleep 0.05
done
[[ -s "$PORT_FILE" ]] || {
  echo "Doctor HTTP fixture did not publish its port within 15 seconds" >&2
  print_server_log
  exit 1
}
PORT="$(cat "$PORT_FILE")"

printf 'api_base_url = "http://127.0.0.1:%s/v1?token=%s"\n' \
  "$PORT" "$QUERY_SECRET" > "$HOME_DIR/config.toml"
BEFORE_STATE="$(find "$HOME_DIR" -mindepth 1 -print | sort)"
COMMON_ENV=(
  "QUILLCODE_API_KEY=$API_KEY"
  "HTTPS_PROXY=https://proxy-user:$PROXY_SECRET@proxy.example.test"
  "NO_PROXY=127.0.0.1"
  "TERM=xterm-256color"
  "PATH=$ROOT_DIR/.build/debug:$PATH"
)

echo "==> Checking redacted doctor JSON and live reachability"
JSON_OUTPUT="$(env "${COMMON_ENV[@]}" "$CLI" --home "$HOME_DIR" doctor --json)"
JSON_OUTPUT="$JSON_OUTPUT" \
API_KEY="$API_KEY" \
QUERY_SECRET="$QUERY_SECRET" \
PROXY_SECRET="$PROXY_SECRET" \
python3 - <<'PY'
import json
import os

output = os.environ["JSON_OUTPUT"]
report = json.loads(output)
assert report["schemaVersion"] == 1, report
assert report["checks"]["auth.credentials"]["status"] == "ok", report
reachability = report["checks"]["network.provider_reachability"]
assert reachability["status"] == "ok", reachability
assert reachability["details"]["HTTP status"] == "200", reachability
assert reachability["details"]["endpoint"].endswith("/v1/models"), reachability
for secret in (
    os.environ["API_KEY"],
    os.environ["QUERY_SECRET"],
    os.environ["PROXY_SECRET"],
    "proxy-user",
):
    assert secret not in output, f"doctor JSON leaked {secret}"
PY

echo "==> Checking doctor human summary and read-only state inspection"
HUMAN_OUTPUT="$(env "${COMMON_ENV[@]}" \
  "$CLI" --home "$HOME_DIR" doctor --summary --ascii --no-color)"
grep -Fq "QuillCode Doctor" <<<"$HUMAN_OUTPUT"
grep -Fq "Connectivity" <<<"$HUMAN_OUTPUT"
grep -Fq "[ok]" <<<"$HUMAN_OUTPUT"
for secret in "$API_KEY" "$QUERY_SECRET" "$PROXY_SECRET" "proxy-user"; do
  if grep -Fq "$secret" <<<"$HUMAN_OUTPUT"; then
    echo "Doctor human output leaked $secret" >&2
    exit 1
  fi
done
AFTER_STATE="$(find "$HOME_DIR" -mindepth 1 -print | sort)"
[[ "$BEFORE_STATE" == "$AFTER_STATE" ]] || {
  echo "Doctor mutated QuillCode state" >&2
  diff -u <(printf '%s\n' "$BEFORE_STATE") <(printf '%s\n' "$AFTER_STATE") >&2 || true
  exit 1
}

echo "quill-code doctor smoke passed"
