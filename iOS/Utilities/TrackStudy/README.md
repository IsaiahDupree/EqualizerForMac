# Track Study

Track Study is a local iPhone and iPad practice utility (iOS 17+). It imports one audio file selected through the system file picker, stores it in the app's private Application Support directory, plays it back, and saves named practice markers with the track. Removing a track is an explicit action that deletes only that imported file and its local marker/analysis record.

The iOS 27 Music Understanding integration is compiler and OS gated. With an iOS 27 SDK and runtime, it requests rhythm, key, song sections, and pace analysis from the user-selected local asset and stores the result with that track. The current development Mac uses Xcode 26.0.1 / iOS 26 SDK, so this integration cannot be compiled or verified here yet. The current build still provides file import, playback, seeking, persistent practice markers, and a clear availability message for analysis.

The app does not read Apple Music or other apps' protected streaming audio, access a user's broader media library, upload audio, record microphone input, or publish results. Framework output is analysis guidance, not a guarantee of correct musical interpretation.

Generate and build locally with XcodeGen and Xcode:

```sh
xcodegen generate --spec iOS/Utilities/TrackStudy/project.yml --project iOS/Utilities/TrackStudy
xcodebuild -project iOS/Utilities/TrackStudy/TrackStudy.xcodeproj -scheme TrackStudy -destination 'generic/platform=iOS Simulator' -jobs 1 CODE_SIGNING_ALLOWED=NO build
```

The iOS Simulator target built successfully with Xcode 26.0.1 on 2026-11-22. The resulting bundle identifier is `com.isaiahdupree.trackstudy` and contains arm64 and x86_64 simulator executables. No simulator runtime exercise, iPhone installation, or release is included in this build task.
