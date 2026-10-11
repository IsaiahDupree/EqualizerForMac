"""Checkout-local command plans and actual Apple packages; no simulated uploads."""
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("sonance_handoff", TOOLS / "asc/pipeline.py")
handoff = importlib.util.module_from_spec(spec)
spec.loader.exec_module(handoff)
PIPELINE = Path.home() / "Documents/Software/AppFleet/appstore_pipeline.py"


class PlanTests(unittest.TestCase):
    def arguments(self, *args):
        return handoff.parser().parse_args(list(args))

    def test_default_is_read_only_doctor(self):
        command, artifact = handoff.plan(self.arguments(), PIPELINE)
        self.assertEqual(command[2:4], ["doctor", str(TOOLS.parent)])
        self.assertNotIn("--yes", command)
        self.assertIsNone(artifact)

    def test_source_and_all_use_canonical_ship_from_this_checkout(self):
        for name in ("ship", "all"):
            with self.subTest(name=name):
                command, artifact = handoff.plan(self.arguments(name), PIPELINE)
                self.assertEqual(command[:4], [sys.executable, str(PIPELINE), "ship", str(TOOLS.parent)])
                self.assertEqual(command[command.index("--configuration") + 1], "Release-MAS")
                self.assertEqual(command[command.index("--bundle-id") + 1], handoff.gate.BUNDLE)
                self.assertNotIn("--yes", command)
                self.assertIsNone(artifact)

    def test_yes_is_explicit_and_attachment_cannot_be_skipped(self):
        command, _ = handoff.plan(self.arguments("ship", "--yes"), PIPELINE)
        self.assertIn("--yes", command)
        self.assertNotIn("--skip-attach", command)
        self.assertNotIn("--allow-dirty", command)

    def test_implicit_old_package_directories_are_not_selected(self):
        with self.assertRaisesRegex(handoff.gate.ConfigurationError, "no implicit package path"):
            handoff.plan(self.arguments("upload"), PIPELINE)

    def test_read_only_commands_cannot_take_write_options(self):
        for name in ("doctor", "status"):
            for args in (("--yes",), ("--build-number", "9")):
                with self.subTest(command=name, args=args), self.assertRaises(handoff.gate.ConfigurationError):
                    handoff.plan(self.arguments(name, *args), PIPELINE)

    def test_invalid_or_missing_build_number_is_rejected(self):
        for number in ("", "0", "-1", "1.2", "2147483648", "9;upload"):
            with self.subTest(number=number), self.assertRaises(handoff.gate.ConfigurationError):
                handoff.plan(self.arguments("ship", "--build-number=" + number), PIPELINE)

    def test_existing_non_package_source_is_rejected(self):
        with self.assertRaisesRegex(handoff.gate.ConfigurationError, "package does not exist"):
            handoff.plan(self.arguments("upload", "--artifact", str(TOOLS.parent / "appstore.json"),
                                       "--build-number", "9"), PIPELINE)

    def test_status_keeps_json_and_fixed_release_scope(self):
        command, _ = handoff.plan(self.arguments("status", "--json"), PIPELINE)
        self.assertEqual(command[2], "status")
        self.assertIn("--json", command)
        self.assertEqual(command[command.index("--platform") + 1], "macos")


class ActualPackageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        configured = os.environ.get("SONANCE_HANDOFF_TEST_PKG")
        if not configured or not shutil.which("pkgutil") or not PIPELINE.is_file():
            raise unittest.SkipTest("Actual Sonance Apple package and canonical AppFleet not supplied")
        cls.pkg = Path(configured).resolve()
        if not cls.pkg.is_file():
            raise RuntimeError("Supplied actual package is missing")
        cls.settings = handoff.gate.read_settings()
        handoff.gate.validate_settings(cls.settings)
        cls.build = cls.settings["CURRENT_PROJECT_VERSION"]
        cls.canonical = handoff.appfleet_module(PIPELINE)

    def test_actual_package_key_and_version_binding(self):
        value = handoff.validate_package_purchase_metadata(self.pkg, self.settings, self.build)
        self.assertEqual(value["package_sha256"], handoff.file_digest(self.pkg))
        self.assertEqual(value["metadata"], "verified")
        self.assertFalse(value["distribution_signature_verified"])

    def test_actual_package_rejects_other_expected_build(self):
        with self.assertRaisesRegex(handoff.gate.ConfigurationError, "CFBundleVersion"):
            handoff.validate_package_purchase_metadata(self.pkg, self.settings, str(int(self.build) + 1))

    def test_actual_package_rejects_different_embedded_sdk_key(self):
        expected = dict(self.settings, REVENUECAT_PUBLIC_KEY="")
        with self.assertRaisesRegex(handoff.gate.ConfigurationError, "RevenueCatPublicKey"):
            handoff.validate_package_purchase_metadata(self.pkg, expected, self.build)

    def test_explicit_artifact_plan_and_build(self):
        args = handoff.parser().parse_args(["upload", "--artifact", str(self.pkg), "--build-number", self.build])
        command, path = handoff.plan(args, PIPELINE)
        self.assertEqual(path, self.pkg)
        self.assertEqual(command[command.index("--artifact") + 1], str(self.pkg))
        self.assertEqual(command[command.index("--build-number") + 1], self.build)
        self.assertNotIn("--yes", command)

    def test_plans_parse_with_the_actual_canonical_cli(self):
        for arguments in (["doctor"], ["status", "--json"], ["ship", "--yes"],
                          ["upload", "--artifact", str(self.pkg), "--build-number", self.build]):
            with self.subTest(arguments=arguments):
                args = handoff.parser().parse_args(arguments)
                command, _ = handoff.plan(args, PIPELINE)
                canonical_args = self.canonical.parser().parse_args(command[2:])
                self.assertEqual(Path(canonical_args.repo), TOOLS.parent)
                self.assertEqual(canonical_args.configuration, "Release-MAS")
                self.assertEqual(canonical_args.bundle_id, handoff.gate.BUNDLE)

    def test_actual_foreign_package_is_rejected(self):
        configured = os.environ.get("SONANCE_HANDOFF_FOREIGN_PKG")
        if not configured:
            self.skipTest("Actual foreign Apple package not supplied")
        with self.assertRaisesRegex(handoff.gate.ConfigurationError, "CFBundleIdentifier"):
            handoff.validate_package_purchase_metadata(Path(configured), self.settings, self.build)

    def test_shell_works_outside_git_checkout_without_writes(self):
        with tempfile.TemporaryDirectory(prefix="sonance-handoff-cwd-") as directory:
            result = subprocess.run(["bash", str(TOOLS / "ship.sh"), "upload", "--artifact", str(self.pkg),
                                     "--build-number", self.build], cwd=directory, capture_output=True,
                                    text=True, timeout=90, env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1"))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        value = json.loads(result.stdout)
        self.assertEqual(value["source_repo"], str(TOOLS.parent))
        self.assertEqual(value["status"], "preview")
        self.assertTrue(value["dry_run"])
        self.assertFalse(value["native_distribution_verified"])
        self.assertNotIn("--yes", value["command"])

    def test_canonical_verifier_rejects_genuine_unsigned_package(self):
        # The owner-generated productbuild package wraps an actual compiled app.
        # This exercises genuine Apple signature verification without an API client.
        config = json.loads((TOOLS.parent / "appstore.json").read_text())
        team = json.loads((PIPELINE.parent / "asc/config.json").read_text())["team_id"]
        project = self.canonical.Project(
            repo=TOOLS.parent, container_flag="-project", container=TOOLS.parent / "SonanceEQ.xcodeproj",
            scheme="SonanceEQ", configuration="Release-MAS", platform="MAC_OS", bundle_id=handoff.gate.BUNDLE,
            name=config["name"], marketing_version=self.settings["MARKETING_VERSION"], project_build=self.build,
            team_id=team, profile_name=config["profile_name"], app_config=config)
        with self.assertRaisesRegex(self.canonical.PipelineError, "signature"):
            self.canonical.verify_artifact(self.pkg, project, self.build)


if __name__ == "__main__":
    unittest.main()
