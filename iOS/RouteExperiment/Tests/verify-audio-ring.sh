#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
output="$(mktemp -d "${TMPDIR:-/tmp}/sonance-audio-ring.XXXXXX")"
trap 'rm -rf "$output"' EXIT
flags=(-O0)
if [[ "${ROUTE_TSAN:-0}" == "1" && "${ROUTE_UBSAN:-0}" == "1" ]]; then
  echo "Choose one sanitizer" >&2
  exit 1
elif [[ "${ROUTE_TSAN:-0}" == "1" ]]; then
  flags=(-fsanitize=thread -g -O1)
elif [[ "${ROUTE_UBSAN:-0}" == "1" ]]; then
  flags=(-fsanitize=undefined -fno-sanitize-recover=all -g -O1)
fi
xcrun clang -std=c11 -Wall -Wextra -Werror -pthread "${flags[@]}" \
  -I "$root/Sources/Shared" "$root/Sources/Shared/MDPAudioRing.c" \
  "$root/Tests/VerifyAudioRing.c" -o "$output/verify"
"$output/verify"
