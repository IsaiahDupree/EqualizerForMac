#!/usr/bin/env python3
"""Fixed, serial Sonance native build/test harness; callable only by Orion jobs."""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile

import worker


def wsl_path(value):
    text = str(value).replace("\\", "/")
    if not re.match(r"^[A-Za-z]:/", text):
        raise ValueError("expected an absolute Windows staging path")
    return "/mnt/" + text[0].lower() + text[2:]


def execute(command, output, label, *, environment=None, input_text=None, timeout=120):
    done = subprocess.run(list(map(str, command)), env=environment, input=input_text,
                          capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout)
    text = done.stdout + done.stderr
    (output / (label + ".log")).write_text(text, encoding="utf-8")
    if done.returncode:
        print(text[-16000:], flush=True)
        raise RuntimeError(f"{label} exited with code {done.returncode}")
    return done.stdout, text


def msvc_environment(profile):
    script = profile["tools"]["vsdevcmd"]["path"]
    if any(char in script for char in '\n\r"&|<>^%'):
        raise ValueError("unexpected characters in the registered Visual Studio path")
    with tempfile.TemporaryDirectory(prefix="orion-msvc-env-") as directory:
        wrapper = Path(directory) / "environment.cmd"
        wrapper.write_text(f'@echo off\ncall "{script}" -no_logo -arch=x64 -host_arch=x64 >nul\n'
                           'if errorlevel 1 exit /b %errorlevel%\nset\n', encoding="utf-8")
        done = subprocess.run(["cmd.exe", "/d", "/c", str(wrapper)], capture_output=True,
                              text=True, encoding="utf-8", errors="replace", timeout=60, check=True)
    result = os.environ.copy()
    for line in done.stdout.splitlines():
        key, separator, value = line.partition("=")
        if separator and key and not key.startswith("="):
            result[key] = value
    return result


def native(request, source, output):
    profile = request["profile"]
    windows = platform.system() == "Windows"
    if platform.system() != ("Windows" if profile["kind"] == "windows" else "Linux"):
        raise RuntimeError("profile is not running on its declared native OS")
    tools = profile["tools"]
    for name, entry in tools.items():
        if worker.file_sha(entry["path"]) != entry["sha256"]:
            raise RuntimeError("toolchain pin mismatch: " + name)
    env = msvc_environment(profile) if windows else os.environ.copy()
    env.update(PYTHONDONTWRITEBYTECODE="1", PYTHONUTF8="1", PYTHONIOENCODING="utf-8")
    if profile["sanitizers"]:
        env["ASAN_OPTIONS"] = "halt_on_error=1" + ("" if windows else ":detect_leaks=1")
        if not windows:
            env["UBSAN_OPTIONS"] = "halt_on_error=1:print_stacktrace=1"
    with tempfile.TemporaryDirectory(prefix="orion-sonance-build-") as directory:
        build = Path(directory)
        configure = [tools["cmake"]["path"], "-S", source / "portable", "-B", build,
            "-G", "Ninja", "-DCMAKE_BUILD_TYPE=Release", "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON",
            "-DCMAKE_CXX_COMPILER=" + tools["compiler"]["path"],
            "-DCMAKE_MAKE_PROGRAM=" + tools["ninja"]["path"],
            "-DSONANCE_SANITIZERS=" + ("ON" if profile["sanitizers"] else "OFF")]
        execute(configure, output, "configure", environment=env)
        execute([tools["cmake"]["path"], "--build", build, "--parallel", "1"], output, "build", environment=env)
        ctest = Path(tools["cmake"]["path"]).with_name("ctest.exe" if windows else "ctest")
        _, tests = execute([ctest, "--test-dir", build, "--output-on-failure", "-V", "-j", "1"],
                           output, "ctest", environment=env, timeout=60)
        matches = re.findall(r"PASS: (\d+) DSP assertions", tests)
        if len(matches) != 1 or int(matches[0]) < 5278:
            raise RuntimeError("CTest did not report the complete DSP assertion gate")
        _, python_tests = execute([sys.executable, "-m", "unittest", "discover", "-s", source / "portable/tests",
                                   "-p", "test_*.py", "-v"], output, "presets", environment=env, timeout=60)
        count = re.search(r"Ran (\d+) tests", python_tests)
        if count is None or int(count[1]) != 5:
            raise RuntimeError("preset test report is incomplete")
        spec = importlib.util.spec_from_file_location("sonance_verify", source / "portable/tests/verify.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        requests = module.fixtures()
        coefficient_tool = build / ("sonance_eq_coefficients.exe" if windows else "sonance_eq_coefficients")
        coefficients, _ = execute([coefficient_tool], output, "coefficients", environment=env, input_text=requests, timeout=60)
        if len(coefficients.splitlines()) != len(requests.splitlines()):
            raise RuntimeError("coefficient output count mismatch")
        (output / "coefficients.jsonl").write_text(coefficients, encoding="utf-8")
        (output / "requests.txt").write_text(requests, encoding="utf-8")
        (output / "bin").mkdir()
        for name in ("sonance_eq_tests", "sonance_eq_coefficients"):
            executable = build / (name + (".exe" if windows else ""))
            shutil.copy2(executable, output / "bin" / executable.name)
        info = list((build / "CMakeFiles").glob("*/CMakeCXXCompiler.cmake"))
        if len(info) != 1:
            raise RuntimeError("CMake compiler identification is missing or ambiguous")
        compiler_info = info[0].read_text()
        compiler_version = re.search(r'set\(CMAKE_CXX_COMPILER_VERSION "([^"]+)"\)', compiler_info)
        compiler_id = re.search(r'set\(CMAKE_CXX_COMPILER_ID "([^"]+)"\)', compiler_info)
        if compiler_version is None or compiler_id is None:
            raise RuntimeError("CMake compiler version is unavailable")
        shutil.copy2(build / "CMakeCache.txt", output / "CMakeCache.txt")
        shutil.copy2(build / "compile_commands.json", output / "compile_commands.json")
        shutil.copy2(build / "Testing/Temporary/LastTest.log", output / "LastTest.log")
        with zipfile.ZipFile(output / ("sonance-core-" + request["profile_name"] + ".zip"), "w", zipfile.ZIP_DEFLATED) as package:
            for executable in (output / "bin").iterdir():
                package.write(executable, "bin/" + executable.name)
            for relative in ("portable/include/sonance/eq.hpp", "portable/presets.py", "portable/README.md",
                             "Sources/SonanceEQ/Resources/autoeq.sqlite", "LICENSE", "THIRD-PARTY-NOTICES.md"):
                package.write(source / relative, relative)
        result = {"status": "passed", "profile": request["profile_name"], "platform": platform.platform(),
                "machine": platform.machine(), "compiler_id": compiler_id[1], "compiler_version": compiler_version[1],
                "source_sha256": request["source_sha256"], "dsp_assertions": int(matches[0]),
                "preset_tests": int(count[1]), "coefficient_cases": len(requests.splitlines()),
                "sanitizers": (["address"] if windows else ["address", "undefined", "leaks"]) if profile["sanitizers"] else [],
                "hardware_audio_verified": False, "retail_app_produced": False}
        if profile.get("desktop"):
            import ui_jobs
            result.update(ui_jobs.desktop(request, source, build, output, env, execute))
        return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--request", type=Path, required=True)
    parser.add_argument("--linux", action="store_true")
    args = parser.parse_args()
    if os.environ.get("ORION_SONANCE_TYPED_WORKER") != "1":
        raise RuntimeError("this harness requires the authenticated Orion typed worker")
    request = json.loads(args.request.read_text(encoding="utf-8"))
    source, output = Path(request["source"]), Path(request["output"])
    if args.linux:
        source, output = Path(wsl_path(request["source"])), Path(wsl_path(request["output"]))
    output.mkdir(parents=True, exist_ok=True)
    if request["profile"]["kind"] in {"linux", "linux-setup", "linux-ui-setup"} and not args.linux:
        if platform.system() != "Windows":
            raise RuntimeError("the bridge must start on the registered Windows worker")
        command = ["wsl.exe", "-d", request["profile"]["distribution"], "-u", "root", "--",
                   "/usr/bin/timeout", "--kill-after=10s", "540s", "/usr/bin/env",
                   "ORION_SONANCE_TYPED_WORKER=1", "PYTHONDONTWRITEBYTECODE=1", "PYTHONUTF8=1",
                   "/usr/bin/python3", wsl_path(source / "portable/orion/run.py"),
                   "--request", wsl_path(args.request), "--linux"]
        done = subprocess.run(command, timeout=560)
        if done.returncode:
            raise RuntimeError("Linux worker failed with code " + str(done.returncode))
        return
    if worker.digest(worker.source_manifest(source)) != request["source_sha256"]:
        raise RuntimeError("source changed before execution")
    if request["profile"]["kind"] in {"windows-ui-setup", "linux-ui-setup"}:
        import ui_jobs
        result = ui_jobs.setup(request, source, output, execute)
    elif request["profile"]["kind"] == "linux-setup":
        setup_env = {**os.environ, "DEBIAN_FRONTEND": "noninteractive"}
        package_state, _ = execute(["/usr/bin/dpkg-query", "-W", "-f=${Status}", "man-db"],
                                   output, "dpkg-state", environment=setup_env)
        configured = []
        if "half-configured" in package_state:
            execute(["/usr/bin/dpkg", "--configure", "man-db"], output, "dpkg-man-db",
                    environment=setup_env, timeout=240)
            configured.append("man-db")
        execute(["/usr/bin/apt-get", "update", "-qq"], output, "apt-update", timeout=240)
        execute(["/usr/bin/apt-get", "install", "-y", "--no-install-recommends", "cmake", "ninja-build"],
                output, "apt-install", environment=setup_env, timeout=240)
        result = {"status": "passed", "profile": "prepare-linux", "installed_packages": ["cmake", "ninja-build"],
                  "configured_packages": configured}
    else:
        result = native(request, source, output)
    if worker.digest(worker.source_manifest(source)) != request["source_sha256"]:
        raise RuntimeError("source changed during execution")
    (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result), flush=True)


if __name__ == "__main__":
    main()
