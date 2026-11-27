#!/usr/bin/env bash
set -euo pipefail

# Install the EffectDeck-derived Sonance EQ host on the assigned stationary iPhone 11 by
# exact UDID. The optional Media Device route companion is a separate Apple
# capability and must not prevent installing or testing the full host.
DEVICE_ID="${SONANCE_IPHONE_UDID:-00008030-000359A13688802E}"
TEAM_ID="${SONANCE_DEVELOPMENT_TEAM:-Y4HDXFWXUV}"
HOST_BUNDLE_ID="com.isaiahdupree.SonanceEQ.iOSPrototype"
ROUTE_BUNDLE_ID="com.isaiahdupree.SonanceEQ.iOSPrototype.RouteInstaller"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST_PROJECT="${PROJECT_ROOT}/iOS/Vendor/EffectDeck/SonanceEQHost.xcodeproj"
CONFIGURATION="${SONANCE_BUILD_CONFIGURATION:-Debug}"
BUILD_JOBS="${SONANCE_BUILD_JOBS:-2}"
DERIVED_DATA="${SONANCE_IPHONE_DERIVED_DATA:-/tmp/SonanceEQHostDeviceDerivedData}"
LOG_DIR="${SONANCE_IPHONE_LOG_DIR:-${DERIVED_DATA}/logs}"
MIN_BUILD_FREE_KB="${SONANCE_BUILD_MIN_FREE_KB:-4194304}"
HOST_APP_PATH="${DERIVED_DATA}/Build/Products/${CONFIGURATION}-iphoneos/SonanceEQHost.app"
ROUTE_APP_PATH="${DERIVED_DATA}/Build/Products/${CONFIGURATION}-iphoneos/SonanceEQRoute.app"
HOST_SPEC="${PROJECT_ROOT}/iOS/sonance-host.project.yml"
INSTALL_ROUTE_COMPANION="${SONANCE_INSTALL_ROUTE_COMPANION:-0}"
SIGNING_SETTINGS=("DEVELOPMENT_TEAM=${TEAM_ID}" "CODE_SIGN_STYLE=Automatic")

if [[ "${INSTALL_ROUTE_COMPANION}" != "0" && "${INSTALL_ROUTE_COMPANION}" != "1" ]]; then
    echo "SONANCE_INSTALL_ROUTE_COMPANION must be 0 or 1." >&2
    exit 2
fi

if [[ ! "${BUILD_JOBS}" =~ ^[1-4]$ ]]; then
    echo "SONANCE_BUILD_JOBS must be an integer from 1 to 4." >&2
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
fi

if ! xcodebuild -license check >/dev/null 2>&1; then
    cat >&2 <<'EOF'
Xcode is not ready. Open Xcode on this Mac and complete first-use setup
before building. This script will not accept license agreements for you.
EOF
    exit 2
fi

if [[ ( "${DERIVED_DATA}" == "/Volumes/SonanceEQBuildScratch" || "${DERIVED_DATA}" == "/Volumes/SonanceEQBuildScratch/"* ) && ! -d "/Volumes/SonanceEQBuildScratch" ]]; then
    echo "Build volume /Volumes/SonanceEQBuildScratch is not mounted; refusing to fill the Mac system volume." >&2
    exit 2
fi

diagnose_device_connection() {
    echo "CoreDevice record for ${DEVICE_ID}:" >&2
    xcrun devicectl list devices --search "${DEVICE_ID}" --timeout 10 >&2 || true

    if command -v idevice_id >/dev/null 2>&1; then
        if idevice_id -l 2>/dev/null | /usr/bin/grep -Fxq "${DEVICE_ID}"; then
            echo "usbmuxd lists the target UDID." >&2
        else
            echo "usbmuxd does not list the target UDID." >&2
        fi
    else
        echo "libimobiledevice is unavailable; usbmuxd enumeration was not checked." >&2
    fi

    local usb_match
    usb_match="$(system_profiler SPUSBDataType 2>/dev/null | /usr/bin/grep -i -E 'iPhone|Apple Mobile Device' || true)"
    if [[ -n "${usb_match}" ]]; then
        echo "USB inventory contains an Apple mobile device:" >&2
        echo "${usb_match}" >&2
    else
        echo "USB inventory contains no iPhone / Apple Mobile Device entry." >&2
    fi
    echo "No pairing, service restart, or device mutation was attempted." >&2
}

if ! xcrun xcdevice list --timeout 10 2>/dev/null | /usr/bin/python3 -c '
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
    echo "Target iPhone ${DEVICE_ID} is not available to Xcode; collecting read-only connection diagnostics." >&2
    diagnose_device_connection
    exit 2
fi

if [[ ! "${MIN_BUILD_FREE_KB}" =~ ^[0-9]+$ ]] || (( MIN_BUILD_FREE_KB < 1 )); then
    echo "SONANCE_BUILD_MIN_FREE_KB must be a positive integer." >&2
    exit 2
fi

SPACE_CHECK_PATH="$(dirname "${DERIVED_DATA}")"
if [[ ! -d "${SPACE_CHECK_PATH}" ]]; then
    echo "The parent directory for the DerivedData path is not mounted or does not exist: ${SPACE_CHECK_PATH}" >&2
    exit 2
fi
AVAILABLE_BUILD_KB="$(df -Pk "${SPACE_CHECK_PATH}" | awk 'NR == 2 { print $4 }')"
if [[ ! "${AVAILABLE_BUILD_KB}" =~ ^[0-9]+$ ]] || (( AVAILABLE_BUILD_KB < MIN_BUILD_FREE_KB )); then
    echo "Build volume for ${DERIVED_DATA} has ${AVAILABLE_BUILD_KB:-unknown} KiB free; ${MIN_BUILD_FREE_KB} KiB is required." >&2
    echo "Set SONANCE_IPHONE_DERIVED_DATA to a mounted build volume with sufficient free space." >&2
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
    local -a xcode_args
    xcode_args=(
        -project "${HOST_PROJECT}"
        -scheme "${scheme}"
        -configuration "${CONFIGURATION}"
        -destination "platform=iOS,id=${DEVICE_ID}"
        -derivedDataPath "${DERIVED_DATA}"
        -jobs "${BUILD_JOBS}"
        -allowProvisioningUpdates
    )
    if [[ "${AUTH_SET:-0}" -eq 3 ]]; then
        xcode_args+=(
            -authenticationKeyPath "${SONANCE_ASC_API_KEY_PATH}"
            -authenticationKeyID "${SONANCE_ASC_API_KEY_ID}"
            -authenticationKeyIssuerID "${SONANCE_ASC_API_ISSUER_ID}"
        )
    fi
    echo "Building ${scheme} for iPhone ${DEVICE_ID}..."
    set -o pipefail
    if ! xcodebuild \
        "${xcode_args[@]}" \
        build "${SIGNING_SETTINGS[@]}" 2>&1 | tee "${log_path}"; then
        if rg -qi 'error:.*(provisioning profile|entitlement).*(application-groups|group\.com\.isaiahdupree\.SonanceEQ)|(application-groups|group\.com\.isaiahdupree\.SonanceEQ).*error:.*(provisioning profile|entitlement)' "${log_path}"; then
            echo "Signing blocked: assign group.com.isaiahdupree.SonanceEQ to the host and Share App IDs, then regenerate their provisioning profiles." >&2
        fi
        if rg -qi 'error:.*(provisioning profile|entitlement).*com\.apple\.developer\.media-device-extension|com\.apple\.developer\.media-device-extension.*error:.*(provisioning profile|entitlement)' "${log_path}"; then
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

# Refuse a stale DerivedData product. Bundle ID alone cannot distinguish the
# combined host from older prototype builds that used the same identifier.
EXPECTED_HOST_VERSION="$(awk '/^    MARKETING_VERSION:/ { print $2; exit }' "${HOST_SPEC}" | tr -d '"')"
EXPECTED_HOST_BUILD="$(awk '/^    CURRENT_PROJECT_VERSION:/ { print $2; exit }' "${HOST_SPEC}" | tr -d '"')"
if [[ -z "${EXPECTED_HOST_VERSION}" || -z "${EXPECTED_HOST_BUILD}" ]]; then
    echo "Could not read expected host version/build from ${HOST_SPEC}." >&2
    exit 1
fi
PRODUCT_HOST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${HOST_APP_PATH}/Info.plist")"
PRODUCT_HOST_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${HOST_APP_PATH}/Info.plist")"
if [[ "${PRODUCT_HOST_VERSION}" != "${EXPECTED_HOST_VERSION}" || "${PRODUCT_HOST_BUILD}" != "${EXPECTED_HOST_BUILD}" ]]; then
    echo "Refusing stale host product: expected ${EXPECTED_HOST_VERSION} (${EXPECTED_HOST_BUILD}), found ${PRODUCT_HOST_VERSION} (${PRODUCT_HOST_BUILD}) at ${HOST_APP_PATH}." >&2
    exit 1
fi

echo "Installing ${HOST_BUNDLE_ID} on ${DEVICE_ID}..."
xcrun devicectl device install app --device "${DEVICE_ID}" "${HOST_APP_PATH}"
INSTALLED_APPS_JSON="${LOG_DIR}/installed-host-apps.json"
xcrun devicectl device info apps --device "${DEVICE_ID}" --bundle-id "${HOST_BUNDLE_ID}" --json-output "${INSTALLED_APPS_JSON}" >/dev/null
python3 - "${INSTALLED_APPS_JSON}" "${HOST_BUNDLE_ID}" "${EXPECTED_HOST_VERSION}" "${EXPECTED_HOST_BUILD}" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
apps = payload.get("result", {}).get("apps", [])
matches = [app for app in apps if app.get("bundleIdentifier") == sys.argv[2]]
if len(matches) != 1:
    raise SystemExit(f"Expected one installed host app, found {len(matches)}")
app = matches[0]
actual = (app.get("version"), app.get("bundleVersion"))
expected = (sys.argv[3], sys.argv[4])
if actual != expected:
    raise SystemExit(f"Installed host version mismatch: expected {expected[0]} ({expected[1]}), found {actual[0]} ({actual[1]})")
print(f"Verified installed host {app['bundleIdentifier']} {actual[0]} ({actual[1]})")
PY
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
