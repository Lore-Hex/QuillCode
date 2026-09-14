#!/usr/bin/env bash
set -euo pipefail
: "${SIGN_IDENTITY:?}" "${NOTARY_KEY_ID:?}" "${NOTARY_ISSUER_ID:?}" "${DESKTOP_SHA:?}"
cd "$GITHUB_WORKSPACE/desktop/packages/desktop"
export OPENCODE_CHANNEL=prod
export CSC_NAME="${SIGN_IDENTITY#Developer ID Application: }"
export CSC_KEYCHAIN="$RUNNER_TEMP/trcc-signing.keychain-db"
export APPLE_API_KEY="$RUNNER_TEMP/AuthKey.p8"
export APPLE_API_KEY_ID="$NOTARY_KEY_ID"
export APPLE_API_ISSUER="$NOTARY_ISSUER_ID"
arch="$(node -p process.arch)"
[[ "$arch" = arm64 || "$arch" = x64 ]]
bunx --no-install electron-builder --mac dir --config electron-builder.config.ts --publish never
app="$(find dist -maxdepth 2 -name 'Trusted Cowork.app' -type d)"
test -n "$app"
codesign --verify --deep --strict --verbose=2 "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
root="$RUNNER_TEMP/trusted-cowork-dmg"
mkdir "$root"
ditto "$app" "$root/Trusted Cowork.app"
ln -s /Applications "$root/Applications"
version="$(node -p "require('./package.json').version")"
dmg="$PWD/dist/Trusted-Cowork-$version-mac-$arch.dmg"
hdiutil create -quiet -fs HFS+ -volname 'Trusted Cowork' -srcfolder "$root" "$dmg"
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$dmg"
xcrun notarytool submit "$dmg" --key "$APPLE_API_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" --wait
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
codesign --verify --verbose=2 "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
cd dist
shasum -a 256 "$(basename "$dmg")" > "$(basename "$dmg").sha256"
node -e 'require("fs").writeFileSync("source-provenance.json", JSON.stringify({desktop:process.env.DESKTOP_SHA,workflow:process.env.GITHUB_SHA,arch:process.arch,channel:"prod"},null,2)+"\n")'
