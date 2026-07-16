#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SMOKE_ROOT="$(mktemp -d /tmp/quillcode-app-server-websocket-smoke.XXXXXX)"
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
  "$SMOKE_ROOT/token" \
  "$SMOKE_ROOT/server.stderr" <<'PY'
import json
import socket
import struct
import subprocess
import sys
import time

binary, home, workspace, token_path, stderr_path = sys.argv[1:]


def free_port():
    probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    probe.bind(("127.0.0.1", 0))
    port = probe.getsockname()[1]
    probe.close()
    return port


def start_server(port, extra=()):
    stderr = open(stderr_path, "ab", buffering=0)
    process = subprocess.Popen(
        [
            binary, "--home", home, "app-server",
            "--listen", f"ws://127.0.0.1:{port}", "--mock", *extra,
        ],
        cwd=workspace,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=stderr,
    )
    return process, stderr


def stop_server(process, stderr):
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
    stderr.close()


def connect(port, timeout=10):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            client = socket.create_connection(("127.0.0.1", port), timeout=1)
            client.settimeout(timeout)
            return client
        except OSError:
            time.sleep(0.05)
    raise AssertionError("WebSocket listener did not become ready")


def http_request(port, path, headers=()):
    client = connect(port)
    request = [f"GET {path} HTTP/1.1", "Host: 127.0.0.1", *headers, "", ""]
    client.sendall("\r\n".join(request).encode("ascii"))
    response = bytearray()
    while b"\r\n\r\n" not in response:
        chunk = client.recv(4096)
        if not chunk:
            break
        response.extend(chunk)
    client.close()
    return bytes(response)


class WebSocketClient:
    def __init__(self, port, token=None):
        self.socket = connect(port)
        self.buffer = bytearray()
        headers = [
            "Host: 127.0.0.1",
            "Upgrade: websocket",
            "Connection: Upgrade",
            "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==",
            "Sec-WebSocket-Version: 13",
        ]
        if token is not None:
            headers.append(f"Authorization: Bearer {token}")
        request = "\r\n".join(["GET / HTTP/1.1", *headers, "", ""]).encode("ascii")
        self.socket.sendall(request)
        while b"\r\n\r\n" not in self.buffer:
            self._read_more()
        marker = self.buffer.index(b"\r\n\r\n") + 4
        self.upgrade_response = bytes(self.buffer[:marker])
        del self.buffer[:marker]

    def send(self, message):
        payload = json.dumps(message, separators=(",", ":")).encode("utf-8")
        mask = b"\x12\x34\x56\x78"
        if len(payload) <= 125:
            header = bytes([0x81, 0x80 | len(payload)])
        elif len(payload) <= 0xFFFF:
            header = bytes([0x81, 0xFE]) + struct.pack("!H", len(payload))
        else:
            header = bytes([0x81, 0xFF]) + struct.pack("!Q", len(payload))
        body = bytes(byte ^ mask[index % 4] for index, byte in enumerate(payload))
        self.socket.sendall(header + mask + body)

    def receive(self):
        while len(self.buffer) < 2:
            self._read_more()
        first, second = self.buffer[0], self.buffer[1]
        assert first & 0x80 and first & 0x0F == 1, (first, second)
        assert second & 0x80 == 0
        length = second & 0x7F
        offset = 2
        if length == 126:
            while len(self.buffer) < 4:
                self._read_more()
            length = struct.unpack("!H", self.buffer[2:4])[0]
            offset = 4
        elif length == 127:
            while len(self.buffer) < 10:
                self._read_more()
            length = struct.unpack("!Q", self.buffer[2:10])[0]
            offset = 10
        while len(self.buffer) < offset + length:
            self._read_more()
        payload = bytes(self.buffer[offset:offset + length])
        del self.buffer[:offset + length]
        return json.loads(payload)

    def _read_more(self):
        chunk = self.socket.recv(4096)
        if not chunk:
            raise AssertionError("server closed before completing the response")
        self.buffer.extend(chunk)

    def close(self):
        self.socket.close()


def initialize(client, request_id):
    client.send({
        "id": request_id,
        "method": "initialize",
        "params": {"clientInfo": {"name": "ws-smoke", "version": "1"}},
    })
    response = client.receive()
    assert response.get("id") == request_id and "result" in response, response
    client.send({"method": "initialized", "params": {}})


port = free_port()
process, stderr = start_server(port)
try:
    assert http_request(port, "/readyz").startswith(b"HTTP/1.1 200 OK\r\n")
    assert http_request(port, "/healthz").startswith(b"HTTP/1.1 200 OK\r\n")
    assert http_request(port, "/healthz", ["Origin: https://example.test"]).startswith(
        b"HTTP/1.1 403 Forbidden\r\n"
    )
    client = WebSocketClient(port)
    assert client.upgrade_response.startswith(b"HTTP/1.1 101 Switching Protocols\r\n")
    initialize(client, 1)
    client.send({"id": 2, "method": "model/list", "params": {"limit": 1}})
    response = client.receive()
    assert response.get("id") == 2 and len(response["result"]["data"]) == 1, response
    client.close()
finally:
    stop_server(process, stderr)

with open(token_path, "w", encoding="utf-8") as file:
    file.write("capability-token\n")
port = free_port()
process, stderr = start_server(port, [
    "--ws-auth", "capability-token", "--ws-token-file", token_path,
])
try:
    unauthorized = WebSocketClient(port)
    assert unauthorized.upgrade_response.startswith(b"HTTP/1.1 401 Unauthorized\r\n")
    unauthorized.close()
    authorized = WebSocketClient(port, token="capability-token")
    assert authorized.upgrade_response.startswith(b"HTTP/1.1 101 Switching Protocols\r\n")
    initialize(authorized, 10)
    authorized.close()
finally:
    stop_server(process, stderr)

port = free_port()
failure = subprocess.run(
    [binary, "--home", home, "app-server", "--listen", f"ws://0.0.0.0:{port}", "--mock"],
    cwd=workspace,
    stdin=subprocess.DEVNULL,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    timeout=5,
    check=False,
)
assert failure.returncode != 0, failure
assert b"non-loopback WebSocket listeners require --ws-auth" in failure.stderr, failure.stderr

print("app-server WebSocket smoke passed")
PY
