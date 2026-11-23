# Sonance EQ for iPhone — build status

This branch is a development prototype. It is not a finished, distribution-ready
iOS 27 cross-app product and has not been submitted or published.

## Utility portfolio progress — 2026-11-22

- Sonance's Files player now offers 15, 30, 45, 60, and 90 minute stop timers.
  The Sonance iOS app and AUv3 target compiled for the iOS Simulator with
  Xcode 26.0.1. The timer has not been exercised at runtime.
- Screenshot Scout is a separate iOS 17 app target in
  `Utilities/ScreenshotScout/`. It imports only images selected through
  PhotosUI, runs Vision OCR and image classification on-device, searches the
  local index, skips byte-identical reimports, and stores resized JPEG copies
  in its app container. It also ranks closest indexed images through Vision
  feature prints for manual review, with a cancel control and no auto deletion.
  Its iOS Simulator build succeeded with Xcode 26.0.1.
- Clear Record is a second iOS 17 app target in `Utilities/MeetingNotes/`.
  It requires an explicit consent confirmation, records in the foreground,
  saves on an interruption or background transition, and asks Speech for
  on-device English transcription only. Its iOS Simulator build succeeded with
  Xcode 26.0.1; microphone behavior and transcription have not been exercised
  at runtime.
- These are local build results. No simulator interaction, phone installation,
  or iPhone deployment was performed in this step.

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
3. Implement and validate an iOS 27 Media Device route if appropriate. Confirm
   the applicable Apple terms, entitlement configuration and review position.
   The separate debug-only Route Lab contains unverified experimental source
   but is not integrated. Resolve its peer authentication and privacy issues.
   Capture the results in [ROUTING-EXPERIMENT.md](ROUTING-EXPERIMENT.md).
4. Complete distribution signing, icon and release review separately when
   the product and its compatibility claims have been verified.

Additional concepts are listed in [APP-IDEAS.md](APP-IDEAS.md).
