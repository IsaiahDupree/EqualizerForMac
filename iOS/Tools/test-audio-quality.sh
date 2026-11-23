#!/usr/bin/env bash
# Runs the installed AUv3 quality suite. This is not a Bluetooth certification.
set -euo pipefail

SONANCE_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SONANCE_REPO_DIR="$(cd -- "${SONANCE_SCRIPT_DIR}/../.." && pwd)"
cd "${SONANCE_REPO_DIR}"

if [[ "$(uname -s)" != Darwin ]]; then
  echo "This suite needs macOS, Xcode 26 or later, XcodeGen, and an available iOS Simulator." >&2
  echo "A Linux check cannot validate the installed Apple Audio Unit or Bluetooth playback." >&2
  exit 2
fi
for SONANCE_TOOL in xcodebuild xcrun xcodegen python3; do
  if ! command -v "${SONANCE_TOOL}" >/dev/null 2>&1; then
    echo "Missing required tool: ${SONANCE_TOOL}" >&2
    exit 2
  fi
done

SONANCE_RESULTS_DIR="${SONANCE_AUDIO_RESULTS_DIR:-${SONANCE_REPO_DIR}/build/audio-quality/$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "${SONANCE_RESULTS_DIR}"
SONANCE_RESULTS_DIR="$(cd -- "${SONANCE_RESULTS_DIR}" && pwd)"
SONANCE_RESULT_BUNDLE="${SONANCE_RESULTS_DIR}/AudioQuality.xcresult"
if [[ -e "${SONANCE_RESULT_BUNDLE}" ]]; then
  echo "Result bundle already exists; choose a new SONANCE_AUDIO_RESULTS_DIR." >&2
  exit 2
fi

SONANCE_DESTINATION="${SONANCE_AUDIO_DESTINATION:-}"
if [[ -z "${SONANCE_DESTINATION}" ]]; then
  xcrun simctl list devices available --json > "${SONANCE_RESULTS_DIR}/available-simulators.json"
  SONANCE_SIMULATOR_ID="$(python3 - "${SONANCE_RESULTS_DIR}/available-simulators.json" <<'PY'
import json
import re
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
candidates = []
for runtime, devices in data.get("devices", {}).items():
    if ".iOS-" not in runtime:
        continue
    version = tuple(map(int, re.findall(r"\d+", runtime.split(".iOS-", 1)[1])))
    for device in devices:
        if device.get("isAvailable", False) and device.get("name", "").startswith("iPhone"):
            candidates.append((version, device.get("state") == "Booted", device["name"], device["udid"]))
if not candidates:
    sys.exit("No available iPhone simulator. Install an iOS runtime in Xcode or set SONANCE_AUDIO_DESTINATION.")
print(max(candidates)[3])
PY
  )"
  SONANCE_DESTINATION="platform=iOS Simulator,id=${SONANCE_SIMULATOR_ID}"
fi

xcodebuild -version > "${SONANCE_RESULTS_DIR}/xcode-version.txt"
git rev-parse HEAD > "${SONANCE_RESULTS_DIR}/commit.txt"
git status --short > "${SONANCE_RESULTS_DIR}/working-tree.txt"
python3 - "${SONANCE_RESULTS_DIR}" "${SONANCE_DESTINATION}" <<'PY'
import datetime
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
manifest = {
    "suite": "Sonance installed AUv3 audio quality and continuity",
    "started_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "commit": (root / "commit.txt").read_text().strip(),
    "working_tree": (root / "working-tree.txt").read_text(),
    "xcode": (root / "xcode-version.txt").read_text().strip(),
    "destination": sys.argv[2],
    "digital_suite_status": "running",
    "physical_bluetooth_status": "not_run",
    "scope": "Installed AUv3 offline rendering. No real-time deadline or Bluetooth claim.",
}
(root / "run-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
PY

finish_manifest() {
  SONANCE_EXIT_CODE=$?
  trap - EXIT
  python3 - "${SONANCE_RESULTS_DIR}/run-manifest.json" "${SONANCE_EXIT_CODE}" <<'PY'
import datetime
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text())
data["finished_at_utc"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
data["exit_code"] = int(sys.argv[2])
data["digital_suite_status"] = "passed" if data["exit_code"] == 0 else "failed"
path.write_text(json.dumps(data, indent=2) + "\n")
PY
  exit "${SONANCE_EXIT_CODE}"
}
trap finish_manifest EXIT

xcodegen generate --spec iOS/project.yml --project iOS
xcodebuild test \
  -project iOS/SonanceEQ.xcodeproj \
  -scheme SonanceEQiOS \
  -destination "${SONANCE_DESTINATION}" \
  -destination-timeout 120 \
  -jobs 1 -parallel-testing-enabled NO \
  -only-testing:SonanceEQiOSTests/AudioContinuityTests \
  -resultBundlePath "${SONANCE_RESULT_BUNDLE}" \
  "$@" 2>&1 | tee "${SONANCE_RESULTS_DIR}/xcodebuild.log"

# A successful command with an empty/renamed selector is not a test pass.
xcrun xcresulttool get test-results summary --path "${SONANCE_RESULT_BUNDLE}" \
  > "${SONANCE_RESULTS_DIR}/test-summary.json"
xcrun xcresulttool get test-results tests --path "${SONANCE_RESULT_BUNDLE}" \
  > "${SONANCE_RESULTS_DIR}/test-tree.json"
python3 iOS/Tools/verify_audio_test_results.py \
  "${SONANCE_RESULTS_DIR}/test-summary.json" \
  "${SONANCE_RESULTS_DIR}/test-tree.json" \
  iOS/Tests/AudioContinuityTests.swift

echo "Digital results: ${SONANCE_RESULTS_DIR}"
echo "Physical Bluetooth acceptance remains not_run; see iOS/AudioValidation/README.md."
