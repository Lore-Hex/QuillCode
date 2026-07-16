#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SMOKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/quillcode-app-server-smoke.XXXXXX")"
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
  "$ROOT_DIR/scripts/fixtures/mcp-stdio-server.py" <<'PY'
import json
import base64
import os
import subprocess
import sys

binary, home, workspace, mcp_fixture = sys.argv[1:]
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
with open(os.path.join(workspace, "alpha-search.txt"), "w", encoding="utf-8") as file:
    file.write("fuzzy search smoke\n")
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
    "clientInfo": {"name": "quillcode-smoke", "version": "1"},
    "capabilities": {
        "experimentalApi": True,
        "mcpServerOpenaiFormElicitation": True,
    },
}})
initialized, _ = read_until(lambda record: record.get("id") == 1)
assert "result" in initialized and "jsonrpc" not in initialized, initialized
send({"method": "initialized", "params": {}})

send({"id": 206, "method": "permissionProfile/list", "params": {}})
profiles, _ = read_until(lambda record: record.get("id") == 206)
assert profiles["result"] == {
    "data": [
        {"id": ":read-only", "description": None, "allowed": True},
        {"id": ":workspace", "description": None, "allowed": True},
        {"id": ":danger-full-access", "description": None, "allowed": True},
    ],
    "nextCursor": None,
}, profiles

send({"id": 207, "method": "collaborationMode/list", "params": {}})
collaboration_modes, _ = read_until(lambda record: record.get("id") == 207)
assert collaboration_modes["result"] == {
    "data": [
        {
            "name": "Plan",
            "mode": "plan",
            "model": None,
            "reasoning_effort": "medium",
        },
        {
            "name": "Default",
            "mode": "default",
            "model": None,
            "reasoning_effort": None,
        },
    ],
}, collaboration_modes

send({"id": 208, "method": "configRequirements/read", "params": {}})
config_requirements, _ = read_until(lambda record: record.get("id") == 208)
assert config_requirements["result"] == {"requirements": None}, config_requirements

send({"id": 2, "method": "model/list", "params": {"limit": 2}})
models, _ = read_until(lambda record: record.get("id") == 2)
assert len(models["result"]["data"]) == 2, models
assert models["result"]["data"][0]["isDefault"] is True, models
assert models["result"]["nextCursor"], models

send({"id": 200, "method": "fuzzyFileSearch", "params": {
    "query": "alps",
    "roots": [workspace],
}})
search, _ = read_until(lambda record: record.get("id") == 200)
assert search["result"]["files"][0]["path"] == "alpha-search.txt", search
assert search["result"]["files"][0]["match_type"] == "file", search
assert search["result"]["files"][0]["indices"] == [0, 1, 2, 6], search

send({"id": 202, "method": "fuzzyFileSearch/sessionStart", "params": {
    "sessionId": "smoke-search",
    "roots": [workspace],
}})
search_start, _ = read_until(lambda record: record.get("id") == 202)
assert search_start["result"] == {}, search_start
send({"id": 203, "method": "fuzzyFileSearch/sessionUpdate", "params": {
    "sessionId": "smoke-search",
    "query": "ALPS",
}})
search_complete, search_records = read_until(
    lambda record: record.get("method") == "fuzzyFileSearch/sessionCompleted"
)
search_update = next(
    record for record in search_records
    if record.get("method") == "fuzzyFileSearch/sessionUpdated"
)
assert search_update["params"]["sessionId"] == "smoke-search", search_update
assert search_update["params"]["query"] == "ALPS", search_update
assert search_update["params"]["files"][0]["path"] == "alpha-search.txt", search_update
assert search_complete["params"] == {"sessionId": "smoke-search"}, search_complete

send({"id": 201, "method": "process/spawn", "params": {
    "command": ["/bin/sh", "-c", "printf process-smoke"],
    "cwd": workspace,
    "processHandle": "smoke-process",
}})
process_exit, process_records = read_until(
    lambda record: record.get("method") == "process/exited"
)
assert process_records[0] == {"id": 201, "result": {}}, process_records
assert process_exit["params"] == {
    "exitCode": 0,
    "processHandle": "smoke-process",
    "stderr": "",
    "stderrCapReached": False,
    "stdout": "process-smoke",
    "stdoutCapReached": False,
}, process_exit

command_payload = b"command-exec-smoke\n"
send({"id": 204, "method": "command/exec", "params": {
    "command": ["/bin/cat"],
    "processId": "smoke-command-exec",
    "streamStdin": True,
    "streamStdoutStderr": True,
    "disableTimeout": True,
    "permissionProfile": ":danger-full-access",
}})
send({"id": 205, "method": "command/exec/write", "params": {
    "processId": "smoke-command-exec",
    "deltaBase64": base64.b64encode(command_payload).decode("ascii"),
    "closeStdin": True,
}})
command_response, command_records = read_until(lambda record: record.get("id") == 204)
write_index = next(index for index, record in enumerate(command_records) if record.get("id") == 205)
response_index = len(command_records) - 1
command_deltas = [
    record for record in command_records
    if record.get("method") == "command/exec/outputDelta"
]
assert command_records[write_index] == {"id": 205, "result": {}}, command_records
assert write_index < response_index, command_records
assert command_deltas, command_records
assert all(command_records.index(record) < response_index for record in command_deltas), command_records
assert all(record["params"]["processId"] == "smoke-command-exec" for record in command_deltas)
assert all(record["params"]["stream"] == "stdout" for record in command_deltas)
assert all(record["params"]["capReached"] is False for record in command_deltas)
streamed_command_output = b"".join(
    base64.b64decode(record["params"]["deltaBase64"])
    for record in command_deltas
)
assert streamed_command_output == command_payload, command_records
assert command_response == {
    "id": 204,
    "result": {"exitCode": 0, "stdout": "", "stderr": ""},
}, command_response

send({"id": 3, "method": "account/read", "params": {}})
account, _ = read_until(lambda record: record.get("id") == 3)
assert account["result"] == {"account": None, "requiresOpenaiAuth": False}, account

account_secret = "sk-tr-v1-app-server-smoke"
send({"id": 30, "method": "account/login/start", "params": {
    "type": "apiKey",
    "apiKey": account_secret,
}})
account_updated, login_records = read_until(
    lambda record: record.get("method") == "account/updated"
)
assert [record.get("id") for record in login_records] == [30, None, None], login_records
assert login_records[0]["result"] == {"type": "apiKey"}, login_records
assert login_records[1]["method"] == "account/login/completed", login_records
assert login_records[1]["params"] == {
    "loginId": None,
    "success": True,
    "error": None,
}, login_records
assert account_updated["params"] == {"authMode": "apikey", "planType": None}, account_updated
assert account_secret not in json.dumps(login_records, sort_keys=True), login_records

send({"id": 31, "method": "account/read", "params": {}})
account, _ = read_until(lambda record: record.get("id") == 31)
assert account["result"] == {
    "account": {"type": "apiKey"},
    "requiresOpenaiAuth": False,
}, account

send({"id": 32, "method": "account/logout", "params": {}})
account_updated, logout_records = read_until(
    lambda record: record.get("method") == "account/updated"
)
assert [record.get("id") for record in logout_records] == [32, None], logout_records
assert logout_records[0]["result"] == {}, logout_records
assert account_updated["params"] == {"authMode": None, "planType": None}, account_updated

send({"id": 33, "method": "account/read", "params": {}})
account, _ = read_until(lambda record: record.get("id") == 33)
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
session_id = started["result"]["thread"]["sessionId"]
startup_ready, startup_records = read_until(
    lambda record: (
        record.get("method") == "mcpServer/startupStatus/updated"
        and record.get("params", {}).get("status") == "ready"
    )
)
startup_updates = [
    record["params"]
    for record in startup_records
    if record.get("method") == "mcpServer/startupStatus/updated"
]
assert [update["status"] for update in startup_updates] == ["starting", "ready"], (
    startup_updates
)
assert all(update["threadId"] == thread_id for update in startup_updates), startup_updates
assert all(update["name"] == "smoke-mcp" for update in startup_updates), startup_updates
assert all(update["error"] is None for update in startup_updates), startup_updates
assert all(update["failureReason"] is None for update in startup_updates), startup_updates
assert startup_ready["params"] == startup_updates[-1], startup_ready

send({"id": 801, "method": "thread/loaded/list", "params": {"limit": 0}})
loaded_threads, _ = read_until(lambda record: record.get("id") == 801)
assert loaded_threads["result"] == {
    "data": [thread_id],
    "nextCursor": None,
}, loaded_threads

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
mcp_request_meta = mcp_call["result"]["_meta"]["request"]
assert mcp_request_meta["requestID"] == "smoke-request", mcp_call
assert mcp_request_meta["progressToken"].startswith("quillcode-"), mcp_call

send({"id": 611, "method": "mcpServer/tool/call", "params": {
    "threadId": thread_id,
    "server": "smoke-mcp",
    "tool": "search",
    "arguments": {"query": "elicit-form"},
}})
elicitation, _ = read_until(
    lambda record: record.get("method") == "mcpServer/elicitation/request"
)
elicitation_id = elicitation["id"]
assert isinstance(elicitation_id, str), elicitation
assert elicitation["params"] == {
    "threadId": thread_id,
    "turnId": None,
    "serverName": "smoke-mcp",
    "mode": "form",
    "message": "Choose a smoke-test label",
    "requestedSchema": {
        "type": "object",
        "properties": {
            "label": {"type": "string", "title": "Label"},
        },
        "required": ["label"],
    },
    "_meta": {"fixture": "stdio"},
}, elicitation
send({
    "id": elicitation_id,
    "result": {
        "action": "accept",
        "content": {"label": "real-stdio-roundtrip"},
        "_meta": {"receipt": "smoke-accepted"},
    },
})
resolved, _ = read_until(
    lambda record: (
        record.get("method") == "serverRequest/resolved"
        and record.get("params", {}).get("requestId") == elicitation_id
    )
)
assert resolved["params"] == {
    "threadId": thread_id,
    "requestId": elicitation_id,
}, resolved
mcp_elicitation_call, _ = read_until(lambda record: record.get("id") == 611)
assert "result" in mcp_elicitation_call, mcp_elicitation_call
elicitation_result = mcp_elicitation_call["result"]["structuredContent"]
assert elicitation_result["elicitation"] == {
    "action": "accept",
    "content": {"label": "real-stdio-roundtrip"},
    "_meta": {"receipt": "smoke-accepted"},
}, mcp_elicitation_call
assert elicitation_result["clientCapabilities"] == {
    "elicitation": {},
    "extensions": {"openai/form": {}},
}, mcp_elicitation_call

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

image_bytes = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
)
image_data_url = "data:image/png;base64," + base64.b64encode(image_bytes).decode("ascii")
send({"id": 9, "method": "turn/start", "params": {
    "threadId": thread_id,
    "input": [
        {"type": "text", "text": "app-server smoke"},
        {"type": "image", "url": image_data_url, "detail": "high"},
        {"type": "skill", "name": "smoke-review", "path": skill_manifest},
        {"type": "mention", "name": "Smoke App", "path": "app://smoke-app"},
    ],
}})
turn_response, records = read_until(lambda record: record.get("id") == 9)
assert turn_response["result"]["turn"]["status"] == "inProgress", turn_response
completed, tail = read_until(lambda record: record.get("method") == "turn/completed")
records.extend(tail)
assert completed["params"]["turn"]["status"] == "completed", completed
idle, tail = read_until(
    lambda record: (
        record.get("method") == "thread/status/changed"
        and record.get("params", {}).get("threadId") == thread_id
        and record.get("params", {}).get("status", {}).get("type") == "idle"
    )
)
records.extend(tail)
assert idle["params"]["threadId"] == thread_id, idle
methods = {record.get("method") for record in records}
assert "turn/started" in methods, methods
assert "item/started" in methods, methods
assert "item/completed" in methods, methods
user_item = next(
    item
    for item in completed["params"]["turn"]["items"]
    if item["type"] == "userMessage"
)
assert [item["type"] for item in user_item["content"]] == [
    "text",
    "localImage",
    "skill",
    "mention",
], user_item
managed_image = next(item for item in user_item["content"] if item["type"] == "localImage")
assert managed_image["detail"] == "high", managed_image
managed_path = os.path.realpath(managed_image["path"])
attachment_root = os.path.realpath(os.path.join(home, "attachments"))
assert os.path.commonpath([managed_path, attachment_root]) == attachment_root, managed_image
with open(managed_image["path"], "rb") as image_stream:
    assert image_stream.read() == image_bytes, managed_image
skill_item = next(item for item in user_item["content"] if item["type"] == "skill")
assert skill_item["type"] == "skill", skill_item
assert skill_item["name"] == "smoke-review", skill_item
assert os.path.samefile(skill_item["path"], skill_manifest), skill_item
mention_item = next(item for item in user_item["content"] if item["type"] == "mention")
assert mention_item == {
    "type": "mention",
    "name": "Smoke App",
    "path": "app://smoke-app",
}, mention_item
found_skill_snapshot = False
for thread_name in os.listdir(os.path.join(home, "threads")):
    with open(os.path.join(home, "threads", thread_name), "r", encoding="utf-8") as thread_file:
        thread_contents = thread_file.read()
        assert image_data_url not in thread_contents, thread_name
        found_skill_snapshot = found_skill_snapshot or (
            '"inputReferences"' in thread_contents
            and "Updated by the app-server watcher smoke." in thread_contents
        )
assert found_skill_snapshot, "selected skill context was not persisted with the turn"

send({"id": 901, "method": "thread/search", "params": {
    "searchTerm": "APP-SERVER SMOKE",
}})
thread_search, _ = read_until(lambda record: record.get("id") == 901)
assert thread_search["result"]["nextCursor"] is None, thread_search
assert thread_search["result"]["backwardsCursor"], thread_search
assert thread_search["result"]["data"][0]["thread"]["id"] == thread_id, thread_search
assert thread_search["result"]["data"][0]["snippet"] == "app-server smoke", thread_search

send({"id": 902, "method": "thread/turns/list", "params": {
    "threadId": thread_id,
}})
turn_summary, _ = read_until(lambda record: record.get("id") == 902)
summary_turns = turn_summary["result"]["data"]
assert len(summary_turns) == 1, turn_summary
assert summary_turns[0]["itemsView"] == "summary", turn_summary
assert [item["type"] for item in summary_turns[0]["items"]] == [
    "userMessage", "agentMessage",
], turn_summary

send({"id": 903, "method": "thread/turns/list", "params": {
    "threadId": thread_id,
    "itemsView": "full",
}})
turn_full, _ = read_until(lambda record: record.get("id") == 903)
full_turn = turn_full["result"]["data"][0]
assert full_turn["id"] == turn_response["result"]["turn"]["id"], turn_full
assert full_turn["itemsView"] == "full", turn_full
assert [item["type"] for item in full_turn["items"]] == [
    "userMessage", "agentMessage",
], turn_full

send({"id": 904, "method": "thread/turns/list", "params": {
    "threadId": thread_id,
    "itemsView": "notLoaded",
}})
turn_not_loaded, _ = read_until(lambda record: record.get("id") == 904)
assert turn_not_loaded["result"]["data"][0]["items"] == [], turn_not_loaded
assert turn_not_loaded["result"]["data"][0]["itemsView"] == "notLoaded", (
    turn_not_loaded
)

send({"id": 905, "method": "thread/turns/items/list", "params": {
    "threadId": thread_id,
    "turnId": turn_response["result"]["turn"]["id"],
}})
turn_items_unsupported, _ = read_until(lambda record: record.get("id") == 905)
assert turn_items_unsupported["error"] == {
    "code": -32601,
    "message": "thread/turns/items/list is not supported yet",
}, turn_items_unsupported

send({"id": 65, "method": "review/start", "params": {
    "threadId": thread_id,
    "target": {"type": "uncommittedChanges"},
}})
review_response, review_records = read_until(lambda record: record.get("id") == 65)
review_turn = review_response["result"]["turn"]
assert review_response["result"]["reviewThreadId"] == thread_id, review_response
assert review_turn["status"] == "inProgress", review_response
assert review_turn["itemsView"] == "notLoaded", review_response
assert review_turn["items"][0]["id"] == review_turn["id"], review_response
review_idle, review_tail = read_until(
    lambda record: (
        record.get("method") == "thread/status/changed"
        and record.get("params", {}).get("threadId") == thread_id
        and record.get("params", {}).get("status", {}).get("type") == "idle"
    )
)
review_records.extend(review_tail)
review_completion = next(
    record for record in review_records if record.get("method") == "turn/completed"
)
assert review_completion["params"]["turn"]["status"] == "completed", review_completion
review_item_types = [
    record.get("params", {}).get("item", {}).get("type")
    for record in review_records
    if record.get("method") in {"item/started", "item/completed"}
]
assert review_item_types.count("enteredReviewMode") == 2, review_item_types
assert review_item_types.count("exitedReviewMode") == 2, review_item_types
review_agent_items = [
    item
    for item in review_completion["params"]["turn"]["items"]
    if item["type"] == "agentMessage"
]
assert len(review_agent_items) == 1, review_agent_items
assert "No actionable findings" in review_agent_items[0]["text"], review_agent_items
assert review_idle["params"]["threadId"] == thread_id, review_idle

send({"id": 10, "method": "thread/compact/start", "params": {
    "threadId": thread_id,
}})
compaction_response, compaction_response_records = read_until(
    lambda record: record.get("id") == 10
)
assert compaction_response["result"] == {}, compaction_response
assert not any(record.get("method") for record in compaction_response_records), (
    compaction_response_records
)
compaction_idle, compaction_lifecycle = read_until(
    lambda record: (
        record.get("method") == "thread/status/changed"
        and record.get("params", {}).get("status", {}).get("type") == "idle"
    )
)
assert compaction_idle["params"]["threadId"] == thread_id, compaction_idle
assert [record.get("method") for record in compaction_lifecycle] == [
    "thread/status/changed",
    "turn/started",
    "item/started",
    "item/completed",
    "turn/completed",
    "thread/status/changed",
], compaction_lifecycle
compaction_started = next(
    record for record in compaction_lifecycle if record.get("method") == "item/started"
)
compaction_completed = next(
    record for record in compaction_lifecycle if record.get("method") == "item/completed"
)
assert compaction_started["params"]["item"] == compaction_completed["params"]["item"]
assert compaction_started["params"]["turnId"] == compaction_completed["params"]["turnId"]
assert compaction_started["params"]["item"]["type"] == "contextCompaction"
compaction_turn = next(
    record for record in compaction_lifecycle if record.get("method") == "turn/completed"
)
assert compaction_turn["params"]["turn"]["status"] == "completed", compaction_turn

send({"id": 11, "method": "turn/start", "params": {
    "threadId": thread_id,
    "input": [{"type": "text", "text": "rollback this turn"}],
}})
second_turn, _ = read_until(lambda record: record.get("id") == 11)
assert second_turn["result"]["turn"]["status"] == "inProgress", second_turn
second_completed, _ = read_until(
    lambda record: record.get("method") == "turn/completed"
)
assert second_completed["params"]["turn"]["status"] == "completed", second_completed
read_until(
    lambda record: (
        record.get("method") == "thread/status/changed"
        and record.get("params", {}).get("threadId") == thread_id
        and record.get("params", {}).get("status", {}).get("type") == "idle"
    )
)

send({"id": 111, "method": "thread/turns/list", "params": {
    "threadId": thread_id,
    "limit": 1,
}})
newest_turn_page, _ = read_until(lambda record: record.get("id") == 111)
assert [turn["id"] for turn in newest_turn_page["result"]["data"]] == [
    second_turn["result"]["turn"]["id"],
], newest_turn_page
history_cursor = newest_turn_page["result"]["nextCursor"]
assert history_cursor, newest_turn_page
send({"id": 112, "method": "thread/turns/list", "params": {
    "threadId": thread_id,
    "limit": 1,
    "cursor": history_cursor,
}})
older_turn_page, _ = read_until(lambda record: record.get("id") == 112)
assert [turn["id"] for turn in older_turn_page["result"]["data"]] == [
    review_turn["id"],
], older_turn_page
assert older_turn_page["result"]["nextCursor"] is None, older_turn_page

send({"id": 12, "method": "thread/rollback", "params": {
    "threadId": thread_id,
    "numTurns": 1,
}})
rollback_response, rollback_records = read_until(
    lambda record: record.get("id") == 12
)
assert len(rollback_records) == 1, rollback_records
assert not any(record.get("method") for record in rollback_records), rollback_records
rolled_back = rollback_response["result"]["thread"]
assert rolled_back["id"] == thread_id, rolled_back
assert rolled_back["sessionId"] == session_id, rolled_back
assert rolled_back["status"] == {"type": "idle"}, rolled_back
assert rolled_back["name"] is None, rolled_back
assert len(rolled_back["turns"]) == 1, rolled_back

send({"id": 13, "method": "thread/read", "params": {
    "threadId": thread_id,
    "includeTurns": True,
}})
thread_after_rollback, _ = read_until(lambda record: record.get("id") == 13)
assert len(thread_after_rollback["result"]["thread"]["turns"]) == 1, (
    thread_after_rollback
)

send({"id": 14, "method": "thread/rollback", "params": {
    "threadId": thread_id,
    "numTurns": 0,
}})
invalid_rollback, _ = read_until(lambda record: record.get("id") == 14)
assert invalid_rollback["error"] == {
    "code": -32600,
    "message": "numTurns must be >= 1",
}, invalid_rollback

send({"id": 150, "method": "thread/increment_elicitation", "params": {
    "threadId": thread_id,
}})
elicitation_increment, _ = read_until(lambda record: record.get("id") == 150)
assert elicitation_increment["result"] == {"count": 1, "paused": True}, (
    elicitation_increment
)
send({"id": 151, "method": "thread/decrement_elicitation", "params": {
    "threadId": thread_id,
}})
elicitation_decrement, _ = read_until(lambda record: record.get("id") == 151)
assert elicitation_decrement["result"] == {"count": 0, "paused": False}, (
    elicitation_decrement
)

send({"id": 152, "method": "thread/metadata/update", "params": {
    "threadId": thread_id,
    "gitInfo": {
        "sha": "app-server-smoke-sha",
        "branch": "smoke/thread-controls",
        "originUrl": "https://example.invalid/quillcode.git",
    },
}})
metadata_update, _ = read_until(lambda record: record.get("id") == 152)
assert metadata_update["result"]["thread"]["gitInfo"] == {
    "sha": "app-server-smoke-sha",
    "branch": "smoke/thread-controls",
    "originUrl": "https://example.invalid/quillcode.git",
}, metadata_update

send({"id": 153, "method": "thread/settings/update", "params": {
    "threadId": thread_id,
    "effort": "low",
    "personality": "friendly",
    "serviceTier": "priority",
    "summary": "concise",
    "permissions": ":workspace",
}})
settings_response, settings_records = read_until(lambda record: record.get("id") == 153)
assert settings_response["result"] == {}, settings_response
assert not any(
    record.get("method") == "thread/settings/updated"
    for record in settings_records
), settings_records
settings_updated, _ = read_until(
    lambda record: record.get("method") == "thread/settings/updated"
)
thread_settings = settings_updated["params"]["threadSettings"]
assert settings_updated["params"]["threadId"] == thread_id, settings_updated
assert thread_settings["effort"] == "low", thread_settings
assert thread_settings["personality"] == "friendly", thread_settings
assert thread_settings["serviceTier"] == "priority", thread_settings
assert thread_settings["summary"] == "concise", thread_settings
assert thread_settings["activePermissionProfile"] == {
    "id": ":workspace",
    "extends": None,
}, thread_settings

send({"id": 154, "method": "thread/memoryMode/set", "params": {
    "threadId": thread_id,
    "mode": "disabled",
}})
memory_mode, _ = read_until(lambda record: record.get("id") == 154)
assert memory_mode["result"] == {}, memory_mode

send({"id": 159, "method": "thread/shellCommand", "params": {
    "threadId": thread_id,
    "command": "printf app-server-user-shell-smoke",
}})
shell_response, shell_response_records = read_until(lambda record: record.get("id") == 159)
assert shell_response == {"id": 159, "result": {}}, shell_response
assert shell_response_records == [shell_response], shell_response_records
shell_turn_completed, shell_lifecycle = read_until(
    lambda record: record.get("method") == "turn/completed"
)
shell_started = next(
    record for record in shell_lifecycle
    if record.get("method") == "item/started"
    and record.get("params", {}).get("item", {}).get("source") == "userShell"
)
shell_delta = next(
    record for record in shell_lifecycle
    if record.get("method") == "item/commandExecution/outputDelta"
)
shell_completed = next(
    record for record in shell_lifecycle
    if record.get("method") == "item/completed"
    and record.get("params", {}).get("item", {}).get("source") == "userShell"
)
shell_turn_id = shell_started["params"]["turnId"]
shell_item_id = shell_started["params"]["item"]["id"]
assert shell_started["params"]["item"]["type"] == "commandExecution", shell_started
assert shell_started["params"]["item"]["status"] == "inProgress", shell_started
assert os.path.realpath(shell_started["params"]["item"]["cwd"]) == os.path.realpath(
    workspace
), shell_started
assert shell_started["params"]["item"]["commandActions"] == [{
    "type": "unknown",
    "command": "printf app-server-user-shell-smoke",
}], shell_started
assert shell_delta["params"] == {
    "threadId": thread_id,
    "turnId": shell_turn_id,
    "itemId": shell_item_id,
    "delta": "app-server-user-shell-smoke",
}, shell_delta
assert shell_completed["params"]["turnId"] == shell_turn_id, shell_completed
assert shell_completed["params"]["item"]["id"] == shell_item_id, shell_completed
assert shell_completed["params"]["item"]["status"] == "completed", shell_completed
assert shell_completed["params"]["item"]["aggregatedOutput"] == (
    "app-server-user-shell-smoke"
), shell_completed
assert shell_completed["params"]["item"]["exitCode"] == 0, shell_completed
assert shell_turn_completed["params"]["turn"]["id"] == shell_turn_id, shell_turn_completed
assert shell_turn_completed["params"]["turn"]["status"] == "completed", shell_turn_completed
assert shell_turn_completed["params"]["turn"]["items"] == [], shell_turn_completed

send({"id": 160, "method": "thread/read", "params": {
    "threadId": thread_id,
    "includeTurns": True,
}})
shell_history, _ = read_until(lambda record: record.get("id") == 160)
shell_turns = shell_history["result"]["thread"]["turns"]
assert len(shell_turns) == 2, shell_history
assert shell_turns[-1]["id"] == shell_turn_id, shell_history
assert shell_turns[-1]["items"] == [], shell_history
assert all(
    item.get("type") != "commandExecution"
    for turn in shell_turns
    for item in turn["items"]
), shell_history

send({"id": 155, "method": "thread/unsubscribe", "params": {
    "threadId": thread_id,
}})
unsubscribed, _ = read_until(lambda record: record.get("id") == 155)
assert unsubscribed["result"] == {"status": "unsubscribed"}, unsubscribed
send({"id": 156, "method": "thread/loaded/list", "params": {}})
loaded_after_unsubscribe, _ = read_until(lambda record: record.get("id") == 156)
assert thread_id in loaded_after_unsubscribe["result"]["data"], loaded_after_unsubscribe

send({"id": 157, "method": "thread/resume", "params": {"threadId": thread_id}})
resumed, _ = read_until(lambda record: record.get("id") == 157)
assert resumed["result"]["thread"]["gitInfo"]["branch"] == "smoke/thread-controls", resumed
assert resumed["result"]["reasoningEffort"] == "low", resumed
assert resumed["result"]["serviceTier"] == "priority", resumed
send({"id": 158, "method": "thread/unsubscribe", "params": {
    "threadId": thread_id,
}})
resubscribed, _ = read_until(lambda record: record.get("id") == 158)
assert resubscribed["result"] == {"status": "unsubscribed"}, resubscribed

process.stdin.close()
status = process.wait(timeout=10)
stderr = process.stderr.read()
assert status == 0, (status, stderr)
PY

echo "quill-code app-server smoke passed"
