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

python3 - \
  "$ROOT_DIR/.build/debug/quill-code" \
  "$SMOKE_ROOT/home" \
  "$SMOKE_ROOT/workspace" <<'PY'
import base64
import hashlib
import json
import os
import select
import socket
import struct
import subprocess
import sys
import threading
import time

binary, home, workspace = [os.path.abspath(path) for path in sys.argv[1:]]


def receive_exact(connection, count):
    data = bytearray()
    while len(data) < count:
        chunk = connection.recv(count - len(data))
        if not chunk:
            raise EOFError("WebSocket peer closed")
        data.extend(chunk)
    return bytes(data)


def receive_http_request(connection):
    data = bytearray()
    while b"\r\n\r\n" not in data:
        data.extend(connection.recv(4096))
        if len(data) > 64 * 1024:
            raise AssertionError("oversized WebSocket upgrade request")
    return bytes(data)


def receive_text_frame(connection):
    first, second = receive_exact(connection, 2)
    opcode = first & 0x0F
    length = second & 0x7F
    if length == 126:
        length = struct.unpack("!H", receive_exact(connection, 2))[0]
    elif length == 127:
        length = struct.unpack("!Q", receive_exact(connection, 8))[0]
    mask = receive_exact(connection, 4) if second & 0x80 else None
    payload = bytearray(receive_exact(connection, length))
    if mask is not None:
        for index in range(len(payload)):
            payload[index] ^= mask[index % 4]
    if opcode == 8:
        return None
    if opcode == 9:
        send_frame(connection, 10, payload)
        return receive_text_frame(connection)
    if opcode != 1 or first & 0x80 == 0:
        raise AssertionError(f"expected one complete text frame, got opcode {opcode}")
    return payload.decode("utf-8")


def send_frame(connection, opcode, payload):
    payload = bytes(payload)
    if len(payload) <= 125:
        header = bytes([0x80 | opcode, len(payload)])
    elif len(payload) <= 0xFFFF:
        header = bytes([0x80 | opcode, 126]) + struct.pack("!H", len(payload))
    else:
        header = bytes([0x80 | opcode, 127]) + struct.pack("!Q", len(payload))
    connection.sendall(header + payload)


def send_json(connection, value):
    send_frame(
        connection,
        1,
        json.dumps(value, separators=(",", ":")).encode("utf-8"),
    )


class ExecServer:
    def __init__(self):
        self.listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.listener.bind(("127.0.0.1", 0))
        self.listener.listen(1)
        self.port = self.listener.getsockname()[1]
        self.connection = None
        self.error = None
        self.methods = []
        self.process_starts = []
        self.process_reads = {}
        self.thread = threading.Thread(target=self._run, daemon=True)

    def start(self):
        self.thread.start()

    def close(self):
        if self.connection is not None:
            try:
                self.connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            self.connection.close()
        self.listener.close()
        self.thread.join(timeout=5)
        if self.thread.is_alive():
            raise AssertionError("exec-server fixture did not stop")
        if self.error is not None:
            raise self.error

    def _run(self):
        try:
            self.connection, _ = self.listener.accept()
            self.connection.settimeout(15)
            request = receive_http_request(self.connection).decode("latin-1")
            headers = {}
            for line in request.split("\r\n")[1:]:
                if ":" in line:
                    key, value = line.split(":", 1)
                    headers[key.strip().lower()] = value.strip()
            key = headers.get("sec-websocket-key")
            if not key:
                raise AssertionError("missing WebSocket key")
            digest = hashlib.sha1(
                (key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode("ascii")
            ).digest()
            accept = base64.b64encode(digest).decode("ascii")
            self.connection.sendall(
                (
                    "HTTP/1.1 101 Switching Protocols\r\n"
                    "Upgrade: websocket\r\n"
                    "Connection: Upgrade\r\n"
                    f"Sec-WebSocket-Accept: {accept}\r\n\r\n"
                ).encode("ascii")
            )
            while True:
                text = receive_text_frame(self.connection)
                if text is None:
                    return
                message = json.loads(text)
                method = message.get("method")
                self.methods.append(method)
                if "id" not in message:
                    continue
                result = self._result(method, message.get("params", {}))
                send_json(self.connection, {"id": message["id"], "result": result})
        except (EOFError, OSError):
            return
        except BaseException as error:
            self.error = error

    def _result(self, method, params):
        if method == "initialize":
            assert params == {
                "clientName": "quillcode-environment",
                "resumeSessionId": None,
            }, params
            return {"sessionId": "environment-smoke-session"}
        if method == "environment/info":
            return {
                "shell": {"name": "zsh", "path": "/bin/zsh"},
                "cwd": "file:///workspace",
            }
        if method == "fs/canonicalize":
            return {"path": params["path"]}
        if method == "process/start":
            self.process_starts.append(params)
            self.process_reads[params["processId"]] = 0
            return {"processId": params["processId"]}
        if method == "process/read":
            process_id = params["processId"]
            read_index = self.process_reads[process_id]
            self.process_reads[process_id] += 1
            if read_index == 0:
                assert params["afterSeq"] is None, params
                return {
                    "chunks": [{
                        "seq": 1,
                        "stream": "stdout",
                        "chunk": base64.b64encode(b"remote-shell\n").decode("ascii"),
                    }],
                    "nextSeq": 2,
                    "exited": False,
                    "closed": False,
                }
            if read_index == 1:
                assert params["afterSeq"] == 1, params
                return {
                    "chunks": [],
                    "nextSeq": 3,
                    "exited": True,
                    "exitCode": 0,
                    "closed": False,
                    "failure": None,
                    "sandboxDenied": False,
                }
            if read_index == 2:
                assert params["afterSeq"] == 2, params
                return {
                    "chunks": [{
                        "seq": 3,
                        "stream": "stdout",
                        "chunk": base64.b64encode(b"late-output\n").decode("ascii"),
                    }],
                    "nextSeq": 4,
                    "exited": True,
                    "exitCode": 0,
                    "closed": False,
                    "failure": None,
                    "sandboxDenied": False,
                }
            assert read_index == 3, read_index
            assert params["afterSeq"] == 3, params
            return {
                "chunks": [],
                "nextSeq": 5,
                "exited": True,
                "exitCode": 0,
                "closed": True,
                "failure": None,
                "sandboxDenied": False,
            }
        if method == "process/terminate":
            return {}
        raise AssertionError(f"unexpected exec-server method: {method}")


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
        "method": "thread/start",
        "params": {
            "cwd": workspace,
            "model": "trustedrouter/fast",
            "sandbox": "read-only",
            "environments": [{"environmentId": "remote", "cwd": "/workspace"}],
        },
    })
    thread_id = response(4)["result"]["thread"]["id"]
    local_sentinel = os.path.join(workspace, "must-not-run-locally")
    remote_command = f"touch {local_sentinel}; printf remote-shell"
    send({
        "id": 5,
        "method": "thread/shellCommand",
        "params": {"threadId": thread_id, "command": remote_command},
    })
    assert response(5)["result"] == {}
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

    send({
        "id": 6,
        "method": "thread/start",
        "params": {
            "cwd": workspace,
            "model": "trustedrouter/fast",
            "sandbox": "read-only",
            "environments": [],
        },
    })
    disabled_thread_id = response(6)["result"]["thread"]["id"]
    disabled_sentinel = os.path.join(workspace, "disabled-must-not-run")
    send({
        "id": 7,
        "method": "thread/shellCommand",
        "params": {
            "threadId": disabled_thread_id,
            "command": f"touch {disabled_sentinel}",
        },
    })
    disabled = response(7)
    assert disabled["error"]["code"] == -32600, disabled
    assert disabled["error"]["message"] == (
        "environment access is disabled for this thread"
    ), disabled
    assert not os.path.exists(disabled_sentinel), "disabled command ran locally"
    assert len(server.process_starts) == 1, server.process_starts

    send({
        "id": 8,
        "method": "thread/start",
        "params": {
            "cwd": workspace,
            "model": "trustedrouter/fast",
            "sandbox": "read-only",
            "environments": [{"environmentId": "missing", "cwd": "/workspace"}],
        },
    })
    missing = response(8)
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

assert server.methods[:3] == ["initialize", "initialized", "environment/info"], (
    server.methods
)
assert server.methods.count("environment/info") >= 2, server.methods
PY

echo "app-server environment smoke passed"
