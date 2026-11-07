#!/usr/bin/env python3
"""Provision and stop a task-scoped Orion controller; never switch the shared API."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import urllib.request
import zipfile


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def receipt(root, action, status, **fields):
    record = {"time": datetime.now(timezone.utc).isoformat(), "action": action, "status": status, **fields}
    with (root / "admin-receipts.jsonl").open("a", encoding="utf-8") as stream:
        stream.write(json.dumps(record) + "\n")


def linux_tools():
    code = """import hashlib,json,pathlib,shutil
result={}
for name,executable in [('compiler','g++'),('cmake','cmake'),('ninja','ninja'),('ctest','ctest'),('python','python3')]:
 p=shutil.which(executable)
 if p:
  p=pathlib.Path(p).resolve()
  result[name]={'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
print(json.dumps(result))
"""
    import base64
    encoded = base64.b64encode(code.encode()).decode()
    command = ["wsl.exe", "-d", "Ubuntu", "-u", "root", "--", "/usr/bin/python3", "-c",
               "import base64;exec(base64.b64decode('" + encoded + "'))"]
    done = subprocess.run(command, capture_output=True, text=True, timeout=40, check=True)
    return json.loads(done.stdout)


def register(root, source):
    sys.path.insert(0, str(source / "portable/orion"))
    import worker
    identity = "sonance-core-" + worker.digest(worker.source_manifest(source))[:12]
    vs = Path(r"C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools")
    versions = sorted((vs / "VC/Tools/MSVC").glob("*/bin/Hostx64/x64/cl.exe"))
    if not versions:
        raise RuntimeError("Orion's native Visual Studio 2022 C++ compiler is unavailable")
    paths = {"compiler": versions[-1], "vsdevcmd": vs / "Common7/Tools/VsDevCmd.bat",
             "cmake": vs / "Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe",
             "ctest": vs / "Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/ctest.exe",
             "ninja": vs / "Common7/IDE/CommonExtensions/Microsoft/CMake/Ninja/ninja.exe"}
    tools = {name: {"path": str(path), "sha256": sha(path)} for name, path in paths.items()}
    profiles = {"windows": {"kind": "windows", "sanitizers": False, "tools": tools},
                "prepare-linux": {"kind": "linux-setup", "distribution": "Ubuntu"}}
    if (versions[-1].parent / "clang_rt.asan_dynamic-x86_64.dll").is_file():
        profiles["windows-asan"] = {"kind": "windows", "sanitizers": True, "tools": tools}
    linux = linux_tools()
    if set(linux) == {"compiler", "cmake", "ninja", "ctest", "python"}:
        profiles["linux"] = {"kind": "linux", "distribution": "Ubuntu", "sanitizers": False, "tools": linux}
        profiles["linux-sanitizers"] = {"kind": "linux", "distribution": "Ubuntu", "sanitizers": True, "tools": linux}
    project = {"root": str(source), "source_sha256": worker.digest(worker.source_manifest(source)),
               "python_exe": sys.executable, "python_exe_sha256": sha(sys.executable), "profiles": profiles}
    registry = root / "control/sonance-projects.json"
    registry.parent.mkdir(parents=True, exist_ok=True)
    data = json.loads(registry.read_text()) if registry.exists() else {"projects": {}}
    data["projects"][identity] = project
    temporary = registry.with_suffix(".tmp")
    temporary.write_text(json.dumps(data, indent=2) + "\n")
    os.replace(temporary, registry)
    receipt(root, "register.sonance_core", "success", project_id=identity,
            source_sha256=project["source_sha256"], profiles=sorted(profiles))
    return identity, project


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--archive-sha256")
    parser.add_argument("--retained-runtime", type=Path)
    parser.add_argument("--refresh", action="store_true")
    parser.add_argument("--serve", action="store_true")
    parser.add_argument("--stop", action="store_true")
    args = parser.parse_args()
    if os.name != "nt":
        raise RuntimeError("provisioning requires the authenticated Orion Windows host")
    root = args.root.resolve()
    root.mkdir(parents=True, exist_ok=True)
    source, runtime = root / "source", root / "runtime"
    if args.stop:
        with urllib.request.urlopen("http://127.0.0.1:18810/api/health", timeout=10) as response:
            observed = json.load(response)
        state = json.loads((root / "server.json").read_text())
        if observed["pid"] != state["pid"] or Path(observed["control_home"]).resolve() != root / "control":
            raise RuntimeError("the private API no longer matches this task")
        token = Path(r"C:\orion\control\token").read_text().strip()
        request = urllib.request.Request("http://127.0.0.1:18810/api/services/orion/workers.capabilities", data=b'{"params":{}}',
            headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
        with urllib.request.urlopen(request, timeout=45) as response:
            queue = json.load(response)["result"]
        if queue.get("active_job_id") or queue.get("queue_depth"):
            raise RuntimeError("private Sonance worker still has unfinished work")
        subprocess.run(["taskkill.exe", "/PID", str(state["pid"]), "/T", "/F"], check=True, timeout=20)
        receipt(root, "controller.stop", "success", pid=state["pid"])
        return
    if args.serve:
        env = os.environ.copy()
        env.update(ORION_CONTROL_HOME=str(root / "control"), ORION_CONTROL_BIND="127.0.0.1", ORION_CONTROL_PORT="18810",
            ORION_CONTROL_TOKEN_FILE=r"C:\orion\control\token", ORION_WORKER_HOME=str(root / "workers"),
            ORION_WORKER_INPUT_ROOT=str(root / "inputs"), ORION_SONANCE_PROJECTS_FILE=str(root / "control/sonance-projects.json"),
            ORION_RECEIPTS_PATH=str(root / "control/receipts.jsonl"), PYTHONDONTWRITEBYTECODE="1")
        (root / "inputs").mkdir(exist_ok=True)
        child = subprocess.Popen([sys.executable, "-u", str(runtime / "control-api/orion_control_api.py")], cwd=runtime, env=env)
        (root / "server.json").write_text(json.dumps({"pid": child.pid, "port": 18810, "runtime": str(runtime)}))
        receipt(root, "controller.start", "running", pid=child.pid, lifetime_seconds=3600)
        try:
            child.wait(timeout=3600)
        finally:
            if child.poll() is None:
                subprocess.run(["taskkill.exe", "/PID", str(child.pid), "/T", "/F"], timeout=20)
            receipt(root, "controller.exit", "complete", pid=child.pid, exit_code=child.returncode)
        return
    receipt(root, "controller.provision", "running", refresh=args.refresh)
    if not args.refresh:
        if not args.archive or sha(args.archive) != args.archive_sha256 or source.exists() or runtime.exists():
            raise ValueError("a fresh task directory and exact archive hash are required")
        with zipfile.ZipFile(args.archive) as archive:
            entries = archive.infolist()
            if len(entries) > 256 or sum(entry.file_size for entry in entries) > 64 * 1024 * 1024:
                raise ValueError("source archive exceeds bounds")
            for entry in entries:
                name = entry.filename
                if name.startswith("/") or "\\" in name or ":" in name or ".." in name.split("/"):
                    raise ValueError("unsafe source archive path")
            archive.extractall(source)
        shutil.copytree(args.retained_runtime, runtime, ignore=shutil.ignore_patterns("__pycache__", ".git"))
        spec = importlib.util.spec_from_file_location("sonance_integrate", source / "portable/orion/integrate.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        module.integrate(runtime, source / "portable/orion/worker.py")
    identity, project = register(root, source)
    receipt(root, "controller.provision", "success", project_id=identity)
    print(json.dumps({"root": str(root), "project_id": identity,
                      "source_sha256": project["source_sha256"], "profiles": sorted(project["profiles"])}))


if __name__ == "__main__":
    main()
