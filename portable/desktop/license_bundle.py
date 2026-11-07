"""Copy the exact installed dependency notices into an onedir preview bundle."""
import importlib.metadata
import json
from pathlib import Path
import shutil
import sys

destination = Path(sys.argv[1])
destination.mkdir(parents=True, exist_ok=True)
packages = []
for name in ("PySide6-Essentials", "shiboken6", "pyinstaller"):
    distribution = importlib.metadata.distribution(name)
    notices = []
    for relative in distribution.files or []:
        if any(word in str(relative).lower() for word in ("license", "copying", "notice")):
            source = Path(distribution.locate_file(relative))
            if source.is_file() and source.stat().st_size < 4 * 1024 * 1024:
                target = destination / name / str(relative).replace("../", "")
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, target)
                notices.append(str(target.relative_to(destination)))
    if not notices:
        raise RuntimeError("Installed dependency notices are missing: " + name)
    packages.append({"name": name, "version": distribution.version, "notices": notices})
(destination / "packages.json").write_text(json.dumps(packages, indent=2) + "\n")
(destination / "README.txt").write_text(
    "Qt and PySide6 are dynamically linked, unmodified open-source components.\n"
    "Their licenses apply independently from Sonance's original application code.\n"
    "Qt/PySide6 version: 6.10.2. Source and licensing information:\n"
    "https://code.qt.io/cgit/pyside/pyside-setup.git/\n"
    "https://code.qt.io/cgit/qt/qtbase.git/\n"
    "https://doc.qt.io/qtforpython-6.10/licenses.html\n"
    "https://www.qt.io/licensing/open-source-lgpl-obligations\n"
    "PyInstaller is a build tool with an exception permitting distribution of non-free applications.\n"
    "https://pyinstaller.org/en/stable/license.html\n")
print(json.dumps({"packages": [{"name": p["name"], "version": p["version"], "notice_files": len(p["notices"])} for p in packages]}))
