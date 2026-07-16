#!/usr/bin/env python3
import json
import os
import sys


def read_message():
    line = sys.stdin.buffer.readline()
    if not line:
        return None
    if line.lower().startswith(b"content-length:"):
        raise RuntimeError("legacy Content-Length framing is not supported by this fixture")
    return json.loads(line)


def send(message):
    payload = json.dumps(message, separators=(",", ":")).encode("utf-8")
    sys.stdout.buffer.write(payload + b"\n")
    sys.stdout.buffer.flush()


pid_file = os.environ.get("QUILLCODE_MCP_PID_FILE")
if pid_file:
    with open(pid_file, "w", encoding="utf-8") as handle:
        handle.write(str(os.getpid()))

client_capabilities = {}

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
        client_capabilities = params.get("capabilities") or {}
        result = {
            "protocolVersion": "2025-06-18",
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
        elicitation_response = None
        if query == "elicit-form":
            if client_capabilities.get("elicitation") != {}:
                raise RuntimeError("client did not advertise standard form elicitation")
            elicitation_request_id = "smoke-elicitation-form"
            send({
                "jsonrpc": "2.0",
                "id": elicitation_request_id,
                "method": "elicitation/create",
                "params": {
                    "mode": "form",
                    "message": "Choose a smoke-test label",
                    "requestedSchema": {
                        "type": "object",
                        "properties": {
                            "label": {"type": "string", "title": "Label"},
                        },
                        "required": ["label"],
                    },
                    "_meta": {
                        "fixture": "stdio",
                        "progressToken": "must-not-be-forwarded",
                    },
                },
            })
            elicitation_message = read_message()
            if elicitation_message is None:
                raise RuntimeError("client closed before answering elicitation")
            if elicitation_message.get("id") != elicitation_request_id:
                raise RuntimeError("client answered elicitation with the wrong request id")
            elicitation_response = elicitation_message.get("result")
        result = {
            "content": [{"type": "text", "text": f"searched {query}"}],
            "structuredContent": {"query": query, "matches": 1},
            "isError": False,
            "_meta": {"fixture": True, "request": params.get("_meta")},
        }
        if elicitation_response is not None:
            result["structuredContent"]["elicitation"] = elicitation_response
            result["structuredContent"]["clientCapabilities"] = client_capabilities
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
