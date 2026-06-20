#!/usr/bin/env python3
"""App Store Connect provisioning via the ASC API key (living off the land, no Xcode account).
Idempotent: each step checks for an existing object before creating. Commands:
  bundleid   register com.isaiahdupree.SonanceEQ (MAC_OS)
  certs      create MAC_APP_DISTRIBUTION + MAC_INSTALLER_DISTRIBUTION, import to keychain
  profile    create the MAC_APP_STORE provisioning profile + install
  status     print certs / bundle id / profile state
Env: ASC_API_KEY_ID, ASC_API_ISSUER_ID, ASC_API_KEY_PATH, TEAM_ID.
"""
import base64, json, os, subprocess, sys, time, urllib.request, urllib.error
import jwt

KID = os.environ["ASC_API_KEY_ID"]; ISS = os.environ["ASC_API_ISSUER_ID"]
KEY = open(os.environ["ASC_API_KEY_PATH"]).read(); TEAM = os.environ.get("TEAM_ID", "Y4HDXFWXUV")
BUNDLE = "com.isaiahdupree.SonanceEQ"; APP_NAME = "Sonance EQ"
CERTS_DIR = os.path.expanduser("~/Documents/Software/EqualizerForMac/build/certs")
PP_DIR = os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles")

def token():
    return jwt.encode({"iss": ISS, "iat": int(time.time()), "exp": int(time.time())+1200,
                       "aud": "appstoreconnect-v1"}, KEY, algorithm="ES256",
                      headers={"kid": KID, "typ": "JWT"})

def api(method, path, body=None):
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request("https://api.appstoreconnect.apple.com"+path, data=data, method=method,
                                 headers={"Authorization": "Bearer "+token(), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.load(r) if r.length != 0 else {}
    except urllib.error.HTTPError as e:
        print(f"  HTTP {e.code}: {e.read().decode()[:300]}"); raise

def sh(*a, **k):
    return subprocess.run(a, check=True, capture_output=True, text=True, **k)

# ---- bundle id ----
def get_bundle():
    d = api("GET", f"/v1/bundleIds?filter[identifier]={BUNDLE}&limit=200")
    for b in d.get("data", []):
        if b["attributes"]["identifier"] == BUNDLE:
            return b
    return None

def cmd_bundleid():
    b = get_bundle()
    if b:
        print(f"  ✓ bundle id already registered (id {b['id']})"); return
    d = api("POST", "/v1/bundleIds", {"data": {"type": "bundleIds",
            "attributes": {"identifier": BUNDLE, "name": "Sonance EQ", "platform": "MAC_OS", "seedId": TEAM}}})
    print(f"  ✓ registered bundle id {BUNDLE} (id {d['data']['id']})")

# ---- certificates ----
def list_certs():
    return api("GET", "/v1/certificates?limit=200").get("data", [])

def create_cert(cert_type):
    os.makedirs(CERTS_DIR, exist_ok=True)
    key_path = os.path.join(CERTS_DIR, f"{cert_type}.key")
    existing = [c for c in list_certs() if c["attributes"]["certificateType"] == cert_type]
    if existing:
        cert = existing[0]
        print(f"  ✓ {cert_type} exists in account (id {cert['id']})")
        if not os.path.exists(key_path):
            print(f"    ⚠ no local private key for the existing {cert_type}; revoke it in the portal + re-run to mint a fresh keypair.")
            return cert["id"]
    else:
        sh("openssl", "genrsa", "-out", key_path, "2048")
        csr_path = os.path.join(CERTS_DIR, f"{cert_type}.csr")
        sh("openssl", "req", "-new", "-key", key_path, "-out", csr_path,
           "-subj", f"/CN=Sonance EQ {cert_type}/O=isaiah dupree/C=US")
        d = api("POST", "/v1/certificates", {"data": {"type": "certificates",
                "attributes": {"certificateType": cert_type, "csrContent": open(csr_path).read()}}})
        cert = d["data"]
        print(f"  ✓ created {cert_type} (id {cert['id']})")
    # build a .p12 (LEGACY pkcs12 encryption — OpenSSL 3 default can't be read by macOS keychain) + import
    der = base64.b64decode(cert["attributes"]["certificateContent"])
    der_path = os.path.join(CERTS_DIR, f"{cert_type}.cer")
    pem_path = os.path.join(CERTS_DIR, f"{cert_type}.pem")
    p12_path = os.path.join(CERTS_DIR, f"{cert_type}.p12")
    open(der_path, "wb").write(der)
    sh("openssl", "x509", "-inform", "DER", "-in", der_path, "-out", pem_path)
    pw = "sonance"
    sh("openssl", "pkcs12", "-export", "-legacy", "-macalg", "sha1",
       "-certpbe", "PBE-SHA1-3DES", "-keypbe", "PBE-SHA1-3DES",
       "-inkey", key_path, "-in", pem_path, "-out", p12_path, "-passout", f"pass:{pw}",
       "-name", f"Sonance {cert_type}")
    kc = os.path.expanduser("~/Library/Keychains/login.keychain-db")
    r = subprocess.run(["security", "import", p12_path, "-k", kc, "-P", pw,
                        "-T", "/usr/bin/codesign", "-T", "/usr/bin/productbuild", "-T", "/usr/bin/xcodebuild"],
                       capture_output=True, text=True)
    if r.returncode != 0 and "already exists" not in (r.stderr + r.stdout):
        print(f"    ✗ import failed: {r.stderr.strip()[:200]}")
    else:
        print(f"  ✓ imported {cert_type} into login keychain")
    return cert["id"]

def cmd_certs():
    create_cert("MAC_APP_DISTRIBUTION")
    create_cert("MAC_INSTALLER_DISTRIBUTION")

# ---- provisioning profile ----
def cmd_profile():
    b = get_bundle()
    if not b: sys.exit("  ✗ bundle id missing — run `bundleid` first")
    app_cert = [c for c in list_certs() if c["attributes"]["certificateType"] == "MAC_APP_DISTRIBUTION"]
    if not app_cert: sys.exit("  ✗ MAC_APP_DISTRIBUTION cert missing — run `certs` first")
    name = "Sonance EQ MAS"
    # delete an existing profile of the same name to avoid duplicates
    for p in api("GET", "/v1/profiles?limit=200").get("data", []):
        if p["attributes"]["name"] == name:
            api("DELETE", f"/v1/profiles/{p['id']}"); print("  · removed old profile")
    d = api("POST", "/v1/profiles", {"data": {"type": "profiles",
            "attributes": {"name": name, "profileType": "MAC_APP_STORE"},
            "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": b["id"]}},
                              "certificates": {"data": [{"type": "certificates", "id": app_cert[0]["id"]}]}}}})
    content = base64.b64decode(d["data"]["attributes"]["profileContent"])
    os.makedirs(PP_DIR, exist_ok=True)
    out = os.path.join(PP_DIR, "Sonance_EQ_MAS.provisionprofile")
    open(out, "wb").write(content)
    print(f"  ✓ created + installed profile '{name}' → {out}")

def cmd_status():
    print("certs:", [c["attributes"]["certificateType"] for c in list_certs()])
    print("bundle id:", "present" if get_bundle() else "MISSING")
    print("profiles:", [p["attributes"]["name"] for p in api("GET", "/v1/profiles?limit=200").get("data", [])])

if __name__ == "__main__":
    {"bundleid": cmd_bundleid, "certs": cmd_certs, "profile": cmd_profile,
     "status": cmd_status}[sys.argv[1]]()
