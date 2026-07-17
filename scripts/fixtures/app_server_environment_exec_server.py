#!/usr/bin/env python3
"""Minimal WebSocket exec-server fixture for the environment app-server smoke."""

import base64
import hashlib
import json
import socket
import struct
import threading
import time


READ_ONLY_SANDBOX = {
    "permissions": {
        "type": "managed",
        "file_system": {
            "type": "restricted",
            "entries": [{
                "path": {
                    "type": "special",
                    "value": {"kind": "root"},
                },
                "access": "read",
            }],
        },
        "network": "restricted",
    },
    "cwd": "file:///workspace",
    "workspaceRoots": ["file:///workspace"],
    "windowsSandboxLevel": "disabled",
    "windowsSandboxPrivateDesktop": False,
    "useLegacyLandlock": False,
}


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
        self.listener.listen(2)
        self.listener.settimeout(0.2)
        self.port = self.listener.getsockname()[1]
        self.connection = None
        self.connection_condition = threading.Condition()
        self.stopping = False
        self.error = None
        self.methods = []
        self.session_id = None
        self.initialize_count = 0
        self.process_starts = []
        self.process_reads = {}
        self.file_system_requests = []
        self.thread = threading.Thread(target=self._run, daemon=True)

    def start(self):
        self.thread.start()

    def close(self):
        with self.connection_condition:
            self.stopping = True
            connection = self.connection
        if connection is not None:
            try:
                connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            connection.close()
        self.listener.close()
        self.thread.join(timeout=5)
        if self.thread.is_alive():
            raise AssertionError("exec-server fixture did not stop")
        if self.error is not None:
            raise self.error

    def disconnect_client(self):
        with self.connection_condition:
            connection = self.connection
        if connection is None:
            raise AssertionError("exec-server fixture has no client to disconnect")

        try:
            send_frame(connection, 8, b"")
        except OSError:
            pass

        if self._wait_for_connection_change(connection, timeout=5):
            return

        try:
            connection.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        connection.close()
        if not self._wait_for_connection_change(connection, timeout=15):
            raise AssertionError("exec-server fixture did not observe client disconnect")

    def _wait_for_connection_change(self, connection, timeout):
        deadline = time.monotonic() + timeout
        with self.connection_condition:
            while self.connection is connection and time.monotonic() < deadline:
                self.connection_condition.wait(deadline - time.monotonic())
            return self.connection is not connection

    def _run(self):
        try:
            while True:
                try:
                    connection, _ = self.listener.accept()
                except socket.timeout:
                    with self.connection_condition:
                        if self.stopping:
                            return
                    continue
                except OSError:
                    return
                with self.connection_condition:
                    if self.stopping:
                        connection.close()
                        return
                    self.connection = connection
                    self.connection_condition.notify_all()
                try:
                    self._serve(connection)
                except (EOFError, OSError):
                    pass
                finally:
                    connection.close()
                    with self.connection_condition:
                        if self.connection is connection:
                            self.connection = None
                        self.connection_condition.notify_all()
        except BaseException as error:
            self.error = error

    def _serve(self, connection):
        connection.settimeout(15)
        request = receive_http_request(connection).decode("latin-1")
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
        connection.sendall(
            (
                "HTTP/1.1 101 Switching Protocols\r\n"
                "Upgrade: websocket\r\n"
                "Connection: Upgrade\r\n"
                f"Sec-WebSocket-Accept: {accept}\r\n\r\n"
            ).encode("ascii")
        )
        while True:
            text = receive_text_frame(connection)
            if text is None:
                return
            message = json.loads(text)
            method = message.get("method")
            self.methods.append(method)
            if "id" not in message:
                continue
            result = self._result(method, message.get("params", {}))
            send_json(connection, {"id": message["id"], "result": result})

    def _result(self, method, params):
        if method == "initialize":
            assert params == {
                "clientName": "quillcode-environment",
                "resumeSessionId": self.session_id,
            }, params
            self.initialize_count += 1
            self.session_id = f"environment-smoke-session-{self.initialize_count}"
            return {"sessionId": self.session_id}
        if method == "environment/status":
            assert params is None, params
            return {"status": "ready"}
        if method == "environment/info":
            return {
                "shell": {"name": "zsh", "path": "/bin/zsh"},
                "cwd": "file:///workspace",
            }
        if method == "fs/canonicalize":
            self._assert_read_only_sandbox(params)
            self.file_system_requests.append(params)
            return {"path": params["path"]}
        if method == "process/start":
            self._assert_read_only_sandbox(params)
            assert params["enforceManagedNetwork"] is False, params
            assert params["managedNetwork"] is None, params
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

    @staticmethod
    def _assert_read_only_sandbox(params):
        assert params["sandbox"] == READ_ONLY_SANDBOX, params
