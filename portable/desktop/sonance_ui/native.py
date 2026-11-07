from __future__ import annotations

import ctypes
import math
import os
from pathlib import Path
import platform
import sys

import presets


class NativeBand(ctypes.Structure):
    _fields_ = [("type", ctypes.c_int32), ("frequency", ctypes.c_double),
                ("gain", ctypes.c_double), ("q", ctypes.c_double),
                ("enabled", ctypes.c_int32), ("slope", ctypes.c_double)]


def resource_root() -> Path:
    return Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parents[3]))


def database_path() -> Path:
    override = os.environ.get("SONANCE_EQ_DATABASE")
    if override:
        return Path(override)
    if getattr(sys, "frozen", False):
        return resource_root() / "sonance/data/autoeq.sqlite"
    return resource_root() / "Sources/SonanceEQ/Resources/autoeq.sqlite"


class NativeCore:
    def __init__(self, path: Path | None = None):
        system = platform.system()
        if system not in {"Windows", "Linux"}:
            raise RuntimeError("This desktop preview requires Windows or Linux.")
        name = "sonance_eq_bridge.dll" if system == "Windows" else "libsonance_eq_bridge.so"
        selected = path or os.environ.get("SONANCE_EQ_CORE_LIBRARY")
        if selected is None:
            selected = resource_root() / ("sonance/native/" + name) if getattr(sys, "frozen", False) else resource_root() / "build/portable" / name
        self.path = Path(selected).resolve()
        if not self.path.is_file():
            raise RuntimeError("The Sonance native core is missing. Use a complete desktop preview bundle.")
        self.library = ctypes.CDLL(str(self.path))
        self.library.sonance_abi_version.restype = ctypes.c_uint32
        self.library.sonance_band_v1_size.restype = ctypes.c_size_t
        if self.library.sonance_abi_version() != 1 or self.library.sonance_band_v1_size() != ctypes.sizeof(NativeBand):
            raise RuntimeError("The Sonance native core version does not match this editor.")
        self.calculate = self.library.sonance_response_v1
        self.calculate.argtypes = [ctypes.POINTER(NativeBand), ctypes.c_size_t, ctypes.c_double,
                                   ctypes.c_double, ctypes.c_int32, ctypes.POINTER(ctypes.c_double),
                                   ctypes.POINTER(ctypes.c_double), ctypes.c_size_t,
                                   ctypes.POINTER(ctypes.c_char), ctypes.c_size_t]
        self.calculate.restype = ctypes.c_int32

    def response(self, preset: dict, rate: int = 48000, bypass: bool = False, frequencies=None):
        value = presets.validate(preset)
        if frequencies is None:
            upper = min(20000, rate * 0.49)
            frequencies = [20 * (upper / 20) ** (index / 511) for index in range(512)]
        frequencies = list(frequencies)
        if not 1 <= len(frequencies) <= 4096:
            raise ValueError("Expected 1 to 4096 response points")
        bands = (NativeBand * len(value["bands"]))(*[
            NativeBand(presets.FILTERS.index(band["type"]), band["frequency"], band["gain"], band["q"],
                       int(band["enabled"]), band["slopeDbPerOct"]) for band in value["bands"]])
        inputs = (ctypes.c_double * len(frequencies))(*frequencies)
        output = (ctypes.c_double * len(frequencies))()
        error = ctypes.create_string_buffer(512)
        status = self.calculate(bands, len(bands), rate, value["preampDb"], int(bypass),
                                inputs, output, len(frequencies), error, len(error))
        if status:
            raise ValueError(error.value.decode("utf-8", errors="replace") or "Native response failed")
        if not all(math.isfinite(number) for number in output):
            raise ValueError("Native core returned an invalid response")
        return frequencies, list(output)
