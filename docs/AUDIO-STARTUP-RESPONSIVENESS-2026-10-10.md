# Responsive route startup and cancellation

The next ready Sonance revenue prerequisite is current-device first use. Current
research and prospective production placement remain separately blocked. This
repair addresses a reproduced startup hang; it does not establish audibility,
successful acquisition, a purchase or an App Store release.

## Observed failure

Two retained 1.0.6/build 9 hardware runs stopped progressing at `starting_tap`.
The retained process sample places the main thread in `SystemAudioTap.build` →
`AudioDeviceStart` → Core Audio server IPC. The same system sample places Core
Audio inside a synchronous TCC access request and user TCC inside
`CFUserNotificationReceiveResponse`. Another client request waits behind the
first TCC request. This supports an unanswered permission-notification wait;
it does not identify the original requesting app or prove a device-driver fault.

The old callback watchdog was armed only after `AudioDeviceStart` returned.
While that call waited, the main thread could neither process Stop nor run the
watchdog. A separate retained CLI probe also waited in Core Audio stream-usage
IPC; a CLI probe is not shipping-app acceptance.

The original samples, exact build hashes and unfinished hardware receipts stay
outside Git in `~/Library/Caches/SonanceEQ/HardwareProof-20261010/` and the daily
revenue assessment receipts. Historical `status=running` is not a live process
or a passing test.

## Implemented behavior

Route creation, output rebuilds, listener ownership and destruction use one
serial worker. Main-actor intent, immutable route snapshots and the existing
callback watchdog drive the window. Startup returns immediately and reports
its actual result asynchronously; the normal Stop control remains usable.

Stop invalidates route intent and the callback deadline. Cancellation is checked
between OS operations and after the worker returns. A late success cannot make
the cancelled route Active, including cancellation while its completion waits
on the main queue. Rebuild requests during setup coalesce into the latest target;
both worker and main-actor generations reject old device notifications.

A ten-second main-queue deadline reports a localized routing error. The slot
remains occupied until the blocked OS call and serialized cleanup actually
finish. The UI shows `Finishing audio routing…` and disables another Start while
stopped cleanup is pending. It retains the existing route controller rather
than creating a second capture pipeline. No background retry or unbounded worker
pool is introduced. All three new messages are in the nine shipping catalogs.

The actual development-window check also exposed a pending-permission UI gap:
Start returned while the window still said Stopped/Start EQ. A pending permission
request now retains Start intent, exposes Stop and shares the ten-second user
deadline. Stop invalidates its generation. A delayed grant can update permission
state, but cannot restart cancelled intent; another request is withheld until
the original reply arrives. No test automatically grants a permission.

This does not interrupt a Core Audio IPC or guarantee that an OS destruction
call succeeds. It does not grant/reset Audio Capture permission, dismiss another
app's notification or restart the shared Core Audio daemon. Callback delivery
continues to mean processing, not audible audio or proof of a purchase.

## Validation

`AudioRouteOperationTests` uses actual serial/main queues, clock deadlines,
semaphores and a genuine missing-file error. It verifies responsiveness,
single-operation admission, cancellation, cleanup ordering, deadline expiry,
late completion, preserved errors and stale-deadline rejection. It substitutes
no Core Audio implementation or provider. Hardware routing remains a separate
acceptance condition.

The second focused selection passed 27 tests, zero failures/skips, covering the
operation, callback watchdog, AppState and shipping localization. Subsequent
source adjustments retain the same tests; the required full pre-commit test
hook validates the final source. Exact result bundles and logs remain outside
Git under `/tmp/sonance-startup-focused-20261010*`.

The remaining acceptance is a reproducible signed current artifact, its observed
existing capture authorization, and a bounded callback/stop/restart/output-switch
run on attached hardware with human audibility confirmation. Built-in, wired,
Bluetooth and interface results must be recorded separately; unavailable devices
remain untested. A development entitlement is not a production Pro transaction.

Apple's [Core Audio tap documentation](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps)
describes capture permission and aggregate lifecycle. Its
[responsiveness guidance](https://developer.apple.com/documentation/xcode/improving-app-responsiveness)
recommends keeping blocking work off the main thread. The specific wait chain
above comes from the owner's retained sample, not an inferred Apple API guarantee.
