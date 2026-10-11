"""Real macOS process/filesystem integration; no audio API or provider is replaced."""
import importlib.util
import json
import os
import plistlib
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import uuid

MODULE_PATH = Path(__file__).resolve().parents[1] / "bounded_audio_probe.py"
SPEC = importlib.util.spec_from_file_location("bounded_audio_probe", MODULE_PATH)
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)


@unittest.skipUnless(sys.platform == "darwin", "requires real macOS process identity")
class ProcessSupervisionIntegration(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.receipts = self.root / "receipts"
        self.receipts.mkdir()
        self.executable = Path(probe.process_identity(os.getpid())["executable"])

    def tearDown(self):
        self.directory.cleanup()

    def child_command(self, run_id, *, wait, status="running"):
        # This child reports its own real PID and executable. It does no audio work;
        # the record is expressly a process-supervision observation, never a HAL receipt.
        script = self.root / (run_id + ".py")
        script.write_text("import os,json,time,pathlib\n"
            "record=" + repr({"contract": "process_supervision_integration_observation_v1",
                "supervisor_run_id": run_id, "build_artifacts": [{"path": str(self.executable),
                    "sha256": probe.digest(self.executable)}], "status": status,
                "stage": "real_os_child_wait"}) + "\n"
            "record['process_id']=os.getpid()\n"
            "pathlib.Path(" + repr(str(self.receipts / (run_id + ".json")))
            + ").write_text(json.dumps(record))\n"
            + ("time.sleep(20)\n" if wait else ""))
        return [str(self.executable), str(script)]

    def run_child(self, command, run_id, deadline=1):
        return probe.supervise(command, executable=self.executable, receipts=self.receipts,
            output=self.root / "observation", run_id=run_id, deadline=deadline,
            source_revision=None)

    def test_deadline_terminates_real_owned_child_without_editing_original(self):
        run_id = str(uuid.uuid4())
        result = self.run_child(self.child_command(run_id, wait=True), run_id)
        self.assertEqual(result["status"], "deadline_exceeded")
        self.assertLess(result["elapsed_seconds"], 6)
        self.assertTrue(result["host_termination"]["term_sent"])
        self.assertTrue(result["host_termination"]["exit_observed"])
        native = self.receipts / (run_id + ".json")
        self.assertEqual(probe.digest(native), result["native_receipt"]["sha256"])
        self.assertEqual(native.read_bytes(), (self.root / "observation/native-receipt.json").read_bytes())
        self.assertEqual(json.loads(native.read_text())["status"], "running")
        self.assertFalse(result["hardware_acceptance_certified"])
        self.assertIsNone(result["native_cleanup_verified"])
        self.assertIsNone(probe.process_identity(result["runner_pid"]))
        self.assertEqual((self.root / "observation/supervision.json").stat().st_mode & 0o777, 0o600)

    def test_completed_runner_does_not_certify_hardware(self):
        run_id = str(uuid.uuid4())
        result = self.run_child(self.child_command(run_id, wait=False), run_id)
        self.assertEqual(result["status"], "runner_completed")
        self.assertEqual(result["runner_return_code"], 0)
        self.assertFalse(result["native_completed"])
        self.assertFalse(result["hardware_acceptance_certified"])
        self.assertIsNone(result["audibility_verified"])

    def test_another_nonce_and_preexisting_receipt_cannot_qualify_an_unrelated_process(self):
        other_id = str(uuid.uuid4())
        other = subprocess.Popen(self.child_command(other_id, wait=True))
        try:
            import time
            until = time.monotonic() + 2
            while not (self.receipts / (other_id + ".json")).exists() and time.monotonic() < until:
                time.sleep(0.02)
            other_receipt = self.receipts / (other_id + ".json")
            original = other_receipt.read_bytes()
            run_id = str(uuid.uuid4())
            result = self.run_child(self.child_command(run_id, wait=False), run_id)
            self.assertEqual(result["status"], "runner_completed")
            self.assertIsNone(other.poll())
            self.assertEqual(other_receipt.read_bytes(), original)
            self.assertNotEqual(result["native_receipt"]["process_id"], other.pid)
        finally:
            other.terminate()
            other.wait(timeout=2)

    def test_wrong_binary_hash_cannot_qualify_the_actual_process(self):
        real = subprocess.Popen([str(self.executable), "-c", "import time;time.sleep(20)"])
        try:
            record = {"process_id": real.pid, "build_artifacts": [{"path": str(self.executable),
                "sha256": "0" * 64}]}
            self.assertIsNone(probe.owned_host(record, self.executable, None))
            self.assertIsNone(real.poll())
        finally:
            real.terminate()
            real.wait(timeout=2)

    def test_current_process_and_symlinks_are_rejected(self):
        current = probe.process_identity(os.getpid())
        record = {"process_id": os.getpid(), "build_artifacts": [{"path": str(self.executable),
            "sha256": probe.digest(self.executable)}]}
        self.assertIsNone(probe.owned_host(record, self.executable, current))
        regular = self.receipts / "ordinary.json"
        regular.write_text(json.dumps(record))
        link = self.receipts / "link.json"
        link.symlink_to(regular)
        self.assertIsNone(probe.read_receipt(link))


@unittest.skipUnless(os.environ.get("SONANCE_NATIVE_XCTESTRUN"),
                     "requires an actual compiled native test runner")
class NativeRunnerBindingIntegration(unittest.TestCase):
    def test_real_compiled_runner_identity_nonce_and_original_preservation(self):
        original = Path(os.environ["SONANCE_NATIVE_XCTESTRUN"])
        executable = Path(os.environ["SONANCE_NATIVE_APP"]) / "Contents/MacOS/SonanceEQ"
        before = original.read_bytes()
        with tempfile.TemporaryDirectory() as directory:
            run_id = str(uuid.uuid4())
            path = probe.prepare_run(original, Path(directory), executable, run_id,
                                     subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip())
            value = plistlib.loads(path.read_bytes())
            target = value["SonanceEQTests"]
            self.assertEqual(target["EnvironmentVariables"]["SONANCE_AUDIO_PROBE_RUN_ID"], run_id)
            self.assertEqual(target["EnvironmentVariables"]["SONANCE_AUDIO_HARDWARE_TESTS"], "1")
            self.assertTrue(target["TestHostPath"].startswith(str(original.parent)))
            self.assertTrue(executable.is_file())
            self.assertEqual(original.read_bytes(), before)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_other_actual_executable_cannot_replace_native_runner(self):
        original = Path(os.environ["SONANCE_NATIVE_XCTESTRUN"])
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, "test_host_executable"):
                probe.prepare_run(original, Path(directory), Path(sys.executable), str(uuid.uuid4()), "unknown")


if __name__ == "__main__":
    unittest.main()
