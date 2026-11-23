# App ideas from the iOS 27 brief

These are concepts to evaluate, not claims of validated demand, available
APIs on every device, or committed standalone products. Sonance EQ is the
current implementation; its cross-app route is not yet implemented or verified.
Screenshot Scout is now the first separate utility prototype, using the stable
PhotosUI and Vision APIs. See [the portfolio roadmap](UTILITY-APP-ROADMAP.md)
for build order, current iOS SDK limits, and which ideas remain features inside
an existing app.

| Concept | Initial scope | What must be established |
| --- | --- | --- |
| Sonance Voice | Speech-oriented listening controls; start as Sonance EQ modes | Audible benefit, source and route compatibility, then a distinct audience before a separate app |
| Headphone profile assistant | Guided preference choices create a modest editable EQ curve that can be saved to presets and compared in Sonance | The current guide does not measure or identify headphones. Real headphone reference data, output identification, and automatic switching remain separate feasibility work. |
| Sonance Sleep | Gentle tone profiles and a user-controlled sleep timer, now represented by a 15–90 minute timer in the Sonance player | Verify timer behavior and route recovery across lock, interruption and output changes |
| Sonance Focus | Listening profiles for work and study | A distinct user need and reliable audio routing |
| Audio A/B tester | Compare two saved curves with easy level matching | Accurate level matching and seamless switching without clicks or misleading loudness differences |
| Portable speaker tuner | Editable speaker presets and speech-oriented tuning | Supported outputs and whether route-specific identity is stable |
| EverReach capture assistant | In-app screenshot/photo selection, local OCR on iOS, reviewable notes and follow-up drafts in EverReach; the system share-sheet extension remains unbuilt | Device/model availability, explicit source permissions, contact matching, user review and share-extension integration |
| Music practice companion | Analyze user-selected audio and organize practice material | Music Understanding outputs on supported devices and accessible file formats |
| Music library organizer | Sort user-supplied tracks by musical features | File permissions, framework coverage and accuracy; protected streams require separate verification |
| Creator library assistant | Screenshot Scout indexes selected images and videos, extracts OCR/labels from images and five sampled video frames, skips exact duplicates, ranks visually close images for manual review, exports a JSON inventory, and keeps a persistent user-reviewed queue. An optional iOS 27 Foundation Models path suggests reviewable descriptions for user-selected images and individual sampled video frames. | Compile the gated image-description paths with Xcode 27 and review them on a supported runtime; validate search and similarity on representative media; no automatic deletion |
| Meeting-note companion | Clear Record prototype: explicit consent confirmation, foreground recording, local storage, an on-device transcription shortcut, and an optional editable iOS 27 summary draft | Compile and review the Foundation Models path on Xcode 27; verify microphone and speech permission flows and locale/device coverage; no calls, arbitrary background recording, or automatic summaries are claimed |
| Siri utility actions | Sonance EQ exposes Siri/Shortcuts actions for EQ bypass, Track Study can mark the current practice playhead, and Clear Record can transcribe the latest saved recording without overwriting existing text | The current app builds include shortcut metadata; review runtime behavior and Siri/Spotlight availability on supported OS versions and devices |
| EverReach Siri actions | Find a contact's saved notes, open screenshot capture, or start a reviewable follow-up draft from a supported App Intent | Define privacy-safe action parameters and destinations, add the App Intents integration, and review supported Siri/Spotlight behavior on device |

See [ROUTING-EXPERIMENT.md](ROUTING-EXPERIMENT.md) for the Sonance route
prerequisites and the untested compatibility matrix. Nothing in this list
authorizes publication, metered cloud inference or access to private content
without the relevant user permission.
