# Lessons Learned — Sonance EQ (through first sale)

Durable lessons worth carrying into the next app. Kept short on purpose; each one cost real time to learn.

## Shipping & distribution

1. **"Live" is not one bit — it's a chain, and every link is scriptable except the human gates.** Bundle id →
   certs → provisioning profile → app record → build/sign/export → upload → IAP → agreements → pricing →
   submit. `Tools/asc/` automates all of it *except* the three Apple makes account-holder-only (PLA, Paid Apps
   agreement, Submit for Review). Know which links are human before you plan a release day.
2. **The Paid Apps Agreement is a hard prerequisite for selling anything.** Until it's Active, the New App form
   won't even open. Ours went Active Jun 20 — same day as launch. Do this *first* next time.
3. **App Store Connect renders forms in nested shadow DOM.** Flat `document.querySelector` finds nothing. The
   `deepdom.js` shadow-piercing driver (`Tools/asc/safari.py`) is what made the browser steps automatable —
   reuse it verbatim for the next app.

## Money & verification

4. **Know where the money actually lands before you go looking for it.** We burned a whole detour in
   RevenueCat — which pointed at a *different* app (EverReach). A direct StoreKit IAP with no live RevenueCat
   key never touches RevenueCat; the truth is in App Store Connect's Sales Reports. Map the payment path first.
5. **The vendor number is the key to headless revenue, and it's weirdly hidden.** Not the `providerId`, not on
   disk, not in any config — it's an 8-digit number on the Business Agreements page. Once you have it, sales
   verification is a cron-able API call forever. (Ours: `93676981`. See the runbook.)
6. **Sales Reports API only speaks gzip** (`Accept: application/a-gzip`) and lags ~1 day. App Analytics is
   role-gated and useless for a brand-new app; Sales & Trends has no threshold. Use the right endpoint.
7. **A logged-in browser session is a credential.** Same-origin synchronous XHR from an authenticated
   `/apps` tab reaches internal endpoints (`/olympus/v1/session`) that no API key exposes. Living off the land
   beats re-authenticating — but note step-up-auth sections (`/trends`, `/analytics`) sit behind a cross-origin
   `idmsa` iframe you can't script.

## Product & engineering

8. **The moat is the system-level capability, not the UI.** Anyone can draw EQ faders. Almost no one wires
   Core Audio process taps + a private aggregate device + a wait-free real-time engine. That's why we beat
   Safari-only competitors — and it's the reusable asset for the next app.
9. **Prove DSP offline, on the audio thread's terms.** `Tools/verify_{biquad,fir,midside}.swift` compile
   against the *shipping* sources and caught the `vDSP_biquadm(M=sections, N=channels)` argument-order trap
   that segfaults on the audio thread. Real-time bugs don't show up in a UI click-test; prove them cold.
10. **Freemium converted on buyer #1.** Free download + Pro unlock (AutoEq library, parametric, FIR, mid-side,
    per-app) was the right split. Lead with a genuinely useful free tier; gate the power features.
11. **Guard OS-version-specific APIs from day one.** Min OS 14.4 (process-tap floor) with `#available` guards
    for macOS-26-only tap features (`bundleIDs`, `processRestoreEnabled`) meant one binary serves everyone.

## Meta

12. **Build the tooling as you go, not after.** The `Tools/asc/` toolkit, the offline DSP verifiers, the
    packaging script — each was built to solve a real blocker and each paid for itself again during
    verification. The next app starts with this toolbox already in hand.
