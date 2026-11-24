# Sonance audio quality and Bluetooth continuity

This suite addresses two reports: intermittent audio cuts while Sonance EQ is
hosted in EffectDeck, and poor perceived quality with a strongly boosted profile
in Pragmatic Audio PEQ. It does not assume the two reports have the same cause.

## What a pass means

1. The installed Sonance AUv3 produces the intended samples, gain, channels and
   EQ response across legal host formats and buffer sizes.
2. A separate physical-device run shows continuous audible playback through the
   actual host and Bluetooth endpoint, including controlled lifecycle changes.

A simulator/offline pass proves item 1 only. An ordinary music silence, user
pause, call interruption or intentionally disconnected headphone is not an
unexpected dropout. Define a dropout as unexplained missing, repeated, corrupted
or discontinuous output while the source is supplying audio and the route is
expected to play. Keep expected interruptions explicitly timestamped.

The thresholds below are initial **project acceptance targets**, not Apple or
industry certification requirements. Record changes to a threshold and the
measurement reason; do not loosen it simply to make a failing build pass.

## Run the automated digital suite

On a Mac with Xcode 26 or newer, an installed iOS Simulator and XcodeGen:

```sh
bash iOS/Tools/test-audio-quality.sh
```

The runner selects an available iPhone simulator, generates the existing iOS
project, and executes `AudioContinuityTests` against the installed AUv3. It saves
an `.xcresult`, build/test log, commit, working-tree status, toolchain and run
manifest under `build/audio-quality/`.

The runner also checks the result bundle: all expected tests must actually run
and pass, with no skipped tests. An exit code of zero with an empty test
selection does not count as a pass.

An explicit destination is supported:

```sh
SONANCE_AUDIO_DESTINATION='platform=iOS Simulator,name=iPhone 17' \
  bash iOS/Tools/test-audio-quality.sh
```

Use a simulator that actually appears in `xcrun simctl list devices available`.
The example name is not a requirement. Passing a real-device destination still
executes offline digital rendering; it does not turn the suite into a Bluetooth
test. Physical-device signing must already be configured for such a run.

Run the suite directly on an owned Mac with Xcode and the iOS Simulator
available. Do not use hosted CI for this validation; retain the local result
bundle with the change review.

### Why these tests are different

The older `RenderStream.measure()` uses 48 kHz and fixed 960-frame blocks and
examines only the final block after 24 render calls. That verifies a settled
gain but can miss a hole earlier in the stream. The new helper retains every
rendered frame, checks every render result and compares whole streams.

Coverage in `AudioContinuityTests.swift` includes stable flat/bypass fidelity,
mono/stereo and sample-rate variations, legal irregular buffer sizes, static-EQ
consistency across buffer partitions, channel isolation, resource reallocation,
and a controlled high-complexity EQ case. The test source is authoritative for
the exact cases and numeric tolerances.

Two additional fixtures exercise supported gain/bypass edits during playback
and a +17.4 dB bass bell with explicit -18.4 dB preamp headroom. They verify
continuity and the intended output for those controlled Sonance inputs, not
every user preset or another app's implementation.

For the continuous 1 kHz/3 kHz fixtures, the gap detector uses overlapping 2 ms
windows at 0.5 ms steps. Injected 5 ms and 10 ms mutes crossing window boundaries
must be detected by that same helper. These fixture checks do not establish a
general music, acoustic, or click-detection threshold.

An enabled EQ is compared to its intended response, not to unprocessed music.
The test signal has known levels and channel identity. A zero crossing is not
a missing sample. A correct high-pass/notch filter can intentionally remove
signal energy; simple silence detection alone is not enough.

## Physical-device protocol

Start with the user's actual iPhone, OS, host build and Bluetooth model. Add
the phone speaker or wired output as a control. A second Bluetooth model is
useful after the first configuration is understood; a large device lab is not
needed to begin.

Use one locally stored track or continuous test fixture and the same moderate
listening level. First spend two minutes on each isolation condition. Complete
a 30-minute steady-state run for a configuration before recording it as passed.

| Condition | Purpose |
| --- | --- |
| Direct Bluetooth, no virtual processor selected | Establish the source/device/connection baseline |
| EffectDeck, empty chain | Test host delivery and output independently of Sonance |
| EffectDeck, Sonance only, flat settings | Test plug-in integration without an intentional tonal change |
| EffectDeck, Sonance only, modest known EQ and adequate preamp | Test actual processing |
| Pragmatic, profile/preferences/effects off | Establish that app's flat baseline |
| Pragmatic, selected profile at matched loudness | Separate intended EQ/effects/headroom from output damage |

Save the existing chain/profile before changing it. Select the intended physical
Bluetooth output before selecting EffectDeck. Keep Sonance's standalone file
player stopped while testing its hosted AUv3 instance. Use only one virtual
processing output at a time.

For the first EffectDeck comparison, 48 kHz processing and its 1,024-sample DSP
buffer are conservative diagnostic settings. Record the actual output rate and
buffer, because requested values are hints. After a clean baseline, repeat the
smaller-buffer or oversampling settings the user wants. These settings cannot
repair all route or stream-delivery defects.

### Steady-state target

- Thirty minutes of continuous source playback, with **zero unexplained audible
  gaps**, short fills/underruns, render errors, and nonfinite output samples.
- No unexpected channel change or telephone-quality route during music.
- No unexplained level or tonal change in flat mode.
- Adequate headroom in the tested EQ fixture; no unexpected digital clipping.
- Record the source, route, host and render counters where available. Missing
  measurements remain unknown; they are never converted to zero.

Include screen lock, background/foreground transitions and ordinary editor use
without interrupting the source. Start with the supported normal chain, then
exercise the heaviest realistic supported chain. Offline rendering speed is not
evidence of real-time scheduling headroom.

For a development host that exposes render timing, record the actual deadline
`frames / sampleRate`. A proposed target is p99 processing time below half that
deadline and observed maximum below the deadline. At 48 kHz, 256 frames allow
5.33 ms; 1,024 frames allow 21.33 ms. Measure the complete active chain, not only
Sonance's filter math. Do not print logs, allocate or do disk/network work from
an audio callback to obtain these measurements; export preallocated counters
outside rendering.

### Recovery target

Record ten deliberate route/recovery trials, separate from uninterrupted
playback. Include headphone reconnect, switching to/from a control output,
background/foreground and lock/unlock as appropriate. Also exercise a real
interruption and the case where resumption is not allowed.

Preserve the EQ state, re-read the actual sample rate/channel count/buffer,
and avoid repeated engine rebuilds. The initial recovery target is two seconds
after the route is usable **and playback resumption is allowed**. Do not time
recovery from the moment Bluetooth was intentionally switched off. Do not
override a user pause or an interruption that does not permit resumption. A
controlled route switch may have a bounded gap; unexplained steady-state gaps
remain failures.

## Preserve sound quality while testing

Use flat and steady bypass as integrity controls. Add independent checks for a
known preamp reduction, a bell's center gain, shelves/cuts and a useful preset.
Initial response targets can be approximately 0.1–0.25 dB at well-conditioned
measurement frequencies, with sample-error tolerances specified in code. Avoid
relative dB comparisons where the intended output is effectively zero.

For the reported Pragmatic screenshot, the visible bass boost exceeded +15 dB
and the applied preamp was -17.4 dB. Automatic attenuation provides room for EQ
boosts. Compare flat and EQ at matched loudness; do not confuse lower level with
a lower-quality Bluetooth codec. Reduce the phone volume before removing a large
attenuation. Test a modest bass adjustment with automatic headroom first.

Sonance's renderer does not contain a general output limiter. Tests with enough
headroom do not guarantee that any arbitrary +24 dB user profile cannot clip.
For preset validation, consider the maximum **combined** EQ response. A true-peak
ceiling, if adopted, needs a true-peak estimator; ordinary sample peaks are not
true peaks. No universal subjective "sounds good" result is implied by a
numerically correct filter.

## Capture evidence, not just the screen

Record the exact source fixture/track, Sonance commit/build, host version,
iPhone/OS, Bluetooth model, settings and durations. Note the time of each audible
failure and whether the Bluetooth device remained connected. In EffectDeck,
save its Audio/Details diagnostics and relevant log. In Pragmatic, inspect
Live Audio / Audio stream details for route, stream state and limiter/clipping.
UI labels may differ across releases, so include the version in the report.

An internal tap or screen recording may be upstream of the actual Bluetooth
failure. Listen at the endpoint; if necessary record its analogue output or
use a fixed acoustic pickup. Compare through the same Bluetooth/device path.
Do not demand bit identity after a lossy codec, DAC, speaker or microphone.

A recorded signal needs initial latency alignment and may need bounded gradual
clock-drift compensation. Realigning every short segment can conceal a missing
or repeated block. Keep delay jumps visible. A dedicated detector may flag
unexplained attenuation lasting 5 ms or longer in a continuous known fixture,
but that detection sensitivity is not permission for shorter faults. Verify
any detector by injecting silence, a repeated block and a missing block.

## Record and assess a device run

Copy `device-run-template.json` for each tested configuration. Fill it only with
actual observations; all unmeasured fields stay null/not-run. The assessor does
not connect to a device or manufacture telemetry:

```sh
python3 iOS/Tools/assess_audio_device_run.py path/to/device-run.json
python3 -m unittest discover -s iOS/Tools/tests -p 'test_*.py' -v
```

The evaluator distinguishes pass, fail and incomplete/not-run, with exit codes
0, 1 and 2 respectively. A clean listening run with unavailable host counters
is useful evidence but does not become a fully instrumented pass. A digital
CI result and the physical-device evidence remain separate.

The JSON assessor evaluates continuity and recovery evidence. It does not
calculate tonal response, true peaks, or callback timing from the record;
those require the separate signal and timing measurements above.

## How to use a failure

| Observation | First investigation |
| --- | --- |
| Direct Bluetooth fails | Source delivery, connection, interference or endpoint |
| Direct is stable; empty EffectDeck fails | Host/session/route/buffering |
| Empty host is stable; adding Sonance fails | AU rendering, resource negotiation, plug-in/host interaction |
| Flat Pragmatic is clear; selected profile sounds poor | EQ, additional effects, headroom and loudness matching |
| Audio returns only after app restart | Route/interruption recovery or stale engine state |
| Problems begin with microphone/call use | Session profile transition and negotiated format |

Add the smallest reproduction to the appropriate automated suite before
changing the code. Confirm the test fails with the defect, then passes with
the fix. Keep the user's real Bluetooth configuration in the device regression
matrix. A new app version, iOS update, host version or different endpoint
requires renewed evidence for that configuration.

## References

- [Apple: requesting audio session preferences](https://developer.apple.com/library/archive/qa/qa1631/_index.html) — requested hardware values are hints; read actual values after activation.
- [Apple: responding to route changes](https://developer.apple.com/library/archive/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/HandlingAudioHardwareRouteChanges/HandlingAudioHardwareRouteChanges.html) — routes can change rate, buffer duration and channels.
- [Apple: creating custom audio effects](https://developer.apple.com/documentation/avfaudio/creating-custom-audio-effects) — real-time render requirements.
- [Apple: AVAudioEngine configuration changes](https://developer.apple.com/documentation/foundation/nsnotification/name-swift.struct/avaudioengineconfigurationchange) — hardware format changes stop/uninitialize the engine.
- [EffectDeck connection guide](https://effectdeck.nemut.ai/guide/connect) — select the physical output before the virtual route.
- [Pragmatic developer guide](https://www.pragmaticaudio.com/articles/2026/10/pragmatic-audio-peq/) — headroom, processing toggles and diagnostic views.
