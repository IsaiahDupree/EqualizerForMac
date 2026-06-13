#!/bin/bash
#
# Import a Developer ID Application certificate (issued from our CSR) + its private key into the keychain,
# so it becomes a usable codesigning identity for Tools/package_and_notarize.sh / release.yml.
#
# Apple gates Developer ID certificate *creation* to the Account Holder (Xcode or developer.apple.com) —
# it cannot be created via the App Store Connect API. The keypair + CSR were generated locally
# (~/private_keys/sonance_devid_key.pem and sonance_devid.csr); once the cert is issued, run:
#
#   Tools/import_developer_id.sh ~/Downloads/developerID_application.cer
#
# (If you instead create the cert via Xcode → Settings → Accounts → Manage Certificates → ＋ Developer ID
#  Application, Xcode installs the key+cert for you and you do NOT need this script.)
set -euo pipefail

CER="${1:?usage: import_developer_id.sh <path/to/developerID_application.cer>}"
KEY="$HOME/private_keys/sonance_devid_key.pem"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

[ -f "$CER" ] || { echo "✗ cert not found: $CER"; exit 1; }
[ -f "$KEY" ] || { echo "✗ private key not found at $KEY (re-run the generate step)"; exit 1; }

echo "▸ Importing private key + certificate into the login keychain"
security import "$KEY" -k "$KEYCHAIN" -T /usr/bin/codesign 2>/dev/null || true
security import "$CER" -k "$KEYCHAIN" -T /usr/bin/codesign

echo "▸ Codesigning identities now available:"
if security find-identity -p codesigning -v | grep -i "Developer ID Application"; then
  echo ""
  echo "✓ Developer ID Application identity is installed. Use its full name as DEVELOPER_ID, e.g.:"
  echo "    export DEVELOPER_ID=\"\$(security find-identity -p codesigning -v | grep 'Developer ID Application' | head -1 | sed -E 's/.*\\\"(.*)\\\"/\\1/')\""
  echo "    ./Tools/package_and_notarize.sh"
else
  echo "✗ No Developer ID Application identity found — the .cer may not match the saved private key."
  exit 2
fi
