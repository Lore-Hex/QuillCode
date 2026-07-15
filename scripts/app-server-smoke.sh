#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SMOKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/quillcode-app-server-smoke.XXXXXX")"
trap 'rm -rf "$SMOKE_ROOT"' EXIT

mkdir -p "$SMOKE_ROOT/home" "$SMOKE_ROOT/workspace"
cd "$ROOT_DIR"
swift build --product quill-code >/dev/null

python3 - "$ROOT_DIR/.build/debug/quill-code" "$SMOKE_ROOT/home" "$SMOKE_ROOT/workspace" <<'PY'
import json
import base64
import os
import subprocess
import sys

binary, home, workspace = sys.argv[1:]
skill_directory = os.path.join(workspace, ".agents", "skills", "smoke-review")
os.makedirs(skill_directory, exist_ok=True)
skill_manifest = os.path.join(skill_directory, "SKILL.md")
with open(skill_manifest, "w", encoding="utf-8") as manifest:
    manifest.write("""---
name: smoke-review
description: Review the smoke-test workspace.
---

# Smoke review
""")
extra_skill_root = os.path.join(home, "extra-skills")
os.makedirs(os.path.join(extra_skill_root, "smoke-advisor"), exist_ok=True)
with open(
    os.path.join(extra_skill_root, "smoke-advisor", "SKILL.md"),
    "w",
    encoding="utf-8",
) as manifest:
    manifest.write("""---
name: smoke-advisor
description: Advise the app-server smoke test.
---
""")
marketplace_directory = os.path.join(workspace, ".agents", "plugins")
catalog_plugin_root = os.path.join(workspace, "catalog", "smoke-tools")
installed_plugin_root = os.path.join(workspace, ".quillcode", "plugins", "smoke-tools")
for directory in [marketplace_directory, catalog_plugin_root, installed_plugin_root]:
    target = os.path.join(directory, ".codex-plugin") \
        if directory != marketplace_directory else directory
    os.makedirs(target, exist_ok=True)
with open(
    os.path.join(marketplace_directory, "marketplace.json"),
    "w",
    encoding="utf-8",
) as manifest:
    json.dump({
        "name": "smoke-marketplace",
        "interface": {"displayName": "Smoke Marketplace"},
        "plugins": [{
            "name": "smoke-tools",
            "source": "./catalog/smoke-tools",
            "category": "Testing",
        }],
    }, manifest)
with open(
    os.path.join(catalog_plugin_root, ".codex-plugin", "plugin.json"),
    "w",
    encoding="utf-8",
) as manifest:
    json.dump({
        "name": "smoke-tools",
        "version": "1.0.0",
        "keywords": ["smoke"],
        "interface": {"displayName": "Smoke Tools"},
    }, manifest)
plugin_skill = os.path.join(catalog_plugin_root, "skills", "smoke-plugin-skill")
os.makedirs(plugin_skill, exist_ok=True)
with open(os.path.join(plugin_skill, "SKILL.md"), "w", encoding="utf-8") as manifest:
    manifest.write("""---
name: smoke-plugin-skill
description: Exercise plugin detail discovery.
---
""")
os.makedirs(os.path.join(catalog_plugin_root, "hooks"), exist_ok=True)
with open(
    os.path.join(catalog_plugin_root, "hooks", "hooks.json"),
    "w",
    encoding="utf-8",
) as manifest:
    json.dump({
        "hooks": {"PreToolUse": [{"hooks": [{"type": "command"}]}]},
    }, manifest)
with open(
    os.path.join(catalog_plugin_root, ".app.json"),
    "w",
    encoding="utf-8",
) as manifest:
    json.dump({"apps": {"smoke-app": {"id": "smoke-app"}}}, manifest)
with open(
    os.path.join(catalog_plugin_root, ".mcp.json"),
    "w",
    encoding="utf-8",
) as manifest:
    json.dump({"mcpServers": {"smoke-mcp": {"command": "smoke-mcp"}}}, manifest)
with open(
    os.path.join(installed_plugin_root, ".codex-plugin", "plugin.json"),
    "w",
    encoding="utf-8",
) as manifest:
    json.dump({"name": "smoke-tools", "version": "2.0.0"}, manifest)
mcp_fixture = os.path.join(home, "mcp-fixture.py")
with open(mcp_fixture, "w", encoding="utf-8") as fixture:
    fixture.write(r'''import json
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
    payload = sys.stdin.buffer.read(content_length)
    return json.loads(payload)

def send(message):
    payload = json.dumps(message, separators=(",", ":")).encode("utf-8")
    sys.stdout.buffer.write(f"Content-Length: {len(payload)}\r\n\r\n".encode("ascii"))
    sys.stdout.buffer.write(payload)
    sys.stdout.buffer.flush()

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
''')
with open(os.path.join(home, "config.toml"), "w", encoding="utf-8") as config_file:
    config_file.write(
        "[mcp_servers.smoke-mcp]\n"
        f"command = {json.dumps(sys.executable)}\n"
        f"args = [{json.dumps(mcp_fixture)}]\n"
        "startup_timeout_sec = 5\n"
        "tool_timeout_sec = 5\n"
    )
process = subprocess.Popen(
    [binary, "--home", home, "app-server", "--mock"],
    cwd=workspace,
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    bufsize=1,
)

def send(message):
    process.stdin.write(json.dumps(message, separators=(",", ":")) + "\n")
    process.stdin.flush()

def read_until(predicate, limit=200):
    records = []
    for _ in range(limit):
        line = process.stdout.readline()
        if not line:
            stderr = process.stderr.read()
            raise AssertionError(f"app-server closed early: {stderr}")
        record = json.loads(line)
        records.append(record)
        if predicate(record):
            return record, records
    raise AssertionError("app-server did not emit the expected record")

send({"id": 1, "method": "initialize", "params": {
    "clientInfo": {"name": "quillcode-smoke", "version": "1"}
}})
initialized, _ = read_until(lambda record: record.get("id") == 1)
assert "result" in initialized and "jsonrpc" not in initialized, initialized
send({"method": "initialized", "params": {}})

send({"id": 2, "method": "model/list", "params": {"limit": 2}})
models, _ = read_until(lambda record: record.get("id") == 2)
assert len(models["result"]["data"]) == 2, models
assert models["result"]["data"][0]["isDefault"] is True, models
assert models["result"]["nextCursor"], models

send({"id": 3, "method": "account/read", "params": {}})
account, _ = read_until(lambda record: record.get("id") == 3)
assert account["result"] == {"account": None, "requiresOpenaiAuth": False}, account

send({"id": 4, "method": "config/read", "params": {"cwd": workspace}})
config, _ = read_until(lambda record: record.get("id") == 4)
assert config["result"]["config"]["model"] == "trustedrouter/fast", config
assert config["result"]["config"]["model_provider"] == "trustedrouter", config
assert "layers" not in config["result"], config

send({"id": 40, "method": "config/value/write", "params": {
    "keyPath": "desktop.appearanceTheme",
    "value": "dark",
    "mergeStrategy": "replace",
}})
config_write, _ = read_until(lambda record: record.get("id") == 40)
assert config_write["result"]["status"] == "ok", config_write
config_version = config_write["result"]["version"]
assert config_version.startswith("sha256:"), config_write

send({"id": 41, "method": "config/batchWrite", "params": {
    "edits": [{
        "keyPath": "desktop.workspace",
        "value": {"collapsed": True, "width": 320},
        "mergeStrategy": "upsert",
    }],
    "expectedVersion": config_version,
    "reloadUserConfig": True,
}})
config_batch, _ = read_until(lambda record: record.get("id") == 41)
assert config_batch["result"]["status"] == "ok", config_batch

send({"id": 42, "method": "config/read", "params": {
    "cwd": workspace,
    "includeLayers": True,
}})
config, _ = read_until(lambda record: record.get("id") == 42)
assert config["result"]["config"]["desktop"] == {
    "appearanceTheme": "dark",
    "workspace": {"collapsed": True, "width": 320},
}, config
assert config["result"]["origins"]["desktop.workspace.width"]["version"] \
    == config_batch["result"]["version"], config
assert config["result"]["layers"][0]["config"]["desktop"]["appearanceTheme"] == "dark", config

send({"id": 43, "method": "plugin/list", "params": {"cwds": [workspace]}})
plugin_list, _ = read_until(lambda record: record.get("id") == 43)
assert plugin_list["result"]["featuredPluginIds"] == [], plugin_list
assert plugin_list["result"]["marketplaceLoadErrors"] == [], plugin_list
marketplace = plugin_list["result"]["marketplaces"][0]
assert marketplace["name"] == "smoke-marketplace", plugin_list
assert marketplace["interface"] == {"displayName": "Smoke Marketplace"}, plugin_list
plugin = marketplace["plugins"][0]
assert plugin["id"] == "smoke-tools@smoke-marketplace", plugin_list
assert plugin["installed"] is True and plugin["enabled"] is True, plugin_list
assert plugin["localVersion"] == "2.0.0", plugin_list
assert plugin["interface"]["category"] == "Testing", plugin_list
assert plugin["keywords"] == ["smoke"], plugin_list

send({"id": 44, "method": "plugin/installed", "params": {"cwds": [workspace]}})
plugin_installed, _ = read_until(lambda record: record.get("id") == 44)
assert "featuredPluginIds" not in plugin_installed["result"], plugin_installed
assert [
    item["name"]
    for entry in plugin_installed["result"]["marketplaces"]
    for item in entry["plugins"]
] == ["smoke-tools"], plugin_installed

send({"id": 45, "method": "plugin/read", "params": {
    "marketplacePath": os.path.join(marketplace_directory, "marketplace.json"),
    "pluginName": "smoke-tools",
}})
plugin_read, _ = read_until(lambda record: record.get("id") == 45)
detail = plugin_read["result"]["plugin"]
assert detail["marketplaceName"] == "smoke-marketplace", plugin_read
assert detail["summary"]["installed"] is True, plugin_read
assert [skill["name"] for skill in detail["skills"]] == [
    "smoke-tools:smoke-plugin-skill"
], plugin_read
assert detail["hooks"] == [{
    "key": "smoke-tools@smoke-marketplace:hooks/hooks.json:pre_tool_use:0:0",
    "eventName": "preToolUse",
}], plugin_read
assert [app["id"] for app in detail["apps"]] == ["smoke-app"], plugin_read
assert detail["mcpServers"] == ["smoke-mcp"], plugin_read

send({"id": 46, "method": "plugin/skill/read", "params": {
    "remoteMarketplaceName": "remote",
    "remotePluginId": "smoke-plugin",
    "skillName": "smoke-skill",
}})
remote_skill_read, _ = read_until(lambda record: record.get("id") == 46)
assert remote_skill_read["error"]["code"] == -32600, remote_skill_read
assert "remote plugin skill read is not available" in remote_skill_read["error"]["message"], \
    remote_skill_read

send({"id": 5, "method": "skills/list", "params": {"cwds": [workspace]}})
skills, _ = read_until(lambda record: record.get("id") == 5)
skill = skills["result"]["data"][0]["skills"][0]
assert skill["name"] == "smoke-review", skills
assert skill["scope"] == "repo", skills
assert skill["enabled"] is True, skills

send({"id": 50, "method": "skills/config/write", "params": {
    "path": skill_manifest,
    "enabled": False,
}})
disabled, records = read_until(lambda record: record.get("id") == 50)
assert disabled["result"] == {"effectiveEnabled": False}, disabled
assert any(record.get("method") == "skills/changed" for record in records), records

send({"id": 51, "method": "skills/list", "params": {"cwds": [workspace]}})
skills, _ = read_until(lambda record: record.get("id") == 51)
review_skill = next(
    skill for skill in skills["result"]["data"][0]["skills"]
    if skill["name"] == "smoke-review"
)
assert review_skill["enabled"] is False, skills

send({"id": 52, "method": "skills/config/write", "params": {
    "path": skill_manifest,
    "enabled": True,
}})
enabled, records = read_until(lambda record: record.get("id") == 52)
assert enabled["result"] == {"effectiveEnabled": True}, enabled
assert any(record.get("method") == "skills/changed" for record in records), records

with open(skill_manifest, "w", encoding="utf-8") as manifest:
    manifest.write("""---
name: smoke-review
description: Updated by the app-server watcher smoke.
---
""")
changed, _ = read_until(lambda record: record.get("method") == "skills/changed")
assert changed["params"] == {}, changed

send({"id": 53, "method": "skills/list", "params": {"cwds": [workspace]}})
skills, _ = read_until(lambda record: record.get("id") == 53)
review_skill = next(
    skill for skill in skills["result"]["data"][0]["skills"]
    if skill["name"] == "smoke-review"
)
assert review_skill["enabled"] is True, skills
assert review_skill["description"] == "Updated by the app-server watcher smoke.", skills

send({"id": 6, "method": "skills/extraRoots/set", "params": {
    "extraRoots": [extra_skill_root],
}})
extra_roots, records = read_until(lambda record: record.get("id") == 6)
assert extra_roots["result"] == {}, extra_roots
assert any(record.get("method") == "skills/changed" for record in records), records

send({"id": 7, "method": "skills/list", "params": {"forceReload": True}})
skills, _ = read_until(lambda record: record.get("id") == 7)
skill_names = {skill["name"] for skill in skills["result"]["data"][0]["skills"]}
assert skill_names == {"smoke-review", "smoke-advisor"}, skills

fs_root = os.path.join(workspace, "app-server-fs")
nested = os.path.join(fs_root, "nested")
source_file = os.path.join(nested, "blob.bin")
copy_file = os.path.join(fs_root, "blob-copy.bin")
payload = bytes([0, 1, 2, 255])

send({"id": 80, "method": "fs/createDirectory", "params": {"path": nested}})
created, _ = read_until(lambda record: record.get("id") == 80)
assert created["result"] == {}, created

send({"id": 81, "method": "fs/writeFile", "params": {
    "path": source_file,
    "dataBase64": base64.b64encode(payload).decode("ascii"),
}})
written, _ = read_until(lambda record: record.get("id") == 81)
assert written["result"] == {}, written

send({"id": 82, "method": "fs/readFile", "params": {"path": source_file}})
read_file, _ = read_until(lambda record: record.get("id") == 82)
assert base64.b64decode(read_file["result"]["dataBase64"]) == payload, read_file

send({"id": 83, "method": "fs/getMetadata", "params": {"path": source_file}})
metadata, _ = read_until(lambda record: record.get("id") == 83)
assert set(metadata["result"]) == {
    "isDirectory", "isFile", "isSymlink", "createdAtMs", "modifiedAtMs",
}, metadata
assert metadata["result"]["isFile"] is True, metadata

send({"id": 84, "method": "fs/readDirectory", "params": {"path": nested}})
directory, _ = read_until(lambda record: record.get("id") == 84)
assert directory["result"]["entries"] == [{
    "fileName": "blob.bin", "isDirectory": False, "isFile": True,
}], directory

send({"id": 85, "method": "fs/copy", "params": {
    "sourcePath": source_file,
    "destinationPath": copy_file,
}})
copied, _ = read_until(lambda record: record.get("id") == 85)
assert copied["result"] == {}, copied
with open(copy_file, "rb") as copied_stream:
    assert copied_stream.read() == payload, copied

send({"id": 86, "method": "fs/watch", "params": {
    "watchId": "smoke-copy", "path": copy_file,
}})
watched, _ = read_until(lambda record: record.get("id") == 86)
assert set(watched["result"]) == {"path"}, watched
assert os.path.samefile(watched["result"]["path"], copy_file), watched
send({"id": 87, "method": "fs/unwatch", "params": {"watchId": "smoke-copy"}})
unwatched, _ = read_until(lambda record: record.get("id") == 87)
assert unwatched["result"] == {}, unwatched

send({"id": 88, "method": "fs/remove", "params": {"path": copy_file}})
removed, _ = read_until(lambda record: record.get("id") == 88)
assert removed["result"] == {} and not os.path.exists(copy_file), removed

send({"id": 8, "method": "thread/start", "params": {
    "cwd": workspace,
    "model": "trustedrouter/fast",
    "sandbox": "workspace-write",
}})
started, _ = read_until(lambda record: record.get("id") == 8)
thread_id = started["result"]["thread"]["id"]

send({"id": 60, "method": "mcpServerStatus/list", "params": {
    "threadId": thread_id,
    "detail": "full",
}})
mcp_status, _ = read_until(lambda record: record.get("id") == 60)
mcp_server = mcp_status["result"]["data"][0]
assert mcp_server["name"] == "smoke-mcp", mcp_status
assert mcp_server["serverInfo"] == {"name": "Smoke MCP", "version": "1.0.0"}, mcp_status
assert mcp_server["tools"]["search"]["annotations"]["readOnlyHint"] is True, mcp_status
assert mcp_server["resources"][0]["uri"] == "smoke://guide", mcp_status
assert mcp_server["resourceTemplates"][0]["uriTemplate"] == "smoke://record/{id}", mcp_status

send({"id": 61, "method": "mcpServer/tool/call", "params": {
    "threadId": thread_id,
    "server": "smoke-mcp",
    "tool": "search",
    "arguments": {"query": "swift"},
    "_meta": {"requestID": "smoke-request"},
}})
mcp_call, _ = read_until(lambda record: record.get("id") == 61)
assert mcp_call["result"]["content"][0]["text"] == "searched swift", mcp_call
assert mcp_call["result"]["structuredContent"] == {"query": "swift", "matches": 1}, mcp_call
assert mcp_call["result"]["isError"] is False, mcp_call
assert mcp_call["result"]["_meta"]["request"] == {"requestID": "smoke-request"}, mcp_call

send({"id": 62, "method": "mcpServer/resource/read", "params": {
    "threadId": thread_id,
    "server": "smoke-mcp",
    "uri": "smoke://guide",
}})
mcp_resource, _ = read_until(lambda record: record.get("id") == 62)
assert mcp_resource["result"]["contents"][0]["text"] == "# Smoke Guide", mcp_resource

send({"id": 63, "method": "config/mcpServer/reload", "params": {}})
mcp_reload, _ = read_until(lambda record: record.get("id") == 63)
assert mcp_reload["result"] == {}, mcp_reload
send({"id": 64, "method": "mcpServerStatus/list", "params": {
    "threadId": thread_id,
    "detail": "toolsAndAuthOnly",
}})
mcp_fast_status, _ = read_until(lambda record: record.get("id") == 64)
mcp_fast_server = mcp_fast_status["result"]["data"][0]
assert set(mcp_fast_server["tools"]) == {"search"}, mcp_fast_status
assert mcp_fast_server["resources"] == [], mcp_fast_status
assert mcp_fast_server["resourceTemplates"] == [], mcp_fast_status

send({"id": 9, "method": "turn/start", "params": {
    "threadId": thread_id,
    "input": [{"type": "text", "text": "app-server smoke"}],
}})
turn_response, records = read_until(lambda record: record.get("id") == 9)
assert turn_response["result"]["turn"]["status"] == "inProgress", turn_response
completed, tail = read_until(lambda record: record.get("method") == "turn/completed")
records.extend(tail)
assert completed["params"]["turn"]["status"] == "completed", completed
methods = {record.get("method") for record in records}
assert "turn/started" in methods, methods
assert "item/started" in methods, methods
assert "item/completed" in methods, methods

process.stdin.close()
status = process.wait(timeout=10)
stderr = process.stderr.read()
assert status == 0, (status, stderr)
PY

echo "quill-code app-server smoke passed"
