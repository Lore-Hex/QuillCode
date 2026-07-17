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
import struct
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
        self._upgrade()

    def _upgrade(self):
        request = (
            "GET / HTTP/1.1\r\n"
            "Host: localhost\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
            "Sec-WebSocket-Version: 13\r\n\r\n"
        ).encode("ascii")
        self.socket.sendall(request)
        while b"\r\n\r\n" not in self.buffer:
            chunk = self.socket.recv(4096)
            if not chunk:
                raise AssertionError("app-server closed before the WebSocket upgrade")
            self.buffer.extend(chunk)
        marker = self.buffer.index(b"\r\n\r\n") + 4
        response = bytes(self.buffer[:marker])
        del self.buffer[:marker]
        assert response.startswith(b"HTTP/1.1 101 Switching Protocols\r\n"), response

    def send(self, message):
        payload = json.dumps(message, separators=(",", ":")).encode("utf-8")
        mask = b"\x11\x22\x33\x44"
        if len(payload) <= 125:
            header = bytes([0x81, 0x80 | len(payload)])
        elif len(payload) <= 0xFFFF:
            header = bytes([0x81, 0xFE]) + struct.pack("!H", len(payload))
        else:
            header = bytes([0x81, 0xFF]) + struct.pack("!Q", len(payload))
        masked = bytes(byte ^ mask[index % 4] for index, byte in enumerate(payload))
        frame = header + mask + masked
        midpoint = max(1, len(frame) // 2)
        self.socket.sendall(frame[:midpoint])
        self.socket.sendall(frame[midpoint:])

    def receive(self):
        try:
            while len(self.buffer) < 2:
                self._read_more()
            first, second = self.buffer[0], self.buffer[1]
            assert first & 0x80 and first & 0x0F == 1, (first, second)
            assert second & 0x80 == 0, "server frames must not be masked"
            length = second & 0x7F
            header_length = 2
            if length == 126:
                while len(self.buffer) < 4:
                    self._read_more()
                length = struct.unpack("!H", self.buffer[2:4])[0]
                header_length = 4
            elif length == 127:
                while len(self.buffer) < 10:
                    self._read_more()
                length = struct.unpack("!Q", self.buffer[2:10])[0]
                header_length = 10
            while len(self.buffer) < header_length + length:
                self._read_more()
            record = bytes(self.buffer[header_length:header_length + length])
            del self.buffer[:header_length + length]
            return json.loads(record)
        except TimeoutError as error:
            raise AssertionError(
                f"app-server did not respond before the protocol deadline: {server_failure()}"
            ) from error

    def _read_more(self):
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
            client.settimeout(timeout)
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

    additional = [connect_client() for _ in range(8)]
    for index, client in enumerate(additional):
        request_id = 10 + (index * 10)
        client.send({"id": request_id, "method": "model/list", "params": {"limit": 1}})
    for index, client in enumerate(additional):
        request_id = 10 + (index * 10)
        uninitialized = client.receive()
        assert uninitialized.get("id") == request_id and "error" in uninitialized, uninitialized
        initialize(client, request_id + 1)
        assert_model_list(client, request_id + 2)
    first.close()
    for client in additional:
        client.close()

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
