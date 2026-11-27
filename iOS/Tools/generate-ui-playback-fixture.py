#!/usr/bin/env python3
"""Generate an audible local-playback fixture for Debug UI tests only."""
import math
import pathlib
import struct
import sys
import wave

RATE = 48_000
DURATION_SECONDS = 60
AMPLITUDE = 0.22


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: generate-ui-playback-fixture.py OUTPUT.wav")
    destination = pathlib.Path(sys.argv[1])
    destination.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(destination), "wb") as audio:
        audio.setnchannels(1)
        audio.setsampwidth(2)
        audio.setframerate(RATE)
        frames = bytearray()
        for index in range(RATE * DURATION_SECONDS):
            time = index / RATE
            sample = AMPLITUDE * (math.sin(2 * math.pi * 440 * time) +
                                  0.25 * math.sin(2 * math.pi * 997 * time))
            frames.extend(struct.pack("<h", round(max(-1.0, min(1.0, sample)) * 32767)))
        audio.writeframes(frames)
    print(f"Generated {destination} ({DURATION_SECONDS}s, mono PCM16, {RATE} Hz)")


if __name__ == "__main__":
    main()
