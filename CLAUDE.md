# Sonance EQ — Project Context for Claude Code

System-wide macOS equalizer. Driverless (Core Audio process taps). Goal: beat Safari-only
equalizers by EQ-ing the **entire Mac** with high precision + a huge preset library.

## Decisions (locked with the user)
- **Name:** Sonance EQ · bundle id `com.isaiahdupree.SonanceEQ`
- **Scope (ambitious):** system-wide tap EQ **+ per-app EQ + virtual-driver fallback** (older macOS)
- **Distribution:** direct (Developer ID + notarization) **and** Mac App Store
- **Monetization:** one-time paid (RevenueCat IAP)
- **Min OS:** 14.4 (process-tap floor; macOS-26-only tap features like `bundleIDs` / `processRestoreEnabled` are guarded with `#available`)

## How to build
The `.xcodeproj` is generated and git-ignored. Always:
```bash
xcodegen generate
xcodebuild -project SonanceEQ.xcodeproj -scheme SonanceEQ -configuration Debug \
  -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO build   # compile check
```
Edit `project.yml`, never the `.xcodeproj`. Swift language mode is **5** (set in project.yml) to keep
Core Audio IOProc closures simple; the one Swift-6 concurrency hotspot (EQEngine lock closure) is already clean.

## Architecture / file map
```
Sources/SonanceEQ/
  App/SonanceEQApp.swift        @main; `kSubsystem` logger string lives here
  App/AppState.swift            @MainActor @Observable; ties EQ + tap + UI; pushSettings()
  AudioEngine/
    CoreAudioProperties.swift   AudioObjectID property-read helpers (our own)
    AudioRecordingPermission.swift  TCC kTCCServiceAudioCapture via private SPI behind ENABLE_TCC_SPI
    SystemAudioTap.swift        THE CORE: tap + private aggregate + IOProc re-injection + device-change rebuild
  DSP/Biquad.swift              FilterType (+usesGain) + BiquadCoeffs + RBJ cookbook coefficients
  DSP/EQEngine.swift            real-time engine; two chains (Mid/Side); control plane (update) vs audio plane (beginRender/process/processMidSide)
  DSP/FrequencyResponse.swift   magnitude-response (dB) of the band cascade for the editor curve
  DSP/FIRDesigner.swift         linear-phase FIR design (frequency-sampling IDFT + L/2-centered Blackman); proven by Tools/verify_fir.swift
  DSP/FIRProcessor.swift        streaming overlap convolution (vDSP_conv + per-channel history), 2 filter slots (Mid/Side), wait-free swap; L=2048 → ~21ms latency
  UI/ResponseCurveView.swift    parametric editor: live curve + draggable band handles + inspector (type/Q/gain), add/remove
  Models/EQBand.swift           band model (freq/gain/Q/type/enabled)
  Models/Presets.swift          starter presets (10-band graphic)
  Models/AutoEqPreset.swift     one AutoEq headphone correction; bands() → [EQBand]
  Models/PresetStore.swift      @MainActor SQLite reader over bundled autoeq.sqlite (import SQLite3); search(text,category)
  Models/PresetFile.swift       portable versioned import/export JSON (PortableBand, no UUIDs)
  UI/PresetBrowserView.swift    searchable headphone-library sheet (Pro-gated via license.canUse(.autoEqLibrary))
  Licensing/LicenseConfig.swift  M3-fillable RevenueCat IDs (public key/entitlement/offering/product) + ProFeature enum
  Licensing/PurchaseManager.swift @MainActor @Observable; configures RevenueCat, tracks isPro, purchase/restore. Unconfigured key ⇒ Pro-unlocked, no network (dev/eval safe)
  UI/ContentView.swift          faders, presets, preamp, bypass, permission banner
  Resources/                    Info.plist + entitlements (generated/maintained via project.yml)

references/                     git-ignored study-only clones (AudioCap, eqMac, AutoEq) — see references/README.md. DO NOT copy code; data (AutoEq presets) is fair to ship with attribution.
```

## Licensing (RevenueCat, wired early — M3 fills the IDs)
- SPM dep `RevenueCat` (`from: 5.0.0`) added in project.yml. `PurchaseManager` is held by `AppState` and `start()`ed in its init.
- **Dev/eval builds run Pro-unlocked with zero network** while `LicenseConfig.revenueCatPublicAPIKey` is the `REVENUECAT_PUBLIC_KEY_TODO` sentinel — so M1/M2 work and the headless compile-check are unaffected.
- Gating lives in one place: `PurchaseManager.canUse(_ feature: ProFeature)`. Default free tier = M1 10-band graphic EQ + built-in presets; Pro = parametric/AutoEq library/import-export/per-app.
- **M3 TODO:** create the Sonance EQ app(s) in RevenueCat (direct vs MAS = two apps/keys), a `pro` entitlement, a one-time non-consumable in App Store Connect (`com.isaiahdupree.SonanceEQ.pro`), fill the public key(s), and add a paywall + In-App-Purchase capability. RevenueCat account today only has EverReach.

## The audio loop (the load-bearing part)
1. `CATapDescription(stereoGlobalTapButExcludeProcesses: [selfObjectID])` — global stereo tap of all
   processes EXCEPT us (self-exclusion prevents feedback). `muteBehavior = .mutedWhenTapped`, `isPrivate = true`.
2. `AudioHardwareCreateProcessTap` → tapID. Read `kAudioTapPropertyFormat` for the stream format.
3. Build a **private aggregate device**: `kAudioAggregateDeviceMainSubDeviceKey` = real default-output UID
   (clock master), `kAudioAggregateDeviceTapListKey` = [the tap], `kAudioAggregateDeviceSubDeviceListKey`
   = [real output], `private`/`tapautostart` = true.
4. `AudioDeviceCreateIOProcIDWithBlock`: in the block, `inInputData` = tapped audio, `outOutputData` =
   real device buffers. Copy in→out, then EQ the out buffers in place. `AudioDeviceStart`.
5. On `kAudioHardwarePropertyDefaultOutputDevice` change → teardown + rebuild (works around the known
   "all-zeros after device/sample-rate/Bluetooth change" behavior).

## Gotchas / known constraints (verified — see docs/RESEARCH.md)
- "All audio" excludes **DRM/FairPlay** streams (some Apple Music/Netflix) — they pass through un-EQ'd. Set
  expectations in copy as "all unprotected audio".
- **No public API** to query/request the audio-capture permission → we use private TCC SPI for the direct
  build (`ENABLE_TCC_SPI`); a Mac App Store build must turn that flag OFF and use the public fallback
  (prompt on first capture). This is the #1 App Store rejection risk (Guideline 2.5.1). Lead with direct.
- **Driver-based** designs cannot ship self-contained on the Mac App Store (2.4.5/2.5.2) — that's why the
  virtual-driver fallback is a v2, off-store concern.
- Keep the aggregate **output-only** so it doesn't trip mic permission.
- Real-time discipline: no allocations/locks-of-unknown-duration on the IOProc thread. **M2 done:**
  `EQEngine` now runs `vDSP_biquadm` (32 sections/channel). The control→audio handoff is **wait-free**
  (`beginRender()` uses `withLockIfAvailable` — a try-lock — so the audio thread never blocks; it keeps
  ramping toward the last targets if the control thread is mid-write). Coefficient changes are applied
  via `vDSP_biquadm_SetTargetsDouble` (per-sample ramp ≈ a few ms), killing zipper noise on live edits,
  preset switches, and bypass (preamp + bypass fold into the ramped coefficient set).
- ⚠️ **`vDSP_biquadm_CreateSetup(coeffs, M, N)` gotcha:** despite the header param names, **M = number of
  sections, N = number of channels** (the opposite of how it reads). Getting it backwards makes the
  function read N channel pointers when you supply one → **segfault on the audio thread**. Verified
  empirically by `Tools/verify_biquad.swift` (offline frequency-response check — run it after any DSP
  change: `swiftc -O Tools/verify_biquad.swift -o /tmp/vb && /tmp/vb`).

## Roadmap (see docs/BUILD-PLAN.md)
- **M0 ✅** prove capture→DSP→replay loop
- **M1 ✅** working system-wide 10-band graphic EQ + UI + permission + device rebuild
- **M2 ✅** — AutoEq import (`Tools/build_autoeq_db.py` → bundled `Resources/autoeq.sqlite`, **8,850** headphones), searchable browser UI, JSON import/export. `vDSP_biquadm` engine (wait-free handoff + `SetTargets` ramping). Parametric editor (live response curve + draggable handles, up to 32 bands). **Linear-phase FIR mode** (`FIRDesigner` + `FIRProcessor`, toggle, ~21ms latency). **Mid-Side mode** (two chains; `processMidSide` encodes L/R→M/S, EQs each, decodes; Mid/Side curve selector in UI). User manual at `docs/MANUAL.md`. All DSP proven offline by `Tools/verify_{biquad,fir,midside}.swift` (compiled against shipping sources).
- **M3** RevenueCat one-time-paid gating, Developer-ID notarization, branding/icon, MAS submission of tap-only public-permission build, per-app EQ

## Reference
- Apple SDK headers (ground truth): `…/MacOSX26.0.sdk/.../CoreAudio.framework/Headers/{AudioHardwareTapping,CATapDescription,AudioHardware}.h`
- Study-only (do NOT copy code): `insidegui/AudioCap` (capture half), iQualize / Equaliser (full driverless loop, shipping proof)
