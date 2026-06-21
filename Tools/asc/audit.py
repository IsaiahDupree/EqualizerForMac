#!/usr/bin/env python3
"""audit.py — pre-submission readiness check: queries every field App Store Connect validates at submit
time and prints a ✅/❌ checklist. Read-only.  python3 Tools/asc/audit.py
"""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from api import api, get_app

def ok(b): return "✅" if b else "❌"
miss = []
def check(label, cond, detail=""):
    if not cond: miss.append(label)
    print(f"  {ok(cond)} {label}{(' — ' + str(detail)) if detail else ''}")
def safe(fn, default=None):
    try: return fn()
    except Exception: return default

a = get_app(); aid = a["id"]; at = a["attributes"]
print(f"APP  {at['name']}  ({at.get('bundleId')})")
check("content rights declaration", at.get("contentRightsDeclaration"), at.get("contentRightsDeclaration"))

info = api("GET", f"/v1/apps/{aid}/appInfos")["data"][0]
ia = info["attributes"]
pc = api("GET", f"/v1/appInfos/{info['id']}/relationships/primaryCategory").get("data")
check("primary category", pc)
check("age rating computed", ia.get("appStoreAgeRating"), ia.get("appStoreAgeRating"))
for loc in api("GET", f"/v1/appInfos/{info['id']}/appInfoLocalizations")["data"]:
    if loc["attributes"]["locale"] == "en-US":
        la = loc["attributes"]
        check("app name", la.get("name"), la.get("name"))
        check("subtitle", la.get("subtitle"), la.get("subtitle"))
        check("privacy policy URL", la.get("privacyPolicyUrl"))

v = api("GET", f"/v1/apps/{aid}/appStoreVersions?limit=3")["data"][0]; vid = v["id"]; va = v["attributes"]
print(f"VERSION {va['versionString']}  state={va['appStoreState']}")
b = api("GET", f"/v1/appStoreVersions/{vid}/relationships/build").get("data")
check("build attached", b)
for loc in api("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations")["data"]:
    if loc["attributes"]["locale"] == "en-US":
        la = loc["attributes"]
        check("description", la.get("description"), f"{len(la.get('description') or '')} chars")
        check("keywords", la.get("keywords"))
        sets = api("GET", f"/v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")["data"]
        n = 0
        for s in sets:
            n += len(api("GET", f"/v1/appScreenshotSets/{s['id']}/appScreenshots")["data"])
        check("screenshots", n > 0, f"{n} uploaded")

check("price schedule (Free counts)", safe(lambda: api("GET", f"/v1/apps/{aid}/appPriceSchedule").get("data")))
print("  ℹ︎ app privacy ('Data Not Collected') — set+published via the web UI (not cleanly readable via API)")
for p in api("GET", f"/v1/apps/{aid}/inAppPurchasesV2?limit=10")["data"]:
    st = p["attributes"]["state"]
    check(f"IAP {p['attributes']['productId']}", st in ("READY_TO_SUBMIT", "APPROVED"), st)
if b:
    bd = api("GET", f"/v1/builds/{b['id']}")["data"]["attributes"]
    check("export compliance (encryption)", bd.get("usesNonExemptEncryption") is not None,
          f"usesNonExemptEncryption={bd.get('usesNonExemptEncryption')}")

print("\n" + ("🎉 READY TO SUBMIT — no blockers found" if not miss else f"⛔ {len(miss)} blocker(s): " + ", ".join(miss)))
