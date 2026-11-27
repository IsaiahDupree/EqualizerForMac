# Sonance EQ for iPhone — build status

This branch is a development prototype. It is not a finished, distribution-ready
iOS 27 cross-app product and has not been submitted or published.

## Latest physical install and Xcode checks — 2026-11-27

- Restored the host target's iOS 27 minimum after an iOS 26 device build exposed
  unguarded SwiftUI `reorderable` / `ReorderDifference` APIs that require iOS 27.
  Xcode 27.2 then built the combined host successfully for the exact iPhone 15.
- Installed and launched Sonance EQ **0.2.0 (35)** on
  `00008120-000465A20C52201E` (iPhone 15, iOS 27.3). `devicectl device info
  apps` verified the installed bundle ID and version; the host and AU process
  were present afterward. The CoreDevice transport was `localNetwork`, not USB.
- The build uses `/tmp/SonanceEQHostDeviceDerivedData` on local APFS. The prior
  external scratch volume had only 61 MiB free, and Xcode planning stalled when
  DerivedData was placed on the NTFS passport volume. The installer script now
  defaults to the verified local path and reports entitlement signing errors
  only when the log contains an actual matching provisioning error.
- A targeted host UI smoke test did **not** run. First, the pinned profile
  targeted `HostUITests` while Xcode requires `HostUITests.xctrunner`; automatic
  signing then stopped because no Apple developer account is configured in this
  Xcode and the wildcard profile does not include the installed development
  certificate. The project now leaves this test target on automatic signing,
  but a valid Xcode account/profile is still required for device UI tests.
- `devicectl device info audio` reports that Audio Output Device Selection is
  unsupported by this phone. No active CarPlay/Bluetooth endpoint or audio
  session was measured, so the physical Bluetooth/CarPlay playback acceptance
  run remains outstanding. The Media Device route capability is still absent.

## Latest standalone app regression — 2026-11-27

- The full `SonanceEQiOS` unit and UI scheme passed **59/59**, with zero skips,
  on the iPad Pro 13-inch (M5) iOS 26.0 simulator under Xcode 27.2. The result
  tree and manifest are retained in `iOS/AudioValidation/Results/2026-11-27/`;
  the full `.xcresult` is kept locally at
  `build/audio-quality/2026-11-27-full/SonanceEQiOS-FullSuite.xcresult`.
- Xcode reported three QoS priority-inversion warnings and two
  `_UIReparentingView` hierarchy warnings. The tests passed, but the QoS and UI
  warnings remain open follow-up items.
- This validates the standalone app and its AUv3 offline/render integration on
  a simulator. It does not validate the EffectDeck host's iOS 27 UI, iPhone
  audio output, Bluetooth, CarPlay or the Media Device route.
- The exact iPhone 15 again reports unavailable to CoreDevice (error -27 on
  `xcdevice`) and no iPhone is present in USB inventory. The updated build has
  not been installed; physical route playback remains unverified.

## Route-report sharing — 2026-11-25

- Added a user-triggered Share action to the route warning. Its report contains
  the app/build and iOS versions, current output, route-state flags, and recent
  transitions. It excludes track details and audio samples; nothing is sent
  until the user chooses a destination in the system share sheet.
- The focused host route suite passes **19/19** on the iOS 26 simulator. Result:
  `/Volumes/My Passport/SonanceEQ-build-34/RouteReportTests.xcresult`.
- Signed iPhoneOS build **0.2.0 (35)** passes strict deep signature
  verification. Host, Share extension, and Audio Unit extension all report
  build 35. App: `/Volumes/My Passport/SonanceEQ-build-35/SonanceEQHost.app`.
- The requested iPhone 15 remains paired but unavailable to CoreDevice. The
  exact-UDID install attempt returned error 4016; Xcode discovery returns -27,
  and USB inventory has no attached phone. Physical CarPlay and Bluetooth
  checks remain pending.

## Route diagnosis copy — 2026-11-25

- Updated the no-audio and Known limitations text to recognize both route labels
  shown to the user: **EffectDeck Audio** and **Sonance EQ Audio**. The recovery
  wording says to choose CarPlay directly for car audio, or use a compatible
  source/local file for EQ, without implying Sonance EQ can override a source's
  route rejection.
- Xcode 27.2 on the iOS 26 iPad Pro simulator: `StatusReadingsTests` passed
  20/20 and `ETRouteChangeHistoryTests` passed 17/17. Results:
  `/Volumes/SonanceEQBuildScratch/SonanceRouteHelpCopy.xcresult` and
  `/Volumes/SonanceEQBuildScratch/SonanceRouteBounceRetest.xcresult`.
- The focused route bounce suite passed 17/17 after its recovery guidance was
  updated to recognize both route labels. Result:
  `/Volumes/SonanceEQBuildScratch/SonanceRouteBounceCopy.xcresult`.
- Combined host build 34 (0.2.0) includes the detailed guidance and was built
  for iPhoneOS with the project's development team configured. The app at
  `/Volumes/SonanceEQBuildScratch/SonanceHostBuild34/SonanceEQHost.app` passes
  strict deep signature verification; the host, Share extension and Audio Unit
  extension report build 34. The iPhone 15 remains `unavailable` to CoreDevice
  and absent from USB inventory, so build 34 is not installed and no physical
  CarPlay or Bluetooth run has been completed.

## Live maximum-load render check — 2026-11-25

- Added a live player stress case with 32 active Mid bands, 32 active Side
  bands, Mid/Side enabled and linear-phase FIR enabled. It played a stereo
  fixture for 24 observation intervals, required continued analysis frames,
  and asserted zero Audio Unit render deadline misses.
- The focused iOS 26 iPad Pro M5 simulator run passed **1/1**, with no skips or
  failures. Result: `/Volumes/SonanceEQBuildScratch/SonanceLiveFullLoad.xcresult`.
  Xcode still emitted a QoS inversion runtime warning, so the deadline result
  applies to the measured simulator run only.
- A fresh install attempt for the signed host build 34 on iPhone 15 UDID
  `00008120-000465A20C52201E` failed with CoreDevice error 4016: no requested
  connectivity, power or service states were assertable. `devicectl` reports
  the device paired with Developer Mode enabled but unavailable; `xcdevice`
  still returns device-preparation error -27 and USB inventory has no iPhone.
  Physical installation, CarPlay and Bluetooth playback remain unverified.

## Latest iPhone install and route diagnosis — 2026-11-25

- Current standalone `SonanceEQiOS` scheme passed **57/57** unit and UI tests on
  the iOS 26 iPad Pro simulator, with no skips. This includes the all-sample
  audio-continuity suite, EQ/session and preset behavior, AU lifecycle,
  playback recovery, and player UI flows. Result bundle:
  `/tmp/SonanceStandaloneCurrent.xcresult`. Xcode recorded several simulator
  runtime warnings (thread QoS inversion and `_UIReparentingView` hierarchy); no
  test failed. Physical iPhone/audio routing remains unverified.
- The two live playback integration cases now also assert AU render telemetry:
  completed blocks are reported and the running deadline-miss counter stays at
  zero. The focused `AudioUnitIntegrationTests` suite passed 9/9 on the iOS 26
  simulator; result: `/tmp/SonanceAudioRealtimeTests.xcresult`. Xcode still
  reports QoS inversion warnings on those cases, despite zero measured AU
  deadline misses in the test. This is simulator evidence, not a phone result.
- Full embedded-host `Logic` suite now passes **1,436/1,436** on the iOS 26
  iPad Pro simulator with test parallelization disabled. Result:
  `/tmp/SonanceEffectDeckFullLogicSerial.xcresult`. A prior parallel run had
  1,435/1,436 passing because `JSFXAudioTests.testStereoSwapExchangesChannels`
  exceeded the 2-second JSFX compile guard; the exact test passed alone, then
  passed again in the successful serial suite. The first result bundle's
  simulator diagnostics are incomplete because its scratch volume ran out of
  space; it is retained as a failed-run record, not a pass.
- Combined host build 34 (0.2.0) contains the current route guidance for both
  **EffectDeck Audio** and **Sonance EQ Audio**, in the general no-audio state
  and both CarPlay bounce classifications. Its focused route-history suite
  passed 17/17 on the iOS 26 iPad simulator; result:
  `/Volumes/SonanceEQBuildScratch/SonanceRouteBounceCopyFinal.xcresult`. The signed
  app bundle is `/Volumes/SonanceEQBuildScratch/SonanceHostBuild34/SonanceEQHost.app`.
  CoreDevice still reports the exact iPhone 15 unavailable, and USB inventory
  has no iPhone, so installation and physical route validation are pending.
- Standalone playback now preserves a Bluetooth/CarPlay output identity if an audio-engine configuration notification arrives before the route-change notification. It records reconnectable outputs while playback is active and keeps a pending reconnect target ahead of the previous route identity; user-paused playback does not seed a new target. `PlaybackResumeSegmentTests` passed 6/6 on the iOS 26 iPad Pro M5 simulator. Result bundle: `/Volumes/SonanceEQBuildScratch/SonanceBluetoothReconnectPolicy.xcresult`.
- Combined host build 32 (0.2.0) embeds this update and the Effects host recovery UI; build succeeded for iPhoneOS and passed strict code-signature verification. App: `/Volumes/SonanceEQBuildScratch/SonanceHostBuild32/SonanceEQHost.app`. The iPhone 15 remains unavailable to Xcode and absent from USB inventory, so this build is not installed and its Bluetooth route has not been tested physically.
- Combined host build 33 (0.2.0) adds the current SoundCloud route-rejection guidance for both **EffectDeck Audio** and **Sonance EQ Audio**. iPhoneOS build and strict deep signature verification passed; app: `/Volumes/SonanceEQBuildScratch/SonanceHostBuild33/SonanceEQHost.app`. The phone is still unavailable, so installation and physical route validation remain pending.

- Installed and launched Sonance EQ 0.2.0 (build 28) on Isaiah's iPhone 15,
  UDID `00008120-000465A20C52201E`. `devicectl` confirms the app and its
  Audio Unit extension are installed and running.
- The supplied screenshots show SoundCloud explicitly rejecting **EffectDeck
  Audio**, after which iOS has **iPhone Speaker** selected while CarPlay remains
  available. This is a source-route compatibility rejection, not proof of an EQ
  render failure. Sonance EQ cannot make SoundCloud accept the route or force
  iOS to keep it selected.
- The recovery action now uses one shared predicate for the visible **Open Player** button and its tests, so route bursts, fallback routes, and CarPlay ↔ EQ/speaker bounces expose the same local-player escape hatch, while a restart-required state suppresses it. Focused `ETRouteChangeHistoryTests` passed 16/16 on the iPad Pro M5 simulator; result bundle: `/Volumes/SonanceEQBuildScratch/SonanceRouteRecoveryAction.xcresult`.
- Build 30 (0.2.0) compiled and signed for iPhoneOS. `codesign --verify --deep --strict` passed. App: `/Volumes/SonanceEQBuildScratch/SonanceHostBuild30/SonanceEQHost.app`. `xcdevice` reports Isaiah's iPhone 15 as unavailable with error -27 while browsing the LAN; `system_profiler` shows no iPhone on USB. This build is not installed and in-car behavior has not been verified.
- The no-audio banner now also offers **Open Player** whenever the host has no audio peer, so the fallback is available before a repeated route-change threshold is reached. Required-restart states still suppress the action. The generated host project compiles this UI path; focused `ETRouteChangeHistoryTests` passed 17/17 on the iPad Pro M5 simulator. Result: `/Volumes/SonanceEQBuildScratch/SonanceRouteRecoveryNoAudio.xcresult`.
- Build 31 (0.2.0) compiled and passed `codesign --verify --deep --strict`; app bundle: `/Volumes/SonanceEQBuildScratch/SonanceHostBuild31/SonanceEQHost.app`. It is not installed because Xcode cannot currently connect to the iPhone 15.
- The integrated host records AVAudioSession route changes, preserves recent
  evidence for 30 seconds, distinguishes CarPlay ↔ EQ and CarPlay ↔ speaker
  bounce patterns, and offers **Open Player** to recover into Sonance EQ's
  local-file player. Focused route-history tests passed 15/15 on the iOS 27.2
  iPad Pro M5 simulator. Result bundle:
  `/Volumes/SonanceEQBuildScratch/CarPlayRouteCurrent.xcresult`. Physical
  CarPlay behavior still needs an in-car reproduction.
- Generic route-instability warnings now also show **Open Player**; this closes
  a recovery-action gap when iOS is switching routes without matching a known
  CarPlay/speaker or CarPlay/EQ pattern. Build 29 compiled and signed for
  iPhoneOS; `codesign --verify --deep --strict` passed. App:
  `/Volumes/SonanceEQBuildScratch/SonanceHostBuild29/Build/Products/Debug-iphoneos/SonanceEQHost.app`.
  Xcode still reports the exact iPhone 15 as `unavailable`, so build 29 has not
  been installed and CarPlay behavior remains unverified on hardware.
- Build 28 contains the host and AUv3 extension, but not the separate Sonance
  EQ Media Device route extension. The Apple Media Device entitlement needed to
  ship that system route is still unavailable to this team. The phone's
  **EffectDeck** route is provided by the separately installed EffectDeck app;
  the Sonance host cannot claim or rename that route without Apple's entitlement.
- For SoundCloud in the car, select **CarPlay** directly and leave it selected
  (audio bypasses Sonance EQ). For EQ processing, use a compatible source in a
  supported host or play a local file in Sonance EQ.

## Latest CarPlay and EQ handoff work — 2026-11-25

- Retested the focused `ETRouteChangeHistoryTests` on the iOS 26 iPad Pro M5
  simulator: 15/15 passed, including the SoundCloud-style unsupported-route
  return, CarPlay/speaker and CarPlay/EQ bounce classification, event-history
  persistence, and recovery copy. Result bundle:
  `/Volumes/SonanceEQBuildScratch/CarPlayRouteHistoryRetest.xcresult`.
- Added an **Open Player** recovery button to the route warning. It switches
  directly to Sonance EQ's local audio player so the user can choose a file
  instead of repeatedly selecting a route the streaming app rejects. The
  generic iOS Simulator build compiled successfully with Xcode 27.2, arm64,
  and one build job. The app cannot read another app's rejection alert or
  change that app's route compatibility.
- Current USB inventory does not show the designated iPhone 11
  (`00008030-000359A13688802E`). Isaiah's iPhone 15 reports `unavailable` to
  Xcode. I did not install to the personal phone; physical CarPlay behavior
  remains unverified.
- The route banner now distinguishes three repeated CarPlay ↔ Sonance EQ
  handoffs from the existing CarPlay ↔ iPhone speaker pattern. It retains the
  last 30 seconds of route evidence across a quick app relaunch and explains the
  compatible-source/local-file fallback. CarPlay ↔ EQ bounces now use the same
  orange warning icon and text as the other route failures.
- The detector now also recognizes a connected three-change path through the
  iPhone speaker (CarPlay → speaker → EQ → CarPlay), while rejecting unrelated
  route records that do not connect. The focused XCTest suite covers this
  sequence, disconnected-route rejection, new-history persistence and loading
  history written by the older format. Simulator results do not validate the
  production Media Device extension or physical CarPlay behavior.
- The standalone Sonance Audio Unit continuity suite was rerun on the iOS 26
  iPad Pro simulator: 12/12 tests passed, zero skipped. Result bundle:
  `/Volumes/SonanceEQBuildScratch/SonanceGoalContinuityCurrent/AudioQuality.xcresult`.
- The regenerated EffectDeck-integrated host compiled for arm64 iPhoneOS at
  build 28 with exit code 0. This was a compile-only build; the signed app on
  the phone and the physical route remain unverified.
- Focused `ETRouteChangeHistoryTests`: 15/15 passed on the iOS 26 simulator
  after the warning presentation fix. Result bundle:
  `/Volumes/SonanceEQBuildScratch/SonanceRouteEQWarningUIFix.xcresult`;
  log: `/tmp/sonance-route-eq-warning-ui-fix.log`.
- Combined host simulator build including the warning-style fix succeeded.
  App: `/Volumes/SonanceEQBuildScratch/SonanceRouteWarningBuildDerivedData/Build/Products/Debug-iphonesimulator/SonanceEQHost.app`;
  log: `/tmp/sonance-route-warning-build.log`.
- Signed iPhoneOS build 0.2.0 (28) includes the same fix; bundle ID and deep
  signature verification passed. App:
  `/Volumes/SonanceEQBuildScratch/SonanceEQBuild27DerivedData/Build/Products/Debug-iphoneos/SonanceEQHost.app`;
  log: `/tmp/sonance-host-build28-device.log`.
- Exact-UDID install was attempted and returned CoreDevice error 4016 with no
  assertable connectivity/service states. The phone remains absent from USB
  inventory, so build 28 is signed but not installed.
- Combined host 0.2.0 (build 27) built and signed for arm64 iPhoneOS; deep
  codesign verification passed. App:
  `/Volumes/SonanceEQBuildScratch/SonanceEQBuild27DerivedData/Build/Products/Debug-iphoneos/SonanceEQHost.app`;
  log: `/tmp/sonance-route-eq-bounce-device-build-signed.log`.
- The assigned iPhone 15 UDID `00008120-000465A20C52201E` currently reports
  `unavailable` to Xcode, so build 27 is not installed and the physical CarPlay
  handoff is not verified. The supplied SoundCloud alert says it rejects
  EffectDeck Audio; the host cannot make that source support the route or force
  iOS to keep it selected. For that source, select CarPlay directly; EQ requires
  a compatible source or Sonance EQ's local-file player.

## Full standalone simulator regression — 2026-11-25

- The regenerated standalone iOS scheme passed 48/48 unit tests and all eight
  UI tests on the iOS 26 iPad Pro simulator. The missing Files fixture was replaced
  by a generated, audible Debug-only WAV test signal, so the playback test now
  runs without manual simulator setup. All 56 tests passed, with no skips,
  including background/resume, termination, preset, AU lifecycle, AutoEq and
  output-correction coverage.
- Result bundle: `/Volumes/SonanceEQBuildScratch/SonanceStandaloneFullRegression-Rerun.xcresult`;
  log: `/tmp/sonance-standalone-full-regression-rerun.log`.
- This verifies simulator behavior only. It does not replace iPhone 15 touch,
  Bluetooth playback, CarPlay, or AUv3 host validation.

## Route diagnostic status — 2026-11-24

- The host tracks route transitions, translates common system reasons, and
  raises an “Audio route keeps changing” warning after three or more changes
  within 30 seconds. The warning expires as the window rolls forward. It cannot
  read SoundCloud's rejection dialog or force an unsupported player onto the
  route.

## Route endpoint detection — 2026-11-25

- Route changes are now compared by port type and endpoint UID, using the
  `previousRoute` snapshot delivered with iOS route-change notifications. This
  catches transitions where two endpoints share a display name or a periodic
  refresh observes the new route before the notification handler runs.
- Xcode 27.2 built and signed version 0.2.0 (build 11), then installed and
  launched it on iPhone 15 UDID `00008120-000465A20C52201E`.
- Build log: `/Volumes/SonanceEQBuildScratch/SonanceEQHostDeviceInstall/EffeTuneLive-xcodebuild.log`.
- This confirms compilation and installation. The reported CarPlay/SoundCloud
  switching sequence has not been reproduced in the car. The app cannot
  observe SoundCloud's private rejection dialog or force its audio onto an
  unsupported route; direct CarPlay output or a compatible player is the
  available fallback.

## Route fallback diagnosis — 2026-11-25

- Build 13 recognizes both EffectDeck and Sonance EQ output names and retains
  the transition when iOS changes to another route, including CarPlay or the iPhone speaker. The
  host displays that state with the new current output and clears it when the
  Sonance route becomes active again.
- The guidance says to keep CarPlay selected if SoundCloud rejects Sonance EQ
  Audio. The host does not override or retry route selection; iOS owns that
  choice, and a source app that rejects the route cannot be made compatible by
  the effect host.
- Xcode 27.2 built, signed, installed, and launched build 13 on iPhone 15 UDID
  `00008120-000465A20C52201E`. `devicectl` verified the installed host version
  as 0.2.0 (13). Build log: `/Volumes/SonanceEQBuildScratch/SonanceEQHostDeviceInstall/EffeTuneLive-xcodebuild.log`.
- The actual CarPlay route notification still needs a physical run in the car.

## Route transition attribution — 2026-11-25

- The route-change banner now labels the transition using the previous route
  captured in Apple's notification. A periodic status refresh can update the
  current route before the notification handler runs; using the current cached
  label in that case produced misleading entries such as “CarPlay → CarPlay.”
- This improves detection and troubleshooting for EQ-to-CarPlay or EQ-to-speaker
  fallback. It does not make SoundCloud support the Media Device route or let
  Sonance EQ override iOS route selection.
- The combined host builds successfully with the fix. Physical CarPlay behavior
  and SoundCloud playback remain unverified; they require reproducing the route
  transition in the car.

## Route diagnostics host installed — 2026-11-25

- Device inspection found the connected iPhone still had the standalone 0.1.0
  (6) app installed. Built the current combined EffectDeck-style host and
  installed/launched version 0.2.0 (14) on iPhone 15 UDID
  `00008120-000465A20C52201E`.
- The installed host includes endpoint-aware route diagnostics, route-flap
  warning and direct-CarPlay guidance when a source rejects the EQ route.
- Physical CarPlay route switching remains unverified. The screenshots show
  SoundCloud rejecting EffectDeck Audio; Sonance EQ cannot override that app's
  route support or iOS output selection.

## SoundCloud and CarPlay route report — 2026-11-25

- The supplied screenshots show iPhone Speaker selected while CarPlay and the
  EffectDeck route are available, followed by SoundCloud's explicit alert:
  “SoundCloud does not support playing media with EffectDeck Audio.” This is
  direct evidence that the selected source rejects the EQ audio route; it is
  not evidence of an EQ render failure.
- The installed host's route observer records transitions away from Sonance EQ
  and shows the current route, last transition and recovery guidance. It does
  not read SoundCloud's private alert, force iOS to retain an unsupported route,
  or bridge CarPlay audio into the EQ chain.
- Recovery for this source is to select CarPlay directly and keep it selected.
  EQ processing of SoundCloud playback requires SoundCloud to support the iOS
  Media Device route; Sonance EQ cannot add that support. Sonance EQ's own local
  file player remains a separate EQ playback path.
- Version 0.2.0 (14) remains installed on iPhone 15. The supplied screenshots
  document the source refusal, but the car's physical route-change sequence
  still needs an in-car run before claiming a reproduced route-flap test.

## CarPlay route-bounce detection — 2026-11-25

- Combined host build 25 records route endpoints using AVAudioSession port
  types and flags three consecutive CarPlay ↔ built-in-speaker transitions
  inside 30 seconds as a specific handoff pattern. The status banner names the
  pattern and tells the user to leave CarPlay selected for car playback or use
  a compatible source/local file for EQ.
- Added focused route-history tests for detection, banner guidance and avoiding
  false classification of unrelated Bluetooth/speaker transitions. The
  `ETRouteChangeHistoryTests` Logic target now passes 10/10 on the iOS 26 iPad
  Pro simulator. Result bundle:
  `/Volumes/SonanceEQBuildScratch/SonanceRouteHistoryModel-fixed.xcresult`;
  log: `/tmp/sonance-route-history-model-fixed.log`.
- Xcode 27.2 build 25 compiled and signed successfully; `codesign --verify
  --deep --strict` passed. Log: `/tmp/sonance-eq-build25.log`.
- The exact iPhone 15 UDID `00008120-000465A20C52201E` reports unavailable to
  Xcode with device-prep error -27, so build 25 is not installed. The route
  pattern needs a physical CarPlay run. This detection cannot make SoundCloud
  support the rejected EffectDeck Audio route or force iOS to select it.

## Media Device entitlement portal recheck — 2026-11-25

- Rechecked the Apple Developer account for Team ID `Y4HDXFWXUV` and the
  route-installer App ID `com.isaiahdupree.SonanceEQ.iOSPrototype.RouteInstaller`.
- The App ID's **Capability Requests** tab has no Media Device entry; Safari's
  page search for “Media Device” reports no match. The separate Capabilities
  list also has no matching capability. No entitlement request was submitted
  and no signing configuration was changed.
- This leaves Apple's managed `com.apple.developer.media-device-extension`
  entitlement and matching provisioning profiles as the blocker for the
  Control Center Media Device route. The existing route-bounce detector can
  explain observed CarPlay/iPhone-speaker switches, but cannot make an
  unsupported source such as the photographed SoundCloud session accept the
  EffectDeck Audio route.

## Persistent route evidence — 2026-11-25

- The host now stores the bounded route history in `UserDefaults` when iOS
  reports a route transition and restores it on app launch. Entries expire
  after 30 seconds of the same system-uptime epoch, so a quick relaunch retains
  the diagnosis while stale evidence and pre-reboot uptime values are discarded.
- The focused route-history Logic target passes 11/11 on the iOS 26 iPad Pro
  simulator, including serialization/restore and expiry. Result bundle:
  `/Volumes/SonanceEQBuildScratch/SonanceRouteHistoryPersistenceDefaults.xcresult`;
  log: `/tmp/sonance-route-history-persistence-defaults.log`.
- Combined host version 0.2.0 (build 26) builds and signs for arm64 iPhoneOS;
  `codesign --verify --deep --strict` passes. App bundle:
  `/Volumes/SonanceEQBuildScratch/SonanceEQBuild26DerivedData/Build/Products/Debug-iphoneos/SonanceEQHost.app`;
  log: `/tmp/sonance-eq-build26.log`.
- Build 26 is not installed. Xcode still lists the assigned iPhone 15 UDID
  `00008120-000465A20C52201E` with tunnel state `unavailable`. Physical route
  behavior and Bluetooth playback remain unverified.

## Preset and output-correction UI regression — 2026-11-25

- Fixed the UI test's preset-list navigation to handle lazy rows in the full-screen
  SwiftUI library sheet, then passed
  `EqualizerRelaunchTests.testNamedPresetCanBeSavedAndLoadedAfterRelaunch` on
  iPhone 15 UDID `00008120-000465A20C52201E`.
- The test covers saving and reopening a named preset, assigning it as output
  correction, toggling correction off, verifying the off state after process
  relaunch, and clearing the assignment and test preset.
- The UI test ran against the standalone `SonanceEQiOS` target (0.1.0 build 6);
  the combined 0.2.0 build 14 host was reinstalled and relaunched afterward.
- Result bundle: `/Volumes/SonanceEQBuildScratch/SonanceCorrectionUITest/RouteCorrection18.xcresult`.

## Route diagnostics build and iPhone install — 2026-11-24

- Fixed the upstream adaptation so route state, observer, and banner fields are
  each inserted once even after repeated project generation. The first device
  build exposed duplicate `@State` declarations; the clean regeneration and
  rebuild succeeded.
- Xcode 27.2 built and signed the full host and embedded extensions for the
  exact iPhone 15 UDID `00008120-000465A20C52201E`, then `devicectl` installed
  and launched `com.isaiahdupree.SonanceEQ.iOSPrototype`. `devicectl` reports
  version 0.2.0 (7). Build log:
  `/Volumes/SonanceEQBuildScratch/SonanceEQHostDeviceInstall/EffeTuneLive-xcodebuild.log`.
- A current device screenshot is retained at
  `/Volumes/SonanceEQBuildScratch/SonanceEQ-iPhone15-latest.png`. It shows the
  Sonance EQ host running; a YouTube picture-in-picture overlay covers part of
  the no-audio banner. No playback or Bluetooth continuity pass is claimed.
- The build used two Xcode jobs and kept DerivedData on the separate scratch
  volume. The system volume remains low on free space. The separate Media Device
  route companion was not built or installed; its entitlement/profile remains
  unavailable.

## Latest route-flap build and install — 2026-11-24

- Version 0.2.0 (build 8) compiled, signed, installed and launched on the exact
  iPhone 15 UDID `00008120-000465A20C52201E`. `devicectl` reports the installed
  host as `com.isaiahdupree.SonanceEQ.iOSPrototype`, version 0.2.0, build 8.
- Build log:
  `/Volumes/SonanceEQBuildScratch/SonanceEQHostDeviceInstall/EffeTuneLive-xcodebuild.log`.
  A device screenshot was captured at
  `/Volumes/SonanceEQBuildScratch/SonanceEQ-iPhone15-route-flap-build8.png`, but
  TikTok was in the foreground, so it does not verify the Sonance EQ warning UI.
- The route-flap code compiled, but the real car/CarPlay switching sequence has
  not been reproduced on device. SoundCloud's explicit unsupported-route alert
  remains a source-app limitation.

## Route-flap detection revision — 2026-11-24

- The route observer keeps a rolling 30-second window, shows plain-language
  transition reasons, and raises a warning after three or more output changes.
  The warning clears as those transitions age out. It never forces a route.
- The SoundCloud screenshot explicitly says it does not support “EffectDeck
  Audio.” Apple documents that source apps use AVSystemRouting to start playback
  on Media Device routes; Sonance EQ cannot make a nonparticipating source
  stream or read its private rejection dialog.
- This revision is included in installed version 0.2.0 (build 8). Physical
  CarPlay/Bluetooth route-bounce verification remains pending.

## Combined Sonance EQ and EffectDeck app — 2026-11-24

- Added the original Sonance EQ player/editor as a separate framework module
  and exposed it alongside the EffectDeck host in a two-tab app. This preserves
  the full file player and EQ UI while avoiding name collisions between the two
  codebases.
- XcodeGen initially produced an invalid duplicate `iOS` group for the sibling
  source paths. Setting `createIntermediateGroups: false` fixed project
  generation; regeneration and the device build now succeed.
- Xcode 27.2 built and signed the framework, host and extensions; the install
  script installed and launched `com.isaiahdupree.SonanceEQ.iOSPrototype` on
  iPhone 15 UDID `00008120-000465A20C52201E`. `devicectl` reports version 0.2.0,
  build 10. Build log:
  `/Volumes/SonanceEQBuildScratch/SonanceRouteBuild10/EffeTuneLive-xcodebuild.log`.
- Route-flap diagnostics are included. Physical CarPlay switching, SoundCloud
  compatibility and Bluetooth playback have not been verified; SoundCloud's
  explicit unsupported-route message remains outside the host's control.

## Current iOS build and install — 2026-11-24

- Xcode 27.2 is available and first-run setup is complete. Its global
  `DerivedData` symlink pointed at the absent
  `/Volumes/WatchBuilds20261103/StorageOffload/DerivedData` mount, preventing
  Xcode from creating build log stores. It now points to the writable APFS path
  `/Volumes/SonanceEQBuildScratch/XcodeDerivedData`.
- The generated full Sonance EQ host and its embedded AUv3/share extensions
  compile successfully for the connected iPhone 15 on the iOS 27.2 SDK, with
  code signing disabled. Automatic signing with the existing App Store Connect
  API key and correct developer team reached provisioning, but the profiles
  omit `group.com.isaiahdupree.SonanceEQ`. The group is enabled on the host and
  Share App IDs but is not assigned to their profiles; Apple Developer web
  account access is needed to assign it. The route installer separately needs
  Apple's Media Device entitlement and matching profile. Logs are retained at
  `/Volumes/SonanceEQBuildScratch/SonanceEQHostDeviceLatest-build.log` and
  `/Volumes/SonanceEQBuildScratch/SonanceEQHostDeviceLatest-sign-build.log`.
- The installed app on the iPhone is still `com.isaiahdupree.SonanceEQ.iOSPrototype`
  version 0.1.0, build 6. The new full host is version 0.2.0, build 7 and has not
  been installed. The separate `Sonance EQ Route` installer is also not
  installed. The iPhone is visible over its network interface, not USB.
- `iOS/Tools/install-on-test-iphone.sh` now defaults to the assigned stationary
  iPhone 11 UDID `00008030-000359A13688802E`. It regenerates the latest host
  project, builds both the full host and route installer, verifies their bundle
  IDs and signatures, and installs only after both builds succeed. The
  historical build results below were recorded against the iPhone 15 and do
  not establish current iPhone 11 availability or test status. The signed host
  build stopped on the missing App Group assignment;
  the separate route build stops because neither route profile contains
  `com.apple.developer.media-device-extension`. No install command was reached.
  Current logs are `/Volumes/SonanceEQBuildScratch/SonanceEQHostDeviceInstall/EffeTuneLive-xcodebuild.log`
  and `/Volumes/SonanceEQBuildScratch/SonanceEQRouteInstaller-sign-build.log`.
- An iOS 26 simulator runtime is installed, but the full host uses an iOS 27
  API (`ReorderDifference`) and cannot be compiled for that runtime by lowering
  its deployment target. No simulator launch or UI validation was performed.
- No tests were run. The automated audio suite and physical Bluetooth route
  session remain pending. The Media Device entitlement/profile is unavailable;
  the route and Bluetooth return path have not been verified on device.
- The EffectDeck-style iOS host scope is tracked in
  [EFFECTDECK-PARITY.md](EFFECTDECK-PARITY.md); the host target is now
  compile-verified as of 2026-11-24 (status below).

## EffectDeck parity host — 2026-11-24

- Added the full host as a separate XcodeGen project spec. It embeds the
  existing Sonance EQ AUv3 and includes EffectDeck's chain, effects/plugins/
  presets browser, routing, audio settings, meters, remote panel, About and
  share/import extensions. The host app is named Sonance EQ, version 0.2.0
  (build 7).
- The full host embeds the Sonance EQ AUv3 and share extension and provides
  EffectDeck's chain/effect/preset/routing/settings/remote/About workflows.
  The Media Device route is now a separate minimal `Sonance EQ Route` installer
  app, with only the matching protocol entitlement on its app and extension.
  Its loopback sample bridge feeds the full host's processing chain.
- Updated the host and Control Center/audio-driver route identity to Sonance EQ,
  including the self-route loop guard, Now Playing title, and install guidance.
- Updated the Share sheet and route troubleshooting copy to call the product
  Sonance EQ. The upstream EffectDeck issue links remain intact.
- The full host and route installer/extension compile for the arm64 iOS SDK
  with signing disabled. A fresh host build after the copy changes succeeded
  on 2026-11-24. The 154 installed profiles contain neither the Media Device
  entitlement nor `group.com.isaiahdupree.SonanceEQ`. The iPhone 15 is visible
  over its network interface, not USB. No signed install of this build, route
  run, or Bluetooth playback test has occurred.
- The iOS Simulator SDK does not provide the `MediaDevice` module, so this host
  route target cannot be validated in the Simulator. No automated tests were
  run.

Older notes below record the state when they were written; the status above is
the current build/install record.

## Utility portfolio progress — 2026-11-23

- Sonance now pauses its active player and preserves the playhead when an
  audio-session interruption begins. On iOS 27 it handles the new lifecycle
  and resumption-recommendation notifications and activates the session
  asynchronously before resuming; older systems use the legacy interruption
  notification and `shouldResume` option. A user Stop clears the pending
  resume. This is source-level behavior until Xcode can compile it and a
  physical interruption/reconnect run can verify it.
- A removed audio route now parks the standalone player at its current
  position. Reconnection automatically resumes only when the route identifies
  as Bluetooth and returns with the same output ID; a different route requires
  an explicit Play action. If the route's ID changes, Play rebuilds the graph
  from the saved position. This avoids silently sending interrupted Bluetooth
  audio to the phone speaker. Compile and route verification remain pending.

- Sonance's headphone profile assistant now displays a read-only preview of the
  generated frequency response and suggested preamp before saving or applying
  the curve. It remains a preference-based starting point, not a measured
  headphone correction.
- Sonance EQ now includes everyday Workout, Focus, and Late Night starting
  curves in the standalone profile screen and AUv3 preset menu. Built-in preset
  application calculates peak-response headroom and disables bypass. Late
  Night is documented as a tonal profile; it does not compress audio or limit
  playback volume. `git diff --check` passed. The focused profile verification
  and app build both stop before compilation because Xcode's first-use license
  remains unaccepted.
- Sonance EQ's response plot now gives VoiceOver the enabled-filter count and
  selected filter type, frequency, and applicable gain, with a hint to use the
  accessible controls below for editing. Source review and `git diff --check`
  passed; current Xcode compilation remains license-gated.
- Screenshot Scout reapplies device-backup exclusion hints to its selected
  images, videos, sampled frames, and indexes. A failed image-index save now
  rolls back the in-memory record and removes its private media copy.
- Screenshot Scout now rebuilds image and video SHA-256 lookup sets from its
  JSON indexes and updates them during import, rollback, and removal. This
  avoids a full saved-record scan for every duplicate check. Source review and
  `git diff --check` passed; Xcode compilation remains license-gated.
- Screenshot Scout now invalidates pending image and frame descriptions
  after user edits, save/clear actions, source removal, or leaving the detail
  screen. Late model results and errors no longer overwrite the active review.
  Xcode compilation remains license-gated.
- Screenshot Scout now writes updated image, video, and review-queue indexes
  before deleting private media. If index persistence fails, it restores the
  in-memory records and keeps the media; failed cleanup is reported separately.
- Screenshot Scout video search now marks which sampled timestamps contain a
  query term on each result card, so a video hit points to its relevant indexed
  moments. Source review and `git diff --check` passed; Xcode compilation
  remains license-gated.
- Screenshot Scout's video detail now shares timestamped text notes from
  sampled OCR, labels, and reviewed frame descriptions without including the
  video. Xcode compilation remains license-gated.
- Screenshot Scout's video detail now shares an individual sampled frame as a
  still image, with the source timestamp in its VoiceOver label. The user shares
  the chosen frame file without including the source video. Source review and
  `git diff --check` passed; Xcode compilation remains license-gated.
- Screenshot Scout's review queue now supports local multi-term search across
  queued image and video OCR, labels, and saved descriptions, with a visible
  match count and empty state. Xcode compilation remains license-gated.
- Screenshot Scout now keeps a pending state during search debounce and local
  index lookup, preventing a stale empty-results message from flashing between
  successive queries. Xcode compilation remains license-gated.
- Screenshot Scout library cards and review-queue rows now give VoiceOver a
  concise media label, key labels, a shortened OCR or scene-description excerpt,
  and matching sampled timestamps for video search results. The UI exposes the
  full media details after opening the card. Native compilation remains
  license-gated.
- Clear Record now writes its session index before deleting a recording and
  restores the session if that save fails. Transcript and rename edits also
  revert in memory when index persistence fails.
- Clear Record's session library now filters locally across session titles,
  transcripts, and saved summaries, with a visible match count and empty state.
  Every whitespace-separated search word can match across different fields;
  result rows show labeled transcript and summary excerpts. Search does not call
  a service. Source review and `git diff --check` are the available verification
  while Xcode remains license-gated.
- Clear Record now saves labeled bookmarks at the active playback position.
  Users can jump to a saved moment, remove it, find its label in the local
  session search, and include labeled timestamps in the text export. Older
  session index entries omit the optional bookmark field and remain decodable.
  Source review and `git diff --check` are available; native compilation is
  still stopped by Xcode's first-use license gate.
- Track Study now keeps a multi-track local library, migrates the previous
  single-track index, supports stoppable batch imports, searches title/key/
  tempo/instrument/pace/marker/loop metadata, and sorts by title/date plus
  analyzed first key/tempo. Multi-term search can combine metadata across
  fields, and result rows show up to two matching marker, loop, key, tempo,
  instrument, or pace labels. The library count reflects the active filter.
  VoiceOver labels each selectable row with its duration, available analyzed
  key and tempo, and the metadata explaining a search match.
  Music Understanding key results now display conventional note
  symbols rather than enum identifiers.
  Each track keeps its own practice data. A failed file import removes the
  partial copy, leaves existing records intact, and reapplies backup-exclusion
  hints to each stored audio
  file and the shared index. Xcode verification remains blocked by its
  first-use license.
- Track Study's library now surfaces up to five analyzed local tracks with the
  same detected first key or exact BPM, labels the matching metadata, and lets
  the user open a result for practice. It does not claim harmonic compatibility
  or predict transitions. `git diff --check` passed; native compilation remains
  blocked by Xcode's unaccepted first-use license.
- Clear Record's iOS 27 summary shortcut now prepares the latest transcript's
  draft in memory, opens an editable review sheet, and saves only after an
  explicit user action. Siri receives only a neutral status dialog.
- EverReach Capture now discards an on-device note suggestion if the user edits
  the draft or changes the screenshot/OCR source while generation is running.
  Leaving the screen invalidates the request, and obsolete errors are ignored.
  Attachment paths are unique and capture controls are locked during save.
  OCR now offers up to five explicit full-name contact matches, ordered by
  first appearance in the screenshot text. The local-only iOS Goal Picker now
  passes its selected image to this review flow; Apple Vision reads it locally,
  and reviewed contact notes save to local storage without placeholder OCR.
  Follow-up drafting and image attachment stay unavailable in local-only mode.
  Focused ESLint passed and a fresh local Expo iOS export bundled 3,699 modules
  into a 10.4 MB bundle on 2026-11-23. Native extension, App Group, and iOS 27
  model compilation remain blocked by Xcode's unaccepted first-use license. No
  iPhone installation was performed.
- EverReach's Goal Picker and message composer no longer invent imported-contact
  history, sample interests, or screenshot-analysis results. Suggested contact
  goals use saved fields and interactions; choosing a screenshot opens the
  existing review flow with the selected image and contact. Focused ESLint and
  the local Expo iOS export passed after these changes; no device install or
  service call was performed.
- Apple's release page was checked on 2026-11-23: iOS 27.2.1 remains public,
  iOS 27.3 beta 2 v2 remains the newest listed iOS beta, and Xcode 27.2 remains
  stable. Xcode 27.2 simulator builds still stop before compilation because
  the first-use license has not been accepted. `git diff --check` passed; no
  tests, simulator interactions, or phone installs were run.
- The bounded portfolio build command now regenerates Sonance EQ, Screenshot
  Scout, Track Study, and Clear Record projects from their tracked XcodeGen
  specs before Simulator builds. XcodeGen generation succeeded for all four
  specs. `bash iOS/build-utilities.sh` then stopped at its SDK-discovery
  preflight with exit code 2 because Xcode's first-use license is unaccepted;
  no target compilation started.

- Sonance EQ now exposes App Shortcuts to enable or disable bypass for the
  standalone file player. Both actions operate on the app's shared EQ session,
  preserve its current curve, and do not claim to control audio in other apps.
  Xcode 26.0.1 compiled the iOS Simulator app and AUv3 extension for arm64 and
  x86_64; the built App Intents metadata contains both shortcuts and their Siri
  phrases. Bundle IDs are `com.isaiahdupree.SonanceEQ.iOSPrototype` and
  `com.isaiahdupree.SonanceEQ.iOSPrototype.AudioUnit`. Siri and lifecycle
  behavior have not been exercised at runtime.
- Sonance's Files player now offers 15, 30, 45, 60, and 90 minute stop timers.
  The Sonance iOS app and AUv3 target compiled for the iOS Simulator with
  Xcode 26.0.1. The timer has not been exercised at runtime.
- Sonance's listening screen now includes a preference-guided headphone
  profile assistant. Three listening choices create a moderate editable EQ
  curve and estimate preamp headroom from the calculated filter response;
  users can save it as a preset or apply it for A/B comparison with the current
  curve. It does not measure headphones or identify a model. The
  updated Sonance app and AUv3 target built with Xcode 26.0.1 for the generic
  iOS Simulator destination. No runtime or listening check has been performed.
- Screenshot Scout is a separate iOS 17 app target in
  `Utilities/ScreenshotScout/`. It imports only images selected through
  PhotosUI, runs Vision OCR and image classification on-device, searches the
  local index, skips byte-identical reimports, and stores resized JPEG copies
  in its app container. It also ranks closest indexed images through Vision
  feature prints for manual review, with a cancel control and no auto deletion.
  Its iOS Simulator build succeeded with Xcode 26.0.1.
- Screenshot Scout now accepts user-selected videos, copies them into its app
  library, hashes them incrementally to skip exact reimports, and scans five
  sampled frames for OCR and scene labels. Search can surface text and labels
  from those frames; each result retains timestamps and opens the original
  video copy for review. Video indexing can be cancelled. Its library folder
  is excluded from device backups. The expanded target compiled for the iOS
  Simulator with Xcode 26.0.1; media picker and playback behavior have not been
  exercised at runtime.
- Screenshot Scout can export a JSON index without including local media files.
  Export offers a metadata-only manifest or an explicit option to include OCR
  text and Vision labels. The manifest omits app-container file paths. The
  updated target compiled for a generic iOS Simulator destination with Xcode
  26.0.1 on 2026-11-22. Export UI has not been exercised at runtime.
- Screenshot Scout source now includes a persistent image/video review queue,
  a queue view that opens media for inspection, explicit queue removal after
  review, and queue metadata in the JSON manifest. It also has an optional
  iOS 27 Foundation Models image-description path. That path passes a locally
  stored, user-selected image to the on-device model only when the model
  reports availability and image capability, then requires review before
  saving the description to the local search index. The Xcode 26.0.1 / iOS 26
  Simulator build succeeded on 2026-11-22 for arm64 and x86_64, bundle ID
  `com.isaiahdupree.ScreenshotScout`; the iOS 27 path compiles only with Xcode
  27 and has not been compiled or exercised. The queue and description flows
  have not been exercised at runtime.
- Clear Record is a second iOS 17 app target in `Utilities/MeetingNotes/`.
  It requires an explicit consent confirmation, records in the foreground,
  saves on an interruption or background transition, and offers on-device
  transcription only for locales whose recognizers support it. Its iOS
  Simulator build succeeded with Xcode 26.0.1; recording, locale availability,
  and transcription have not been exercised at runtime.
- Clear Record now requests Speech permission only when the person chooses to
  transcribe a saved recording, so microphone capture is not blocked by optional
  speech access. A transcript can be corrected and saved locally. This update
  compiled for a generic iOS Simulator destination with Xcode 26.0.1 on
  2026-11-22. Recording and transcription were not exercised at runtime.
- Clear Record now lists only Speech locales whose recognizers report
  `supportsOnDeviceRecognition`, checks service availability again at use, and
  stores the user's locale choice. The updated app target compiled for a generic
  iOS Simulator destination with Xcode 26.0.1 on 2026-11-22. Actual locale and
  recognition availability still require runtime verification on supported
  hardware.
- Clear Record now has an optional iOS 27 Foundation Models summary action for
  a saved local transcript. It creates an editable draft, saves only after
  review, records the source transcript digest, and marks a saved summary stale
  after transcript corrections. Xcode 26.0.1 compiled the fallback-only app for
  arm64 and x86_64 with bundle ID `com.isaiahdupree.MeetingNotes`; the iOS 27
  model path and permission behavior have not been exercised at runtime.
- Clear Record now also offers a Siri/Shortcuts action for transcribing the
  newest saved recording. It refuses to run while recording or transcribing,
  skips sessions that already have a transcript, and uses the app's selected
  on-device Speech locale. Xcode 26.0.1 built the arm64 and x86_64 Simulator
  app with bundle ID `com.isaiahdupree.MeetingNotes`; generated App Intents
  metadata includes the action and phrases. No runtime permission or Siri flow
  was exercised.
- Track Study is a new iOS 17+ music practice app. Its file import, local audio
  playback/seeking, and persistent practice marker flow compiled for a generic
  iOS Simulator destination with Xcode 26.0.1 on 2026-11-22. The Music
  Understanding adapter is guarded by SDK/OS availability. It has not been
  compiled with the installed Xcode 27.2 SDK because first-use setup is pending.
  App UI and audio behavior have not been exercised
  in a simulator or on a phone.
- Track Study now saves named A/B practice loops with tracks, supports marking
  start and end from the current playhead, and repeats the passage during
  playback. Existing track records decode without a loops field. The updated
  target compiled with Xcode 26.0.1 for arm64 and x86_64; playback and loop
  boundary behavior remain unexercised at runtime. Its iOS 27 Music
  Understanding adapter is gated to Swift 6.4 / Xcode 27 and remains uncompiled
  against the installed SDK pending first-use setup.
- Track Study now provides a Siri/Shortcuts action to mark the current
  playhead on an imported track. The action adds a named marker without
  starting recording or playback. The Xcode 26.0.1 Simulator build succeeded
  for arm64 and x86_64 with bundle ID `com.isaiahdupree.trackstudy`; generated
  App Intents metadata contains the marker action and Siri phrases. Runtime
  behavior has not been exercised.
- Track Study's iOS 27 Music Understanding adapter requests all six documented
  analysis types: rhythm, key, structure, pace, instrument activity, and
  loudness. It saves instrument ranges and integrated/peak loudness with the
  practice analysis. Pace windows show Apple's perceived events-per-minute
  measure separately from BPM, and section, key, pace, and first instrument
  detections can jump to their start time. This path is compile-gated to Swift
  6.4 / Xcode 27; the last verified Xcode 26 build covers only stable playback
  and practice features. The iOS 27 API and outputs remain uncompiled and
  unreviewed on a supported runtime.
- After that adapter change, the full Track Study app target rebuilt with
  Xcode 26.0.1 for the generic iOS Simulator destination. The arm64 and x86_64
  app slices and bundle ID `com.isaiahdupree.trackstudy` were confirmed. This
  verifies the stable app and fallback path only; no tests or device installs
  were run, and the Xcode 27 analyzer branch remains uncompiled.
- Track Study's music map makes detected section, key, pace, and first instrument
  detections actionable: selecting a span seeks the local player to its start.
  The iOS 27 analyzer branch still needs compilation and supported-runtime
  review.
- On 2026-11-23, Track Study gained a user-initiated text export of its title,
  practice markers, A/B ranges, and available analysis. The export never
  includes the audio file. XcodeGen added the formatter to the app target and
  `git diff --check` passed. A generic Simulator build stopped before
  compilation because Xcode 27.2 requires its license to be reviewed and
  accepted; no tests or device installs were run.
- Track Study now offers 0.5×, 0.75×, 0.9×, and 1× playback speed with
  AVPlayer's spectral pitch algorithm for slower practice. The selected rate is
  saved locally and applied to the active item and future playback. The source
  and roadmap were updated on 2026-11-23; Xcode 27.2 first-use setup still
  blocks a new SDK build, and no runtime audio review was performed.
- On 2026-11-23, Clear Record gained a combined text export for the saved
  transcript and summary. It labels a summary as stale when its source
  transcript changed and never includes the audio file. XcodeGen added the
  formatter to the app target and `git diff --check` passed. Xcode 27.2
  compilation remains blocked by its first-use license gate; no tests or
  device installs were run.
- Screenshot Scout now offers the same optional, review-before-save iOS 27
  scene description for one selected video frame at a time. The frame is the
  model input; full video analysis is not claimed. Saved descriptions are
  searchable and included only in the explicit detailed JSON export option.
  The Foundation Models path remains compile-gated to Xcode 27 and has not
  been compiled or exercised on a supported runtime.
- After this change, Screenshot Scout built with Xcode 26.0.1 for the generic
  iOS Simulator destination, with arm64 and x86_64 slices and bundle ID
  `com.isaiahdupree.ScreenshotScout`. This confirms the stable UI, storage,
  search, and fallback paths. No tests or device installs were run; the iOS 27
  Foundation Models path remains uncompiled.
- Clear Record rebuilt with Xcode 26.0.1 for the generic iOS Simulator
  destination, with arm64 and x86_64 slices and bundle ID
  `com.isaiahdupree.MeetingNotes`. This verifies the recorder, local Speech
  path, shortcut, and fallback build only; no tests or device installs were
  run, and the Foundation Models summary path remains uncompiled.
- Sonance EQ and its AUv3 extension rebuilt with Xcode 26.0.1 for the generic
  iOS Simulator destination. The app bundle IDs are
  `com.isaiahdupree.SonanceEQ.iOSPrototype` and
  `com.isaiahdupree.SonanceEQ.iOSPrototype.AudioUnit`; both binaries contain
  arm64 and x86_64 slices. This confirms the local-player and extension build,
  not the separate iOS 27 Media Device route. No tests or device installs were
  run.
- These are local build results. No simulator interaction, phone installation,
  or iPhone deployment was performed in this step.
- EverReach now has an optional Foundation Models note-drafting source path
  gated on iOS 27 and model availability. It passes only OCR text to the local
  model and leaves the output editable before saving. The Mac's Xcode 26 / iOS
  26 SDK compiles only the fallback; the new path has not been compiled or
  exercised. After CocoaPods regenerated the local module source list, the
  EverReach Simulator build succeeded again with arm64 and x86_64 slices and
  bundle ID `com.everreach.app`.
- EverReach's native App Shortcuts now include an authenticated People search
  that accepts a contact name and opens the filtered app screen; it does not
  return contact notes through Siri. The contact name is not included in search
  analytics, and People-screen debug logging no longer prints contact records.
  The new App Intent and deep-link behavior remain uncompiled and unreviewed at
  runtime because Xcode 27.2 first-use setup is pending.
- Screenshot Scout now has a local-storage review screen that measures indexed
  private image/video/frame copies, sorts by size, and requires explicit
  confirmation before removing one. It refreshes when the library changes and
  cancels superseded size scans. It does not delete the Photos original.
  XcodeGen regenerated all four local utility projects from their tracked
  specs, and the new file appears in the Screenshot Scout target;
  `git diff --check` passed. Native compilation is still stopped by Xcode's
  first-use license gate, so the screen has not been compiled or exercised.

## Implemented

- Local mono/stereo audio file playback with a parametric equalizer, bypass,
  built-in presets, an editable curve and saved/imported/exported presets.
- An AUv3 effect and editor for compatible host apps, with independent host
  settings and speech listening presets.
- Editable speech curves in the standalone player and in the host editor,
  output correction for the standalone player, and an in-app getting-started guide.

## Checks on 2026-11-21

- The iPhone app and iOS test bundles compiled with Xcode 26.0.1 for arm64;
  this is a test build, not a signed distribution artifact.
- `bash iOS/Tools/verify-speech-listening.sh` ran the actual preset filters on
  the Mac using Accelerate and passed. This does not establish listening quality.
- The repository's pre-commit Mac test suite passed against the existing Mac
  app. It does not exercise the new iOS user interface or route.
- The iPhone-specific tests compiled but have not run. The simulator service
  did not respond. A separately provisioned Mac iPhone-app test destination
  installed the signed test app, but macOS displayed an app-damaged alert and
  did not open it. Do not treat either attempt as a test pass.
- Sarah's designated iPhone was unavailable. No physical-device or route test
  was performed in this session.

## Remaining acceptance work

1. Build and sign on the appropriate iOS SDK and run the iOS unit and UI tests.
2. Test playback, speech curves, persistence, the AUv3 host, interruptions,
   headphones and background behavior on Sarah's designated iPhone. Preserve
   evidence, then uninstall the exact test bundle and verify its absence.
3. Before distributing the Media Device route, obtain Apple's entitlement and
   a matching profile for the minimal `Sonance EQ Route` installer and its
   extension. This installer-only bundle is separate from the full AUv3 host
   and carries no App Group entitlement. Physical route and Bluetooth tests
   remain required. The debug-only Route Lab still has unauthenticated
   transport and privacy issues; it is not the product route implementation.
   See [ROUTING-EXPERIMENT.md](ROUTING-EXPERIMENT.md).
4. Complete distribution signing, icon and release review separately when
   the product and its compatibility claims have been verified.

Additional concepts are listed in [APP-IDEAS.md](APP-IDEAS.md).

## Local utility builds

Run `./build-utilities.sh` from the `iOS/` directory to build Sonance EQ,
Screenshot Scout, Track Study, and Clear Record sequentially for the generic
iOS Simulator destination with code signing disabled. The script uses bounded
local build concurrency and writes DerivedData under `/tmp` by default. It
does not run tests, launch a simulator, install to a device, or publish an app.
EverReach remains in its separate repository and is built there independently.
## CarPlay reconnect recovery — 2026-11-25

- The standalone Sonance file player now recognizes CarPlay as a reconnectable
  output. If that exact route disappears, playback parks at its current
  position and resumes only when the same CarPlay output identity returns.
  It will not resume onto the iPhone speaker or a different available route.
- An intentional user pause remains paused. The focused playback recovery suite
  passes 5/5 on the iOS 26 iPad Pro simulator, including same-CarPlay identity acceptance,
  different-route rejection, Bluetooth identity acceptance and empty-ID rejection.
- This covers the in-app file player. It cannot make SoundCloud accept the
  separate EffectDeck Audio system route; that source's rejection still requires
  direct CarPlay playback or a compatible player/local file for EQ.
- Physical CarPlay reconnect and route-bounce behavior remain unverified because
  the target iPhone 15 is currently unavailable to Xcode.
