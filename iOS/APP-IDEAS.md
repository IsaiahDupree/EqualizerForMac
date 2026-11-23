# App ideas from the iOS 27 brief

These are concepts to evaluate, not claims of validated demand, available
APIs on every device, or committed standalone products. Sonance EQ is the
current implementation. The proposed same-phone Media Device route remains
isolated: Apple's public documentation targets remote hardware, and the current
agreement says the app bundling the extension should exist solely to deliver
and install it.
Do not treat it as an approved cross-app EQ path without written Apple guidance.
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
| EverReach capture assistant | In-app screenshot/photo selection plus a one-image Share extension that stores a backup-excluded local capture and hands it to EverReach's review route after the user opens the app; local OCR, editable notes, up to five explicit contact-match suggestions, and separate follow-up drafts | Build/sign the extension and App Group, then review the manual handoff, contact matching, Foundation Models output and device behavior |
| Music practice companion | Track Study analyzes user-selected audio, organizes practice material, searches analyzed key, tempo, instrument and pace metadata, and slows passages while retaining pitch | Compile Music Understanding on Xcode 27, review result accuracy, and confirm source-file format coverage; protected streams remain outside the supported source boundary |
| Music library organizer | Included in Track Study as a private, searchable multi-track file library with title/date sorting, key/tempo sorting, and search across analyzed key, instrument, and pace metadata | Compile Music Understanding on Xcode 27 and review result accuracy; protected streams remain outside the supported source boundary |
| Creator library assistant | Screenshot Scout indexes selected images and videos, extracts OCR/labels from images and five sampled video frames, skips exact duplicates, ranks visually close images for manual review, exports a JSON inventory, and keeps a persistent user-reviewed queue. An optional iOS 27 Foundation Models path suggests reviewable descriptions for user-selected images and individual sampled video frames. | Compile the gated image-description paths with Xcode 27 and review them on a supported runtime; validate search and similarity on representative media; no automatic deletion |
| Meeting-note companion | Clear Record prototype: explicit consent confirmation, foreground recording, private local search across titles/transcripts/summaries, an on-device transcription shortcut, and an optional editable iOS 27 summary that processes up to 120,000 transcript characters in local sections | Compile and review the Foundation Models path on Xcode 27; verify section consolidation, microphone and speech permission flows, and locale/device coverage; no calls, arbitrary background recording, or automatic summaries are claimed |
| Siri utility actions | Sonance EQ exposes Siri/Shortcuts actions for EQ bypass, Track Study can mark the current practice playhead, and Clear Record can transcribe the latest saved recording without overwriting existing text | The current app builds include shortcut metadata; review runtime behavior and Siri/Spotlight availability on supported OS versions and devices |
| EverReach Siri actions | A native App Shortcut can open screenshot capture or prefill the authenticated People search for a contact name; reading notes and preparing a follow-up remain user actions inside EverReach | Compile both shortcuts, review custom-scheme deep-link delivery and Siri/Spotlight availability on a supported device, and confirm the contact name stays out of analytics |

See [ROUTING-EXPERIMENT.md](ROUTING-EXPERIMENT.md) for the Sonance route
prerequisites and the untested compatibility matrix. Nothing in this list
authorizes publication, metered cloud inference or access to private content
without the relevant user permission.
