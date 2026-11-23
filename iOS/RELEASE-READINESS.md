# Sonance EQ for iPhone — build status

This branch is a development prototype. It is not a finished, distribution-ready
iOS 27 cross-app product and has not been submitted or published.

Xcode 27.2 was installed on this Mac on 2026-11-22. Its first-use license has
not been accepted, so SDK discovery and new builds are currently blocked. Build
results below are historical Xcode 26.0.1 Simulator evidence until the license
is reviewed and accepted and the apps are rebuilt.

## Utility portfolio progress — 2026-11-23

- Sonance's headphone profile assistant now displays a read-only preview of the
  generated frequency response and suggested preamp before saving or applying
  the curve. It remains a preference-based starting point, not a measured
  headphone correction.
- Sonance EQ's A/B comparison now has separate temporary output trims for the
  reference and edited curves. Each can be attenuated by up to 12 dB at the
  player output stage; changing the edited curve, audio file, or workspace
  clears its trim, and no trim is written to the settings file or presets.
  VoiceOver labels and describes each control. `git diff --check` and XcodeGen
  project generation passed;
  Xcode compilation remains blocked by its unaccepted first-use license, and
  listening behavior has not been validated on a device.
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
- Sonance EQ's A/B controls now give VoiceOver explicit reference/edited labels,
  selection values, and audition hints. The comparison also discloses that A and
  B retain their saved preamp levels instead of claiming a loudness match.
  `git diff --check` passed; native compilation and listening-level review remain
  open because Xcode's first-use license is pending and iPhone testing is out of scope.

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
3. Do not integrate the iOS 27 Media Device Route Lab into Sonance EQ without
   written Apple guidance that covers same-device processing and the purpose of
   the containing app. Apple's public docs describe remote playback hardware,
   and the current agreement says the app bundling the extension should exist
   solely to deliver and install it. The separate debug-only Route Lab also has
   unauthenticated transport and privacy issues; it is not a product candidate.
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
