#!/usr/bin/env python3
"""create_app.py — drive App Store Connect's New App modal (shadow-DOM) to create the macOS app record,
the one step the ASC API forbids. Adaptive: it discovers fields by their label text each run via
deepdom.js, so it tolerates Apple's selector churn. Detects the agreement-block dialog and aborts cleanly.

Run AFTER the PLA + Paid Applications agreements are accepted (else the form never opens).
  python3 Tools/asc/create_app.py
Verifies success via the ASC API (api.get_app).
"""
import sys, time, os
sys.path.insert(0, os.path.dirname(__file__))
import safari, api

NAME = os.environ.get("APP_NAME", "Sonance EQ")
BUNDLE = os.environ.get("APP_BUNDLE_ID", "com.isaiahdupree.SonanceEQ")
SKU = os.environ.get("APP_SKU", BUNDLE)

def field_id(fields, *needles):
    """First field whose label/text contains all needles (case-insensitive)."""
    for f in fields:
        hay = (f["label"] + " " + f["text"]).lower()
        if all(n.lower() in hay for n in needles):
            return f["id"]
    return None

def main():
    if api.get_app():
        print("✓ app record already exists — nothing to do"); return
    safari.goto("https://appstoreconnect.apple.com/apps"); time.sleep(5)

    fields = safari.run_json("__asc.fields()")
    nid = field_id(fields, "new app") or field_id(fields, "new-app")
    if nid is None: sys.exit("✗ couldn't find the New App button — are you signed in to App Store Connect?")
    safari.run(f"__asc.click({nid})"); time.sleep(3)

    if safari.run('__asc.hasText("agreement")') == "true" and \
       safari.run('__asc.hasText("outdated")') == "true":
        sys.exit("⛔ blocked: Paid Applications Agreement is outdated. Accept it at "
                 "App Store Connect → Business (Agreements, Tax, and Banking), then re-run.")

    f = safari.run_json("__asc.fields()")
    # macOS platform checkbox
    mac = field_id(f, "macos") or field_id(f, "mac os")
    if mac is not None: safari.run(f"__asc.check({mac}, true)")
    # text fields
    for needles, val in [(("name",), NAME), (("sku",), SKU)]:
        fid = field_id(f, *needles)
        if fid is not None: safari.run(f"__asc.set({fid}, {safari.jarg(val)})")
    # primary language + bundle id are comboboxes: open then pick by text
    lang = field_id(f, "primary language") or field_id(f, "language")
    if lang is not None:
        safari.run(f"__asc.click({lang})"); time.sleep(1); safari.run(f"__asc.clickText({safari.jarg('English (U.S.)')})")
    bid = field_id(f, "bundle")
    if bid is not None:
        safari.run(f"__asc.click({bid})"); time.sleep(1); safari.run(f"__asc.clickText({safari.jarg(BUNDLE)})")

    print("· filled the modal — review it in Safari, then it will submit in 4s (Ctrl-C to abort)")
    time.sleep(4)
    f = safari.run_json("__asc.fields()")
    create = field_id(f, "create")
    if create is not None: safari.run(f"__asc.click({create})")
    time.sleep(5)

    if api.get_app():
        print(f"✓ created app record for {BUNDLE}")
    else:
        print("⚠ couldn't confirm the record via API — check the modal in Safari and finish manually.")

if __name__ == "__main__":
    main()
