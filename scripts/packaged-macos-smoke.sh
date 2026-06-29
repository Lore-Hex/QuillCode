#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SMOKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/quillcode-packaged-macos-smoke.XXXXXX")"
APP_OUTPUT_DIR="$SMOKE_ROOT/app"

cleanup() {
  rm -rf "$SMOKE_ROOT"
}
trap cleanup EXIT

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "packaged-macos-smoke.sh must run on macOS." >&2
  exit 2
fi

cd "$ROOT_DIR"

echo "==> Building packaged macOS app"
APP_BUNDLE="$("$ROOT_DIR/scripts/build-macos-app.sh" --output "$APP_OUTPUT_DIR")"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/QuillCode"

assert_plist_value() {
  local key="$1"
  local expected="$2"
  local actual
  actual="$(/usr/libexec/PlistBuddy -c "Print :$key" "$INFO_PLIST")"
  if [[ "$actual" != "$expected" ]]; then
    echo "Packaged app Info.plist $key expected '$expected' but found '$actual'." >&2
    exit 1
  fi
}

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Packaged app bundle was not created: $APP_BUNDLE" >&2
  exit 1
fi
if [[ ! -x "$APP_EXECUTABLE" ]]; then
  echo "Packaged app executable is missing or not executable: $APP_EXECUTABLE" >&2
  exit 1
fi

plutil -lint "$INFO_PLIST" >/dev/null
assert_plist_value CFBundleName QuillCode
assert_plist_value CFBundleDisplayName QuillCode
assert_plist_value CFBundleExecutable QuillCode
assert_plist_value CFBundleIdentifier co.lorehex.QuillCode
assert_plist_value CFBundlePackageType APPL
assert_plist_value LSApplicationCategoryType public.app-category.developer-tools
assert_plist_value NSPrincipalClass NSApplication

QUILLCODE_DESKTOP_EXECUTABLE="$APP_EXECUTABLE" \
QUILLCODE_NATIVE_DESKTOP_SMOKE_LABEL="packaged macOS app" \
  "$ROOT_DIR/scripts/native-desktop-smoke.sh"

QUILLCODE_DESKTOP_APP_BUNDLE="$APP_BUNDLE" \
QUILLCODE_NATIVE_DESKTOP_SMOKE_LABEL="packaged macOS app Launch Services" \
  "$ROOT_DIR/scripts/native-desktop-smoke.sh"

echo "QuillCode packaged macOS app smoke passed."
