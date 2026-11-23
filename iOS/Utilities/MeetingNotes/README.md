# Clear Record (Meeting Notes)

Clear Record is a local meeting recorder and note organizer prototype for iPhone and iPad (iOS 17+). A person must confirm that everyone present has agreed before each recording. Recording state remains visible, and a Stop control is always available. Recording stops and saves when the app leaves the foreground or the audio session is interrupted. Audio and transcripts stay in the app's Application Support folder unless the user explicitly shares the audio or transcript.

Transcription is a separate action after recording. The app requests Apple's Speech permission and sets `requiresOnDeviceRecognition`; it will not fall back to network recognition. If the current device or language does not support on-device recognition, the recording remains saved and the app reports that transcription is unavailable.

The app does not record calls, read other apps, start in the background, upload media, or generate summaries. It supports review, transcript correction and local saving, rename, copy/share of transcript text, and explicit deletion of the local recording and note. Speech permission is requested only when the person chooses to transcribe a saved recording; recording itself requires microphone access and participant consent.

Build locally with XcodeGen and Xcode:

```sh
xcodegen generate --spec iOS/Utilities/MeetingNotes/project.yml --project iOS/Utilities/MeetingNotes
xcodebuild -project iOS/Utilities/MeetingNotes/MeetingNotes.xcodeproj -scheme MeetingNotes -destination 'generic/platform=iOS Simulator' -jobs 1 CODE_SIGNING_ALLOWED=NO build
```

The latest simulator-target build succeeded with Xcode 26.0.1 on 2026-11-22. No runtime exercise, phone installation, or release is part of this project.
