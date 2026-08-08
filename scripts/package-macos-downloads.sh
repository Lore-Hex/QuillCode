#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${QUILLCODE_DOWNLOAD_DIST_DIR:-$ROOT_DIR/.build/downloads/macos}"
CONFIGURATION="${QUILLCODE_DOWNLOAD_CONFIGURATION:-release}"
VERSION="${QUILLCODE_BUILD_VERSION:-0.1.0}"
BUILD_NUMBER="${QUILLCODE_BUILD_NUMBER:-0}"
ARCH="$(uname -m)"
COMMIT="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || printf 'unknown')"
BUNDLE_ID="${QUILLCODE_MACOS_BUNDLE_ID:-co.lorehex.QuillCowork}"
MINIMUM_SYSTEM_VERSION="${QUILLCODE_MACOS_MINIMUM_SYSTEM_VERSION:-14.0}"
REPO="${GITHUB_REPOSITORY:-Lore-Hex/QuillCode}"
UPDATE_CHANNEL="${QUILLCODE_UPDATE_CHANNEL:-tester}"
SIGNING_IDENTITY="${QUILLCODE_MACOS_SIGNING_IDENTITY:-}"
SIGNING_TEAM_IDENTIFIER="${QUILLCODE_MACOS_SIGNING_TEAM_IDENTIFIER:-}"
SIGNING_KEYCHAIN="${QUILLCODE_MACOS_SIGNING_KEYCHAIN:-}"
SWIFT_DEBUG_INFO_FORMAT="${QUILLCODE_SWIFT_DEBUG_INFO_FORMAT:-}"
NOTARY_KEY_ID="${QUILLCODE_MACOS_NOTARY_KEY_ID:-}"
NOTARY_ISSUER_ID="${QUILLCODE_MACOS_NOTARY_ISSUER_ID:-}"
NOTARY_KEY_PATH="${QUILLCODE_MACOS_NOTARY_KEY_PATH:-}"
TESTER_MANIFEST_URL="${QUILLCODE_TESTER_UPDATE_MANIFEST_URL:-https://github.com/$REPO/releases/download/tester-latest/latest-tester-build.json}"
STABLE_MANIFEST_URL="${QUILLCODE_STABLE_UPDATE_MANIFEST_URL:-https://github.com/$REPO/releases/latest/download/latest-stable-build.json}"
ASSET_DIR="$DIST_DIR/assets"
APP_OUTPUT_DIR="$DIST_DIR/app"
CLI_ROOT="$DIST_DIR/cli"
CLI_DIR="$CLI_ROOT/quill-code-macOS-$ARCH"

if [[ "$UPDATE_CHANNEL" == "stable" ]]; then
  DEFAULT_UPDATE_MANIFEST_URL="$STABLE_MANIFEST_URL"
else
  DEFAULT_UPDATE_MANIFEST_URL="$TESTER_MANIFEST_URL"
fi

if [[ ! "$COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Download packaging requires an exact lowercase Git commit." >&2
  exit 2
fi
UPDATE_MANIFEST_URL="${QUILLCODE_UPDATE_MANIFEST_URL:-$DEFAULT_UPDATE_MANIFEST_URL}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "package-macos-downloads.sh must run on macOS." >&2
  exit 2
fi

if [[ "$UPDATE_CHANNEL" == "stable" ]]; then
  if [[ -z "$SIGNING_IDENTITY" || -z "$SIGNING_TEAM_IDENTIFIER" ]]; then
    echo "Stable macOS builds require a Developer ID signing identity and team identifier." >&2
    exit 2
  fi
  if [[ -z "$NOTARY_KEY_ID" || -z "$NOTARY_ISSUER_ID" || -z "$NOTARY_KEY_PATH" ]]; then
    echo "Stable macOS builds require App Store Connect notarization credentials." >&2
    exit 2
  fi
fi

cd "$ROOT_DIR"
rm -rf "$DIST_DIR"
mkdir -p "$ASSET_DIR" "$CLI_DIR"

echo "==> Packaging Quill Cowork macOS app ($ARCH, version $VERSION build $BUILD_NUMBER)"
APP_BUNDLE="$(
  QUILLCODE_MACOS_APP_VERSION="$VERSION" \
  QUILLCODE_MACOS_BUILD_NUMBER="$BUILD_NUMBER" \
  QUILLCODE_MACOS_BUILD_COMMIT="$COMMIT" \
  QUILLCODE_MACOS_BUNDLE_ID="$BUNDLE_ID" \
  QUILLCODE_MACOS_MINIMUM_SYSTEM_VERSION="$MINIMUM_SYSTEM_VERSION" \
  QUILLCODE_MACOS_UPDATE_CHANNEL="$UPDATE_CHANNEL" \
  QUILLCODE_MACOS_UPDATE_MANIFEST_URL="$UPDATE_MANIFEST_URL" \
  QUILLCODE_MACOS_UPDATE_STABLE_MANIFEST_URL="$STABLE_MANIFEST_URL" \
  QUILLCODE_MACOS_UPDATE_TESTER_MANIFEST_URL="$TESTER_MANIFEST_URL" \
  QUILLCODE_MACOS_SIGNING_IDENTITY="$SIGNING_IDENTITY" \
  QUILLCODE_MACOS_SIGNING_TEAM_IDENTIFIER="$SIGNING_TEAM_IDENTIFIER" \
  QUILLCODE_MACOS_SIGNING_KEYCHAIN="$SIGNING_KEYCHAIN" \
  QUILLCODE_MACOS_ADHOC_CODESIGN="${QUILLCODE_MACOS_ADHOC_CODESIGN:-1}" \
    "$ROOT_DIR/scripts/build-macos-app.sh" \
      --configuration "$CONFIGURATION" \
      --output "$APP_OUTPUT_DIR"
)"

APP_ZIP="$ASSET_DIR/Quill-Cowork-macOS-$ARCH.zip"
APP_DMG="$ASSET_DIR/Quill-Cowork-macOS-$ARCH.dmg"
PERFORMANCE_MANIFEST="$ASSET_DIR/Quill-Cowork-macOS-$ARCH-PERFORMANCE.json"
NOTARIZED=false
CODESIGN_KIND="ad-hoc"
if [[ -n "$SIGNING_IDENTITY" ]]; then
  CODESIGN_KIND="developer-id"
  if [[ -n "$NOTARY_KEY_ID" && -n "$NOTARY_ISSUER_ID" && -n "$NOTARY_KEY_PATH" ]]; then
    if [[ ! -f "$NOTARY_KEY_PATH" ]]; then
      echo "Notarization private key does not exist: $NOTARY_KEY_PATH" >&2
      exit 2
    fi
    NOTARY_ARCHIVE="$DIST_DIR/notarization-submission.zip"
    ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$NOTARY_ARCHIVE"
    xcrun notarytool submit "$NOTARY_ARCHIVE" \
      --key "$NOTARY_KEY_PATH" \
      --key-id "$NOTARY_KEY_ID" \
      --issuer "$NOTARY_ISSUER_ID" \
      --wait
    xcrun stapler staple "$APP_BUNDLE"
    xcrun stapler validate "$APP_BUNDLE"
    codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
    spctl --assess --type execute --verbose=2 "$APP_BUNDLE"
    NOTARIZED=true
    rm -f "$NOTARY_ARCHIVE"
  fi
fi
"$ROOT_DIR/scripts/packaged-macos-performance-smoke.sh" \
  --app "$APP_BUNDLE" \
  --manifest "$PERFORMANCE_MANIFEST"
"$ROOT_DIR/scripts/create-macos-disk-image.sh" \
  --app "$APP_BUNDLE" \
  --output "$APP_DMG"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$APP_ZIP"

echo "==> Packaging quill-code macOS CLI ($ARCH)"
SWIFT_BUILD_ARGUMENTS=(--configuration "$CONFIGURATION" --product quill-code)
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
swift build "${SWIFT_BUILD_ARGUMENTS[@]}" >&2
BIN_DIR="$(swift build "${SWIFT_BUILD_ARGUMENTS[@]}" --show-bin-path)"
cp "$BIN_DIR/quill-code" "$CLI_DIR/quill-code"
chmod 755 "$CLI_DIR/quill-code"
cat > "$CLI_DIR/README.txt" <<README
Quill Cowork CLI for macOS $ARCH

Install:
  sudo install -m 755 quill-code /usr/local/bin/quill-code

Smoke test:
  quill-code "run whoami"
README

CLI_TARBALL="$ASSET_DIR/quill-code-macOS-$ARCH.tar.gz"
tar -C "$CLI_ROOT" -czf "$CLI_TARBALL" "$(basename "$CLI_DIR")"

cat > "$ASSET_DIR/BUILD_INFO.txt" <<INFO
product=Quill Cowork
platform=macOS
arch=$ARCH
version=$VERSION
build=$BUILD_NUMBER
commit=$COMMIT
createdAt=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
configuration=$CONFIGURATION
bundleIdentifier=$BUNDLE_ID
minimumSystemVersion=$MINIMUM_SYSTEM_VERSION
updateChannel=$UPDATE_CHANNEL
updateManifestURL=$UPDATE_MANIFEST_URL
stableUpdateManifestURL=$STABLE_MANIFEST_URL
testerUpdateManifestURL=$TESTER_MANIFEST_URL
installer=Quill-Cowork-macOS-$ARCH.dmg
app=Quill-Cowork-macOS-$ARCH.zip
performance=Quill-Cowork-macOS-$ARCH-PERFORMANCE.json
cli=quill-code-macOS-$ARCH.tar.gz
codesign=$CODESIGN_KIND
signingTeamIdentifier=${SIGNING_TEAM_IDENTIFIER:-none}
notarized=$NOTARIZED
INFO

(
  cd "$ASSET_DIR"
  shasum -a 256 Quill-Cowork-macOS-"$ARCH".dmg \
    Quill-Cowork-macOS-"$ARCH".zip \
    Quill-Cowork-macOS-"$ARCH"-PERFORMANCE.json \
    quill-code-macOS-"$ARCH".tar.gz BUILD_INFO.txt \
    > "Quill-Cowork-macOS-$ARCH-SHASUMS256.txt"
)

echo "Quill Cowork macOS download assets:"
find "$ASSET_DIR" -maxdepth 1 -type f -print | sort
