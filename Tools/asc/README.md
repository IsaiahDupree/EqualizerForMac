# asc/ — Mac App Store upload automation toolkit

Automates the whole "ship Sonance EQ to the Mac App Store" pipeline, including the **browser-only** steps
Apple's API refuses to do. Built because App Store Connect renders its forms in **nested shadow-DOM web
components** — flat `document.querySelector` finds nothing, so this toolkit ships a shadow-piercing driver.

## Pieces

| File | Role |
|------|------|
| `deepdom.js` | Injected JS: `window.__asc` — shadow-DOM-piercing `deepAll`, `fields()` (stamps `data-asc-id`), `set/check/click/clickText/pick`, `hasText`. The thing that makes Apple's web components driveable. |
| `safari.py` | Drives Safari's front doc via `do JavaScript`, auto-injecting `deepdom.js` (base64'd to dodge all escaping). CLI: `goto · fields · find · set · check · click · clicktext · pick · waitfor · eval`. |
| `api.py` | App Store Connect REST client (JWT/ES256 via the account `.p8`): certs, bundle ids, provisioning profiles, app lookup, in-app purchases. |
| `create_app.py` | Browser flow for the New App record (API-forbidden). **Adaptive** — finds fields by label each run, so it tolerates selector churn. Verifies via the API. |
| `pipeline.py` | One idempotent orchestrator: provision → app record → build/sign/export → upload → IAP. Detects human-gated blockers and stops with a clear message. |

## "Obtaining all selectors"

```bash
python3 Tools/asc/safari.py fields          # every interactive control, deep, with stable ids
python3 Tools/asc/safari.py find "bundle"   # filter by label/text
python3 Tools/asc/safari.py set 12 "Sonance EQ"
python3 Tools/asc/safari.py check 4 on      # tick the macOS platform box
python3 Tools/asc/safari.py clicktext "Create"
```
Because actions address elements by the `data-asc-id` stamped during `fields()`, you discover and drive in
the same vocabulary — no brittle hand-written CSS paths, and it works inside shadow roots.

## Run the whole thing

```bash
export ASC_API_KEY_ID=… ASC_API_ISSUER_ID=… ASC_API_KEY_PATH=~/private_keys/AuthKey_<id>.p8 TEAM_ID=Y4HDXFWXUV
python3 Tools/asc/pipeline.py status   # see what's done / missing
python3 Tools/asc/pipeline.py          # do everything up to the next human gate
```

## Human-gated (Apple makes these account-holder-only — the toolkit detects + reports, never fakes them)
1. **PLA** — Apple Developer Program License Agreement (developer.apple.com).
2. **Paid Applications Agreement + tax + banking** — App Store Connect → Business. Required to sell a paid
   app; until it's active, the New App form won't even open.
3. **Submit for Review** — final human action after pricing + screenshots.

## State already provisioned (this account)
Team `Y4HDXFWXUV` · bundle id `com.isaiahdupree.SonanceEQ` ✓ · `MAC_APP_DISTRIBUTION` + `MAC_INSTALLER_DISTRIBUTION`
certs ✓ (in login keychain) · `Sonance EQ MAS` provisioning profile ✓. Blocked only on the Paid Apps
agreement → then `pipeline.py` finishes app-record → build → upload → IAP unattended.
