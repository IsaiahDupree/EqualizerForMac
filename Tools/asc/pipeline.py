#!/usr/bin/env python3
"""pipeline.py — one orchestrator for the whole Mac App Store upload, mixing the API (cert/bundle/profile/
IAP) and browser (app record) layers, plus the local build/sign/upload. Idempotent and resumable: every
step checks current state first, so re-running after fixing a blocker just continues.

  python3 Tools/asc/pipeline.py            # run every step, stopping at the first human-gated blocker
  python3 Tools/asc/pipeline.py status     # just print state

Human-gated blockers it detects and reports (it can't do these): accepting the PLA / Paid Apps agreement,
tax + banking, and any App Store review submission. Everything else is automated.
"""
import os, subprocess, sys
sys.path.insert(0, os.path.dirname(__file__))
import api

REPO = os.path.expanduser("~/Documents/Software/EqualizerForMac")

def step(title): print(f"\n▸ {title}")

def run():
    step("Provision (certs · bundle id · profile)")
    api.ensure_cert("MAC_APP_DISTRIBUTION"); api.ensure_cert("MAC_INSTALLER_DISTRIBUTION")
    api.ensure_bundle(); api.ensure_profile()

    step("App Store Connect record")
    if api.get_app():
        print("  ✓ app record present")
    else:
        print("  · creating via browser (create_app.py)")
        r = subprocess.run([sys.executable, os.path.join(os.path.dirname(__file__), "create_app.py")])
        if api.get_app() is None:
            sys.exit("  ⛔ app record not created — likely the Paid Applications agreement. "
                     "Accept it in App Store Connect → Business, then re-run pipeline.py.")

    step("Build · sign · export the .pkg (Release-MAS)")
    subprocess.run(["bash", os.path.join(REPO, "Tools", "build_mas.sh")], check=True)

    step("Upload to App Store Connect")
    pkg = os.path.join(REPO, "build", "appstore", "SonanceEQ.pkg")
    subprocess.run(["xcrun", "altool", "--upload-app", "--type", "macos", "--file", pkg,
                    "--apiKey", os.environ["ASC_API_KEY_ID"], "--apiIssuer", os.environ["ASC_API_ISSUER_ID"]], check=True)

    step("In-App Purchase (Pro unlock)")
    api.ensure_iap()

    print("\n✅ build uploaded + IAP ensured. Remaining (web): pricing, screenshots, and Submit for Review.")
    print("   Then wire RevenueCat: Tools/asc/revenuecat.py")

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "status":
        api.status()
    else:
        run()
