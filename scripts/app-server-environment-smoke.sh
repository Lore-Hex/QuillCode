#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SMOKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/quillcode-app-server-environment-smoke.XXXXXX")"
trap 'rm -rf "$SMOKE_ROOT"' EXIT

mkdir -p "$SMOKE_ROOT/home" "$SMOKE_ROOT/workspace"
cd "$ROOT_DIR"
if [[ "${QUILLCODE_SKIP_BUILD:-0}" != "1" ]]; then
  swift build --product quill-code >/dev/null
fi

PYTHONPATH="$ROOT_DIR/scripts/fixtures${PYTHONPATH:+:$PYTHONPATH}" \
  python3 - \
  "$ROOT_DIR/.build/debug/quill-code" \
  "$SMOKE_ROOT/home" \
  "$SMOKE_ROOT/workspace" <<'PY'
import json
import os
import select
import subprocess
import sys
import time

from app_server_environment_exec_server import ExecServer

binary, home, workspace = [os.path.abspath(path) for path in sys.argv[1:]]

server = ExecServer()
server.start()
process = subprocess.Popen(
    [binary, "--home", home, "app-server", "--mock"],
    cwd=workspace,
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    bufsize=1,
)
records = []


def send(message):
    process.stdin.write(json.dumps(message, separators=(",", ":")) + "\n")
    process.stdin.flush()


def read_record(timeout=15):
    ready, _, _ = select.select([process.stdout], [], [], timeout)
    if not ready:
        raise AssertionError("app-server did not respond before timeout")
    line = process.stdout.readline()
    if not line:
        raise AssertionError(
            "app-server closed early: " + process.stderr.read()
        )
    record = json.loads(line)
    records.append(record)
    return record


def read_until(predicate, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        record = read_record(max(0.01, deadline - time.monotonic()))
        if predicate(record):
            return record
    raise AssertionError("app-server did not emit the expected record")


def response(request_id):
    return read_until(lambda record: record.get("id") == request_id)


try:
    send({
        "id": 1,
        "method": "initialize",
        "params": {"clientInfo": {"name": "environment-smoke", "version": "1"}},
    })
    assert "result" in response(1)
    send({"method": "initialized", "params": {}})

    send({
        "id": 2,
        "method": "environment/add",
        "params": {
            "environmentId": "remote",
            "execServerUrl": f"ws://127.0.0.1:{server.port}",
            "connectTimeoutMs": 2_000,
        },
    })
    assert response(2)["result"] == {}
    send({
        "id": 3,
        "method": "environment/info",
        "params": {"environmentId": "remote"},
    })
    info = response(3)["result"]
    assert info == {
        "shell": {"name": "zsh", "path": "/bin/zsh"},
        "cwd": "file:///workspace",
    }, info
    send({
        "id": 4,
        "method": "environment/status",
        "params": {"environmentId": "remote"},
    })
    assert response(4)["result"] == {"status": "ready", "error": None}
    send({
        "id": 5,
        "method": "environment/status",
        "params": {"environmentId": "missing"},
    })
    assert response(5)["result"] == {
        "status": "unknown",
        "error": "unknown environment id `missing`",
    }

    send({
        "id": 6,
        "method": "thread/start",
        "params": {
            "cwd": workspace,
            "model": "trustedrouter/fast",
            "sandbox": "read-only",
            "environments": [{"environmentId": "remote", "cwd": "/workspace"}],
        },
    })
    thread_id = response(6)["result"]["thread"]["id"]
    assert not any(
        record.get("method") == "thread/environment/connected"
        for record in records
    ), "already-connected state was replayed to a newly selected thread"
    local_sentinel = os.path.join(workspace, "must-not-run-locally")
    remote_command = f"touch {local_sentinel}; printf remote-shell"
    send({
        "id": 7,
        "method": "thread/shellCommand",
        "params": {"threadId": thread_id, "command": remote_command},
    })
    assert response(7)["result"] == {}
    completed = read_until(
        lambda record: record.get("method") == "item/completed"
    )
    item = completed["params"]["item"]
    assert item["status"] == "completed", item
    assert item["aggregatedOutput"] == "remote-shell\nlate-output\n", item
    assert item["cwd"] == "/workspace", item
    read_until(lambda record: record.get("method") == "turn/completed")
    assert not os.path.exists(local_sentinel), "remote command ran on the local host"
    assert len(server.process_starts) == 1, server.process_starts
    start = server.process_starts[0]
    assert start["argv"] == ["/bin/zsh", "-lc", remote_command], start
    assert start["cwd"] == "file:///workspace", start

    server.disconnect_client()
    disconnected = read_until(
        lambda record: record.get("method") == "thread/environment/disconnected"
    )
    assert disconnected["params"] == {
        "threadId": thread_id,
        "environmentId": "remote",
    }, disconnected

    send({
        "id": 8,
        "method": "environment/info",
        "params": {"environmentId": "remote"},
    })
    assert response(8)["result"] == info
    connected = next((
        record for record in records
        if record.get("method") == "thread/environment/connected"
        and record.get("params", {}).get("threadId") == thread_id
    ), None)
    if connected is None:
        connected = read_until(
            lambda record: (
                record.get("method") == "thread/environment/connected"
                and record.get("params", {}).get("threadId") == thread_id
            )
        )
    assert connected["params"] == {
        "threadId": thread_id,
        "environmentId": "remote",
    }, connected
    send({
        "id": 9,
        "method": "environment/status",
        "params": {"environmentId": "remote"},
    })
    assert response(9)["result"] == {"status": "ready", "error": None}

    send({
        "id": 10,
        "method": "thread/start",
        "params": {
            "cwd": workspace,
            "model": "trustedrouter/fast",
            "sandbox": "read-only",
            "environments": [],
        },
    })
    disabled_thread_id = response(10)["result"]["thread"]["id"]
    disabled_sentinel = os.path.join(workspace, "disabled-must-not-run")
    send({
        "id": 11,
        "method": "thread/shellCommand",
        "params": {
            "threadId": disabled_thread_id,
            "command": f"touch {disabled_sentinel}",
        },
    })
    disabled = response(11)
    assert disabled["error"]["code"] == -32600, disabled
    assert disabled["error"]["message"] == (
        "environment access is disabled for this thread"
    ), disabled
    assert not os.path.exists(disabled_sentinel), "disabled command ran locally"
    assert len(server.process_starts) == 1, server.process_starts

    send({
        "id": 12,
        "method": "thread/start",
        "params": {
            "cwd": workspace,
            "model": "trustedrouter/fast",
            "sandbox": "read-only",
            "environments": [{"environmentId": "missing", "cwd": "/workspace"}],
        },
    })
    missing = response(12)
    assert missing["error"]["code"] == -32600, missing
    assert "unknown turn environment id `missing`" in missing["error"]["message"], missing
finally:
    if process.stdin and not process.stdin.closed:
        process.stdin.close()
    try:
        return_code = process.wait(timeout=15)
    except subprocess.TimeoutExpired:
        process.terminate()
        return_code = process.wait(timeout=5)
    stderr = process.stderr.read()
    server.close()
    if return_code != 0:
        raise AssertionError(
            f"app-server exited with {return_code}: {stderr}"
        )

assert server.methods[:2] == ["initialize", "initialized"], (
    server.methods
)
assert server.methods.count("initialize") == 2, server.methods
assert server.methods.count("initialized") == 2, server.methods
assert server.methods.count("environment/status") == 2, server.methods
assert server.methods.count("environment/info") >= 3, server.methods
PY

echo "app-server environment smoke passed"
