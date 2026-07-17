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

from app_server_environment_exec_server import ExecServer, READ_ONLY_SANDBOX

binary, home, workspace = [os.path.abspath(path) for path in sys.argv[1:]]
RESPONSE_TIMEOUT = float(os.environ.get("QUILLCODE_APP_SERVER_SMOKE_TIMEOUT", "45"))

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


def read_record(timeout=RESPONSE_TIMEOUT):
    ready, _, _ = select.select([process.stdout], [], [], timeout)
    if not ready:
        raise AssertionError(
            "app-server did not respond before timeout "
            f"(timeout={timeout:.1f}s, poll={process.poll()}, "
            f"records={len(records)}, exec_methods={server.methods[-12:]!r})"
        )
    line = process.stdout.readline()
    if not line:
        raise AssertionError(
            "app-server closed early: " + process.stderr.read()
        )
    record = json.loads(line)
    records.append(record)
    return record


def read_until(predicate, timeout=RESPONSE_TIMEOUT):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        record = read_record(max(0.01, deadline - time.monotonic()))
        if predicate(record):
            return record
    raise AssertionError("app-server did not emit the expected record")


def response(request_id, timeout=RESPONSE_TIMEOUT):
    return read_until(lambda record: record.get("id") == request_id, timeout=timeout)


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
    assert start["sandbox"] == READ_ONLY_SANDBOX, start
    assert start["enforceManagedNetwork"] is False, start
    assert start["managedNetwork"] is None, start
    assert server.file_system_requests, "expected a canonicalize request"
    assert all(
        request["sandbox"] == READ_ONLY_SANDBOX
        for request in server.file_system_requests
    ), server.file_system_requests

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

    background_commands = {
        "printf quillcode-background-smoke-one",
        "printf quillcode-background-smoke-two",
    }
    for request_id, command in zip((10, 11), sorted(background_commands)):
        send({
            "id": request_id,
            "method": "thread/shellCommand",
            "params": {"threadId": thread_id, "command": command},
        })
        assert response(request_id)["result"] == {}

    expected_live_outputs = {"background-one\n", "background-two\n"}
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        live_outputs = {
            record.get("params", {}).get("delta")
            for record in records
            if record.get("method") == "item/commandExecution/outputDelta"
        }
        if expected_live_outputs <= live_outputs:
            break
        read_record(max(0.01, deadline - time.monotonic()))
    else:
        raise AssertionError("remote background output did not stream before exit")

    background_item_ids = {
        item["id"]
        for record in records
        if record.get("method") == "item/started"
        for item in [record.get("params", {}).get("item", {})]
        if item.get("commandActions")
        and item["commandActions"][0].get("command") in background_commands
    }
    assert len(background_item_ids) == 2, background_item_ids
    completed_item_ids = {
        record.get("params", {}).get("item", {}).get("id")
        for record in records
        if record.get("method") == "item/completed"
    }
    assert background_item_ids.isdisjoint(completed_item_ids), (
        "background commands completed before lifecycle inspection",
        background_item_ids,
        completed_item_ids,
    )

    send({
        "id": 12,
        "method": "thread/backgroundTerminals/list",
        "params": {"threadId": thread_id},
    })
    terminals = response(12)["result"]["data"]
    assert len(terminals) == 2, terminals
    assert all(terminal["osPid"] is None for terminal in terminals), terminals
    assert {terminal["command"] for terminal in terminals} == background_commands, terminals
    process_ids = {terminal["processId"] for terminal in terminals}
    assert process_ids == {
        start["processId"] for start in server.process_starts[-2:]
    }, (process_ids, server.process_starts)

    terminated_process_id = terminals[0]["processId"]
    send({
        "id": 13,
        "method": "thread/backgroundTerminals/terminate",
        "params": {
            "threadId": thread_id,
            "processId": terminated_process_id,
        },
    })
    assert response(13)["result"] == {"terminated": True}
    deadline = time.monotonic() + 15
    while terminated_process_id not in server.process_terminations:
        if time.monotonic() >= deadline:
            raise AssertionError(
                "remote process terminate was not forwarded: "
                f"methods={server.methods!r} reads={server.process_reads!r}"
            )
        time.sleep(0.01)

    send({
        "id": 14,
        "method": "thread/backgroundTerminals/list",
        "params": {"threadId": thread_id},
    })
    remaining = response(14)["result"]["data"]
    assert len(remaining) == 1, remaining
    assert remaining[0]["processId"] != terminated_process_id, remaining

    send({
        "id": 15,
        "method": "thread/backgroundTerminals/clean",
        "params": {"threadId": thread_id},
    })
    assert response(15)["result"] == {}
    deadline = time.monotonic() + 15
    while set(server.process_terminations) != process_ids:
        if time.monotonic() >= deadline:
            raise AssertionError("remote background clean was not forwarded")
        time.sleep(0.01)
    send({
        "id": 16,
        "method": "thread/backgroundTerminals/list",
        "params": {"threadId": thread_id},
    })
    assert response(16)["result"] == {"data": [], "nextCursor": None}

    send({
        "id": 20,
        "method": "thread/start",
        "params": {
            "cwd": workspace,
            "model": "trustedrouter/fast",
            "sandbox": "read-only",
            "environments": [],
        },
    })
    disabled_thread_id = response(20)["result"]["thread"]["id"]
    disabled_sentinel = os.path.join(workspace, "disabled-must-not-run")
    send({
        "id": 21,
        "method": "thread/shellCommand",
        "params": {
            "threadId": disabled_thread_id,
            "command": f"touch {disabled_sentinel}",
        },
    })
    disabled = response(21)
    assert disabled["error"]["code"] == -32600, disabled
    assert disabled["error"]["message"] == (
        "environment access is disabled for this thread"
    ), disabled
    assert not os.path.exists(disabled_sentinel), "disabled command ran locally"
    assert len(server.process_starts) == 3, server.process_starts

    send({
        "id": 22,
        "method": "thread/start",
        "params": {
            "cwd": workspace,
            "model": "trustedrouter/fast",
            "sandbox": "read-only",
            "environments": [{"environmentId": "missing", "cwd": "/workspace"}],
        },
    })
    missing = response(22)
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
assert server.methods.count("initialize") >= 2, server.methods
assert server.methods.count("initialize") == server.methods.count("initialized"), server.methods
assert server.methods.count("environment/status") == 2, server.methods
assert server.methods.count("environment/info") >= 3, server.methods
assert server.methods.count("process/terminate") == 2, server.methods
PY

echo "app-server environment smoke passed"
