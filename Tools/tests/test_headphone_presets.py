"""Verify the real published input and bundled SQLite catalog; no generated provider data."""
import hashlib
import json
import sqlite3
import sys
import unittest
import tempfile
from pathlib import Path
from contextlib import closing

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "Tools"))
import build_autoeq_db as builder
import audit_headphone_coverage as audit


class HeadphonePresetDataTests(unittest.TestCase):
    def test_every_1_0_7_catalog_row_is_preserved(self):
        with closing(sqlite3.connect(f"file:{builder.OUT}?mode=ro", uri=True)) as db:
            rows = db.execute("SELECT * FROM presets WHERE id<=8851 ORDER BY id").fetchall()
        digest = hashlib.sha256(json.dumps(rows, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()
        # Independently captured from the committed 1.0.7 database before adding any new data.
        self.assertEqual(digest, "225eb7cb151a0dedfcbf54620ddde438689be5bf054ba54c526bc24df56eb35f")

    def test_published_pro3_file_retains_positive_and_negative_filters(self):
        path = REPO / "Tools/headphone_presets/airpods-pro-3-songbird-jm1-6band.txt"
        preamp, filters = builder.parse(path)
        self.assertEqual(preamp, -3.9)
        self.assertEqual([f["gain"] for f in filters], [-2.3, 3.7, 3.9, 1.5, -6.4, -2.9])
        self.assertEqual([f["frequency"] for f in filters], [40, 151, 3417, 4305, 5747, 7671])
        self.assertEqual([f["q"] for f in filters], [0.7, 1.41, 3, 2, 3, 1.41])
        self.assertTrue(all(f["type"] == "peaking" for f in filters))

    def test_reviewed_inputs_match_the_shipped_database(self):
        with closing(sqlite3.connect(f"file:{builder.OUT}?mode=ro", uri=True)) as db:
            for expected in builder.supplemental_rows():
                actual = db.execute(
                    "SELECT model, brand, category, source, rig, preamp, filters FROM presets WHERE model = ?",
                    (expected[0],),
                ).fetchall()
                self.assertEqual(actual, [expected])
            self.assertEqual(db.execute("PRAGMA integrity_check").fetchone(), ("ok",))
            self.assertEqual(db.execute("SELECT COUNT(*) FROM presets").fetchone(), (8862,))

    def test_supplemental_sources_have_pinned_attribution_and_bundled_license(self):
        entries = json.loads((REPO / "Tools/headphone_presets/manifest.json").read_text())
        for entry in entries:
            self.assertIn(entry["source_commit"], entry["preset_url"])
            self.assertTrue(entry["measurement_url"].startswith("https://"))
            self.assertIsNone(entry["listening_mode"])
        license_bytes = (REPO / "Sources/SonanceEQ/Resources/openEq-LICENSE.txt").read_bytes()
        self.assertEqual(hashlib.sha256(license_bytes).hexdigest(),
                         "5c9d0b3d3a69a647ff50e309e2a1b2ca0499f3b27ef8a059e24e930b79c201e6")

    def test_opra_inputs_are_pinned_and_match_both_bundled_data_formats(self):
        manifest = json.loads((Path(builder.OPRA) / "manifest.json").read_text())
        rows, provenance, portable = builder.opra_rows()
        self.assertEqual(len(rows), 11)
        self.assertEqual(portable, json.loads((REPO / "Sources/SonanceEQ/Resources/OPRA-Beats.json").read_text()))
        with closing(sqlite3.connect(f"file:{builder.OUT}?mode=ro", uri=True)) as db:
            for row, (url, license_name), entry in zip(rows, provenance, manifest["entries"]):
                self.assertIn(manifest["source_commit"], url)
                self.assertEqual(license_name, "CC BY-SA 4.0")
                actual = db.execute(
                    "SELECT p.model,p.brand,p.category,p.source,p.rig,p.preamp,p.filters "
                    "FROM presets p JOIN preset_metadata m ON p.id=m.preset_id WHERE m.source_url=?", (url,),
                ).fetchall()
                self.assertEqual(actual, [row])
                original = json.loads((Path(builder.OPRA) / entry["file"]).read_text())
                self.assertLessEqual(row[5], original["parameters"]["gain_db"])
            self.assertEqual(db.execute("SELECT COUNT(*) FROM preset_metadata").fetchone(), (8862,))
            self.assertEqual(db.execute("PRAGMA foreign_key_check").fetchall(), [])

    def test_additional_beats_curves_do_not_duplicate_existing_corrections(self):
        def fingerprint(row):
            return row[0], tuple(sorted((f["type"], f["frequency"], f["gain"], f["q"])
                                       for f in json.loads(row[1])))
        with closing(sqlite3.connect(f"file:{builder.OUT}?mode=ro", uri=True)) as db:
            existing = {fingerprint(r) for r in db.execute(
                "SELECT preamp,filters FROM presets WHERE brand='Beats' AND id<=8851")}
            additions = [fingerprint(r) for r in db.execute(
                "SELECT preamp,filters FROM presets WHERE id>8851")]
            self.assertEqual(len(additions), 11)
            self.assertEqual(len(set(additions)), 11)
            self.assertTrue(existing.isdisjoint(additions))

    def test_search_metadata_retains_generation_mode_and_plus_variants(self):
        self.assertEqual(builder.search_key("Beats Studio Buds +"), builder.search_key("Beats Studio Buds Plus"))
        self.assertNotEqual(builder.search_key("Beats Studio Buds +"), builder.search_key("Beats Studio Buds"))
        with closing(sqlite3.connect(f"file:{builder.OUT}?mode=ro", uri=True)) as db:
            self.assertEqual(db.execute(
                "SELECT p.category,m.category FROM presets p JOIN preset_metadata m ON p.id=m.preset_id "
                "WHERE p.model='Beats Powerbeats 2 Wireless'").fetchone(), ("over-ear", "in-ear"))
            self.assertEqual(db.execute(
                "SELECT COUNT(*) FROM preset_metadata WHERE display_model='Apple AirPods Pro 3'").fetchone(), (1,))
            self.assertEqual(db.execute(
                "SELECT display_model FROM preset_metadata WHERE display_model LIKE '%Powerbeats 4%'").fetchone(),
                ("Beats Powerbeats 4",))

    def test_reviewed_coverage_reports_actual_gaps_without_model_substitution(self):
        report = audit.coverage()
        self.assertEqual(report["beats_presets"], 55)
        current = [d for d in report["devices"] if d["scope"] == "current_beats"]
        self.assertEqual(len(current), 8)
        self.assertEqual({d["model"] for d in current if d["status"] == "needs_preset_data"},
                         {"Beats 360", "Beats Powerbeats Fit"})
        self.assertTrue(all(d["status"] == "needs_preset_data" for d in report["devices"]
                            if d["scope"] in ("requested", "legacy_gap")))
        self.assertTrue(all(d["status"] == "available" for d in report["devices"]
                            if d["scope"] == "legacy_catalog"))

    def test_failed_real_sqlite_rebuild_preserves_the_existing_catalog(self):
        with closing(sqlite3.connect(f"file:{builder.OUT}?mode=ro", uri=True)) as db:
            row = list(db.execute("SELECT model,brand,category,source,rig,preamp,filters FROM presets "
                                  "WHERE model='Apple AirPods Pro 3'").fetchone())
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "autoeq.sqlite"
            original = Path(builder.OUT).read_bytes()
            output.write_bytes(original)
            row[-1] = None  # Real SQLite NOT NULL failure during insertion, not a provider double.
            with self.assertRaises(sqlite3.IntegrityError):
                builder.write_catalog(str(output), [row], {})
            self.assertEqual(output.read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
