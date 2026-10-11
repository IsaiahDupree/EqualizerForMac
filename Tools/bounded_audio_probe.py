#!/usr/bin/env python3
"""Bound the opt-in native Core Audio test outside its potentially stalled host.

This is a diagnostic client of the existing test, not an audio provider. It never
requests permissions, changes devices, edits a native receipt, or certifies audio.
"""
from __future__ import annotations

import argparse
import ctypes
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import plistlib
import signal
import stat
import subprocess
import time
import uuid


MAX_RECEIPT = 1024 * 1024


def utc() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def save(path: Path, value: dict) -> None:
    data = (json.dumps(value, indent=2, sort_keys=True) + "\n").encode()
    temporary = path.with_name(path.name + ".tmp")
    fd = os.open(temporary, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    with os.fdopen(fd, "wb") as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)


def process_identity(pid: int) -> dict | None:
    """Observe the executable and birth identity on macOS; fail closed elsewhere."""
    if pid <= 1:
        return None
    buffer = ctypes.create_string_buffer(4096)
    library = ctypes.CDLL("/usr/lib/libproc.dylib")
    library.proc_pidpath.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
    library.proc_pidpath.restype = ctypes.c_int
    if library.proc_pidpath(pid, buffer, len(buffer)) <= 0:
        return None
    observed = subprocess.run(["/bin/ps", "-p", str(pid), "-o", "lstart="],
                              capture_output=True, text=True, timeout=2,
                              env={**os.environ, "LC_ALL": "C"})
    birth = observed.stdout.strip()
    if observed.returncode or not birth:
        return None
    return {"pid": pid, "executable": str(Path(os.fsdecode(buffer.value)).resolve()),
            "birth": birth}


def read_receipt(path: Path) -> dict | None:
    """Only bounded regular files, with O_NOFOLLOW to close the symlink race."""
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(fd, "rb") as stream:
            info = os.fstat(stream.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_RECEIPT:
                return None
            value = json.loads(stream.read(MAX_RECEIPT + 1))
        return value if isinstance(value, dict) else None
    except (OSError, ValueError):
        return None


def matching_receipts(root: Path, before: set[Path], run_id: str) -> list[tuple[Path, dict]]:
    paths = set(root.glob("*.json")) - before
    if len(paths) > 32:
        raise RuntimeError("receipt_inventory_changed_beyond_bound")
    return [(path, value) for path in sorted(paths)
            if (value := read_receipt(path)) is not None
            and value.get("supervisor_run_id") == run_id]


def owned_host(value: dict, executable: Path, baseline: dict | None) -> dict | None:
    """A nonce alone is insufficient: bind the actual binary and live PID birth."""
    pid = value.get("process_id")
    if type(pid) is not int or pid == os.getpid():
        return None
    identity = process_identity(pid)
    if identity is None or identity == baseline:
        return None
    if identity["executable"] != str(executable.resolve()):
        return None
    expected = {"path": str(executable), "sha256": digest(executable)}
    if expected not in value.get("build_artifacts", []):
        return None
    return identity


def terminate_host(identity: dict, *, grace: float = 2) -> dict:
    result = {"identity": identity, "term_sent": False, "kill_sent": False,
              "exit_observed": False, "identity_change": False}
    for sig in [signal.SIGTERM, signal.SIGKILL]:
        current = process_identity(identity["pid"])
        if current is None:
            result["exit_observed"] = True
            break
        if current != identity:
            result["identity_change"] = True
            break
        try:
            os.kill(identity["pid"], sig)
        except OSError as error:
            result["signal_error_type"] = type(error).__name__
            break
        result["term_sent" if sig == signal.SIGTERM else "kill_sent"] = True
        until = time.monotonic() + grace
        while time.monotonic() < until:
            if process_identity(identity["pid"]) is None:
                result["exit_observed"] = True
                return result
            time.sleep(0.05)
    return result


def supervise(command: list[str], *, executable: Path, receipts: Path,
              output: Path, run_id: str, deadline: float,
              source_revision: str | None, sample_after: float | None = None) -> dict:
    if not 0 < deadline <= 90:
        raise ValueError("deadline_must_be_between_zero_and_90_seconds")
    output.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(output, 0o700)
    before = set(receipts.glob("*.json"))
    result = {"contract": "sonance_audio_probe_supervision_v1", "run_id": run_id,
              "started_at": utc(), "source_revision": source_revision,
              "deadline_seconds": deadline, "status": "running",
              "host_executable": str(executable), "host_sha256": digest(executable),
              "audio_permission_requested": False, "audio_samples_saved": False,
              "hardware_acceptance_certified": False, "audibility_verified": None,
              "native_cleanup_verified": None, "runner_return_code": None,
              "native_receipt": None, "host_termination": None}
    path = output / "supervision.json"
    save(path, result)
    log_path = output / "runner.log"
    log_fd = os.open(log_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    start = time.monotonic()
    observed_host = None
    sampled = False
    with os.fdopen(log_fd, "wb") as log:
        runner = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT,
                                  start_new_session=True)
        result["runner_pid"] = runner.pid
        try:
            while runner.poll() is None and time.monotonic() - start < deadline:
                matches = matching_receipts(receipts, before, run_id)
                if len(matches) > 1:
                    raise RuntimeError("multiple_native_receipts_for_single_probe")
                if matches:
                    native_path, native = matches[0]
                    result["native_receipt"] = {"path": str(native_path),
                        "sha256": digest(native_path), "stage": native.get("stage"),
                        "status": native.get("status"), "process_id": native.get("process_id"),
                        "audio_capture_permission": native.get("audio_capture_permission")}
                    identity = owned_host(native, executable, None)
                    if identity is not None:
                        if observed_host is not None and observed_host != identity:
                            raise RuntimeError("native_host_identity_changed")
                        observed_host = identity
                        if (sample_after is not None and not sampled
                                and time.monotonic() - start >= sample_after):
                            sample_path = output / "host-stack.txt"
                            sampled = True
                            if process_identity(identity["pid"]) == identity:
                                observation = subprocess.run(["/usr/bin/sample", str(identity["pid"]),
                                    "1", "10", "-file", str(sample_path)],
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3)
                                result["stack_capture"] = {"return_code": observation.returncode,
                                    "path": str(sample_path),
                                    "sha256": digest(sample_path) if sample_path.exists() else None}
                                if sample_path.exists():
                                    os.chmod(sample_path, 0o600)
                    save(path, result)
                time.sleep(0.1)
                if log_path.stat().st_size > 16 * 1024 * 1024:
                    raise RuntimeError("runner_log_exceeded_16_mib_bound")
            if runner.poll() is None:
                result["status"] = "deadline_exceeded"
            else:
                result["status"] = "runner_completed"
                result["runner_return_code"] = runner.returncode
        except Exception as error:
            result["status"] = "supervisor_failed"
            result["error_type"] = type(error).__name__
            result["error"] = str(error)
        finally:
            # Native hosts can be launched by testmanagerd outside xcodebuild's process group.
            # Never use pgrep/killall: only the fresh nonce + binary + live birth identity qualifies.
            if observed_host is not None and process_identity(observed_host["pid"]) is not None:
                result["host_termination"] = terminate_host(observed_host)
            if runner.poll() is None:
                runner.terminate()
                try:
                    runner.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    runner.kill()
                    runner.wait(timeout=2)
            result["runner_return_code"] = runner.returncode
            try:
                matches = matching_receipts(receipts, before, run_id)
            except RuntimeError as error:
                matches = []
                result["receipt_inventory_error"] = str(error)
            if len(matches) == 1:
                native_path, native = matches[0]
                result["native_receipt"] = {"path": str(native_path),
                    "sha256": digest(native_path), "stage": native.get("stage"),
                    "status": native.get("status"), "process_id": native.get("process_id"),
                    "audio_capture_permission": native.get("audio_capture_permission")}
                result["native_completed"] = native.get("completed_at") is not None
                # Retain an exact private copy; the original owner's receipt is never edited.
                copy_path = output / "native-receipt.json"
                copy_fd = os.open(copy_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                with os.fdopen(copy_fd, "wb") as copy:
                    copy.write(native_path.read_bytes())
            result["completed_at"] = utc()
            result["elapsed_seconds"] = round(time.monotonic() - start, 3)
            save(path, result)
    return result


def prepare_run(original: Path, output: Path, executable: Path,
                run_id: str, source_revision: str) -> Path:
    value = plistlib.loads(original.read_bytes())
    targets = [target for configuration in value.get("TestConfigurations", [])
               for target in configuration.get("TestTargets", [])]
    if not targets:
        targets = [v for k, v in value.items() if not k.startswith("__") and isinstance(v, dict)]
    if len(targets) != 1 or targets[0].get("TestHostBundleIdentifier") != "com.isaiahdupree.SonanceEQ":
        raise ValueError("exact_single_sonance_test_host_required")
    target = targets[0]
    host = target.get("TestHostPath", "").replace("__TESTROOT__", str(original.parent))
    if Path(host).resolve() not in [executable.resolve(), executable.resolve().parents[2]]:
        raise ValueError("test_host_executable_does_not_match_selected_app")
    target.setdefault("EnvironmentVariables", {}).update({"SONANCE_AUDIO_HARDWARE_TESTS": "1",
        "SONANCE_AUDIO_PROBE_RUN_ID": run_id, "SONANCE_AUDIO_PROBE_SOURCE_REVISION": source_revision})
    # The copied runner is outside Build/Products; resolve the original test-root bindings.
    def resolve(item):
        if isinstance(item, str):
            return item.replace("__TESTROOT__", str(original.parent))
        if isinstance(item, list):
            return [resolve(v) for v in item]
        if isinstance(item, dict):
            return {k: resolve(v) for k, v in item.items()}
        return item
    path = output / "SonanceEQ-AudioHardware.xctestrun"
    with path.open("xb") as stream:
        stream.write(plistlib.dumps(resolve(value)))
    path.chmod(0o600)
    return path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--xctestrun", type=Path, required=True)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--deadline", type=float, default=45)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parent.parent
    revision = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip()
    if subprocess.check_output(["git", "-C", str(repo), "status", "--porcelain"], text=True).strip():
        parser.error("commit the source and generated metadata before the hardware run")
    args.output.mkdir(mode=0o700, parents=True, exist_ok=True)
    args.output.chmod(0o700)
    run_id = str(uuid.uuid4())
    executable = args.app.resolve() / "Contents/MacOS/SonanceEQ"
    native_info = plistlib.loads((args.app / "Contents/Info.plist").read_bytes())
    manifest = json.loads((repo / "appstore.json").read_text())
    if native_info.get("CFBundleIdentifier") != "com.isaiahdupree.SonanceEQ":
        parser.error("selected native artifact is not Sonance EQ")
    if (native_info.get("CFBundleShortVersionString") != manifest["version"]
            or str(native_info.get("CFBundleVersion")) != str(manifest["build_number"])):
        parser.error("selected artifact does not match the current source version/build")
    subprocess.run(["/usr/bin/codesign", "--verify", "--strict", str(args.app)],
                   check=True, capture_output=True, timeout=5)
    run = prepare_run(args.xctestrun.resolve(), args.output, executable, run_id, revision)
    command = ["/usr/bin/xcodebuild", "test-without-building", "-xctestrun", str(run),
               "-destination", "platform=macOS,arch=arm64", "-jobs", "1",
               "-parallel-testing-enabled", "NO", "-only-testing:SonanceEQTests/SystemAudioHardwareTests",
               "-resultBundlePath", str(args.output / "hardware.xcresult"), "-quiet"]
    result = supervise(command, executable=executable,
        receipts=Path.home() / "Library/Application Support/SonanceEQ/RouteProofs",
        output=args.output, run_id=run_id, deadline=args.deadline,
        source_revision=revision, sample_after=min(12, args.deadline / 2))
    print(json.dumps({k: result.get(k) for k in ["status", "runner_return_code", "native_receipt",
                                               "native_completed", "completed_at"]}))
    native = result.get("native_receipt") or {}
    return 0 if (result["status"] == "runner_completed" and result["runner_return_code"] == 0
                 and result.get("native_completed") is True and native.get("status") == "succeeded") else 1


if __name__ == "__main__":
    raise SystemExit(main())
