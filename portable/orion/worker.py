"""Typed Sonance-only build extension for an isolated Orion worker runtime."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat

PARAMETERS = ["project_id", "profile", "expected_source_sha256", "timeout_sec"]
PROFILES = {"windows", "windows-asan", "linux", "linux-sanitizers", "prepare-linux",
            "prepare-ui-windows", "prepare-ui-linux", "windows-ui", "linux-ui"}


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def file_sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def source_manifest(root):
    root = Path(root)
    if not root.is_dir() or root.is_symlink():
        raise ValueError("registered Sonance source directory is unavailable")
    result, size = [], 0
    for path in sorted(root.rglob("*")):
        if "__pycache__" in path.parts:
            continue
        info = path.lstat()
        if stat.S_ISLNK(info.st_mode) or getattr(info, "st_file_attributes", 0) & 0x400:
            raise ValueError("Sonance source links/reparse points are prohibited")
        if stat.S_ISDIR(info.st_mode):
            continue
        if not stat.S_ISREG(info.st_mode):
            raise ValueError("Sonance source must contain regular files")
        size += info.st_size
        if info.st_size > 16 * 1024 * 1024 or size > 64 * 1024 * 1024 or len(result) >= 256:
            raise ValueError("Sonance source exceeds its file/byte bounds")
        result.append([path.relative_to(root).as_posix(), info.st_size, file_sha(path)])
    if not result:
        raise ValueError("Sonance source manifest is empty")
    return sorted(result, key=lambda item: item[0])


def projects():
    from shared.receipt import control_home
    path = Path(os.environ.get("ORION_SONANCE_PROJECTS_FILE") or control_home() / "sonance-projects.json")
    return json.loads(path.read_text(encoding="utf-8-sig"))["projects"] if path.is_file() else {}


def validate(params, input_root):
    if not isinstance(params, dict) or set(params) - set(PARAMETERS):
        raise ValueError("unsupported Sonance build parameters")
    identity = params.get("project_id")
    if not isinstance(identity, str) or not re.fullmatch(r"sonance-core-[0-9a-f]{12}", identity):
        raise ValueError("a registered Sonance project ID is required")
    project = projects().get(identity)
    if not project:
        raise ValueError("unregistered Sonance build project")
    profile = params.get("profile")
    if not isinstance(profile, str) or profile not in PROFILES or profile not in project["profiles"]:
        raise ValueError("unregistered Sonance build profile")
    expected = params.get("expected_source_sha256")
    observed = digest(source_manifest(project["root"]))
    if expected != project["source_sha256"] or expected != observed:
        raise ValueError("Sonance source snapshot hash mismatch")
    if file_sha(project["python_exe"]) != project["python_exe_sha256"]:
        raise ValueError("registered Windows Python changed")
    timeout = params.get("timeout_sec", 600)
    if type(timeout) is not int or not 60 <= timeout <= 900:
        raise ValueError("Sonance timeout must be 60 to 900 seconds")
    selected = project["profiles"][profile]
    if selected["kind"] == "windows":
        for name, entry in selected["tools"].items():
            if file_sha(entry["path"]) != entry["sha256"]:
                raise ValueError("registered Windows tool changed: " + name)
        for entry in selected.get("ui_runtime", {}).get("pins", {}).values():
            if file_sha(entry["path"]) != entry["sha256"]:
                raise ValueError("registered desktop UI runtime changed")
    return {"project_id": identity, "profile": profile, "expected_source_sha256": expected,
            "timeout_sec": timeout, "runtime_sha256": digest(selected)}, "cpu-heavy", 0


def command(job, job_dir, input_root, environment):
    params = job["params"]
    normalized, _, _ = validate({key: params[key] for key in PARAMETERS}, input_root)
    if normalized != params:
        raise RuntimeError("Sonance project/profile changed after admission")
    project = projects()[params["project_id"]]
    source = job_dir / "work/source"
    shutil.copytree(project["root"], source, ignore=shutil.ignore_patterns("__pycache__"))
    if digest(source_manifest(source)) != params["expected_source_sha256"]:
        raise RuntimeError("isolated Sonance source copy differs from the registered snapshot")
    request = job_dir / "sonance-request.json"
    request.write_text(json.dumps({"job_id": job["job_id"], "source": str(source),
        "output": str(job_dir / "out"), "source_sha256": params["expected_source_sha256"],
        "profile_name": params["profile"], "profile": project["profiles"][params["profile"]]}, indent=2))
    environment = {**environment, "ORION_SONANCE_TYPED_WORKER": "1", "PYTHONDONTWRITEBYTECODE": "1",
                   "PYTHONUTF8": "1", "PYTHONIOENCODING": "utf-8", "OMP_NUM_THREADS": "1"}
    job["runtime"] = {"project_id": params["project_id"], "profile": params["profile"],
                      "source_sha256": params["expected_source_sha256"], "runtime_sha256": params["runtime_sha256"]}
    return [project["python_exe"], str(source / "portable/orion/run.py"), "--request", str(request)], source, environment
