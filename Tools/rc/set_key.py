#!/usr/bin/env python3
"""set_key.py — set the RevenueCat public SDK key for the App Store (Release-MAS) build. The key is
injected per-build via `REVENUECAT_PUBLIC_KEY` in project.yml → Info.plist → LicenseConfig, so Debug/Release
stay on the mock store (no network) for dev + tests while only the App Store build goes live.
  python3 Tools/rc/set_key.py appl_XXXXXXXXXXXXXXXXXXXX
"""
import re, sys, os, subprocess

PROJECT = os.path.expanduser("~/Documents/Software/EqualizerForMac/project.yml")

def main():
    if len(sys.argv) < 2 or not sys.argv[1].startswith(("appl_", "mac_")):
        sys.exit("usage: set_key.py <appl_… public SDK key>")
    key = sys.argv[1]
    src = open(PROJECT).read()
    # Replace the Release-MAS REVENUECAT_PUBLIC_KEY value (the one with a real/empty appl_ string after it).
    new = re.sub(r'(REVENUECAT_PUBLIC_KEY:\s*")(appl_[A-Za-z0-9]*|mac_[A-Za-z0-9]*)(")',
                 lambda m: m.group(1) + key + m.group(3), src, count=1)
    if new == src:
        sys.exit("✗ couldn't find a Release-MAS REVENUECAT_PUBLIC_KEY line to update")
    open(PROJECT, "w").write(new)
    subprocess.run(["xcodegen", "generate"], cwd=os.path.dirname(PROJECT),
                   capture_output=True)
    print(f"✓ Release-MAS REVENUECAT_PUBLIC_KEY set ({key[:9]}…) + project regenerated — live store in MAS build")

if __name__ == "__main__":
    main()
