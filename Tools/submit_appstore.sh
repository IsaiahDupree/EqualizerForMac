#!/bin/bash
#
# Sonance EQ — Mac App Store build → .pkg → upload to App Store Connect.
# Reuses your account-level App Store Connect API key (the same one EverReach uses); no new account setup.
#
# ⚠️ Read docs/RELEASE.md first. The Mac App Store path is the project's #1 rejection risk (Guideline 2.5.1):
#    the MAS build must run SANDBOXED and use the PUBLIC audio-capture permission flow (ENABLE_TCC_SPI OFF),
#    and system-wide tap capture under the App Store sandbox is unverified. Lead with DIRECT distribution
#    (Tools/package_and_notarize.sh). This script automates the upload mechanics for when you tackle MAS.
#
# Required (env or defaults):
#   ASC_API_KEY_ID    App Store Connect API key id      (reuse your existing account-level key)
#   ASC_API_ISSUER    API key issuer id                 (App Store Connect → Users and Access → Integrations)
#   ASC_APP_ID        the Sonance EQ app record's Apple ID (created once in App Store Connect)
#   DIST_IDENTITY     "Apple Distribution: Your Name (TEAMID)"
#   PROVISIONING_PROFILE_NAME   a Mac App Store provisioning profile for com.isaiahdupree.SonanceEQ
#   DEVELOPMENT_TEAM  your Team ID
# The API key .p8 must live at ~/private_keys/AuthKey_${ASC_API_KEY_ID}.p8 (altool finds it there).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

APP_NAME="SonanceEQ"
ARCHIVE="build/$APP_NAME.xcarchive"
EXPORT_DIR="build/appstore"
PKG="$EXPORT_DIR/$APP_NAME.pkg"

echo "▸ Preflight"
missing=0
for var in ASC_API_KEY_ID ASC_API_ISSUER ASC_APP_ID DIST_IDENTITY PROVISIONING_PROFILE_NAME DEVELOPMENT_TEAM; do
  if [ -z "${!var:-}" ]; then echo "  ✗ $var not set"; missing=1; fi
done
KEYFILE="$HOME/private_keys/AuthKey_${ASC_API_KEY_ID:-MISSING}.p8"
[ -f "$KEYFILE" ] || { echo "  ✗ API key not found at $KEYFILE"; missing=1; }
if [ "$missing" = "1" ]; then
  echo ""
  echo "Pending Apple setup for the Mac App Store path. Once a Sonance EQ app record + Apple Distribution"
  echo "cert + MAS provisioning profile exist, set the vars above and re-run. See docs/RELEASE.md."
  exit 2
fi

echo "▸ Generating project"
xcodegen generate

echo "▸ Archiving (sandboxed, public permission flow — NO ENABLE_TCC_SPI)"
xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
  -archivePath "$ARCHIVE" \
  -destination 'generic/platform=macOS' \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$DIST_IDENTITY" \
  PROVISIONING_PROFILE_SPECIFIER="$PROVISIONING_PROFILE_NAME" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  ENABLE_APP_SANDBOX=YES \
  ENABLE_HARDENED_RUNTIME=NO \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS="" \
  clean archive

echo "▸ Exporting .pkg (app-store)"
cat > build/ExportOptions-appstore.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store</string>
  <key>teamID</key><string>${DEVELOPMENT_TEAM}</string>
  <key>signingStyle</key><string>manual</string>
  <key>destination</key><string>export</string>
</dict></plist>
PLIST
rm -rf "$EXPORT_DIR"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist build/ExportOptions-appstore.plist

echo "▸ Validating + uploading to App Store Connect"
xcrun altool --validate-app -f "$PKG" -t macos --apiKey "$ASC_API_KEY_ID" --apiIssuer "$ASC_API_ISSUER"
xcrun altool --upload-app  -f "$PKG" -t macos --apiKey "$ASC_API_KEY_ID" --apiIssuer "$ASC_API_ISSUER"

echo "✓ Uploaded $PKG to App Store Connect (app id $ASC_APP_ID). Finish the submission in App Store Connect."
