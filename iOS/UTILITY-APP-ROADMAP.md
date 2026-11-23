# iOS utility app roadmap

Updated 2026-11-22. This is a build roadmap for locally built apps and prototypes. It does not authorize installation on a phone, release, publication, deployment, or cloud builds.

## Platform baseline

- Apple's newest public iPhone release is iOS 27.2.1 (November 9, 2026); the newest beta listed is iOS 27.3 beta 2 v2 (November 19, 2026). Xcode 27.2 is the latest stable release listed and Xcode 27.3 beta 2 is listed November 16. Xcode 27 includes Swift 6.4 and the iOS 27 SDK. This Mac currently has Xcode 26.0.1 and the iOS 26 SDK. iOS 27-only frameworks cannot be compiled or validated here until a newer SDK is installed. Do not describe an iOS 27 capability as implemented based on a web page or a Mac-only API experiment.
- Vision already provides local OCR, image categorization, visual similarity, and video analysis on earlier supported iOS versions. The Screenshot Scout app uses the system photo picker and Vision; selected image bytes and extracted metadata stay in its app container.
- iOS 27 Foundation Models supports image attachments in prompts. The model must be available and support image input; use the user's selected local image and keep generated descriptions reviewable. Apple documents no built-in video input, so video analysis remains frame-based. A share sheet remains the explicit boundary for screenshots and conversations; the app does not read other apps' private data.
- Music Understanding analyzes an audio asset supplied by the user or app, on-device, across rhythm, key, structure, pace, instrument activity, and loudness. Apple currently marks the framework documentation as beta. Start with files the user chooses; do not promise access to protected streaming catalog audio.
- Media Device and AVSystemRouting require iOS 27. They make a selected playback device available through system routing. Apple's docs describe activated output devices and media apps that support the protocol; they do not establish unrestricted same-phone capture from every app. Entitlement, terms, device operation, and app-by-app compatibility remain separate gates.

## Ordered product work

| Order | App / product | Form | Build boundary and next milestone |
|---|---|---|---|
| 1 | Sonance EQ for iPhone | Standalone app plus AUv3 | Existing prototype plays user-selected files with parametric EQ, presets, A/B, live meters, output correction, speech modes, and Siri/Shortcuts actions to enable or disable bypass. Keep improving this on stable APIs. Treat cross-app route support as an isolated iOS 27 experiment until Apple requirements and a working entitlement are resolved. |
| 2 | Screenshot Scout / Creator Library | Standalone utility | Index user-selected images and videos with local OCR, Vision labels, exact duplicate detection, cancellable visual-similarity ranking for images, search across five sampled video frames, user-controlled JSON inventory export, and a persistent review queue. Optional iOS 27 Foundation Models descriptions cover an image or one sampled video frame at a time and require review before saving. Compile the new model paths with Xcode 27 and review them on a supported runtime. |
| 3 | EverReach Capture | Feature in EverReach | Share-in screenshot flow runs local Vision OCR, suggests a unique visible contact, previews an editable note, saves only after review, optionally attaches the image, and drafts a follow-up as a separate action. An optional Foundation Models note drafting path now consumes OCR text only and remains editable; source is gated by SDK, iOS 27, and model availability. The Xcode 26.0.1 / iOS 26 simulator build compiles the fallback only. Runtime behavior and the iOS 27 path remain unverified. |
| 4 | Sonance Voice and Headphone Profiles | Sonance EQ modes | Keep dialogue, podcast, audiobook, headphone, sleep, focus, speaker, and A/B profiles within the EQ product while they use the same playback and DSP engine. A 15–90 minute sleep timer is now part of the player prototype. Split only if customer evidence supports a distinct app. |
| 5 | Track Study (music practice) | Standalone app | Locally buildable iOS 17+ app imports one user-selected audio file, stores it privately, supports playback/seeking, and saves named practice markers and A/B repeat loops. Siri/Shortcuts can mark the current playhead. A Swift 6.4/Xcode 27 and iOS 27-gated Music Understanding path requests all six documented dimensions: rhythm, key, structure, pace, instrument activity, and loudness. Compile and review this beta API before relying on its results. |
| 6 | Clear Record (Meeting Notes) | Standalone local utility | iOS 17 prototype records after explicit consent, stores audio and notes locally, stops on interruption/background, lists system-supported on-device speech locales, and lets the user correct transcripts. Siri/Shortcuts can transcribe the newest saved recording using existing on-device Speech checks. An optional iOS 27 Foundation Models path drafts reviewable meeting notes from the saved transcript; the Xcode 26 build compiles only its fallback. Next: compile with Xcode 27 and review outputs on supported hardware; do not promise call capture, arbitrary background recording, or network transcription. |

## Product boundaries

The named products above are intentionally fewer than the idea list: Voice, headphone tuning, sleep, focus, speaker tuning, and A/B comparison share Sonance's DSP and profiles; screenshot organization and creator media cleanup share one user-selected media index; contact capture belongs in EverReach. This keeps separate apps for distinct jobs and keeps related controls together.

## Build sequence

1. Keep Sonance EQ as the first product and continue its standalone file-player and AUv3 experience.
2. Continue Screenshot Scout on stable PhotosUI and Vision APIs; compile its gated iOS 27 image-description path with Xcode 27 when available, then refine search and indexing for larger libraries. The persistent user-reviewed candidate queue is implemented locally.
3. Clear Record now has an optional transcript-to-notes Foundation Models path. Compile it with Xcode 27 when available, review its summaries and stale-transcript handling, and validate dynamic locale support and recording behavior on-device when permitted.
4. Continue EverReach capture with local build checks. Compile and validate its Foundation Models path once an iOS 27 SDK is available; runtime and output review remain pending.
5. Track Study now has saved A/B loops that repeat a selected passage. Compile the optional Music Understanding analyzer with Xcode 27 when a newer local SDK is available; then review its beta API outputs before adding them to the core workflow.
6. Revisit Media Device only after official entitlement/terms review and a signed route prototype can be validated. Physical iPhone installation is outside the current goal.

## Evidence

- [Apple iOS releases](https://developer.apple.com/news/releases/)
- [iOS 27 release notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes)
- [Xcode 27 release notes](https://developer.apple.com/documentation/Xcode-Release-Notes/xcode-27-release-notes)
- [Foundation Models](https://developer.apple.com/documentation/foundationmodels)
- [Foundation Models image attachments](https://developer.apple.com/documentation/foundationmodels/analyzing-images-with-multimodal-prompting)
- [Foundation Models image capability](https://developer.apple.com/documentation/foundationmodels/languagemodelcapabilities/capability/vision)
- [Foundation Models text generation](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models)
- [App Intents and App Shortcuts](https://developer.apple.com/documentation/appintents/getting-started-with-the-app-intents-framework)
- [App Intent supported modes](https://developer.apple.com/documentation/appintents/appintent/supportedmodes)
- [Vision](https://developer.apple.com/documentation/vision)
- [Music Understanding](https://developer.apple.com/documentation/musicunderstanding)
- [Music Understanding WWDC26 overview](https://developer.apple.com/videos/play/wwdc2026/253/)
- [Media Device](https://developer.apple.com/documentation/MediaDevice)
- [Routing and streaming media](https://developer.apple.com/documentation/avsystemrouting/routing-and-streaming-media-to-remote-devices)
