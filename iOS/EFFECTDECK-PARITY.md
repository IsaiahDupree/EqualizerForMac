# Sonance EQ iOS — EffectDeck feature parity

This branch turns Sonance EQ into an iPhone audio host as well as an EQ. It
embeds the pinned, MIT-licensed EffectDeck host and DSP, then adds Sonance EQ as
an Audio Unit and brands the host as Sonance EQ. The goal is to make the
EffectDeck workflows available inside Sonance EQ while retaining Sonance's
32-band EQ, AutoEQ catalog, correction profiles, presets and standalone player.

## Current implementation status — 2026-11-24

| EffectDeck workflow | In the Sonance iOS source | Build / device evidence |
| --- | --- | --- |
| Ordered effects chain | Add, remove, reorder, collapse, bypass and persist chain stages; chain enable, I/O and latency indicators | Full host and embedded extensions compile for arm64 iPhone SDK unsigned. Not signed or run on iPhone. |
| Effects, plug-ins and presets browser | Searchable Effects / Plugins / Presets tabs; categories; built-in effects and analyzers; installed AUv3 discovery and editors; system, user and effect presets | Source is included in generated `EffeTuneLive` target and compiles unsigned. Device behavior remains unverified. |
| Signal routing | Routing screen shows each stage's input/output buses and channel mode; stage channel maps and multichannel processing are part of the host | Source compiles unsigned. No physical route or multichannel device run yet. |
| Import, export and sharing | Clipboard chain replacement, share links, chain and preset import/export, share extension and import inbox | Host and share extension compile unsigned. The host/share App Group is not assigned to the development profiles, so signed install and shared-container runtime remain blocked. |
| Analyzers and meters | Level / analog meters, spectrum, note spectrum, spectrogram, oscilloscope and other built-in analysis stages | Source compiles unsigned. Meter and analyzer readings have not been checked against device fixtures. |
| Processing and power settings | Oversampling, DSP buffer selection, input format/buffer, CPU and latency display, pause-after-silence, silence threshold, keep-screen-on and visual sync controls | Source compiles unsigned. Real-time deadline and power behavior remain unmeasured on iPhone. |
| Floating meters and chain controls | Floating meter controls, chain-level effects switch and per-card enable, collapse and menu actions | Source compiles unsigned; UI interaction is not device-verified. |
| Remote control | Remote settings and QR-code scanning workflow | Source compiles unsigned. No remote peer/session was tested. |
| About and support | Version, DSP version, limitations, licenses, privacy and feedback links | Source compiles unsigned. Final branded copy is applied by `HostConfig/apply-upstream-adaptation.py`. |
| Control Center output routing | Separate minimal `Sonance EQ Route` installer and Media Device extension; extension sends captured samples to the full host's DSP chain over the loopback PCM bridge | Both targets compile unsigned. Apple Media Device entitlement/profile is unavailable; route cannot be signed, installed or exercised. |
| Sonance EQ | Existing Sonance AUv3 embedded in the host, alongside the standalone 32-band EQ, AutoEQ data, corrections and presets | Host target compiles unsigned. AU lifecycle, state transfer and audio quality are not device-verified in this host. |

The screenshots' routing screen and the Effects / Plugins / Presets browser are
implemented in the host source. They are not yet evidence that those controls
work on the phone. The latest full host is version 0.2.0 (build 7); the phone
still has the earlier 0.1.0 (build 6) app.

## Apple route architecture and limits

Apple requires the Media Device entitlement on both the route extension and a
separate container app whose only purpose is to deliver/install that extension.
That is why the project contains a small `Sonance EQ Route` installer alongside
the full Sonance EQ host. The installer must be present before Sonance EQ can
appear as a Control Center output. The host app itself contains the chain editor,
Sonance EQ Audio Unit, share extension, import workflow and DSP processing.

The full host and Share extension require the App Group
`group.com.isaiahdupree.SonanceEQ`. That group is enabled on the existing App IDs
but has not been assigned to the development profiles. Xcode's authenticated
App Store Connect API-key provisioning created profiles but did not add this
App Group. The Apple Developer web session available during the 2026-11-24
attempt was not signed in, so the profiles still need the group assigned through
the Apple Developer account before the host can be signed and installed. The
route installer separately needs Apple's Media Device capability and a matching
profile. Neither product bundle is currently installed from this branch.

This Media Device workflow is experimental until Apple grants the entitlement
and the signed route is validated on the phone. It follows Apple's documented
Control Center media route model; do not claim arbitrary capture of other apps
or games, per-app routing, or a proven Bluetooth return path. System routing,
standalone file playback and compatible-host AUv3 use are separate audio paths
and need separate evidence.

## Build and next validation

Regenerate the host project from its tracked spec:

```bash
bash iOS/Tools/generate-sonance-host-project.sh
```

The generated project is in the vendored checkout and ignored. The tracked
source of truth is `iOS/sonance-host.project.yml` plus
`iOS/HostConfig/apply-upstream-adaptation.py`. Homebrew Python 3.11 or newer is
required for the upstream asset generator.

After Apple provisions both targets, the next steps are to install the full
host and route installer on the assigned iPhone, verify the chain editor and
stage routing, run the audio-quality and AUv3 lifecycle suites, and exercise
Control Center → Sonance EQ → DSP chain → selected Bluetooth output. Capture
separate evidence for direct Bluetooth playback, the host with an empty chain,
the host with Sonance EQ flat, and the controlled EQ configuration. Record
unavailable counters as unknown. Clean up only the tested Sonance app bundle IDs
after the assigned physical testing is complete.

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
