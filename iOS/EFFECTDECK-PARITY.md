# Sonance EQ iOS — EffectDeck feature parity

This branch turns Sonance EQ into an iPhone audio host as well as an EQ. It
embeds the pinned, MIT-licensed EffectDeck host and DSP, then adds Sonance EQ as
an Audio Unit and brands the host as Sonance EQ. The goal is to make the
EffectDeck workflows available inside Sonance EQ while retaining Sonance's
32-band EQ, AutoEQ catalog, correction profiles, presets and standalone player.

## Current implementation status — 2026-11-25

| EffectDeck workflow | In the Sonance iOS source | Build / device evidence |
| --- | --- | --- |
| Ordered effects chain | Add, remove, reorder, collapse, bypass and persist chain stages; chain enable, I/O and latency indicators | Combined host 0.2.0 (28) was installed and launched on iPhone 15. Current signed build 34 includes persisted route diagnostics and recovery guidance. Physical CarPlay behavior still needs validation. |
| Effects, plug-ins and presets browser | Searchable Effects / Plugins / Presets tabs; categories; built-in effects and analyzers; installed AUv3 discovery and editors; system, user and effect presets | Included in generated `EffeTuneLive` target and signed. Device behavior remains unverified. |
| Signal routing | Routing screen shows each stage's input/output buses and channel mode; stage channel maps and multichannel processing are part of the host | Included and signed. Stage routing has not yet been exercised on device. |
| Import, export and sharing | Clipboard chain replacement, share links, chain and preset import/export, share extension and import inbox | Host and Share extension are signed with `group.com.isaiahdupree.SonanceEQ`; host launch is verified. Share-container workflows remain unverified. |
| Analyzers and meters | Level / analog meters, spectrum, note spectrum, spectrogram, oscilloscope and other built-in analysis stages | Included and signed. Meter and analyzer readings have not been checked against device fixtures. |
| Processing and power settings | Oversampling, DSP buffer selection, input format/buffer, CPU and latency display, pause-after-silence, silence threshold, keep-screen-on and visual sync controls | Included and signed. Real-time deadline and power behavior remain unmeasured on iPhone. |
| Floating meters and chain controls | Floating meter controls, chain-level effects switch and per-card enable, collapse and menu actions | Included and signed; UI interaction is not device-verified. |
| Remote control | Remote settings and QR-code scanning workflow | Included and signed. No remote peer/session was tested. |
| About and support | Version, DSP version, limitations, licenses, privacy and feedback links | Included and signed. Final branded copy is applied by `HostConfig/apply-upstream-adaptation.py`. |
| Control Center output routing | Separate minimal `Sonance EQ Route` installer and Media Device extension; extension sends captured samples to the full host's DSP chain over the loopback PCM bridge | Build 16 route installer and extension compile unsigned. Profiles contain an empty Media Device entitlement; the Developer portal exposes the older Media Device Discovery capability but no request entry for the new entitlement. |
| Sonance EQ | Existing Sonance AUv3 embedded in the host; its editor now includes the offline headphone-correction catalog. Standalone 32-band EQ/player remains available in its own tab with AutoEQ data, output corrections and presets | Host and standalone Audio Unit targets both bundle the 8,862-row catalog. The focused simulator integration test applies an AirPods Pro 3 correction to AU parameters and verifies finite rendering (1/1); host AU lifecycle, picker interaction and physical audio remain unverified. |
| Standalone EQ edit history | Undo/redo buttons in the EQ editor; edits are grouped at interaction boundaries, restored snapshots persist, and new edits clear redo | Session tests and one simulator UI workflow pass; iPhone interaction remains unverified. |
| AutoEq GraphicEQ import | Converts GraphicEQ text into a fitted 32-band parametric approximation, estimates headroom when the source has no preamp, and displays an approximation notice | All six preset-library simulator tests pass; combined host build 23 includes the importer but is not installed on iPhone. |

The no-audio host banner now has a direct **Open Player** action even before a route burst is classified. The shared presentation predicate and route state tests pass 17/17 on the iOS 26 simulator. Signed iPhoneOS build 31 (0.2.0) contains the change and passes strict code-signature verification; it has not been installed because Xcode currently reports the exact iPhone 15 unavailable (CoreDevice -27 and no USB device entry).

Combined build 32 contains a standalone playback reconnect fix: if an engine configuration notification arrives before the route-change notification, it retains the active Bluetooth/CarPlay identity needed to resume only when that same route returns. The playback policy suite passes 6/6 on iOS 26 simulator. Build 34 includes route rejection guidance for both EffectDeck Audio and Sonance EQ Audio labels, including the detailed CarPlay bounce state; its focused suite passes 17/17 on iOS 26 simulator (`/Volumes/SonanceEQBuildScratch/SonanceRouteBounceCopyFinal.xcresult`). The iPhoneOS app passes strict deep signature verification, but physical Bluetooth validation remains pending because the exact iPhone 15 is unavailable to Xcode and absent from USB inventory.

The full embedded-host `Logic` suite passes 1,436/1,436 on the iOS 26 iPad Pro
simulator with test parallelization disabled. Result bundle:
`/tmp/SonanceEffectDeckFullLogicSerial.xcresult`. A prior parallel run had one
JSFX compile-guard timeout; that exact case passed alone and in the successful
serial run. Its incomplete diagnostic bundle is retained as a failed-run record.

The screenshots' routing screen and the Effects / Plugins / Presets browser are
implemented in the host source. Combined host version 0.2.0 (build 28) was
installed and launched on the exact iPhone 15 UDID
`00008120-000465A20C52201E`; `devicectl` verified the installed version and
the app plus AU extension running. At 11:13 EDT on 2026-11-25, Xcode later
reported the phone unavailable (CoreDevice preparation error -27), and USB
inventory had no Apple mobile device, so the subsequent physical route/audio
test could not start. The host and Share extension contain the expected Sonance App Group
entitlement. The host distinguishes a changing route, iPhone Speaker fallback,
and direct car-audio output in its status banner. Route changes are compared
using endpoint UID and port type. The banner now retains a single transition
from the EffectDeck or Sonance EQ route to CarPlay or another output. Physical
CarPlay behavior remains unverified.

The route-diagnostic update is included in signed build 21. It displays the last
four route transitions and iOS reason, distinguishes a route handoff from an EQ
processing fault, tells users to stop retrying an unsupported source route, and
distinguishes direct CarPlay playback (EQ bypassed) from compatible-source
playback through the EQ. The warning remains visible when the host peer is
connected but output is routed to CarPlay or the iPhone speaker. The route
notification handler now snapshots the destination when the notification is
delivered, so a deferred task cannot relabel a fast CarPlay/iPhone transition
with a later route. The extracted presentation suite previously passed 8/8 on
the iOS 26.0 simulator; the production host test target requires iOS 27 and
could not run on the installed iOS 26 simulators. The signed generic iOS build succeeded with the host
and embedded Share / AU profiles; `codesign --verify --deep --strict` passed.
Build 21 is version 0.2.0, bundle ID `com.isaiahdupree.SonanceEQ.iOSPrototype`,
and its app bundle signature verifies. The exact iPhone 15 continues to report
unavailable to Xcode. A second exact-UDID install retry on 2026-11-25 returned
CoreDevice 4016 with no assertable connectivity/service states, so build 21 is
not installed or physically exercised. Xcode Device Hub displayed only the iPad simulator;
the unavailable-device list was empty, and `system_profiler SPUSBDataType`
showed no iPhone/Apple Mobile Device USB entry. `xcdevice list` reports error
-27 while browsing the local network for the phone. Build log:
`/tmp/sonance-eq-carplay-fix21-build.log`.

Standalone editor undo/redo was added after build 21. The full session test
class passed 11/11, including grouped edits, persisted undo/redo, route-bound
correction persistence and clearing redo after a new edit. The simulator UI
test passed 1/1 by loading Vocal, undoing to the Flat preamp, and redoing the
preset. Combined host build 22 embeds that editor in `SonanceEQPlayer.framework`;
the signed app passes `codesign --verify --deep --strict`. Build 22 is not
installed because the same exact iPhone is still
unavailable to Xcode. Build log: `/tmp/sonance-eq-build22.log`.

AutoEq `GraphicEQ:` text import fits source curves to up to 32 peaking bands,
adds estimated headroom when the file has no preamp, and surfaces an explicit
approximation notice. All six preset-library tests passed on the iOS 26.0
simulator, covering fitted response, BOM input, malformed/unordered rejection
and notice presentation. Combined build 23 compiles and signs; the main app
bundle catalog passes `PRAGMA integrity_check` with 8,862 presets. The exact
iPhone 15 remains unavailable (`xcdevice` error -27; no iPhone USB entry), so
build 23 is not installed or physically exercised. Build log:
`/tmp/sonance-eq-build23.log`.

Build 25 adds endpoint-type detection for repeated CarPlay ↔ iPhone-speaker
handoffs. After three matching transitions in 30 seconds, the host labels that
pattern and tells the user to leave CarPlay selected for car playback. It also
explains that the supplied SoundCloud alert rejects the EffectDeck Audio route.
The detector reports route state; it cannot override iOS routing or add support
to SoundCloud. The focused route tests cover correct classification and reject
unrelated Bluetooth/speaker changes. Build log: `/tmp/sonance-eq-build24.log`.

Build 26 persists that bounded route history to app-local defaults and restores
it on launch while it remains inside the 30-second diagnostic window. The
focused route suite passes 11/11 on the iOS 26 iPad Pro simulator, including
the serialization/restore path. Build 26 (0.2.0) compiles and signs for iPhoneOS;
strict signature verification passes. It is not installed because the exact
iPhone 15 is currently unavailable to Xcode. Build log:
`/tmp/sonance-eq-build26.log`; result bundle:
`/Volumes/SonanceEQBuildScratch/SonanceRouteHistoryPersistenceDefaults.xcresult`.

The standalone Sonance EQ Audio Unit continuity suite ran on the available iPad
Pro 13-inch M5 simulator (iOS 26.0): 12 tests passed, zero failures or skips.
It covers rendered sample continuity, injected gaps/corruption, stereo and
Mid/Side behavior, FIR output, gain/bypass edits and filter load. This is
simulator DSP evidence only; it does not validate iPhone hardware, the iOS 27
EffectDeck host, Bluetooth or CarPlay.

Build 35 (0.2.0) adds an opt-in Share route report to the route-warning card.
It includes app/build and iOS versions, current output, route-state flags and
the recent transition summary. It excludes track metadata and sends nothing
automatically. The focused route suite, including report contents, passes 19/19
on the iOS 26 simulator. Xcode 27.2 compiles and signs the host for iPhoneOS;
the binary contains the Share action and strict signature verification passes
for bundle ID `com.isaiahdupree.SonanceEQ.iOSPrototype`. The signed app is
preserved at `/Volumes/My Passport/SonanceEQ-build-35/SonanceEQHost.app`.
Installation was attempted against the requested iPhone 15 UDID
`00008120-000465A20C52201E` and failed because CoreDevice could not establish
trusted live connectivity (`remoteServiceDiscoveryTrustedConnectivityAvailable`;
device error 4016). `xcdevice` also reports error -27 while browsing for the
iPhone; Mac USB enumeration and `idevice_id` list no attached iPhone. The device
is paired, running iOS 27.3, and has Developer Mode enabled, but is unavailable
for installation. The route report tests and app build results are preserved in
`/Volumes/My Passport/SonanceEQ-build-34/`. CarPlay routing and Bluetooth remain
unverified on hardware.

The embedded host's complete `Logic` unit-test scheme passes 1,436/1,436 tests
on the iOS 26 simulator when test parallelization is disabled. Branding-sensitive checks derive the route name
from `ETAudioSessionRules.nameStem` and validate the Sonance EQ status copy.
The production host still targets iOS 27, so this result covers its logic
suite, not its UI, physical routing, CarPlay or Bluetooth playback.

For repeated switching, the route-burst warning now takes priority over the
latched single-handoff warning, so the banner keeps showing the recent route
sequence instead of hiding it after the first return from the EQ route. The
updated combined host simulator build succeeded on 2026-11-25. A clean-source
audit also regenerated the adapted EffectDeck Sources and Tests exactly from
the pinned upstream archive and the checked-in adaptation script. Device build
18 was rebuilt and signed with the tested route-presentation model. All 7
focused route-history/presentation tests passed on the iOS 26 simulator. It is
ready at
`/Volumes/SonanceEQBuildScratch/SonanceRouteHistoryDevice/Build/Products/Debug-iphoneos/SonanceEQHost.app`,
but is not installed: `devicectl` still reports the exact iPhone 15 as
unavailable. The latest `xcdevice list --timeout 15` identifies it by the
correct UDID but returns CoreDevice error -27 while browsing for it on the
local network; `system_profiler SPUSBDataType` contains no iPhone or Apple
Mobile Device entry. A bounded Bonjour browse for `_apple-mobdev2._tcp` also
found no iPhone service. The JetKVM-observed Developer portal returned “Not
found” for “Media Device” in both the App ID Capabilities and Capability
Requests tabs.

The separate `SonanceEQRouteInstaller` scheme and embedded Media Device
extension compile for generic iPhoneOS with signing disabled. That build exposed
and fixed a missing `ExtensionFoundation` import and a timer callback's
MainActor isolation warning. Both route App IDs exist, but their profiles have
an empty `com.apple.developer.media-device-extension` entitlement. The Apple
Developer portal exposes only the older Media Device Discovery capability; its
Capability Requests tab has no request entry for the new entitlement. A fresh
JetKVM screen inspection on 2026-11-25 confirmed “Media Device” is not found
under either App ID Capabilities or Capability Requests.

## Apple route architecture and limits

Apple requires the Media Device entitlement on both the route extension and a
separate container app whose only purpose is to deliver/install that extension.
That is why the project contains a small `Sonance EQ Route` installer alongside
the full Sonance EQ host. The installer must be present before Sonance EQ can
appear as a Control Center output. The host app itself contains the chain editor,
Sonance EQ Audio Unit, share extension, import workflow and DSP processing.

The full host and Share extension require the App Group
`group.com.isaiahdupree.SonanceEQ`. On 2026-11-24 the group was assigned to both
App IDs in the Apple Developer account; Xcode regenerated the profiles and the
signed host and Share extension now carry that entitlement. Host install and
launch are verified on iPhone 15; shared-container runtime verification is
still pending. The route installer separately needs Apple's Media Device
capability and a matching profile. The Developer portal lists both route App
IDs but only exposes the older Media Device Discovery capability; the new
Media Device extension entitlement is absent from its standard capability and
request lists, and local profiles contain an empty entitlement array. No route companion was installed from this
branch. The installed host asks the user to select the Sonance EQ Control
Center output and install Sonance EQ Route if it is absent. Since the route
extension cannot yet be installed, system playback through that route is not
available or verified from this build.

This Media Device workflow is experimental until Apple grants the entitlement
and the signed route is validated on the phone. It follows Apple's documented
Control Center media route model; do not claim arbitrary capture of other apps
or games, per-app routing, or a proven Bluetooth return path. System routing,
standalone file playback and compatible-host AUv3 use are separate audio paths
and need separate evidence.

### Source-player compatibility and CarPlay fallback

The Media Device route is opt-in per source app: a player must use Apple's
AVSystemRouting API before iOS can send its audio to this route. The supplied
SoundCloud screenshot shows the player rejecting “EffectDeck Audio” while
iPhone Speaker is selected and CarPlay is available. That refusal belongs to
the source app; Sonance EQ cannot read SoundCloud's private alert, force iOS to
select a route, or make an incompatible source stream. The host reports when no
audio has reached its chain, the current output when available, and the last
observed AVAudioSession transition. Three or more transitions within a rolling
30-second window produce a route-instability warning with the last four route
transitions and system reasons. Car audio is reported as a direct output with EQ bypassed, not
as an EQ processing failure. The no-audio message now explains that route
support is controlled by the source and iOS, and tells users to stop retrying
after an unsupported-route alert: keep CarPlay selected for car audio, or use
local playback / a source that supports system routing for EQ. Physical
route-bounce verification remains pending because the phone became unavailable
to Xcode during the physical test attempt and the separate route companion lacks
its Apple entitlement.

Apple documents that source apps use `AVSystemRoute` to start playback and that
the system delivers real-time samples only after a source app starts a route
session: [Creating a Media Device Extension](https://developer.apple.com/documentation/MediaDevice/creating-a-media-device-extension).

## Build and next validation

Regenerate the host project from its tracked spec:

```bash
bash iOS/Tools/generate-sonance-host-project.sh
```

The generated project is in the vendored checkout and ignored. The tracked
source of truth is `iOS/sonance-host.project.yml` plus
`iOS/HostConfig/apply-upstream-adaptation.py`. Homebrew Python 3.11 or newer is
required for the upstream asset generator.

The install script builds, installs and launches the full host independently:

```bash
bash iOS/Tools/install-on-test-iphone.sh
```

The host and Share extension now have matching App Group profiles. Verify the
chain editor and stage routing, run the audio-quality and AUv3 lifecycle
suites, and capture separate evidence for direct Bluetooth playback, the host
with an empty chain, the host
with Sonance EQ flat, and the controlled EQ configuration. Record unavailable
counters as unknown. Clean up only the tested Sonance app bundle IDs after the
assigned physical testing is complete.

Control Center output routing is a separate, optional installation step:

```bash
SONANCE_INSTALL_ROUTE_COMPANION=1 bash iOS/Tools/install-on-test-iphone.sh
```

It requires Apple's Media Device entitlement and matching profiles for the
route extension and installer. That requirement no longer blocks installing
the full host or using its in-app chain routing screen.

## Licensing and references

EffectDeck host source is MIT-licensed. Keep the upstream license and all
bundled DSP/runtime notices with the vendored source, and retain the local
adaptation disclosures. The app is an independent project and is not affiliated
with or endorsed by EffectDeck or its author.

- [EffectDeck source](https://github.com/satomasahiro2005/EffectDeck)
- [EffectDeck license](https://github.com/satomasahiro2005/EffectDeck/blob/main/LICENSE)
- [EffectDeck feature listing](https://apps.apple.com/app/effectdeck/id6812467517)
- [Apple Media Device entitlement requirements](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.media-device-extension)
- [Apple App Groups capability setup](https://developer.apple.com/help/account/identifiers/enable-app-capabilities)

## CarPlay route handoff diagnosis — 2026-11-25

The host records route endpoints and iOS change reasons, preserves the last
30 seconds across a quick relaunch, and calls out repeated CarPlay ↔ Sonance EQ
handoffs separately from CarPlay ↔ iPhone speaker transitions. The classifier
also recognizes a connected three-transition handoff through the iPhone
speaker, and rejects disconnected route records. Its Foundation-only behavior
check passes, including persistence compatibility. The focused XCTest suite
could not launch because the available simulator is iOS 26 while the host test
target requires iOS 27. Signed host build 28 predates this classifier change and
is not installed because the exact iPhone 15 currently reports unavailable to
Xcode; a physical CarPlay reproduction remains outstanding.

The supplied SoundCloud screenshot explicitly rejects “EffectDeck Audio.” That
is source-app route rejection, which Sonance EQ cannot override. Use CarPlay
directly for that playback, or choose a compatible player/local file when EQ is
required. The detector diagnoses and explains the handoff; it cannot force iOS
to keep an unsupported route.
