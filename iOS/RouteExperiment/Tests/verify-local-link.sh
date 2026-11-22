#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
output="$(mktemp -d "${TMPDIR:-/tmp}/sonance-route-link.XXXXXX")"
trap 'rm -rf "$output"' EXIT
if lsof -nP -iTCP:47129 -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Route-lab port is already in use; refusing to affect another listener" >&2
  exit 1
fi
flags=(-O0)
if [[ "${ROUTE_UBSAN:-0}" == "1" ]]; then flags=(-fsanitize=undefined -fno-sanitize-recover=all -g -O1); fi
xcrun clang -fobjc-arc -fblocks "${flags[@]}" -framework Foundation -I "$root/Sources/Shared" \
  "$root/Sources/Shared/LocalLink.m" "$root/Sources/Shared/MDPAudioRing.c" \
  "$root/Tests/VerifyLocalLink.m" -o "$output/verify"
"$output/verify"
