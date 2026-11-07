"""Fixed desktop dependency, widget-test and native preview packaging steps."""
from __future__ import annotations

import importlib.metadata
import json
import os
from pathlib import Path
import platform
import shutil
import sys
import tempfile
import venv
import zipfile


def setup(request, source, output, execute):
    kind = request["profile"]["kind"]
    expected = "Windows" if kind == "windows-ui-setup" else "Linux"
    if platform.system() != expected:
        raise RuntimeError("UI setup must run on its declared Orion operating system")
    directory = Path(request["profile"]["venv"])
    directory.parent.mkdir(parents=True, exist_ok=True)
    lock = directory.parent / (directory.name + ".setup.lock")
    descriptor = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    try:
        os.write(descriptor, str(os.getpid()).encode())
        if expected == "Linux":
            execute(["/usr/bin/apt-get", "install", "-y", "--no-install-recommends", "python3-venv",
                     "libegl1", "libgl1", "libopengl0", "libxkbcommon0", "libxcb-cursor0", "fonts-dejavu-core"],
                    output, "ui-system-dependencies", timeout=240,
                    environment={**os.environ, "DEBIAN_FRONTEND": "noninteractive"})
        venv.EnvBuilder(with_pip=True).create(directory)
        python = directory / ("Scripts/python.exe" if expected == "Windows" else "bin/python")
        execute([python, "-m", "pip", "--isolated", "install", "--index-url", "https://pypi.org/simple",
                 "--only-binary=:all:", "--disable-pip-version-check", "--no-input", "--progress-bar", "off",
                 "--report", output / "pip-report.json", "-r", source / "portable/desktop/requirements.txt"],
                output, "ui-python-dependencies", timeout=420)
        freeze, _ = execute([python, "-m", "pip", "freeze"], output, "ui-environment", timeout=30)
        (directory / "requirements-observed.txt").write_text(freeze, encoding="utf-8")
        shutil.copy2(output / "pip-report.json", directory / "pip-report.json")
        return {"status": "passed", "profile": request["profile_name"], "venv": str(directory),
                "requirements": freeze.splitlines()}
    finally:
        os.close(descriptor)
        lock.unlink()


def desktop(request, source, build, output, environment, execute):
    runtime = request["profile"]["ui_runtime"]
    python = runtime["python_exe"]
    import worker
    for entry in runtime["pins"].values():
        if worker.file_sha(entry["path"]) != entry["sha256"]:
            raise RuntimeError("desktop Python/Qt runtime changed after admission")
    windows = platform.system() == "Windows"
    library = build / ("sonance_eq_bridge.dll" if windows else "libsonance_eq_bridge.so")
    env = {**environment, "QT_QPA_PLATFORM": "offscreen", "SONANCE_EQ_CORE_LIBRARY": str(library),
           "SONANCE_EQ_DATABASE": str(source / "Sources/SonanceEQ/Resources/autoeq.sqlite"),
           "SONANCE_UI_TEST_OUTPUT": str(output / "screenshots"),
           "PYTHONPATH": os.pathsep.join([str(source / "portable"), str(source / "portable/desktop")])}
    _, tests = execute([python, "-m", "unittest", "discover", "-s", source / "portable/desktop/tests", "-v"],
                       output, "desktop-interactions", environment=env, timeout=120)
    import re
    count = re.search(r"Ran (\d+) tests", tests)
    if count is None or int(count[1]) < 8:
        raise RuntimeError("desktop interaction test report is incomplete")
    with tempfile.TemporaryDirectory(prefix="orion-sonance-ui-") as temporary:
        work = Path(temporary)
        command = [python, "-m", "PyInstaller", "--noconfirm", "--clean", "--onedir", "--windowed",
                   "--name", "SonanceEQ", "--distpath", work / "dist", "--workpath", work / "build",
                   "--specpath", work, "--paths", source / "portable", "--paths", source / "portable/desktop",
                   "--add-binary", str(library) + os.pathsep + "sonance/native",
                   "--add-data", str(source / "Sources/SonanceEQ/Resources/autoeq.sqlite") + os.pathsep + "sonance/data",
                   "--add-data", str(source / "LICENSE") + os.pathsep + "sonance/notices",
                   "--add-data", str(source / "THIRD-PARTY-NOTICES.md") + os.pathsep + "sonance/notices",
                   "--add-data", str(source / "portable/desktop/assets") + os.pathsep + "sonance/assets",
                   source / "portable/desktop/app.py"]
        execute(command, output, "desktop-package", environment=env, timeout=420)
        package = work / "dist/SonanceEQ"
        executable = package / ("SonanceEQ.exe" if windows else "SonanceEQ")
        if not executable.is_file():
            raise RuntimeError("native desktop executable was not produced")
        frozen_env = {**env}
        frozen_env.pop("SONANCE_EQ_CORE_LIBRARY", None)
        frozen_env.pop("SONANCE_EQ_DATABASE", None)
        frozen_env.pop("PYTHONPATH", None)
        execute([executable, "--settings-dir", work / "settings", "--smoke-dir", output / "frozen-smoke"],
                output, "desktop-frozen-startup", environment=frozen_env, timeout=90)
        smoke = json.loads((output / "frozen-smoke/smoke.json").read_text())
        if not smoke["frozen"] or smoke["native_abi"] != 1 or smoke["headphone_count"] != 8850 or smoke["response_points"] != 512:
            raise RuntimeError("packaged desktop startup did not verify its real native core/data")
        # Preserve exact installed license files beside the dynamically linked bundle.
        license_script = source / "portable/desktop/license_bundle.py"
        execute([python, license_script, package / "OPEN-SOURCE-LICENSES"], output, "desktop-notices", environment=env, timeout=30)
        shutil.copy2(source / "portable/desktop/PREVIEW.md", package / "README-PREVIEW.md")
        shutil.copy2(source / "LICENSE", package / "SONANCE-SOURCE-LICENSE.txt")
        shutil.copy2(source / "THIRD-PARTY-NOTICES.md", package / "THIRD-PARTY-NOTICES.md")
        archive_name = "SonanceEQ-" + ("Windows" if windows else "Linux") + "-UI-Preview.zip"
        with zipfile.ZipFile(output / archive_name, "w", zipfile.ZIP_DEFLATED) as archive:
            for path in sorted(package.rglob("*")):
                if path.is_file():
                    archive.write(path, "SonanceEQ/" + path.relative_to(package).as_posix())
    return {"desktop_widget_tests": int(count[1]), "desktop_bundle": archive_name,
            "frozen_startup": smoke, "qt_versions": runtime["versions"], "system_audio_connected": False}
