# Sonance EQ for Windows and Linux

Owner scope, November 6, 2026: core system-wide EQ, headphone presets, preamp and
bypass first. Mixer and recorder are outside this first release. The existing Mac
product is Sonance EQ (`EqualizerForMac`); “Sonity Q” refers to that product here.

## Feasibility and current delivery

Both ports are technically feasible, but the SwiftUI/Core Audio application
cannot be recompiled unchanged for either OS. Its UI, system capture/reinjection,
Accelerate DSP, route watchdogs, Apple purchase handling and packaging are tied to
Apple platforms. The original filter mathematics, portable preset format,
headphone correction database and product identity can be reused.

This branch implements a portable C++17 IIR core and real preset/database tools
in [`portable/`](../portable/README.md), plus a shared Qt desktop preset editor.
Its Windows and Linux core builds pass on Orion, including sanitizer profiles.
The desktop preview edits real presets and calculates the actual native response;
it does not process system playback. No Store submission has been produced.
Windows Store eligibility remains contingent
on the finished app, its audio installation model and Microsoft's certification.

The owner-confirmed v1 includes:

- System-wide stereo EQ on explicitly supported outputs.
- Graphic/parametric editing using the existing eight filter shapes.
- Searchable existing AutoEq headphone corrections, retaining attribution.
- Preamp, bypass/A-B and existing v1 preset import/export.
- Output selection, startup/stop recovery and restoration of normal playback.

Per-app routing/EQ, recording, FIR, Mid-Side, legacy PulseAudio support and broad
hardware/architecture coverage are subsequent work. An early core milestone
does not establish feature parity with the entire Mac product.

## Platform architecture

| Layer | Windows candidate | Linux candidate | State |
|---|---|---|---|
| Equalizer math | Original C++17 biquad cascade | Same original core | Orion Windows/Linux core builds and sanitizer profiles passed |
| Presets | Existing v1 JSON and AutoEq SQLite data | Same files | Real database tests passed on both platforms |
| System processing | User-mode endpoint-effects APO with supported installation package | PipeWire virtual sink/processing node | Not implemented |
| Controller | Qt desktop editor, with a separate audio component still required | Shared Qt editor, with a PipeWire node still required | Preset editor implemented; playback not connected |
| Live changes | Validated snapshots and smooth transitions outside the callback | Same discipline | Not implemented |
| Purchases | Windows-appropriate entitlement/checkout flow | Direct-sale entitlement flow | Not implemented; no price set |
| Release | Signed offline EXE/MSI candidate; evaluate MSIX controller only with valid separate audio delivery | Native Linux package first; additional formats after testing | Unsigned editor previews; no audio installers |

The editor uses PySide6 Essentials 6.10.2 with dynamically linked Qt libraries.
The DSP remains independent of the GUI, purchase SDK and device API. The native
audio proof still determines the final deployment requirements. Existing
Apple StoreKit/RevenueCat entitlements do not automatically license a PC build.

### Windows: prove the processing and installation path first

[WASAPI loopback](https://learn.microsoft.com/en-us/windows/win32/coreaudio/loopback-recording)
captures audio already being rendered. Inference from that behavior: replaying an
equalized loopback stream alone does not replace the original system output and
can duplicate audio or create feedback. It is not a complete system-wide EQ.

Microsoft supports [custom APOs](https://learn.microsoft.com/en-us/windows-hardware/drivers/audio/audio-processing-object-architecture),
which execute DSP in the Windows audio engine. An APO is a user-mode COM DLL,
not necessarily a new kernel-mode driver. The documented installation route uses
an INF/driver package; configuration UI is separate. Its real-time methods must
be nonblocking. See [APO implementation](https://learn.microsoft.com/en-us/windows-hardware/drivers/audio/implementing-audio-processing-objects)
and [deployment classes](https://learn.microsoft.com/en-us/windows-hardware/drivers/dashboard/deploying-audio-processing-objects).

First qualify an original APO on one declared Orion output and prove reversible
installation without replacing unrelated vendor effects. Inspect the existing
endpoint graph and supported association mechanism. Do not assume arbitrary
Realtek, USB, HDMI, Bluetooth, RAW, exclusive or protected streams are covered.
If a supported APO association cannot meet the compatibility target, evaluate an
original virtual endpoint and its separate driver/signing burden before promising
that hardware. No third-party paid driver or commercial SDK was selected.

Acceptance must include silence/bypass behavior, finite output, stopped-stream
configuration, smooth parameter updates, device invalidation/reconnect, reboot,
sleep/wake, crash recovery and clean rollback/uninstall. A DSP unit test cannot
validate audibility, latency or compatibility.

### Linux: PipeWire first

[PipeWire streams](https://docs.pipewire.org/page_streams.html) support virtual
audio sinks and processing callbacks. Its [filter-chain module](https://docs.pipewire.org/page_module_filter_chain.html)
also supports configurable biquads and raw coefficients. These are viable native
processing mechanisms; no macOS process-tap equivalent needs to be ported.

Implement a Sonance stereo sink and explicitly connect its processed output to a
physical output. Select it and move existing application streams only when the
user starts EQ. Preserve and restore the prior default; exclude Sonance's own
sink from output choices to prevent recursion. Test session-manager behavior,
device removal, rate changes, Bluetooth switching and process exit on an actual
PipeWire desktop. WSLg audio alone does not prove a Linux desktop release.

Start qualification with one declared Linux distribution/desktop and package the
actual native dependencies. Do not claim every Linux distribution or ship an
AppImage/Flatpak label before runtime dependencies and routing permissions work.

## Microsoft Store route

Owner update, November 7: use **JetKVM** for store account access and publishing,
with builds and checks on **Orion**. The [store publishing runbook](STORE-PUBLISHING.md)
records the observed account state, Windows package-signing distinction and
Linux storefront requirements.

Microsoft Store supports both MSIX desktop apps and traditional EXE/MSI apps.
There are two materially different delivery paths:

| Route | Microsoft behavior | Consequence for Sonance |
|---|---|---|
| MSIX | Store hosts and re-signs the app package after certification | Good for a self-contained controller, but not a way to install an audio driver |
| EXE/MSI | Publisher supplies a signed, standalone silent installer at an immutable versioned HTTPS URL | Candidate for a complete desktop/audio installer, subject to certification and driver requirements |

[MSIX does not support drivers](https://learn.microsoft.com/en-us/windows/msix/packaging-tool/know-your-installer).
[MSIX Store signing](https://learn.microsoft.com/en-us/windows/apps/publish/faq/get-started-with-the-microsoft-store)
does not replace signing or delivery requirements for a separate audio component.
[EXE/MSI requirements](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msi/app-package-requirements)
require the installer and its PE files to carry a trusted certificate; setup must
work offline and silently (UAC is allowed). That route does not provide installer
hosting. Packaging alone does not guarantee that a particular audio design passes
certification.

Use the native audio proof to choose between those routes. Before selecting a
paid certificate/signing service, inspect existing owner signing assets and the
exact app/driver policy. No certificate, cloud signing, hosted build, add-on or
new hosting expense is authorized by this branch.

Current [developer onboarding](https://learn.microsoft.com/en-us/windows/apps/publish/partner-center/open-a-developer-account)
offers free Individual and Company registration through the new Store entry
flow. This does not remove identity/business verification or guarantee that an
existing account has the necessary publishing rights. No owner Partner Center
session, reserved product name or certificate was verified in this audit.

[Submission requirements](https://learn.microsoft.com/en-us/windows/apps/publish/publish-your-app/msi/create-app-submission)
include a verified publishing account, product name, package/installer, listing
assets, age ratings and appropriate privacy/support information. Capture actual
Windows screenshots and describe only qualified hardware/features. Resolve the
checkout/entitlement and pricing decision before enabling paid distribution.

## Build and release gates

1. **Portable behavior:** compare the original C++ math with shipping Swift;
   verify real sample processing, boundaries and actual headphone preset files.
2. **Native Orion build lane:** the portable-core `software.sonance_core` lane is
   registered and verified for Windows/MSVC and Ubuntu WSL2/GCC, with bounded
   build/test actions and hashed artifacts. Extend the declared source/build
   profile when the actual desktop apps and audio components are implemented.
3. **Windows audio proof:** install/rollback an original APO on a declared output,
   retain real audio/latency observations and decide the complete packaging model.
4. **Linux audio proof:** run an actual PipeWire sink and verify routing and
   restoration on a supported desktop.
5. **Core desktop apps:** the editor, headphone search, preset operations and
   preamp/bypass response controls are implemented. Connect them to actual audio
   processing, device lifecycle handling and smooth live parameter changes.
6. **Release candidates:** qualify install, upgrade and uninstall; produce signed
   Windows and native Linux packages; implement real licensing and retain notices.
7. **Store submission:** verify account/product identity, signing, package route,
   listing and commercial terms, then submit the actual qualified Windows build.

The initial shared Orion worker inventory did not contain a Sonance build lane.
The follow-up owner request to build/test on Orion added a task-scoped copied
runtime and registered the exact source/toolchain profiles. Four core build/test
jobs passed; the shared Orion controller was preserved. That initial milestone
did not build a desktop application or qualify hardware audio. Details and
artifact hashes are in the [core report](reports/ORION-CORE-BUILD-2026-11-06.md).
The subsequent desktop editor work is described in the
[UI guide](DESKTOP-EDITOR.md) and [Orion UI report](reports/ORION-DESKTOP-UI-2026-11-07.md).

The strategy capability packet returned `research_required` in capability-audit
mode. It supplies no current Windows/Linux demand, pricing or revenue validation.
This engineering feasibility finding does not imply validated market demand or a
Store approval. Source references above were checked November 6, 2026.

## Initial validation

- 5,278 C++ DSP assertions passed on the Mac host, including real sine/impulse
  processing, callback block boundaries, channel isolation, bypass history and
  invalid-input rejection.
- 1,584 coefficient cases matched the actual shipping Swift implementation
  within the comparison tolerance; maximum absolute coefficient difference was
  approximately 1.12e-7.
- Six presets round-tripped through the shipping Swift encoder/decoder,
  including all five built-in presets and an actual bundled headphone correction.
- Five Python integration tests passed against the existing read-only database.
  Its actual row count is 8,850; that count does not mean every correction has
  been individually qualified on new hardware.
- The existing Mac project's normal pre-commit test gate passed with zero
  failures and 16 reported skips. The initial uncached attempt could not resolve
  RevenueCat; the hook's documented pinned-cache path succeeded with the actual
  5.102.0 checkout at `193efe58cf61f9d59da4076dd394490ae59e86a9`, automatic package
  resolution disabled and one build job. No tests were removed or excluded by
  this change. This is Mac regression coverage, not Windows/Linux qualification.
- Address/undefined-behavior sanitizer execution timed out twice at 60 seconds.
  A separate minimal sanitizer program also exceeded its five-second limit.
  The initial **Mac sanitizer coverage** was not verified. The subsequent Orion
  sanitizer profiles passed; the original Mac timeout receipt is retained.
  No failure was removed from the test suite.

These initial results and the later Orion builds establish the portable library
milestone. The desktop preset editor extends that work. Real system-audio output,
smooth live audio editing, licensing, install/uninstall and Store certification
remain open.
The initial host verification receipt is in
[`reports/WINDOWS-LINUX-CORE-2026-11-06.json`](reports/WINDOWS-LINUX-CORE-2026-11-06.json).
