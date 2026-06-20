#!/usr/bin/env python3
"""iap.py — finish the Pro in-app purchase so it's submittable: localization (display name + description),
a price (USD tier, mirrored to all territories), and the App Review screenshot. Idempotent.
  python3 Tools/asc/iap.py [price_usd] [review_screenshot.png]
"""
import hashlib, os, sys, urllib.request
sys.path.insert(0, os.path.dirname(__file__))
from api import api, get_app, IAP_PRODUCT

LOCALE = "en-US"
NAME = "Sonance EQ Pro"
DESCRIPTION = "Unlock all Pro features. One-time purchase."  # IAP description max 45 chars
PRICE_USD = sys.argv[1] if len(sys.argv) > 1 else "9.99"
SHOT = sys.argv[2] if len(sys.argv) > 2 else "/tmp/shots/store_1.png"

def iap_id():
    app = get_app()
    for p in api("GET", f"/v1/apps/{app['id']}/inAppPurchasesV2?limit=50")["data"]:
        if p["attributes"]["productId"] == IAP_PRODUCT:
            return p["id"]
    sys.exit("✗ IAP not found")

def localize(iid):
    locs = api("GET", f"/v2/inAppPurchases/{iid}/inAppPurchaseLocalizations").get("data", [])
    cur = next((l for l in locs if l["attributes"]["locale"] == LOCALE), None)
    attrs = {"name": NAME, "description": DESCRIPTION}
    if cur:
        api("PATCH", f"/v1/inAppPurchaseLocalizations/{cur['id']}",
            {"data": {"type": "inAppPurchaseLocalizations", "id": cur["id"], "attributes": attrs}})
    else:
        api("POST", "/v1/inAppPurchaseLocalizations", {"data": {"type": "inAppPurchaseLocalizations",
            "attributes": {**attrs, "locale": LOCALE},
            "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iid}}}}})
    print(f"  ✓ localization ({LOCALE}): {NAME}")

def set_price(iid):
    pts = api("GET", f"/v2/inAppPurchases/{iid}/pricePoints?filter[territory]=USA&limit=8000").get("data", [])
    pp = next((p for p in pts if p["attributes"].get("customerPrice") == PRICE_USD), None)
    if not pp:
        print(f"  ⚠ no USD price point for {PRICE_USD}; set the IAP price in the web UI"); return
    api("POST", "/v1/inAppPurchasePriceSchedules", {"data": {"type": "inAppPurchasePriceSchedules",
        "relationships": {"inAppPurchase": {"data": {"type": "inAppPurchases", "id": iid}},
            "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
            "manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": "${p}"}]}}},
        "included": [{"type": "inAppPurchasePrices", "id": "${p}", "attributes": {"startDate": None},
            "relationships": {"inAppPurchasePricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": pp["id"]}}}}]})
    print(f"  ✓ price set to ${PRICE_USD}")

def review_shot(iid):
    data = open(SHOT, "rb").read()
    d = api("POST", "/v1/inAppPurchaseAppStoreReviewScreenshots", {"data": {
        "type": "inAppPurchaseAppStoreReviewScreenshots",
        "attributes": {"fileName": os.path.basename(SHOT), "fileSize": len(data)},
        "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iid}}}}})
    sid = d["data"]["id"]
    for op in d["data"]["attributes"]["uploadOperations"]:
        req = urllib.request.Request(op["url"], data=data[op["offset"]:op["offset"]+op["length"]], method=op["method"])
        for h in op["requestHeaders"]: req.add_header(h["name"], h["value"])
        urllib.request.urlopen(req, timeout=180)
    api("PATCH", f"/v1/inAppPurchaseAppStoreReviewScreenshots/{sid}", {"data": {
        "type": "inAppPurchaseAppStoreReviewScreenshots", "id": sid,
        "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
    print("  ✓ review screenshot uploaded")

if __name__ == "__main__":
    iid = iap_id()
    localize(iid)
    try: set_price(iid)
    except Exception as e: print(f"  price: {str(e)[:140]}")
    try: review_shot(iid)
    except Exception as e: print(f"  review shot: {str(e)[:140]}")
    print("✓ IAP finalize done")
