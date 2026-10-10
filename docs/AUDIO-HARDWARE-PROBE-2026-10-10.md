# Global-tap hardware observation

The opt-in `SonanceEQ-AudioHardware` scheme exercises the shipping
`SystemAudioTap` on the Mac's actual attached outputs. It starts the global
route, checks current-route callbacks, switches up to three alive physical
outputs, checks rebuild callbacks, stops, restores the original output, and
restarts. Ordinary tests leave this hardware suite disabled.

The probe acquires an audio-route file lock and rejects another running Sonance
audio app before starting a second global tap. It records the host, test bundle
and debug library SHA-256 hashes, OS, device inventory, callback observations and
cleanup results. It does not record audio or request capture permission.

## Run

Generate the project with `xcodegen generate`, then run one native test process:

```sh
xcodebuild test -project SonanceEQ.xcodeproj -scheme SonanceEQ-AudioHardware \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -jobs 1 -parallel-testing-enabled NO \
  -only-testing:SonanceEQTests/SystemAudioHardwareTests OTHER_SWIFT_FLAGS='-j1'
```

The current signed test host must already have Audio Capture authorization.
An ad-hoc rebuild can invalidate a prior grant when its code hash changes.
`AudioRecordingPermission.supportsPreflight` distinguishes a real preflight
from the App Store configuration's public prompt path. If preflight is absent
or the grant is unavailable, the hardware test fails before starting capture.
Do not interpret the public path's assumed status as observed authorization.

The scheme launches without a debugger and explicitly enables
`SONANCE_AUDIO_HARDWARE_TESTS`. Debug/direct permission observation does not
validate the Mac App Store first-run permission flow.

## Evidence and interruption

Each run checkpoints a private JSON receipt under
`~/Library/Application Support/SonanceEQ/RouteProofs/`. The directory is mode
0700 and receipt files are mode 0600. Its contract is
`sonance_system_audio_hardware_observation_v1`.

`process_id`, `stage` and `updated_at` identify the owner and last checkpoint.
Verify that the PID is still alive with the recorded executable before operating
on a run; a retained `running` receipt does not establish process liveness.
`status: running` means
the run is incomplete, including a synchronous Core Audio call that outlives
the test's one-minute allowance. Only a completed `status: succeeded` receipt
can support the callback/cleanup scope. A failed or interrupted run is not
converted into success. Receipt-write failures cannot bypass route cleanup.

Normal completion restores the original default output if the probe still owns
the route, and verifies that its private aggregate inventory matches the
baseline. An external output change is preserved and reported as a cleanup
failure. Private device lifetime also ends with its owning test process; an
interrupted receipt alone does not prove cleanup.

## Observed validation

On October 10, 2026, the first internal-SSD run executed one test and timed out.
Its retained stack trace was inside `SystemAudioTap.start()` →
`AudioDeviceStart`. macOS also reported an Audio Capture code-requirement
mismatch for the ad-hoc host and a capture authorization prompt. That run
produced no completed receipt and remains failed.

After adding preflight and checkpoints, a second real run executed one test,
failed promptly with `audio_capture_permission_required_for_this_signed_build`,
and wrote receipt `187D52B7-0345-4A2E-A737-A75C488AF1CA.json`. The receipt has
three actual binary hashes, permission `unknown`, no callback observations and
no claimed audio/output changes. The hardware run is not a pass.

A third run used the owner's existing Developer ID identity without changing
permission settings. Its actual preflight was available and `authorized`, but
the one executed test again timed out. Checkpoint
`25CDAAB9-555F-4567-B636-C04507DA0E03.json` retained `status: running` at
`stage: starting_tap`, the attached device inventory and three binary hashes.
This shows the startup stall persists after authorization; permission mismatch
alone does not explain it. No callback or output-switch success was observed.
Core Audio logged deactivation of that host's private aggregate after test-host
exit; the system's default output remained Mac mini Speakers. That observation
does not turn the interrupted receipt into a completed cleanup pass.

A fourth run again passed permission preflight and timed out at
`starting_tap`, retaining receipt `F40F3272-6071-4685-B4ED-39F9C0D5C829.json`.
The attempted external system-sound diagnostic began at 08:19:33 UTC, after
the Xcode run had finished at 08:19:32 UTC. It is invalid as startup evidence;
neither quiet-source nor active-source behavior is established by that attempt.
All original failures and the invalid diagnostic remain preserved privately.

The normal pre-commit suite passed 256 methods / 4,227 runs with no failures.
Its eight disabled methods were the seven existing opt-in StoreKit methods and
this opt-in hardware method. This regression pass does not supersede the failed
hardware gate. An initial fresh-worktree SDK checkout failed; the hook now
accepts optional `SONANCE_SOURCE_PACKAGES_DIR` and `SONANCE_DERIVED_DATA_DIR`
paths, preserving the same pinned SDK and full test selection. That cache path
was used for the successful run. Swift compilation remains bounded to one job.

## Acceptance boundary

The receipt always keeps `audibility_verified`, `audio_samples_saved` and
`app_store_release_verified` false. Callback delivery can include silence;
this does not prove sound heard by a user, nonzero source audio, frequency
response, a store-signed release, Bluetooth/Scarlett compatibility, or the
reported MacBook hardware combination. The current Mac has built-in speakers,
DisplayPort/HDMI outputs, JetKVM USB playback and a virtual Immersed device;
virtual and non-alive outputs are excluded from switching.

SON-07 remains subject to the actual current-build first-run, audible-output
and physical-device checks in [the route lifecycle report](AUDIO-ROUTE-LIFECYCLE-2026-10-09.md).
