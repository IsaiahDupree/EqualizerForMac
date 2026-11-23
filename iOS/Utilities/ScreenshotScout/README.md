# Screenshot Scout

Screenshot Scout makes a searchable local index of images a person explicitly selects from Photos. It uses Apple's Vision framework on-device to recognize visible text and suggest image labels. It detects byte-identical reimports by SHA-256, before storing another copy. A person can ask Vision to rank the closest images already in the local index for side-by-side review and cancel the scan; the app doesn't call visual similarity a duplicate and never removes an image automatically.

The app stores a resized JPEG copy (up to 2200 pixels on its longest edge) in its own Documents folder and saves OCR and labels in a local JSON index. It does not scan the photo library, access other apps, upload images, or delete anything from Photos. Removing an item deletes only Screenshot Scout's private copy and index row.

Build the project with XcodeGen and Xcode:

```sh
xcodegen generate --spec iOS/Utilities/ScreenshotScout/project.yml --project iOS/Utilities/ScreenshotScout
xcodebuild -project iOS/Utilities/ScreenshotScout/ScreenshotScout.xcodeproj -scheme ScreenshotScout -destination 'generic/platform=iOS Simulator' -jobs 1 CODE_SIGNING_ALLOWED=NO build
```

This initial app targets iOS 17. It does not depend on beta-only iOS 27 APIs. It has been built locally for development; no phone install or release is part of this project.
