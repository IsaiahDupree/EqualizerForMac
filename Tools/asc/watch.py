#!/usr/bin/env python3
"""watch.py — one-shot App Store Connect status for Sonance EQ: builds + processing state, the app
version state, the live review-submission state, and IAP state. Retry-resilient (the ASC API throws
the odd transient timeout). Read-only.

  python3 Tools/asc/watch.py            # print current status
  python3 Tools/asc/watch.py --json     # machine-readable (for cron/diffing)

Exit code: 0 normally; 2 if a developer action is pending (build VALID but not attached, or a
rejection), so a cron job can decide whether to ping you.
"""
import os, sys, time, json
sys.path.insert(0, os.path.dirname(__file__))
import api as A

def retry(fn, n=6, delay=2):
    for i in range(n):
        try:
            return fn()
        except Exception:
            if i == n - 1:
                raise
            time.sleep(delay)

def main():
    as_json = "--json" in sys.argv
    app = retry(A.get_app)
    aid = app["id"]; name = app["attributes"]["name"]

    builds = retry(lambda: A.api("GET", f"/v1/builds?filter[app]={aid}&limit=5&sort=-version").get("data", []))
    build_rows = [{
        "version": b["attributes"].get("version"),
        "processingState": b["attributes"].get("processingState"),
        "uploaded": b["attributes"].get("uploadedDate"),
    } for b in builds]

    ver = retry(lambda: A.api("GET", f"/v1/apps/{aid}/appStoreVersions?limit=1").get("data", []))[0]
    vid = ver["id"]; vstate = ver["attributes"]["appStoreState"]; vstr = ver["attributes"]["versionString"]
    attached = retry(lambda: A.api("GET", f"/v1/appStoreVersions/{vid}/relationships/build").get("data"))
    attached_ver = None
    if attached:
        bd = retry(lambda: A.api("GET", f"/v1/builds/{attached['id']}")["data"]["attributes"])
        attached_ver = bd.get("version")

    subs = retry(lambda: A.api("GET", f"/v1/reviewSubmissions?filter[app]={aid}&limit=5").get("data", []))
    sub_rows = [{"id": s["id"], "state": s["attributes"]["state"],
                 "submitted": s["attributes"].get("submittedDate")} for s in subs]

    iaps = retry(lambda: A.api("GET", f"/v1/apps/{aid}/inAppPurchasesV2?limit=10").get("data", []))
    iap_rows = [{"productId": p["attributes"]["productId"], "state": p["attributes"]["state"]} for p in iaps]

    # Pending-action heuristics.
    pending = []
    newest_valid = next((b for b in build_rows if b["processingState"] == "VALID"), None)
    if newest_valid and newest_valid["version"] != attached_ver:
        pending.append(f"build {newest_valid['version']} is VALID but version {vstr} still has build {attached_ver}")
    if vstate in ("REJECTED", "DEVELOPER_REJECTED", "METADATA_REJECTED", "INVALID_BINARY"):
        pending.append(f"version state needs attention: {vstate}")

    out = {"app": name, "version": vstr, "versionState": vstate, "attachedBuild": attached_ver,
           "builds": build_rows, "reviewSubmissions": sub_rows, "iaps": iap_rows, "pending": pending}

    if as_json:
        print(json.dumps(out, indent=2))
    else:
        print(f"APP  {name}  · version {vstr}  state={vstate}  attachedBuild={attached_ver}")
        print("BUILDS:")
        for b in build_rows:
            print(f"  · build {b['version']:<4} {b['processingState']:<12} {b['uploaded']}")
        print("REVIEW SUBMISSIONS:")
        for s in sub_rows:
            print(f"  · {s['id'][:8]}  {s['state']:<20} submitted={s['submitted']}")
        print("IAP:")
        for p in iap_rows:
            print(f"  · {p['productId']}  {p['state']}")
        if pending:
            print("\n⚠ ACTION PENDING:")
            for p in pending:
                print(f"  → {p}")
        else:
            print("\n✓ no developer action pending (waiting on Apple)")

    sys.exit(2 if pending else 0)

if __name__ == "__main__":
    main()
