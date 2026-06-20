#!/usr/bin/env python3
"""api.py — App Store Connect REST client (JWT/ES256 auth via the account .p8). The CLI-automatable half
of the pipeline: certificates, bundle ids, provisioning profiles, app lookup, and in-app purchases.
What the API can NOT do (Apple's design) is handled by the browser layer (safari.py / create_app.py):
creating the app record, and accepting the PLA / Paid Apps agreements.

Env: ASC_API_KEY_ID, ASC_API_ISSUER_ID, ASC_API_KEY_PATH, TEAM_ID.
CLI: status | bundleid | certs | profile | iap   (see pipeline.py for the full flow)
"""
import base64, json, os, subprocess, sys, time, urllib.request, urllib.error
import jwt

BASE = "https://api.appstoreconnect.apple.com"
BUNDLE = os.environ.get("APP_BUNDLE_ID", "com.isaiahdupree.SonanceEQ")
APP_NAME = os.environ.get("APP_NAME", "Sonance EQ")
TEAM = os.environ.get("TEAM_ID", "Y4HDXFWXUV")
IAP_PRODUCT = os.environ.get("IAP_PRODUCT_ID", "com.isaiahdupree.SonanceEQ.pro")
CERTS_DIR = os.path.expanduser("~/Documents/Software/EqualizerForMac/build/certs")
PP_DIR = os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles")

def _token():
    kid, iss = os.environ["ASC_API_KEY_ID"], os.environ["ASC_API_ISSUER_ID"]
    key = open(os.environ["ASC_API_KEY_PATH"]).read()
    return jwt.encode({"iss": iss, "iat": int(time.time()), "exp": int(time.time()) + 1100,
                       "aud": "appstoreconnect-v1"}, key, algorithm="ES256", headers={"kid": kid, "typ": "JWT"})

def api(method, path, body=None):
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(BASE + path, data=data, method=method,
        headers={"Authorization": "Bearer " + _token(), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.load(r) if r.length != 0 else {}
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        raise RuntimeError(f"ASC {method} {path} → {e.code}: {body[:300]}")

def sh(*a): return subprocess.run(a, check=True, capture_output=True, text=True)

# ---------- bundle ids ----------
def get_bundle():
    for b in api("GET", f"/v1/bundleIds?filter[identifier]={BUNDLE}&limit=200").get("data", []):
        if b["attributes"]["identifier"] == BUNDLE:
            return b
    return None

def ensure_bundle():
    b = get_bundle()
    if b: print(f"  ✓ bundle id present ({b['id']})"); return b
    d = api("POST", "/v1/bundleIds", {"data": {"type": "bundleIds",
        "attributes": {"identifier": BUNDLE, "name": APP_NAME, "platform": "MAC_OS", "seedId": TEAM}}})
    print(f"  ✓ registered bundle id {BUNDLE}"); return d["data"]

# ---------- certificates ----------
def list_certs(): return api("GET", "/v1/certificates?limit=200").get("data", [])

def ensure_cert(cert_type):
    os.makedirs(CERTS_DIR, exist_ok=True)
    key = os.path.join(CERTS_DIR, f"{cert_type}.key")
    existing = [c for c in list_certs() if c["attributes"]["certificateType"] == cert_type]
    if existing:
        cert = existing[0]; print(f"  ✓ {cert_type} exists")
        if not os.path.exists(key):
            print(f"    ⚠ no local key for existing {cert_type}; revoke + re-run to re-key."); return cert["id"]
    else:
        sh("openssl", "genrsa", "-out", key, "2048")
        csr = os.path.join(CERTS_DIR, f"{cert_type}.csr")
        sh("openssl", "req", "-new", "-key", key, "-out", csr, "-subj",
           f"/CN=Sonance EQ {cert_type}/O=isaiah dupree/C=US")
        cert = api("POST", "/v1/certificates", {"data": {"type": "certificates",
            "attributes": {"certificateType": cert_type, "csrContent": open(csr).read()}}})["data"]
        print(f"  ✓ created {cert_type}")
    der = os.path.join(CERTS_DIR, f"{cert_type}.cer"); pem = os.path.join(CERTS_DIR, f"{cert_type}.pem")
    p12 = os.path.join(CERTS_DIR, f"{cert_type}.p12")
    open(der, "wb").write(base64.b64decode(cert["attributes"]["certificateContent"]))
    sh("openssl", "x509", "-inform", "DER", "-in", der, "-out", pem)
    # LEGACY pkcs12 + SHA1 MAC + a real password — required for `security import` on macOS.
    sh("openssl", "pkcs12", "-export", "-legacy", "-macalg", "sha1",
       "-certpbe", "PBE-SHA1-3DES", "-keypbe", "PBE-SHA1-3DES",
       "-inkey", key, "-in", pem, "-out", p12, "-passout", "pass:sonance", "-name", f"Sonance {cert_type}")
    kc = os.path.expanduser("~/Library/Keychains/login.keychain-db")
    r = subprocess.run(["security", "import", p12, "-k", kc, "-P", "sonance",
        "-T", "/usr/bin/codesign", "-T", "/usr/bin/productbuild", "-T", "/usr/bin/xcodebuild"],
        capture_output=True, text=True)
    print("  ✓ imported" if r.returncode == 0 or "already exists" in (r.stderr + r.stdout)
          else f"  ✗ import: {r.stderr.strip()[:160]}")
    return cert["id"]

# ---------- provisioning profile ----------
def ensure_profile(name="Sonance EQ MAS"):
    b = ensure_bundle()
    app_cert = [c for c in list_certs() if c["attributes"]["certificateType"] == "MAC_APP_DISTRIBUTION"]
    if not app_cert: sys.exit("  ✗ MAC_APP_DISTRIBUTION cert missing — run certs first")
    for p in api("GET", "/v1/profiles?limit=200").get("data", []):
        if p["attributes"]["name"] == name:
            api("DELETE", f"/v1/profiles/{p['id']}")
    d = api("POST", "/v1/profiles", {"data": {"type": "profiles",
        "attributes": {"name": name, "profileType": "MAC_APP_STORE"},
        "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": b["id"]}},
                          "certificates": {"data": [{"type": "certificates", "id": app_cert[0]["id"]}]}}}})
    os.makedirs(PP_DIR, exist_ok=True)
    out = os.path.join(PP_DIR, "Sonance_EQ_MAS.provisionprofile")
    open(out, "wb").write(base64.b64decode(d["data"]["attributes"]["profileContent"]))
    print(f"  ✓ profile '{name}' installed")

# ---------- app record (read-only; creation is browser-only) ----------
def get_app():
    for a in api("GET", f"/v1/apps?filter[bundleId]={BUNDLE}&limit=200").get("data", []):
        if a["attributes"].get("bundleId") == BUNDLE:
            return a
    return None

# ---------- in-app purchase ----------
def ensure_iap():
    app = get_app()
    if not app: sys.exit("  ✗ app record missing — create it first (browser: create_app.py)")
    for p in api("GET", f"/v1/apps/{app['id']}/inAppPurchasesV2?limit=200").get("data", []):
        if p["attributes"].get("productId") == IAP_PRODUCT:
            print(f"  ✓ IAP {IAP_PRODUCT} exists"); return p
    d = api("POST", "/v2/inAppPurchases", {"data": {"type": "inAppPurchases",
        "attributes": {"name": "Sonance EQ Pro", "productId": IAP_PRODUCT,
                       "inAppPurchaseType": "NON_CONSUMABLE", "reviewNote": "Unlocks all Pro features."},
        "relationships": {"app": {"data": {"type": "apps", "id": app["id"]}}}}})
    print(f"  ✓ created IAP {IAP_PRODUCT}"); return d["data"]

def status():
    print("certs:", [c["attributes"]["certificateType"] for c in list_certs()])
    print("bundle id:", "present" if get_bundle() else "MISSING")
    print("profiles:", [p["attributes"]["name"] for p in api("GET", "/v1/profiles?limit=200").get("data", [])])
    app = get_app()
    print("app record:", f"present ({app['id']})" if app else "MISSING (browser step)")

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    {"status": status, "bundleid": ensure_bundle,
     "certs": lambda: [ensure_cert("MAC_APP_DISTRIBUTION"), ensure_cert("MAC_INSTALLER_DISTRIBUTION")],
     "profile": ensure_profile, "iap": ensure_iap}[cmd]()
