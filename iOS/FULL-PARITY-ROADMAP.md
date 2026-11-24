# Sonance EQ for iPhone — parity roadmap

See [EFFECTDECK-PARITY.md](EFFECTDECK-PARITY.md) for the expanded iOS host
scope: system routing, ordered effect chains, AUv3 hosting, analyzers, channel
routing, presets/import links, and host processing controls.

This roadmap tracks the goal of making the iPhone app the full Sonance EQ
experience where iOS allows it. The Mac app remains the reference for DSP,
presets and editing workflows. iPhone playback works through files opened in
Sonance EQ and compatible AUv3 hosts; the new Control Center route is still
awaiting entitlement and device validation.

## Current feature map

| Mac capability | iPhone status | Work remaining |
| --- | --- | --- |
| 32-band parametric EQ, eight filter shapes and cut slopes | Implemented in the file player and AUv3 effect | Run the installed AUv3 quality suite on the selected Xcode toolchain and designated iPhone |
| Bundled AutoEq and attributed headphone corrections | Implemented from the shared 8,862-row offline database; search, model/category filters, main-EQ loading and per-output assignment | Verify the database bundle and search on simulator/device; confirm database count after build |
| Saved presets and portable Sonance JSON | Implemented | Keep import/export compatibility under regression coverage |
| AutoEq ParametricEQ text import | Implemented | Add other useful EQ formats after compatibility fixtures are available |
| Live spectrum, waveform and level analysis | Implemented for Sonance playback and the AUv3 host signal | Compare readings to known fixtures on a device |
| A/B reference audition | Implemented for Sonance file playback | Add smooth level-matched switching if listening checks show a need |
| File playback, background audio, sleep timer and Picture in Picture | Implemented in the prototype; interruption handling preserves the paused playhead, and a Bluetooth route reconnect resumes only when the same output identity returns; iOS 27 lifecycle/resumption recommendations and the legacy path for older iOS are supported in source | Verify screen lock, same-device route recovery, interruptions and PiP on the designated phone |
| Hosted AUv3 effect | Implemented for compatible hosts, with persistent host parameters | Validate EffectDeck and another host with a physical Bluetooth route |
| Linear-phase FIR mode | Implemented in source for standalone and AUv3 paths, including the Mac FIR designer and 2,048-tap streaming convolution; latency is about 21.3 ms at 48 kHz | Verify delay and frequency response, then measure worst-case render deadline use across sample rates, buffer sizes, stereo and Mid-Side on the iPhone |
| Independent Mid and Side curves | Implemented in the AUv3 renderer, standalone player, editor and portable presets; mono streams keep the Mid curve | Run center/side isolation, state restore, mono and stereo tests on Apple runtimes; verify real-time cost in the host |
| Auto headroom and output limiter | Auto Headroom now estimates the peak response of active Mid/Side curves and lowers preamp with a 1 dB margin; no true-peak limiter | Validate estimates against rendered sine sweeps, clipping fixtures and FIR mode; decide separately whether iOS needs a true-peak limiter |
| Render timing diagnostics | Lock-free counters expose Sonance block count, effect deadline overruns, worst processing time and the latest buffer deadline in Live | Verify values on the phone under IIR/FIR and 44.1/48/96/192 kHz routes; collect separate host-level chain timing where the host exposes it |
| EffectDeck-style chain host | Integrated in the full Sonance EQ host: chain editor, effect/plugin/preset browser, import/share, built-in analyzers/effects, per-stage routing, audio settings, meters, remote panel and About/licensing; Sonance EQ AUv3 is embedded | Sign, install and exercise on the assigned phone; validate chain ordering, channel routing and state transfer |
| System Media Device route | Separate minimal Sonance EQ Route installer and Media Device extension; audio samples bridge to the full host over loopback TCP | Apple entitlement and provisioning profile are not yet available; build is unsigned and route remains unverified on device |
| System-wide capture and per-app routing/mixing/recording | Route follows the documented Control Center Media Device path; it has not run on hardware | Validate compatible playback sources; do not claim arbitrary app/game capture or mixing |
| Mac Store licensing and paid Pro access | Not implemented for iPhone | Define the iOS distribution and entitlement model before release work |

## Platform boundary

The iOS app can process its own file playback and expose the Sonance Audio Unit
to compatible hosts. The full EffectDeck-style host and the minimal Apple Media
Device route installer are separate apps. The host and its embedded extensions
compile for iPhone with signing disabled, but Xcode has no Apple Account
configured and the available wildcard profile lacks the host's App Groups,
Associated Domains, Inter-App Audio and iCloud capabilities. The route also
lacks its required Media Device entitlement/profile. Neither the new host nor
route installer is installed on the iPhone. Do not claim a working system route
or Bluetooth return path before signed device validation.

## Acceptance evidence

1. Build the app and Audio Unit for iPhone and Simulator from `iOS/project.yml`.
2. Run unit and UI suites, including all-sample audio continuity and injected
   dropout cases; preserve `.xcresult` output.
3. On the iPhone the owner assigned to this goal, verify Files playback, background and lock
   behavior, route recovery, output corrections and the exact AUv3 host path.
4. Through a connected Bluetooth endpoint, complete the separately documented
   steady-state and reconnect runs. Record unavailable host counters as unknown.
5. Verify update migration, saved presets, AutoEq catalog availability and
   accessibility labels before treating the iPhone build as release-ready.

Xcode 27.2 first-use setup and the full iPhone host's unsigned arm64 build now
succeed. Xcode's broken DerivedData symlink was repaired. The iOS 26 simulator
cannot compile the host because it uses an iOS 27 API; no iOS 27 simulator
runtime is installed. The signed install, Apple audio tests, Mid/Side and FIR
execution, processor-deadline measurements, and physical Bluetooth route stay
unverified until fresh evidence is retained.
