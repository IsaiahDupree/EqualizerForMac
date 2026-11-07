"""Copy the exact installed dependency notices into an onedir preview bundle."""
import importlib.metadata
import hashlib
import json
from pathlib import Path
import platform
import shutil
import sys

destination = Path(sys.argv[1])
destination.mkdir(parents=True, exist_ok=True)
packages = []
root = Path(__file__).resolve().parent
manifest = json.loads((root / "licenses/sources.json").read_text())
upstream_notices = []
for entry in manifest["files"]:
    relative = Path(entry["path"])
    if relative.is_absolute() or ".." in relative.parts:
        raise RuntimeError("Unsafe vendored notice/asset path")
    source = root / relative
    data = source.read_bytes()
    if len(data) != entry["bytes"] or hashlib.sha256(data).hexdigest() != entry["sha256"]:
        raise RuntimeError("Vendored notice/asset differs from its upstream intake: " + str(relative))
    if relative.suffix == ".ttf":
        continue
    target = destination / "upstream" / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
    upstream_notices.append(target.relative_to(destination).as_posix())
shutil.copy2(root / "licenses/sources.json", destination / "upstream-sources.json")
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
                notices.append(target.relative_to(destination).as_posix())
    if name in ("PySide6-Essentials", "shiboken6"):
        if distribution.version != "6.10.2":
            raise RuntimeError("Qt notices are pinned to version 6.10.2")
        pyside_notices = [path for path in upstream_notices if "/pyside-6.10.2/" in path]
        if not any(path.endswith("/LGPL-3.0-only.txt") for path in pyside_notices):
            raise RuntimeError("The upstream Qt for Python LGPL text is missing")
        notices.extend(pyside_notices)
    if not notices:
        raise RuntimeError("Installed dependency notices are missing: " + name)
    packages.append({"name": name, "version": distribution.version, "notices": notices})
python_notices = [path for path in upstream_notices if "/python-" + platform.python_version() + "/" in path]
if not python_notices:
    raise RuntimeError("The exact bundled Python version needs its upstream license")
packages.extend([
    {"name": "Python", "version": platform.python_version(), "notices": python_notices},
    {"name": "Qt", "version": "6.10.2", "notices": [path for path in upstream_notices if "/qtbase-6.10.2/" in path or "/qtsvg-6.10.2/" in path]},
    {"name": "Inter", "version": "4.1", "notices": [path for path in upstream_notices if path.endswith("Inter-LICENSE.txt")]},
])
(destination / "packages.json").write_text(json.dumps(packages, indent=2) + "\n")
(destination / "README.txt").write_text(
    "Qt and PySide6 are dynamically linked, unmodified open-source components.\n"
    "Their licenses apply independently from Sonance's original application code.\n"
    "Qt/PySide6 version: 6.10.2. Upstream LGPL/GPL texts are included even when\n"
    "a wheel omits them or includes only the commercial-license reference.\n"
    "See upstream-sources.json for the exact source URLs and SHA-256 hashes.\n"
    "The Qt license choice for this preview is LGPLv3. Source information:\n"
    "https://code.qt.io/cgit/pyside/pyside-setup.git/\n"
    "https://code.qt.io/cgit/qt/qtbase.git/\n"
    "https://doc.qt.io/qtforpython-6.10/licenses.html\n"
    "https://www.qt.io/development/open-source-lgpl-obligations\n"
    "PyInstaller is a build tool with an exception permitting distribution of non-free applications.\n"
    "https://pyinstaller.org/en/stable/license.html\n")
print(json.dumps({"packages": [{"name": p["name"], "version": p["version"], "notice_files": len(p["notices"])} for p in packages]}))
