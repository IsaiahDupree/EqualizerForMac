# Sonance EQ

A **system-wide equalizer for macOS** — high-precision, driverless, with a huge preset library. Every app's audio (Spotify, Safari, Zoom, games, system sounds) flows through a real-time parametric EQ before it reaches your speakers.

> Not a browser extension. Unlike Safari-only equalizers, Sonance EQ sits between the macOS audio mixer and your output device, so it shapes **everything you hear**.

## Status

**M0 + M1 complete · M2 well underway — a system-wide parametric EQ with an 8,850-headphone library.**

- ✅ Driverless system-audio capture via Core Audio **process taps** (macOS 14.4+) — no kernel extension, no installer, no reboot.
- ✅ Capture → DSP → re-inject loop (private aggregate device, real output as clock master, self-excluded to prevent feedback).
- ✅ Real-time **`vDSP_biquadm`** EQ engine (up to 32 sections/channel) with a **wait-free** control→audio handoff and **ramped** coefficient updates — no zipper noise on live edits.
- ✅ **Parametric editor** with a live response curve (drag bands for freq/gain, edit Q & type, add/remove up to 32 bands), preamp, bypass A/B, starter presets, live output-device rebuild.
- ✅ **8,850 AutoEq headphone corrections** bundled (searchable browser) + JSON **import/export**.
- ⏭️ Remaining (M2): FIR linear-phase mode, per-channel / Mid-Side. **M3:** RevenueCat paid unlock, Developer-ID notarization, per-app EQ, Mac App Store build.

**📖 Using the app:** see the [**User Manual**](docs/MANUAL.md).
For the roadmap see [`docs/BUILD-PLAN.md`](docs/BUILD-PLAN.md); for the fact-checked technical findings see [`docs/RESEARCH.md`](docs/RESEARCH.md).

## Build & run

Requires **macOS 14.4+** and **Xcode 16+** (developed on macOS 26 / Xcode 26). The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonki/XcodeGen).

```bash
brew install xcodegen          # one-time
xcodegen generate              # regenerate SonanceEQ.xcodeproj from project.yml
open SonanceEQ.xcodeproj        # then press ⌘R in Xcode
```

First run:
1. Press **Start EQ**.
2. macOS will ask for permission to capture audio — **Allow** it.
3. Play audio in any app. Drag bands on the response curve, click **Headphones** to load a correction for your gear, or pick a preset. Toggle **Bypass** to A/B against the unprocessed sound.

See the [User Manual](docs/MANUAL.md) for a full walkthrough.

> The project file (`SonanceEQ.xcodeproj`) is git-ignored — always regenerate it with `xcodegen generate`. Edit `project.yml`, never the `.xcodeproj` directly.

## Architecture (one-liner)

```
all apps → [global process tap, muted-when-tapped] → private aggregate device
         → IOProc (copy → EQ biquad cascade → out) → real output device → speakers
```

## License / IP

Original work. Inspired by the *category* of system equalizers; no code, assets, or branding copied from any other app. Headphone correction presets (M2) come from the MIT-licensed [AutoEq](https://github.com/jaakkopasanen/AutoEq) project with attribution. See `docs/RESEARCH.md` §IP.
