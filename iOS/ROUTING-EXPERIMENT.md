# iOS 27 routing experiment

Status: **route source integrated, entitlement and hardware behavior unverified**.
The host source includes a Media Device extension and PCM bridge, and the app
also has an independent local-file player and AUv3 effect. The Media Device
route is not usable in a signed product build yet: the managed entitlement and
matching provisioning profiles are missing. A separate [debug-only Route
Lab](RouteExperiment/README.md) contains additional unverified code and is not
integrated into Sonance EQ.

Apple requires the media-device-extension entitlement for both the extension
and its container app. Apple's current Media Device and AVSystemRouting guides
describe sending media from an iPhone to remote playback hardware. For real-time
audio, Apple's guide describes the system delivering samples to the extension
so it can stream them to that device; it does not document a same-iPhone return
path for effects or unrestricted capture from all source apps. The Apple
Developer Program Agreement defines a Media Device Extension as sending content
from the iPhone or iPad to another device. Section 3.3.7(L) says the app bundling
that extension should have the sole purpose of delivering and installing it.
This appears materially at odds with using the extension as a same-phone Sonance
EQ feature. Keep the experiment isolated and do not productize the route unless
Apple provides written guidance covering same-device processing and the
container app's purpose. A third-party demo does not establish approval or
App Store acceptance.

- [Apple Media Device documentation](https://developer.apple.com/documentation/MediaDevice)
- [Routing and streaming media to remote devices](https://developer.apple.com/documentation/AVSystemRouting/routing-and-streaming-media-to-remote-devices)
- [Apple developer agreement](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/)
- [EffectDeck source and implementation notes](https://github.com/satomasahiro2005/EffectDeck)

## Prerequisites

Same-device route validation is not part of the current app-build goal. Before
any product integration, obtain written Apple guidance on same-device effects
and the container app's permitted purpose. If that gate is resolved in the
future, the separate device prerequisites are:

1. Xcode 27.2 with the iOS 27 SDK. The current branch can compile the host
   without the Media Device entitlement, but the route installer cannot be
   provisioned for real route activation until Apple grants that capability.
2. Sarah's iPhone 11, UDID `00008030-000359A13688802E`, connected, trusted,
   and running iOS 27. Verify its actual OS before testing; do not upgrade it
   or change its data as an assumed prerequisite.
3. A working selectable route, with signed extension and container app,
   and a documented plan for audio transport, interruptions, feedback loops,
   buffer underruns, teardown, failure reporting and authenticated peers. The
   separate Route Lab does not yet meet these requirements.
4. Retain the device log, app and OS versions, output, sample, and observed
   result for each row. Compare audible filtered and bypassed playback, and
   measure latency and battery with a stated method. Never infer a pass from
   discovery alone.
5. After any future authorized device testing, uninstall the exact tested
   bundle ID from Sarah's phone and verify it is absent. Do not remove other
   apps or reset the phone.

## Compatibility matrix

Every row is untested. Add separate records for device model, OS, app version,
output and reproduction steps as runs are performed.

| Source or condition | Outcome | Evidence and caveats |
| --- | --- | --- |
| Apple Music | Not tested | |
| Spotify, including video/Canvas | Not tested | |
| YouTube Music | Not tested | |
| Podcasts | Not tested | |
| Safari audio and video | Not tested | |
| YouTube video | Not tested | |
| Wired headphones | Not tested | |
| Bluetooth headphones and reconnect | Not tested | |
| AirPlay output | Not tested | |
| Background and lock screen | Not tested | |
| Interruption and recovery | Not tested | |
| Latency and battery | Not tested | |

## CarPlay and system-audio routing diagnosis — 2026-11-27

There are two independent route legs, and the current design cannot claim a
working phone-to-EQ-to-CarPlay path:

1. **Ingress (source → EQ):** the Media Device extension can receive samples
   only after iOS activates its route and the source app sends audio to that
   route. Apple documents AVSystemRouting as an app-facing routing API. It is
   not an API for capturing arbitrary audio from other apps. In the supplied
   screenshot, SoundCloud explicitly rejects “EffectDeck Audio”; that session
   therefore has no source samples for Sonance to process.
2. **Egress (EQ → car):** `AudioIO.escapeVirtualDevice` detects when the host's
   own AVAudioSession is routed back to the Sonance virtual device and applies
   `overrideOutputAudioPort(.speaker)` to break the feedback loop. Apple
   documents that this override sends a `.playAndRecord` session to the built-in
   speaker. Consequently the current virtual-route design cannot deliver its
   processed signal to CarPlay while that escape is active. Removing the
   override without a different, independently selected output path risks the
   documented-in-code loop: virtual route → extension → DSP → host output →
   virtual route.

The local-file player is a separate, viable path: it owns the source audio,
processes it in Sonance, and configures an `.playback` audio session. It should
be tested with CarPlay as its selected output; this does not enable EQ of
SoundCloud or other apps. The AUv3 path likewise works only in an app that hosts
the Sonance Audio Unit.

Apple's iOS 27 AVSystemRouting guidance describes app playback to a remote
device and realtime samples delivered through a Media Device extension. It does
not describe using a same-iPhone virtual route as an unrestricted system-wide
audio tap followed by a second independent CarPlay output. The real-time
samples API is for a Media Device extension acting as a remote playback
endpoint; Apple documents receiving the mixed samples in an audio server driver
plug-in and transmitting them to that device. This is not a documented way to
take that stream back into the iPhone's AVAudioSession and select CarPlay as a
second output. The current Apple Developer Program terms also say an app
bundling this extension should have the sole purpose of delivering and
installing it, which conflicts with making the extension a feature inside a
general-purpose EQ app. Do not productize this topology unless Apple documents
and approves a specific design and app purpose.

The user-visible SoundCloud message (“does not support playing media with
‘EffectDeck Audio’”) is a source-app rejection, not an EQ setting or a CarPlay
route failure. In that state the extension receives no SoundCloud samples. The
supported Sonance-owned path to validate is local-file playback through the
currently active Bluetooth or CarPlay route. For audio from another app, use
only a source that actually supports a compatible AUv3 host/effect workflow.
The immediate, testable next step is to validate the owned local-file playback
path to CarPlay, while keeping route-ingress tests limited to source apps that
support Apple's route API. Record the actual active output and route-change
history; do not mark the route extension as passing until its entitlement and a
physical run are available.

On 2026-11-27, Xcode 27.2 built and installed combined host build 35
(0.2.0) on iPhone 15 `00008120-000465A20C52201E` running iOS 27.3, then
launched the host process. This verifies host build/sign/install only. The
device connection is `localNetwork`, not USB. `devicectl device info audio`
reports that this device does not support its Audio Output Device Selection
capability, so it did not provide the active Bluetooth/CarPlay route. The
physical endpoint comparison remains not run.

The targeted physical host UI test also remains unexecuted: its checked-in
manual provisioning profile targets `HostUITests`, while Xcode signs the
runner as `HostUITests.xctrunner`. Switching the target to automatic signing
then exposed that no Apple developer account is configured in this Xcode and
the wildcard profile does not contain the installed API-created development
certificate. The test stopped at signing and did not change the installed
build. Resolve the runner profile/account before claiming on-device UI test
coverage.
