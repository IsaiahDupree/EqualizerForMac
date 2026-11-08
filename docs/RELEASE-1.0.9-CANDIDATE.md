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

The [menu bar validation record](MENU-BAR-ACCESS-2026-11-07.md) contains the
completed regression, StoreKit, physical access and prior signed-package
checks. The new candidate's exact package still requires local build/export
and inspection.

Release requirements remain:

- Complete automated UI execution on a working test host. Xcode Helper
  Accessibility authorization remains pending; no permission has been granted.
- Verify audible continuity on actual AirPods Pro 3 during menu and window use.
- Verify minimum macOS 14.4 and Intel runtime behavior, VoiceOver, keyboard menu
  navigation, menu appearance and full-screen access.
- Complete the normal purchase and audio-permission acceptance on the exact
  signed release candidate.
- Review/integrate the application and AppFleet development changes.
- Obtain the owner's explicit approval before upload, submission or publication.
