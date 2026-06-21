# rc/ — RevenueCat wiring toolkit (CLI + browser)

Wires the Pro IAP (`com.isaiahdupree.SonanceEQ.pro`) to RevenueCat so purchases actually validate. Mirrors
the `asc/` toolkit: a v2 REST CLI for what the API allows, the shared shadow-DOM Safari driver for the
dashboard-only steps (RevenueCat's CSP blocks `eval`, so `asc/safari.py` injects JS directly).

## Pieces
| File | Role |
|------|------|
| `api.py` | RevenueCat **v2 REST** client (project-scoped secret `sk_…`): apps, entitlements, products, offerings, packages. `projects · apps · setup`. |
| `set_key.py` | Pastes the public SDK key (`appl_…`) into `LicenseConfig` → app flips from mock store to live. |
| (browser) `../asc/safari.py` | Drives the RevenueCat dashboard for the API-impossible steps (project creation, App Store app + ASC integration key, reading keys). |

## State (this session)
- ✅ **Project "Sonance EQ" created** (id `0df95734`) — via the browser driver.
- The account's other v2 secret keys are **project-scoped to EverReach**, so the CLI needs a secret key
  minted *for the Sonance project* (dashboard → Project settings → API keys → + Secret key).

## Remaining wiring (ordered)
1. **App Store app** — Sonance project → add app, type App Store, bundle id `com.isaiahdupree.SonanceEQ`.
2. **App Store Connect integration** — generate an **In-App Purchase Key** in App Store Connect
   (Users and Access → Integrations → In-App Purchase) and upload its `.p8` to the RevenueCat app, so RC
   can fetch products + validate receipts. *(This is the one true cross-system step.)*
3. **Products / entitlement / offering** — `RC_SECRET_KEY=sk_… RC_PROJECT_ID=0df95734 python3 Tools/rc/api.py setup`
   (creates entitlement `pro`, product `…​.pro`, offering `default` + a `lifetime` package, all attached).
   Or do it in the dashboard wizard.
4. **Public SDK key** — dashboard → API keys → public `appl_…` → `python3 Tools/rc/set_key.py appl_…`.
5. **Rebuild + re-upload** the MAS build (now live, not mock) and submit the IAP as the 1.0.1 update
   (`Tools/asc/iap.py` already made it READY_TO_SUBMIT; include it in the next `Tools/asc/submit.py`).

## Why the app is safe to ship free first
`PurchaseManager` runs the **mock store** while `LicenseConfig.revenueCatPublicAPIKey` is the sentinel
(no network, Pro logic exercised). `set_key.py` swaps in the real key → live store, no code change.
