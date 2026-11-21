#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
output="$(mktemp -d "${TMPDIR:-/tmp}/sonance-route-test.XXXXXX")"
trap 'rm -rf "$output"' EXIT
xcrun clang -std=c11 -Wall -Wextra -Werror -c "$root/Sources/App/MDPAtomicFloat.c" -o "$output/atomic.o"
xcrun swiftc -j 1 -import-objc-header "$root/Sources/App/MDPAtomicFloat.h" \
  "$root/Sources/App/LowPass.swift" "$root/Tests/VerifyLowPass.swift" "$output/atomic.o" -o "$output/verify"
"$output/verify"
