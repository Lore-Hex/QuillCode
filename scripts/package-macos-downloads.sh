#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${QUILLCODE_DOWNLOAD_DIST_DIR:-$ROOT_DIR/.build/downloads/macos}"
CONFIGURATION="${QUILLCODE_DOWNLOAD_CONFIGURATION:-release}"
VERSION="${QUILLCODE_BUILD_VERSION:-0.1.0}"
BUILD_NUMBER="${QUILLCODE_BUILD_NUMBER:-0}"
ARCH="$(uname -m)"
COMMIT="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || printf 'unknown')"
ASSET_DIR="$DIST_DIR/assets"
APP_OUTPUT_DIR="$DIST_DIR/app"
CLI_ROOT="$DIST_DIR/cli"
CLI_DIR="$CLI_ROOT/quill-code-macOS-$ARCH"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "package-macos-downloads.sh must run on macOS." >&2
  exit 2
fi

cd "$ROOT_DIR"
rm -rf "$DIST_DIR"
mkdir -p "$ASSET_DIR" "$CLI_DIR"

echo "==> Packaging QuillCode macOS app ($ARCH, version $VERSION build $BUILD_NUMBER)"
APP_BUNDLE="$(
  QUILLCODE_MACOS_APP_VERSION="$VERSION" \
  QUILLCODE_MACOS_BUILD_NUMBER="$BUILD_NUMBER" \
  QUILLCODE_MACOS_ADHOC_CODESIGN="${QUILLCODE_MACOS_ADHOC_CODESIGN:-1}" \
    "$ROOT_DIR/scripts/build-macos-app.sh" \
      --configuration "$CONFIGURATION" \
      --output "$APP_OUTPUT_DIR"
)"

APP_ZIP="$ASSET_DIR/QuillCode-macOS-$ARCH.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$APP_ZIP"

echo "==> Packaging quill-code macOS CLI ($ARCH)"
swift build --configuration "$CONFIGURATION" --product quill-code >&2
BIN_DIR="$(swift build --configuration "$CONFIGURATION" --product quill-code --show-bin-path)"
cp "$BIN_DIR/quill-code" "$CLI_DIR/quill-code"
chmod 755 "$CLI_DIR/quill-code"
cat > "$CLI_DIR/README.txt" <<README
QuillCode CLI for macOS $ARCH

Install:
  sudo install -m 755 quill-code /usr/local/bin/quill-code

Smoke test:
  quill-code "run whoami"
README

CLI_TARBALL="$ASSET_DIR/quill-code-macOS-$ARCH.tar.gz"
tar -C "$CLI_ROOT" -czf "$CLI_TARBALL" "$(basename "$CLI_DIR")"

cat > "$ASSET_DIR/BUILD_INFO.txt" <<INFO
product=QuillCode
platform=macOS
arch=$ARCH
version=$VERSION
build=$BUILD_NUMBER
commit=$COMMIT
createdAt=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
configuration=$CONFIGURATION
app=QuillCode-macOS-$ARCH.zip
cli=quill-code-macOS-$ARCH.tar.gz
codesign=ad-hoc
notarized=false
INFO

(
  cd "$ASSET_DIR"
  shasum -a 256 QuillCode-macOS-"$ARCH".zip quill-code-macOS-"$ARCH".tar.gz BUILD_INFO.txt \
    > "QuillCode-macOS-$ARCH-SHASUMS256.txt"
)

echo "QuillCode macOS download assets:"
find "$ASSET_DIR" -maxdepth 1 -type f -print | sort
