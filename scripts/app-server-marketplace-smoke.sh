#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SMOKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/quillcode-marketplace-smoke.XXXXXX")"
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
import json
import os
import subprocess
import sys

binary, home, workspace = [
    os.path.normpath(os.path.abspath(path)) for path in sys.argv[1:]
]
source = os.path.join(workspace, "marketplace-source")
catalog = os.path.join(source, ".agents", "plugins", "marketplace.json")
manifest = os.path.join(
    source,
    "catalog",
    "smoke-plugin",
    ".codex-plugin",
    "plugin.json",
)
os.makedirs(os.path.dirname(catalog), exist_ok=True)
os.makedirs(os.path.dirname(manifest), exist_ok=True)
with open(catalog, "w", encoding="utf-8") as file:
    json.dump({
        "name": "smoke-marketplace",
        "plugins": [{"name": "smoke-plugin", "source": "./catalog/smoke-plugin"}],
    }, file)
with open(manifest, "w", encoding="utf-8") as file:
    json.dump({"name": "smoke-plugin", "version": "1.0.0"}, file)

def git(*arguments):
    return subprocess.run(
        ["git", *arguments],
        cwd=source,
        check=True,
        capture_output=True,
        text=True,
    )

git("init", "-b", "main")
git("config", "user.email", "marketplace-smoke@quillcode.local")
git("config", "user.name", "QuillCode Marketplace Smoke")
git("add", ".")
git("commit", "-m", "initial marketplace")

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

def read_until(predicate, limit=100):
    records = []
    for _ in range(limit):
        line = process.stdout.readline()
        if not line:
            raise AssertionError(f"app-server closed early: {process.stderr.read()}")
        record = json.loads(line)
        records.append(record)
        if predicate(record):
            return record, records
    raise AssertionError("app-server did not emit the expected marketplace record")

send({
    "id": 1,
    "method": "initialize",
    "params": {"clientInfo": {"name": "marketplace-smoke", "version": "1"}},
})
initialized, _ = read_until(lambda record: record.get("id") == 1)
assert "result" in initialized, initialized
send({"method": "initialized", "params": {}})

send({"id": 2, "method": "marketplace/add", "params": {
    "source": source,
    "refName": "main",
}})
added, records = read_until(lambda record: record.get("id") == 2)
assert added["result"]["marketplaceName"] == "smoke-marketplace", added
assert added["result"]["alreadyAdded"] is False, added
installed_root = added["result"]["installedRoot"]
assert os.path.isfile(os.path.join(
    installed_root,
    "catalog",
    "smoke-plugin",
    ".codex-plugin",
    "plugin.json",
)), added
assert any(record.get("method") == "skills/changed" for record in records), records

send({"id": 3, "method": "marketplace/add", "params": {
    "source": source,
    "refName": "main",
}})
added_again, _ = read_until(lambda record: record.get("id") == 3)
assert added_again["result"]["alreadyAdded"] is True, added_again
assert added_again["result"]["installedRoot"] == installed_root, added_again

with open(manifest, "w", encoding="utf-8") as file:
    json.dump({"name": "smoke-plugin", "version": "2.0.0"}, file)
git("add", ".")
git("commit", "-m", "upgrade marketplace")
send({"id": 4, "method": "marketplace/upgrade", "params": {
    "marketplaceName": "smoke-marketplace",
}})
upgraded, records = read_until(lambda record: record.get("id") == 4)
assert upgraded["result"] == {
    "selectedMarketplaces": ["smoke-marketplace"],
    "upgradedRoots": [installed_root],
    "errors": [],
}, upgraded
assert any(record.get("method") == "skills/changed" for record in records), records
with open(os.path.join(
    installed_root,
    "catalog",
    "smoke-plugin",
    ".codex-plugin",
    "plugin.json",
), encoding="utf-8") as file:
    assert json.load(file)["version"] == "2.0.0"

send({"id": 5, "method": "marketplace/remove", "params": {
    "marketplaceName": "smoke-marketplace",
}})
removed, records = read_until(lambda record: record.get("id") == 5)
assert removed["result"] == {
    "marketplaceName": "smoke-marketplace",
    "installedRoot": installed_root,
}, removed
assert not os.path.exists(installed_root), installed_root
assert any(record.get("method") == "skills/changed" for record in records), records

process.stdin.close()
status = process.wait(timeout=10)
stderr = process.stderr.read()
assert status == 0, (status, stderr)
PY

echo "quill-code app-server marketplace smoke passed"
