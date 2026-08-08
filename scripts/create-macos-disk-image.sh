#!/usr/bin/env bash
set -euo pipefail

APP_BUNDLE=""
OUTPUT_PATH=""
VOLUME_NAME="Quill Cowork"
WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/quill-cowork-disk-image.XXXXXX")"
STAGING_DIR="$WORK_ROOT/staging"
MOUNT_POINT="$WORK_ROOT/mounted"
MOUNTED=false

cleanup() {
  set +e
  if [[ "$MOUNTED" == true ]]; then
    hdiutil detach -quiet "$MOUNT_POINT" || hdiutil detach -quiet -force "$MOUNT_POINT"
  fi
  rm -rf "$WORK_ROOT"
}
trap cleanup EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP_BUNDLE="$2"
      shift 2
      ;;
    --output)
      OUTPUT_PATH="$2"
      shift 2
      ;;
    --volume-name)
      VOLUME_NAME="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "create-macos-disk-image.sh must run on macOS." >&2
  exit 2
fi
if [[ ! -d "$APP_BUNDLE" || "$APP_BUNDLE" != *.app || -z "$OUTPUT_PATH" ]]; then
  echo "Usage: create-macos-disk-image.sh --app APP_BUNDLE --output OUTPUT_DMG" >&2
  exit 2
fi

APP_NAME="$(basename "$APP_BUNDLE")"
APP_EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_BUNDLE/Contents/Info.plist")"
if [[ ! -x "$APP_BUNDLE/Contents/MacOS/$APP_EXECUTABLE_NAME" ]]; then
  echo "App executable is missing from $APP_BUNDLE" >&2
  exit 1
fi

mkdir -p "$STAGING_DIR" "$MOUNT_POINT" "$(dirname "$OUTPUT_PATH")"
ditto "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME"
ln -s /Applications "$STAGING_DIR/Applications"
touch "$STAGING_DIR/.metadata_never_index"

hdiutil create \
  -quiet \
  -ov \
  -format UDZO \
  -fs HFS+ \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  "$OUTPUT_PATH"
hdiutil verify -quiet "$OUTPUT_PATH"

hdiutil attach -quiet -readonly -nobrowse -mountpoint "$MOUNT_POINT" "$OUTPUT_PATH"
MOUNTED=true
if [[ ! -d "$MOUNT_POINT/$APP_NAME" || ! -x "$MOUNT_POINT/$APP_NAME/Contents/MacOS/$APP_EXECUTABLE_NAME" ]]; then
  echo "Mounted disk image does not contain an executable $APP_NAME bundle." >&2
  exit 1
fi
if [[ ! -L "$MOUNT_POINT/Applications" || "$(readlink "$MOUNT_POINT/Applications")" != "/Applications" ]]; then
  echo "Mounted disk image does not contain the /Applications install shortcut." >&2
  exit 1
fi
codesign --verify --deep --strict "$MOUNT_POINT/$APP_NAME"
hdiutil detach -quiet "$MOUNT_POINT"
MOUNTED=false

if [[ ! -s "$OUTPUT_PATH" ]]; then
  echo "Disk image was not created: $OUTPUT_PATH" >&2
  exit 1
fi
echo "$OUTPUT_PATH"
