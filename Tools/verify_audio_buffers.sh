#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
proof_dir=$(mktemp -d "${TMPDIR:-/tmp}/sonance-render-proof.XXXXXX")
trap 'rm -rf "$proof_dir"' EXIT
sanitizer_args=(-sanitize=address)
case "${1:-}" in
  "") ;;
  --no-sanitizer) sanitizer_args=(); print 'Address Sanitizer disabled explicitly; buffer guards remain enabled' ;;
  *) print -u2 'Usage: verify_audio_buffers.sh [--no-sanitizer]'; exit 2 ;;
esac
# A bounded single-process native test of shipping code; no Core Audio device/session is opened.
xcrun swiftc -g "${sanitizer_args[@]}" -D SONANCE_STANDALONE_RENDER_PROOF \
  -target "$(uname -m)-apple-macosx14.4" \
  Tests/AudioBufferRouterTests.swift \
  Sources/SonanceEQ/AudioEngine/{AudioBufferRouter,AudioRouteWatchdog,AudioRouteOperation,SystemAudioTap,CoreAudioProperties,AudioProcesses}.swift \
  Sources/SonanceEQ/App/EQText.swift \
  Sources/SonanceEQ/DSP/{EQEngine,FIRProcessor,FIRDesigner,FilterDesigner,FrequencyResponse,Biquad}.swift \
  Sources/SonanceEQ/Models/EQBand.swift -o "$proof_dir/verify-audio-buffers"
python3 - "$proof_dir/verify-audio-buffers" <<'PY'
import subprocess
import sys
try:
    result = subprocess.run([sys.argv[1]], timeout=45)
except subprocess.TimeoutExpired:
    print('FAIL: native render proof exceeded its 45-second runtime limit', flush=True)
    sys.exit(124)
sys.exit(result.returncode)
PY
