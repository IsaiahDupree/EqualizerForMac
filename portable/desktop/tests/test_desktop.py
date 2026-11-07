from copy import deepcopy
import json
import os
from pathlib import Path
import tempfile
import unittest

from PySide6.QtCore import QPoint, Qt
from PySide6.QtGui import QRawFont
from PySide6.QtTest import QTest
from PySide6.QtWidgets import QApplication

import presets
from sonance_ui.document import Document, flat_preset
from sonance_ui.appearance import configure_font
from sonance_ui.native import NativeCore, database_path
from sonance_ui.window import EditorWindow

APP = QApplication.instance() or QApplication([])
configure_font(APP)


class DesktopIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.core = NativeCore()

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="sonance-ui-test-")
        self.settings = Path(self.directory.name)
        self.document = Document(self.core, database_path(), self.settings)
        self.window = EditorWindow(self.document)
        self.window.show()
        QTest.qWait(30)

    def tearDown(self):
        self.window.close()
        APP.processEvents()
        self.directory.cleanup()

    def test_bundled_font_has_real_latin_glyphs(self):
        font = QRawFont.fromFont(APP.font())
        self.assertTrue(font.isValid())
        for character in "Sonance EQ 0123456789 ·—":
            self.assertTrue(font.supportsCharacter(ord(character)), repr(character))

    def test_real_native_bridge_and_bypass(self):
        value = flat_preset()
        value["bands"] = [{"type": "peaking", "frequency": 1000, "gain": 6, "q": 1,
                            "enabled": True, "slopeDbPerOct": 12}]
        _, gains = self.core.response(value, frequencies=[1000])
        self.assertAlmostEqual(gains[0], 6, places=8)
        _, gains = self.core.response(value, bypass=True, frequencies=[1000])
        self.assertEqual(gains, [0])

    def test_real_headphone_search_load_and_screen(self):
        self.assertEqual(self.document.headphone_count, 8850)
        self.window.search.setFocus()
        QTest.keyClicks(self.window.search, "Sennheiser")
        QTest.qWait(220)
        self.assertGreater(self.window.results.count(), 0)
        identity = self.window.results.item(0).data(Qt.ItemDataRole.UserRole)
        expected = presets.export_headphone(database_path(), identity)
        QTest.mouseClick(self.window.load_button, Qt.MouseButton.LeftButton)
        self.assertEqual(self.document.preset, expected)
        self.assertEqual(self.window.name.text(), expected["name"])
        self.assertEqual(self.window.table.rowCount(), len(expected["bands"]))
        self.assertTrue(any(abs(value) > 0.1 for value in self.document.response))
        if os.environ.get("SONANCE_UI_TEST_OUTPUT"):
            directory = Path(os.environ["SONANCE_UI_TEST_OUTPUT"])
            directory.mkdir(parents=True, exist_ok=True)
            self.assertTrue(self.window.grab().save(str(directory / "headphone-editor.png")))

    def test_widget_band_edit_bypass_preamp_and_selection(self):
        self.window.gain.setFocus()
        self.window.gain.selectAll()
        QTest.keyClicks(self.window.gain, "6")
        QTest.keyClick(self.window.gain, Qt.Key.Key_Return)
        self.assertEqual(self.document.preset["bands"][0]["gain"], 6)
        QTest.mouseClick(self.window.bypass, Qt.MouseButton.LeftButton)
        self.assertTrue(self.document.bypassed)
        self.assertTrue(all(value == 0 for value in self.document.response))
        QTest.mouseClick(self.window.bypass, Qt.MouseButton.LeftButton)
        self.window.preamp.setValue(-4.5)
        self.assertEqual(self.document.preset["preampDb"], -4.5)
        self.document.choose(4)
        self.assertEqual(self.window.table.currentRow(), 4)
        self.assertEqual(self.window.frequency.value(), 500)

    def test_chart_drag_changes_actual_document(self):
        start = self.window.plot.handle(5).toPoint()
        end = start + QPoint(40, -25)
        QTest.mousePress(self.window.plot, Qt.MouseButton.LeftButton, pos=start)
        QTest.mouseMove(self.window.plot, end, delay=20)
        QTest.mouseRelease(self.window.plot, Qt.MouseButton.LeftButton, pos=end)
        self.assertEqual(self.document.selected, 5)
        self.assertGreater(self.document.preset["bands"][5]["frequency"], 1000)
        self.assertGreater(self.document.preset["bands"][5]["gain"], 0)

    def test_add_remove_and_reject_capacity_without_losing_edits(self):
        count = len(self.document.preset["bands"])
        QTest.mouseClick(self.window.add_button, Qt.MouseButton.LeftButton)
        self.assertEqual(len(self.document.preset["bands"]), count + 1)
        QTest.mouseClick(self.window.remove_button, Qt.MouseButton.LeftButton)
        self.assertEqual(len(self.document.preset["bands"]), count)
        before = deepcopy(self.document.preset)
        invalid = deepcopy(before)
        invalid["bands"] = [{"type": "lowPass", "frequency": 1000, "gain": 0, "q": 1,
                              "enabled": True, "slopeDbPerOct": 96} for _ in range(5)]
        with self.assertRaises(ValueError):
            self.document.install(invalid)
        self.assertEqual(self.document.preset, before)

    def test_real_file_export_import_save_and_session_restore(self):
        self.document.edit_band(2, gain=4.25, frequency=333.3)
        self.document.set_preamp(-6.125)
        exported = self.settings / "export.json"
        self.document.export_file(exported)
        expected = presets.load(exported)
        self.document.reset()
        self.document.import_file(exported)
        self.assertEqual(self.document.preset, expected)
        saved = self.document.save_copy("Studio headphones")
        self.assertTrue(saved.is_file())
        self.assertEqual(self.window.saved_list.count(), 1)
        self.document.set_bypass(True)
        self.document.flush()
        restored = Document(self.core, database_path(), self.settings)
        self.assertEqual(restored.preset, self.document.preset)
        self.assertTrue(restored.bypassed)

    def test_corrupt_import_is_rejected_and_existing_file_preserved(self):
        path = self.settings / "invalid.json"
        path.write_text('{"app":"SonanceEQ","version":2}')
        before = deepcopy(self.document.preset)
        with self.assertRaises(ValueError):
            self.document.import_file(path)
        self.assertEqual(self.document.preset, before)
        self.assertTrue(path.exists())


if __name__ == "__main__":
    unittest.main()
