# Sonance EQ iOS host parity

This roadmap expands Sonance EQ from a file player and AUv3 effect into an
iOS audio host with the workflows shown in EffectDeck. Sonance's 32-band EQ,
AutoEQ catalog, presets, output correction, standalone player, and AUv3 effect
remain part of the app.

## Reference workflows and current status

| Capability | Sonance iOS today | Parity target |
| --- | --- | --- |
| Select Sonance as an audio output in Control Center | Not implemented in the product; a separate debug Route Lab exists | iOS 27 Media Device route feeding the Sonance processing chain, then the previously selected hardware output |
| Effect chain | Standalone file player contains Sonance EQ and output correction | Ordered, addable, removable, reorderable, bypassable chain with saved card state |
| AUv3 hosting | Sonance ships an AUv3 effect; the app does not host other Audio Units | Discover installed AUv3 effects, instantiate them, show their own editors, and keep each in chain order |
| Built-in effects and analyzers | Sonance EQ, spectrum/level analysis for its own player | EffectDeck-style DSP processors plus level, stereo, spectrum, spectrogram, and oscilloscope stages |
| Per-stage routing | Not implemented | Input/output bus and channel mapping, stereo/mono and multichannel options, with the real negotiated route format visible |
| Presets and sharing | Sonance JSON presets and AutoEQ text import | Local folders, factory presets, EffectDeck-compatible chain import/export, clipboard and universal links |
| Impulse responses and AutoEQ | AutoEQ catalog is bundled; no convolution stage | IR library/import and convolution plus correction profiles in the active chain |
| Host processing controls | Basic render counters; no host DSP controls | Oversampling, DSP buffer size, CPU and latency reporting, silence power policy, synchronized visuals, floating meters |
| Remote control and support | No remote DSP control panel | QR-based remote-control workflow, version/about, limitations, license and support information |
| iPad layout | Responsive single-column app | Two-column chain/editor layout where space allows |

The screenshots also show the chain-level enable switch, I/O and effect latency,
clipboard replacement notice, per-card enable/collapse/menu controls, and an
available-effects browser with Effects, Plugins, and Presets tabs. These belong
to the chain-host milestone.

## Implementation sequence

1. **Host foundation:** model a persistent effect chain, add/remove/reorder and
   enable/bypass stages, enumerate installed AUv3 effects, and host stages in
   their actual order. First end-to-end chain: Level Meter → Sonance EQ.
2. **System route:** replace the debug-only pass-through with a product-quality
   Media Device path connected to the same chain and to the selected speaker or
   Bluetooth output. Add route state, format negotiation, interruption and
   reconnect handling, loop protection, and render diagnostics.
3. **Effect library:** add the built-in processors and analyzer stages from the
   EffectDeck reference, keeping their upstream license notices and versions.
   Add per-stage channel routing and multichannel support.
4. **Preset and asset workflows:** import/export chain JSON and links, preserve
   unknown stages visibly, add preset folders, IR and EQ-profile libraries, and
   make clipboard imports reviewable before replacing the active chain.
5. **Host settings and polish:** oversampling and buffer controls, CPU/latency
   readings, power behavior, synchronized and floating meters, remote control,
   accessibility, iPad layout, About, limitations, and licenses.
6. **Validation:** run the audio continuity suite, AUv3 lifecycle and chain
   tests, then test the full selected-output → route extension → ordered chain →
   Bluetooth path on the assigned iPhone. Keep system-route, app playback, and
   third-party AUv3 validation as separate evidence.

## Host integration in progress

The `feature/sonance-effectdeck-ios-parity` branch now has a generated full-host
project spec at `iOS/sonance-host.project.yml`. It reuses the pinned MIT host
source and adds Sonance EQ's existing AUv3 target as an embedded extension in
the same app bundle. The host's pipeline, effect/plugin/preset picker, routing
editor, settings, meters, remote panel, and About screens remain the host UI;
Sonance EQ is available to add to its chain. The app bundle and Media Device
protocol use Sonance EQ identifiers, and a small idempotent adaptation script
updates the upstream protocol and App Group constants to match.

Regenerate the host project with:

```bash
bash iOS/Tools/generate-sonance-host-project.sh
```

The script initializes the pinned nested DSP/runtime submodules, runs the
upstream asset setup, applies the two Sonance identifiers, and regenerates the
project. The generated Xcode project lives inside the vendored checkout and is
ignored; the tracked spec and adaptation script are the source of truth.

The complete host, route extension, Sonance EQ Audio Unit, and share extension
compiled for the arm64 iOS 27 device SDK with code signing disabled. The
MediaDevice framework is not present in the Simulator SDK, so a simulator build
cannot validate the routing extension. The output bundle was checked for the
Sonance EQ bundle display name, matching Media Device protocol, and embedded
Sonance AUv3.

The local development profiles were inspected. They do not contain the
`com.apple.developer.media-device-extension` entitlement or
`group.com.isaiahdupree.SonanceEQ`. This host build therefore cannot be signed
and installed for a real route with the current profiles. Registering the
required Apple capability and App Group, then provisioning all embedded
identifiers, is the next device-install gate. Until then, the route implementation
is compile-verified only; routing, chain handoff, and Bluetooth playback have
not been established. Keep all upstream license notices with the vendored
source.

## Platform and distribution constraints

The system-output workflow uses Apple's iOS 27 `MediaDevice` and
`AVSystemRouting` frameworks. Apple's public guide describes a media device as
remote playback hardware and documents delivery of real-time samples to its
extension. Same-iPhone processing and the containing app's purpose need a
separate distribution review; a working third-party app is not evidence of
Apple entitlement approval or App Store acceptance. Keep the route feature
marked experimental until its entitlement, signing profile, iOS behavior, and
distribution position are verified. Do not describe it as system-wide support
for games or apps that do not expose a Now Playing transport.

The existing `iOS/RouteExperiment` is research code only. Its transport is not
authenticated and it must not be promoted into the product as-is. The
EffectDeck reference implementation is MIT licensed; any reused code must keep
the applicable MIT and bundled DSP/runtime notices and identify local changes.

## Sources

- [EffectDeck source](https://github.com/satomasahiro2005/EffectDeck) and its
  [MIT license](https://github.com/satomasahiro2005/EffectDeck/blob/main/LICENSE)
- [EffectDeck feature list](https://apps.apple.com/app/effectdeck/id6812467517)
- [Apple Media Device extension](https://developer.apple.com/documentation/mediadevice/mediadeviceextension)
- [Apple real-time Media Device sample delivery](https://developer.apple.com/documentation/MediaDevice/creating-a-media-device-extension)
- [Apple AVSystemRouting](https://developer.apple.com/documentation/AVSystemRouting)
