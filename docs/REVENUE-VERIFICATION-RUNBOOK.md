# Revenue Verification Runbook — "Did we actually get paid?"

The reproducible navigation path we used to confirm Sonance EQ's first paid sale **entirely from this
Mac**, living off the land. Copy-paste ready. Written 2026-07-03.

> TL;DR: your Safari session unlocks the vendor number; the vendor number unlocks the headless Sales
> Reports API. Everything else is a login wall you don't need to touch.

---

## The map (why each hop exists)

```
RevenueCat MCP ──✗ dead end (points at EverReach, not Sonance EQ; Pro is a one-time StoreKit IAP)
                     │
App Store Connect API (Tools/asc) ──✓ confirms app is LIVE + IAP APPROVED
   JWT/ES256 via ~/private_keys/AuthKey_VBDA4SUDJV.p8      but ✗ can't read $ without a vendor number
                     │
Safari (logged-in ASC session) ──✓ /apps and /business share the session
   /trends + /analytics ──✗ force step-up re-auth (cross-origin idmsa iframe, can't script)
                     │
Same-origin XHR from /apps ──✓ /olympus/v1/session → provider info
Scrape /business page ──✓ VENDOR NUMBER = 93676981
                     │
Sales Reports API + vendor number ──✓✓ actual units + proceeds TSV  ← ground truth
```

---

## Step 0 — creds (already on this machine)

```bash
cd ~/Documents/Software/EqualizerForMac
source Tools/asc/env.sh        # → "asc env ready (key=VBDA4SUDJV, team=Y4HDXFWXUV)"
```
Resolves `ASC_API_KEY_ID`, `ASC_API_ISSUER_ID` (from the ios-deploy skill), `ASC_API_KEY_PATH`
(`~/private_keys/AuthKey_VBDA4SUDJV.p8`).

## Step 1 — confirm the app is live + IAP approved (pure API, no browser)

```bash
python3 scratchpad/asc_confirm.py   # or reuse Tools/asc/api.py status
```
Expect: app `6782463839`, v1.0.x `READY_FOR_SALE`, IAP `com.isaiahdupree.SonanceEQ.pro` = `APPROVED`.

## Step 2 — get the vendor number (browser, one-time)

The Sales Reports API **requires** `filter[vendorNumber]`. It is **not** the `providerId` and is **not**
cached on disk. It lives on the logged-in Business page.

1. Confirm Safari has a live session (no login redirect):
   ```bash
   osascript -e 'tell application "Safari" to set URL of front document to "https://appstoreconnect.apple.com/apps"'
   python3 Tools/asc/safari.py eval "location.href"   # stays on /apps == logged in
   ```
2. Read the Business Agreements page (shares the /apps session):
   ```bash
   osascript -e 'tell application "Safari" to set URL of front document to "https://appstoreconnect.apple.com/business"'
   # wait ~15s for the SPA to render, then:
   python3 Tools/asc/safari.py eval "(document.body.innerText||'').replace(/\s+/g,' ').slice(0,400)"
   ```
   The 8-digit number next to your address **is the vendor number**. Ours: **`93676981`**.

   > If Safari is NOT logged in, `/apps` bounces to `/login` (an `idmsa` iframe that can't be scripted —
   > cross-origin + 2FA). Log in by hand once, then this whole runbook is headless again.

## Step 3 — pull the real money (headless, repeatable)

```bash
python3 scratchpad/asc_pull.py 93676981      # daily SALES SUMMARY, Jun 20 → today
```
Raw endpoint (per day):
```
GET /v1/salesReports
  ?filter[frequency]=DAILY&filter[reportType]=SALES&filter[reportSubType]=SUMMARY
  &filter[reportDate]=YYYY-MM-DD&filter[vendorNumber]=93676981&filter[version]=1_0
Header: Accept: application/a-gzip        # NOT application/json → gunzip the body to a TSV
```

### Reading the TSV
| Product Type | Meaning |
|---|---|
| `F1` | Free Mac app download (first-time) |
| `F7` | Free Mac app update |
| `IA1-M` | Mac non-consumable in-app purchase ← **the paid unlock** |

Columns that matter: `Units`, `Customer Price`, `Developer Proceeds`, `Title`, `Product Type Identifier`.

---

## Gotchas (each cost us a probe)

- **`Accept: application/json` → 406.** Sales reports only speak `application/a-gzip`. Gunzip the body.
- **Bad vendor number → 500** (not a clean 400) if it's malformed; a *valid-format-but-wrong* number → 400
  `"Invalid vendor number specified."` Either way: wrong number, no data.
- **`providerId` ≠ vendor number.** `/olympus/v1/session` gives `providerId` (128125412) — Apple rejects it.
- **Apple daily reports lag ~1 day.** "Today" is usually empty until tomorrow.
- **App Analytics is role-gated** ("currently unavailable for Analytics") — Sales & Trends / Sales Reports
  have no such threshold, so prefer them for a brand-new app.
- **RevenueCat is the wrong tool here.** Our `revenuecat-mcp` points at the EverReach project, and Sonance
  Pro is a direct StoreKit IAP that never touches RevenueCat. App Store Connect is the source of truth.
