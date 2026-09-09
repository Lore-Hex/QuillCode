#!/usr/bin/env bash
set -euo pipefail
: "${SIGN_IDENTITY:?}" "${NOTARY_KEY_ID:?}" "${NOTARY_ISSUER_ID:?}" "${DESKTOP_SHA:?}" "${RUNTIME_SHA:?}"
cd "$GITHUB_WORKSPACE/desktop"
export CSC_NAME="$SIGN_IDENTITY"
export CSC_KEYCHAIN="$RUNNER_TEMP/trcc-signing.keychain-db"
npx --no-install electron-builder --mac dir --universal --publish never \
  -c.forceCodeSigning=true -c.mac.notarize=false \
  -c.mac.binaries=Contents/Resources/resources/runtime/tr-cowork
app="$PWD/release/mac-universal/TR Confidential Cowork.app"
test -d "$app"
codesign --verify --deep --strict --verbose=2 "$app"
lipo -verify_arch arm64 x86_64 "$app/Contents/Resources/resources/runtime/tr-cowork"
"$app/Contents/Resources/resources/runtime/tr-cowork" --version
notarize() {
  xcrun notarytool submit "$1" --key "$RUNNER_TEMP/AuthKey.p8" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" --wait
}
ditto -c -k --keepParent "$app" "$RUNNER_TEMP/trcc-desktop.zip"
notarize "$RUNNER_TEMP/trcc-desktop.zip"
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
root="$RUNNER_TEMP/trcc-desktop-dmg"
mkdir "$root"
ditto "$app" "$root/TR Confidential Cowork.app"
ln -s /Applications "$root/Applications"
dmg="$PWD/release/TR-Confidential-Cowork-Desktop-universal.dmg"
hdiutil create -quiet -fs HFS+ -volname 'TR Confidential Cowork' -srcfolder "$root" "$dmg"
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$dmg"
notarize "$dmg"
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
codesign --verify --verbose=2 "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
cd release
shasum -a 256 "$(basename "$dmg")" > "$(basename "$dmg").sha256"
node -e 'require("fs").writeFileSync("source-provenance.json", JSON.stringify({desktop:process.env.DESKTOP_SHA,runtime:process.env.RUNTIME_SHA,workflow:process.env.GITHUB_SHA},null,2)+"\n")'
