# Sonance Route Lab

An **unverified, debug-only research target** for the iOS 27 Media Device
experiment. This is separate from Sonance EQ and does not yet use its equalizer.
It advertises a route, accepts the route's stereo PCM through an audio server
driver, sends it to the container over localhost, and applies an adjustable
one-pole low-pass filter before playback. The user selects the route explicitly.
This is a source implementation, not a claim that the route works on any device.

## Current restrictions

- Do not distribute this target. Release builds intentionally fail. Apple
  documents a hardware-oriented extension and entitlement for both app and
  extension; its developer agreement also contains applicable purpose limits.
  The reference uses an empty container entitlement for local playback. Its
  relationship to Apple's current requirements and review has not been resolved.
- The loopback TCP link does **not authenticate either peer**. Another
  local app may be able to impersonate a peer or receive audio. End-to-end
  thread-safety, extension isolation and privacy require an independent audit
  and a validated authenticated transport before using private audio or shipping.
  Do not install or route private material through this experiment as-is.
- A different output sample rate is rejected rather than silently playing 48 kHz
  samples at the wrong speed. A route-name check stops an apparent feedback loop;
  that check is best-effort and has not been validated on an iPhone.
- No real-device testing has been done. App compatibility, Bluetooth, AirPlay,
  background behavior, interruptions, latency and battery use remain unknown.

## Origin and changes

The source is adapted from [ios27-media-device-passthrough](https://github.com/satomasahiro2005/ios27-media-device-passthrough)
at commit `0ed6091ec6e82d5aa9fb4320bef7a083260f6a0f`, under the license in
[UPSTREAM-LICENSE](UPSTREAM-LICENSE). The bundle, protocol, endpoint port,
device UUID and display name are distinct from the upstream. This branch adds
debug-only distribution guards, a C11 atomic cutoff, refusal of mismatched
sample rates, a best-effort output loop stop, and bounded single-producer /
single-consumer audio queues. When full, the queues drop incoming frames instead
of overwriting frames being read. Sender and receiver drop counts and receiver
underruns are recorded. These changes have not been compiled against iOS 27 or
tested on-device.

## Local checks

`bash iOS/RouteExperiment/Tests/verify-low-pass.sh` compiles the actual filter
and atomic parameter on the Mac. It tests low/high-frequency attenuation,
stereo parity and rejection of a non-finite cutoff. It does not exercise the
extension, network link, operating-system routing, or audio session.

`bash iOS/RouteExperiment/Tests/verify-local-link.sh` exercises the real sender
and receiver over a temporary localhost connection on the Mac. It checks stereo
samples, reconnects, non-finite samples, underruns, bounded overflow and loss of
the receiver while sending. It does not establish peer authentication, bounded
latency or behavior in the iOS extension sandbox.

`bash iOS/RouteExperiment/Tests/verify-audio-ring.sh` checks the queue's capacity,
wrap, mono conversion, discard and 100,000 concurrent stereo frames. The test
can be run with `ROUTE_TSAN=1` on a Mac with a working Thread Sanitizer runtime.
On this Mac, the sanitizer process itself crashes, including for an empty C
program; this is not a sanitizer pass.

Both audio-ring and local-link checks also passed on the Mac with Undefined
Behavior Sanitizer using `ROUTE_UBSAN=1`. Address Sanitizer did not complete its
empty-program probe on this Mac, so it was not used for the real tests.

`bash iOS/RouteExperiment/Tests/verify-tls-psk.sh` is a separate, loopback-only
Network.framework feasibility test. It generates a fresh random key and data,
checks the negotiated TLS 1.2 PSK cipher, verifies correct-key delivery, and
checks that wrong-key, plaintext and impostor-server connections do not deliver
the payload. It passed on this Mac on 2026-11-21. This test is **not connected**
to the route lab's current socket, does not test Keychain sharing or the Media
Device sandbox, and does not establish production readiness. The tested
TLS-PSK cipher does not provide forward secrecy.

Apple documents [keychain access groups](https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps)
and [Network.framework's PSK limitations](https://developer.apple.com/documentation/technotes/tn3213-moving-from-multipeer-connectivity-to-network-framework).
A candidate design is to generate a per-install key, share it between the two
signed targets through Keychain, and use a reviewed authenticated encrypted
transport. Extension access, key lifecycle, handshake failure behavior,
real-time performance and the applicable Apple terms all remain to be tested.

On 2026-11-21, the filter, link and audio-ring checks passed on the Mac.
XcodeGen generated the project, Swift sources passed syntax parsing,
property lists validated, and the localhost and atomic C sources passed an
iOS 26 SDK syntax check. The iOS 27 target could not be built: this Mac has
Xcode 26.0.1 and no iOS 27 SDK. None of these checks validates device routing.

With Xcode 27 and the iOS 27 SDK installed side-by-side, generate the project:

```sh
xcodegen generate --spec iOS/RouteExperiment/project.yml --project iOS/RouteExperiment
DEVELOPER_DIR=/path/to/Xcode27.app/Contents/Developer xcodebuild \
  -project iOS/RouteExperiment/SonanceRouteLab.xcodeproj \
  -scheme SonanceRouteLab -configuration Debug -destination 'generic/platform=iOS' \
  -jobs 1 CODE_SIGNING_ALLOWED=NO build
```

The local test bundle is `com.isaiahdupree.SonanceEQ.RouteLab`; its extension is
`com.isaiahdupree.SonanceEQ.RouteLab.MediaDevice`. A device experiment requires
the exact Media Sharing Protocol identifier and compatible profiles for both
targets, the designated iPhone 11, a scoped test plan, and the privacy and
transport issues above. After all testing, remove the exact test app and verify
it is absent. Never select another phone automatically.
