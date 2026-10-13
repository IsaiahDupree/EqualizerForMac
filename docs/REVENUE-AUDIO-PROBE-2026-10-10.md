# Audio callback diagnostic repair — October 10

The revenue plan's current-device evidence remains open. The standalone process
tap diagnostic previously returned success when AudioDeviceStart succeeded even
if no callbacks arrived, read its counter concurrently, and ignored cleanup
statuses. It now drains the serial callback queue, requires positive callback
delivery, checks cleanup, and explicitly withholds audibility/shipping-app claims.
The counter is retained until process exit if stopping/destroying the IOProc fails.

The updated source compiled successfully using the documented arm64/macOS 14.4
command. A real unsandboxed invocation on macOS 26.6.1 did not complete. A process
sample located the wait inside AudioDeviceCreateIOProcIDWithBlock, specifically
the Core Audio server stream-usage property IPC. The diagnostic was terminated
with SIGTERM; there was no success result. The sample is private at
`/tmp/sonance-revenue-probe-sample-20261010.txt`.

This establishes a diagnostic hang, not its root cause or failure of the shipping
application. No coreaudiod restart, audio-device changes, permission bypass or
App Store release was performed. Built-in/wired/Bluetooth/interface audibility,
current-app first use, stop/restart and route-switch acceptance remain unverified.

Next device check: inspect the current default output and existing Core Audio
device state, then run the actual current app with a bounded audio callback and
operator audibility observation. Do not represent this CLI result as product proof.

The required pre-commit Xcode test hook was attempted but failed during RevenueCat
compilation with `No space left on device`; tests were canceled and the commit
was aborted. The hook was not bypassed. Changes remain local, not pushed or
deployed. Storage recovery is required before the full test/commit acceptance.

Follow-up at 15:05 Eastern: available disk recovered without this agent deleting
files. The required serial Xcode hook passed: 256 test functions, 4,227 runs,
zero failures, seven opt-in functions skipped. Source commit `522acad` contains
the diagnostic repair. This closes source/test acceptance only; the live probe
hang and device/audibility evidence remain open. No App Store deployment occurred.
