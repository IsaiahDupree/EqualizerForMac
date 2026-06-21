# Mac App Store — end-to-end runbook (repeatable)

Everything needed to ship Sonance EQ to the Mac App Store, as saved scripts. The first run was manual
discovery; this is the distilled, one-command-per-stage version. Two toolkits:

- **`Tools/asc/`** — App Store Connect: ASC REST API (certs, app metadata, IAP, submit) + a shadow-DOM
  **Safari driver** for the web-only steps (app record, pricing, age rating, privacy).
- **`Tools/rc/`** — RevenueCat: v2 REST API + the same Safari driver for the dashboard.

Run the whole thing: **`Tools/ship.sh all`** then **`Tools/ship.sh submit`**. Or stage by stage below.

---

## 0. One-time prerequisites (human, in the browser)
1. **Apple Developer Program** active.
2. **Program License Agreement** accepted — developer.apple.com (the API 403s `PLA_NOT_ACCEPTED` until then).
3. **Paid Applications Agreement + tax + banking** — App Store Connect → Business. Required for any IAP /
   paid app; until active, the **New App form won't even open**.
4. App Store Connect **API key** (`~/private_keys/AuthKey_<id>.p8`) + its key-id/issuer in the ios-deploy
   skill. `source Tools/asc/env.sh` loads these.

The signing certs (`MAC_APP_DISTRIBUTION` + `MAC_INSTALLER_DISTRIBUTION`) are created automatically by the
provision stage via the API — no Xcode account login needed.

---

## 1. The pipeline (each stage idempotent)

```bash
source Tools/asc/env.sh        # creds (ASC key/issuer/.p8, team, bundle id, RC secret)

Tools/ship.sh provision        # API: create+import the 2 Mac certs, register bundle id, make profile
Tools/ship.sh app              # BROWSER: fill App Store Connect "New App" (Tools/asc/create_app.py)
Tools/ship.sh build            # xcodebuild archive Release-MAS → export app-store .pkg
Tools/ship.sh upload           # altool --upload-app (build → Processing, ~5–30 min)
Tools/ship.sh meta             # API: description, keywords, subtitle, URLs, screenshots, IAP
Tools/ship.sh web              # BROWSER: price=Free, age=4+/Music, privacy="Data Not Collected"
Tools/ship.sh finalize         # API: content rights, copyright, export compliance
Tools/ship.sh audit            # readiness checklist (✅/❌ for every submit-time field)
Tools/ship.sh submit           # API: submit version for review (IAP intentionally NOT included)
```

`Tools/ship.sh all` runs provision→audit and stops before submit.

---

## 2. Browser automation — how it works (the load-bearing trick)

App Store Connect & RevenueCat render forms inside **nested shadow-DOM web components**, so a flat
`document.querySelector` finds nothing.

- **`Tools/asc/deepdom.js`** defines `window.__asc`: `deepAll(sel)` recurses through every `.shadowRoot`;
  `fields()` stamps a `data-asc-id` on every control and returns a descriptor list; `set/check/click/
  clickText/pick/hasText` act by that id. Elements are addressed by the stamped id, not brittle CSS paths.
- **`Tools/asc/safari.py`** injects that library via AppleScript `do JavaScript`. **It injects the code
  DIRECTLY** (not `eval(atob(...))`) — RevenueCat's CSP blocks `eval`. Helpers: `focus(host)` (bring the
  right tab to front — Safari has many), `field(label)` (id of the control whose label contains text),
  `goto`, plus CLI verbs.

Discover selectors on any page:
```bash
python3 Tools/asc/safari.py focus appstoreconnect.apple.com
python3 Tools/asc/safari.py fields            # every control, deep, with stable ids
python3 Tools/asc/safari.py find "bundle"     # filter by label
python3 Tools/asc/safari.py set 12 "Sonance EQ"
python3 Tools/asc/safari.py check 8 on        # tick a checkbox/switch
python3 Tools/asc/safari.py clicktext "Create"
```

The saved flows (`Tools/asc/web_flows.py {price|age|privacy|all}`, `Tools/asc/create_app.py`,
`Tools/rc/web_flows.py create-project`) are these primitives composed, **finding controls by label each
run** so they survive Apple/RevenueCat redesigns.

### Browser gotchas (learned the hard way)
- **Wrong tab.** `do JavaScript` targets the *front document*. Always `focus("<host>")` first.
- **Transient React menus** close between automation calls. Prefer the destination URL (e.g. RevenueCat
  "Create new project" is just a link to `/projects/add`) over puppeteering a dropdown.
- **CSP blocks eval** → the driver injects JS directly (already handled).
- **Click that navigates** → the `do JavaScript` call may report an AppleEvent timeout even though the
  click worked; verify via the API (`audit.py` / `api.py status`) rather than the click's return.

---

## 3. RevenueCat wiring (after the free app is approved, with the IAP update)
```bash
python3 Tools/rc/web_flows.py create-project "Sonance EQ"   # done → project 0df95734 (BROWSER)
# BROWSER: add the App Store app (bundle id) + upload an App Store Connect *In-App Purchase Key* (.p8 from
#          ASC → Users and Access → Integrations → In-App Purchase) so RC can validate purchases.
# BROWSER: Project settings → API keys → mint a Sonance-scoped secret key (sk_…).
RC_SECRET_KEY=sk_… RC_PROJECT_ID=0df95734 python3 Tools/rc/api.py setup   # entitlement+product+offering
python3 Tools/rc/web_flows.py public-key 0df95734           # read the appl_ public SDK key
python3 Tools/rc/set_key.py appl_…                          # paste into LicenseConfig (mock → live)
Tools/ship.sh build && Tools/ship.sh upload                 # rebuild with the live key
# then submit the IAP with the next version via Tools/asc/submit.py (include the IAP item)
```

---

## 4. Submit-time required fields (what `audit.py` checks — all caught us once)
content rights · primary category · age rating · name · subtitle · privacy-policy URL · build attached ·
description · keywords · ≥1 screenshot · price schedule · App Privacy published · IAP `READY_TO_SUBMIT`
(needs localization **+ price + review screenshot + all-territory availability**) · **copyright** ·
**export compliance** (`usesNonExemptEncryption=false`) · **App Review contact** (name/phone/email,
`demoAccountRequired=false`). The review submission's `associatedErrors` is the source of truth — it lists
exactly what's missing.

## State (Sonance EQ, this account)
App `6782463839` · version 1.0 **WAITING_FOR_REVIEW** (free, IAP excluded) · IAP `…​.pro` READY_TO_SUBMIT ·
RevenueCat project `0df95734` created, wiring pending the In-App Purchase Key.
