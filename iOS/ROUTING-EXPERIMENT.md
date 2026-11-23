# iOS 27 routing experiment

Status: **not tested; not productized**. The existing Sonance iOS prototype
plays files and provides an AUv3 effect; it does not register a Media Device
route. A separate [debug-only Route Lab](RouteExperiment/README.md) contains
unverified source with a low-pass filter, unauthenticated transport, and
unresolved privacy concerns. It is not integrated into Sonance EQ. Speech
listening modes are available independently in the player and AUv3 host.

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

1. Xcode 27.2 with the iOS 27 SDK. It is installed on this Mac, but its
   first-use license has not been accepted, so builds cannot run yet.
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
