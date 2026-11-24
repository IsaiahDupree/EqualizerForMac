# Sonance EQ for iPhone — parity roadmap

See [EFFECTDECK-PARITY.md](EFFECTDECK-PARITY.md) for the expanded iOS host
scope: system routing, ordered effect chains, AUv3 hosting, analyzers, channel
routing, presets/import links, and host processing controls.

This roadmap tracks the goal of making the iPhone app the full Sonance EQ
experience where iOS allows it. The Mac app remains the reference for DSP,
presets and editing workflows. iPhone playback is delivered through files the
person opens in Sonance EQ and through compatible AUv3 hosts.

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
| EffectDeck-style chain host | Integrated in the full-host target: chain editor, effect/plugin/preset browser, import/share, built-in analyzers/effects, routing editor, audio settings, meters, remote panel and About/licensing; Sonance EQ AUv3 is embedded | Code-sign, install and exercise with a route on the assigned phone; validate ordering, channel routing and chain state transfer |
| System Media Device route | Host extension and Sonance protocol are integrated and compile for the iOS 27 arm64 device SDK | Current local profiles lack Apple's Media Device entitlement and the app's App Group; register/provision those capabilities before device installation and route testing |
| System-wide capture and per-app routing/mixing/recording | The integrated route follows Apple's Media Device host path; the generated build has not yet been installed or exercised on hardware | Validate only the documented Control Center route and compatible playback sources; do not claim arbitrary app/game capture or mixing |
| Mac Store licensing and paid Pro access | Not implemented for iPhone | Define the iOS distribution and entitlement model before release work |

## Platform boundary

The iOS app can process its own file playback and expose the Sonance Audio Unit
to compatible hosts. The new full-host target also contains an Apple Media
Device extension, with a route UI and audio path, but source compilation does
not prove that Apple's entitlements permit this app's purpose or that the route
works on an iPhone. Available local development profiles lack the Media Device
and App Group capabilities, so signed device validation is blocked until
provisioning is updated. Do not claim arbitrary app/game capture or a working
Bluetooth return path before that validation.

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

Xcode 27.2 first-use setup and the iPhone app build/install now succeed. The
audio suite still needs a signed test-runner build; no Simulator runtime is
installed. Mid/Side and FIR implementation status remains source review until
Apple tests pass. Keep processor-deadline and physical Bluetooth playback
status explicitly unverified until fresh evidence is retained.
