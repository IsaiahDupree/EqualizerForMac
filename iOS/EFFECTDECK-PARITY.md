# Sonance EQ iOS — EffectDeck feature parity

This branch turns Sonance EQ into an iPhone audio host as well as an EQ. It
embeds the pinned, MIT-licensed EffectDeck host and DSP, then adds Sonance EQ as
an Audio Unit and brands the host as Sonance EQ. The goal is to make the
EffectDeck workflows available inside Sonance EQ while retaining Sonance's
32-band EQ, AutoEQ catalog, correction profiles, presets and standalone player.

## Current implementation status — 2026-11-24

| EffectDeck workflow | In the Sonance iOS source | Build / device evidence |
| --- | --- | --- |
| Ordered effects chain | Add, remove, reorder, collapse, bypass and persist chain stages; chain enable, I/O and latency indicators | Host 0.2.0 build 8 installed on iPhone 15. Interaction and audio processing still need device validation. |
| Effects, plug-ins and presets browser | Searchable Effects / Plugins / Presets tabs; categories; built-in effects and analyzers; installed AUv3 discovery and editors; system, user and effect presets | Included in generated `EffeTuneLive` target and signed. Device behavior remains unverified. |
| Signal routing | Routing screen shows each stage's input/output buses and channel mode; stage channel maps and multichannel processing are part of the host | Included and signed. Stage routing has not yet been exercised on device. |
| Import, export and sharing | Clipboard chain replacement, share links, chain and preset import/export, share extension and import inbox | Host and Share extension are signed with `group.com.isaiahdupree.SonanceEQ`; host launch is verified. Share-container workflows remain unverified. |
| Analyzers and meters | Level / analog meters, spectrum, note spectrum, spectrogram, oscilloscope and other built-in analysis stages | Included and signed. Meter and analyzer readings have not been checked against device fixtures. |
| Processing and power settings | Oversampling, DSP buffer selection, input format/buffer, CPU and latency display, pause-after-silence, silence threshold, keep-screen-on and visual sync controls | Included and signed. Real-time deadline and power behavior remain unmeasured on iPhone. |
| Floating meters and chain controls | Floating meter controls, chain-level effects switch and per-card enable, collapse and menu actions | Included and signed; UI interaction is not device-verified. |
| Remote control | Remote settings and QR-code scanning workflow | Included and signed. No remote peer/session was tested. |
| About and support | Version, DSP version, limitations, licenses, privacy and feedback links | Included and signed. Final branded copy is applied by `HostConfig/apply-upstream-adaptation.py`. |
| Control Center output routing | Separate minimal `Sonance EQ Route` installer and Media Device extension; extension sends captured samples to the full host's DSP chain over the loopback PCM bridge | Both targets compile unsigned. Apple Media Device entitlement/profile is unavailable; route cannot be signed, installed or exercised. |
| Sonance EQ | Existing Sonance AUv3 embedded in the host, alongside the standalone 32-band EQ, AutoEQ data, corrections and presets | Host and AUv3 extension compile and sign. AU lifecycle, state transfer and audio quality are not device-verified in this host. |

The screenshots' routing screen and the Effects / Plugins / Presets browser are
implemented in the host source. The latest full host is version 0.2.0 (build 8).
On 2026-11-24, the host and both embedded extensions built and signed for
arm64 iPhoneOS; the signed host and Share extension both contain the expected
Sonance App Group entitlement. Build 8 is installed and launched on iPhone 15
UDID `00008120-000465A20C52201E`; `devicectl` confirms version 0.2.0, build 8.
The current device capture showed TikTok in the foreground, so it verifies
neither the Sonance screen nor audio playback. In-app routing and physical
CarPlay/Bluetooth behavior remain unverified.

## Apple route architecture and limits

Apple requires the Media Device entitlement on both the route extension and a
separate container app whose only purpose is to deliver/install that extension.
That is why the project contains a small `Sonance EQ Route` installer alongside
the full Sonance EQ host. The installer must be present before Sonance EQ can
appear as a Control Center output. The host app itself contains the chain editor,
Sonance EQ Audio Unit, share extension, import workflow and DSP processing.

The full host and Share extension require the App Group
`group.com.isaiahdupree.SonanceEQ`. On 2026-11-24 the group was assigned to both
App IDs in the Apple Developer account; Xcode regenerated the profiles and the
signed host and Share extension now carry that entitlement. Host install and
launch are verified on iPhone 15; shared-container runtime verification is
still pending. The route installer separately needs Apple's Media Device
capability and a matching profile. No route companion was installed from this
branch. The installed host asks the user to select the Sonance EQ Control
Center output and install Sonance EQ Route if it is absent. Since the route
extension cannot yet be installed, system playback through that route is not
available or verified from this build.

This Media Device workflow is experimental until Apple grants the entitlement
and the signed route is validated on the phone. It follows Apple's documented
Control Center media route model; do not claim arbitrary capture of other apps
or games, per-app routing, or a proven Bluetooth return path. System routing,
standalone file playback and compatible-host AUv3 use are separate audio paths
and need separate evidence.

### Source-player compatibility and CarPlay fallback

The Media Device route is opt-in per source app: a player must use Apple's
AVSystemRouting API before iOS can send its audio to this route. The supplied
SoundCloud screenshot shows the player rejecting “EffectDeck Audio” and leaving
the output on iPhone Speaker while CarPlay is available. That source-app refusal
is outside Sonance EQ's control; the extension cannot identify or override an
app that never starts a route session. The host UI shows its current
output and the last observed AVAudioSession output transition while no source
audio is reaching the host. This records the route change and its system reason
for diagnosis; it does not claim the source app's private rejection message is
observable inside Sonance EQ. When the output is the built-in speaker or car
audio, the banner names that route and explains how to reselect Sonance EQ. If
SoundCloud explicitly rejects the route, use CarPlay directly or play a local
file in Sonance EQ. iOS does not expose a way for Sonance EQ to force-select the
route or make an incompatible source stream. The host now detects three or more
route changes in a rolling 30-second window, reports readable transition
reasons, and expires the warning as the window ages. Version 0.2.0 (build 8)
contains this change and is installed on the iPhone. The diagnostic UI was not
visible in the latest capture, and physical route-bounce verification remains
pending. This does not mean the route companion is installed or SoundCloud is
supported.

Apple documents that source apps use `AVSystemRoute` to start playback and that
the system delivers real-time samples only after a source app starts a route
session: [Creating a Media Device Extension](https://developer.apple.com/documentation/MediaDevice/creating-a-media-device-extension).

## Build and next validation

Regenerate the host project from its tracked spec:

```bash
bash iOS/Tools/generate-sonance-host-project.sh
```

The generated project is in the vendored checkout and ignored. The tracked
source of truth is `iOS/sonance-host.project.yml` plus
`iOS/HostConfig/apply-upstream-adaptation.py`. Homebrew Python 3.11 or newer is
required for the upstream asset generator.

The install script builds, installs and launches the full host independently:

```bash
bash iOS/Tools/install-on-iphone15.sh
```

The host and Share extension now have matching App Group profiles. Verify the
chain editor and stage routing, run the audio-quality and AUv3 lifecycle
suites, and capture separate evidence for direct Bluetooth playback, the host
with an empty chain, the host
with Sonance EQ flat, and the controlled EQ configuration. Record unavailable
counters as unknown. Clean up only the tested Sonance app bundle IDs after the
assigned physical testing is complete.

Control Center output routing is a separate, optional installation step:

```bash
SONANCE_INSTALL_ROUTE_COMPANION=1 bash iOS/Tools/install-on-iphone15.sh
```

It requires Apple's Media Device entitlement and matching profiles for the
route extension and installer. That requirement no longer blocks installing
the full host or using its in-app chain routing screen.

## Licensing and references

EffectDeck host source is MIT-licensed. Keep the upstream license and all
bundled DSP/runtime notices with the vendored source, and retain the local
adaptation disclosures. The app is an independent project and is not affiliated
with or endorsed by EffectDeck or its author.

- [EffectDeck source](https://github.com/satomasahiro2005/EffectDeck)
- [EffectDeck license](https://github.com/satomasahiro2005/EffectDeck/blob/main/LICENSE)
- [EffectDeck feature listing](https://apps.apple.com/app/effectdeck/id6812467517)
- [Apple Media Device entitlement requirements](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.media-device-extension)
- [Apple App Groups capability setup](https://developer.apple.com/help/account/identifiers/enable-app-capabilities)
