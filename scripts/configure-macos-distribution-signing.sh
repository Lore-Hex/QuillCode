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

SIGNING_ROOT="$RUNNER_TEMP/quill-cowork-signing"
CERTIFICATE_PATH="$SIGNING_ROOT/developer-id.p12"
NOTARY_KEY_PATH="$SIGNING_ROOT/AuthKey_${NOTARY_KEY_ID}.p8"
KEYCHAIN_PATH="$SIGNING_ROOT/build.keychain-db"
KEYCHAIN_PASSWORD="$(openssl rand -hex 24)"

mkdir -p "$SIGNING_ROOT"
chmod 700 "$SIGNING_ROOT"
printf '%s' "$CERTIFICATE_BASE64" | openssl base64 -d -A > "$CERTIFICATE_PATH"
printf '%s' "$NOTARY_KEY_BASE64" | openssl base64 -d -A > "$NOTARY_KEY_PATH"
chmod 600 "$CERTIFICATE_PATH" "$NOTARY_KEY_PATH"

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
security find-identity -v -p codesigning "$KEYCHAIN_PATH" | grep -F "$SIGNING_IDENTITY" >/dev/null

{
  echo "QUILLCODE_MACOS_SIGNING_IDENTITY=$SIGNING_IDENTITY"
  echo "QUILLCODE_MACOS_SIGNING_TEAM_IDENTIFIER=$SIGNING_TEAM_IDENTIFIER"
  echo "QUILLCODE_MACOS_SIGNING_KEYCHAIN=$KEYCHAIN_PATH"
  echo "QUILLCODE_MACOS_SIGNING_CERTIFICATE_PATH=$CERTIFICATE_PATH"
  echo "QUILLCODE_MACOS_NOTARY_KEY_ID=$NOTARY_KEY_ID"
  echo "QUILLCODE_MACOS_NOTARY_ISSUER_ID=$NOTARY_ISSUER_ID"
  echo "QUILLCODE_MACOS_NOTARY_KEY_PATH=$NOTARY_KEY_PATH"
} >> "$GITHUB_ENV"

echo "Configured Developer ID signing and App Store Connect notarization credentials."
