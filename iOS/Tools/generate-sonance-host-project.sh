#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
ios_root="$(cd "$script_dir/.." && pwd)"
vendor="$ios_root/Vendor/EffectDeck"

git -C "$vendor" submodule update --init --recursive
export PATH="/opt/homebrew/bin:$PATH"
bash "$vendor/Scripts/setup.sh"
python3 "$ios_root/HostConfig/apply-upstream-adaptation.py"
cd "$vendor"
xcodegen -s "$ios_root/sonance-host.project.yml" -p "$vendor" -r "$vendor"

printf 'Generated %s/SonanceEQHost.xcodeproj\n' "$vendor"
