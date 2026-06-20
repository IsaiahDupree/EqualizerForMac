# Sonance EQ — Mac App Store path

**Status: technically de-risked. The build variant exists and works; only the Apple-side records remain.**

The direct (Developer ID, notarized) build already ships on GitHub Releases. This is the parallel
Mac App Store build — same app, sandboxed, public permission flow.

---

## The make-or-break question — ANSWERED ✅

*Does the driverless process-tap loop (tap → private aggregate → IOProc → re-inject) work under the
mandatory App Sandbox?* **Yes — verified empirically, two ways:**

1. **`Tools/sandbox_tap_probe.swift`** runs the exact Core Audio sequence from `SystemAudioTap.build()`.
   Wrapped in a `.app` bundle, ad-hoc-signed with `app-sandbox` + `device.audio-input`, every call
   returns `noErr` and render callbacks fire (≈133 in 1.5 s). The same binary as a bare executable is
   killed by the sandbox at launch (SIGTRAP) — the sandbox **is** active; the tap simply works inside it.
2. **The full `SonanceEQ.app` built in `Release-MAS`**, sandbox-signed, launches and runs with a real
   sandbox container at `~/Library/Containers/com.isaiahdupree.SonanceEQ`.

This was the one thing that could have killed the MAS path (no tap-only EQ had publicly confirmed
shipping on the MAS). It's clear.

---

## The build

`Release-MAS` configuration (see `project.yml`):
- **App Sandbox on**, **no private TCC SPI** (`SWIFT_ACTIVE_COMPILATION_CONDITIONS` drops `ENABLE_TCC_SPI`),
  hardened runtime on.
- Entitlements `Sources/SonanceEQ/Resources/SonanceEQ-MAS.entitlements`:
  `app-sandbox`, `device.audio-input` (the tap), `network.client` (RevenueCat/StoreKit),
  `files.user-selected.read-write` (preset import/export + recording to a chosen file).

```bash
# compile check
xcodebuild -project SonanceEQ.xcodeproj -scheme SonanceEQ -configuration Release-MAS \
  -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build
# archive → export .pkg → (optional) upload
Tools/build_mas.sh           # preflights and tells you what's missing
Tools/build_mas.sh --upload
```

## Permission flow (MAS-safe)
`AudioRecordingPermission` already has the public path under `#else` (no `ENABLE_TCC_SPI`): it assumes
authorized and lets the system prompt on first capture. No private API → no Guideline 2.5.1 exposure.

---

## ⛔ Current hard blocker: Program License Agreement (PLA)

A read-only probe of the App Store Connect API (the account-level ASC key, JWT auth — verified working)
returns **`403 FORBIDDEN_ERROR.PLA_NOT_ACCEPTED`** ("Program License Agreement update available") for every
endpoint. This blocks **all** API operations — listing/creating certs, registering the bundle id, creating
the app record, and uploading. It is account-wide and can only be cleared by the **Account Holder accepting
the updated agreement** at developer.apple.com (or on App Store Connect login). There is no CLI bypass.

**Until the PLA is accepted, none of the steps below can run.** Once accepted, they are fully scriptable.

What we already have (found by "living off the land"): Team ID `Y4HDXFWXUV`, the ASC API key id + issuer
(ios-deploy skill) + the `.p8` on disk, a Developer ID cert, and the `fastlane mac app_store` lane wired to
`Release-MAS`. Missing only: the App Store distribution cert + the App Store Connect app record (both
PLA-gated).

## Remaining steps — all Apple-account / outward-facing (need your go)

1. **App Store Connect app record** — create the app under bundle id `com.isaiahdupree.SonanceEQ`
   (same id as the direct build is fine; they're different distribution channels).
2. **In-App Purchase** — create the non-consumable `com.isaiahdupree.SonanceEQ.pro`; submit it with the app.
3. **RevenueCat** — create the **MAS** app in RevenueCat (separate from the direct app ⇒ a *different*
   public key), attach the `pro` entitlement + the product, paste the key into
   `LicenseConfig.revenueCatPublicAPIKey`. The mock store auto-switches to live.
4. **Signing** — an "Apple Distribution" (or "3rd Party Mac Developer Application") cert + a MAS
   provisioning profile in the keychain.
5. **Upload** — `Tools/build_mas.sh --upload` (reuses the account ASC API key), or drop the `.pkg` into
   Transporter.app.
6. **Listing** — screenshots, description, and review notes (below), then submit.

## Review-note talking points (preempt rejections)
- **2.5.1 (private API):** none — Release-MAS uses no private TCC SPI; permission is the public prompt.
- **2.4.5 / 2.5.2 (drivers / self-contained):** Sonance EQ is **driverless** (Core Audio process taps);
  it installs no kext, helper, or login item and is fully self-contained in the sandbox.
- **5.1.1 (permission purpose):** `NSAudioCaptureUsageDescription` explains the EQ use plainly; recording
  is strictly opt-in and writes only to a user-chosen file.
- **Known limitation:** DRM/FairPlay audio (some Apple Music/Netflix) passes through un-EQ'd — an Apple
  platform constraint shared by every app in this class.
