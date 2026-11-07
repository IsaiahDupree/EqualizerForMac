"""Add one Sonance job to a copied Orion runtime, preserving other extensions."""
from __future__ import annotations

import json
from pathlib import Path
import shutil


def integrate(runtime: Path, extension: Path):
    worker = runtime / "workers/orion_workers.py"
    text = worker.read_text(encoding="utf-8")
    if '"software.sonance_core"' in text:
        raise ValueError("Sonance extension is already present")
    replacements = [
        ('JOB_TYPES: dict[str, dict[str, Any]] = {',
         'from workers import sonance_core\n\nJOB_TYPES: dict[str, dict[str, Any]] = {\n    "software.sonance_core": {"runtime": "pinned-sonance-cpp", "description": "Build and test the registered Sonance portable core on Orion.", "parameters": sonance_core.PARAMETERS},'),
        ('    if job_type not in JOB_TYPES:',
         '    if job_type == "software.sonance_core":\n        return sonance_core.validate(params, input_root)\n    if job_type not in JOB_TYPES:'),
        ('        input_sha = None\n',
         '        input_sha = None\n        if job_type == "software.sonance_core":\n            input_sha = normalized["expected_source_sha256"]\n'),
        ('        if job["job_type"] == "image.super_resolution":',
         '        if job["job_type"] == "software.sonance_core":\n            return sonance_core.command(job, job_dir, self.config.input_root, environment)\n        if job["job_type"] == "image.super_resolution":'),
        ('            "runtimes": {',
         '            "runtimes": {\n                "sonance_core": {"registered_projects": sorted(sonance_core.projects())},'),
    ]
    for old, new in replacements:
        if text.count(old) != 1:
            raise ValueError("retained worker extension point changed: " + old[:80])
        text = text.replace(old, new, 1)
    compile(text, str(worker), "exec")
    worker.write_text(text, encoding="utf-8")
    shutil.copy2(extension, runtime / "workers/sonance_core.py")
    schema = runtime / "shared/orion-worker-job.schema.json"
    data = json.loads(schema.read_text())
    data["properties"]["job_type"]["enum"].append("software.sonance_core")
    schema.write_text(json.dumps(data, indent=2) + "\n")
