# iOS utility app roadmap

Updated 2026-11-22. This is a build roadmap for locally built apps and prototypes. It does not authorize installation on a phone, release, publication, deployment, or cloud builds.

## Platform baseline

- Apple's newest public iPhone release is iOS 27.2.1 (November 9, 2026); the newest beta listed is iOS 27.3 beta 2 v2 (November 19, 2026). Xcode 27.2 is publicly listed, but this Mac currently has Xcode 26.0.1 and the iOS 26 SDK. iOS 27-only frameworks cannot be compiled or validated here until a newer SDK is installed. Do not describe an iOS 27 capability as implemented based on a web page or a Mac-only API experiment.
- Vision already provides local OCR, image categorization, visual similarity, and video analysis on earlier supported iOS versions. The Screenshot Scout app uses the system photo picker and Vision; selected image bytes and extracted metadata stay in its app container.
- iOS 27 Foundation Models adds on-device language and multimodal image understanding on supported devices. Use it as an optional enhancement after building with Xcode 27 and handling model/device availability. A share sheet remains the explicit boundary for screenshots and conversations; the app does not read other apps' private data.
- Music Understanding analyzes an audio asset supplied by the user or app. Start with files the user chooses. Do not promise access to protected streaming catalog audio.
- Media Device and AVSystemRouting require iOS 27. They make a selected playback device available through system routing. Apple's docs describe activated output devices and media apps that support the protocol; they do not establish unrestricted same-phone capture from every app. Entitlement, terms, device operation, and app-by-app compatibility remain separate gates.

## Ordered product work

| Order | App / product | Form | Build boundary and next milestone |
|---|---|---|---|
| 1 | Sonance EQ for iPhone | Standalone app plus AUv3 | Existing prototype plays user-selected files with parametric EQ, presets, A/B, live meters, output correction, and speech modes. Keep improving this on stable APIs. Treat cross-app route support as an isolated iOS 27 experiment until Apple requirements and a working entitlement are resolved. |
| 2 | Screenshot Scout / Creator Library | Standalone utility | Index user-selected images and videos with local OCR, Vision labels, exact duplicate detection, cancellable visual-similarity ranking for images, search across five sampled video frames, and user-controlled JSON inventory export. Next: library-scale performance and scene search refinements. |
| 3 | EverReach Capture | Feature in EverReach | Share-in screenshot flow runs local Vision OCR, suggests a unique visible contact, previews an editable note, saves only after review, optionally attaches the image, and drafts a follow-up as a separate action. An optional Foundation Models note drafting path now consumes OCR text only and remains editable; source is gated by SDK, iOS 27, and model availability. The Xcode 26.0.1 / iOS 26 simulator build compiles the fallback only. Runtime behavior and the iOS 27 path remain unverified. |
| 4 | Sonance Voice and Headphone Profiles | Sonance EQ modes | Keep dialogue, podcast, audiobook, headphone, sleep, focus, speaker, and A/B profiles within the EQ product while they use the same playback and DSP engine. A 15–90 minute sleep timer is now part of the player prototype. Split only if customer evidence supports a distinct app. |
| 5 | Track Study (music practice) | Standalone app | Locally buildable iOS 17+ app imports one user-selected audio file, stores it privately, supports playback/seeking, and saves named practice markers. A compiler-gated Music Understanding path requests rhythm, key, structure, and pace on iOS 27, but cannot be compiled with the Xcode 26 SDK currently installed here. |
| 6 | Creator Library workflows | Screenshot Scout expansion | User-selected video copies, five-frame sampling, OCR and scene labels, similarity review, and JSON inventory export now build locally. Next: library-scale performance, scene search refinements, and a reviewed candidate queue. Similarity suggests candidates; deletion remains an explicit user choice. |
| 7 | Clear Record (Meeting Notes) | Standalone local utility | iOS 17 prototype records after explicit consent, stores audio and notes locally, stops on interruption/background, lists system-supported on-device speech locales, and lets the user correct transcripts. Next: simulator/device behavior and locale review on supported hardware; do not promise call capture, arbitrary background recording, summaries, or network transcription. |

## Product boundaries

The named products above are intentionally fewer than the idea list: Voice, headphone tuning, sleep, focus, speaker tuning, and A/B comparison share Sonance's DSP and profiles; screenshot organization and creator media cleanup share one user-selected media index; contact capture belongs in EverReach. This keeps separate apps for distinct jobs and keeps related controls together.

## Build sequence

1. Keep Sonance EQ as the first product and continue its standalone file-player and AUv3 experience.
2. Continue Screenshot Scout on stable PhotosUI and Vision APIs; refine search and indexing for larger libraries.
3. Continue Clear Record on stable speech/audio APIs; validate dynamic locale support and review behavior on-device when permitted.
4. Continue EverReach capture with local build checks. Compile and validate its Foundation Models path once an iOS 27 SDK is available; runtime and output review remain pending.
5. Build Track Study's file practice flow on current SDKs; compile and validate the Music Understanding analyzer when a newer local SDK is available.
6. Revisit Media Device only after official entitlement/terms review and a signed route prototype can be validated. Physical iPhone installation is outside the current goal.

## Evidence

- [Apple iOS releases](https://developer.apple.com/news/releases/)
- [iOS 27 release notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes)
- [Foundation Models](https://developer.apple.com/documentation/foundationmodels)
- [Vision](https://developer.apple.com/documentation/vision)
- [Music Understanding](https://developer.apple.com/documentation/musicunderstanding)
- [Media Device](https://developer.apple.com/documentation/MediaDevice)
- [Routing and streaming media](https://developer.apple.com/documentation/avsystemrouting/routing-and-streaming-media-to-remote-devices)
