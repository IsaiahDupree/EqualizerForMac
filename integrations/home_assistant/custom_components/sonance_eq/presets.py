"""Sonance EQ curves translated to Music Assistant's DSP schema.

The first five curves match the built-in Sonance EQ macOS presets. The room-oriented
presets extend the same ten octave-spaced bands for speaker playback.
"""

from __future__ import annotations

from copy import deepcopy
from typing import Any

ISO_CENTERS = (
    31.25,
    62.5,
    125.0,
    250.0,
    500.0,
    1000.0,
    2000.0,
    4000.0,
    8000.0,
    16000.0,
)
GRAPHIC_Q = 1.414

_CURVES: dict[str, tuple[float, ...]] = {
    "Flat": (0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    "Bass Boost": (6, 5, 4, 2, 0, 0, 0, 0, 0, 0),
    "Treble": (0, 0, 0, 0, 0, 0, 2, 4, 5, 6),
    "Vocal": (-3, -2, -1, 1, 3, 4, 3, 1, 0, -1),
    "Loudness": (6, 4, 2, 0, -1, -1, 0, 2, 4, 5),
    "Warm Room": (2, 2, 1.5, 1, 0, -0.5, -1, -1, -0.5, 0),
    "Night": (-8, -6, -3, -1, 1, 2, 2, 1, -1, -3),
    "Small Speaker": (-12, -8, -4, 0, 2, 3, 2, 1, 0, -1),
    "Cinema": (4, 3, 1, 0, -1, 1, 3, 2, 2, 1),
}

PRESET_NAMES = tuple(_CURVES)


def _config(gains: tuple[float, ...]) -> dict[str, Any]:
    """Build a validated Music Assistant-compatible DSP configuration."""
    if not any(gains):
        return {
            "enabled": False,
            "filters": [],
            "input_gain": 0.0,
            "output_gain": 0.0,
            "preset_id": None,
        }

    # Sonance's curves can boost several adjacent bands. Pull the parametric stage
    # down by the largest boost and finish with a limiter so a preset never trades
    # tonal shape for clipping on a full-scale source.
    preamp = -max(0.0, max(gains))
    bands = [
        {
            "frequency": frequency,
            "q": GRAPHIC_Q,
            "gain": gain,
            "type": "peak",
            "enabled": True,
            "channel": "ALL",
        }
        for frequency, gain in zip(ISO_CENTERS, gains, strict=True)
    ]
    return {
        "enabled": True,
        "filters": [
            {
                "type": "parametric_eq",
                "enabled": True,
                "preamp": preamp,
                "per_channel_preamp": {},
                "bands": bands,
            },
            {
                "type": "safety_limiter",
                "enabled": True,
                "ceiling": -2.0,
            },
        ],
        "input_gain": 0.0,
        "output_gain": 0.0,
        "preset_id": None,
    }


SONANCE_PRESETS: tuple[dict[str, Any], ...] = tuple(
    {"name": f"Sonance · {name}", "config": _config(gains), "preset_id": None}
    for name, gains in _CURVES.items()
)


def preset_payload(name: str) -> dict[str, Any]:
    """Return an isolated Music Assistant preset payload by short or full name."""
    normalized = name.removeprefix("Sonance · ")
    for preset in SONANCE_PRESETS:
        if preset["name"] == f"Sonance · {normalized}":
            return deepcopy(preset)
    raise KeyError(name)
