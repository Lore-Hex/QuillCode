#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SMOKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/quillcode-mcp-server-smoke.XXXXXX")"
trap 'rm -rf "$SMOKE_ROOT"' EXIT

mkdir -p "$SMOKE_ROOT/home" "$SMOKE_ROOT/workspace"
cd "$ROOT_DIR"
if [[ "${QUILLCODE_SKIP_BUILD:-0}" != "1" ]]; then
  swift build --product quill-code >/dev/null
fi

python3 - \
  "$ROOT_DIR/.build/debug/quill-code" \
  "$SMOKE_ROOT/home" \
  "$SMOKE_ROOT/workspace" <<'PY'
import atexit
import json
import os
import select
import subprocess
import sys
import time

binary, home, workspace = sys.argv[1:]
process = subprocess.Popen(
    [binary, "--home", home, "mcp-server", "--mock"],
    cwd=workspace,
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    bufsize=0,
)
# Frame bytes ourselves: TextIOWrapper can prefetch JSONL records that select() can no longer see.
stdout_buffer = bytearray()

def cleanup_process():
    if process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)

atexit.register(cleanup_process)

def send(message):
    line = json.dumps(message, separators=(",", ":")) + "\n"
    process.stdin.write(line.encode("utf-8"))
    process.stdin.flush()

def read_record(timeout):
    deadline = time.monotonic() + timeout
    while True:
        newline = stdout_buffer.find(b"\n")
        if newline >= 0:
            line = bytes(stdout_buffer[:newline])
            del stdout_buffer[: newline + 1]
            record = json.loads(line.decode("utf-8"))
            assert record.get("jsonrpc") == "2.0", record
            return record
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise AssertionError("mcp-server timed out waiting for a protocol record")
        ready, _, _ = select.select([process.stdout], [], [], remaining)
        if not ready:
            raise AssertionError("mcp-server timed out waiting for a protocol record")
        chunk = os.read(process.stdout.fileno(), 64 * 1_024)
        if not chunk:
            raise AssertionError("mcp-server closed before completing a protocol record")
        stdout_buffer.extend(chunk)

def read_until(predicate, timeout=10, limit=200):
    records = []
    deadline = time.monotonic() + timeout
    for _ in range(limit):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        try:
            record = read_record(remaining)
        except AssertionError as error:
            recent = json.dumps(records[-8:], separators=(",", ":"))
            raise AssertionError(f"{error}; recent protocol records: {recent}") from error
        records.append(record)
        if predicate(record):
            return record, records
    recent = json.dumps(records[-8:], separators=(",", ":"))
    raise AssertionError(
        f"mcp-server did not emit the expected protocol record within {timeout}s; "
        f"recent protocol records: {recent}"
    )

send({
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
        "protocolVersion": "2025-06-18",
        "capabilities": {},
        "clientInfo": {"name": "quillcode-smoke", "version": "1"},
    },
})
initialized, _ = read_until(lambda record: record.get("id") == 1)
assert initialized["result"]["protocolVersion"] == "2025-06-18", initialized
assert initialized["result"]["serverInfo"]["name"] == "quillcode-mcp-server", initialized
send({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})

send({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
catalog, _ = read_until(lambda record: record.get("id") == 2)
assert [tool["name"] for tool in catalog["result"]["tools"]] == ["codex", "codex-reply"], catalog

send({
    "jsonrpc": "2.0",
    "id": "start",
    "method": "tools/call",
    "params": {
        "name": "codex",
        "arguments": {
            "prompt": "Run `whoami` and report the result.",
            "cwd": workspace,
            "approval-policy": "never",
            "sandbox": "workspace-write",
            "compact-prompt": "Preserve verified commands and unresolved work.",
        },
    },
})
_, start_records = read_until(
    lambda record: record.get("method") == "codex/event"
    and record.get("params", {}).get("msg", {}).get("type") == "session_configured"
)
started, remaining_start_records = read_until(
    lambda record: record.get("id") == "start",
    timeout=30,
)
start_records.extend(remaining_start_records)
assert started["result"]["isError"] is False, started
structured = started["result"]["structuredContent"]
thread_id = structured["threadId"]
assert thread_id and structured["content"], started
events = [record["params"] for record in start_records if record.get("method") == "codex/event"]
event_types = [event["msg"]["type"] for event in events]
assert "session_configured" in event_types, event_types
assert "exec_command_begin" in event_types, event_types
assert "exec_command_end" in event_types, event_types
assert "turn_complete" in event_types, event_types
assert all(event["_meta"]["threadId"] == thread_id for event in events), events

send({
    "jsonrpc": "2.0",
    "id": "reply",
    "method": "tools/call",
    "params": {
        "name": "codex-reply",
        "arguments": {
            "threadId": thread_id,
            "prompt": "Reply with: MCP reply smoke complete.",
        },
    },
})
replied, reply_records = read_until(
    lambda record: record.get("id") == "reply",
    timeout=30,
)
assert replied["result"]["isError"] is False, replied
reply_content = replied["result"]["structuredContent"]["content"]
assert replied["result"]["structuredContent"]["threadId"] == thread_id, replied
assert reply_content.strip(), replied
reply_events = [record["params"] for record in reply_records if record.get("method") == "codex/event"]
assert any(event["msg"]["type"] == "turn_complete" for event in reply_events), reply_events

thread_file = os.path.join(home, "threads", f"{thread_id}.json")
metadata_file = os.path.join(home, "app-server-threads", f"{thread_id}.json")
assert os.path.isfile(thread_file), thread_file
assert os.path.isfile(metadata_file), metadata_file
with open(metadata_file, "r", encoding="utf-8") as handle:
    metadata = json.load(handle)
assert metadata["compactPrompt"] == "Preserve verified commands and unresolved work.", metadata
with open(thread_file, "r", encoding="utf-8") as handle:
    persisted_thread = json.load(handle)
user_messages = [
    message["content"]
    for message in persisted_thread["messages"]
    if message["role"] == "user"
]
assert user_messages == [
    "Run `whoami` and report the result.",
    "Reply with: MCP reply smoke complete.",
], user_messages

process.stdin.close()
return_code = process.wait(timeout=10)
stderr = process.stderr.read().decode("utf-8", errors="replace")
assert return_code == 0, (return_code, stderr)
assert "sk-tr-" not in json.dumps(start_records + reply_records), "secret-like output leaked"
print("QuillCode MCP server smoke passed")
PY
