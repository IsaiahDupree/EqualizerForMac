from __future__ import annotations

from copy import deepcopy
import json
import os
from pathlib import Path
import sqlite3
import tempfile
import uuid

from PySide6.QtCore import QObject, Signal
import presets


def flat_preset():
    return {"app": "SonanceEQ", "version": 1, "name": "Flat", "preampDb": 0,
            "bands": [{"type": "peaking", "frequency": frequency, "gain": 0, "q": 1.414,
                       "enabled": True, "slopeDbPerOct": 12}
                      for frequency in (31.25, 62.5, 125, 250, 500, 1000, 2000, 4000, 8000, 16000)]}


def atomic_json(path: Path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent, delete=False) as stream:
            temporary = Path(stream.name)
            json.dump(value, stream, ensure_ascii=False, indent=2, allow_nan=False)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if temporary and temporary.exists():
            temporary.unlink()


class Document(QObject):
    changed = Signal()
    error = Signal(str)
    saved = Signal()

    def __init__(self, core, database: Path, settings: Path):
        super().__init__()
        self.core, self.database, self.settings = core, Path(database), Path(settings)
        connection = presets.database(self.database)
        try:
            self.headphone_count = connection.execute("SELECT count(*) FROM presets").fetchone()[0]
        finally:
            connection.close()
        self.preset, self.rate, self.bypassed, self.selected, self.modified = flat_preset(), 48000, False, 0, False
        self.restore_warning = ""
        session = self.settings / "session.json"
        if session.exists():
            try:
                if session.stat().st_size > 1024 * 1024:
                    raise ValueError("Session exceeds 1 MiB")
                value = json.loads(session.read_text(encoding="utf-8"), object_pairs_hook=presets.unique_object)
                if value["version"] != 1 or type(value["bypassed"]) is not bool or value["rate"] not in (44100, 48000, 96000):
                    raise ValueError("Unsupported saved session")
                preset = presets.validate(value["preset"])
                self.core.response(preset, value["rate"], value["bypassed"])
                self.preset, self.rate, self.bypassed = preset, value["rate"], value["bypassed"]
            except (ValueError, KeyError, TypeError, OSError) as error:
                preserved = self.settings / ("session-unreadable-" + uuid.uuid4().hex + ".json")
                session.rename(preserved)
                self.restore_warning = "The previous session could not be restored. Its file has been preserved. " + str(error)
        self.selected = 0 if self.preset["bands"] else -1
        self.frequencies, self.response = self.core.response(self.preset, self.rate, self.bypassed)

    def install(self, value, *, modified=False, selected=None, bypassed=None, rate=None):
        candidate = presets.validate(value)
        next_rate = self.rate if rate is None else rate
        next_bypass = self.bypassed if bypassed is None else bypassed
        if next_rate not in (44100, 48000, 96000) or type(next_bypass) is not bool:
            raise ValueError("Unsupported response preview settings")
        frequencies, response = self.core.response(candidate, next_rate, next_bypass)
        self.preset, self.rate, self.bypassed = candidate, next_rate, next_bypass
        self.frequencies, self.response, self.modified = frequencies, response, modified
        choice = self.selected if selected is None else selected
        self.selected = max(0, min(choice, len(candidate["bands"]) - 1)) if candidate["bands"] else -1
        self.changed.emit()

    def choose(self, index):
        selected = index if 0 <= index < len(self.preset["bands"]) else -1
        if selected != self.selected:
            self.selected = selected
            self.changed.emit()

    def edit_band(self, index, **fields):
        if not 0 <= index < len(self.preset["bands"]):
            raise ValueError("Select a band first")
        candidate = deepcopy(self.preset)
        candidate["bands"][index].update(fields)
        self.install(candidate, modified=True, selected=index)

    def add_band(self):
        candidate = deepcopy(self.preset)
        candidate["bands"].append({"type": "peaking", "frequency": 1000, "gain": 0, "q": 1,
                                   "enabled": True, "slopeDbPerOct": 12})
        self.install(candidate, modified=True, selected=len(candidate["bands"]) - 1)

    def remove_band(self):
        if self.selected < 0:
            return
        candidate = deepcopy(self.preset)
        del candidate["bands"][self.selected]
        self.install(candidate, modified=True)

    def set_preamp(self, gain):
        self.install({**deepcopy(self.preset), "preampDb": gain}, modified=True)

    def set_bypass(self, enabled):
        self.install(self.preset, modified=self.modified, bypassed=bool(enabled))

    def rename(self, name):
        self.install({**deepcopy(self.preset), "name": name}, modified=True)

    def reset(self):
        self.install(flat_preset(), selected=0, bypassed=False)

    def load_headphone(self, identity):
        self.install(presets.export_headphone(self.database, identity), selected=0, bypassed=False)

    def search(self, query):
        return presets.search(self.database, query, 100)

    def import_file(self, path):
        self.install(presets.load(Path(path)), selected=0, bypassed=False)

    def export_file(self, path):
        value = presets.validate(self.preset)
        self.core.response(value, self.rate, self.bypassed)
        atomic_json(Path(path), value)
        self.modified = False
        self.changed.emit()

    def save_copy(self, name):
        value = presets.validate({**deepcopy(self.preset), "name": name})
        self.core.response(value, self.rate, self.bypassed)
        path = self.settings / "presets" / (uuid.uuid4().hex + ".json")
        atomic_json(path, value)
        self.install(value, modified=False)
        self.saved.emit()
        return path

    def saved_presets(self):
        result = []
        directory = self.settings / "presets"
        if not directory.exists():
            return result
        for path in sorted(directory.glob("*.json"))[:500]:
            try:
                value = presets.load(path)
                result.append((value["name"], path))
            except (ValueError, OSError):
                self.error.emit("A saved preset could not be read. Its file has been preserved.")
        return sorted(result, key=lambda value: value[0].casefold())

    def flush(self):
        atomic_json(self.settings / "session.json", {"version": 1, "preset": self.preset,
                    "rate": self.rate, "bypassed": self.bypassed})
