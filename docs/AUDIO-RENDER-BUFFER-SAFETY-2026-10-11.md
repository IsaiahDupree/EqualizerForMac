# Audio render buffers and truthful startup health

The global tap previously incremented its route heartbeat for every IOProc callback,
including callbacks with empty or absent audio buffers. The planar Mid-Side path
also derived its processing length from the left buffer alone, allowing it to read
and write beyond a shorter right buffer. Large blocks could skip Mid-Side/FIR DSP
while still reporting success because their scratch storage has a fixed capacity.

The IOProc now calls one shared `AudioBufferRouter`. Before copying or processing,
it requires a nonempty matching Float32 layout, aligned pointers, complete frames,
matching input/output channel counts and byte sizes, equal planar frame counts,
and at most the engine's eight supported channels. An unsupported callback clears
only the advertised writable output regions and supplies no success heartbeat.
Persistent invalid startup callbacks therefore follow the existing watchdog's
failure/Stop cleanup path. Supported input is processed in chunks bounded by the
same scratch capacity as the Mid-Side and FIR engines.

The router introduces no audio-thread allocation, remote telemetry, account or
campaign identifier. It preserves valid digital silence: complete zero-valued
buffers prove delivery, not audible sound. The watchdog remains a startup check,
not a continuous health monitor. Device format conversion and previously unsupported
input/output layouts are not added by this repair.

## Verification

`Tests/AudioBufferRouterTests.swift` runs the actual router, DSP and heartbeat with
real `AVAudioPCMBuffer` allocations. Computed test tones exercise mono, interleaved,
planar and eight-channel layouts, Mid-Side gain and FIR delay/gain, including blocks
larger than scratch capacity. Boundary cases verify missing/empty/unaligned buffers,
partial frames, channel mismatches, a shorter right buffer, and output-region guards.
Input bytes remain unchanged. Invalid buffers cannot increment the heartbeat.

The same checks are available to the normal native test scheme and a bounded
standalone Address Sanitizer build, without opening a physical audio device:

```sh
/bin/zsh Tools/verify_audio_buffers.sh
```

CI runs the sanitizer check before its existing native build and tests. This is
software render-path evidence only. Current-build capture permission, actual-device
audibility, live purchase attribution and distribution acceptance remain separate.
This fix does not close revenue plan REV-03 or REV-04 by itself.

On the development Mac, all **26 cases passed** with the explicit `--no-sanitizer`
option. The standalone build also compiles the actual `SystemAudioTap` wiring and
its control-plane dependencies. Against the extracted original render path at
`85487b4`, the empty-buffer, large planar Mid-Side and large interleaved FIR cases
each failed their new assertion; all three pass with this repair. The earlier
planar right-bound defect is also covered by writable-region guards.

Address Sanitizer itself stalled before `main`:
the captured process sample shows recursive sanitizer initialization during dyld
and malloc setup. That process was stopped; this is not a sanitizer pass. The
runner now fails after 45 seconds rather than leaving a stalled test running.
CI retains the sanitizer check, and native hardware/audio-capture tests remain
opt-in. No app was installed, signed for distribution, or submitted in this repair.
