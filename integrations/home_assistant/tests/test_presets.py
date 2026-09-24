"""DSP contract tests for Sonance's Music Assistant presets."""

from __future__ import annotations

import sys
from pathlib import Path

COMPONENTS = Path(__file__).parents[1] / "custom_components"
sys.path.insert(0, str(COMPONENTS))

from sonance_eq.presets import (
    ISO_CENTERS,
    PRESET_NAMES,
    SONANCE_PRESETS,
    powerzone_bands,
    preset_payload,
)


def test_all_non_flat_presets_are_safe_parametric_chains() -> None:
    assert len(PRESET_NAMES) == len(set(PRESET_NAMES)) == 9
    for preset in SONANCE_PRESETS:
        config = preset["config"]
        assert preset["name"].startswith("Sonance · ")
        assert -60 <= config["input_gain"] <= 60
        assert -60 <= config["output_gain"] <= 60
        if not config["enabled"]:
            assert preset["name"] == "Sonance · Flat"
            assert config["filters"] == []
            continue
        parametric, limiter = config["filters"]
        assert parametric["type"] == "parametric_eq"
        assert len(parametric["bands"]) == len(ISO_CENTERS)
        assert parametric["preamp"] <= 0
        assert [band["frequency"] for band in parametric["bands"]] == list(ISO_CENTERS)
        assert all(0.01 <= band["q"] <= 100 for band in parametric["bands"])
        assert limiter == {"type": "safety_limiter", "enabled": True, "ceiling": -2.0}


def test_preset_payload_is_isolated_and_accepts_full_name() -> None:
    first = preset_payload("Vocal")
    second = preset_payload("Sonance · Vocal")
    first["config"]["enabled"] = False
    assert second["config"]["enabled"] is True


def test_powerzone_adaptation_is_headroom_safe_and_respects_band_count() -> None:
    assert powerzone_bands("Flat", 4) == []
    four_band = powerzone_bands("Bass Boost", 4)
    assert len(four_band) == 4
    assert [band["frequency"] for band in four_band] == [31.25, 250.0, 2000.0, 16000.0]
    assert max(float(band["gain"]) for band in four_band) == 0
    assert all(0.4 <= float(band["q"]) <= 30 for band in four_band)

    ten_band = powerzone_bands("Vocal", 20)
    assert len(ten_band) == len(ISO_CENTERS)
    assert [band["frequency"] for band in ten_band] == list(ISO_CENTERS)
    assert max(float(band["gain"]) for band in ten_band) == 0
