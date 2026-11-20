# Sonance EQ for iOS

The first iPhone and iPad build runs on iOS 17 or later. Open a mono or stereo
file from Files, tap Play, and compare your changes with Bypass EQ. The app
includes the Mac app’s ten starting bands and five presets. Each band has
adjustable frequency, gain, and Q. Preamp controls the overall level. The graph
shows the band response at the selected file’s sample rate. Adjustments are
saved on the device.

The same installed AUv3 effect processes the preview and appears independently
in compatible hosts. Search for **Sonance EQ** in the host’s effects list. The
host can expose the plug-in’s controls and save them with its session. The
effect supports planar Float32 mono and stereo from 8 to 192 kHz. Host control
changes ramp during processing. Sample-accurate automation is outside this
prototype’s scope.

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

The first validation used Xcode 26.0.1 and iOS Simulator 26.0. The simulator
discovered the installed extension, measured the expected mono and stereo
filter response, verified live bypass and host state restoration, and played
a file through the app. The app and extension also built for arm64 iOS.

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
