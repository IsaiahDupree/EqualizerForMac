#!/usr/bin/env bash
set -euo pipefail

DEVICE_ID="${SONANCE_IPHONE_UDID:-00008120-000465A20C52201E}"
BUNDLE_ID="com.isaiahdupree.SonanceEQ.iOSPrototype"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DERIVED_DATA="${SONANCE_IPHONE_DERIVED_DATA:-${PROJECT_ROOT}/build/iphone15-derived}"
LOG_DIR="${SONANCE_IPHONE_LOG_DIR:-${PROJECT_ROOT}/build/iphone15-install}"
APP_PATH="${DERIVED_DATA}/Build/Products/Debug-iphoneos/SonanceEQiOS.app"
SIGNING_SETTINGS=()

if [[ -n "${SONANCE_DEVELOPMENT_TEAM:-}" ]]; then
    SIGNING_SETTINGS+=("DEVELOPMENT_TEAM=${SONANCE_DEVELOPMENT_TEAM}")
fi
if [[ -n "${SONANCE_CODE_SIGN_STYLE:-}" ]]; then
    SIGNING_SETTINGS+=("CODE_SIGN_STYLE=${SONANCE_CODE_SIGN_STYLE}")
fi
if [[ -n "${SONANCE_PROVISIONING_PROFILE_SPECIFIER:-}" ]]; then
    SIGNING_SETTINGS+=("PROVISIONING_PROFILE_SPECIFIER=${SONANCE_PROVISIONING_PROFILE_SPECIFIER}")
fi
if [[ -n "${SONANCE_CODE_SIGN_IDENTITY:-}" ]]; then
    SIGNING_SETTINGS+=("CODE_SIGN_IDENTITY=${SONANCE_CODE_SIGN_IDENTITY}")
fi

if ! xcodebuild -license check >/dev/null 2>&1; then
    cat >&2 <<'EOF'
Xcode is not ready. Open Xcode on this Mac and complete its first-use setup
before building. This script will not accept license agreements for you.
EOF
    exit 2
fi

if ! xcrun xcdevice list 2>/dev/null | /usr/bin/python3 -c '
import json
import sys

device_id = sys.argv[1]
devices = json.load(sys.stdin)
sys.exit(0 if any(
    device.get("identifier") == device_id
    and device.get("available") is True
    and device.get("simulator") is False
    for device in devices
) else 1)
' "${DEVICE_ID}"; then
    echo "Target iPhone ${DEVICE_ID} is not available to Xcode." >&2
    exit 2
fi

mkdir -p "${LOG_DIR}"
BUILD_LOG="${LOG_DIR}/xcodebuild.log"
echo "Building Sonance EQ for iPhone ${DEVICE_ID}..."
set -o pipefail
xcodebuild \
    -project "${PROJECT_ROOT}/iOS/SonanceEQ.xcodeproj" \
    -scheme SonanceEQiOS \
    -destination "platform=iOS,id=${DEVICE_ID}" \
    -derivedDataPath "${DERIVED_DATA}" \
    build "${SIGNING_SETTINGS[@]}" 2>&1 | tee "${BUILD_LOG}"

if [[ ! -d "${APP_PATH}" ]]; then
    echo "Build succeeded but app bundle was not found at ${APP_PATH}." >&2
    exit 1
fi

BUILT_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${APP_PATH}/Info.plist")"
if [[ "${BUILT_BUNDLE_ID}" != "${BUNDLE_ID}" ]]; then
    echo "Refusing install: expected ${BUNDLE_ID}, found ${BUILT_BUNDLE_ID}." >&2
    exit 1
fi

echo "Installing ${BUNDLE_ID} on ${DEVICE_ID}..."
xcrun devicectl device install app --device "${DEVICE_ID}" "${APP_PATH}"
echo "Launching ${BUNDLE_ID} on ${DEVICE_ID}..."
xcrun devicectl device process launch --device "${DEVICE_ID}" "${BUNDLE_ID}"
echo "Installed and launched ${BUNDLE_ID} on ${DEVICE_ID}. Build log: ${BUILD_LOG}"
