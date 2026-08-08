#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${QUILLCODE_MACOS_APP_OUTPUT_DIR:-$ROOT_DIR/.build/quillcode-macos-app}"
CONFIGURATION="${QUILLCODE_MACOS_APP_CONFIGURATION:-debug}"
APP_NAME="${QUILLCODE_MACOS_APP_NAME:-Quill Cowork}"
BUNDLE_ID="${QUILLCODE_MACOS_BUNDLE_ID:-co.lorehex.QuillCowork}"
MINIMUM_SYSTEM_VERSION="${QUILLCODE_MACOS_MINIMUM_SYSTEM_VERSION:-14.0}"
VERSION="${QUILLCODE_MACOS_APP_VERSION:-0.1.0}"
BUILD_NUMBER="${QUILLCODE_MACOS_BUILD_NUMBER:-1}"
BUILD_COMMIT="${QUILLCODE_MACOS_BUILD_COMMIT:-}"
UPDATE_CHANNEL="${QUILLCODE_MACOS_UPDATE_CHANNEL:-tester}"
UPDATE_MANIFEST_URL="${QUILLCODE_MACOS_UPDATE_MANIFEST_URL:-https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/latest-tester-build.json}"
UPDATE_STABLE_MANIFEST_URL="${QUILLCODE_MACOS_UPDATE_STABLE_MANIFEST_URL:-https://github.com/Lore-Hex/QuillCode/releases/latest/download/latest-stable-build.json}"
UPDATE_TESTER_MANIFEST_URL="${QUILLCODE_MACOS_UPDATE_TESTER_MANIFEST_URL:-https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/latest-tester-build.json}"
SIGNING_IDENTITY="${QUILLCODE_MACOS_SIGNING_IDENTITY:-}"
SIGNING_TEAM_IDENTIFIER="${QUILLCODE_MACOS_SIGNING_TEAM_IDENTIFIER:-}"
SIGNING_KEYCHAIN="${QUILLCODE_MACOS_SIGNING_KEYCHAIN:-}"
SWIFT_DEBUG_INFO_FORMAT="${QUILLCODE_SWIFT_DEBUG_INFO_FORMAT:-}"

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

if [[ -z "$BUILD_COMMIT" ]]; then
  BUILD_COMMIT="$(git rev-parse HEAD 2>/dev/null || printf 'development')"
fi
if [[ "$BUILD_COMMIT" != "development" && ! "$BUILD_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
  echo "QUILLCODE_MACOS_BUILD_COMMIT must be a lowercase 40-character commit or development." >&2
  exit 2
fi

SWIFT_BUILD_ARGUMENTS=(--configuration "$CONFIGURATION" --product quill-code-desktop)
if [[ -n "$SWIFT_DEBUG_INFO_FORMAT" ]]; then
  case "$SWIFT_DEBUG_INFO_FORMAT" in
    dwarf|codeview|none) ;;
    *)
      echo "Unsupported QUILLCODE_SWIFT_DEBUG_INFO_FORMAT: $SWIFT_DEBUG_INFO_FORMAT" >&2
      exit 2
      ;;
  esac
  SWIFT_BUILD_ARGUMENTS+=(-debug-info-format "$SWIFT_DEBUG_INFO_FORMAT")
fi

echo "==> Building quill-code-desktop ($CONFIGURATION)" >&2
swift build "${SWIFT_BUILD_ARGUMENTS[@]}" >&2
BIN_DIR="$(swift build "${SWIFT_BUILD_ARGUMENTS[@]}" --show-bin-path)"
SOURCE_EXECUTABLE="$BIN_DIR/quill-code-desktop"

if [[ ! -x "$SOURCE_EXECUTABLE" ]]; then
  echo "Built executable is missing or not executable: $SOURCE_EXECUTABLE" >&2
  exit 1
fi

APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
APP_ICON_SOURCE="$ROOT_DIR/Resources/AppIcon/QuillCode.icns"
MENU_BAR_ICON_SOURCE="$ROOT_DIR/Resources/MenuBar/QuillCodeMenuBarTemplate.png"

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$SOURCE_EXECUTABLE" "$MACOS_DIR/$APP_NAME"
chmod 755 "$MACOS_DIR/$APP_NAME"
if [[ -f "$APP_ICON_SOURCE" ]]; then
  cp "$APP_ICON_SOURCE" "$RESOURCES_DIR/QuillCode.icns"
fi
if [[ -f "$MENU_BAR_ICON_SOURCE" ]]; then
  cp "$MENU_BAR_ICON_SOURCE" "$RESOURCES_DIR/QuillCodeMenuBarTemplate.png"
fi

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
  <key>CFBundleIconFile</key>
  <string>QuillCode</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>QuillCodeBuildCommit</key>
  <string>$BUILD_COMMIT</string>
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
  <key>QuillCodeUpdateChannel</key>
  <string>$UPDATE_CHANNEL</string>
  <key>QuillCodeUpdateManifestURL</key>
  <string>$UPDATE_MANIFEST_URL</string>
  <key>QuillCodeStableUpdateManifestURL</key>
  <string>$UPDATE_STABLE_MANIFEST_URL</string>
  <key>QuillCodeTesterUpdateManifestURL</key>
  <string>$UPDATE_TESTER_MANIFEST_URL</string>
</dict>
</plist>
PLIST

if [[ -n "$SIGNING_TEAM_IDENTIFIER" ]]; then
  /usr/libexec/PlistBuddy -c \
    "Add :QuillCodeSigningTeamIdentifier string $SIGNING_TEAM_IDENTIFIER" \
    "$CONTENTS_DIR/Info.plist"
fi

printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"
plutil -lint "$CONTENTS_DIR/Info.plist" >&2

if [[ -n "$SIGNING_IDENTITY" ]]; then
  if [[ -z "$SIGNING_TEAM_IDENTIFIER" ]]; then
    echo "QUILLCODE_MACOS_SIGNING_TEAM_IDENTIFIER is required for Developer ID signing." >&2
    exit 2
  fi
  CODESIGN_ARGUMENTS=(
    --force
    --options runtime
    --timestamp
    --sign "$SIGNING_IDENTITY"
  )
  if [[ -n "$SIGNING_KEYCHAIN" ]]; then
    CODESIGN_ARGUMENTS+=(--keychain "$SIGNING_KEYCHAIN")
  fi
  codesign "${CODESIGN_ARGUMENTS[@]}" "$APP_BUNDLE" >&2
  codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE" >&2
elif [[ "${QUILLCODE_MACOS_ADHOC_CODESIGN:-0}" == "1" ]]; then
  codesign --force --deep --sign - "$APP_BUNDLE" >&2
fi

printf '%s\n' "$APP_BUNDLE"
