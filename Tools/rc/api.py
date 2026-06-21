#!/usr/bin/env python3
"""api.py — RevenueCat v2 REST client. Handles the CLI-automatable half of wiring Sonance EQ:
apps, entitlements, products (attached to the App Store IAP), offerings + packages — everything
*inside* a project. Project creation itself is dashboard-only (see browser flow / README).

Auth: a project-scoped secret key (sk_…). Provide via RC_SECRET_KEY, or it's read from the first
~/Documents/Software/*/.env that has one (living off the land). Set RC_PROJECT_ID to target a project.

CLI:  projects | apps | setup        (setup = entitlement + product + offering for Sonance EQ)
"""
import glob, json, os, sys, urllib.request, urllib.error

BASE = "https://api.revenuecat.com/v2"
BUNDLE = os.environ.get("APP_BUNDLE_ID", "com.isaiahdupree.SonanceEQ")
IAP = os.environ.get("IAP_PRODUCT_ID", "com.isaiahdupree.SonanceEQ.pro")
ENTITLEMENT = "pro"
OFFERING = "default"

def secret():
    k = os.environ.get("RC_SECRET_KEY")
    if k: return k
    for f in glob.glob(os.path.expanduser("~/Documents/Software/*/.env")):
        try:
            for line in open(f):
                if "sk_" in line:
                    import re
                    m = re.search(r"sk_[A-Za-z0-9]+", line)
                    if m: return m.group(0)
        except Exception: pass
    sys.exit("✗ no RevenueCat secret key (set RC_SECRET_KEY)")

def api(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method,
        headers={"Authorization": "Bearer " + secret(), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=45) as r:
            return json.load(r) if r.length != 0 else {}
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"RC {method} {path} → {e.code}: {e.read().decode()[:300]}")

def projects(): return api("GET", "/projects?limit=20").get("items", [])

def project_id():
    pid = os.environ.get("RC_PROJECT_ID")
    if pid: return pid
    ps = projects()
    if len(ps) == 1: return ps[0]["id"]
    sys.exit(f"✗ set RC_PROJECT_ID — projects: {[(p['name'], p['id']) for p in ps]}")

def find(items, key, val):
    return next((i for i in items if i.get(key) == val), None)

def setup():
    pid = project_id()
    print(f"project {pid}")
    apps = api("GET", f"/projects/{pid}/apps?limit=50").get("items", [])
    app = find(apps, "type", "app_store") or (apps[0] if apps else None)
    if not app: sys.exit("✗ no App Store app in this project — add it in the dashboard first")
    print(f"  app: {app.get('name')} ({app['id']})  bundle={app.get('app_store',{}).get('bundle_id')}")

    ents = api("GET", f"/projects/{pid}/entitlements?limit=50").get("items", [])
    ent = find(ents, "lookup_key", ENTITLEMENT)
    if not ent:
        ent = api("POST", f"/projects/{pid}/entitlements",
                  {"lookup_key": ENTITLEMENT, "display_name": "Pro"})
        print(f"  ✓ entitlement '{ENTITLEMENT}'")
    else: print(f"  · entitlement '{ENTITLEMENT}' exists")

    prods = api("GET", f"/projects/{pid}/products?limit=100").get("items", [])
    prod = find(prods, "store_identifier", IAP)
    if not prod:
        prod = api("POST", f"/projects/{pid}/products",
                   {"store_identifier": IAP, "app_id": app["id"], "type": "non_consumable"})
        print(f"  ✓ product {IAP}")
    else: print(f"  · product {IAP} exists")

    api("POST", f"/projects/{pid}/entitlements/{ent['id']}/actions/attach_products",
        {"product_ids": [prod["id"]]})
    print(f"  ✓ attached product → entitlement")

    offs = api("GET", f"/projects/{pid}/offerings?limit=50").get("items", [])
    off = find(offs, "lookup_key", OFFERING)
    if not off:
        off = api("POST", f"/projects/{pid}/offerings",
                  {"lookup_key": OFFERING, "display_name": "Default"})
        print(f"  ✓ offering '{OFFERING}'")
    else: print(f"  · offering '{OFFERING}' exists")

    pkgs = api("GET", f"/projects/{pid}/offerings/{off['id']}/packages?limit=50").get("items", [])
    pkg = find(pkgs, "lookup_key", "lifetime")
    if not pkg:
        pkg = api("POST", f"/projects/{pid}/offerings/{off['id']}/packages",
                  {"lookup_key": "lifetime", "display_name": "Lifetime Pro"})
        print(f"  ✓ package 'lifetime'")
    api("POST", f"/projects/{pid}/offerings/{off['id']}/packages/{pkg['id']}/actions/attach_products",
        {"products": [{"product_id": prod["id"], "eligibility_criteria": "all"}]})
    print(f"  ✓ attached product → package")
    print("✓ RevenueCat entitlement/product/offering wired. Public SDK key → LicenseConfig (see README).")

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "projects"
    if cmd == "projects":
        for p in projects(): print(p["id"], p["name"])
    elif cmd == "apps":
        for a in api("GET", f"/projects/{project_id()}/apps?limit=50").get("items", []):
            print(a["id"], a.get("type"), a.get("name"), a.get("app_store", {}).get("bundle_id", ""))
    elif cmd == "setup":
        setup()
