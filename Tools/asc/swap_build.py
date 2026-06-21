#!/usr/bin/env python3
"""swap_build.py — point the app version at the newest VALID build, replacing whatever is attached.

If the version is mid-review (WAITING_FOR_REVIEW), the build can't be changed, so this first CANCELS the
open review submission (only valid before Apple starts the actual review), which returns the version to an
editable state; it then attaches the newest build. Re-submit afterwards with submit.py.

  python3 Tools/asc/swap_build.py            # DRY RUN — print the plan, change nothing
  python3 Tools/asc/swap_build.py --yes      # execute: cancel (if needed) → attach newest build
"""
import os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
import api as A

CANCELLABLE = {"WAITING_FOR_REVIEW", "READY_FOR_REVIEW", "UNRESOLVED_ISSUES", "COMPLETING"}
EDITABLE_VERSION = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED",
                    "INVALID_BINARY"}

def retry(fn, n=6, delay=2):
    for i in range(n):
        try:
            return fn()
        except Exception:
            if i == n - 1:
                raise
            time.sleep(delay)

def main():
    go = "--yes" in sys.argv
    app = retry(A.get_app); aid = app["id"]

    builds = retry(lambda: A.api("GET", f"/v1/builds?filter[app]={aid}&limit=10&sort=-version").get("data", []))
    valid = [b for b in builds if b["attributes"].get("processingState") == "VALID"]
    if not valid:
        sys.exit("✗ no VALID build to attach (still processing?).")
    newest = valid[0]; bid = newest["id"]; bver = newest["attributes"]["version"]

    ver = retry(lambda: A.api("GET", f"/v1/apps/{aid}/appStoreVersions?limit=1").get("data", []))[0]
    vid = ver["id"]; vstate = ver["attributes"]["appStoreState"]; vstr = ver["attributes"]["versionString"]
    attached = retry(lambda: A.api("GET", f"/v1/appStoreVersions/{vid}/relationships/build").get("data"))
    attached_ver = None
    if attached:
        attached_ver = retry(lambda: A.api("GET", f"/v1/builds/{attached['id']}")["data"]["attributes"]["version"])

    print(f"App {app['attributes']['name']} · version {vstr} (state={vstate})")
    print(f"  attached build: {attached_ver}   →   newest VALID build: {bver}")
    if attached_ver == bver:
        print("✓ already attached to the newest build — nothing to do."); return

    subs = retry(lambda: A.api("GET", f"/v1/reviewSubmissions?filter[app]={aid}&limit=5").get("data", []))
    open_subs = [s for s in subs if s["attributes"]["state"] in CANCELLABLE]

    print("\nPLAN:")
    for s in open_subs:
        print(f"  1. cancel review submission {s['id'][:8]} ({s['attributes']['state']})")
    print(f"  {'2' if open_subs else '1'}. attach build {bver} to version {vstr}")
    print(f"  next: python3 Tools/asc/submit.py   # re-submit for review")

    if not go:
        print("\n(dry run — pass --yes to execute)")
        return

    for s in open_subs:
        retry(lambda: A.api("PATCH", f"/v1/reviewSubmissions/{s['id']}",
            {"data": {"type": "reviewSubmissions", "id": s["id"], "attributes": {"canceled": True}}}))
        print(f"  ✓ cancelled {s['id'][:8]}")

    # Wait for the version to become editable after cancellation.
    if open_subs:
        for _ in range(15):
            st = retry(lambda: A.api("GET", f"/v1/appStoreVersions/{vid}")["data"]["attributes"]["appStoreState"])
            if st in EDITABLE_VERSION:
                vstate = st; break
            time.sleep(4)
        print(f"  · version state now {vstate}")

    retry(lambda: A.api("PATCH", f"/v1/appStoreVersions/{vid}",
        {"data": {"type": "appStoreVersions", "id": vid,
                  "relationships": {"build": {"data": {"type": "builds", "id": bid}}}}}))
    print(f"  ✓ attached build {bver} to version {vstr}")
    print("\n✅ build swapped. Re-submit with: python3 Tools/asc/submit.py")

if __name__ == "__main__":
    main()
