# iOS 27 routing experiment

Status: **not tested**. The existing Sonance iOS prototype plays files and
provides an AUv3 effect; it does not itself register a Media Device route.
Speech listening modes are available independently in the player and AUv3 host.

Apple documents Media Device as a way to stream to playback hardware, and
requires the media-device-extension entitlement for the extension and container
app. The developer agreement defines the extension in terms of sending media
to another device; section 3.3.7(L) also describes the container app's
purpose as delivering and installing the extension. An existing third-party app demonstrates same-phone audio
processing, but that is not proof that this implementation is permissible,
that a future submission will be accepted, or that each source app will work.
Confirm the applicable agreement and Apple review position before release.

- [Apple Media Device documentation](https://developer.apple.com/documentation/MediaDevice)
- [Apple developer agreement](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/)
- [EffectDeck source and implementation notes](https://github.com/satomasahiro2005/EffectDeck)

## Prerequisites

1. Xcode with the iOS 27 device SDK and a signed development build. The
   installed Xcode 26.0.1 provides only the iOS 26 SDK.
2. Sarah's iPhone 11, UDID `00008030-000359A13688802E`, connected, trusted,
   and running iOS 27. Verify its actual OS before testing; do not upgrade it
   or change its data as an assumed prerequisite.
3. A working selectable route, with signed extension and container app,
   and a documented plan for audio transport, interruptions, feedback loops,
   buffer underruns, teardown, and failure reporting. No route is implemented
   in this branch.
4. Retain the device log, app and OS versions, output, sample, and observed
   result for each row. Compare audible filtered and bypassed playback, and
   measure latency and battery with a stated method. Never infer a pass from
   discovery alone.
5. After all testing, uninstall the exact tested bundle ID from Sarah's phone
   and verify it is absent. Do not remove other apps or reset the phone.

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
