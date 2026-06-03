# Sonance EQ — Build Plan

*Original system-wide macOS equalizer. Reference category to beat: Safari-only Web Audio EQs
(e.g. "EQA – Equalizer for Safari", App Store id 6760381100), which are structurally limited to
one browser tab. Synthesized from a 9-agent research + adversarial-verification pass (2026-06-03).*

## 1. Verdict
**Feasible and proven.** Build on the **Core Audio Process Tap API** (`CATapDescription` +
`AudioHardwareCreateProcessTap` + private aggregate device, macOS 14.4+) as the **primary
architecture**. A global, exclusive, `.mutedWhenTapped` tap reads the post-mix system bus into a
single private aggregate that also contains the real output device as the clock-master sub-device;
the IOProc runs the EQ in-process and writes back to that real output. Chosen over a virtual driver
because it needs **zero kernel/system extensions, no installer, no reboot, lowest latency**, and is
crash-safe (auto-unmute). Existence proof: **iQualize** (macOS 14.2+, "zero drivers") and
**Equaliser** (64-band parametric, driverless, macOS 15+) ship this exact loop today. **Fallback:**
an `AudioServerPlugIn` virtual loopback driver (built from Apple's *NullAudio* sample — NOT a GPL
BlackHole/eqMac fork) for macOS ≤13 or a "set-as-default-device" workflow → **v2, off-store**.

## 2. How it beats a Safari-only EQ
| Goal | Safari EQ | Sonance EQ |
|---|---|---|
| System-wide | one Safari tab (Web Audio sandbox) | every unprotected app via global process tap |
| Precision | fixed gain-only browser biquads | up to 32-band parametric, 0.1 dB, per-channel L/R + Mid-Side, optional linear-phase |
| Presets | a handful | 6,000+ AutoEq headphone corrections + ~40 curated, stackable + import/export |

## 3. Architecture
- **Capture layer** (`SystemAudioTap`): owns the tap, builds the private aggregate, installs the
  IOProc, rebuilds on device/format/Bluetooth change. Output-only aggregate (no mic permission).
- **DSP engine** (`EQEngine`): M0/M1 Swift biquad cascade; **M2 → C++/`vDSP_biquadm`** multichannel,
  double-precision RBJ coeffs, `SetTargets` click-free updates, `SetActiveFilters` so disabled bands
  cost nothing, preamp + auto-preamp + brickwall limiter, optional FIR linear-phase (FFT overlap-add).
- **UI** (SwiftUI): menu-bar + window; graphic/parametric skins, preset browser, device picker,
  permission onboarding.
- **Preset store**: bundled SQLite index of AutoEq corrections (built at compile time), curated JSON
  presets, user presets in Application Support; one tokenizing parser + multi-format exporter.

```
apps → [global tap · mutedWhenTapped] → private aggregate (real output = clock master + tap)
     → IOProc: in → preamp → biquad cascade → auto-preamp → limiter → out → real output → speakers
```

## 4. DSP / precision spec
- Engine: custom `vDSP_biquadm` cascade (NOT the black-box `AVAudioUnitEQ`; keep the latter only as an
  MVP throwaway). One engine, three skins:
  - **Parametric** (core): up to 32 bands (headroom 64); types PK / LSC / HSC / LP / HP / notch / band-pass; per-band f/gain/Q.
  - **Graphic**: lock f to ISO ⅓-octave centers (10/15/31-band), Q≈4.3, same peaking biquads.
  - **FIR linear-phase** (optional): symmetric FIR via FFT overlap-add; ~2048-tap (~43 ms) latency, opt-in.
- Resolution: f 20 Hz–20 kHz; gain −30…+30 dB at 0.1 dB; Q 0.1–40. Coeffs in double precision, stored float.
- Per-channel: stereo-linked default; Unlinked L/R + Mid-Side modes.
- Preamp/auto-gain: master preamp; auto-preamp = −max(0, composite peak dB) (honor AutoEq `Preamp:`); output limiter safety net.
- RT discipline: create setup once at init, never in callback; `SetTargets` ramps for live edits; rebuild on sample-rate/Bluetooth change. CPU: 31 bands stereo @48 kHz ≈ 9–15M MAC/s, <1% of one Apple-Silicon core.

## 5. Preset system ("many many presets")
1. **AutoEq headphone corrections (headline):** bundle the MIT-licensed *computed* corrections for
   6,000+ headphones (8,850 `ParametricEQ.txt` variants) into a build-time SQLite DB; fuzzy search by
   model. **Legal:** MIT covers code + computed corrections; do NOT redistribute raw measurement `.csv`;
   ship MIT notice + attribute measurement sources (oratory1990, Crinacle, Rtings, …); no endorsement claims.
2. **~40 curated original presets:** Tonal (Flat, Bass ×3, Sub, Treble, Warm, Bright, V-Shape, …),
   Content (Vocal, Podcast, Classical, Rock, EDM, Hip-Hop, Cinema, Gaming, …), Perceptual (Equal-Loudness/
   Fletcher-Munson, Night, Laptop/Small-Speaker). All editable, stored as the same band model.
3. **User presets:** save/duplicate/rename; **stackable** (headphone correction × genre).

Import/export: Equalizer-APO/AutoEq `ParametricEQ.txt`, AutoEq `GraphicEQ.txt` (Wavelet), REW/FBQ2496,
`AUNBandEQ` `.aupreset`. Round-trip = retention + lets users carry tunings across tools.

## 6. Distribution
- **Primary — Direct** (Developer ID + hardened runtime + `notarytool` + staple). No review gatekeeping
  on the capture permission; how eqMac/iQualize/Equaliser ship.
- **Secondary — Mac App Store** (tap-only build): possible but the clean permission flow uses **private
  TCC API** (2.5.1 risk). For MAS use **only the public fallback** (trigger capture, handle failure) and
  test on the target OS. **No driver in v1** keeps the submission clean (driver designs are barred by
  2.4.5(iv)/2.5.2 — every driver-based MAS EQ side-loads its driver separately).
- Entitlements: Info.plist `NSAudioCaptureUsageDescription` (add raw key manually); sandbox
  `com.apple.security.device.audio-input`. No DriverKit entitlements for v1.
- Monetization: **one-time paid** under a single RevenueCat "pro" entitlement (unifies MAS IAP + direct license).

## 7. IP do / don't
**DO:** 100% original code; learn from Apple public samples + public-domain RBJ math (EQ patents long
expired); original name/icon/UI; credit AutoEq (MIT) + measurement sources.
**DON'T:** reuse any competitor's name/icon/screenshots/copy/trade-dress; decompile/copy any competitor
binary, preset file, or asset; bundle/link **GPL** source (BlackHole GPL-3, Background Music GPL-2,
Equaliser GPL-3 — study only); redistribute AutoEq raw `.csv`; imply endorsement/compatibility.

## 8. Milestones
- **M0 ✅ Spike** — prove tap → IOProc → write-back to real output (unity/one biquad), no echo, low latency.
  Riskiest unknown de-risked: the re-injection aggregate config (public samples only show capture).
- **M1 ✅ MVP** — menu-bar/window app, 10-band graphic EQ, output device, permission onboarding, preamp,
  presets, save/load. *(M0+M1 shipped together in the initial build.)*
- **M2 Precision + presets** — `vDSP_biquadm` 32-band parametric, AutoEq SQLite import (fuzzy + stacking),
  multi-format import/export, auto-preamp + limiter, FIR linear-phase, per-channel/Mid-Side.
  Riskiest unknown: RT stability under load (lock-free param swap, zipper-free edits) + parser robustness
  vs the full 8,850-file corpus.
- **M3 Polish / ship** — RevenueCat one-time gating, Developer-ID notarization + staple, branding/icon/
  screenshots, per-app EQ (macOS 26 `bundleIDs`/`processRestoreEnabled`), edge handling (DRM passthrough,
  device hot-swap, Electron/Teams quirks), MAS submission of the tap-only public-permission build.

## 9. Top risks
1. **App Store rejection** (2.5.1 private permission API; no tap-only EQ confirmed on MAS) → lead direct, MAS public-path only.
2. **DRM/FairPlay audio** not tappable → copy says "all unprotected audio"; ensure clean passthrough.
3. **RT reliability** (all-zeros after device/SR/BT change → rebuild; added round-trip latency; Electron/Teams quirks) → listeners + smallest glitch-free buffer + QA matrix.
4. **OS floor** cuts off macOS ≤13 → accept for v1; virtual-driver fallback (v2) is the only path below 14.4.
5. **AutoEq data-license boundary** → bundle only computed corrections + attribution; never raw `.csv`.

**Study-first reference:** `insidegui/AudioCap` `ProcessTap.swift` (the capture half) — we supply the
missing re-injection half (aggregate with real-output sub-device + write-back IOProc) per the
iQualize/Equaliser pattern. Already implemented in `Sources/SonanceEQ/AudioEngine/SystemAudioTap.swift`.
