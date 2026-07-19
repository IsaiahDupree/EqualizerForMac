#!/usr/bin/env python3
"""app_privacy.py — publish the App Privacy "Data Not Collected" declaration for each app, by driving the
logged-in App Store Connect Safari session (App Privacy has no API — it's dashboard-only).

Flow per app: open the App Privacy page → Get Started → select "No, we do not collect data" (the 2nd
`isAnyDataCollected` radio) → Save → VERIFY the page now says "Data Not Collected" (safety gate — abort if not)
→ Publish → confirm. Only publishes when the accurate "not collected" state is confirmed.

    python3 app_privacy.py            # all apps in /tmp/fleet_ids.json  (repo -> numeric app id)
    python3 app_privacy.py Forge      # one
"""
import json, os, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
IDS = json.load(open("/tmp/fleet_ids.json"))

def sf(*args):
    return subprocess.run([sys.executable, os.path.join(HERE, "safari.py"), *args],
                          capture_output=True, text=True).stdout.strip()

def first_id(needle):
    for line in sf("find", needle).splitlines():
        p = line.strip().split()
        if p and p[0].isdigit():
            return p[0]
    return None

def all_ids(needle):
    out = []
    for line in sf("find", needle).splitlines():
        p = line.strip().split()
        if p and p[0].isdigit():
            out.append(p[0])
    return out

def text():
    return sf("eval", "document.body.innerText")

def wait_text(*needles, timeout=30):
    """Poll the page until any needle appears in the visible text (the ASC SPA renders slowly)."""
    end = time.time() + timeout
    while time.time() < end:
        b = text()
        if any(n in b for n in needles):
            return b
        time.sleep(2)
    return text()

def is_published(body):
    # The published state carries a confirmation line like "Published N minutes ago by <name>".
    return "Published" in body and "by " in body.split("Published", 1)[1][:60]

def publish_and_confirm(repo):
    pubs = all_ids("Publish")
    if not pubs:
        print(f"  {repo}: no Publish button — SKIP"); return False
    sf("click", pubs[0])                      # opens confirmation dialog
    wait_text("agree that your responses", "Publish Your App Privacy", timeout=15)
    confirm = all_ids("Publish")
    sf("click", confirm[-1])                  # dialog's confirm Publish
    body = wait_text("Published", timeout=20)
    return is_published(body)

def do(repo):
    adam = IDS[repo]
    sf("goto", f"https://appstoreconnect.apple.com/apps/{adam}/distribution/privacy")
    body = wait_text("Data Not Collected", "does not collect any data", "Get Started", timeout=30)

    if is_published(body):
        print(f"  {repo}: already published ✓"); return

    # Saved draft ("Data Not Collected" but not yet published) → just Publish.
    if "Data Not Collected" in body or "does not collect any data" in body:
        ok = publish_and_confirm(repo)
        print(f"  {repo}: {'✓✓ PUBLISHED (was a saved draft)' if ok else '⚠ publish unconfirmed — check manually'}")
        return

    # Fresh → full flow.
    gs = first_id("Get Started")
    if not gs:
        print(f"  {repo}: no Get Started + not published — SKIP (unclear state)"); return
    sf("click", gs)
    wait_text("collect data from this app", timeout=20)
    radios = all_ids("collect")           # the two isAnyDataCollected radios; [0]=Yes, [1]=No
    if len(radios) < 2:
        print(f"  {repo}: couldn't find the data-collection radios — SKIP"); return
    sf("click", radios[1]); time.sleep(1)  # No, we do not collect data
    save = first_id("Save")
    if not save:
        print(f"  {repo}: no Save button — SKIP"); return
    sf("click", save)
    body = wait_text("Data Not Collected", "does not collect any data", timeout=20)
    if "Data Not Collected" not in body and "does not collect any data" not in body:
        print(f"  {repo}: ⚠ after Save the page is NOT 'Data Not Collected' — ABORT (won't publish)"); return
    ok = publish_and_confirm(repo)
    print(f"  {repo}: {'✓✓ PUBLISHED (Data Not Collected)' if ok else '⚠ publish unconfirmed — check manually'}")

if __name__ == "__main__":
    only = sys.argv[1] if len(sys.argv) > 1 else None
    for repo in IDS:
        if only and repo != only:
            continue
        do(repo)
