#!/bin/bash
#
# Sonance EQ — Mac App Store build → archive → export (.pkg) → (optional) upload to App Store Connect.
# The MAS path: sandboxed (Release-MAS config), public audio-capture permission (no private TCC SPI).
# The driverless process-tap loop is VERIFIED to run under the App Sandbox — see Tools/sandbox_tap_probe.swift.
#
# Like Tools/package_and_notarize.sh, this preflights and tells you exactly what's missing instead of
# failing cryptically. It does NOT create the App Store Connect record or the IAP — those are one-time
# manual steps (see docs/APP-STORE.md).
#
# Prerequisites:
#   1. Apple Developer Program membership + a paid App Store Connect account.
#   2. An "Apple Distribution" (or "3rd Party Mac Developer Application") cert + a Mac App Store
#      provisioning profile for com.isaiahdupree.SonanceEQ in your keychain.
#   3. The App Store Connect app record + the non-consumable IAP already created (docs/APP-STORE.md).
#   4. A real RevenueCat public key pasted into LicenseConfig (else the app ships Pro-unlocked).
#
# Config via env:
#   TEAM_ID         your Apple Developer team id (required for export signing)
#   ASC_KEY_ID      App Store Connect API key id   (reuse ~/private_keys/AuthKey_<KEYID>.p8)
#   ASC_ISSUER      App Store Connect API issuer id
#   ASC_KEY         path to the .p8                (default ~/private_keys/AuthKey_$ASC_KEY_ID.p8)
#
# Usage:  Tools/build_mas.sh            # archive + export the .pkg
#         Tools/build_mas.sh --upload   # …and upload to App Store Connect
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

SCHEME="SonanceEQ"
CONFIG="Release-MAS"
ARCHIVE="build/SonanceEQ-MAS.xcarchive"
EXPORT_DIR="build/mas"
PKG="$EXPORT_DIR/SonanceEQ.pkg"
UPLOAD=0
[ "${1:-}" = "--upload" ] && UPLOAD=1

echo "▸ Preflight"
missing=0
command -v xcodegen >/dev/null || { echo "  ✗ xcodegen not found"; missing=1; }
if [ -z "${TEAM_ID:-}" ]; then
  echo "  ✗ TEAM_ID not set (needed to sign the App Store archive)."
  missing=1
fi
# Distribution cert present?
if ! security find-identity -v -p codesigning 2>/dev/null | grep -qiE "Apple Distribution|3rd Party Mac Developer Application"; then
  echo "  ✗ No 'Apple Distribution' / '3rd Party Mac Developer Application' cert in the keychain."
  echo "    Create one at developer.apple.com → Certificates, then download + install it."
  missing=1
fi
# The live key is injected per-build via the Release-MAS REVENUECAT_PUBLIC_KEY build setting → Info.plist
# → LicenseConfig (NOT hardcoded in LicenseConfig.swift anymore). An empty value ships the mock store.
if ! grep -qE 'REVENUECAT_PUBLIC_KEY:\s*"(appl_|mac_)[A-Za-z0-9]+"' project.yml; then
  echo "  ⚠ No live Release-MAS REVENUECAT_PUBLIC_KEY in project.yml — the build will ship the MOCK store"
  echo "    (Pro unlockable with no real charge). Run Tools/rc/set_key.py <appl_…> before the paid release."
fi
ASC_KEY="${ASC_KEY:-$HOME/private_keys/AuthKey_${ASC_KEY_ID:-}.p8}"
if [ "$UPLOAD" = "1" ]; then
  { [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER:-}" ] && [ -f "$ASC_KEY" ]; } || {
    echo "  ✗ Upload needs ASC_KEY_ID + ASC_ISSUER + the .p8 at \$ASC_KEY ($ASC_KEY)."; missing=1; }
fi
[ "$missing" = "1" ] && { echo "✗ Resolve the above, then re-run."; exit 1; }
echo "  ✓ preflight passed"

echo "▸ Generating project"
xcodegen generate >/dev/null

echo "▸ Archiving ($CONFIG)"
rm -rf "$ARCHIVE"
xcodebuild archive \
  -project SonanceEQ.xcodeproj -scheme "$SCHEME" -configuration "$CONFIG" \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" \
  DEVELOPMENT_TEAM="$TEAM_ID"

echo "▸ Exporting App Store package"
rm -rf "$EXPORT_DIR"
# Manual signing → the export must name the certificate + map the bundle id to its MAS profile,
# otherwise xcodebuild errors "requires a provisioning profile".
cat > build/ExportOptions-MAS.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>destination</key><string>export</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>3rd Party Mac Developer Application</string>
  <key>installerSigningCertificate</key><string>3rd Party Mac Developer Installer</string>
  <key>provisioningProfiles</key><dict>
    <key>com.isaiahdupree.SonanceEQ</key><string>Sonance EQ MAS</string>
  </dict>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist build/ExportOptions-MAS.plist
echo "  ✓ package: $PKG"

if [ "$UPLOAD" = "1" ]; then
  echo "▸ Uploading to App Store Connect"
  xcrun altool --upload-app --type macos --file "$PKG" \
    --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER"
  echo "  ✓ uploaded — finish in App Store Connect (screenshots, IAP review, submit)."
else
  echo "▸ Not uploading. To upload: Tools/build_mas.sh --upload  (or drop $PKG into Transporter.app)."
fi
