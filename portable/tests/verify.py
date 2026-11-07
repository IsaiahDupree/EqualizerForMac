#!/usr/bin/env python3
"""Bounded, single-process C++ DSP tests and optional parity with shipping Swift.

No downloads, network calls, renderer, local model or cloud runner. This small
unit-test compile may run on the Mac; full native release builds belong on Orion.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
PORTABLE = ROOT / "portable"
SWIFT = ROOT / "Sources/SonanceEQ"


def run(command: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(command, check=True, text=True, timeout=60, **kwargs)


def fixtures() -> str:
    rows = []
    for rate in (8000, 44100, 48000, 96000, 192000, 384000):
        for kind in ("peaking", "lowShelf", "highShelf", "lowPass", "highPass", "notch", "bandPass", "allPass"):
            for frequency in (20, 1000, rate * 0.49, rate):
                for gain, q in ((-12, 0.3), (0, 0.7071067811865476), (6, 4)):
                    slopes = (6, 12, 18, 24, 36, 48, 72, 96) if kind in ("lowPass", "highPass") else (12,)
                    for slope in slopes:
                        rows.append(f"{kind} {rate} {frequency} {gain} {q} {slope}")
    return "\n".join(rows) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--swift-parity", action="store_true")
    parser.add_argument("--sanitize", action="store_true", help="enable address and undefined behavior sanitizers")
    parser.add_argument("--receipt", type=Path)
    args = parser.parse_args()
    compiler = shutil.which(os.environ.get("CXX", "c++"))
    if compiler is None:
        raise SystemExit("A C++17 compiler is required; no download was attempted.")
    receipt = {"core_assertions": None, "swift_parity_cases": None,
               "swift_preset_roundtrip_cases": None, "sanitizers": args.sanitize}
    with tempfile.TemporaryDirectory(prefix="sonance-eq-core-") as directory:
        work = Path(directory)
        flags = ["-std=c++17", "-Wall", "-Wextra", "-Werror", "-pedantic", "-O1", "-I", str(PORTABLE / "include")]
        if args.sanitize:
            flags += ["-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
        binary = work / "core-tests"
        run([compiler, *flags, str(PORTABLE / "tests/core_tests.cpp"), "-o", str(binary)])
        output = run([str(binary)], capture_output=True).stdout.strip()
        print(output, flush=True)
        receipt["core_assertions"] = int(output.split()[1])
        if args.swift_parity:
            swift = shutil.which("swiftc")
            if swift is None:
                raise SystemExit("Swift compiler missing; shipping-source parity was not run.")
            coefficients = work / "cpp-coefficients"
            run([compiler, *flags, str(PORTABLE / "tests/coefficients.cpp"), "-o", str(coefficients)])
            swift_main = work / "main.swift"
            swift_main.write_text((PORTABLE / "tests/swift_coefficients.swift").read_text())
            shipping = [SWIFT / "DSP/Biquad.swift", SWIFT / "Models/EQBand.swift", SWIFT / "DSP/FilterDesigner.swift"]
            swift_binary = work / "swift-coefficients"
            run([swift, *map(str, shipping), str(swift_main), "-o", str(swift_binary)])
            requests = fixtures()
            cpp_rows = run([str(coefficients)], input=requests, capture_output=True).stdout.splitlines()
            swift_rows = run([str(swift_binary)], input=requests, capture_output=True).stdout.splitlines()
            if len(cpp_rows) != len(swift_rows) or len(cpp_rows) != len(requests.splitlines()):
                raise RuntimeError("Coefficient parity response count mismatch")
            max_error = 0.
            for request, cpp, original in zip(requests.splitlines(), cpp_rows, swift_rows):
                actual, expected = json.loads(cpp), json.loads(original)
                if len(actual) != len(expected):
                    raise RuntimeError(f"Section mismatch: {request}")
                for a, e in zip(actual, expected):
                    if len(a) != 5 or len(e) != 5 or not all(math.isfinite(v) for v in a + e):
                        raise RuntimeError(f"Invalid coefficient response: {request}")
                    for value, reference in zip(a, e):
                        error = abs(value - reference)
                        max_error = max(max_error, error)
                        if error > 2e-6 * max(1., abs(reference)):
                            raise RuntimeError(f"Coefficient mismatch: {request}: {value} != {reference}")
            receipt["swift_parity_cases"] = len(cpp_rows)
            receipt["max_absolute_coefficient_error"] = max_error
            print(f"PASS: {len(cpp_rows)} coefficient cases against shipping Swift; max absolute error {max_error:.3g}", flush=True)

            # Decode actual shipping exports and have the shipping decoder read an
            # exported row from the real headphone database. No replacement models.
            spec = importlib.util.spec_from_file_location("sonance_presets", PORTABLE / "presets.py")
            presets = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(presets)
            shipping += [SWIFT / "Models/PresetFile.swift", SWIFT / "Models/Presets.swift"]
            swift_main.write_text((PORTABLE / "tests/swift_presets.swift").read_text())
            swift_presets = work / "swift-presets"
            run([swift, *map(str, shipping), str(swift_main), "-o", str(swift_presets)])
            exports = json.loads(run([str(swift_presets)], capture_output=True).stdout)
            first = presets.search(presets.DATABASE, "", 1)[0]
            exports.append(presets.export_headphone(presets.DATABASE, first["id"]))
            for preset in exports:
                canonical = presets.validate(preset)
                result = run([str(swift_presets), "--round-trip"], input=json.dumps(canonical), capture_output=True)
                if presets.validate(json.loads(result.stdout)) != canonical:
                    raise RuntimeError(f"Shipping preset round-trip mismatch: {canonical['name']}")
            receipt["swift_preset_roundtrip_cases"] = len(exports)
            receipt["shipping_source_sha256"] = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in shipping}
            print(f"PASS: {len(exports)} preset round trips through shipping Swift, including the real headphone database", flush=True)
        receipt["portable_source_sha256"] = {
            str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(PORTABLE.rglob("*")) if p.is_file() and "__pycache__" not in p.parts
        }
        receipt["native_windows_build_verified"] = False
        receipt["native_linux_build_verified"] = False
        receipt["hardware_audio_verified"] = False
        if args.receipt:
            args.receipt.parent.mkdir(parents=True, exist_ok=True)
            args.receipt.write_text(json.dumps(receipt, indent=2) + "\n")


if __name__ == "__main__":
    main()
