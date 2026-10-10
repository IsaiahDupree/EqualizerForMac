"""Actual Xcode/source reads and an explicitly supplied incremented native app."""
import hashlib
import importlib.util
import json
import os
import plistlib
import shutil
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
REPO = TOOLS.parent
spec = importlib.util.spec_from_file_location("version_gate", TOOLS / "verify_mas_purchase_config.py")
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)
FIXTURE = Path(__file__).parent / "evidence/version_binding"


class VersionSourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not shutil.which("xcodebuild"):
            raise unittest.SkipTest("Actual Xcode settings unavailable")
        cls.settings = gate.read_settings()
        cls.info_relative = Path("Sources/SonanceEQ/Resources/Info.plist")
        receipt = json.loads((FIXTURE / "capture.json").read_text())
        cls.original = (FIXTURE / "original-info.plist").read_bytes()
        if hashlib.sha256(cls.original).hexdigest() != receipt["body_sha256"]:
            raise AssertionError("Actual historical source capture changed")

    def copied_source(self, root):
        """Copy just the two actual release inputs; no test provider or native stub."""
        info = root / self.info_relative
        info.parent.mkdir(parents=True)
        shutil.copyfile(REPO / self.info_relative, info)
        shutil.copyfile(REPO / "appstore.json", root / "appstore.json")
        return info

    def test_actual_source_and_resolved_manifest(self):
        gate.validate_version_source(self.settings)

    def test_unchanged_old_source_is_rejected_before_build(self):
        with tempfile.TemporaryDirectory(prefix="sonance-version-source-") as directory:
            root = Path(directory)
            info = self.copied_source(root)
            info.write_bytes(self.original)
            with self.assertRaisesRegex(gate.ConfigurationError, "must expand"):
                gate.validate_version_source(self.settings, root)

    def test_each_frozen_metadata_field_is_rejected(self):
        for field, setting in (("CFBundleShortVersionString", "MARKETING_VERSION"),
                               ("CFBundleVersion", "CURRENT_PROJECT_VERSION")):
            with self.subTest(field=field), tempfile.TemporaryDirectory(prefix="sonance-version-source-") as directory:
                root = Path(directory)
                info = self.copied_source(root)
                values = plistlib.loads(info.read_bytes())
                values[field] = self.settings[setting]
                info.write_bytes(plistlib.dumps(values))
                with self.assertRaisesRegex(gate.ConfigurationError, field):
                    gate.validate_version_source(self.settings, root)

    def test_manifest_conflicts_are_rejected(self):
        for field in ("version", "build_number", "bundle_id"):
            with self.subTest(field=field), tempfile.TemporaryDirectory(prefix="sonance-version-source-") as directory:
                root = Path(directory)
                self.copied_source(root)
                config = json.loads((root / "appstore.json").read_text())
                config[field] += ".other"
                (root / "appstore.json").write_text(json.dumps(config))
                with self.assertRaises(gate.ConfigurationError):
                    gate.validate_version_source(self.settings, root)

    def test_escaped_source_is_rejected(self):
        with tempfile.TemporaryDirectory(prefix="sonance-version-source-") as directory:
            root = Path(directory)
            self.copied_source(root)
            settings = dict(self.settings, INFOPLIST_FILE=str(REPO / self.info_relative))
            with self.assertRaisesRegex(gate.ConfigurationError, "Wrong app metadata source"):
                gate.validate_version_source(settings, root)

    def test_oversized_source_is_rejected(self):
        with tempfile.TemporaryDirectory(prefix="sonance-version-source-") as directory:
            root = Path(directory)
            info = self.copied_source(root)
            info.write_bytes(info.read_bytes() + b" " * gate.MAX_BYTES)
            with self.assertRaisesRegex(gate.ConfigurationError, "oversized"):
                gate.validate_version_source(self.settings, root)

    def test_missing_source_is_rejected(self):
        with tempfile.TemporaryDirectory(prefix="sonance-version-source-") as directory:
            root = Path(directory)
            self.copied_source(root).unlink()
            with self.assertRaisesRegex(gate.ConfigurationError, "Missing"):
                gate.validate_version_source(self.settings, root)


class CompiledVersionTests(unittest.TestCase):
    def test_actual_incremented_version_and_build(self):
        configured = os.environ.get("SONANCE_VERSION_BINDING_TEST_APP")
        if not configured:
            self.skipTest("Actual incremented native compile candidate not supplied")
        version = os.environ["SONANCE_VERSION_BINDING_TEST_VERSION"]
        build = os.environ["SONANCE_VERSION_BINDING_TEST_BUILD"]
        settings = gate.read_settings()
        gate.validate_settings(settings)
        self.assertNotEqual(version, settings["MARKETING_VERSION"])
        self.assertGreater(int(build), int(settings["CURRENT_PROJECT_VERSION"]))
        expected = dict(settings, MARKETING_VERSION=version, CURRENT_PROJECT_VERSION=build)
        value = gate.validate_app(Path(configured), expected)
        self.assertEqual(value["metadata"], "verified")


if __name__ == "__main__":
    unittest.main()
