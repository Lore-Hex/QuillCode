#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${QUILLCODE_DOWNLOAD_DIST_DIR:-$ROOT_DIR/.build/downloads/macos}"
CONFIGURATION="${QUILLCODE_DOWNLOAD_CONFIGURATION:-release}"
EDITION="${QUILLCODE_EDITION:-standard}"
VERSION="${QUILLCODE_BUILD_VERSION:-0.1.0}"
BUILD_NUMBER="${QUILLCODE_BUILD_NUMBER:-0}"
ARCH="$(uname -m)"
COMMIT="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || printf 'unknown')"
case "$EDITION" in
  standard)
    DEFAULT_PRODUCT_NAME="Quill Cowork"
    DEFAULT_ASSET_PREFIX="Quill-Cowork"
    DEFAULT_BUNDLE_ID="co.lorehex.QuillCowork"
    DEFAULT_TESTER_TAG="tester-latest"
    DEFAULT_TESTER_MANIFEST_NAME="latest-tester-build.json"
    DEFAULT_STABLE_TAG=""
    DEFAULT_STABLE_MANIFEST_NAME="latest-stable-build.json"
    ;;
  confidential)
    DEFAULT_PRODUCT_NAME="Confidential Cowork"
    DEFAULT_ASSET_PREFIX="Confidential-Cowork"
    DEFAULT_BUNDLE_ID="com.trustedrouter.ConfidentialCowork"
    DEFAULT_TESTER_TAG="confidential-cowork-latest"
    DEFAULT_TESTER_MANIFEST_NAME="latest-confidential-cowork-build.json"
    DEFAULT_STABLE_TAG="confidential-cowork-stable"
    DEFAULT_STABLE_MANIFEST_NAME="latest-confidential-cowork-stable-build.json"
    ;;
  *)
    echo "QUILLCODE_EDITION must be standard or confidential." >&2
    exit 2
    ;;
esac
PRODUCT_NAME="${QUILLCODE_PRODUCT_NAME:-$DEFAULT_PRODUCT_NAME}"
ASSET_PREFIX="${QUILLCODE_ASSET_PREFIX:-$DEFAULT_ASSET_PREFIX}"
BUNDLE_ID="${QUILLCODE_MACOS_BUNDLE_ID:-$DEFAULT_BUNDLE_ID}"
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
TESTER_TAG="${QUILLCODE_TESTER_RELEASE_TAG:-$DEFAULT_TESTER_TAG}"
TESTER_MANIFEST_NAME="${QUILLCODE_TESTER_MANIFEST_NAME:-$DEFAULT_TESTER_MANIFEST_NAME}"
STABLE_TAG="${QUILLCODE_STABLE_RELEASE_TAG:-$DEFAULT_STABLE_TAG}"
STABLE_MANIFEST_NAME="${QUILLCODE_STABLE_MANIFEST_NAME:-$DEFAULT_STABLE_MANIFEST_NAME}"
TESTER_MANIFEST_URL="${QUILLCODE_TESTER_UPDATE_MANIFEST_URL:-https://github.com/$REPO/releases/download/$TESTER_TAG/$TESTER_MANIFEST_NAME}"
if [[ -n "$STABLE_TAG" ]]; then
  DEFAULT_STABLE_MANIFEST_URL="https://github.com/$REPO/releases/download/$STABLE_TAG/$STABLE_MANIFEST_NAME"
else
  DEFAULT_STABLE_MANIFEST_URL="https://github.com/$REPO/releases/latest/download/$STABLE_MANIFEST_NAME"
fi
STABLE_MANIFEST_URL="${QUILLCODE_STABLE_UPDATE_MANIFEST_URL:-$DEFAULT_STABLE_MANIFEST_URL}"
ASSET_DIR="$DIST_DIR/assets"
APP_OUTPUT_DIR="$DIST_DIR/app"
CLI_ROOT="$DIST_DIR/cli"
CLI_DIR="$CLI_ROOT/quill-code-macOS-$ARCH"
BUILD_INFO="$ASSET_DIR/BUILD_INFO-macOS-$ARCH.txt"

case "$ARCH" in
  arm64|x86_64) ;;
  *)
    echo "Unsupported macOS download architecture: $ARCH" >&2
    exit 2
    ;;
esac

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
if [[ -n "$SIGNING_IDENTITY" && ( -z "$NOTARY_KEY_ID" || -z "$NOTARY_ISSUER_ID" || -z "$NOTARY_KEY_PATH" ) ]]; then
  echo "Developer ID signing requires notarization; Gatekeeper blocks a signed but unnotarized download." >&2
  exit 2
fi

cd "$ROOT_DIR"
rm -rf "$DIST_DIR"
mkdir -p "$ASSET_DIR" "$CLI_DIR"

echo "==> Packaging $PRODUCT_NAME macOS app ($ARCH, version $VERSION build $BUILD_NUMBER)"
APP_BUNDLE="$(
  QUILLCODE_EDITION="$EDITION" \
  QUILLCODE_MACOS_APP_NAME="$PRODUCT_NAME" \
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

APP_ZIP="$ASSET_DIR/$ASSET_PREFIX-macOS-$ARCH.zip"
APP_DMG="$ASSET_DIR/$ASSET_PREFIX-macOS-$ARCH.dmg"
PERFORMANCE_MANIFEST="$ASSET_DIR/$ASSET_PREFIX-macOS-$ARCH-PERFORMANCE.json"
APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/$PRODUCT_NAME"
APP_EXECUTABLE_SIZE_BYTES="$(stat -f '%z' "$APP_EXECUTABLE")"
SYMBOLS_STRIPPED=false
if [[ "$CONFIGURATION" == "release" ]]; then
  SYMBOLS_STRIPPED=true
fi
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
"$ROOT_DIR/scripts/packaged-macos-relocation-smoke.sh" \
  --product-name "$PRODUCT_NAME" \
  --dmg "$APP_DMG" \
  --expected-architecture "$ARCH"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$APP_ZIP"

CLI_TARBALL=""
if [[ "$EDITION" == "standard" ]]; then
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
  cp "$BIN_DIR/quill-code-process-supervisor" "$CLI_DIR/quill-code-process-supervisor"
  chmod 755 "$CLI_DIR/quill-code"
  chmod 755 "$CLI_DIR/quill-code-process-supervisor"
  cat > "$CLI_DIR/README.txt" <<README
$PRODUCT_NAME CLI for macOS $ARCH

Install:
  sudo install -m 755 quill-code /usr/local/bin/quill-code
  sudo install -m 755 quill-code-process-supervisor /usr/local/bin/quill-code-process-supervisor

Smoke test:
  quill-code "run whoami"
README

  CLI_TARBALL="$ASSET_DIR/quill-code-macOS-$ARCH.tar.gz"
  tar -C "$CLI_ROOT" -czf "$CLI_TARBALL" "$(basename "$CLI_DIR")"
fi

cat > "$BUILD_INFO" <<INFO
product=$PRODUCT_NAME
edition=$EDITION
platform=macOS
arch=$ARCH
version=$VERSION
build=$BUILD_NUMBER
commit=$COMMIT
createdAt=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
configuration=$CONFIGURATION
symbolsStripped=$SYMBOLS_STRIPPED
executableSizeBytes=$APP_EXECUTABLE_SIZE_BYTES
bundleIdentifier=$BUNDLE_ID
minimumSystemVersion=$MINIMUM_SYSTEM_VERSION
updateChannel=$UPDATE_CHANNEL
updateManifestURL=$UPDATE_MANIFEST_URL
stableUpdateManifestURL=$STABLE_MANIFEST_URL
testerUpdateManifestURL=$TESTER_MANIFEST_URL
installer=$ASSET_PREFIX-macOS-$ARCH.dmg
app=$ASSET_PREFIX-macOS-$ARCH.zip
performance=$ASSET_PREFIX-macOS-$ARCH-PERFORMANCE.json
codesign=$CODESIGN_KIND
signingTeamIdentifier=${SIGNING_TEAM_IDENTIFIER:-none}
notarized=$NOTARIZED
INFO

(
  cd "$ASSET_DIR"
  CHECKSUM_INPUTS=(
    "$ASSET_PREFIX-macOS-$ARCH.dmg"
    "$ASSET_PREFIX-macOS-$ARCH.zip"
    "$ASSET_PREFIX-macOS-$ARCH-PERFORMANCE.json"
    "$(basename "$BUILD_INFO")"
  )
  if [[ -n "$CLI_TARBALL" ]]; then
    CHECKSUM_INPUTS+=("$(basename "$CLI_TARBALL")")
  fi
  shasum -a 256 "${CHECKSUM_INPUTS[@]}" > "$ASSET_PREFIX-macOS-$ARCH-SHASUMS256.txt"
)

echo "$PRODUCT_NAME macOS download assets:"
find "$ASSET_DIR" -maxdepth 1 -type f -print | sort
