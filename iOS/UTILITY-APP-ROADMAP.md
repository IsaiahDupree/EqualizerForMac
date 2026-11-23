# iOS utility app roadmap

Updated 2026-11-23. Apple's release page was rechecked today: iOS 27.2.1 remains the newest public release, iOS 27.3 beta 2 v2 remains the newest listed beta, and Xcode 27.2 is the newest stable Xcode. This is a build roadmap for locally built apps and prototypes. It does not authorize installation on a phone, release, publication, deployment, or cloud builds.

## Portfolio goal

Build the focused utility apps and app features below into complete, locally
buildable iPhone apps or app features, then keep a ranked list of adjacent apps
to build.
Each product needs its core workflow, local data handling, honest capability
gates, a repeatable Mac build command, and a status record. Do not install to an
iPhone, publish, deploy, or trigger a cloud build as part of this goal. The
existing active Codex goal tracks this work.

Completion means every product has a usable core flow, a local build that
compiles against its intended SDK gates, documented setup and privacy behavior,
and an ordered next-step list. Runtime validation that requires an iPhone stays
out of scope; report it as a separate open item.

## Platform baseline

- Apple's newest public iPhone release is iOS 27.2.1 (November 9, 2026); the newest beta listed is iOS 27.3 beta 2 v2 (November 19, 2026). Xcode 27.2 is the latest stable release and Xcode 27.3 beta 2 is the latest Xcode beta listed (November 16). Xcode 27.2 includes Swift 6.4 and the iOS 27.2 SDK and requires macOS 26.6 or later; this Mac is running macOS 26.6.1. Xcode 27.2 is installed here, replacing Xcode 26.0.1. Its first-use license has not been accepted, so `xcodebuild -showsdks` currently stops before exposing the SDK list. iOS 27-only compile verification remains pending that setup step. Do not describe an iOS 27 capability as implemented based on a web page or a Mac-only API experiment.
- Vision already provides local OCR, image categorization, visual similarity, and video analysis on earlier supported iOS versions. The Screenshot Scout app uses the system photo picker and Vision; selected image bytes and extracted metadata stay in its app container.
- iOS 27 Foundation Models supports image attachments in prompts. The model must be available and support image input; use the user's selected local image and keep generated descriptions reviewable. Apple documents no built-in video input, so video analysis remains frame-based. User-selected pickers or a system share action are the boundary for screenshots and conversations; EverReach's Share extension now accepts one shared image into a local App Group inbox, and the app waits for the user to open and review it.
- Music Understanding analyzes an audio asset supplied by the user or app, on-device, across rhythm, key, structure, pace, instrument activity, and loudness. Apple currently marks the framework documentation as beta. Start with files the user chooses; do not promise access to protected streaming catalog audio.
- Media Device and AVSystemRouting require iOS 27. They make a selected playback device available through system routing. Apple's docs describe activated output devices and media apps that support the protocol; they do not establish unrestricted same-phone capture from every app. Entitlement, terms, device operation, and app-by-app compatibility remain separate gates.

## Ordered product work

| Order | App / product | Form | Build boundary and next milestone |
|---|---|---|---|
| 1 | Sonance EQ for iPhone | Standalone app plus AUv3 | Existing prototype plays user-selected files with parametric EQ, presets, A/B, live meters, output correction, speech modes, and Siri/Shortcuts actions to enable or disable bypass. A preference-guided headphone profile assistant creates editable curves, saves them to presets, and can apply a suggestion for A/B comparison. Keep improving this on stable APIs. Treat cross-app route support as an isolated iOS 27 experiment until Apple requirements and a working entitlement are resolved. |
| 2 | Screenshot Scout / Creator Library | Standalone utility | Index user-selected images and videos with local OCR, Vision labels, exact duplicate detection, cancellable visual-similarity ranking for images, search across five sampled video frames, user-controlled JSON inventory export, and a persistent review queue. Optional iOS 27 Foundation Models descriptions cover an image or one sampled video frame at a time and require review before saving. Compile the new model paths with Xcode 27 and review them on a supported runtime. |
| 3 | EverReach Capture | Feature in EverReach | The in-app picker and one-image Share extension both feed the screenshot review flow. The extension writes one pending image to a backup-excluded App Group inbox, then asks the user to open EverReach manually; the app routes to review after authentication and onboarding. Local Vision OCR, unique-name suggestions, editable notes, optional screenshot attachment, and separate follow-up drafting remain explicit user actions. A native App Shortcut also opens the route. The extension, App Group signing setup, iOS 27 model path, and runtime flow need build/device validation. |
| 4 | Sonance Voice and Headphone Profiles | Sonance EQ modes | Keep dialogue, podcast, audiobook, headphone, sleep, focus, speaker, and A/B profiles within the EQ product while they use the same playback and DSP engine. A listening-preference assistant now makes a moderate editable EQ starting point without claiming headphone measurement or model correction. A 15–90 minute sleep timer is part of the player prototype. Split only if customer evidence supports a distinct app. |
| 5 | Track Study (music practice) | Standalone app | Locally buildable iOS 17+ app imports one user-selected audio file, stores it in an app directory excluded from device backups, supports playback/seeking, and saves named practice markers and A/B repeat loops. A user-initiated share action exports a text practice plan without attaching audio. Music analysis can be canceled; removing the track or leaving the app discards stale results. When analysis is available, detected section, key, pace, and first instrument spans can jump the playhead to a practice point; pace is labeled as perceived events/minute, separately from BPM, and integrated/peak loudness are shown. Siri/Shortcuts can mark the current playhead. A Swift 6.4/Xcode 27 and iOS 27-gated Music Understanding path requests all six documented dimensions. Compile and review this beta API before relying on its results. |
| 6 | Clear Record (Meeting Notes) | Standalone local utility | iOS 17 prototype records after explicit consent, stores audio and notes locally, stops on interruption/background, lists system-supported on-device speech locales, and lets the user correct transcripts. Siri/Shortcuts can transcribe the newest saved recording using on-device Speech checks. The optional iOS 27 Foundation Models path now supports up to 120,000 transcript characters with local section summaries and successive consolidation, preserves transcript-to-summary provenance, and keeps summary actions unavailable during active edits. The Xcode 26 build compiles only its fallback. Next: compile with Xcode 27 and review long-transcript outputs on a supported runtime; do not promise call capture, arbitrary background recording, or network transcription. |

## Product boundaries

The named products above are intentionally fewer than the idea list: Voice, headphone tuning, sleep, focus, speaker tuning, and A/B comparison share Sonance's DSP and profiles; screenshot organization and creator media cleanup share one user-selected media index; contact capture belongs in EverReach. This keeps separate apps for distinct jobs and keeps related controls together.

## Build sequence

1. Keep Sonance EQ as the first product and continue its standalone file-player and AUv3 experience.
2. Continue Screenshot Scout on stable PhotosUI and Vision APIs; compile its gated iOS 27 image-description path with Xcode 27 when available, then refine search and indexing for larger libraries. The persistent user-reviewed candidate queue is implemented locally.
3. Clear Record supports long transcript summaries through local sectioning and multi-pass consolidation. Compile the iOS 27 path with Xcode 27 when available, review section boundary behavior and stale-transcript handling, and validate dynamic locale support and recording behavior on-device when permitted.
4. Continue EverReach capture with local build checks. Compile the Share extension, App Group entitlements, App Intents, and Foundation Models paths, then verify share handoff, deep-link delivery, and model output when a supported runtime is available; runtime and output review remain pending.
5. Track Study has saved A/B loops that repeat a selected passage, cancellable analysis, and backup-excluded audio and notes. Compile the optional Music Understanding analyzer with Xcode 27 when the installed SDK is usable; then review its beta API outputs before adding them to the core workflow.
6. Revisit Media Device only after official entitlement/terms review and a signed route prototype can be validated. Physical iPhone installation is outside the current goal.
7. Continue Sonance's guided headphone profile work on stable APIs; refine preset naming, accessibility, and comparison behavior before considering a standalone sound-profile app.

## Evidence

- [Apple iOS releases](https://developer.apple.com/news/releases/)
- [iOS 27 release notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes)
- [Xcode 27 release notes](https://developer.apple.com/documentation/Xcode-Release-Notes/xcode-27-release-notes)
- [Xcode 27.2 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27_2-release-notes)
- [Foundation Models](https://developer.apple.com/documentation/foundationmodels)
- [Foundation Models image attachments](https://developer.apple.com/documentation/foundationmodels/analyzing-images-with-multimodal-prompting)
- [Foundation Models image capability](https://developer.apple.com/documentation/foundationmodels/languagemodelcapabilities/capability/vision)
- [Foundation Models text generation](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models)
- [App Intents and App Shortcuts](https://developer.apple.com/documentation/appintents/getting-started-with-the-app-intents-framework)
- [App Intent supported modes](https://developer.apple.com/documentation/appintents/appintent/supportedmodes)
- [App Shortcuts provider](https://developer.apple.com/documentation/appintents/appshortcutsprovider)
- [Expo Router deep links](https://docs.expo.dev/router/basics/navigation/)
- [Vision](https://developer.apple.com/documentation/vision)
- [Music Understanding](https://developer.apple.com/documentation/musicunderstanding)
- [Music Understanding pace results](https://developer.apple.com/documentation/musicunderstanding/paceresult)
- [Music Understanding loudness results](https://developer.apple.com/documentation/musicunderstanding/loudnessresult)
- [Music Understanding WWDC26 overview](https://developer.apple.com/videos/play/wwdc2026/253/)
- [Media Device](https://developer.apple.com/documentation/MediaDevice)
- [Routing and streaming media](https://developer.apple.com/documentation/avsystemrouting/routing-and-streaming-media-to-remote-devices)
