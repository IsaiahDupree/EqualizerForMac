#!/usr/bin/env python3
"""metadata.py — fill the App Store listing text via the ASC API: the app-level info (subtitle, privacy
policy, category) and the version localization (description, keywords, promo text, what's new, URLs).
Idempotent PATCHes. Run after the app record exists.
  python3 Tools/asc/metadata.py
"""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from api import api, get_app

LOCALE = "en-US"

SUBTITLE = "System-wide audio equalizer"
DESCRIPTION = (
    "Sonance EQ equalizes everything your Mac plays — Spotify, Safari and Chrome, Zoom, games, even "
    "system sounds — before it reaches your speakers or headphones. No driver, no kernel extension, no "
    "reboot.\n\n"
    "FEATURES\n"
    "• System-wide EQ via Core Audio process taps (macOS 14.4+)\n"
    "• Parametric editor with a live response curve — drag bands to shape frequency, gain, Q and type\n"
    "• Filter shapes: peaking, low/high shelf, variable-slope low/high cut (6–96 dB/oct), notch, "
    "band-pass, all-pass\n"
    "• 8,850 AutoEq headphone corrections — search your model and apply instantly\n"
    "• Linear-Phase mode (zero phase distortion) and Mid-Side EQ\n"
    "• Per-app EQ, an app volume mixer with per-app output routing, and an audio recorder\n"
    "• Preset import/export, bypass A/B, master preamp\n\n"
    "Built for people who care how their Mac sounds. Audio is processed live on your device and is "
    "never sent anywhere."
)
KEYWORDS = "equalizer,EQ,audio,sound,parametric,headphones,AutoEq,bass,treble,music,mixer,system audio"
PROMO = "Tune everything your Mac plays — a precise system-wide equalizer with 8,850 headphone presets."
WHATS_NEW = "Initial release of Sonance EQ."
SUPPORT_URL = "https://github.com/IsaiahDupree/EqualizerForMac"
MARKETING_URL = "https://github.com/IsaiahDupree/EqualizerForMac"
PRIVACY_URL = "https://github.com/IsaiahDupree/EqualizerForMac/blob/main/PRIVACY.md"

def patch(path, type_, id_, attrs):
    api("PATCH", path, {"data": {"type": type_, "id": id_, "attributes": attrs}})

def fill_app_info(app_id):
    infos = api("GET", f"/v1/apps/{app_id}/appInfos").get("data", [])
    for info in infos:
        locs = api("GET", f"/v1/appInfos/{info['id']}/appInfoLocalizations").get("data", [])
        loc = next((l for l in locs if l["attributes"]["locale"] == LOCALE), None)
        if loc:
            patch(f"/v1/appInfoLocalizations/{loc['id']}", "appInfoLocalizations", loc["id"],
                  {"subtitle": SUBTITLE, "privacyPolicyUrl": PRIVACY_URL})
            print(f"  ✓ app info: subtitle + privacy URL ({LOCALE})")

def fill_version(app_id):
    versions = api("GET", f"/v1/apps/{app_id}/appStoreVersions?limit=10").get("data", [])
    if not versions:
        print("  ⚠ no app store version yet"); return
    ver = versions[0]
    print(f"  · version {ver['attributes'].get('versionString')} [{ver['attributes'].get('appStoreState')}]")
    locs = api("GET", f"/v1/appStoreVersions/{ver['id']}/appStoreVersionLocalizations").get("data", [])
    loc = next((l for l in locs if l["attributes"]["locale"] == LOCALE), None)
    if not loc:
        d = api("POST", "/v1/appStoreVersionLocalizations", {"data": {
            "type": "appStoreVersionLocalizations",
            "attributes": {"locale": LOCALE},
            "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": ver["id"]}}}}})
        loc = d["data"]
    attrs = {"description": DESCRIPTION, "keywords": KEYWORDS, "promotionalText": PROMO,
             "supportUrl": SUPPORT_URL, "marketingUrl": MARKETING_URL}
    # whatsNew only applies to updates, not the first release (read-only for v1).
    if ver["attributes"].get("versionString") not in (None, "1.0"):
        attrs["whatsNew"] = WHATS_NEW
    patch(f"/v1/appStoreVersionLocalizations/{loc['id']}", "appStoreVersionLocalizations", loc["id"], attrs)
    print(f"  ✓ version localization: description, keywords, promo, URLs ({LOCALE})")
    return ver["id"]

if __name__ == "__main__":
    app = get_app()
    if not app: sys.exit("✗ app record missing")
    print(f"App {app['attributes']['name']} ({app['id']})")
    fill_app_info(app["id"])
    fill_version(app["id"])
    print("✓ metadata filled — review at App Store Connect")
