#!/usr/bin/env bash
# cua-driver computer-use backend smoke.
#
# Proves the cua-driver-backed ComputerUseBackend works end-to-end against a REAL driver binary,
# without firing any unsolicited input events on the live desktop. It exercises the read path
# (permissions probe, desktop-scope config, native screenshot capture, frontmost-app resolution) at
# the driver level, then runs the gated Swift live-drive test so the same path is proven through the
# production Swift types (screenshot → coordinate-safe downscale → reported dims match the PNG).
#
# Requires a cua-driver binary. Point at it explicitly:
#   QUILLCODE_CUA_LIVE_BINARY=/path/to/cua-driver bash scripts/cua-driver-smoke.sh
# or install it at one of the locator's conventional paths (~/.quillcode/tools/cua-driver, etc.).
#
# Screen Recording must be granted to the process that launches this (Terminal/IDE); Accessibility is
# required only for the interactive write path, which this smoke intentionally does NOT exercise.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRIVER="${QUILLCODE_CUA_LIVE_BINARY:-}"

if [[ -z "$DRIVER" ]]; then
  for candidate in \
    "$HOME/.quillcode/tools/cua-driver" \
    "$HOME/.local/bin/cua-driver" \
    "$HOME/.cua/bin/cua-driver" \
    "/opt/homebrew/bin/cua-driver" \
    "/usr/local/bin/cua-driver"; do
    if [[ -x "$candidate" ]]; then DRIVER="$candidate"; break; fi
  done
fi

if [[ -z "$DRIVER" || ! -x "$DRIVER" ]]; then
  echo "SKIP: no cua-driver binary found. Set QUILLCODE_CUA_LIVE_BINARY=/path/to/cua-driver." >&2
  exit 0
fi

echo "cua-driver: $DRIVER"
fail() { echo "FAIL: $1" >&2; exit 1; }

# Privacy posture: keep automation metadata on-device.
"$DRIVER" telemetry disable >/dev/null 2>&1 || true

echo "== check_permissions (caller TCC identity) =="
PERMS="$("$DRIVER" call check_permissions '{"prompt":false}' 2>/dev/null)"
echo "$PERMS" | python3 -c '
import sys, json
d = json.load(sys.stdin)
print("  screen_recording:", d.get("screen_recording"), " accessibility:", d.get("accessibility"))
if not d.get("screen_recording"):
    sys.exit("  screen recording NOT granted — the read path cannot run")
' || fail "screen recording not granted"

echo "== set_config capture_scope=desktop =="
"$DRIVER" call set_config '{"capture_scope":"desktop"}' >/dev/null 2>&1 || fail "set_config failed"

echo "== get_desktop_state (native screenshot) =="
"$DRIVER" call get_desktop_state '{"session":"quillcode-smoke"}' 2>/dev/null | python3 -c '
import sys, json, base64
d = json.load(sys.stdin)
b64 = d.get("screenshot_png_b64")
w, h = d.get("screenshot_width"), d.get("screenshot_height")
if not b64 or not w or not h:
    sys.exit("  missing screenshot fields")
raw = base64.b64decode(b64)
if raw[:8] != b"\x89PNG\r\n\x1a\n":
    sys.exit("  not a PNG")
print(f"  captured {w}x{h} PNG ({len(raw)} bytes)")
' || fail "get_desktop_state did not return a valid PNG"

echo "== list_apps (frontmost resolution) =="
"$DRIVER" call list_apps '{}' 2>/dev/null | python3 -c '
import sys, json
apps = json.load(sys.stdin).get("apps", [])
active = [a for a in apps if a.get("active")]
if not active:
    sys.exit("  no frontmost app resolved")
a = active[0]
print("  frontmost:", a.get("name"), "(pid", a.get("pid"), ")")
' || fail "list_apps did not resolve a frontmost app"

echo "== Swift live-drive test (production types) =="
(
  cd "$ROOT_DIR"
  CC="${CC:-clang-17}" QUILLCODE_CUA_LIVE_BINARY="$DRIVER" \
    swift test --filter CuaDriverLiveDriveTests 2>&1 | tail -8
) || fail "Swift live-drive test failed"

echo "PASS: cua-driver read path proven live (driver + production Swift types)."
