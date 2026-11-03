"""Verify the real published input and bundled SQLite catalog; no generated provider data."""
import hashlib
import json
import sqlite3
import sys
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "Tools"))
import build_autoeq_db as builder


class HeadphonePresetDataTests(unittest.TestCase):
    def test_published_pro3_file_retains_positive_and_negative_filters(self):
        path = REPO / "Tools/headphone_presets/airpods-pro-3-songbird-jm1-6band.txt"
        preamp, filters = builder.parse(path)
        self.assertEqual(preamp, -3.9)
        self.assertEqual([f["gain"] for f in filters], [-2.3, 3.7, 3.9, 1.5, -6.4, -2.9])
        self.assertEqual([f["frequency"] for f in filters], [40, 151, 3417, 4305, 5747, 7671])
        self.assertEqual([f["q"] for f in filters], [0.7, 1.41, 3, 2, 3, 1.41])
        self.assertTrue(all(f["type"] == "peaking" for f in filters))

    def test_reviewed_inputs_match_the_shipped_database(self):
        with sqlite3.connect(f"file:{builder.OUT}?mode=ro", uri=True) as db:
            for expected in builder.supplemental_rows():
                actual = db.execute(
                    "SELECT model, brand, category, source, rig, preamp, filters FROM presets WHERE model = ?",
                    (expected[0],),
                ).fetchall()
                self.assertEqual(actual, [expected])
            self.assertEqual(db.execute("PRAGMA integrity_check").fetchone(), ("ok",))
            self.assertEqual(db.execute("SELECT COUNT(*) FROM presets").fetchone(), (8851,))

    def test_supplemental_sources_have_pinned_attribution_and_bundled_license(self):
        entries = json.loads((REPO / "Tools/headphone_presets/manifest.json").read_text())
        for entry in entries:
            self.assertIn(entry["source_commit"], entry["preset_url"])
            self.assertTrue(entry["measurement_url"].startswith("https://"))
            self.assertIsNone(entry["listening_mode"])
        license_bytes = (REPO / "Sources/SonanceEQ/Resources/openEq-LICENSE.txt").read_bytes()
        self.assertEqual(hashlib.sha256(license_bytes).hexdigest(),
                         "5c9d0b3d3a69a647ff50e309e2a1b2ca0499f3b27ef8a059e24e930b79c201e6")


if __name__ == "__main__":
    unittest.main()
