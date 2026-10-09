# Current-route audio health

Source target: `SonanceEQ`, bundle `com.isaiahdupree.SonanceEQ`, source version
1.0.6 / build 9. This change is source validation, not an App Store release.

The initial route reset its callback counter after `AudioDeviceStart`, which
could erase an early callback. Output-device and target rebuilds reused the old
counter and did not arm a new watchdog. A failed rebuild also omitted teardown
of its partially created tap, aggregate, IOProc and device listener.

Every start/rebuild now creates a separate heartbeat before the IOProc starts.
Its closure retains only that route's heartbeat. The watchdog uses a cancelable
main-queue work item and checks its arm generation and heartbeat identity.
Stop invalidates pending checks before releasing the route. Failed builds take
the same cleanup path as Stop; listener registration failures also fail startup.
Queued device notifications carry a session generation. Deferred UI callbacks
check the current tap identity and read its current state.

The Stop control stays usable while a route is starting. The header displays
`Routing audio…` until that route's 1.5-second callback check succeeds. A prior
route's callbacks cannot produce an Active label for a replacement. Repeated
Start/permission completions do not replace an already running route.

## Executable validation

`AudioRouteWatchdogTests` exercises the shipping heartbeat and real main-queue
deadlines without substituting Core Audio or providers: early callback delivery,
late old-route delivery, distinct replacement deadlines, cancellation, stop and
restart, rearming, and exactly one timeout result. `AppStateTests` checks that
running intent alone does not claim flow and that Start is idempotent while
running. `ShippingLocalizationTests` validates the localized status catalog.

```sh
xcodegen generate
xcodebuild test -project SonanceEQ.xcodeproj -scheme SonanceEQ \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -jobs 2 -parallel-testing-enabled NO 'OTHER_SWIFT_FLAGS=$(inherited) -j2'
```

The normal scheme excludes the opt-in local StoreKit gate. This route change
does not alter purchase, restore, provider configuration or transaction policy.

The final Debug build/test passed on October 9, 2026: 256 test functions,
4,227 test runs, zero failures, with seven opt-in StoreKit functions skipped.
The new lifecycle suite uses seven serialized real-clock tests; two additional
AppState tests cover start/status behavior. The initial focused run also passed
19 tests across lifecycle, AppState and localization. Final evidence is outside
Git at `/tmp/sonance-audio-route-final-20261009.xcresult`; the build log is
`/tmp/sonance-audio-route-final-20261009.log`. `git diff --check` passed.

## Remaining acceptance

Callback delivery proves current-route processing, not audible/nonzero audio,
useful EQ, continuous liveness, or hardware compatibility. Silent source audio
is valid and must not itself trip a routing failure. Existing cleanup OSStatus
handling is unchanged; this change proves the cleanup path is invoked, not that
an operating-system destruction call always succeeds.

SON-07 remains open for actual current-build first-run/permission and
output-switch checks on built-in, wired, Bluetooth and an available interface.
Use owned unprotected audio, record OS/build/device and success/failure, verify
audible recovery or normal passthrough after failure, and restore the original
output. The existing `Tools/verify_audio_flow.swift` covers the per-app mixer,
not this global `SystemAudioTap`; it cannot stand in for this acceptance.
The reported MacBook/Scarlett failure has not been reproduced in this change.

No remote analytics, campaign identity, audio upload, App Store publication,
or replacement of the owner's installed app is part of this fix.
