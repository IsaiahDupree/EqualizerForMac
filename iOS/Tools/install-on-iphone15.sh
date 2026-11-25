#!/usr/bin/env bash
set -euo pipefail

# Install the EffectDeck-derived Sonance EQ host on the assigned iPhone 15 by
# exact UDID. The optional Media Device route companion is a separate Apple
# capability and must not prevent installing or testing the full host.
DEVICE_ID="${SONANCE_IPHONE_UDID:-00008120-000465A20C52201E}"
TEAM_ID="${SONANCE_DEVELOPMENT_TEAM:-Y4HDXFWXUV}"
HOST_BUNDLE_ID="com.isaiahdupree.SonanceEQ.iOSPrototype"
ROUTE_BUNDLE_ID="com.isaiahdupree.SonanceEQ.iOSPrototype.RouteInstaller"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST_PROJECT="${PROJECT_ROOT}/iOS/Vendor/EffectDeck/SonanceEQHost.xcodeproj"
CONFIGURATION="${SONANCE_BUILD_CONFIGURATION:-Debug}"
DERIVED_DATA="${SONANCE_IPHONE_DERIVED_DATA:-/Volumes/SonanceEQBuildScratch/SonanceEQHostDeviceDerivedData}"
LOG_DIR="${SONANCE_IPHONE_LOG_DIR:-/Volumes/SonanceEQBuildScratch/SonanceEQHostDeviceInstall}"
HOST_APP_PATH="${DERIVED_DATA}/Build/Products/${CONFIGURATION}-iphoneos/SonanceEQHost.app"
ROUTE_APP_PATH="${DERIVED_DATA}/Build/Products/${CONFIGURATION}-iphoneos/SonanceEQRoute.app"
INSTALL_ROUTE_COMPANION="${SONANCE_INSTALL_ROUTE_COMPANION:-0}"
SIGNING_SETTINGS=("DEVELOPMENT_TEAM=${TEAM_ID}" "CODE_SIGN_STYLE=Automatic")
AUTHENTICATION_ARGS=()

if [[ "${INSTALL_ROUTE_COMPANION}" != "0" && "${INSTALL_ROUTE_COMPANION}" != "1" ]]; then
    echo "SONANCE_INSTALL_ROUTE_COMPANION must be 0 or 1." >&2
    exit 2
fi

for name in SONANCE_ASC_API_KEY_PATH SONANCE_ASC_API_KEY_ID SONANCE_ASC_API_ISSUER_ID; do
    if [[ -n "${!name:-}" ]]; then
        AUTH_SET=$(( ${AUTH_SET:-0} + 1 ))
    fi
done
if [[ "${AUTH_SET:-0}" -ne 0 && "${AUTH_SET:-0}" -ne 3 ]]; then
    echo "Set all three SONANCE_ASC_API_KEY_PATH, SONANCE_ASC_API_KEY_ID and SONANCE_ASC_API_ISSUER_ID values, or leave all unset." >&2
    exit 2
fi
if [[ "${AUTH_SET:-0}" -eq 3 ]]; then
    if [[ ! -r "${SONANCE_ASC_API_KEY_PATH}" ]]; then
        echo "App Store Connect API key file is missing or unreadable." >&2
        exit 2
    fi
    AUTHENTICATION_ARGS+=(
        -authenticationKeyPath "${SONANCE_ASC_API_KEY_PATH}"
        -authenticationKeyID "${SONANCE_ASC_API_KEY_ID}"
        -authenticationKeyIssuerID "${SONANCE_ASC_API_ISSUER_ID}"
    )
fi

if ! xcodebuild -license check >/dev/null 2>&1; then
    cat >&2 <<'EOF'
Xcode is not ready. Open Xcode on this Mac and complete first-use setup
before building. This script will not accept license agreements for you.
EOF
    exit 2
fi

if [[ ! -d "/Volumes/SonanceEQBuildScratch" ]]; then
    echo "Build volume /Volumes/SonanceEQBuildScratch is not mounted; refusing to fill the Mac system volume." >&2
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

echo "Regenerating the Sonance EQ host project from its tracked spec..."
bash "${PROJECT_ROOT}/iOS/Tools/generate-sonance-host-project.sh"
if [[ ! -d "${HOST_PROJECT}" ]]; then
    echo "Generated project was not found at ${HOST_PROJECT}." >&2
    exit 2
fi

mkdir -p "${LOG_DIR}" "${DERIVED_DATA}"

build_scheme() {
    local scheme="$1"
    local log_path="${LOG_DIR}/${scheme}-xcodebuild.log"
    echo "Building ${scheme} for iPhone ${DEVICE_ID}..."
    set -o pipefail
    if ! xcodebuild \
        -project "${HOST_PROJECT}" \
        -scheme "${scheme}" \
        -configuration "${CONFIGURATION}" \
        -destination "platform=iOS,id=${DEVICE_ID}" \
        -derivedDataPath "${DERIVED_DATA}" \
        -allowProvisioningUpdates \
        "${AUTHENTICATION_ARGS[@]}" \
        build "${SIGNING_SETTINGS[@]}" 2>&1 | tee "${log_path}"; then
        if rg -q 'com.apple.security.application-groups' "${log_path}"; then
            echo "Signing blocked: assign group.com.isaiahdupree.SonanceEQ to the host and Share App IDs, then regenerate their provisioning profiles." >&2
        fi
        if rg -q 'com.apple.developer.media-device-extension' "${log_path}"; then
            echo "Signing blocked: Apple must enable the Media Device capability for the route installer and extension App IDs, then issue matching profiles." >&2
        fi
        echo "Build failed. See ${log_path}." >&2
        return 1
    fi
}

build_scheme "EffeTuneLive"

verify_bundle_id() {
    local app_path="$1"
    local expected="$2"
    if [[ ! -d "${app_path}" ]]; then
        echo "Build succeeded but app bundle is missing: ${app_path}" >&2
        exit 1
    fi
    local actual
    actual="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${app_path}/Info.plist")"
    if [[ "${actual}" != "${expected}" ]]; then
        echo "Refusing install: expected ${expected}, found ${actual} in ${app_path}." >&2
        exit 1
    fi
    codesign --verify --deep --strict "${app_path}"
}

verify_bundle_id "${HOST_APP_PATH}" "${HOST_BUNDLE_ID}"

echo "Installing ${HOST_BUNDLE_ID} on ${DEVICE_ID}..."
xcrun devicectl device install app --device "${DEVICE_ID}" "${HOST_APP_PATH}"
echo "Launching ${HOST_BUNDLE_ID} on ${DEVICE_ID}..."
xcrun devicectl device process launch --device "${DEVICE_ID}" "${HOST_BUNDLE_ID}"

if [[ "${INSTALL_ROUTE_COMPANION}" == "1" ]]; then
    build_scheme "SonanceEQRouteInstaller"
    verify_bundle_id "${ROUTE_APP_PATH}" "${ROUTE_BUNDLE_ID}"
    echo "Installing ${ROUTE_BUNDLE_ID} on ${DEVICE_ID}..."
    xcrun devicectl device install app --device "${DEVICE_ID}" "${ROUTE_APP_PATH}"
fi

cat <<EOF
Installed and launched the full Sonance EQ host on ${DEVICE_ID}.
Host build log: ${LOG_DIR}/EffeTuneLive-xcodebuild.log
EOF
if [[ "${INSTALL_ROUTE_COMPANION}" == "1" ]]; then
    echo "Route companion build log: ${LOG_DIR}/SonanceEQRouteInstaller-xcodebuild.log"
fi
