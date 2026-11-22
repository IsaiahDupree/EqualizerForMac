#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
output="$(mktemp -d "${TMPDIR:-/tmp}/sonance-route-tls.XXXXXX")"
trap 'rm -rf "$output"' EXIT
xcrun swiftc -j 1 -swift-version 5 -parse-as-library "$root/Tests/VerifyTLSPSK.swift" -o "$output/verify"
"$output/verify"
