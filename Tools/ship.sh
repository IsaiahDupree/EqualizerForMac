#!/bin/bash
# ship.sh — the whole Mac App Store pipeline in stages. Each stage is idempotent; re-run after fixing a
# gate and it continues. Run a single stage by name, or `all`. Browser stages need Safari signed in to
# App Store Connect (and RevenueCat for the rc stage). Human gates are flagged ⛔ and stop the run.
#
#   Tools/ship.sh provision   # certs + bundle id + provisioning profile (API)
#   Tools/ship.sh app         # create the App Store Connect app record (BROWSER)
#   Tools/ship.sh build       # archive Release-MAS + export the signed .pkg
#   Tools/ship.sh upload      # upload the .pkg (altool + API key)
#   Tools/ship.sh meta        # description/keywords/screenshots/IAP (API)
#   Tools/ship.sh web         # price=Free + age=4+ + privacy=no-data (BROWSER)
#   Tools/ship.sh finalize    # content rights + export compliance (API)
#   Tools/ship.sh audit       # readiness checklist
#   Tools/ship.sh submit      # submit for review (free app; IAP excluded)
#   Tools/ship.sh all         # provision → … → audit  (stops before submit)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
source Tools/asc/env.sh
P=python3
stage(){ echo; echo "════ $1 ════"; }

s_provision(){ stage provision; $P Tools/asc/api.py certs; $P Tools/asc/api.py bundleid; $P Tools/asc/api.py profile; }
s_app(){ stage "app record (browser)"; $P Tools/asc/create_app.py; }
s_build(){ stage build; bash Tools/build_mas.sh; }
s_upload(){ stage upload; xcrun altool --upload-app --type macos --file build/appstore/SonanceEQ.pkg \
              --apiKey "$ASC_API_KEY_ID" --apiIssuer "$ASC_API_ISSUER_ID"; }
s_meta(){ stage metadata; $P Tools/asc/metadata.py; $P Tools/asc/screenshots.py; $P Tools/asc/iap.py 9.99; }
s_web(){ stage "web flows (browser)"; $P Tools/asc/web_flows.py all; }
s_finalize(){ stage "finalize (content rights + export compliance)"; $P - <<'PY'
import sys; sys.path.insert(0,"Tools/asc")
from api import api, get_app
a=get_app(); aid=a["id"]
api("PATCH",f"/v1/apps/{aid}",{"data":{"type":"apps","id":aid,"attributes":{"contentRightsDeclaration":"DOES_NOT_USE_THIRD_PARTY_CONTENT"}}})
v=api("GET",f"/v1/apps/{aid}/appStoreVersions?limit=1")["data"][0]
api("PATCH",f"/v1/appStoreVersions/{v['id']}",{"data":{"type":"appStoreVersions","id":v["id"],"attributes":{"copyright":"2026 Isaiah Dupree"}}})
b=api("GET",f"/v1/appStoreVersions/{v['id']}/relationships/build").get("data")
if b: api("PATCH",f"/v1/builds/{b['id']}",{"data":{"type":"builds","id":b["id"],"attributes":{"usesNonExemptEncryption":False}}})
print("✓ content rights · copyright · export compliance set")
PY
}
s_audit(){ stage audit; $P Tools/asc/audit.py; }
s_submit(){ stage submit; $P Tools/asc/submit.py; }

case "${1:-all}" in
  provision) s_provision;; app) s_app;; build) s_build;; upload) s_upload;;
  meta) s_meta;; web) s_web;; finalize) s_finalize;; audit) s_audit;; submit) s_submit;;
  all) s_provision; s_app; s_build; s_upload; s_meta; s_web; s_finalize; s_audit
       echo; echo "▶ review the audit, then: Tools/ship.sh submit";;
  *) grep '^#' "$0" | sed 's/^# \{0,1\}//';;
esac
