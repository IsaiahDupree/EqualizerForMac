# Menu bar access — November 7, 2026

Development change based on `main` at `5dd2c36`, the 1.0.8 source baseline.
No application update has been uploaded, submitted or published.

## Architecture and interaction

The latest fetched default branch uses SwiftUI's singleton `Window` with id
`main`. An app-level `@State AppState` owns the EQ engine, tap, mixer, recorder,
licensing and selected settings. `ContentView` presents the existing controls
and entitlement-gated sheets. It has no disappearance handler that stops audio.
Source inspection found no menu bar extra, status item or global shortcut on
`main`, or in the newer feature-analytics and cross-platform development heads.
The existing native Window menu can restore the window when the app is active.

A system menu bar extra fits access while another app is active. An additional
application menu command alone would require switching apps first. Apple's
[MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)
supports commonly used functionality while the app is inactive. Its existing
[Window](https://developer.apple.com/documentation/swiftui/window) scene can be
opened with `openWindow` without creating a second EQ controller.

The addition is limited to:

- A persistent `slider.horizontal.3` symbol with the accessible name Sonance EQ.
- **Open Sonance EQ**, which opens the existing window id and activates the app.
- **Quit Sonance EQ**, using the standard AppKit termination path.
- **⌘⇧E** on the native Window command while Sonance EQ is active.
- English, French and the eight other existing shipping language catalogs.

The main window stays first in the scene list. Dock presence and the macOS
14.4 minimum remain intact. The extra is present only while the app runs; it
does not launch the app at login. It keeps the app available after its window
closes. App-level ownership preserves settings and any existing audio route.
Opening the window never calls Start, Stop, bypass, a preset action or a device
change. It uses the existing permission and purchase flows. No global hotkey,
second editor, volume control or menu-level audio mutation was added.

## Validation

The opt-in `SonanceEQ-MenuBar` scheme runs real macOS XCTest UI interactions.
It covers existing-window reuse, reopening after close with the bundled AirPods
Pro 3 preset and preamp retained, restoration after minimize and Hide, access
to the existing headphone browser, the Window keyboard shortcut, and Quit.
It does not start capture or change the system output.

Run directly on the owned Mac, with bounded concurrency:

```sh
xcodegen generate
xcodebuild test -project SonanceEQ.xcodeproj -scheme SonanceEQ-MenuBar \
  -xcconfig UITests/AccessTestIdentity.xcconfig \
  -destination 'platform=macOS,arch=arm64' -jobs 1 -parallel-testing-enabled NO
xcodebuild test -project SonanceEQ.xcodeproj -scheme SonanceEQ \
  -destination 'platform=macOS,arch=arm64' -jobs 1 -parallel-testing-enabled NO
```

The UI command uses a separate bundle identity so its launch/termination actions
cannot attach to an installed Sonance EQ copy. Test code targets that exact
identity and fails if the separate host is unavailable.

Observed on the owned Apple Silicon Mac with macOS 26.6.1 / Xcode 26.0.1:

| Check | Result |
| --- | --- |
| Debug application build | Passed |
| Full native regression | 281 methods / 4,297 runs passed, zero failures; existing 16 opt-in methods skipped |
| Separate local StoreKit gate | 15 methods / 25 runs passed, zero failures or skips, using real local Apple test transactions |
| AirPods Pro 3 catalog/application and existing DSP/audio lifecycle tests | Passed as part of the native regression |
| Isolated app and three UI test methods, `build-for-testing` | Passed compilation |
| Native interaction smoke check | Menu opens while another app is foreground; Open activates Sonance EQ; published preset loads and remains selected with its six-band curve and -3.9 dB preamp; native Window menu displays the shortcut; menu Quit exits the isolated host |
| Physical input acceptance, follow-up | Passed close/reopen, minimize/restore, Hide/unhide, and actual ⌘⇧E reopening after close. Each restored the six-band AirPods Pro 3 curve and -3.9 dB preamp. Used the isolated bundle, a verified foreground PID and leased JetKVM input; capture remained stopped |
| Automated UI execution | Blocked before any method ran: runner failed to initialize, “Timed out while enabling automation mode”; same result after test-helper recovery |
| Release-MAS resolved settings | Explicit task-local DerivedData probe resolves the real main app, arm64/x86_64, macOS 14.4, App Sandbox and hardened runtime enabled, with no `ENABLE_TCC_SPI` condition. Configuration verification, not a compiled/signed release |
| Local signing prerequisites | Valid Mac App Store application/distribution identities found in Keychain. AppFleet doctor remains blocked in target discovery; archive/export not completed |
| Preset database hash | Unchanged from 1.0.8: `5e57770a181181f892e7153ef942a48ff0ffdd014dc077827aac57ba5a0ee8e3` |

`DevToolsSecurity -status` reported developer mode disabled. This is a dated
environment observation, not proof of the timeout's root cause. No developer
security or privacy settings were changed. The three XCTest UI methods remain
unexecuted. Their principal access interactions were subsequently verified with
physical input as recorded above; automated execution still needs a working
UI-test host. The local Xcode test helper stopped
responding during later control-session requests. Restarting that stuck helper
restored both the repository's complete pre-commit check and the separate
StoreKit gate; no app code or test assertions were changed to resolve it.
The smoke check did not start capture,
and is not an audible-continuity test. Task-owned hosts were closed afterward;
the installed Sonance EQ copy was preserved.

The follow-up inspection found Xcode Helper absent from the Mac's Accessibility
authorization list. Its installed `com.apple.dt.Xcode-Helper` bundle passes an
Apple-root signature requirement. Apple documents
[Xcode Helper Accessibility access for UI testing](https://developer.apple.com/documentation/XCUIAutomation/recording-ui-automation-for-testing).
That permission is for development test tooling. Enabling new computer-control
access requires the owner's response to the pending permission request; no
permission was enabled during this validation. Its absence is a concrete setup
gap, not proof that it is the only cause of the XCTest timeout.

No AirPods output was connected during the follow-up device inventory. The
current output was Mac mini Speakers. Audible AirPods Pro 3 continuity therefore
remains unverified; the preset selection check is not an acoustic measurement.

The canonical AppFleet doctor initially failed on the default Xcode cache path,
then returned no signable target when that path produced empty build settings.
A real `-showBuildSettings -json` query with explicit task-local
`-derivedDataPath` resolves 579 settings and the expected main application.
AppFleet's current target-discovery path does not pass that explicit location.
Resolve that tooling path and rerun its signing preflight before local
archive/export. No fallback signing pipeline, new signing assets, version
record, upload or submission was created.

Native logs/results remain in the ignored `build/` directory:
`native-regression.xcresult`, `native-summary.json`, `menu-bar-ui.xcresult`,
`menu-bar-ui.log`, `menu-bar-ui-recovered.xcresult`, `isolated-ui-compile-final.log`,
`storekit-gate-recovered.xcresult`, `storekit-summary.json` and
`commit-validation-recovered.log`.
Follow-up evidence: `manual-access-continue.json`, `release-settings-explicit-derived.json`,
`local-release-doctor-workspace.stderr` and `ui-diagnostics-continue/`.
GitHub Actions was verified
disabled with no active runs. The repository has no deployment records or
active hooks; no cloud build or deployment was started. Existing workflow
files are historical source, not authorization to run them.

## Before release

- Review and merge this development branch.
- Run `SonanceEQ-MenuBar` with the isolated test identity on a working macOS
  UI automation host; do not treat its successful compilation as execution.
- Repair/recheck AppFleet's task-local target-settings discovery, then complete
  the signed archive/export and exact-artifact validation.
- Verify audible continuity on actual AirPods Pro 3 while opening the menu,
  closing/reopening the window, hiding/minimizing it and switching foreground
  apps. Check that the selected preset, preamp and bypass state remain intact.
- Exercise these interactions on the minimum supported macOS 14.4, with
  VoiceOver/keyboard menu navigation, and on Intel hardware.
- Check light/dark menu appearance and crowded/full-screen menu bar behavior.
- Run the normal signed MAS purchase, permission and distribution checks for
  the exact release candidate. This change does not alter those subsystems.
- Select the next version/build, prepare release notes and obtain the owner's
  explicit approval before any upload, submission or publication.

The bundled preset database, AirPods Pro 3 correction, DSP and audio lifecycle
sources are unchanged. Automated software checks do not establish audibility
or headphone-specific outcomes. This access change adds no marketing or
hearing-related product claims.
