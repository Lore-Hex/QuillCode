#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export QUILLCODE_EDITION=confidential
export QUILLCODE_MACOS_APP_OUTPUT_DIR="${QUILLCODE_MACOS_APP_OUTPUT_DIR:-$ROOT_DIR/.build/confidential-cowork-macos-app}"

exec "$ROOT_DIR/scripts/build-macos-app.sh" "$@"
