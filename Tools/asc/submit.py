#!/usr/bin/env python3
"""submit.py — submit the current app version for App Store review via the ASC reviewSubmissions API.
Adds ONLY the appStoreVersion to the submission (NOT the IAP), so the free app is reviewed on its own
and the Pro IAP can be submitted later with a real-StoreKit build.  python3 Tools/asc/submit.py
"""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from api import api, get_app

def main():
    app = get_app(); aid = app["id"]
    ver = api("GET", f"/v1/apps/{aid}/appStoreVersions?limit=3")["data"][0]
    print(f"App {app['attributes']['name']} · version {ver['attributes']['versionString']} "
          f"({ver['attributes']['appStoreState']})")

    # Reuse an open submission for this app/platform, else create one.
    subs = api("GET", f"/v1/reviewSubmissions?filter[app]={aid}&filter[state]=READY_FOR_REVIEW,COMPLETING").get("data", [])
    if subs:
        rs = subs[0]; print(f"  · reusing review submission {rs['id']} ({rs['attributes']['state']})")
    else:
        rs = api("POST", "/v1/reviewSubmissions", {"data": {"type": "reviewSubmissions",
            "attributes": {"platform": "MAC_OS"},
            "relationships": {"app": {"data": {"type": "apps", "id": aid}}}}})["data"]
        print(f"  ✓ created review submission {rs['id']}")

    # Add the version as an item (skip if already present).
    items = api("GET", f"/v1/reviewSubmissions/{rs['id']}/items").get("data", [])
    have = any((i.get("relationships", {}).get("appStoreVersion", {}).get("data") or {}).get("id") == ver["id"]
               for i in items)
    if have:
        print("  · version already in the submission")
    else:
        api("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems",
            "relationships": {"reviewSubmission": {"data": {"type": "reviewSubmissions", "id": rs["id"]}},
                              "appStoreVersion": {"data": {"type": "appStoreVersions", "id": ver["id"]}}}}})
        print("  ✓ added version to the submission (IAP intentionally NOT included)")

    # Submit.
    api("PATCH", f"/v1/reviewSubmissions/{rs['id']}", {"data": {"type": "reviewSubmissions",
        "id": rs["id"], "attributes": {"submitted": True}}})
    state = api("GET", f"/v1/reviewSubmissions/{rs['id']}")["data"]["attributes"]["state"]
    print(f"\n🚀 SUBMITTED — review submission state: {state}")

if __name__ == "__main__":
    main()
