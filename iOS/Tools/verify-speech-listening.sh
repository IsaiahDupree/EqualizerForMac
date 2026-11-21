#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
output="$(mktemp -d "${TMPDIR:-/tmp}/sonance-speech-check.XXXXXX")"
trap 'rm -rf "$output"' EXIT
cd "$root"
xcrun swiftc -j 1 \
  Sources/SonanceEQ/Models/EQBand.swift Sources/SonanceEQ/Models/Presets.swift \
  Sources/SonanceEQ/DSP/Biquad.swift Sources/SonanceEQ/DSP/FilterDesigner.swift \
  iOS/Sources/Shared/MobileEQ.swift iOS/Sources/Shared/SpeechListening.swift \
  iOS/Tools/VerifySpeechListening.swift -o "$output/verify"
"$output/verify"
