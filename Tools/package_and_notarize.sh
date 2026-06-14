#!/bin/bash
#
# Sonance EQ — Developer ID build → codesign → notarize → staple → DMG.
# This is the DIRECT-distribution path (Developer ID + hardened runtime). It is ready to run once you
# have registered with Apple; until then it will tell you exactly what's missing.
#
# Prerequisites (these are the "register with Apple" steps that are currently mocked elsewhere):
#   1. Apple Developer Program membership.
#   2. A "Developer ID Application" signing certificate in your login keychain.
#   3. A notarytool keychain profile OR an app-specific password.
#
# Configure via environment variables:
#   DEVELOPER_ID   e.g. "Developer ID Application: Isaiah Dupree (TEAMID)"
#   NOTARY_PROFILE name of a stored notarytool profile  (xcrun notarytool store-credentials NOTARY_PROFILE …)
#     — or —
#   APPLE_ID / TEAM_ID / APP_PASSWORD   for one-off notarization
#
# Usage:  Tools/package_and_notarize.sh
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

APP_NAME="SonanceEQ"
SCHEME="SonanceEQ"
BUILD_DIR="build/release"
APP_PATH="build/$APP_NAME.app"      # NOTE: must live OUTSIDE $BUILD_DIR (which holds the build products)
DMG_PATH="build/Sonance-EQ.dmg"

echo "▸ Preflight"
missing=0
if [ -z "${DEVELOPER_ID:-}" ]; then
  echo "  ✗ DEVELOPER_ID not set (need a 'Developer ID Application' certificate from Apple)."
  missing=1
fi
have_api_key=0
if [ -n "${NOTARY_KEY:-}" ] && [ -n "${NOTARY_KEY_ID:-}" ] && [ -n "${NOTARY_ISSUER:-}" ]; then have_api_key=1; fi
if [ "$have_api_key" = "0" ] && [ -z "${NOTARY_PROFILE:-}" ] \
   && { [ -z "${APPLE_ID:-}" ] || [ -z "${TEAM_ID:-}" ] || [ -z "${APP_PASSWORD:-}" ]; }; then
  echo "  ✗ Notarization creds not set. Provide ONE of:"
  echo "      • App Store Connect API key: NOTARY_KEY (path to .p8) + NOTARY_KEY_ID + NOTARY_ISSUER  ← reuse your ~/private_keys/AuthKey_<KEYID>.p8"
  echo "      • a stored notarytool profile: NOTARY_PROFILE"
  echo "      • Apple ID: APPLE_ID + TEAM_ID + APP_PASSWORD (app-specific password)"
  missing=1
fi
if [ "$missing" = "1" ]; then
  echo ""
  echo "These are the Apple-registration steps still pending. Once you have them, re-run this script."
  echo "Build/signing scaffolding is in place; nothing else in the app blocks release."
  exit 2
fi

echo "▸ Generating project + building Release (Developer ID, hardened runtime)"
xcodegen generate
xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$SCHEME" -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$BUILD_DIR/dd" \
  CODE_SIGN_IDENTITY="$DEVELOPER_ID" \
  CODE_SIGN_STYLE=Manual \
  ENABLE_HARDENED_RUNTIME=YES \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" \
  clean build

PRODUCT="$BUILD_DIR/dd/Build/Products/Release/$APP_NAME.app"
[ -d "$PRODUCT" ] || { echo "✗ build product not found at $PRODUCT"; exit 1; }
rm -rf "$APP_PATH"
cp -R "$PRODUCT" "$APP_PATH"

echo "▸ Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "▸ Building DMG"
rm -f "$DMG_PATH"
hdiutil create -volname "Sonance EQ" -srcfolder "$APP_PATH" -ov -format UDZO "$DMG_PATH"
codesign --sign "$DEVELOPER_ID" --timestamp "$DMG_PATH"

echo "▸ Notarizing (this can take a few minutes)"
if [ -n "${NOTARY_KEY:-}" ] && [ -n "${NOTARY_KEY_ID:-}" ] && [ -n "${NOTARY_ISSUER:-}" ]; then
  xcrun notarytool submit "$DMG_PATH" --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" --wait
elif [ -n "${NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
else
  xcrun notarytool submit "$DMG_PATH" --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APP_PASSWORD" --wait
fi

echo "▸ Stapling"
xcrun stapler staple "$DMG_PATH"
xcrun stapler staple "$APP_PATH"

echo "✓ Done → $DMG_PATH (notarized + stapled, ready to distribute)"
