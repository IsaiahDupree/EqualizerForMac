from __future__ import annotations

import argparse
import json
from pathlib import Path
import platform
import sys

from PySide6.QtCore import QStandardPaths, QTimer
from PySide6.QtGui import QFontDatabase
from PySide6.QtWidgets import QApplication, QMessageBox

from .document import Document
from .native import NativeCore, database_path
from .window import EditorWindow


def main(argv=None):
    parser = argparse.ArgumentParser(description="Sonance EQ desktop preset editor")
    parser.add_argument("--preset", type=Path)
    parser.add_argument("--settings-dir", type=Path, help=argparse.SUPPRESS)
    parser.add_argument("--smoke-dir", type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    app = QApplication.instance() or QApplication([sys.argv[0]])
    app.setApplicationName("SonanceEQ")
    app.setApplicationDisplayName("Sonance EQ")
    app.setOrganizationName("Sonance")
    app.setFont(QFontDatabase.systemFont(QFontDatabase.SystemFont.GeneralFont))
    try:
        settings = args.settings_dir or Path(QStandardPaths.writableLocation(QStandardPaths.StandardLocation.AppConfigLocation))
        core = NativeCore()
        document = Document(core, database_path(), settings)
        if args.preset:
            document.import_file(args.preset)
        window = EditorWindow(document)
    except Exception as error:
        if args.smoke_dir:
            args.smoke_dir.mkdir(parents=True, exist_ok=True)
            (args.smoke_dir / "startup-error.txt").write_text(str(error))
            return 1
        QMessageBox.critical(None, "Sonance EQ could not start", str(error))
        return 1
    window.show()
    if args.smoke_dir:
        def capture():
            args.smoke_dir.mkdir(parents=True, exist_ok=True)
            if not window.grab().save(str(args.smoke_dir / "desktop.png")):
                app.exit(1)
                return
            state = {"status": "passed", "platform": platform.platform(), "frozen": bool(getattr(sys, "frozen", False)),
                     "native_abi": core.library.sonance_abi_version(), "headphone_count": document.headphone_count,
                     "preset": document.preset, "response_points": len(document.response),
                     "system_audio_connected": False, "window_size": [window.width(), window.height()]}
            (args.smoke_dir / "smoke.json").write_text(json.dumps(state, indent=2) + "\n")
            window.close()
            app.quit()
        QTimer.singleShot(500, capture)
    return app.exec()
