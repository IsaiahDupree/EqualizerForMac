# Sonance EQ 1.0.9 — local candidate

Proposed version 1.0.9, build 12, for the menu bar access addition. This is
development preparation. No Apple version record, upload, submission or
publication is authorized or completed by this document.

## Proposed release notes

- Open Sonance EQ from its new menu bar icon while using another application.
- Restore the EQ window with Command-Shift-E while Sonance EQ is active.

The menu presents the existing EQ controls and standard Quit command. Closing
the window keeps the application running. It does not add a login item or
change audio processing, the AirPods Pro 3 preset, purchases or permissions.

## Candidate selection

A read-only AppFleet status check found 1.0.8/build 11 ready for sale, with build
11 the latest uploaded build and no newer version record. The local XcodeGen
settings and appstore.json now agree on 1.0.9/build 12. The Info.plist continues
to expand those build settings. Apple state must be checked again before any
future authorized upload; these numbers are not reserved on Apple's servers.

## Acceptance

The current package was built from application commit `cfba8f0` through
AppFleet commit `262d811`, using the existing Sonance EQ MAS profile and
application/installer certificates. It was neither installed nor launched.
Its local workspace path is:

`artifacts/sonance-menu-bar-validation-20261107/com.isaiahdupree.SonanceEQ/1.0.9-12-20261108-002208-272720/export/SonanceEQ.pkg`

SHA-256: `c928b932a3a4e4b6872694b21378ac2dd755bbc5e78046d663824f8be55e21be`.

| Check | Result |
| --- | --- |
| Native pre-commit regression after activation change | 281 methods passed, zero failures; 16 existing opt-in cases skipped, with StoreKit checked separately |
| Local StoreKit gate on 1.0.9 before the presentation-only activation change | 15 methods passed, zero skips or failures |
| Exact package verification | Passed signatures, exact certificate fingerprints, profile names, entitlements, bundle/version/build, embedded purchase SDK key and manifest binding |
| Actual payload inspection | arm64/x86_64, macOS 14.4 minimum load commands, sandbox/hardened runtime, no debugging entitlement, Dock presence retained |
| Preset database in the actual package | Unchanged SHA-256 `5e57770a181181f892e7153ef942a48ff0ffdd014dc077827aac57ba5a0ee8e3` |
| Purchase configuration and real-package handoff tests | 25 passed, zero skips/failures, including rejection of a wrong build/key and a read-only preview outside the repository |
| Version source and handoff command checks | Passed; the existing opt-in second-version compile test remains skipped |
| UI acceptance target | Four methods compiled; execution remains blocked by the test-host setup described in the validation record |
| Keyboard status-menu activation | Physical test of the initial build reopened the window behind Finder; mouse selection activated it correctly. Activation is now deferred until menu tracking returns. Physical retest of that change is pending the shared input lease |

The [menu bar validation record](MENU-BAR-ACCESS-2026-11-07.md) records prior
close/reopen, Hide, minimize and application-shortcut checks with the AirPods
Pro 3 curve retained. Those interactions did not start capture. The initial
1.0.9 package predating the activation change was superseded, despite passing
its signing checks.

The purchase preflight now accepts the existing absolute
`SONANCE_DERIVED_DATA_DIR` and `SONANCE_SOURCE_PACKAGES_DIR` cache options. A
real settings query reproduced the host's unavailable default Xcode directory;
selecting the task cache resolves current Release-MAS settings and preserves
all purchase/version validation. No cached settings response replaces Xcode.

Apple documents [`NSApplication.activate()`](https://developer.apple.com/documentation/appkit/nsapplication/activate())
as an activation request, so the physical foreground check remains an acceptance
requirement. The test copy and task Finder window were closed after reproducing
the issue; the installed application was preserved and the input lease released.

Release requirements remain:

- Complete automated UI execution on a working test host. Xcode Helper
  Accessibility authorization remains pending; no permission has been granted.
- Verify audible continuity on actual AirPods Pro 3 during menu and window use.
- Verify minimum macOS 14.4 and Intel runtime behavior, VoiceOver, keyboard menu
  navigation, menu appearance and full-screen access.
- Physically retest Control-F8, Down, menu selection and Return after closing
  the isolated app window and activating Finder. Confirm the reopened window
  becomes foreground; a background window is not sufficient.
- Complete the normal purchase and audio-permission acceptance on the exact
  signed release candidate.
- Review/integrate the application and AppFleet development changes.
- Obtain the owner's explicit approval before upload, submission or publication.

Private local evidence remains under ignored `build/`: `candidate-native-summary.json`,
`candidate-storekit.xcresult`, `candidate-storekit-summary.json`,
`candidate-final-package-tests.log`, `candidate-signed-validation.json`,
`keyboard-activation-reproduction.json`, `keyboard-activation-compile.log` and
`keyboard-activation-precommit.log`, plus `keyboard-activation-native-summary.json`.
Native build/export logs remain beside the
artifacts outside the source repository.
