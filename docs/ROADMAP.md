# Sonance EQ — Roadmap beyond the EQ

The shipped app is a system-wide equalizer. The strategy (see the Windows→macOS utility analysis) is to
grow it into a full **audio control center** by reusing the Core Audio engine we already have
(`SystemAudioTap`, `AudioProcesses`, `AudioDevices`), then branch into adjacent macOS utilities.

> **Sequencing rule:** finish and fully test **Tier 1** before starting **Tier 2**.

---

## Tier 1 — audio control center (in progress)
Reuses the existing process-tap / aggregate / IOProc engine. Competes with SoundSource ($49),
Audio Hijack, Loopback ($99).

1. **Per-app volume mixer + output router** — *building now.*
   Independent volume / mute / output-device per app. Architecture: one tap per controlled app
   (`MixerChannel`), each scaled by `gain` and routed to its `outputDeviceUID` (or the default).
   - ✅ `AudioDevices` (output-device enumeration) + tests
   - ✅ `MixerChannel` / `MixerState` model + persistence + tests
   - ⏳ `PerAppMixer` engine (per-app tap → gain → routed output)
   - ⏳ Mixer UI (app list, volume sliders, mute, output picker)
   - ⏳ Live verification (can't be unit-tested — needs ears)

2. **System / per-app audio recorder** ("Audio Hijack"-lite) — *fast follow.*
   Write the already-captured tap buffers to a file (WAV → AAC/ALAC via AVAudioFile). Record system
   audio, a single app, or the EQ'd output. Mostly an encoder + file-writer on top of the IOProc;
   the buffer-to-file path is unit-testable offline.

3. **Virtual audio device / routing** ("Loopback"/BlackHole) — *largest, off-store.*
   Combine app + mic sources into a virtual output for OBS/streaming. Needs an `AudioServerPlugIn`
   driver (a HAL plug-in) — a separate installable component; cannot ship sandboxed on the Mac App
   Store, so it's a Developer-ID-only / v2 concern.

---

## Tier 2 — adjacent macOS power-user utilities (PARKED until Tier 1 ships + is fully tested)
Standalone Swift/AppKit apps; little/no reuse of the audio engine. Documented here so we don't lose the
analysis — **do not start until Tier 1 is complete and verified.**

| Idea | Replaces (Windows / Mac paid tool) | Notes / leverage |
|------|-----------------------------------|------------------|
| **Menu-bar system monitor** | Task Manager + Resource Monitor / Stats, iStat Menus ($) | CPU/GPU/RAM/net/disk/sensors/battery in the menu bar. Self-contained; `host_statistics`, IOKit, SMC. Clean standalone product. |
| **Window manager** | FancyZones / Rectangle, Moom ($) | Keyboard snapping + tiling + saved layouts via the Accessibility API. Crowded space but well-understood. |
| **Battery / diagnostics** | BatteryInfoView / coconutBattery | Battery health, cycles, S.M.A.R.T., a shareable support report. Small, easy niche. |
| **Clipboard history + launcher** | PowerToys Run / Raycast | High value but very crowded (Raycast is dominant + free). Lower priority. |
| **Key remapping** | PowerToys Keyboard Manager / Karabiner | Karabiner is free + entrenched; only worth it with a real differentiator. |
| **Archive tool** | 7-Zip/WinRAR / Keka | Keka already owns this; skip unless bundling. |

### Tier-2 selection criteria (decide when Tier 1 is done)
1. **Leverage** — does it reuse anything we built? (Audio ideas win; Tier 2 mostly doesn't.)
2. **Gap + willingness to pay** — is the incumbent paid and beatable on price/UX?
3. **Testability** — can the core be unit-tested without hardware/ears? (Monitor & battery score high; window manager & audio are harder.)
4. **Distribution fit** — does it need a driver/kernel/Accessibility grant that complicates Mac App Store?

**Tentative Tier-2 pick (revisit later):** the **menu-bar system monitor** — self-contained, highly
testable, clear paid incumbent (iStat Menus), and a natural companion to a pro audio app.
