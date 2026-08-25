#!/usr/bin/env bash
set -euo pipefail

CERTIFICATE_BASE64="${APPLE_DEVELOPER_ID_CERTIFICATE_BASE64:-}"
CERTIFICATE_PASSWORD="${APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD:-}"
SIGNING_IDENTITY="${APPLE_DEVELOPER_ID_APPLICATION_IDENTITY:-}"
SIGNING_TEAM_IDENTIFIER="${APPLE_TEAM_ID:-}"
NOTARY_KEY_ID="${APPLE_NOTARY_KEY_ID:-}"
NOTARY_ISSUER_ID="${APPLE_NOTARY_ISSUER_ID:-}"
NOTARY_KEY_BASE64="${APPLE_NOTARY_PRIVATE_KEY_BASE64:-}"

VALUES=(
  "$CERTIFICATE_BASE64"
  "$CERTIFICATE_PASSWORD"
  "$SIGNING_IDENTITY"
  "$SIGNING_TEAM_IDENTIFIER"
  "$NOTARY_KEY_ID"
  "$NOTARY_ISSUER_ID"
  "$NOTARY_KEY_BASE64"
)
CONFIGURED_VALUES=0
for value in "${VALUES[@]}"; do
  if [[ -n "$value" ]]; then
    CONFIGURED_VALUES=$((CONFIGURED_VALUES + 1))
  fi
done

if [[ "$CONFIGURED_VALUES" == 0 ]]; then
  echo "Apple distribution signing is not configured; tester builds will use ad-hoc signing."
  exit 0
fi
if [[ "$CONFIGURED_VALUES" != "${#VALUES[@]}" ]]; then
  echo "Apple distribution signing secrets are only partially configured." >&2
  exit 2
fi
if [[ -z "${RUNNER_TEMP:-}" || -z "${GITHUB_ENV:-}" ]]; then
  echo "RUNNER_TEMP and GITHUB_ENV are required on the signing runner." >&2
  exit 2
fi
if [[ ! "$SIGNING_TEAM_IDENTIFIER" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "APPLE_TEAM_ID must be a 10-character uppercase Apple team identifier." >&2
  exit 2
fi
if [[ ! "$NOTARY_KEY_ID" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "APPLE_NOTARY_KEY_ID must be a 10-character uppercase App Store Connect key identifier." >&2
  exit 2
fi
if [[ ! "$NOTARY_ISSUER_ID" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]; then
  echo "APPLE_NOTARY_ISSUER_ID must be an App Store Connect issuer UUID." >&2
  exit 2
fi

SIGNING_ROOT="$RUNNER_TEMP/quill-cowork-signing"
CERTIFICATE_PATH="$SIGNING_ROOT/developer-id.p12"
NOTARY_KEY_PATH="$SIGNING_ROOT/AuthKey_${NOTARY_KEY_ID}.p8"
KEYCHAIN_PATH="$SIGNING_ROOT/build.keychain-db"
KEYCHAIN_PASSWORD="$(openssl rand -hex 24)"

cleanup_failed_configuration() {
  local status=$?
  trap - EXIT
  set +e
  if [[ -e "$KEYCHAIN_PATH" ]]; then
    security delete-keychain "$KEYCHAIN_PATH" >/dev/null 2>&1
  fi
  rm -rf "$SIGNING_ROOT"
  exit "$status"
}
trap cleanup_failed_configuration EXIT

mkdir -p "$SIGNING_ROOT"
chmod 700 "$SIGNING_ROOT"
printf '%s' "$CERTIFICATE_BASE64" | openssl base64 -d -A > "$CERTIFICATE_PATH"
printf '%s' "$NOTARY_KEY_BASE64" | openssl base64 -d -A > "$NOTARY_KEY_PATH"
chmod 600 "$CERTIFICATE_PATH" "$NOTARY_KEY_PATH"
if [[ ! -s "$CERTIFICATE_PATH" || ! -s "$NOTARY_KEY_PATH" ]]; then
  echo "Apple signing credentials decoded to an empty file." >&2
  exit 2
fi

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$CERTIFICATE_PATH" \
  -k "$KEYCHAIN_PATH" \
  -P "$CERTIFICATE_PASSWORD" \
  -T /usr/bin/codesign \
  -T /usr/bin/security
security set-key-partition-list \
  -S apple-tool:,apple:,codesign: \
  -s \
  -k "$KEYCHAIN_PASSWORD" \
  "$KEYCHAIN_PATH"
# codesign resolves --keychain against the search list, not the path alone, so
# an imported identity that find-identity reports is still unusable until its
# keychain joins the list: signing fails with "The specified item could not be
# found in the keychain". Prepend ours and keep the runner's existing entries.
# Read through a command substitution, not a process substitution: bash does
# not propagate a process-substitution failure through set -e, so a transient
# read failure would silently yield an empty list and the write below would
# replace the runner's whole search list with just this temporary keychain.
if ! KEYCHAIN_LIST_OUTPUT="$(security list-keychains -d user)"; then
  echo "Could not read the keychain search list; refusing to replace it." >&2
  exit 2
fi
EXISTING_KEYCHAINS=()
while IFS= read -r keychain_line; do
  keychain_line="${keychain_line#"${keychain_line%%[![:space:]]*}"}"
  keychain_line="${keychain_line%"${keychain_line##*[![:space:]]}"}"
  keychain_line="${keychain_line#\"}"
  keychain_line="${keychain_line%\"}"
  if [[ -n "$keychain_line" ]]; then
    EXISTING_KEYCHAINS+=("$keychain_line")
  fi
done <<< "$KEYCHAIN_LIST_OUTPUT"
if [[ ${#EXISTING_KEYCHAINS[@]} -eq 0 ]]; then
  echo "The keychain search list came back empty; refusing to replace it." >&2
  exit 2
fi
security list-keychains -d user -s "$KEYCHAIN_PATH" "${EXISTING_KEYCHAINS[@]}"
IDENTITY_OUTPUT="$(security find-identity -v -p codesigning "$KEYCHAIN_PATH")"
IDENTITY_LINE=""
while IFS= read -r line; do
  if [[ "$line" == *"$SIGNING_IDENTITY"* ]]; then
    IDENTITY_LINE="$line"
    break
  fi
done <<< "$IDENTITY_OUTPUT"
if [[ -z "$IDENTITY_LINE" ]]; then
  echo "The imported keychain does not contain the configured Developer ID identity." >&2
  exit 2
fi
if [[ "$IDENTITY_LINE" != *"($SIGNING_TEAM_IDENTIFIER)"* ]]; then
  echo "The configured Apple team does not own the imported Developer ID identity." >&2
  exit 2
fi

{
  echo "QUILLCODE_MACOS_SIGNING_IDENTITY=$SIGNING_IDENTITY"
  echo "QUILLCODE_MACOS_SIGNING_TEAM_IDENTIFIER=$SIGNING_TEAM_IDENTIFIER"
  echo "QUILLCODE_MACOS_SIGNING_KEYCHAIN=$KEYCHAIN_PATH"
  echo "QUILLCODE_MACOS_SIGNING_CERTIFICATE_PATH=$CERTIFICATE_PATH"
  echo "QUILLCODE_MACOS_NOTARY_KEY_ID=$NOTARY_KEY_ID"
  echo "QUILLCODE_MACOS_NOTARY_ISSUER_ID=$NOTARY_ISSUER_ID"
  echo "QUILLCODE_MACOS_NOTARY_KEY_PATH=$NOTARY_KEY_PATH"
} >> "$GITHUB_ENV"

trap - EXIT
echo "Configured Developer ID signing and App Store Connect notarization credentials."
