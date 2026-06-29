#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SMOKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/quillcode-packaged-macos-smoke.XXXXXX")"
APP_OUTPUT_DIR="$SMOKE_ROOT/app"
DIRECT_SMOKE_ARTIFACT_DIR="$SMOKE_ROOT/direct-executable"
LAUNCH_SERVICES_SMOKE_ARTIFACT_DIR="$SMOKE_ROOT/launch-services"
CLICK_PROBE_MANIFEST="$SMOKE_ROOT/packaged-click-probes.json"
ARTIFACT_DIR="${QUILLCODE_PACKAGED_MACOS_SMOKE_ARTIFACT_DIR:-}"

cleanup() {
  local status=$?
  set +e

  if [[ -n "$ARTIFACT_DIR" ]]; then
    mkdir -p "$ARTIFACT_DIR"
    if [[ -n "${INFO_PLIST:-}" && -e "$INFO_PLIST" ]]; then
      cp "$INFO_PLIST" "$ARTIFACT_DIR/Info.plist"
    fi
    if [[ -d "$DIRECT_SMOKE_ARTIFACT_DIR" ]]; then
      rm -rf "$ARTIFACT_DIR/direct-executable"
      cp -R "$DIRECT_SMOKE_ARTIFACT_DIR" "$ARTIFACT_DIR/direct-executable"
    fi
    if [[ -d "$LAUNCH_SERVICES_SMOKE_ARTIFACT_DIR" ]]; then
      rm -rf "$ARTIFACT_DIR/launch-services"
      cp -R "$LAUNCH_SERVICES_SMOKE_ARTIFACT_DIR" "$ARTIFACT_DIR/launch-services"
    fi
    if [[ -e "$CLICK_PROBE_MANIFEST" ]]; then
      cp "$CLICK_PROBE_MANIFEST" "$ARTIFACT_DIR/packaged-click-probes.json"
    fi
    {
      printf 'label=packaged macOS app\n'
      printf 'status=%s\n' "$status"
      printf 'source=%s\n' "$SMOKE_ROOT"
      if [[ -n "${APP_BUNDLE:-}" ]]; then
        printf 'app_bundle=%s\n' "$APP_BUNDLE"
      fi
      printf 'direct_smoke=direct-executable\n'
      printf 'launch_services_smoke=launch-services\n'
      printf 'click_probe_manifest=packaged-click-probes.json\n'
    } > "$ARTIFACT_DIR/manifest.txt"
    echo "QuillCode packaged macOS app smoke artifacts: $ARTIFACT_DIR"
  fi

  rm -rf "$SMOKE_ROOT"
  exit "$status"
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
QUILLCODE_NATIVE_DESKTOP_SMOKE_ARTIFACT_DIR="$DIRECT_SMOKE_ARTIFACT_DIR" \
  "$ROOT_DIR/scripts/native-desktop-smoke.sh"

QUILLCODE_DESKTOP_APP_BUNDLE="$APP_BUNDLE" \
QUILLCODE_NATIVE_DESKTOP_SMOKE_LABEL="packaged macOS app Launch Services" \
QUILLCODE_NATIVE_DESKTOP_SMOKE_ARTIFACT_DIR="$LAUNCH_SERVICES_SMOKE_ARTIFACT_DIR" \
  "$ROOT_DIR/scripts/native-desktop-smoke.sh"

"$ROOT_DIR/scripts/native-click-probe-contracts.py" compare \
  "$DIRECT_SMOKE_ARTIFACT_DIR/report.json" \
  "$LAUNCH_SERVICES_SMOKE_ARTIFACT_DIR/report.json" \
  --manifest "$CLICK_PROBE_MANIFEST"

echo "QuillCode packaged macOS app smoke passed."
