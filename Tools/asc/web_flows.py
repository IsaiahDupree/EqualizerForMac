#!/usr/bin/env python3
"""web_flows.py — the App Store Connect *browser* steps the API can't do, captured as repeatable,
adaptive flows (find controls by label each run → survive Apple's shadow-DOM selector churn). These are
the flows we performed by hand the first time; now they're one command each.

  python3 Tools/asc/web_flows.py price     # set price → Free
  python3 Tools/asc/web_flows.py age       # age rating → 4+ (+ primary category Music)
  python3 Tools/asc/web_flows.py privacy   # App Privacy → Data Not Collected (published)
  python3 Tools/asc/web_flows.py all       # all three, in order

Requires: Safari logged in to App Store Connect (any tab). APP_ID env, else resolved via the ASC API.
"""
import os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
import safari

def app_id():
    if os.environ.get("APP_ID"): return os.environ["APP_ID"]
    from api import get_app
    a = get_app()
    if not a: sys.exit("✗ app record not found")
    return a["id"]

def open_page(app_id, path):
    """Focus the App Store Connect tab and navigate it to a distribution sub-page."""
    if not safari.focus("appstoreconnect.apple.com"):
        sys.exit("✗ open App Store Connect in Safari and sign in first")
    safari.goto(f"https://appstoreconnect.apple.com/apps/{app_id}/distribution/{path}")
    time.sleep(7)

def click_label(label):
    fid = safari.field(label)
    if fid is None: return False
    safari.run(f"__asc.click({fid})"); return True

def click_button_text(text):  # exact-text button anywhere (re-stamps each call)
    return safari.run(f"__asc.clickText({safari.jarg(text)})") == "ok"

# ---------------------------------------------------------------- price → Free
def price_free(aid):
    open_page(aid, "pricing")
    if not click_label("Add Pricing"): print("  · pricing may already be set");
    time.sleep(2)
    click_label("Choose"); time.sleep(2)
    click_button_text("$0.00"); time.sleep(1)             # Free price point
    for _ in range(3):                                     # Next → … → Confirm
        if click_button_text("Next"): time.sleep(2)
        else: break
    click_button_text("Confirm"); time.sleep(2)
    click_button_text("Save"); time.sleep(2)
    print("  ✓ price → Free")

# ---------------------------------------------------------------- age rating → 4+
def age_rating(aid, category="Music"):
    open_page(aid, "info")
    if not click_label("Set Up Age Ratings"):
        click_label("Age Rating")  # fallback if it shows as an Edit
    time.sleep(3)
    # category
    cat = safari.field("primaryCategory") or safari.field("Primary")
    if cat is not None:
        safari.run(f"__asc.pick({cat}, {safari.jarg(category)})")
    # walk every questionnaire page: answer all NONE / false, advance on Next, finish on Save
    for _ in range(8):
        safari.run("__asc.fields()")  # stamp ids
        safari.run("__asc.deepAll('input[type=radio]').filter(function(e){return e.value==='NONE'||e.value==='false';}).forEach(function(e){if(!e.checked)e.click();})")
        time.sleep(1)
        if click_button_text("Next"): time.sleep(2); continue
        break
    click_button_text("Save"); time.sleep(3)
    print("  ✓ age rating → 4+ (category", category + ")")

# ---------------------------------------------------------------- App Privacy → no data
def app_privacy(aid):
    open_page(aid, "privacy")
    if not click_label("Get Started"):
        print("  · privacy may already be set"); return
    time.sleep(3)
    # "No, we do not collect data" = the radio whose value is false
    safari.run("__asc.fields()")
    no = safari.run("(function(){var e=__asc.deepAll('input[name=isAnyDataCollected]').filter(function(x){return x.value==='false';})[0]; if(e){e.click();return 'ok';}return 'no';})()")
    time.sleep(1)
    click_button_text("Save"); time.sleep(4)
    click_button_text("Publish"); time.sleep(2)
    click_button_text("Publish"); time.sleep(2)  # confirm dialog
    print("  ✓ App Privacy → Data Not Collected (published)")

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "all"
    aid = app_id()
    print(f"App {aid}")
    flows = {"price": price_free, "age": age_rating, "privacy": app_privacy}
    if cmd == "all":
        for fn in (price_free, age_rating, app_privacy): fn(aid)
    elif cmd in flows:
        flows[cmd](aid)
    else:
        print(__doc__)
