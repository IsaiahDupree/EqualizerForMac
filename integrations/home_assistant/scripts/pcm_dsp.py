"""Reference PCM implementation of the Sonance ten-band preset curves.

This module is intentionally kept with the hardware acceptance tools. Music
Assistant remains the production stream-DSP backend; the implementation here
lets a physical Sendspin check prove that non-flat, headroom-safe PCM entered
the transport without requiring a Music Assistant installation.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path
from typing import Any

import numpy as np

COMPONENTS = Path(__file__).parents[1] / "custom_components"
sys.path.insert(0, str(COMPONENTS))

from sonance_eq.presets import GRAPHIC_Q, ISO_CENTERS, preset_gains  # noqa: E402

DEFAULT_SAMPLE_RATE = 48_000
DEFAULT_CHANNELS = 2
LIMITER_CEILING_DBFS = -2.0
CALIBRATION_FREQUENCIES = (125.0, 1_000.0, 8_000.0)


def _peaking_coefficients(
    frequency: float,
    q: float,
    gain_db: float,
    sample_rate: int,
) -> tuple[float, float, float, float, float]:
    """Return normalized RBJ peaking-EQ coefficients."""
    if sample_rate <= 0:
        raise ValueError("Sample rate must be positive")
    if not 0 < frequency < sample_rate / 2:
        raise ValueError("Filter frequency must be below Nyquist")
    if q <= 0:
        raise ValueError("Filter Q must be positive")

    amplitude = 10 ** (gain_db / 40)
    omega = 2 * math.pi * frequency / sample_rate
    alpha = math.sin(omega) / (2 * q)
    cosine = math.cos(omega)
    a0 = 1 + alpha / amplitude
    return (
        (1 + alpha * amplitude) / a0,
        (-2 * cosine) / a0,
        (1 - alpha * amplitude) / a0,
        (-2 * cosine) / a0,
        (1 - alpha / amplitude) / a0,
    )


def _filter_channel(
    samples: np.ndarray,
    coefficients: tuple[float, float, float, float, float],
) -> np.ndarray:
    """Apply one biquad using transposed direct form II."""
    b0, b1, b2, a1, a2 = coefficients
    output = np.empty_like(samples, dtype=np.float64)
    state1 = 0.0
    state2 = 0.0
    for index, sample in enumerate(samples):
        value = b0 * float(sample) + state1
        state1 = b1 * float(sample) - a1 * value + state2
        state2 = b2 * float(sample) - a2 * value
        output[index] = value
    return output


def apply_preset(
    samples: np.ndarray,
    preset: str,
    *,
    sample_rate: int = DEFAULT_SAMPLE_RATE,
) -> np.ndarray:
    """Apply a Sonance curve, compensating preamp, and -2 dBFS ceiling."""
    source = np.asarray(samples, dtype=np.float64)
    if source.ndim not in (1, 2) or source.size == 0:
        raise ValueError("PCM samples must be a non-empty mono or channel matrix")
    if not np.all(np.isfinite(source)):
        raise ValueError("PCM samples must contain only finite values")

    gains = preset_gains(preset)
    if not any(gains):
        return np.clip(source.copy(), -1.0, 1.0)

    processed = source.copy()
    if processed.ndim == 1:
        processed = processed[:, np.newaxis]

    preamp_db = -max(0.0, max(gains))
    processed *= 10 ** (preamp_db / 20)
    for frequency, gain_db in zip(ISO_CENTERS, gains, strict=True):
        if gain_db == 0:
            continue
        coefficients = _peaking_coefficients(
            frequency,
            GRAPHIC_Q,
            gain_db,
            sample_rate,
        )
        for channel in range(processed.shape[1]):
            processed[:, channel] = _filter_channel(processed[:, channel], coefficients)

    ceiling = 10 ** (LIMITER_CEILING_DBFS / 20)
    processed = np.clip(processed, -ceiling, ceiling)
    return processed[:, 0] if source.ndim == 1 else processed


def calibration_signal(
    duration_seconds: float = 1.0,
    *,
    sample_rate: int = DEFAULT_SAMPLE_RATE,
    channels: int = DEFAULT_CHANNELS,
) -> np.ndarray:
    """Generate a quiet deterministic multitone with short click-free fades."""
    if not 0.1 <= duration_seconds <= 5.0:
        raise ValueError("Calibration duration must be between 0.1 and 5 seconds")
    if channels not in (1, 2):
        raise ValueError("Calibration signal supports mono or stereo")

    frame_count = round(sample_rate * duration_seconds)
    times = np.arange(frame_count, dtype=np.float64) / sample_rate
    amplitude = 10 ** (-24.0 / 20)
    mono = sum(
        np.sin(2 * math.pi * frequency * times) for frequency in CALIBRATION_FREQUENCIES
    )
    mono *= amplitude / len(CALIBRATION_FREQUENCIES)

    fade_frames = min(round(sample_rate * 0.02), frame_count // 2)
    fade = np.linspace(0.0, 1.0, fade_frames, endpoint=True)
    mono[:fade_frames] *= fade
    mono[-fade_frames:] *= fade[::-1]
    return mono if channels == 1 else np.repeat(mono[:, np.newaxis], channels, axis=1)


def pcm16_bytes(samples: np.ndarray) -> bytes:
    """Quantize normalized floating-point PCM as little-endian signed 16-bit."""
    clipped = np.clip(np.asarray(samples, dtype=np.float64), -1.0, 1.0)
    return np.rint(clipped * 32_767).astype("<i2").tobytes()


def signal_stats(samples: np.ndarray) -> dict[str, float]:
    """Return deterministic level metrics for an acceptance report."""
    values = np.asarray(samples, dtype=np.float64)
    peak = float(np.max(np.abs(values)))
    rms = float(np.sqrt(np.mean(np.square(values))))
    floor = np.finfo(np.float64).tiny
    return {
        "peak_dbfs": round(20 * math.log10(max(peak, floor)), 3),
        "rms_dbfs": round(20 * math.log10(max(rms, floor)), 3),
    }


def frequency_response(preset: str) -> list[dict[str, Any]]:
    """Calculate the linear biquad-chain response at every Sonance band center."""
    gains = preset_gains(preset)
    if not any(gains):
        return [
            {"frequency_hz": frequency, "gain_db": 0.0} for frequency in ISO_CENTERS
        ]

    preamp_db = -max(0.0, max(gains))
    response: list[dict[str, Any]] = []
    for measured_frequency in ISO_CENTERS:
        omega = 2 * math.pi * measured_frequency / DEFAULT_SAMPLE_RATE
        z1 = complex(math.cos(-omega), math.sin(-omega))
        z2 = z1 * z1
        transfer = complex(10 ** (preamp_db / 20), 0)
        for filter_frequency, gain_db in zip(ISO_CENTERS, gains, strict=True):
            if gain_db == 0:
                continue
            b0, b1, b2, a1, a2 = _peaking_coefficients(
                filter_frequency,
                GRAPHIC_Q,
                gain_db,
                DEFAULT_SAMPLE_RATE,
            )
            transfer *= (b0 + b1 * z1 + b2 * z2) / (1 + a1 * z1 + a2 * z2)
        response.append(
            {
                "frequency_hz": measured_frequency,
                "gain_db": round(20 * math.log10(abs(transfer)), 3),
            }
        )
    return response
