# Orion portable-core build and test results

All four core build profiles passed on the owner’s Orion computer. Each used a
verified source snapshot, one compiler job, strict compiler warnings, CMake/CTest
and the actual bundled headphone database. No cloud build or render job ran.

| Profile | Compiler | Result | DSP assertions | Preset integration tests |
|---|---|---|---:|---:|
| Windows x64 release | MSVC 19.43.34810.0 | Passed | 5278 | 5 |
| Windows x64 AddressSanitizer | MSVC 19.43.34810.0 | Passed | 5278 | 5 |
| Linux x64 release (Ubuntu WSL2) | GNU 13.3.0 | Passed | 5278 | 5 |
| Linux x64 ASan + UBSan + leak checks | GNU 13.3.0 | Passed | 5278 | 5 |

The 1,584 coefficient cases agree across release and sanitizer profiles. The
largest absolute Windows/Linux coefficient difference was
`2.220446049250313e-16`, within the `1e-12` comparison tolerance. The generated
compile commands independently confirm AddressSanitizer instrumentation on the
Windows sanitizer build and AddressSanitizer/UndefinedBehaviorSanitizer on Linux.
Linux leak detection was enabled during execution. No sanitizer errors were
reported by these fixtures.

The exact tested source commit is `ea83b6d4fe6e210cf42a77ac9d3fcd8e1d7aa4cc`.
The full source closure hash is `a650a7cdffba6fd6ad70471ac3b5eca4ffd0ec2ecd0ce15ba530f919afa85ac9`.
The registered project is `sonance-core-a650a7cdffba`.
Job IDs, timings and artifact hashes are retained in the
[machine-readable receipt](ORION-CORE-BUILD-2026-11-06.json).

## Artifacts

The retained Orion task root is `E:/orion-jobs/sonance-eq-698f82d` and the immutable
source snapshot is `E:/orion-jobs/sonance-eq-ea83b6d/source`.
Each job’s `out` directory includes the native verification executables, build
and test logs, CMake compiler metadata, coefficient inputs/outputs and a ZIP
bundle containing the core header, preset tool, real database and license notices.
Verified copies are on the Mac under
`/Users/isaiahdupree/Documents/Software/artifacts/sonance-eq-orion-20261106/`.

Release bundles:

- [Windows core verification bundle](/Users/isaiahdupree/Documents/Software/artifacts/sonance-eq-orion-20261106/windows/sonance-core-windows.zip)
- [Linux core verification bundle](/Users/isaiahdupree/Documents/Software/artifacts/sonance-eq-orion-20261106/linux/sonance-core-linux.zip)

These are developer verification bundles, not installed consumer applications.
The Windows/Linux desktop UI, system-audio processing adapters, device lifecycle,
real hardware latency/playback, licensing, distribution signing and Store
submission remain separate work. Ubuntu WSL2 core verification does not establish
Linux desktop audio routing or broad distribution compatibility.

## Setup, contract checks and cleanup

The Windows build uses the existing Visual Studio 2022 Build Tools. Linux already
had GCC 13; its package manager had a half-configured `man-db` package. The typed
setup job finished only that configuration, then installed free CMake and Ninja.
No other OS upgrade was requested.

The first Windows harness attempt exposed command quoting in Visual Studio
environment setup. The fixed batch wrapper was verified with the actual MSVC
installation; the full native builds then passed with strict warnings intact.
No DSP assertion or preset test was removed or weakened.

All seven Orion runtime checks passed: contract inventory regeneration/check,
schema validation, agent-state listing, API self-test, native monitoring and
browser-status inspection. Three real API requests with an unsupported parameter,
unregistered profile or incorrect source hash were rejected. The existing API
reports validation exceptions as HTTP 500; no invalid request created a build.

The task-specific controller and its Mac SSH forward were stopped after artifact
verification. The shared Orion API remained healthy with its original PID.
The source tree and receipts remain available for reproducibility; no recurring
build, cloud deployment, audio driver or publishing task was enabled.
