"""Tests for the real PCM path used by Sendspin hardware acceptance."""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np

SCRIPTS = Path(__file__).parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))

from pcm_dsp import (  # noqa: E402
    LIMITER_CEILING_DBFS,
    apply_preset,
    calibration_signal,
    frequency_response,
    pcm16_bytes,
    signal_stats,
)


def test_flat_is_bit_stable_for_in_range_calibration_signal() -> None:
    source = calibration_signal()
    processed = apply_preset(source, "Flat")
    assert np.array_equal(source, processed)
    assert pcm16_bytes(source) == pcm16_bytes(processed)


def test_vocal_curve_changes_real_pcm_and_preserves_shape() -> None:
    source = calibration_signal()
    processed = apply_preset(source, "Vocal")
    assert processed.shape == source.shape
    assert np.all(np.isfinite(processed))
    assert pcm16_bytes(source) != pcm16_bytes(processed)
    assert any(pcm16_bytes(processed))


def test_every_preset_respects_the_safety_ceiling() -> None:
    source = np.full((2_048, 2), 1.0)
    ceiling = 10 ** (LIMITER_CEILING_DBFS / 20)
    for preset in (
        "Bass Boost",
        "Treble",
        "Vocal",
        "Loudness",
        "Warm Room",
        "Night",
        "Small Speaker",
        "Cinema",
    ):
        processed = apply_preset(source, preset)
        assert float(np.max(np.abs(processed))) <= ceiling


def test_frequency_response_exposes_the_intended_tonal_shape() -> None:
    flat = frequency_response("Flat")
    vocal = frequency_response("Vocal")
    assert all(point["gain_db"] == 0 for point in flat)
    vocal_by_frequency = {point["frequency_hz"]: point["gain_db"] for point in vocal}
    assert vocal_by_frequency[1_000.0] > vocal_by_frequency[31.25]
    assert vocal_by_frequency[2_000.0] > vocal_by_frequency[16_000.0]


def test_calibration_signal_is_quiet_non_silent_pcm() -> None:
    source = calibration_signal()
    stats = signal_stats(source)
    assert source.shape == (48_000, 2)
    assert -40 < stats["rms_dbfs"] < -20
    assert -30 < stats["peak_dbfs"] < -15
    assert any(pcm16_bytes(source))
