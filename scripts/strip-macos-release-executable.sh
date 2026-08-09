#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: strip-macos-release-executable.sh EXECUTABLE" >&2
  exit 2
fi

EXECUTABLE="$1"
STRIP_BIN="${QUILLCODE_MACOS_STRIP_BIN:-/usr/bin/strip}"

if [[ -L "$EXECUTABLE" || ! -f "$EXECUTABLE" || ! -x "$EXECUTABLE" ]]; then
  echo "Release executable must be a regular executable file: $EXECUTABLE" >&2
  exit 2
fi
if [[ ! -x "$STRIP_BIN" ]]; then
  echo "macOS strip tool is missing or not executable: $STRIP_BIN" >&2
  exit 2
fi

BEFORE_BYTES="$(wc -c < "$EXECUTABLE")"
BEFORE_BYTES=$((BEFORE_BYTES))
"$STRIP_BIN" -S -x "$EXECUTABLE"

if [[ -L "$EXECUTABLE" || ! -f "$EXECUTABLE" || ! -x "$EXECUTABLE" ]]; then
  echo "Stripping did not preserve a regular executable file: $EXECUTABLE" >&2
  exit 1
fi

AFTER_BYTES="$(wc -c < "$EXECUTABLE")"
AFTER_BYTES=$((AFTER_BYTES))
if [[ "$AFTER_BYTES" -le 0 || "$AFTER_BYTES" -gt "$BEFORE_BYTES" ]]; then
  echo "Stripping produced an invalid release executable size: $BEFORE_BYTES -> $AFTER_BYTES" >&2
  exit 1
fi

SAVED_BYTES=$((BEFORE_BYTES - AFTER_BYTES))
echo "Stripped release executable: $BEFORE_BYTES -> $AFTER_BYTES bytes ($SAVED_BYTES removed)." >&2
