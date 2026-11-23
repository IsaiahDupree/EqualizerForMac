# iOS utility app roadmap

Updated 2026-11-22. This is a build roadmap for locally built apps and prototypes. It does not authorize installation on a phone, release, publication, deployment, or cloud builds.

## Platform baseline

- Apple's newest public iPhone release is iOS 27.2.1 (November 9, 2026). The newest beta listed is iOS 27.3 beta 2 v2 (November 19, 2026).
- This Mac currently has Xcode 26.0.1 and the iOS 26 SDK. iOS 27-only frameworks cannot be compiled or validated here until an iOS 27 SDK is installed. Do not describe an iOS 27 capability as implemented based on a web page or a Mac-only API experiment.
- Vision already provides local OCR, image categorization, visual similarity, and video analysis on earlier supported iOS versions. The Screenshot Scout app uses the system photo picker and Vision; selected image bytes and extracted metadata stay in its app container.
- iOS 27 Foundation Models adds on-device language and multimodal image understanding on supported devices. Use it as an optional enhancement after building with Xcode 27 and handling model/device availability. A share sheet remains the explicit boundary for screenshots and conversations; the app does not read other apps' private data.
- Music Understanding analyzes an audio asset supplied by the user or app. Start with files the user chooses. Do not promise access to protected streaming catalog audio.
- Media Device and AVSystemRouting require iOS 27. They make a selected playback device available through system routing. Apple's docs describe activated output devices and media apps that support the protocol; they do not establish unrestricted same-phone capture from every app. Entitlement, terms, device operation, and app-by-app compatibility remain separate gates.

## Ordered product work

| Order | App / product | Form | Build boundary and next milestone |
|---|---|---|---|
| 1 | Sonance EQ for iPhone | Standalone app plus AUv3 | Existing prototype plays user-selected files with parametric EQ, presets, A/B, live meters, output correction, and speech modes. Keep improving this on stable APIs. Treat cross-app route support as an isolated iOS 27 experiment until Apple requirements and a working entitlement are resolved. |
| 2 | Screenshot Scout / Creator Library | Standalone utility | Index user-selected images and videos with local OCR, Vision labels, exact duplicate detection, cancellable visual-similarity ranking for images, and search across five sampled video frames. Next: library-scale performance, scene search refinements, and inventory export. |
| 3 | EverReach Capture | Feature in EverReach | Evolve the existing share-in screenshot and voice-note flows: extract visible text, suggest a contact and note, show a preview, then let the user save and draft a follow-up. Foundation Models can improve interpretation when the iOS 27 SDK and device are available. |
| 4 | Sonance Voice and Headphone Profiles | Sonance EQ modes | Keep dialogue, podcast, audiobook, headphone, sleep, focus, speaker, and A/B profiles within the EQ product while they use the same playback and DSP engine. A 15–90 minute sleep timer is now part of the player prototype. Split only if customer evidence supports a distinct app. |
| 5 | Music practice and discovery | New app candidate | Prototype file-based tempo, key, loudness, pace, and structure analysis with Music Understanding after the iOS 27 SDK is installed. Keep the file importer and library UX separate from protected subscription streams. |
| 6 | Creator Library Assistant | Screenshot Scout expansion | User-selected video copies, five-frame sampling, OCR and scene labels now build locally. Next: library-scale performance, a review queue, and exportable inventory. Similarity suggests candidates; deletion remains an explicit user choice. |
| 7 | Clear Record (Meeting Notes) | Standalone local utility | iOS 17 prototype now records after an explicit consent confirmation, stores audio and notes locally, stops on interruption/background, and asks Speech for on-device English transcription only. Next: simulator/device behavior and supported-locale review; do not promise call capture, arbitrary background recording, summaries, or network transcription. |

## Product boundaries

The named products above are intentionally fewer than the idea list: Voice, headphone tuning, sleep, focus, speaker tuning, and A/B comparison share Sonance's DSP and profiles; screenshot organization and creator media cleanup share one user-selected media index; contact capture belongs in EverReach. This keeps separate apps for distinct jobs and keeps related controls together.

## Build sequence

1. Keep Sonance EQ as the first product and continue its standalone file-player and AUv3 experience.
2. Build Screenshot Scout as a separate local iOS target with stable PhotosUI and Vision APIs; refine the image/video index for larger libraries and add inventory export.
3. Build Clear Record on stable speech/audio APIs and refine locale support and review controls.
4. Audit the canonical EverReach iOS app and implement its share-in capture flow in that codebase.
5. When Xcode 27 is available locally, add isolated Foundation Models and Music Understanding prototypes with feature-availability handling.
6. Revisit Media Device only after official entitlement/terms review and a signed route prototype can be validated. Physical iPhone installation is outside the current goal.

## Evidence

- [Apple iOS releases](https://developer.apple.com/news/releases/)
- [iOS 27 release notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes)
- [Foundation Models](https://developer.apple.com/documentation/foundationmodels)
- [Vision](https://developer.apple.com/documentation/vision)
- [Music Understanding](https://developer.apple.com/documentation/musicunderstanding)
- [Media Device](https://developer.apple.com/documentation/MediaDevice)
- [Routing and streaming media](https://developer.apple.com/documentation/avsystemrouting/routing-and-streaming-media-to-remote-devices)
