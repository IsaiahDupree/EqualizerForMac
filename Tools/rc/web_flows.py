#!/usr/bin/env python3
"""web_flows.py — RevenueCat *dashboard* steps the v2 API can't do, captured as repeatable flows. Uses
the shared CSP-safe Safari driver (Tools/asc/safari.py). Requires Safari signed in to app.revenuecat.com.

  python3 Tools/rc/web_flows.py create-project "Sonance EQ"   # → prints the new project id
  python3 Tools/rc/web_flows.py public-key <project_id>       # read the public appl_ SDK key (if shown)
"""
import os, re, sys, time
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "asc"))
import safari

def cur_url():
    import subprocess
    return subprocess.run(["osascript", "-e", 'tell application "Safari" to get URL of front document'],
                          capture_output=True, text=True).stdout.strip()

def create_project(name):
    if not safari.focus("app.revenuecat.com"):
        sys.exit("✗ open app.revenuecat.com in Safari and sign in first")
    # /projects/add is the real create-project route (the switcher menu is a transient portal).
    safari.goto("https://app.revenuecat.com/projects/add"); time.sleep(7)
    nid = safari.field("Project name")
    if nid is None: sys.exit("✗ create-project form not found (are you signed in?)")
    safari.run(f"__asc.set({nid}, {safari.jarg(name)})"); time.sleep(1)
    cid = safari.field("Create project")
    if cid is None: sys.exit("✗ Create button not found")
    safari.run(f"__asc.click({cid})"); time.sleep(5)
    m = re.search(r"/projects/([0-9a-f]+)", cur_url())
    pid = m.group(1) if m else "?"
    print(f"✓ created project '{name}' → id {pid}")
    return pid

def public_key(pid):
    if not safari.focus("app.revenuecat.com"):
        sys.exit("✗ sign in to app.revenuecat.com first")
    safari.goto(f"https://app.revenuecat.com/projects/{pid}/api-keys"); time.sleep(7)
    key = safari.run("(function(){var m=(document.body.innerText.match(/appl_[A-Za-z0-9]+/)||[])[0];return m||'';})()")
    print(key or "  (no appl_ key shown — add the App Store app first)")
    return key

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "create-project":
        create_project(sys.argv[2] if len(sys.argv) > 2 else "Sonance EQ")
    elif cmd == "public-key":
        public_key(sys.argv[2])
    else:
        print(__doc__)
