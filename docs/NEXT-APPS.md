# Next Apps — Reusing the Sonance Moat

Sonance EQ proved two reusable assets:

1. **The audio moat** — driverless system-wide + per-app capture/processing via Core Audio process taps, a
   private aggregate device, and a wait-free real-time DSP engine. Almost nobody else builds this.
2. **The ship-spine** — `xcodegen` → notarize/DMG → App Store Connect automation (`Tools/asc/`) →
   RevenueCat freemium → verified revenue. A repeatable path from code to a paid, notarized app.

The highest-leverage next apps **reuse both**. Every idea below is scored on Effort (dev time from where we
are), Moat (how hard for a competitor to copy), and Market (is anyone already paying for this?).

---

## Tier A — reuse the audio engine directly (the moat compounds)

### A1. Per-App Volume Mixer  ⭐ recommended
macOS has **no per-app volume control** — Windows has had one for a decade. A menu-bar mixer that sets each
running app's level independently (mute Chrome, boost Spotify) is an obvious, universally-wanted gap.
- **Reuses:** the per-app mixdown tap we *already built* for per-app EQ (`AudioProcesses` + `SystemAudioTap`).
- **Effort:** Low–Med · **Moat:** High (same tap engine) · **Market:** Proven (people beg for this in forums)
- Pairs beautifully with EQ; could even ship as a Sonance companion.

### A2. System / Per-App Audio Recorder
Record any app's audio — or the whole system — to a file. Podcasters, transcription, "capture that stream/
meeting/song." Already stubbed as `ProFeature.audioRecorder`.
- **Reuses:** the exact tap → we just write buffers to disk instead of re-injecting.
- **Effort:** Low · **Moat:** High · **Market:** Proven (Audio Hijack $59, Piezo $19 — we undercut / one-time)
- Lowest-effort of all: the capture half exists; add an encoder + UI.

### A3. Loudness Normalizer / Auto-Leveler
Real-time AGC so ads, YouTube, and Zoom stop blasting you. "Set it once, never touch the volume knob again."
- **Reuses:** the real-time chain; swap EQ coefficients for a gain-riding compressor/limiter.
- **Effort:** Med · **Moat:** High · **Market:** Real (Sound Control did this, now defunct — gap open)

### A4. Mic / Voice Enhancer for calls
System-wide microphone EQ + noise suppression + de-esser for Zoom/Meet/Discord.
- **Reuses:** the DSP engine; different capture path (input side) + a denoise stage is new work.
- **Effort:** Med–High · **Moat:** Med–High · **Market:** Proven (Krisp — but subscription; we go one-time)

---

## Tier B — reuse the ship-spine, add a new capability

### B1. Menu-bar Spectrum Analyzer / Visualizer  (funnel play)
A gorgeous live spectrum/loudness meter of system audio in the menu bar. Cheap or free — a **top-of-funnel
magnet** that screenshots well and cross-sells the paid apps.
- **Effort:** Low · **Moat:** Low–Med · **Market:** Viral/free-tier, not a big earner alone.

### B2. Non-audio utilities (clipboard / window / screenshot-OCR)
Proven markets, but they **don't reuse the audio moat**, so we compete on execution alone. Lower priority
unless we want category diversification.

---

## The strategic frame: a Suite, not scattered apps

The tap engine is a **platform**. EQ is facet #1. Recorder, Mixer, Normalizer are facets #2–4 sharing one
codebase, one RevenueCat account, one notarization pipeline — and cross-selling each other.

> **"Sonance Audio Tools"** — one moat, four products, one buyer who already trusts you.

Recommended order (effort-adjusted): **A2 Recorder** (fastest to revenue) → **A1 Mixer** (biggest obvious
gap) → **A3 Normalizer** → **A4 Voice Enhancer**.

Each ships on the exact spine that just produced our first $7.00 — and each reuses `docs/APP-STORE-RUNBOOK.md`
and `docs/REVENUE-VERIFICATION-RUNBOOK.md` unchanged.
