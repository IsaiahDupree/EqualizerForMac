# Sonance EQ for iOS

The first iPhone and iPad build runs on iOS 17 or later. Open a mono or stereo
file from Files, tap Play, and compare your changes with Bypass EQ. The app
includes the Mac app’s ten starting bands and five presets. Tap a point on the
curve to select its band. Drag it left or right to change frequency and up or
down to change gain. The sliders remain available for fine adjustments and Q.
Preamp controls the overall level. The graph uses the selected file’s sample
rate.

The floating player stays on screen as you scroll the equalizer. While a file
is playing, use the Picture in Picture button on supported devices to see the
EQ curve and playback progress in a resizable window. Its play and pause
controls operate the file in Sonance. Tap the return-to-app button to edit the
curve.

The same installed AUv3 effect processes the preview and appears independently
in compatible hosts. Search for **Sonance EQ** in the host’s effects list. The
host can open the same touch editor or present standard parameter controls.
The host saves the plug-in’s settings with its session and manages playback. The
effect supports planar Float32 mono and stereo from 8 to 192 kHz. Host control
changes ramp during processing. Sample-accurate automation is outside this
prototype’s scope.

## Closing and reopening

Sonance saves frequency, gain, Q, preamp, bypass, and the selected band on the
device when you finish a drag or slider edit. Going to the Home Screen also
saves the current EQ. Build 2 loads the EQ settings from build 1 when upgrading.

- Switching apps or locking the screen during Files playback uses iOS background
  audio. Stop playback in Sonance when you’re done.
- Force-quitting Sonance stops its own player. Reopening restores your EQ and
  opens the local player with an empty file selection. Choose a file and press
  Play to start a new playback session.
- An AUv3 host controls playback and stores its own effect settings. Opening or
  closing the Sonance screen leaves control of a hosted effect with the host.

## Build and verify

```sh
xcodegen generate --spec iOS/project.yml --project iOS
xcodebuild -project iOS/SonanceEQ.xcodeproj -scheme SonanceEQiOS \
  -destination 'platform=iOS Simulator,id=<simulator-udid>' \
  -jobs 1 -parallel-testing-enabled NO test
```

For a device build, use a development team that can provision
`com.isaiahdupree.SonanceEQ.iOSPrototype` and its `.AudioUnit` extension.
The prototype has its own bundle identifiers. The existing Mac app and its
StoreKit products use the production identifiers.

The initial validation used Xcode 26.0.1 and iOS Simulator 26.0. The simulator
discovered the installed extension, measured the expected mono and stereo
filter response, verified live bypass and host state restoration, and played
a file through the app. The app and extension also built for arm64 iOS.

Build 2 passed the settings relaunch, independent AUv3 host, and Files
playback Home Screen and force-quit cases on iOS Simulator 26.0. The iPhone
build declares Apple's background audio mode. Lock-screen and headphone
checks still require the designated physical iPhone.

Build 3 passed the simulator tests for touch selection and dragging, the
floating transport, rendering the curve and progress into video frames, and
loading the custom AUv3 editor. The app and extension built for arm64 iOS.
Verify the Picture in Picture window and EffectDeck's presentation on a
supported physical device.

The UI lifecycle suite changes the EQ, goes to the Home Screen, and terminates
and relaunches Sonance to verify restored settings. An independent test host
measures its EQ output before and after Sonance terminates. To include the
active background playback case, put a 30-second mono or stereo WAV named
`Sonance Background Verification.wav` at the top level of **On My iPhone** or
**On My iPad** in Files on the test device.

## iOS 27 routing

[Apple’s MediaDevice documentation](https://developer.apple.com/documentation/MediaDevice/creating-a-media-device-extension)
describes an entitlement and audio server driver for playback on external
devices. The [Apple Developer Program terms](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/)
also define the extension around sending media to another device. The
[EffectDeck listing](https://apps.apple.com/us/app/effectdeck/id6812467517)
describes same-phone routing and support for AUv3 effects. Loading Sonance in
that host is the candidate iOS 27 path. Sonance itself exposes playback from
Files and the AUv3 effect. Direct Control Center routing would need a supported
same-device design and independent device and distribution validation.

Hardware acceptance uses Sarah’s designated iPhone 11. Verify that the plug-in
appears in an AUv3 host, then compare bypass and a clearly audible band change
on routed music and podcast playback. Check headphones, lock screen playback,
interruptions, disconnect and reconnect, and recovery. Record the OS, host and
player versions, route, and outcome for each case. Remove the exact Sonance
prototype bundle from that phone after testing and verify it is absent.
