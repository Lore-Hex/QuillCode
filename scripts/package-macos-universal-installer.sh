#!/usr/bin/env bash
set -euo pipefail
shopt -s dotglob nullglob

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLATFORM="${QUILLCODE_UNIVERSAL_INSTALLER_PLATFORM:-$(uname -s)}"
DITTO_BIN="${QUILLCODE_DITTO_BIN:-ditto}"
LIPO_BIN="${QUILLCODE_LIPO_BIN:-lipo}"
CODESIGN_BIN="${QUILLCODE_CODESIGN_BIN:-codesign}"
SPCTL_BIN="${QUILLCODE_SPCTL_BIN:-spctl}"
XCRUN_BIN="${QUILLCODE_XCRUN_BIN:-xcrun}"
SIGNING_IDENTITY="${QUILLCODE_MACOS_SIGNING_IDENTITY:-}"
SIGNING_TEAM_IDENTIFIER="${QUILLCODE_MACOS_SIGNING_TEAM_IDENTIFIER:-}"
SIGNING_KEYCHAIN="${QUILLCODE_MACOS_SIGNING_KEYCHAIN:-}"
NOTARY_KEY_ID="${QUILLCODE_MACOS_NOTARY_KEY_ID:-}"
NOTARY_ISSUER_ID="${QUILLCODE_MACOS_NOTARY_ISSUER_ID:-}"
NOTARY_KEY_PATH="${QUILLCODE_MACOS_NOTARY_KEY_PATH:-}"
UPDATE_CHANNEL="${QUILLCODE_UPDATE_CHANNEL:-tester}"
MAXIMUM_ARCHIVE_BYTES=$((1024 * 1024 * 1024))
APP_NAME="Quill Cowork.app"
EXECUTABLE_RELATIVE_PATH="Contents/MacOS/Quill Cowork"

usage() {
  cat <<'USAGE'
Usage: package-macos-universal-installer.sh \
  --arm64-app-zip PATH --x86-64-app-zip PATH --output PATH
USAGE
}

fail() {
  printf '%s\n' "$1" >&2
  exit "${2:-1}"
}

ARM64_APP_ZIP=""
X86_64_APP_ZIP=""
OUTPUT_PATH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --arm64-app-zip)
      [[ $# -ge 2 ]] || fail "--arm64-app-zip requires a path." 2
      ARM64_APP_ZIP="$2"
      shift 2
      ;;
    --x86-64-app-zip)
      [[ $# -ge 2 ]] || fail "--x86-64-app-zip requires a path." 2
      X86_64_APP_ZIP="$2"
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || fail "--output requires a path." 2
      OUTPUT_PATH="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1" 2
      ;;
  esac
done

[[ "$PLATFORM" == "Darwin" ]] || fail "Universal macOS packaging must run on macOS." 2
[[ -n "$ARM64_APP_ZIP" && -n "$X86_64_APP_ZIP" && -n "$OUTPUT_PATH" ]] || {
  usage >&2
  exit 2
}
[[ "$OUTPUT_PATH" == *.dmg ]] || fail "Universal installer output must end in .dmg." 2

validate_archive() {
  local archive="$1"
  local label="$2"
  [[ -f "$archive" && ! -L "$archive" ]] || fail "$label must be a regular ZIP archive: $archive" 2
  local size
  size="$(stat -f '%z' "$archive")"
  [[ "$size" =~ ^[0-9]+$ && "$size" -gt 0 && "$size" -le "$MAXIMUM_ARCHIVE_BYTES" ]] || \
    fail "$label has an invalid size: $size bytes" 2
}

validate_archive "$ARM64_APP_ZIP" "arm64 app archive"
validate_archive "$X86_64_APP_ZIP" "x86_64 app archive"

if [[ "$UPDATE_CHANNEL" == "stable" ]]; then
  [[ -n "$SIGNING_IDENTITY" && -n "$SIGNING_TEAM_IDENTIFIER" ]] || \
    fail "Stable universal installers require Developer ID signing." 2
  [[ -n "$NOTARY_KEY_ID" && -n "$NOTARY_ISSUER_ID" && -n "$NOTARY_KEY_PATH" ]] || \
    fail "Stable universal installers require App Store Connect notarization credentials." 2
fi
if [[ -n "$SIGNING_IDENTITY" && -z "$SIGNING_TEAM_IDENTIFIER" ]]; then
  fail "QUILLCODE_MACOS_SIGNING_TEAM_IDENTIFIER is required for Developer ID signing." 2
fi

OUTPUT_DIRECTORY="$(dirname "$OUTPUT_PATH")"
mkdir -p "$OUTPUT_DIRECTORY"
WORK_DIRECTORY="$(mktemp -d "$OUTPUT_DIRECTORY/.quill-cowork-universal.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIRECTORY"
}
trap cleanup EXIT

ARM64_ROOT="$WORK_DIRECTORY/arm64"
X86_64_ROOT="$WORK_DIRECTORY/x86_64"
UNIVERSAL_ROOT="$WORK_DIRECTORY/universal"
mkdir -p "$ARM64_ROOT" "$X86_64_ROOT" "$UNIVERSAL_ROOT"
"$DITTO_BIN" -x -k "$ARM64_APP_ZIP" "$ARM64_ROOT"
"$DITTO_BIN" -x -k "$X86_64_APP_ZIP" "$X86_64_ROOT"

validate_app_bundle() {
  local extraction_root="$1"
  local expected_architecture="$2"
  local app_bundle="$extraction_root/$APP_NAME"
  local executable="$app_bundle/$EXECUTABLE_RELATIVE_PATH"
  local entries=("$extraction_root"/*)

  [[ ${#entries[@]} -eq 1 && "${entries[0]}" == "$app_bundle" && -d "$app_bundle" && ! -L "$app_bundle" ]] || \
    fail "$expected_architecture archive must contain exactly one top-level $APP_NAME." 2
  [[ -f "$app_bundle/Contents/Info.plist" && ! -L "$app_bundle/Contents/Info.plist" ]] || \
    fail "$expected_architecture app has no regular Info.plist." 2
  [[ -f "$executable" && -x "$executable" && ! -L "$executable" ]] || \
    fail "$expected_architecture app has no executable Quill Cowork binary." 2
  if find "$app_bundle" \( -type l -o \( ! -type d ! -type f \) \) -print -quit | grep -q .; then
    fail "$expected_architecture app contains a symlink or special filesystem entry." 2
  fi
  while IFS= read -r -d '' path; do
    [[ "$path" != *$'\n'* && "$path" != *$'\r'* ]] || \
      fail "$expected_architecture app contains an unsafe path." 2
  done < <(find "$app_bundle" -print0)
  local architectures
  architectures="$("$LIPO_BIN" -archs "$executable")"
  [[ "$architectures" == "$expected_architecture" ]] || \
    fail "$expected_architecture source app must contain exactly one $expected_architecture executable slice; found: $architectures" 2
  "$CODESIGN_BIN" --verify --deep --strict --verbose=2 "$app_bundle"
}

validate_app_bundle "$ARM64_ROOT" "arm64"
validate_app_bundle "$X86_64_ROOT" "x86_64"

ARM64_APP="$ARM64_ROOT/$APP_NAME"
X86_64_APP="$X86_64_ROOT/$APP_NAME"
ARM64_INVENTORY="$WORK_DIRECTORY/arm64-inventory.txt"
X86_64_INVENTORY="$WORK_DIRECTORY/x86_64-inventory.txt"

bundle_inventory() {
  local app_bundle="$1"
  (
    cd "$app_bundle"
    find Contents \
      -path 'Contents/_CodeSignature' -prune -o \
      -path 'Contents/MacOS/Quill Cowork' -prune -o \
      -print | LC_ALL=C sort
  )
}

bundle_inventory "$ARM64_APP" > "$ARM64_INVENTORY"
bundle_inventory "$X86_64_APP" > "$X86_64_INVENTORY"
cmp -s "$ARM64_INVENTORY" "$X86_64_INVENTORY" || \
  fail "The arm64 and x86_64 app bundle inventories do not match." 2

while IFS= read -r relative_path; do
  arm_path="$ARM64_APP/$relative_path"
  intel_path="$X86_64_APP/$relative_path"
  if [[ -d "$arm_path" ]]; then
    [[ -d "$intel_path" ]] || fail "Bundle entry type differs: $relative_path" 2
  else
    [[ -f "$intel_path" ]] || fail "Bundle entry type differs: $relative_path" 2
    cmp -s "$arm_path" "$intel_path" || \
      fail "The arm64 and x86_64 app bundles differ at $relative_path." 2
  fi
done < "$ARM64_INVENTORY"

UNIVERSAL_APP="$UNIVERSAL_ROOT/$APP_NAME"
"$DITTO_BIN" "$ARM64_APP" "$UNIVERSAL_APP"
rm -rf "$UNIVERSAL_APP/Contents/_CodeSignature"
UNIVERSAL_EXECUTABLE="$UNIVERSAL_APP/$EXECUTABLE_RELATIVE_PATH"
MERGED_EXECUTABLE="$WORK_DIRECTORY/Quill Cowork"
"$LIPO_BIN" -create \
  "$ARM64_APP/$EXECUTABLE_RELATIVE_PATH" \
  "$X86_64_APP/$EXECUTABLE_RELATIVE_PATH" \
  -output "$MERGED_EXECUTABLE"
chmod 755 "$MERGED_EXECUTABLE"
mv "$MERGED_EXECUTABLE" "$UNIVERSAL_EXECUTABLE"
"$LIPO_BIN" "$UNIVERSAL_EXECUTABLE" -verify_arch arm64 x86_64

if [[ -n "$SIGNING_IDENTITY" ]]; then
  CODESIGN_ARGUMENTS=(
    --force
    --options runtime
    --timestamp
    --sign "$SIGNING_IDENTITY"
  )
  if [[ -n "$SIGNING_KEYCHAIN" ]]; then
    CODESIGN_ARGUMENTS+=(--keychain "$SIGNING_KEYCHAIN")
  fi
  "$CODESIGN_BIN" "${CODESIGN_ARGUMENTS[@]}" "$UNIVERSAL_APP"
else
  "$CODESIGN_BIN" --force --deep --sign - "$UNIVERSAL_APP"
fi
"$CODESIGN_BIN" --verify --deep --strict --verbose=2 "$UNIVERSAL_APP"

if [[ -n "$NOTARY_KEY_ID" || -n "$NOTARY_ISSUER_ID" || -n "$NOTARY_KEY_PATH" ]]; then
  [[ -n "$NOTARY_KEY_ID" && -n "$NOTARY_ISSUER_ID" && -n "$NOTARY_KEY_PATH" ]] || \
    fail "Universal installer notarization credentials must be configured together." 2
  [[ -f "$NOTARY_KEY_PATH" && ! -L "$NOTARY_KEY_PATH" ]] || \
    fail "Notarization private key does not exist: $NOTARY_KEY_PATH" 2
  NOTARY_ARCHIVE="$WORK_DIRECTORY/notarization-submission.zip"
  "$DITTO_BIN" -c -k --sequesterRsrc --keepParent "$UNIVERSAL_APP" "$NOTARY_ARCHIVE"
  "$XCRUN_BIN" notarytool submit "$NOTARY_ARCHIVE" \
    --key "$NOTARY_KEY_PATH" \
    --key-id "$NOTARY_KEY_ID" \
    --issuer "$NOTARY_ISSUER_ID" \
    --wait
  "$XCRUN_BIN" stapler staple "$UNIVERSAL_APP"
  "$XCRUN_BIN" stapler validate "$UNIVERSAL_APP"
  "$CODESIGN_BIN" --verify --deep --strict --verbose=2 "$UNIVERSAL_APP"
  "$SPCTL_BIN" --assess --type execute --verbose=2 "$UNIVERSAL_APP"
fi

"$ROOT_DIR/scripts/create-macos-disk-image.sh" \
  --app "$UNIVERSAL_APP" \
  --output "$OUTPUT_PATH"
"$ROOT_DIR/scripts/packaged-macos-relocation-smoke.sh" \
  --dmg "$OUTPUT_PATH" \
  --expected-architecture "$(uname -m)"

printf 'Quill Cowork universal macOS installer: %s\n' "$OUTPUT_PATH"
