# Sonance EQ for iPhone — build status

This branch is a development prototype. It is not a finished, distribution-ready
iOS 27 cross-app product and has not been submitted or published.

## Utility portfolio progress — 2026-11-22

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
  Understanding adapter is guarded by SDK/OS availability and is not compiled
  by this Mac's iOS 26 SDK. App UI and audio behavior have not been exercised
  in a simulator or on a phone.
- Track Study now saves named A/B practice loops with tracks, supports marking
  start and end from the current playhead, and repeats the passage during
  playback. Existing track records decode without a loops field. The updated
  target compiled with Xcode 26.0.1 for arm64 and x86_64; playback and loop
  boundary behavior remain unexercised at runtime. Its iOS 27 Music
  Understanding adapter is gated to Swift 6.4 / Xcode 27 and is not compiled
  by the installed SDK.
- Track Study now provides a Siri/Shortcuts action to mark the current
  playhead on an imported track. The action adds a named marker without
  starting recording or playback. The Xcode 26.0.1 Simulator build succeeded
  for arm64 and x86_64 with bundle ID `com.isaiahdupree.trackstudy`; generated
  App Intents metadata contains the marker action and Siri phrases. Runtime
  behavior has not been exercised.
- Track Study's iOS 27 Music Understanding adapter now requests all six
  documented analysis types: rhythm, key, structure, pace, instrument activity,
  and loudness. It saves instrument ranges and integrated/peak loudness with
  existing practice analysis, and the view presents those results. This path is
  compile-gated to Swift 6.4 / Xcode 27; the current Xcode 26 build can only
  verify the stable playback and practice fallback. The iOS 27 API and outputs
  remain uncompiled and unreviewed on a supported runtime.
- After that adapter change, the full Track Study app target rebuilt with
  Xcode 26.0.1 for the generic iOS Simulator destination. The arm64 and x86_64
  app slices and bundle ID `com.isaiahdupree.trackstudy` were confirmed. This
  verifies the stable app and fallback path only; no tests or device installs
  were run, and the Xcode 27 analyzer branch remains uncompiled.
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
- These are local build results. No simulator interaction, phone installation,
  or iPhone deployment was performed in this step.
- EverReach now has an optional Foundation Models note-drafting source path
  gated on iOS 27 and model availability. It passes only OCR text to the local
  model and leaves the output editable before saving. The Mac's Xcode 26 / iOS
  26 SDK compiles only the fallback; the new path has not been compiled or
  exercised. After CocoaPods regenerated the local module source list, the
  EverReach Simulator build succeeded again with arm64 and x86_64 slices and
  bundle ID `com.everreach.app`.

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
