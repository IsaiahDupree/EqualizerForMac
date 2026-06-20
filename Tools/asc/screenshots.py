#!/usr/bin/env python3
"""screenshots.py — upload Mac App Store screenshots via the ASC API's 3-step binary flow:
reserve (POST appScreenshots → uploadOperations) → PUT the bytes → commit (PATCH uploaded + md5).
Targets the en-US APP_DESKTOP screenshot set of the current version. Skips files already uploaded.
  python3 Tools/asc/screenshots.py /tmp/shots/store_1.png /tmp/shots/store_2.png ...
"""
import hashlib, os, sys, urllib.request
sys.path.insert(0, os.path.dirname(__file__))
from api import api, get_app

LOCALE = "en-US"; DISPLAY = "APP_DESKTOP"

def version_loc(app_id):
    ver = api("GET", f"/v1/apps/{app_id}/appStoreVersions?limit=10")["data"][0]
    locs = api("GET", f"/v1/appStoreVersions/{ver['id']}/appStoreVersionLocalizations")["data"]
    return next(l for l in locs if l["attributes"]["locale"] == LOCALE)

def screenshot_set(loc_id):
    sets = api("GET", f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets")["data"]
    s = next((s for s in sets if s["attributes"]["screenshotDisplayType"] == DISPLAY), None)
    if s: return s["id"], {x["attributes"]["fileName"] for x in
                           api("GET", f"/v1/appScreenshotSets/{s['id']}/appScreenshots")["data"]}
    d = api("POST", "/v1/appScreenshotSets", {"data": {"type": "appScreenshotSets",
        "attributes": {"screenshotDisplayType": DISPLAY},
        "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc_id}}}}})
    return d["data"]["id"], set()

def upload(set_id, path):
    data = open(path, "rb").read(); name = os.path.basename(path)
    d = api("POST", "/v1/appScreenshots", {"data": {"type": "appScreenshots",
        "attributes": {"fileName": name, "fileSize": len(data)},
        "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}}})
    sid = d["data"]["id"]
    for op in d["data"]["attributes"]["uploadOperations"]:
        chunk = data[op["offset"]:op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], data=chunk, method=op["method"])
        for h in op["requestHeaders"]:
            req.add_header(h["name"], h["value"])
        urllib.request.urlopen(req, timeout=180)
    api("PATCH", f"/v1/appScreenshots/{sid}", {"data": {"type": "appScreenshots", "id": sid,
        "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
    print(f"  ✓ uploaded {name}")

if __name__ == "__main__":
    files = sys.argv[1:] or [f"/tmp/shots/store_{i}.png" for i in (1, 2, 3)]
    app = get_app();
    if not app: sys.exit("✗ app record missing")
    loc = version_loc(app["id"])
    set_id, existing = screenshot_set(loc["id"])
    for f in files:
        if os.path.basename(f) in existing:
            print(f"  · {os.path.basename(f)} already uploaded"); continue
        upload(set_id, f)
    print("✓ screenshots uploaded")
