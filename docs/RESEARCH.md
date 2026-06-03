# Sonance EQ — Research & Verified Findings

Three load-bearing claims were adversarially fact-checked (agents tried to *refute* each) against
Apple docs, SDK headers, and shipping apps. Summary of verdicts + citations.

## Claim 1 — Driverless system-audio EQ loop ✅ CONFIRMED (high confidence)
*A new macOS app (mid-2026) can capture ALL system audio, EQ it, and replay it to the speakers using
Core Audio process taps + an aggregate device, with NO kernel extension or virtual driver, on macOS 14.4+.*

- API exists & is driver-free: process taps introduced macOS 14.2; Apple sample `insidegui/AudioCap`
  targets 14.4+. `AudioHardwareCreateProcessTap` + `CATapDescription` + `AudioHardwareCreateAggregateDevice`
  (with `kAudioAggregateDeviceTapListKey`) — only TCC permission via `NSAudioCaptureUsageDescription`.
- System-wide capture: empty process list + global-exclude init = capture everything.
- Replace (not duplicate) the sound: `CATapMutedWhenTapped` mutes the original while we read the tap.
- Full re-inject loop is a **shipping** capability: **iQualize** (macOS 14.2+, "zero drivers", pre-EQ
  gain → parametric EQ → output gain → peak limiter → written back to output device) and **Equaliser**
  (64-band parametric, driverless, macOS 15+) prove it.
- **Caveats:** "ALL" excludes DRM/FairPlay; practical floor 14.4+ (Equaliser 15+); public samples show
  only the capture half (we built the re-injection); **no public API** to request/query the permission
  (private TCC SPI → App-Store-blocking); all-zeros after sample-rate/Bluetooth change (rebuild required);
  keep aggregate output-only to avoid mic permission; added round-trip latency vs an inline driver;
  Electron/Teams tapping quirks.

Sources: Apple Core Audio taps doc; `AudioHardwareCreateProcessTap` / `CATapDescription` refs;
`insidegui/AudioCap`; `makeusabrew/audiotee`; maven.de "CoreAudio taps for dummies"; iQualize; Equaliser.

## Claim 2 — Mac App Store eligibility ⚠️ PARTLY TRUE (high confidence)
*A system-wide EQ can ship on the MAS under the sandbox.*

- **Driver-based** EQs can NOT ship self-contained on the MAS (Guideline 2.4.5(iv) "may not download/
  install kexts/additional code", 2.5.2 "self-contained"). Boom 3D & SpeakerAmp ARE on the MAS but their
  system-wide mode requires the user to side-load a separate driver + reboot — the sandboxed binary alone
  doesn't capture all apps.
- The **driverless tap** path is the only architecture that could ship self-contained to the MAS — but
  **no tap-only EQ has confirmed shipped there yet**. iQualize & Equaliser are direct-download only.
- The concrete blocker is the **permission API**: the clean request/preflight uses **private TCC API**
  (`AudioCap` README states this explicitly), which violates Guideline 2.5.1. Public fallback exists
  (prompt on first capture) but is undocumented and worse UX.
- **Conclusion:** lead with **direct** (Developer ID + notarization); treat MAS as upside via a tap-only
  public-permission build. Don't block direct distribution on MAS review.

Sources: App Store Review Guidelines 2.4.5/2.5.1/2.5.2; `AudioCap` README; Boom 3D MAS FAQ; SpeakerAmp +
nimblesnail audio-driver page; Apple taps doc; `com.apple.security.device.audio-input` entitlement; eqMac.

## Claim 3 — AutoEq presets + vDSP performance ✅ CONFIRMED (high confidence)
*AutoEq parametric profiles can be legally parsed/bundled, and vDSP biquads run a 10–31 band stereo
parametric EQ at negligible CPU in a real-time callback on Apple Silicon.*

- AutoEq `LICENSE` is verbatim **MIT** ("Copyright 2018-2022 Jaakko Pasanen"). MIT permits use/copy/
  modify/distribute/sell with notice preserved → parsing + bundling the **computed corrections**
  (`ParametricEQ.txt` / `GraphicEQ.txt`) into a commercial app is allowed. Repo covers **6,033+** headphones.
- **Caveat (the real one):** MIT covers AutoEq's code + *derived* corrections, NOT the upstream **raw
  measurements** (oratory1990/Crinacle/Rtings — separate, often non-commercial terms). Bundle the computed
  result files + MIT notice + source attribution; do **not** redistribute raw `.csv`; imply no endorsement.
- `vDSP_biquadm` is a multichannel cascaded-biquad designed for real-time use. Rule: `…CreateSetup` once at
  init (never in the callback); `vDSP_biquadm_SetTargetsSingle` ramps coeffs for click-free live edits;
  `vDSP_biquadm_SetActiveFilters` zero-costs disabled bands. 31 bands × 2 ch × 48 kHz ≈ 9–15M MAC/s — a
  tiny fraction of one NEON core. Existence proof: `jeremicna/AudioFlow` (CoreAudio + Accelerate, 10-band
  parametric, auto-preamp) — validates the DSP engine (note: it's BlackHole-driver-based + archived, so it
  does NOT validate the tap path).

Sources: AutoEq `LICENSE` + `results/README`; Apple vDSP Programming Guide "Using Biquadratic Filter
Functions"; `vDSP_biquadm` / `…SetTargetsSingle` / `…SetActiveFilters` refs; `jeremicna/AudioFlow`;
Ross Bencina "Real-time audio programming 101".
