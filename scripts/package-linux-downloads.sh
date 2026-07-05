#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${QUILLCODE_DOWNLOAD_DIST_DIR:-$ROOT_DIR/.build/downloads/linux}"
CONFIGURATION="${QUILLCODE_DOWNLOAD_CONFIGURATION:-release}"
VERSION="${QUILLCODE_BUILD_VERSION:-0.1.0}"
BUILD_NUMBER="${QUILLCODE_BUILD_NUMBER:-0}"
ARCH="$(uname -m)"
COMMIT="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || printf 'unknown')"
ASSET_DIR="$DIST_DIR/assets"
CLI_ROOT="$DIST_DIR/cli"
CLI_DIR="$CLI_ROOT/quill-code-linux-$ARCH"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "package-linux-downloads.sh must run on Linux." >&2
  exit 2
fi

cd "$ROOT_DIR"
rm -rf "$DIST_DIR"
mkdir -p "$ASSET_DIR" "$CLI_DIR"

echo "==> Packaging quill-code Linux CLI ($ARCH, version $VERSION build $BUILD_NUMBER)"
swift build --configuration "$CONFIGURATION" --product quill-code >&2
BIN_DIR="$(swift build --configuration "$CONFIGURATION" --product quill-code --show-bin-path)"
cp "$BIN_DIR/quill-code" "$CLI_DIR/quill-code"
chmod 755 "$CLI_DIR/quill-code"
cat > "$CLI_DIR/README.txt" <<README
QuillCode CLI for Linux $ARCH

Install:
  sudo install -m 755 quill-code /usr/local/bin/quill-code

Smoke test:
  quill-code "run whoami"
README

CLI_TARBALL="$ASSET_DIR/quill-code-linux-$ARCH.tar.gz"
tar -C "$CLI_ROOT" -czf "$CLI_TARBALL" "$(basename "$CLI_DIR")"

cat > "$ASSET_DIR/BUILD_INFO-linux-$ARCH.txt" <<INFO
product=QuillCode
platform=Linux
arch=$ARCH
version=$VERSION
build=$BUILD_NUMBER
commit=$COMMIT
createdAt=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
configuration=$CONFIGURATION
cli=quill-code-linux-$ARCH.tar.gz
INFO

(
  cd "$ASSET_DIR"
  sha256sum quill-code-linux-"$ARCH".tar.gz BUILD_INFO-linux-"$ARCH".txt \
    > "quill-code-linux-$ARCH-SHASUMS256.txt"
)

echo "QuillCode Linux download assets:"
find "$ASSET_DIR" -maxdepth 1 -type f -print | sort
