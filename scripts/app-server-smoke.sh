#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SMOKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/quillcode-app-server-smoke.XXXXXX")"
trap 'rm -rf "$SMOKE_ROOT"' EXIT

mkdir -p "$SMOKE_ROOT/home" "$SMOKE_ROOT/workspace"
cd "$ROOT_DIR"
swift build --product quill-code >/dev/null

python3 - "$ROOT_DIR/.build/debug/quill-code" "$SMOKE_ROOT/home" "$SMOKE_ROOT/workspace" <<'PY'
import json
import subprocess
import sys

binary, home, workspace = sys.argv[1:]
process = subprocess.Popen(
    [binary, "--home", home, "app-server", "--mock"],
    cwd=workspace,
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    bufsize=1,
)

def send(message):
    process.stdin.write(json.dumps(message, separators=(",", ":")) + "\n")
    process.stdin.flush()

def read_until(predicate, limit=200):
    records = []
    for _ in range(limit):
        line = process.stdout.readline()
        if not line:
            stderr = process.stderr.read()
            raise AssertionError(f"app-server closed early: {stderr}")
        record = json.loads(line)
        records.append(record)
        if predicate(record):
            return record, records
    raise AssertionError("app-server did not emit the expected record")

send({"id": 1, "method": "initialize", "params": {
    "clientInfo": {"name": "quillcode-smoke", "version": "1"}
}})
initialized, _ = read_until(lambda record: record.get("id") == 1)
assert "result" in initialized and "jsonrpc" not in initialized, initialized
send({"method": "initialized", "params": {}})

send({"id": 2, "method": "model/list", "params": {"limit": 2}})
models, _ = read_until(lambda record: record.get("id") == 2)
assert len(models["result"]["data"]) == 2, models
assert models["result"]["data"][0]["isDefault"] is True, models
assert models["result"]["nextCursor"], models

send({"id": 3, "method": "account/read", "params": {}})
account, _ = read_until(lambda record: record.get("id") == 3)
assert account["result"] == {"account": None, "requiresOpenaiAuth": False}, account

send({"id": 4, "method": "config/read", "params": {"cwd": workspace}})
config, _ = read_until(lambda record: record.get("id") == 4)
assert config["result"]["config"]["model"] == "trustedrouter/fast", config
assert config["result"]["config"]["model_provider"] == "trustedrouter", config

send({"id": 5, "method": "thread/start", "params": {
    "cwd": workspace,
    "model": "trustedrouter/fast",
    "sandbox": "workspace-write",
}})
started, _ = read_until(lambda record: record.get("id") == 5)
thread_id = started["result"]["thread"]["id"]

send({"id": 6, "method": "turn/start", "params": {
    "threadId": thread_id,
    "input": [{"type": "text", "text": "app-server smoke"}],
}})
turn_response, records = read_until(lambda record: record.get("id") == 6)
assert turn_response["result"]["turn"]["status"] == "inProgress", turn_response
completed, tail = read_until(lambda record: record.get("method") == "turn/completed")
records.extend(tail)
assert completed["params"]["turn"]["status"] == "completed", completed
methods = {record.get("method") for record in records}
assert "turn/started" in methods, methods
assert "item/started" in methods, methods
assert "item/completed" in methods, methods

process.stdin.close()
status = process.wait(timeout=10)
stderr = process.stderr.read()
assert status == 0, (status, stderr)
PY

echo "quill-code app-server smoke passed"
