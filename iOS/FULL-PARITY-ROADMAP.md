# Sonance EQ for iPhone — parity roadmap

See [EFFECTDECK-PARITY.md](EFFECTDECK-PARITY.md) for the current feature map,
implementation evidence and Apple signing blockers. The EffectDeck-derived
host UI and workflows are in the iOS source, including system routing, ordered
chains, AUv3 hosting, analyzers, per-stage channel routing, presets/import
links and processing controls.

This roadmap tracks the goal of making the iPhone app the full Sonance EQ
experience where iOS allows it. The Mac app remains the reference for DSP,
presets and editing workflows. The iPhone app now exposes the standalone player
and EffectDeck host together. System playback through the new Control Center
route is still awaiting entitlement and device validation.

## Current feature map

| Mac capability | iPhone status | Work remaining |
| --- | --- | --- |
| 32-band parametric EQ, eight filter shapes and cut slopes | Implemented in the file player and AUv3 effect | Run the installed AUv3 quality suite on the selected Xcode toolchain and designated iPhone |
| Bundled AutoEq and attributed headphone corrections | Available in the standalone player and hosted AU editor; both app and Audio Unit bundles include the offline database | iOS 26 simulator coverage passes 3/3 catalog search/conversion/persistence tests plus 1/1 AU parameter/render integration test; confirm hosted-picker interaction and listening on iPhone |
| Saved presets and portable Sonance JSON | Implemented | Keep import/export compatibility under regression coverage |
| EQ editing history | Implemented in the standalone player: undo/redo restores complete EQ snapshots, groups slider/curve drags, persists restored state and caps history at 50 steps | Session and UI simulator regression checks pass; verify touch behavior on iPhone |
| AutoEq text import | ParametricEQ files preserve filter shape and values. GraphicEQ files are fitted into up to 32 peaking bands, with estimated headroom and an explicit approximation notice | Six preset-library simulator tests pass, including an AutoEq GraphicEQ fixture and malformed/unordered rejection. Add other useful formats after compatibility fixtures are available |
| Live spectrum, waveform and level analysis | Implemented for Sonance playback and the AUv3 host signal | Compare readings to known fixtures on a device |
| A/B reference audition | Implemented for Sonance file playback | Add smooth level-matched switching if listening checks show a need |
| File playback, background audio, sleep timer and Picture in Picture | Implemented in the prototype; interruption handling preserves the paused playhead, and Bluetooth or CarPlay reconnect resumes only when the same output identity returns; iOS 27 lifecycle/resumption recommendations and the legacy path for older iOS are supported in source | Verify screen lock, same-device route recovery, interruptions and PiP on the designated phone |
| Hosted AUv3 effect | Implemented for compatible hosts, with persistent host parameters | Validate EffectDeck and another host with a physical Bluetooth route |
| Linear-phase FIR mode | Implemented in source for standalone and AUv3 paths, including the Mac FIR designer and 2,048-tap streaming convolution; latency is about 21.3 ms at 48 kHz | Verify delay and frequency response, then measure worst-case render deadline use across sample rates, buffer sizes, stereo and Mid-Side on the iPhone |
| Independent Mid and Side curves | Implemented in the AUv3 renderer, standalone player, editor and portable presets; mono streams keep the Mid curve | Run center/side isolation, state restore, mono and stereo tests on Apple runtimes; verify real-time cost in the host |
| Auto headroom and output limiter | Auto Headroom now estimates the peak response of active Mid/Side curves and lowers preamp with a 1 dB margin; no true-peak limiter | Validate estimates against rendered sine sweeps, clipping fixtures and FIR mode; decide separately whether iOS needs a true-peak limiter |

| Render timing diagnostics | Lock-free counters expose Sonance block count, effect deadline overruns, worst processing time and the latest buffer deadline in Live; AUv3 publishes the counters off the render callback at 10 Hz so out-of-process hosts see live values | The new live full-load simulator case passed with 32 Mid bands, 32 Side bands, Mid/Side and FIR enabled, and zero measured AU deadline misses. Verify on iPhone across IIR/FIR and 44.1/48/96/192 kHz routes; collect separate host-level chain timing where the host exposes it |
| EffectDeck-style chain host | Integrated in the full Sonance EQ host: chain editor, Effects/Plugins/Presets browser, import/share, built-in analyzers/effects, per-stage routing, audio settings, meters, remote panel and About/licensing; Sonance EQ standalone player is in a sibling tab and AUv3 is embedded | Combined host 0.2.0 (build 28) was installed and launched on iPhone 15. Build 35 adds user-controlled route-report sharing and is signed for iPhoneOS. The phone later became unavailable to Xcode; stage routing, import/share and real-route audio behavior still need device validation |
| System Media Device route | Separate minimal Sonance EQ Route installer and Media Device extension; audio samples bridge to the full host over loopback TCP | Still blocked: profiles have empty entitlement arrays, and the 2026-11-25 recheck of the route-installer App ID's Capability Requests tab found no Media Device request entry. Build 16 compiles unsigned; no hardware route validation is possible until Apple grants the managed entitlement and matching profiles |
| System-wide capture and per-app routing/mixing/recording | Route follows the documented Control Center Media Device path; it has not run on hardware | Validate compatible playback sources; do not claim arbitrary app/game capture or mixing |
| Mac Store licensing and paid Pro access | Not implemented for iPhone | Define the iOS distribution and entitlement model before release work |

## Latest route regression work — 2026-11-25

The host detects repeated CarPlay ↔ Sonance EQ handoffs distinctly from
CarPlay ↔ iPhone speaker changes and keeps bounded route evidence through a
quick relaunch. The detector recognizes connected three-change paths that pass
through the iPhone speaker and rejects disconnected route records. Its
focused host XCTest suite passes 15/15 on the iOS 26 iPad Pro simulator,
including old-format history restore and the single-return rejection guidance.
Route warnings now include an Open Player action to take the user to the local
file player when a source rejects the EQ route. The no-audio banner also offers
that action before a route burst is classified, unless a required-restart gate
is active. Focused route and presentation tests pass 17/17 on the iOS 26
simulator; a user-triggered route-report share action now exports app/iOS
versions, current output, route flags and recent transitions without track
metadata or automatic transmission. The expanded focused route suite passes
19/19 on iOS 26. Signed iPhoneOS build 35 includes the UI, playback reconnect changes
and route-rejection guidance. Signed build 34 carries the updated detailed
bounce copy and passes strict deep signature verification; its focused route
suite passes 17/17. The build is not installed because Xcode reports the iPhone
unavailable (CoreDevice -27, no USB entry).
The generated host project completes and the EffectDeck-integrated app compiled
for arm64 iPhoneOS at build 28, which was installed and launched on the iPhone
15. The standalone Audio Unit continuity suite passes 12/12 on the iOS 26 iPad
simulator. A later attempt to run that suite on the phone could not find an
Xcode destination: `xcdevice` reports CoreDevice error -27, `devicectl` reports
the phone unavailable, and USB inventory has no iPhone entry. The production
Media Device route extension cannot run in the simulator because `MediaDevice`
is unavailable to the simulator target. The designated iPhone 11 is absent
from USB inventory. The
supplied SoundCloud message explicitly
rejects the EffectDeck Audio route, which Sonance EQ cannot override; use
CarPlay directly for that source, or a compatible source/local file for EQ.

## Platform boundary

The iOS app contains the EffectDeck-style host and exposes the Sonance Audio
Unit to compatible hosts. The host and the minimal Apple Media Device route
installer are separate apps because Apple's extension rules require a dedicated
installer container. Combined host build 14 was installed and launched on
iPhone 15; build 21 includes route-event snapshot capture while the exact phone remains unavailable to Xcode.
The host and Share extension have matching App Group profiles. Route detection
shows the last four transitions in a route-change burst with iOS's reason,
distinguishes an EQ route
handoff from an EQ processing fault, and advises against repeated switching
after a source rejects the route. Combined host build 25 also classifies three
or more recent CarPlay/iPhone-speaker handoffs by AVAudioSession port type and
shows specific recovery guidance. This diagnoses the route pattern; it cannot
make an unsupported streaming player send audio through the EQ. The route installer still lacks Apple's
Media Device capability and matching profile, so that system route and
Bluetooth return path remain unavailable/unverified. Do not treat the working
host UI or in-app stage-routing editor as proof of system audio routing.
The route history and banner presentation rules are extracted into a
Foundation-only model. Its expanded focused XCTest suite passes 15/15 on the
iOS 26 iPad Pro simulator, including CarPlay/speaker bounce classification,
false-positive rejection, banner visibility while the host peer remains
connected but output bypasses EQ, burst-warning priority, persistence across a
quick app relaunch, single route return and direct CarPlay bypass. The latest handler snapshots the route at notification
delivery to retain rapid transitions; its production host build compiles for
iOS 27. The simulator cannot load the production `MediaDevice` extension. The complete
embedded-host Logic suite passes 1,436/1,436 tests with parallelization
disabled on the iOS 26 simulator. On 2026-11-27, the current standalone
`SonanceEQiOS` scheme passed **59/59** unit and UI tests with no skips on the
iPad Pro 13-inch (M5) simulator, including all-sample audio continuity,
playback, presets, AutoEq, correction and AU lifecycle coverage. Summary and
test tree: `iOS/AudioValidation/Results/2026-11-27/`; complete local result:
`build/audio-quality/2026-11-27-full/SonanceEQiOS-FullSuite.xcresult`. Xcode
reported three thread-QoS inversion warnings and two `_UIReparentingView`
hierarchy warnings despite all tests passing. These simulator results do not
replace physical listening validation. The production host UI suite still
needs an iOS 27 simulator or the iPhone; physical route behavior needs the
phone.

## Acceptance evidence

1. Build the app and Audio Unit for iPhone and Simulator from `iOS/project.yml`.
2. Run unit and UI suites, including all-sample audio continuity and injected
   dropout cases; preserve `.xcresult` output. The 12-test standalone audio
   continuity suite passed on the iPad Pro 13-inch M5 simulator, but the host's
   iOS 27 Media Device route is outside that test scope.
3. On the iPhone the owner assigned to this goal, verify Files playback, background and lock
   behavior, route recovery, output corrections and the exact AUv3 host path.
4. Through a connected Bluetooth endpoint, complete the separately documented
   steady-state and reconnect runs. Record unavailable host counters as unknown.
5. Verify update migration, saved presets, AutoEq catalog availability and
   accessibility labels before treating the iPhone build as release-ready.

The signed build 25 app bundle contains `autoeq.sqlite`; `PRAGMA integrity_check`
returns `ok`, both catalog tables contain 8,862 rows, all preset rows have
metadata, and category totals are 5,807 in-ear, 2,927 over-ear and 128 earbud.
The bundle database is verified, but the catalog UI and search have not been
exercised on the disconnected iPhone.

Xcode 27.2 first-use setup, host signing and build 14 installation succeeded
earlier on 2026-11-25. Build 25 compiles and signs for arm64 iPhoneOS, and its
signature verifies. An exact-UDID install attempt returned CoreDevice 4016
because the iPhone 15 reports unavailable to Xcode and has no assertable
connectivity/service states. JetKVM-observed Xcode Device Hub listed only the
iPad simulator; the iPhone was absent from USB inventory and local-network
discovery returned error -27. The route-warning visibility predicate is
included in the signed host and previously passed the focused 8-test Logic suite. The AutoEq catalog search and output assignment also passed
on the iOS 26 simulator as part of the standalone test suite (49 passed, 0
failed, 1 skipped). The full iOS host UI and physical route behavior still
require an available phone.
The standalone app's refreshed arm64 iPhoneOS build (version 0.1.0, build 6)
also compiles and has a valid signature. A full iOS 26 simulator run passed
48/48 standalone unit tests and all eight UI tests. A generated Debug-only WAV
fixture makes the background-playback UI case self-contained, so there were no
skips. This includes the separate host AU lifecycle UI test. Result bundle:
`/Volumes/SonanceEQBuildScratch/SonanceStandaloneFullRegression-Rerun.xcresult`.
The focused audio-continuity result bundle contains 12/12 passes. Install of combined host
build 19 was attempted with `devicectl` and failed with CoreDevice error 4016:
the exact iPhone 15 currently reports `unavailable`, does not appear in USB
inventory, and its Bluetooth record is not connected. Build 18 is not installed.
iPhone route behavior, in-host stage routing, import/share, Mid/Side and FIR
device behavior, real-time deadline measurements and physical Bluetooth
playback remain unverified. The route companion still requires Apple's Media
Device entitlement and matching profiles.
