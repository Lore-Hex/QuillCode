#!/usr/bin/env bash
set -euo pipefail

export LC_ALL=C
umask 077

OPENSSL_BIN="${OPENSSL_BIN:-openssl}"
TEMP_ROOT="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
MAX_CERTIFICATE_BASE64_BYTES=$((256 * 1024))
MAX_NOTARY_KEY_BASE64_BYTES=$((64 * 1024))
MINIMUM_CERTIFICATE_VALIDITY_SECONDS=$((7 * 24 * 60 * 60))

fail() {
  echo "$*" >&2
  exit 2
}

REQUIRED_CREDENTIALS=(
  APPLE_DEVELOPER_ID_CERTIFICATE_BASE64
  APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD
  APPLE_DEVELOPER_ID_APPLICATION_IDENTITY
  APPLE_TEAM_ID
  APPLE_NOTARY_KEY_ID
  APPLE_NOTARY_ISSUER_ID
  APPLE_NOTARY_PRIVATE_KEY_BASE64
)

missing_credentials=()
for credential_name in "${REQUIRED_CREDENTIALS[@]}"; do
  if [[ -z "${!credential_name:-}" ]]; then
    missing_credentials+=("$credential_name")
  fi
done
if (( ${#missing_credentials[@]} > 0 )); then
  fail "Missing Apple distribution credentials: ${missing_credentials[*]}"
fi

CERTIFICATE_BASE64="$APPLE_DEVELOPER_ID_CERTIFICATE_BASE64"
SIGNING_IDENTITY="$APPLE_DEVELOPER_ID_APPLICATION_IDENTITY"
TEAM_IDENTIFIER="$APPLE_TEAM_ID"
NOTARY_KEY_IDENTIFIER="$APPLE_NOTARY_KEY_ID"
NOTARY_ISSUER_IDENTIFIER="$APPLE_NOTARY_ISSUER_ID"
NOTARY_KEY_BASE64="$APPLE_NOTARY_PRIVATE_KEY_BASE64"

command -v "$OPENSSL_BIN" >/dev/null 2>&1 || fail "OpenSSL is required for Apple credential validation."
[[ -d "$TEMP_ROOT" ]] || fail "Apple credential validation requires an existing temporary directory."
[[ ! -L "$TEMP_ROOT" ]] || fail "Apple credential validation refuses a symbolic-link temporary directory."

if [[ ! "$TEAM_IDENTIFIER" =~ ^[A-Z0-9]{10}$ ]]; then
  fail "APPLE_TEAM_ID must be a 10-character uppercase Apple team identifier."
fi
if [[ ! "$NOTARY_KEY_IDENTIFIER" =~ ^[A-Z0-9]{10}$ ]]; then
  fail "APPLE_NOTARY_KEY_ID must be a 10-character uppercase App Store Connect key identifier."
fi
notary_issuer_pattern='^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-'
notary_issuer_pattern+='[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$'
if [[ ! "$NOTARY_ISSUER_IDENTIFIER" =~ $notary_issuer_pattern ]]; then
  fail "APPLE_NOTARY_ISSUER_ID must be an App Store Connect issuer UUID."
fi
if (( ${#SIGNING_IDENTITY} > 256 )) ||
   [[ "$SIGNING_IDENTITY" == *$'\n'* || "$SIGNING_IDENTITY" == *$'\r'* ]]; then
  fail "APPLE_DEVELOPER_ID_APPLICATION_IDENTITY is malformed."
fi
identity_prefix="Developer ID Application: "
identity_suffix=" ($TEAM_IDENTIFIER)"
identity_is_fingerprint=false
if [[ "$SIGNING_IDENTITY" =~ ^[0-9A-Fa-f]{40}$ ]]; then
  identity_is_fingerprint=true
elif [[ "$SIGNING_IDENTITY" != "$identity_prefix"*"$identity_suffix" ]]; then
  fail "APPLE_DEVELOPER_ID_APPLICATION_IDENTITY must name a Developer ID Application identity owned by APPLE_TEAM_ID."
fi
if [[ "$identity_is_fingerprint" == "false" ]]; then
  identity_owner="${SIGNING_IDENTITY#"$identity_prefix"}"
  identity_owner="${identity_owner%"$identity_suffix"}"
  [[ -n "$identity_owner" ]] || fail "APPLE_DEVELOPER_ID_APPLICATION_IDENTITY is missing its owner name."
fi

if (( ${#CERTIFICATE_BASE64} > MAX_CERTIFICATE_BASE64_BYTES )); then
  fail "APPLE_DEVELOPER_ID_CERTIFICATE_BASE64 exceeds the credential size limit."
fi
if (( ${#NOTARY_KEY_BASE64} > MAX_NOTARY_KEY_BASE64_BYTES )); then
  fail "APPLE_NOTARY_PRIVATE_KEY_BASE64 exceeds the credential size limit."
fi
is_canonical_base64() {
  local value="$1"
  (( ${#value} % 4 == 0 )) && [[ "$value" =~ ^[A-Za-z0-9+/]+={0,2}$ ]]
}
is_canonical_base64 "$CERTIFICATE_BASE64" ||
  fail "APPLE_DEVELOPER_ID_CERTIFICATE_BASE64 is not canonical base64."
is_canonical_base64 "$NOTARY_KEY_BASE64" ||
  fail "APPLE_NOTARY_PRIVATE_KEY_BASE64 is not canonical base64."

WORK_DIRECTORY="$(mktemp -d "$TEMP_ROOT/quill-cowork-apple-preflight.XXXXXX")"
cleanup() {
  rm -rf -- "$WORK_DIRECTORY"
}
trap cleanup EXIT

CERTIFICATE_ARCHIVE="$WORK_DIRECTORY/developer-id.p12"
CERTIFICATE="$WORK_DIRECTORY/developer-id.pem"
CERTIFICATE_PRIVATE_KEY="$WORK_DIRECTORY/developer-id-private-key.pem"
CERTIFICATE_PUBLIC_KEY="$WORK_DIRECTORY/developer-id-public-key.pem"
PRIVATE_PUBLIC_KEY="$WORK_DIRECTORY/private-public-key.pem"
NOTARY_PRIVATE_KEY="$WORK_DIRECTORY/AuthKey_${NOTARY_KEY_IDENTIFIER}.p8"
NOTARY_PARAMETERS="$WORK_DIRECTORY/notary-parameters.der"
P256_NAMED_PARAMETERS="$WORK_DIRECTORY/p256-named-parameters.der"
P256_EXPLICIT_PARAMETERS="$WORK_DIRECTORY/p256-explicit-parameters.der"

if ! printf '%s' "$CERTIFICATE_BASE64" | "$OPENSSL_BIN" base64 -d -A > "$CERTIFICATE_ARCHIVE" ||
   [[ ! -s "$CERTIFICATE_ARCHIVE" ]]; then
  fail "The Developer ID certificate archive is not valid base64 credential material."
fi
if ! printf '%s' "$NOTARY_KEY_BASE64" | "$OPENSSL_BIN" base64 -d -A > "$NOTARY_PRIVATE_KEY" ||
   [[ ! -s "$NOTARY_PRIVATE_KEY" ]]; then
  fail "The App Store Connect private key is not valid base64 credential material."
fi
if [[ "$("$OPENSSL_BIN" base64 -A -in "$CERTIFICATE_ARCHIVE")" != "$CERTIFICATE_BASE64" ]]; then
  fail "APPLE_DEVELOPER_ID_CERTIFICATE_BASE64 is not canonical base64."
fi
if [[ "$("$OPENSSL_BIN" base64 -A -in "$NOTARY_PRIVATE_KEY")" != "$NOTARY_KEY_BASE64" ]]; then
  fail "APPLE_NOTARY_PRIVATE_KEY_BASE64 is not canonical base64."
fi
chmod 600 "$CERTIFICATE_ARCHIVE" "$NOTARY_PRIVATE_KEY"

extract_pkcs12() {
  if "$OPENSSL_BIN" pkcs12 "$@" >/dev/null 2>&1; then
    return 0
  fi
  "$OPENSSL_BIN" pkcs12 -legacy "$@" >/dev/null 2>&1
}

pkey_check_supported=false
if "$OPENSSL_BIN" pkey -help 2>&1 | grep -Eq -- '(^|[[:space:]])-check([[:space:]]|$)'; then
  pkey_check_supported=true
fi
validate_private_key() {
  local key_path="$1"
  if [[ "$pkey_check_supported" == "true" ]]; then
    "$OPENSSL_BIN" pkey -in "$key_path" -check -noout >/dev/null 2>&1
    return
  fi
  "$OPENSSL_BIN" rsa -in "$key_path" -check -noout >/dev/null 2>&1 ||
    "$OPENSSL_BIN" ec -in "$key_path" -text -noout >/dev/null 2>&1
}

if ! extract_pkcs12 \
  -in "$CERTIFICATE_ARCHIVE" -clcerts -nokeys \
  -passin env:APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD -out "$CERTIFICATE"; then
  fail "The Developer ID certificate archive or its password is invalid."
fi
if ! extract_pkcs12 \
  -in "$CERTIFICATE_ARCHIVE" -nocerts -nodes \
  -passin env:APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD -out "$CERTIFICATE_PRIVATE_KEY"; then
  fail "The Developer ID certificate archive does not contain a readable private key."
fi
chmod 600 "$CERTIFICATE" "$CERTIFICATE_PRIVATE_KEY"

if ! "$OPENSSL_BIN" x509 -in "$CERTIFICATE" -noout >/dev/null 2>&1; then
  fail "The Developer ID certificate archive does not contain a readable certificate."
fi
if ! "$OPENSSL_BIN" x509 \
  -in "$CERTIFICATE" \
  -checkend "$MINIMUM_CERTIFICATE_VALIDITY_SECONDS" \
  -noout >/dev/null 2>&1; then
  fail "The Developer ID certificate is expired or expires within seven days."
fi

certificate_subject="$("$OPENSSL_BIN" x509 -in "$CERTIFICATE" -noout -subject -nameopt multiline)"
certificate_common_name="$(
  printf '%s\n' "$certificate_subject" |
    sed -n 's/^[[:space:]]*commonName[[:space:]]*=[[:space:]]*//p'
)"
certificate_team_identifier="$(
  printf '%s\n' "$certificate_subject" |
    sed -n 's/^[[:space:]]*organizationalUnitName[[:space:]]*=[[:space:]]*//p' |
    head -n 1
)"
if [[ "$certificate_common_name" != "$identity_prefix"*"$identity_suffix" ||
      "$certificate_team_identifier" != "$TEAM_IDENTIFIER" ]]; then
  fail "The Developer ID certificate is not owned by APPLE_TEAM_ID."
fi
certificate_owner="${certificate_common_name#"$identity_prefix"}"
certificate_owner="${certificate_owner%"$identity_suffix"}"
[[ -n "$certificate_owner" ]] || fail "The Developer ID certificate is missing its owner name."
certificate_fingerprint="$(
  "$OPENSSL_BIN" x509 -in "$CERTIFICATE" -noout -fingerprint -sha1 |
    sed 's/^[^=]*=//; s/://g' |
    tr '[:lower:]' '[:upper:]'
)"
configured_fingerprint="$(printf '%s' "$SIGNING_IDENTITY" | tr '[:lower:]' '[:upper:]')"
if [[ "$identity_is_fingerprint" == "true" &&
      "$certificate_fingerprint" != "$configured_fingerprint" ]]; then
  fail "The Developer ID certificate fingerprint does not match APPLE_DEVELOPER_ID_APPLICATION_IDENTITY."
fi
if [[ "$identity_is_fingerprint" == "false" &&
      "$certificate_common_name" != "$SIGNING_IDENTITY" ]]; then
  fail "The Developer ID certificate common name does not match APPLE_DEVELOPER_ID_APPLICATION_IDENTITY."
fi

certificate_usage="$("$OPENSSL_BIN" x509 -in "$CERTIFICATE" -noout -text 2>/dev/null || true)"
if [[ "$certificate_usage" != *"Code Signing"* ]]; then
  fail "The Developer ID certificate is not valid for code signing."
fi
if ! validate_private_key "$CERTIFICATE_PRIVATE_KEY"; then
  fail "The Developer ID certificate private key is invalid."
fi
if ! "$OPENSSL_BIN" x509 -in "$CERTIFICATE" -pubkey -noout > "$CERTIFICATE_PUBLIC_KEY" 2>/dev/null ||
   ! "$OPENSSL_BIN" pkey -in "$CERTIFICATE_PRIVATE_KEY" -pubout > "$PRIVATE_PUBLIC_KEY" 2>/dev/null ||
   ! cmp -s "$CERTIFICATE_PUBLIC_KEY" "$PRIVATE_PUBLIC_KEY"; then
  fail "The Developer ID certificate and private key do not match."
fi

if ! grep -Fqx -- "-----BEGIN PRIVATE KEY-----" "$NOTARY_PRIVATE_KEY"; then
  fail "The App Store Connect private key must use unencrypted PKCS#8 PEM format."
fi
if ! validate_private_key "$NOTARY_PRIVATE_KEY"; then
  fail "The App Store Connect private key is invalid."
fi
if ! "$OPENSSL_BIN" ec \
  -in "$NOTARY_PRIVATE_KEY" -param_out -outform DER \
  -out "$NOTARY_PARAMETERS" >/dev/null 2>&1 ||
   ! "$OPENSSL_BIN" ecparam \
  -name prime256v1 -param_enc named_curve -outform DER \
  -out "$P256_NAMED_PARAMETERS" >/dev/null 2>&1 ||
   ! "$OPENSSL_BIN" ecparam \
  -name prime256v1 -param_enc explicit -outform DER \
  -out "$P256_EXPLICIT_PARAMETERS" >/dev/null 2>&1; then
  fail "The App Store Connect private key parameters could not be validated."
fi
if ! cmp -s "$NOTARY_PARAMETERS" "$P256_NAMED_PARAMETERS" &&
   ! cmp -s "$NOTARY_PARAMETERS" "$P256_EXPLICIT_PARAMETERS"; then
  fail "The App Store Connect private key must use the P-256 elliptic curve."
fi

echo "Validated Apple Developer ID and notarization credential material."
