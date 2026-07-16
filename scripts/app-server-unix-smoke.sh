#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SMOKE_ROOT="$(mktemp -d /tmp/quillcode-app-server-unix-smoke.XXXXXX)"
trap 'rm -rf "$SMOKE_ROOT"' EXIT

mkdir -p "$SMOKE_ROOT/home" "$SMOKE_ROOT/workspace"
cd "$ROOT_DIR"
if [[ "${QUILLCODE_SKIP_BUILD:-0}" != "1" ]]; then
  swift build --product quill-code >/dev/null
fi

python3 - \
  "$ROOT_DIR/.build/debug/quill-code" \
  "$SMOKE_ROOT/home" \
  "$SMOKE_ROOT/workspace" \
  "$SMOKE_ROOT/app-server.sock" \
  "$SMOKE_ROOT/server.stderr" <<'PY'
import json
import os
import socket
import stat
import subprocess
import sys
import time

binary, home, workspace, socket_path, stderr_path = sys.argv[1:]
process = None
stderr_file = None


def start_server():
    global process, stderr_file
    stderr_file = open(stderr_path, "ab", buffering=0)
    process = subprocess.Popen(
        [
            binary,
            "--home",
            home,
            "app-server",
            "--listen",
            f"unix://{socket_path}",
            "--mock",
        ],
        cwd=workspace,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=stderr_file,
    )


def stop_server(force=False):
    global process, stderr_file
    if process is not None and process.poll() is None:
        if force:
            process.kill()
        else:
            process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
    process = None
    if stderr_file is not None:
        stderr_file.close()
        stderr_file = None


def server_failure():
    if os.path.exists(stderr_path):
        with open(stderr_path, "r", encoding="utf-8", errors="replace") as file:
            return file.read()
    return ""


class UnixClient:
    def __init__(self, raw_socket):
        self.socket = raw_socket
        self.buffer = bytearray()

    def send(self, message):
        payload = json.dumps(message, separators=(",", ":")).encode("utf-8") + b"\n"
        midpoint = max(1, len(payload) // 2)
        self.socket.sendall(payload[:midpoint])
        self.socket.sendall(payload[midpoint:])

    def receive(self):
        while True:
            newline = self.buffer.find(b"\n")
            if newline >= 0:
                record = bytes(self.buffer[:newline])
                del self.buffer[:newline + 1]
                return json.loads(record)
            chunk = self.socket.recv(4096)
            if not chunk:
                raise AssertionError("app-server closed the Unix client before responding")
            self.buffer.extend(chunk)

    def close(self):
        self.socket.close()


def connect_client(timeout=10):
    deadline = time.monotonic() + timeout
    last_error = None
    while time.monotonic() < deadline:
        if process is not None and process.poll() is not None:
            raise AssertionError(
                f"app-server exited before accepting a client: {server_failure()}"
            )
        client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        client.settimeout(1)
        try:
            client.connect(socket_path)
            return UnixClient(client)
        except OSError as error:
            last_error = error
            client.close()
            time.sleep(0.05)
    raise AssertionError(f"app-server socket was not ready: {last_error}")


def initialize(client, request_id):
    client.send({
        "id": request_id,
        "method": "initialize",
        "params": {
            "clientInfo": {"name": "quillcode-unix-smoke", "version": "1"},
            "capabilities": {"experimentalApi": True},
        },
    })
    response = client.receive()
    assert response.get("id") == request_id and "result" in response, response
    client.send({"method": "initialized", "params": {}})


def assert_model_list(client, request_id):
    client.send({"id": request_id, "method": "model/list", "params": {"limit": 1}})
    response = client.receive()
    assert response.get("id") == request_id, response
    assert len(response["result"]["data"]) == 1, response


try:
    start_server()
    first = connect_client()
    mode = stat.S_IMODE(os.stat(socket_path).st_mode)
    assert mode == 0o600, oct(mode)
    initialize(first, 1)
    assert_model_list(first, 2)

    second = connect_client()
    second.send({"id": 10, "method": "model/list", "params": {"limit": 1}})
    uninitialized = second.receive()
    assert uninitialized.get("id") == 10 and "error" in uninitialized, uninitialized
    initialize(second, 11)
    assert_model_list(second, 12)
    first.close()
    second.close()

    stop_server(force=True)
    assert os.path.exists(socket_path), "forced exit should leave a stale socket"

    start_server()
    recovered = connect_client()
    initialize(recovered, 20)
    assert_model_list(recovered, 21)
    recovered.close()
finally:
    stop_server()

print("app-server Unix socket smoke passed")
PY
