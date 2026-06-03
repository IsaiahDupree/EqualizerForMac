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
  DSP/Biquad.swift              FilterType + BiquadCoeffs + RBJ cookbook coefficients
  DSP/EQEngine.swift            real-time cascade; control plane (update) vs audio plane (beginRender/process)
  Models/EQBand.swift           band model (freq/gain/Q/type/enabled)
  Models/Presets.swift          starter presets (10-band graphic)
  UI/ContentView.swift          faders, presets, preamp, bypass, permission banner
  Resources/                    Info.plist + entitlements (generated/maintained via project.yml)
```

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
- Real-time discipline: no allocations/locks-of-unknown-duration on the IOProc thread. M0 uses a brief
  `OSAllocatedUnfairLock` snapshot in `EQEngine.beginRender()`; **M2 must make this lock-free** (double-buffer
  swap) and add `vDSP_biquadm_SetTargets` ramping to remove zipper noise on live slider edits.

## Roadmap (see docs/BUILD-PLAN.md)
- **M0 ✅** prove capture→DSP→replay loop
- **M1 ✅** working system-wide 10-band graphic EQ + UI + permission + device rebuild
- **M2** vDSP_biquadm 32-band parametric, AutoEq import (SQLite, 6,000+ headphones), import/export, FIR linear-phase, per-channel/Mid-Side
- **M3** RevenueCat one-time-paid gating, Developer-ID notarization, branding/icon, MAS submission of tap-only public-permission build, per-app EQ

## Reference
- Apple SDK headers (ground truth): `…/MacOSX26.0.sdk/.../CoreAudio.framework/Headers/{AudioHardwareTapping,CATapDescription,AudioHardware}.h`
- Study-only (do NOT copy code): `insidegui/AudioCap` (capture half), iQualize / Equaliser (full driverless loop, shipping proof)
