from copy import deepcopy
import importlib.util
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest


PORTABLE = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("sonance_presets", PORTABLE / "presets.py")
PRESETS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PRESETS)


class RealHeadphoneDatabaseTests(unittest.TestCase):
    def setUp(self):
        rows = PRESETS.search(PRESETS.DATABASE, "", 1)
        self.assertEqual(len(rows), 1)
        self.preset = PRESETS.export_headphone(PRESETS.DATABASE, rows[0]["id"])

    def test_real_database_export_round_trip(self):
        self.assertTrue(self.preset["bands"])
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "headphone.json"
            path.write_text(json.dumps(self.preset), encoding="utf-8")
            self.assertEqual(PRESETS.load(path), self.preset)

    def test_search_uses_literal_query_and_bounded_results(self):
        self.assertEqual(PRESETS.search(PRESETS.DATABASE, "%_nonexistent_' OR 1=1 --"), [])
        self.assertLessEqual(len(PRESETS.search(PRESETS.DATABASE, "", 3)), 3)
        with self.assertRaises(ValueError):
            PRESETS.search(PRESETS.DATABASE, "", 101)

    def test_old_mac_presets_receive_shipping_slope_default(self):
        for band in self.preset["bands"]:
            del band["slopeDbPerOct"]
        restored = PRESETS.validate(self.preset)
        self.assertTrue(all(band["slopeDbPerOct"] == 12 for band in restored["bands"]))

    def test_invalid_versions_numbers_and_capacity_fail_closed(self):
        for key, invalid in (("version", 2), ("version", True), ("app", "OtherApp"),
                             ("preampDb", float("nan")), ("preampDb", True)):
            with self.subTest(key=key, invalid=invalid):
                value = deepcopy(self.preset)
                value[key] = invalid
                with self.assertRaises(ValueError):
                    PRESETS.validate(value)
        for key, invalid in (("q", 0), ("frequency", float("inf")), ("gain", 61), ("enabled", 1)):
            with self.subTest(key=key, invalid=invalid):
                value = deepcopy(self.preset)
                value["bands"][0][key] = invalid
                with self.assertRaises(ValueError):
                    PRESETS.validate(value)
        value = deepcopy(self.preset)
        band = deepcopy(value["bands"][0])
        band.update(type="lowPass", slopeDbPerOct=96)
        value["bands"] = [deepcopy(band) for _ in range(5)]
        with self.assertRaisesRegex(ValueError, "32-section"):
            PRESETS.validate(value)

    def test_duplicate_fields_and_missing_database_are_errors(self):
        with self.assertRaises(ValueError):
            json.loads('{"version":1,"version":2}', object_pairs_hook=PRESETS.unique_object)
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(sqlite3.OperationalError):
                PRESETS.search(Path(directory) / "absent.sqlite", "")
            self.assertFalse((Path(directory) / "absent.sqlite").exists())


if __name__ == "__main__":
    unittest.main()
