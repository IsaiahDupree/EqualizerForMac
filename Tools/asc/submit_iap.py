#!/usr/bin/env python3
"""submit_iap.py — submit the Pro In-App Purchase for App Store review via `inAppPurchaseSubmissions`.

  python3 Tools/asc/submit_iap.py            # dry run
  python3 Tools/asc/submit_iap.py --yes      # submit

⚠️  FIRST-IAP CAVEAT (learned 2026-06-26): Apple requires the **first** in-app purchase for an app to be
reviewed *bundled with an app version*, and the ASC API gives no way to do that — `reviewSubmissionItems`
has no `inAppPurchaseV2` relationship, and this standalone `inAppPurchaseSubmissions` call returns 409
"this in-app purchase cannot be reviewed" until at least one app version has shipped *with* the IAP.
After that first approval, this script works for subsequent IAP-only submissions.

EXACT FIRST-IAP WEB FLOW (the step everyone misses — learned 2026-06-28):
  1. Version page (.../distribution/macos/version/inflight) with the version EDITABLE (Prepare for
     Submission / Developer Rejected — cancel any in-flight submission first to make it editable).
  2. Scroll the page BODY to the "In-App Purchases and Subscriptions" section.
  3. Click the **"Select In-App Purchases or Subscriptions"** button — NOT "Add for Review".
     (Clicking "Add for Review" without selecting first submits the version ALONE, every time — this
     was the repeated failure.)
  4. Check the IAP in the picker; it then appears ATTACHED in that section.
  5. THEN click "Add for Review" (top-right) -> the Draft Submission lists BOTH the build and the IAP
     -> Submit for Review. Verify the IAP flips READY_TO_SUBMIT -> WAITING_FOR_REVIEW.
Pre-req gotcha: the IAP review screenshot must be a real uploaded asset. A botched upload shows
fileName="SOURCE"/uploaded=null and the IAP reads "Missing Metadata" in the UI even though the API says
READY_TO_SUBMIT -> delete it and re-upload a valid PNG with a proper filename.
"""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from api import api, get_app, IAP_PRODUCT

def main():
    go = "--yes" in sys.argv
    app = get_app(); aid = app["id"]
    iap = next((p for p in api("GET", f"/v1/apps/{aid}/inAppPurchasesV2?limit=20").get("data", [])
                if p["attributes"].get("productId") == IAP_PRODUCT), None)
    if not iap:
        sys.exit(f"✗ IAP {IAP_PRODUCT} not found")
    state = iap["attributes"]["state"]
    print(f"IAP {IAP_PRODUCT}  state={state}")
    if state != "READY_TO_SUBMIT":
        print(f"  · not in READY_TO_SUBMIT ({state}) — nothing to submit"); return
    if not go:
        print("PLAN: POST /v1/inAppPurchaseSubmissions for this IAP.")
        print("(dry run — pass --yes; if it 409s with 'cannot be reviewed', this is the first IAP —")
        print(" bundle it with a version in the ASC web UI instead, see the caveat in this file's docstring.)")
        return
    try:
        r = api("POST", "/v1/inAppPurchaseSubmissions", {"data": {"type": "inAppPurchaseSubmissions",
            "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap["id"]}}}}})
        print(f"🚀 IAP SUBMITTED — submission {r['data']['id']}")
    except RuntimeError as e:
        if "409" in str(e) and "cannot be reviewed" in str(e):
            sys.exit("✗ 409 'cannot be reviewed' — this is the FIRST IAP. Bundle it with a version in the "
                     "ASC web UI (version page → In-App Purchases → add → Submit). See the docstring caveat.")
        raise

if __name__ == "__main__":
    main()
