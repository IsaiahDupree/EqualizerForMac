# Bounded native startup evidence

The retained authorized global-tap tests stalled inside startup. Their Swift
Testing deadline could not preempt the synchronous Core Audio call on the test
host's main thread. A `running` checkpoint is incomplete evidence, even after
Xcode exits. The existing production watchdog is armed after startup returns;
this diagnostic change does not repair that audio-service stall.

`Tools/bounded_audio_probe.py` supervises the existing opt-in
`SystemAudioHardwareTests`, using a real, separately built native test runner.
It injects a unique run ID. The native test records that ID, its PID and binary
hashes before checking the existing capture permission. It still fails before
capture if its actual signed host has no observable authorization; it never
requests a permission. `SystemAudioTap.onLifecycleStage` records the last
control-plane operation before each Core Audio startup call. The real-time
render block and audio routing behavior are unchanged.

The external deadline defaults to 45 seconds and cannot exceed 90. The
supervisor samples the matching host once and, if necessary, stops only that
host and its own Xcode runner. A new native receipt, matching nonce, exact
executable hash and unchanged live PID birth identity are all required before
host termination. Existing receipts, another app, a symlink or a changed
process identity cannot authorize termination. The supervisor does not edit the
native receipt, request permission, switch outputs, restart Core Audio or run
another publisher/scheduler. The existing native hardware test remains the
only output-switch/restore owner.

Build with XcodeGen and the existing pinned packages, using bounded concurrency:

```sh
xcodegen generate
xcodebuild build-for-testing -project SonanceEQ.xcodeproj \
  -scheme SonanceEQ-AudioHardware -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -jobs 1 \
  -parallel-testing-enabled NO -derivedDataPath <private-derived-data> \
  'OTHER_SWIFT_FLAGS=$(inherited) -j1'
```

Reuse an existing approved signing identity when needed; creating a new grant
or signing credential is outside this diagnostic. Run against clean committed
source and the actual corresponding signed app, retaining build logs and hashes:

```sh
python3 Tools/bounded_audio_probe.py \
  --xctestrun <private-derived-data>/Build/Products/SonanceEQ-AudioHardware_macosx26.0-arm64.xctestrun \
  --app <private-derived-data>/Build/Products/Debug/SonanceEQ.app \
  --output <new-private-observation-directory> --deadline 45
```

The supervisor source revision identifies the diagnostic source used at launch;
it does not independently certify which source produced a supplied app. The
actual version/build must match the source manifest, signatures must verify,
and build provenance must remain linked separately. Supervision completion,
host termination or a passing native regression suite does not prove sound,
native cleanup, storefront release acceptance, purchases or profit. If the
native receipt is incomplete, native cleanup stays unknown until an independent
real device observation. Preserve the original failure and its scope.

Process supervision tests use actual macOS child processes and filesystem
receipts; they do not replace Core Audio or simulate a provider. Set
`SONANCE_NATIVE_XCTESTRUN` and `SONANCE_NATIVE_APP` to the actual compiled
artifacts to additionally verify native runner binding. Missing artifacts are
reported as skips.
