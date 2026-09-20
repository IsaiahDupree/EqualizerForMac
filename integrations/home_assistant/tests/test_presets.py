"""DSP contract tests for Sonance's Music Assistant presets."""

# ruff: noqa: E402

from __future__ import annotations

import sys
from pathlib import Path

COMPONENTS = Path(__file__).parents[1] / "custom_components"
sys.path.insert(0, str(COMPONENTS))

from sonance_eq.presets import (
    ISO_CENTERS,
    PRESET_NAMES,
    SONANCE_PRESETS,
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
