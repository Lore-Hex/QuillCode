#!/usr/bin/env python3
import json
import os
import sys


def read_message():
    content_length = None
    while True:
        line = sys.stdin.buffer.readline()
        if not line:
            return None
        if line in (b"\n", b"\r\n"):
            break
        name, value = line.decode("ascii").split(":", 1)
        if name.lower() == "content-length":
            content_length = int(value.strip())
    if content_length is None:
        raise RuntimeError("missing Content-Length")
    return json.loads(sys.stdin.buffer.read(content_length))


def send(message):
    payload = json.dumps(message, separators=(",", ":")).encode("utf-8")
    sys.stdout.buffer.write(f"Content-Length: {len(payload)}\r\n\r\n".encode("ascii"))
    sys.stdout.buffer.write(payload)
    sys.stdout.buffer.flush()


pid_file = os.environ.get("QUILLCODE_MCP_PID_FILE")
if pid_file:
    with open(pid_file, "w", encoding="utf-8") as handle:
        handle.write(str(os.getpid()))

while True:
    message = read_message()
    if message is None:
        break
    request_id = message.get("id")
    if request_id is None:
        continue
    method = message.get("method")
    params = message.get("params") or {}
    if method == "initialize":
        result = {
            "protocolVersion": "2025-03-26",
            "serverInfo": {"name": "Smoke MCP", "version": "1.0.0"},
            "capabilities": {"tools": {}, "resources": {}},
        }
    elif method == "tools/list":
        result = {"tools": [{
            "name": "search",
            "description": "Search the smoke fixture",
            "inputSchema": {
                "type": "object",
                "properties": {"query": {"type": "string"}},
                "required": ["query"],
            },
            "annotations": {"readOnlyHint": True},
        }]}
    elif method == "resources/list":
        result = {"resources": [{
            "name": "Smoke Guide",
            "uri": "smoke://guide",
            "mimeType": "text/markdown",
        }]}
    elif method == "resources/templates/list":
        result = {"resourceTemplates": [{
            "name": "Smoke record",
            "uriTemplate": "smoke://record/{id}",
        }]}
    elif method == "tools/call":
        query = (params.get("arguments") or {}).get("query", "")
        result = {
            "content": [{"type": "text", "text": f"searched {query}"}],
            "structuredContent": {"query": query, "matches": 1},
            "isError": False,
            "_meta": {"fixture": True, "request": params.get("_meta")},
        }
    elif method == "resources/read":
        result = {"contents": [{
            "uri": params.get("uri"),
            "mimeType": "text/markdown",
            "text": "# Smoke Guide",
        }]}
    else:
        send({
            "jsonrpc": "2.0",
            "id": request_id,
            "error": {"code": -32601, "message": f"unknown method: {method}"},
        })
        continue
    send({"jsonrpc": "2.0", "id": request_id, "result": result})
