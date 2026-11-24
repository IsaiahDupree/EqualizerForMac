#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
ios_root="$(cd "$script_dir/.." && pwd)"
vendor="$ios_root/Vendor/EffectDeck"
repo_root="$(cd "$ios_root/.." && pwd)"

# Initialize the host submodule first so its own pinned DSP/runtime modules exist.
git -C "$repo_root" submodule update --init iOS/Vendor/EffectDeck
# The iOS host uses the pinned DSP and JSFX runtime sources directly. Their
# nested development-only submodules (CLAP extensions and dr_libs) are not part
# of this target; recursively cloning them wastes internal disk space and can
# fail on clean machines without adding anything to the iOS build.
git -C "$vendor" submodule update --init Vendor/effetune Vendor/ysfx
# macOS ships Python 3.9 as /usr/bin/python3; the catalog generator needs the
# newer pathlib.write_text(newline:) API. Homebrew keeps versioned binaries, so
# expose the newest supported one under the generic name expected upstream.
python_bin=""
for candidate in /opt/homebrew/bin/python3.14 /opt/homebrew/bin/python3.13 /opt/homebrew/bin/python3.12 /opt/homebrew/bin/python3.11; do
  if [[ -x "$candidate" ]]; then
    python_bin="$candidate"
    break
  fi
done
if [[ -z "$python_bin" ]]; then
  printf "Python 3.11 or newer is required to generate the EffectDeck catalog.\n" >&2
  exit 1
fi
python_shim="${TMPDIR:-/tmp}/sonance-eq-python-bin"
mkdir -p "$python_shim"
ln -sf "$python_bin" "$python_shim/python3"
export PATH="$python_shim:/opt/homebrew/bin:$PATH"
bash "$vendor/Scripts/setup.sh"
python3 "$ios_root/HostConfig/apply-upstream-adaptation.py"
cd "$vendor"
xcodegen -s "$ios_root/sonance-host.project.yml" -p "$vendor" -r "$vendor"

printf 'Generated %s/SonanceEQHost.xcodeproj\n' "$vendor"
