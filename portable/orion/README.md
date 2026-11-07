# Orion core build lane

`software.sonance_core` runs on a task-scoped copy of the existing authenticated
Orion control API. It uses the ordinary serialized workers queue, resource
admission, idempotency keys, per-job receipts and artifact hashes. It does not
replace the shared controller or start any recurring automation.

The registered profile names are `windows`, `windows-asan`, `linux`,
`linux-sanitizers` and `prepare-linux`. API requests accept only `project_id`,
`profile`, `expected_source_sha256` and a 60–900 second `timeout_sec`. They accept
no caller command, executable, compiler flags or filesystem paths.

`bootstrap.py` runs on Orion Windows through the existing authenticated SSH
route. It verifies a Git source archive, copies the retained control runtime,
installs the bounded extension, and registers the exact source tree and tool
executables. A fresh source snapshot gets a fresh task directory. `--serve`
starts its loopback API on port 18810 with a one-hour lifetime; `--stop` verifies
the task identity and idle queue before stopping that controller. Existing saved
Orion authentication is reused without putting its value in arguments or logs.

The controller's native Windows Python launches the fixed `run.py` harness.
Windows uses the installed Visual Studio 2022 Build Tools. Linux profiles use
Ubuntu WSL2 and verify the registered GCC, CMake, Ninja, CTest and Python hashes.
The setup profile installs only free CMake/Ninja packages; on this device it also
finished the previously half-configured `man-db` package before installation.

Each build uses a verified source copy, one compiler job, CMake/CTest, the actual
headphone database tests and the 1,584-case coefficient matrix. Sanitizer profiles
instrument the compiled binaries; the generated compile commands are retained.
Bundles contain the verification executables, core header, preset tool, actual
database and license notices. They are developer verification bundles, not
desktop application installers.

Submit through the existing saved-token client once the task API/tunnel is up:

```sh
orionctl --port 18810 call workers.submit --json sonance-build-request.json \
  --request-id sonance-windows-ea83b6d-001
```

The request used for the verified Windows build was:

```json
{
  "job_type": "software.sonance_core",
  "params": {
    "project_id": "sonance-core-a650a7cdffba",
    "profile": "windows",
    "expected_source_sha256": "a650a7cdffba6fd6ad70471ac3b5eca4ffd0ec2ecd0ce15ba530f919afa85ac9",
    "timeout_sec": 600
  }
}
```

The same request ID returns the retained job instead of rerunning it. Fresh
snapshots use the actual identity/hash returned by registration. The controller
and its SSH forward are closed after artifact verification. Reusing this lane
for a later assigned task requires starting that task controller; it does not
enable background builds. Full results are in the
[Orion verification report](../../docs/reports/ORION-CORE-BUILD-2026-11-06.md).
