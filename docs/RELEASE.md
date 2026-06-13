# Release Runbook

> **Two ways to drive this:** plain shell (`Tools/*.sh`, zero dependencies) or **fastlane**
> (`fastlane mac release` / `fastlane mac appstore` — see [`fastlane/README.md`](../fastlane/README.md)).
> Both reuse the same account-level App Store Connect API key. Pick whichever you prefer.

Two distribution paths. **Lead with Direct** — the Mac App Store path is the project's #1 rejection risk
(system-audio capture under the App Store sandbox is unproven; see `docs/RESEARCH.md`).

> Note on EverReach: that app ships via **Expo / EAS** (`eas submit`), which only handles React-Native
> iOS/Android — it does **not** apply to this native macOS Xcode app. What *is* reused is the
> **account-level App Store Connect API key** (`~/private_keys/AuthKey_*.p8`) and your Apple Team — so no
> new Apple account setup is needed.

---

## What you already have
- Apple Developer Program membership + Team ID.
- An **App Store Connect API key** on disk (`~/private_keys/AuthKey_*.p8`) — reusable for notarization
  **and** App Store upload.

## What's still needed (each is a few minutes in Apple's portals)
| For | Need | Where |
|-----|------|-------|
| Direct (notarized DMG) | **Developer ID Application** certificate | Xcode → Settings → Accounts → Manage Certificates → ＋ *Developer ID Application*, or developer.apple.com → Certificates |
| Notarization | the API key's **Issuer ID** | App Store Connect → Users and Access → **Integrations** → App Store Connect API |
| Mac App Store | a **Sonance EQ app record**, an **Apple Distribution** cert, a **MAS provisioning profile** | App Store Connect + developer.apple.com |

---

## Creating the Developer ID Application certificate

⚠️ Apple **does not allow** Developer ID certificate creation via the App Store Connect API — it returns
`403 "This operation can only be performed by the Account Holder."` (API keys max out at Admin). It must be
created by the **Account Holder**, one of two ways:

- **Easiest — Xcode (2 clicks):** Xcode → Settings → Accounts → select the team → **Manage Certificates…**
  → **＋** → **Developer ID Application**. Xcode generates the key + cert directly in your keychain. Done.
- **Or upload our prepared CSR:** a keypair + CSR were already generated at
  `~/private_keys/sonance_devid_key.pem` and `~/private_keys/sonance_devid.csr`. Go to
  developer.apple.com → Certificates → **＋** → *Developer ID Application* → upload `sonance_devid.csr` →
  download the `.cer`, then:
  ```bash
  Tools/import_developer_id.sh ~/Downloads/developerID_application.cer
  ```
  which installs the cert + private key and prints the `DEVELOPER_ID` identity string.

Verify with `security find-identity -p codesigning -v | grep "Developer ID Application"`.

## Path A — Direct distribution (recommended): notarized DMG

### Locally
```bash
export DEVELOPER_ID="Developer ID Application: <Your Name> (<TEAMID>)"
export NOTARY_KEY="$HOME/private_keys/AuthKey_<KEYID>.p8"
export NOTARY_KEY_ID="<KEYID>"
export NOTARY_ISSUER="<ISSUER-UUID>"
./Tools/package_and_notarize.sh        # → build/Sonance-EQ.dmg (signed, notarized, stapled)
```

### Via CI (tag → GitHub Release)
1. Add repo secrets (Settings → Secrets and variables → Actions):
   - `DEVELOPER_ID_CERT_P12` — `base64 -i DeveloperID.p12 | pbcopy`
   - `DEVELOPER_ID_CERT_PASSWORD`, `DEVELOPER_ID_NAME`
   - `ASC_API_KEY_P8` (contents of the .p8), `ASC_API_KEY_ID`, `ASC_API_ISSUER_ID`
2. Tag and push:
   ```bash
   git tag v1.0.0 && git push origin v1.0.0
   ```
   `.github/workflows/release.yml` builds, notarizes, and publishes a **GitHub Release** with the DMG.

---

## Path B — Mac App Store

⚠️ Before investing here, confirm the tap-based capture works under the App Store **sandbox** with the
**public** permission flow (the MAS build compiles **without** `ENABLE_TCC_SPI`). This is unverified and is
the main reason to ship Direct first.

```bash
export ASC_API_KEY_ID="<KEYID>"
export ASC_API_ISSUER="<ISSUER-UUID>"
export ASC_APP_ID="<app record id from App Store Connect>"
export DIST_IDENTITY="Apple Distribution: <Your Name> (<TEAMID>)"
export PROVISIONING_PROFILE_NAME="<MAS profile name>"
export DEVELOPMENT_TEAM="<TEAMID>"
./Tools/submit_appstore.sh             # archive (sandboxed) → .pkg → validate → upload
```
Then finish the submission (screenshots, metadata, review notes) in App Store Connect. RevenueCat IAP also
needs the live key in `LicenseConfig` and the product attached (see CLAUDE.md → Licensing).

---

## RevenueCat (both paths, for the paid unlock)
1. Create the Sonance EQ app(s) in RevenueCat (Direct vs MAS may be separate apps/keys).
2. Add a `pro` entitlement; attach the one-time product `com.isaiahdupree.SonanceEQ.pro`.
3. Put the **public** SDK key in `Sources/SonanceEQ/Licensing/LicenseConfig.swift` → the mock store
   auto-switches to the live RevenueCat path (no other code change).
