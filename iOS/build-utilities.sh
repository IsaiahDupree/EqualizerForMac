#!/bin/bash
set -euo pipefail

ios_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
build_root="${IOS_UTILITY_DERIVED_DATA_DIR:-${TMPDIR:-/tmp}/ios-utility-derived-data}"
build_jobs="${IOS_UTILITY_BUILD_JOBS:-2}"
destination="generic/platform=iOS Simulator"

if ! xcodebuild -showsdks >/dev/null 2>&1; then
  printf 'Xcode SDK discovery failed. Complete Xcode first-use setup before building.\n' >&2
  exit 2
fi

while IFS='|' read -r project scheme; do
  [[ -n "$project" ]] || continue
  printf '\nBuilding %s (%s)\n' "$scheme" "$destination"
  xcodebuild \
    -project "$ios_root/$project" \
    -scheme "$scheme" \
    -destination "$destination" \
    -derivedDataPath "$build_root/$scheme" \
    -jobs "$build_jobs" \
    CODE_SIGNING_ALLOWED=NO \
    -quiet build
done <<'PROJECTS'
SonanceEQ.xcodeproj|SonanceEQiOS
Utilities/ScreenshotScout/ScreenshotScout.xcodeproj|ScreenshotScout
Utilities/TrackStudy/TrackStudy.xcodeproj|TrackStudy
Utilities/MeetingNotes/MeetingNotes.xcodeproj|MeetingNotes
PROJECTS

printf '\nAll local utility targets built successfully. No tests or device installs were run.\n'
