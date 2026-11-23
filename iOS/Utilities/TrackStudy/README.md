# Track Study

Track Study is a local iPhone and iPad practice utility (iOS 17+). It imports one audio file selected through the system file picker, stores it in the app's private Application Support directory, plays it back, and saves named practice markers and A/B repeat loops with the track. A loop repeats a saved passage during playback; users set A and B from the current playhead and can remove loops independently. Removing a track is an explicit action that deletes only that imported file and its local marker, loop, and analysis record.

The iOS 27 Music Understanding integration is gated for the Swift 6.4 compiler in Xcode 27 and iOS 27. With that SDK and a supported runtime, it requests rhythm, key, song sections, and pace analysis from the user-selected local asset and stores the result with that track. Apple currently marks the framework documentation as beta, so these results are an optional aid until compiled and reviewed against a final supported runtime. This Mac uses Xcode 26.0.1 / iOS 26 SDK; it compiles the playback and practice features while leaving the analyzer disabled.

The app does not read Apple Music or other apps' protected streaming audio, access a user's broader media library, upload audio, record microphone input, or publish results. Framework output is analysis guidance, not a guarantee of correct musical interpretation.

Generate and build locally with XcodeGen and Xcode:

```sh
xcodegen generate --spec iOS/Utilities/TrackStudy/project.yml --project iOS/Utilities/TrackStudy
xcodebuild -project iOS/Utilities/TrackStudy/TrackStudy.xcodeproj -scheme TrackStudy -destination 'generic/platform=iOS Simulator' -jobs 1 CODE_SIGNING_ALLOWED=NO build
```

The iOS Simulator target with practice loops built successfully with Xcode 26.0.1 on 2026-11-22. The resulting bundle identifier is `com.isaiahdupree.trackstudy` and contains arm64 and x86_64 simulator executables. No simulator runtime exercise, iPhone installation, or release is included in this build task.

Apple references: [Music Understanding](https://developer.apple.com/documentation/musicunderstanding) · [Music Understanding session](https://developer.apple.com/documentation/musicunderstanding/musicunderstandingsession) · [WWDC26 framework overview](https://developer.apple.com/videos/play/wwdc2026/253/)
