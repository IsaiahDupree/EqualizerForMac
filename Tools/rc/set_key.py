#!/usr/bin/env python3
"""set_key.py — paste the RevenueCat public SDK key into LicenseConfig so the app switches from the mock
store to the live RevenueCat store. The mock store is active only while the key equals the sentinel.
  python3 Tools/rc/set_key.py appl_XXXXXXXXXXXXXXXXXXXX
"""
import re, sys, os

CONFIG = os.path.expanduser("~/Documents/Software/EqualizerForMac/Sources/SonanceEQ/Licensing/LicenseConfig.swift")

def main():
    if len(sys.argv) < 2 or not sys.argv[1].startswith(("appl_", "mac_")):
        sys.exit("usage: set_key.py <appl_… public SDK key>")
    key = sys.argv[1]
    src = open(CONFIG).read()
    new = re.sub(r'static let revenueCatPublicAPIKey = \S+',
                 f'static let revenueCatPublicAPIKey = "{key}"', src)
    if new == src:
        sys.exit("✗ couldn't find revenueCatPublicAPIKey line")
    open(CONFIG, "w").write(new)
    print(f"✓ LicenseConfig.revenueCatPublicAPIKey set ({key[:9]}…) — live store active on next build")

if __name__ == "__main__":
    main()
