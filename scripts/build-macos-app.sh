#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${QUILLCODE_MACOS_APP_OUTPUT_DIR:-$ROOT_DIR/.build/quillcode-macos-app}"
CONFIGURATION="${QUILLCODE_MACOS_APP_CONFIGURATION:-debug}"
APP_NAME="${QUILLCODE_MACOS_APP_NAME:-QuillCode}"
BUNDLE_ID="${QUILLCODE_MACOS_BUNDLE_ID:-co.lorehex.QuillCode}"
MINIMUM_SYSTEM_VERSION="${QUILLCODE_MACOS_MINIMUM_SYSTEM_VERSION:-14.0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --configuration)
      CONFIGURATION="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "build-macos-app.sh must run on macOS." >&2
  exit 2
fi

cd "$ROOT_DIR"

echo "==> Building quill-code-desktop ($CONFIGURATION)" >&2
swift build --configuration "$CONFIGURATION" --product quill-code-desktop >&2
BIN_DIR="$(swift build --configuration "$CONFIGURATION" --product quill-code-desktop --show-bin-path)"
SOURCE_EXECUTABLE="$BIN_DIR/quill-code-desktop"

if [[ ! -x "$SOURCE_EXECUTABLE" ]]; then
  echo "Built executable is missing or not executable: $SOURCE_EXECUTABLE" >&2
  exit 1
fi

APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$SOURCE_EXECUTABLE" "$MACOS_DIR/$APP_NAME"
chmod 755 "$MACOS_DIR/$APP_NAME"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MINIMUM_SYSTEM_VERSION</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSSupportsAutomaticTermination</key>
  <true/>
  <key>NSSupportsSuddenTermination</key>
  <true/>
</dict>
</plist>
PLIST

printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"
plutil -lint "$CONTENTS_DIR/Info.plist" >&2

if [[ "${QUILLCODE_MACOS_ADHOC_CODESIGN:-0}" == "1" ]]; then
  codesign --force --deep --sign - "$APP_BUNDLE" >&2
fi

printf '%s\n' "$APP_BUNDLE"
