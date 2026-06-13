# Sonance EQ — User Manual

Sonance EQ is a **system-wide equalizer for macOS**. It shapes the sound of *everything* your Mac
plays — Spotify, Apple Music, Safari/Chrome video, Zoom calls, games, system sounds — before it
reaches your speakers or headphones. It is **driverless**: no kernel extension, no installer, no
reboot. It uses Apple's Core Audio *process taps* (macOS 14.4+).

---

## 1. Requirements

- macOS **14.4 or later** (Apple Silicon or Intel).
- A few seconds, once, to grant the **Audio Capture** permission.

## 2. First run

1. Launch **Sonance EQ**.
2. Click **Start EQ** (top-right).
3. macOS asks for permission to capture system audio — click **Allow**. (Sonance EQ needs this to
   "see" the audio it equalizes. Audio is processed live on your Mac and is **never recorded, saved,
   or sent anywhere** — see §13.)
4. Play audio in any app. You should hear the EQ immediately. Toggle **Bypass** to compare against
   the untouched sound.

If you accidentally denied permission, see §11 (Troubleshooting).

---

## 3. The window at a glance

| Area | What it does |
|------|--------------|
| **Header** | App status (Active / Stopped + the output device or loaded preset), **Bypass** switch, **Start/Stop EQ** button. |
| **Preset row** | One-click built-in presets (Flat, Bass Boost, Treble, Vocal, Loudness) and the **Headphones** button (the AutoEq library). |
| **Response curve** | The live parametric editor — the blue curve is exactly what the EQ is doing to your sound. |
| **Preamp** | Master level trim (see §9). |
| **Linear Phase / Mid-Side** | Advanced filter & stereo modes (see §8). |
| **Footer** | Reset, Import…, Export… (see §9). |

---

## 4. Starting and stopping

- **Start EQ / Stop EQ** turns the whole engine on and off. When stopped, audio passes through your
  Mac normally (Sonance EQ is out of the path).
- **Bypass** (header switch) keeps the engine running but momentarily passes audio through
  *unprocessed* — the fastest way to A/B "EQ vs no EQ". The transition is click-free.

---

## 5. Built-in presets

Click any preset in the preset row to load it instantly: **Flat, Bass Boost, Treble, Vocal,
Loudness**. These are classic 10-band starting points — tweak them in the editor afterward.

---

## 6. Headphone library (AutoEq)

Click **Headphones** to open the library of **8,850 headphone & earbud corrections** from the
[AutoEq](https://github.com/jaakkopasanen/AutoEq) project. A correction flattens a specific
headphone's frequency response so it sounds neutral/accurate.

1. Type your model in the search box (e.g. `HD 600`, `AirPods Pro`, `Moondrop`).
2. Optionally filter by **in-ear / over-ear / earbud**.
3. Click a result to apply it. Its parametric bands and a safety **preamp** load automatically.

The loaded headphone's name shows in the header. You can keep editing the curve afterward.

> Multiple measurement sources (oratory1990, Rtings, etc.) may exist for the same model — they're
> listed separately so you can pick the one you trust.

---

## 7. The parametric editor (response curve)

The blue curve is the EQ's magnitude response (left = bass, right = treble; up = boost, down = cut).
Each **dot** is a band you can grab.

- **Move a band** — drag its dot. Left/right changes the **frequency**; up/down changes the **gain**.
- **Select a band** — click its dot. The inspector row below shows its controls:
  - **Type** — `PK` peaking (a bump/dip), `LSC` low-shelf, `HSC` high-shelf, `LP`/`HP` low/high-pass,
    `NO` notch. (Pass and notch filters have no gain, so they only move horizontally.)
  - **Q** — bandwidth. Higher Q = narrower, more surgical; lower Q = wider, gentler.
  - The frequency and gain readouts update as you drag.
  - **Trash** — delete the band.
- **Add a band** — click **+ Band** (top-right of the curve). A new peaking band appears at 1 kHz.
- **Deselect** — click an empty part of the curve.

Up to **32 bands** are supported. Edits are applied live and **ramped**, so dragging never produces
zipper noise or clicks.

---

## 8. Advanced modes

### Linear Phase

The **Linear Phase** switch (below the preamp) changes *how* the EQ filters, without changing the
shape of the curve:

- **Off (default) — Minimum Phase.** Classic, like analog EQ. Zero added latency. Best for everyday
  use, gaming, video calls.
- **On — Linear Phase.** Applies the exact same magnitude curve but with **no phase distortion** —
  all frequencies stay perfectly time-aligned, which some listeners prefer for critical listening and
  bass tightness. The trade-off is a small, fixed **latency** (shown next to the switch, ~21 ms at
  48 kHz). Because audio is delayed, you may notice slight lip-sync offset on video — so leave it
  **off** for video/calls and switch it **on** for focused music listening.

Both modes sound identical in *tonal balance*; the difference is phase/transient behavior.

### Mid-Side

The **Mid-Side** switch lets you EQ the **center** of the stereo image separately from the **width**:

- **Mid** = what's common to both channels — lead vocals, bass, kick drum (the mono content).
- **Side** = the *difference* between channels — ambience, reverb, hard-panned instruments (the width).

Turn it on and a **Mid | Side** selector appears above the curve. Choose which one you're shaping; the
curve you're editing is drawn solid, the other faintly for reference. For example: add a couple dB of
"air" to the **Side** highs to widen a mix, or trim boomy bass on the **Mid** without thinning the sides.
With the switch **off** (plain stereo), both channels get the same EQ — the normal case.

## 9. Preamp, Reset, Import / Export

- **Preamp** — a master gain trim. Boosting many bands can cause clipping (distortion); pull the
  preamp **down** a few dB to leave headroom. AutoEq presets set this for you.
- **Reset** — return to a flat 10-band EQ.
- **Export…** — save your current EQ (all bands + preamp) to a `.json` file.
- **Import…** — load a previously exported Sonance EQ preset. Great for backing up or sharing tunings.

---

## 10. Switching speakers / headphones

When you change your Mac's output device (plug in headphones, connect Bluetooth, switch in Control
Center), Sonance EQ automatically rebuilds itself to keep equalizing the new device. You may hear a
brief gap during the switch — this is expected.

---

## 11. Troubleshooting

**No sound after pressing Start, or audio is silent**
- Make sure the right output device is selected in macOS (Control Center → Sound).
- Press **Stop EQ**, then **Start EQ** again to rebuild the audio path.
- After switching Bluetooth headphones, a Stop/Start cycle clears any stale state.

**It says permission was denied**
- Open **System Settings → Privacy & Security → Audio Capture** (or use the **Open Settings** button
  in the app's permission banner) and enable **Sonance EQ**, then press Start again.

**Some audio isn't being equalized** — see §12.

**Distortion / crackling when boosting a lot** — lower the **Preamp** a few dB for headroom.

---

## 12. What Sonance EQ can and can't EQ

- It equalizes **all unprotected audio** on your Mac.
- It **cannot** equalize **DRM/FairPlay-protected** streams (some Apple Music tracks, some Netflix
  audio). macOS deliberately keeps protected audio out of capture taps for every app in this class —
  those streams pass through untouched. This is an Apple platform limitation, not a bug.

---

## 13. Privacy

Audio is processed **live, on your Mac, in memory only**. Sonance EQ does **not** record, store, or
transmit your audio anywhere. The Audio Capture permission exists solely so the equalizer can shape
the sound on its way to your speakers.

---

## 14. Sonance EQ Pro

Sonance EQ is **free to use** for everyday equalizing — built-in presets and basic editing. **Pro** is a
one-time purchase that unlocks:

- the **8,850-headphone** AutoEq library,
- the full **parametric** editor with **Linear Phase** and **Mid-Side** modes,
- **Import / Export** of presets.

Tap **Unlock Pro** (top of the window) or any 🔒 control to open the store. A single purchase unlocks
everything, forever, on your Mac.

> **Development builds** show a *mock* store (no real charge) so the purchase flow can be exercised before
> the App Store listing is live. Your unlock persists between launches; "Relock (mock)" resets it.

Headphone corrections are © the [AutoEq](https://github.com/jaakkopasanen/AutoEq) project (MIT) and are
bundled with attribution.

---

*For the technical design, see [`BUILD-PLAN.md`](BUILD-PLAN.md) and [`RESEARCH.md`](RESEARCH.md).*
