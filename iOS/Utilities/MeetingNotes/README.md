# Clear Record (Meeting Notes)

Clear Record is a local meeting recorder and note organizer prototype for iPhone and iPad (iOS 17+). A person must confirm that everyone present has agreed before each recording. Recording state remains visible, and a Stop control is always available. Recording stops and saves when the app leaves the foreground or the audio session is interrupted. Audio and transcripts stay in the app's Application Support folder unless the user explicitly shares the audio or transcript.

Transcription is a separate action after recording. The app lists locales returned by Apple's Speech framework only when that locale's recognizer reports `supportsOnDeviceRecognition`. It checks service availability again when transcription starts, requests Speech permission at that point, and sets `requiresOnDeviceRecognition`; it will not fall back to network recognition. Locale support varies by device and system configuration. If the selected language or service is unavailable, the recording remains saved and the app reports the condition.

The app does not record calls, read other apps, start in the background, or upload media. On iOS 27, a separate optional Foundation Models action can draft a concise summary, decisions, action items, and open questions from the saved transcript. The on-device model must be available; its draft is editable, remains unsaved until the user reviews and saves it, and is marked stale if the transcript later changes. No summary is generated automatically. The app also supports transcript correction and local saving, rename, copy/share of transcript text, and explicit deletion of the local recording and note. Speech permission is requested only when the person chooses to transcribe a saved recording; recording itself requires microphone access and participant consent.

Foundation Models support is compile-gated for Swift 6.4 / Xcode 27 and iOS 27. This Mac has Xcode 26.0.1 / iOS 26 SDK, so it builds the established recording and transcript experience with the summary action unavailable. The iOS 27 model path has not yet been compiled or reviewed at runtime. Apple describes `respond(to:)` as asynchronous and requires checking on-device model availability before use. See [Foundation Models generation](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models) and [SystemLanguageModel availability](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel).

Build locally with XcodeGen and Xcode:

```sh
xcodegen generate --spec iOS/Utilities/MeetingNotes/project.yml --project iOS/Utilities/MeetingNotes
xcodebuild -project iOS/Utilities/MeetingNotes/MeetingNotes.xcodeproj -scheme MeetingNotes -destination 'generic/platform=iOS Simulator' -jobs 1 CODE_SIGNING_ALLOWED=NO build
```

The latest simulator-target build, including the supported-locale picker, succeeded with Xcode 26.0.1 on 2026-11-22. No runtime exercise, phone installation, or release is part of this project.
