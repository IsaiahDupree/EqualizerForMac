# Track Study

Track Study is a local iPhone and iPad practice utility (iOS 17+). It imports one audio file selected through the system file picker, stores it in the app's private Application Support directory, plays it back, and saves named practice markers and A/B repeat loops with the track. A loop repeats a saved passage during playback; users set A and B from the current playhead and can remove loops independently. A Siri/Shortcuts action can mark the current playhead without interrupting practice. Removing a track is an explicit action that deletes only that imported file and its local marker, loop, and analysis record.

The iOS 27 Music Understanding integration is gated for the Swift 6.4 compiler in Xcode 27 and iOS 27. With that SDK and a supported runtime, it requests rhythm, key, song structure, pace, instrument activity, and loudness from the user-selected local asset and stores the summary with that track. Apple currently marks the framework documentation as beta, so these results are an optional aid until compiled and reviewed on a supported runtime. The app labels pace as perceived events per minute, separately from BPM; section, key, pace, and first detected instrument spans can jump playback to the corresponding start time. Integrated loudness and peak level are shown when available. The last verified build used Xcode 26.0.1 / iOS 26 SDK and compiled playback and practice features while leaving the analyzer disabled. Xcode 27.2 is now installed, but its first-use license has not been accepted, so the new analyzer path has not been compiled locally.

The app does not read Apple Music or other apps' protected streaming audio, access a user's broader media library, upload audio, record microphone input, or publish results. Framework output is analysis guidance, not a guarantee of correct musical interpretation.

The App Shortcut “Mark this point in Track Study” requires a saved track, stores a `Siri marker` at the current playhead, and does not start or record audio. It is registered through Apple's App Intents framework and is available from Siri, Spotlight, and Shortcuts when supported by the OS.

Generate and build locally with XcodeGen and Xcode:

```sh
xcodegen generate --spec iOS/Utilities/TrackStudy/project.yml --project iOS/Utilities/TrackStudy
xcodebuild -project iOS/Utilities/TrackStudy/TrackStudy.xcodeproj -scheme TrackStudy -destination 'generic/platform=iOS Simulator' -jobs 1 CODE_SIGNING_ALLOWED=NO build
```

The last iOS Simulator target build, with practice loops, succeeded with Xcode 26.0.1 on 2026-11-22. The resulting bundle identifier is `com.isaiahdupree.trackstudy` and contains arm64 and x86_64 simulator executables. No simulator runtime exercise, iPhone installation, or release is included in this build task.

Apple references: [Music Understanding](https://developer.apple.com/documentation/musicunderstanding) · [Music Understanding session](https://developer.apple.com/documentation/musicunderstanding/musicunderstandingsession) · [Pace results](https://developer.apple.com/documentation/musicunderstanding/paceresult) · [Loudness results](https://developer.apple.com/documentation/musicunderstanding/loudnessresult) · [WWDC26 framework overview](https://developer.apple.com/videos/play/wwdc2026/253/)
