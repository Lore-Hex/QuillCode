#!/usr/bin/env bash
set -euo pipefail

APP_BUNDLE=""
OUTPUT_PATH=""
VOLUME_NAME="Quill Cowork"
MAX_ATTEMPTS="${QUILLCODE_DISK_IMAGE_MAX_ATTEMPTS:-3}"
RETRY_DELAY_SECONDS="${QUILLCODE_DISK_IMAGE_RETRY_DELAY_SECONDS:-2}"
PLATFORM="${QUILLCODE_DISK_IMAGE_PLATFORM:-$(uname -s)}"
HDIUTIL_BIN="${QUILLCODE_HDIUTIL_BIN:-hdiutil}"
DITTO_BIN="${QUILLCODE_DITTO_BIN:-ditto}"
CODESIGN_BIN="${QUILLCODE_CODESIGN_BIN:-codesign}"
PLIST_BUDDY_BIN="${QUILLCODE_PLIST_BUDDY_BIN:-/usr/libexec/PlistBuddy}"
WORK_ROOT=""
MOUNT_POINT=""
MOUNTED=false

detach_mounted_image() {
  if [[ "$MOUNTED" != true ]]; then
    return 0
  fi

  if "$HDIUTIL_BIN" detach "$MOUNT_POINT"; then
    MOUNTED=false
    return 0
  fi

  echo "Normal disk-image detach failed; forcing detach of $MOUNT_POINT." >&2
  if "$HDIUTIL_BIN" detach -force "$MOUNT_POINT"; then
    MOUNTED=false
    return 0
  fi

  echo "Unable to detach disk image from $MOUNT_POINT." >&2
  return 1
}

cleanup() {
  set +e
  if ! detach_mounted_image; then
    echo "Disk-image cleanup could not detach the private mount." >&2
  fi
  if [[ -n "$WORK_ROOT" ]]; then
    rm -rf "$WORK_ROOT"
  fi
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

if [[ "$PLATFORM" != "Darwin" ]]; then
  echo "create-macos-disk-image.sh must run on macOS." >&2
  exit 2
fi
if [[ ! -d "$APP_BUNDLE" || "$APP_BUNDLE" != *.app || -z "$OUTPUT_PATH" ]]; then
  echo "Usage: create-macos-disk-image.sh --app APP_BUNDLE --output OUTPUT_DMG" >&2
  exit 2
fi
if [[ ! "$MAX_ATTEMPTS" =~ ^[1-5]$ ]]; then
  echo "QUILLCODE_DISK_IMAGE_MAX_ATTEMPTS must be an integer from 1 through 5." >&2
  exit 2
fi
if [[ ! "$RETRY_DELAY_SECONDS" =~ ^[0-9]+$ || "$RETRY_DELAY_SECONDS" -gt 30 ]]; then
  echo "QUILLCODE_DISK_IMAGE_RETRY_DELAY_SECONDS must be an integer from 0 through 30." >&2
  exit 2
fi

APP_NAME="$(basename "$APP_BUNDLE")"
APP_EXECUTABLE_NAME="$("$PLIST_BUDDY_BIN" -c 'Print :CFBundleExecutable' "$APP_BUNDLE/Contents/Info.plist")"
if [[ ! -x "$APP_BUNDLE/Contents/MacOS/$APP_EXECUTABLE_NAME" ]]; then
  echo "App executable is missing from $APP_BUNDLE" >&2
  exit 1
fi

OUTPUT_DIRECTORY="$(dirname "$OUTPUT_PATH")"
mkdir -p "$OUTPUT_DIRECTORY"
WORK_ROOT="$(mktemp -d "$OUTPUT_DIRECTORY/.quill-cowork-disk-image.XXXXXX")"
STAGING_DIR="$WORK_ROOT/staging"
mkdir -p "$STAGING_DIR"
"$DITTO_BIN" "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME"
ln -s /Applications "$STAGING_DIR/Applications"
touch "$STAGING_DIR/.metadata_never_index"

run_image_operation() {
  local stage="$1"
  shift
  if "$@"; then
    return 0
  else
    local status=$?
    echo "Disk-image $stage failed on attempt $ATTEMPT/$MAX_ATTEMPTS (exit $status)." >&2
    return "$status"
  fi
}

for ((ATTEMPT = 1; ATTEMPT <= MAX_ATTEMPTS; ATTEMPT += 1)); do
  CANDIDATE_PATH="$WORK_ROOT/Quill-Cowork-attempt-$ATTEMPT.dmg"
  MOUNT_POINT="$WORK_ROOT/mounted-$ATTEMPT"
  mkdir -p "$MOUNT_POINT"
  FAILED_STAGE=""

  echo "==> Creating Quill Cowork disk image (attempt $ATTEMPT/$MAX_ATTEMPTS)"
  if ! run_image_operation create \
    "$HDIUTIL_BIN" create \
      -ov \
      -format UDZO \
      -fs HFS+ \
      -volname "$VOLUME_NAME" \
      -srcfolder "$STAGING_DIR" \
      "$CANDIDATE_PATH"; then
    FAILED_STAGE="create"
  elif ! run_image_operation verify "$HDIUTIL_BIN" verify "$CANDIDATE_PATH"; then
    FAILED_STAGE="verify"
  elif ! run_image_operation attach \
    "$HDIUTIL_BIN" attach -readonly -nobrowse -mountpoint "$MOUNT_POINT" "$CANDIDATE_PATH"; then
    FAILED_STAGE="attach"
    "$HDIUTIL_BIN" detach -force "$MOUNT_POINT" >/dev/null 2>&1 || true
  else
    MOUNTED=true
  fi

  if [[ -n "$FAILED_STAGE" ]]; then
    rm -f "$CANDIDATE_PATH"
    if (( ATTEMPT < MAX_ATTEMPTS )); then
      echo "Retrying disk-image packaging after transient $FAILED_STAGE failure." >&2
      sleep "$RETRY_DELAY_SECONDS"
      continue
    fi
    echo "Disk-image packaging failed after $MAX_ATTEMPTS attempts; last failed stage: $FAILED_STAGE." >&2
    exit 1
  fi

  if [[ ! -d "$MOUNT_POINT/$APP_NAME" || ! -x "$MOUNT_POINT/$APP_NAME/Contents/MacOS/$APP_EXECUTABLE_NAME" ]]; then
    echo "Mounted disk image does not contain an executable $APP_NAME bundle." >&2
    exit 1
  fi
  if [[ ! -L "$MOUNT_POINT/Applications" || "$(readlink "$MOUNT_POINT/Applications")" != "/Applications" ]]; then
    echo "Mounted disk image does not contain the /Applications install shortcut." >&2
    exit 1
  fi
  if ! "$CODESIGN_BIN" --verify --deep --strict "$MOUNT_POINT/$APP_NAME"; then
    echo "Mounted disk image contains an app with an invalid code signature; refusing to retry." >&2
    exit 1
  fi
  if ! detach_mounted_image; then
    exit 1
  fi

  if [[ ! -s "$CANDIDATE_PATH" ]]; then
    echo "Disk image candidate is empty: $CANDIDATE_PATH" >&2
    exit 1
  fi
  mv -f "$CANDIDATE_PATH" "$OUTPUT_PATH"
  echo "Disk image ready after $ATTEMPT attempt(s): $OUTPUT_PATH"
  exit 0
done
