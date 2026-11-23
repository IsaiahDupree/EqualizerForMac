# Screenshot Scout / Creator Library

Screenshot Scout makes a searchable local index of images and videos a person explicitly selects from Photos. It uses Apple's Vision framework on-device to recognize visible text and suggest image labels. It detects byte-identical reimports by SHA-256, before storing another copy. A person can ask Vision to rank the closest images already in the local index for side-by-side review and cancel the scan; visual similarity is a suggestion, not proof of a duplicate, and the app never removes an image automatically.

For a selected video, the app keeps a private full-resolution copy and samples five frames across its duration. Vision reads visible text and scene labels from those frames. On iOS 27, a person can optionally draft and edit a separate scene description for an individual sampled frame using the on-device image model. The model receives that frame image only; the app does not submit the entire video. Search results point to the video and sampled moments; the person reviews the original before using any clip. Video indexing can be cancelled, and exact duplicate videos are skipped using a streaming SHA-256 pass.

The library exports a JSON inventory without media copies. The user chooses metadata only or an explicit option to include recognized text, Vision labels, and any saved scene descriptions. A persistent review queue lets the user save selected images and videos for later inspection, open each item from the queue, and remove it from the queue after review. Queue entries are included in the JSON inventory; nothing is deleted automatically.

On iOS 27 builds, an optional Foundation Models path can suggest a short visual scene description for one selected image or one sampled video frame at a time. It passes the local image URL to Apple's on-device model only when the system reports the model ready and image support available. The user reviews or edits the suggestion and explicitly saves it to the local search index. The description is a search aid, not verified image or video metadata. This path is compile-gated for the Swift 6.4 compiler in Xcode 27.

Image copies, selected video copies, sampled frames, review queue, and JSON indexes are stored in the app's Documents folder. The app marks that folder as excluded from device backups and performs analysis locally. It does not scan the photo library, access other apps, upload media, or delete originals from Photos. Removing an item deletes only Screenshot Scout's private copy and index data.

Build the project with XcodeGen and Xcode:

```sh
xcodegen generate --spec iOS/Utilities/ScreenshotScout/project.yml --project iOS/Utilities/ScreenshotScout
xcodebuild -project iOS/Utilities/ScreenshotScout/ScreenshotScout.xcodeproj -scheme ScreenshotScout -destination 'generic/platform=iOS Simulator' -jobs 1 CODE_SIGNING_ALLOWED=NO build
```

The app's core image and video features target iOS 17 and do not depend on iOS 27 APIs. The optional scene-description feature is compile-gated for iOS 27. The last verified local build used Xcode 26.0.1; Xcode 27.2 is now installed, but its first-use license has not been accepted, so a current-SDK build is pending. Camera/photo runtime behavior has not been exercised. No phone install or release is part of this project.
