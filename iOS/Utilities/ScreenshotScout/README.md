# Screenshot Scout / Creator Library

Screenshot Scout makes a searchable local index of images and videos a person explicitly selects from Photos. It uses Apple's Vision framework on-device to recognize visible text and suggest image labels. It detects byte-identical reimports by SHA-256, before storing another copy. A person can ask Vision to rank the closest images already in the local index for side-by-side review and cancel the scan; visual similarity is a suggestion, not proof of a duplicate, and the app never removes an image automatically.

For a selected video, the app keeps a private full-resolution copy and samples five frames across its duration. Vision reads visible text and scene labels from those frames. Search results point to the video and sampled moments; the person reviews the original before using any clip. Video indexing can be cancelled, and exact duplicate videos are skipped using a streaming SHA-256 pass.

The library exports a JSON inventory without media copies. The user chooses metadata only or an explicit option to include recognized text and Vision labels.

Image copies, selected video copies, sampled frames, and JSON indexes are stored in the app's Documents folder. The app marks that folder as excluded from device backups, performs analysis locally, and does not scan the photo library, access other apps, upload media, or delete originals from Photos. Removing an item deletes only Screenshot Scout's private copy and index data.

Build the project with XcodeGen and Xcode:

```sh
xcodegen generate --spec iOS/Utilities/ScreenshotScout/project.yml --project iOS/Utilities/ScreenshotScout
xcodebuild -project iOS/Utilities/ScreenshotScout/ScreenshotScout.xcodeproj -scheme ScreenshotScout -destination 'generic/platform=iOS Simulator' -jobs 1 CODE_SIGNING_ALLOWED=NO build
```

This initial app targets iOS 17. It does not depend on beta-only iOS 27 APIs. The image and video targets have been compiled locally; camera/photo runtime behavior has not been exercised. No phone install or release is part of this project.
