#!/usr/bin/env python3
"""Read-only Sonance MAS configuration check; does not approve or upload a release."""
import argparse
import hashlib
import http.client
import json
import plistlib
import re
import signal
import subprocess
import sys
import uuid
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
BUNDLE = "com.isaiahdupree.SonanceEQ"
PRODUCT = BUNDLE + ".pro"
MAX_BYTES = 128 * 1024


class ConfigurationError(ValueError):
    pass


class ConfigurationTimeout(TimeoutError):
    pass


def require(condition, message):
    if not condition:
        raise ConfigurationError(message)


def decode_json(raw):
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, "Duplicate JSON property")
            result[key] = value
        return result

    def invalid_constant(_):
        raise ConfigurationError("Non-finite JSON value")

    require(len(raw) <= MAX_BYTES, "Configuration response exceeds 128 KiB")
    return json.loads(raw, object_pairs_hook=pairs, parse_constant=invalid_constant)


def read_settings(repo=REPO, configuration="Release-MAS"):
    result = subprocess.run([
        "xcodebuild", "-showBuildSettings", "-json", "-project", "SonanceEQ.xcodeproj",
        "-scheme", "SonanceEQ", "-configuration", configuration,
        "-destination", "generic/platform=macOS", "-jobs", "1",
        "-skipPackageUpdates",
    ], cwd=repo, capture_output=True, timeout=30, check=False)
    require(result.returncode == 0, "Xcode could not resolve build settings")
    rows = decode_json(result.stdout)
    require(isinstance(rows, list), "Invalid Xcode settings collection")
    selected = [row for row in rows if isinstance(row, dict) and row.get("target") == "SonanceEQ"]
    require(len(selected) == 1, "Expected exactly one SonanceEQ target")
    return selected[0]["buildSettings"]


def validate_settings(settings, repo=REPO):
    require(settings.get("CONFIGURATION") == "Release-MAS", "App Store builds require Release-MAS")
    require(settings.get("PRODUCT_BUNDLE_IDENTIFIER") == BUNDLE, "Wrong App Store bundle")
    require(settings.get("ENABLE_APP_SANDBOX") == "YES", "App Sandbox is disabled")
    require(settings.get("ENABLE_HARDENED_RUNTIME") == "YES", "Hardened runtime is disabled")
    flags = str(settings.get("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "")) + " " + str(settings.get("OTHER_SWIFT_FLAGS", ""))
    require("ENABLE_TCC_SPI" not in flags, "Private permission SPI is enabled")
    key = settings.get("REVENUECAT_PUBLIC_KEY", "")
    require(isinstance(key, str) and re.fullmatch(r"(?:appl|mac)_[A-Za-z0-9]{8,128}", key),
            "A live app-specific RevenueCat public key is required")
    source = (repo / settings.get("CODE_SIGN_ENTITLEMENTS", "")).resolve()
    expected = (repo / "Sources/SonanceEQ/Resources/SonanceEQ-MAS.entitlements").resolve()
    require(source == expected, "Wrong App Store entitlements source")
    require(source.stat().st_size <= MAX_BYTES, "Entitlements source exceeds size limit")
    entitlements = plistlib.loads(source.read_bytes())
    require(entitlements.get("com.apple.security.app-sandbox") is True, "Sandbox entitlement is missing")
    require(entitlements.get("com.apple.security.network.client") is True, "Purchase network entitlement is missing")
    validate_version_source(settings, repo)
    return key


def validate_version_source(settings, repo=REPO):
    """An incremented AppFleet build must reach the app's processed Info.plist."""
    root = repo.resolve()
    source = (repo / settings.get("INFOPLIST_FILE", "")).resolve()
    expected = (repo / "Sources/SonanceEQ/Resources/Info.plist").resolve()
    require(source == expected and source.is_relative_to(root), "Wrong app metadata source")
    require(source.is_file() and source.stat().st_size <= MAX_BYTES, "Missing or oversized metadata source")
    values = plistlib.loads(source.read_bytes())
    for field, reference in (("CFBundleShortVersionString", "$(MARKETING_VERSION)"),
                             ("CFBundleVersion", "$(CURRENT_PROJECT_VERSION)")):
        require(values.get(field) == reference, "App metadata must expand the build setting: " + field)
    config = decode_json((repo / "appstore.json").read_bytes())
    require(isinstance(config, dict) and config.get("bundle_id") == BUNDLE, "Wrong release manifest bundle")
    for field, setting in (("version", "MARKETING_VERSION"), ("build_number", "CURRENT_PROJECT_VERSION")):
        declared = config.get(field)
        require(isinstance(declared, str) and declared == settings.get(setting),
                "Release manifest and resolved build setting disagree: " + setting)


def validate_bundle_metadata(metadata, settings):
    for field, expected in {
        "CFBundleIdentifier": BUNDLE,
        "CFBundleExecutable": "SonanceEQ",
        "CFBundleShortVersionString": settings.get("MARKETING_VERSION"),
        "CFBundleVersion": settings.get("CURRENT_PROJECT_VERSION"),
        "RevenueCatPublicKey": settings.get("REVENUECAT_PUBLIC_KEY"),
    }.items():
        require(isinstance(expected, str) and bool(expected) and metadata.get(field) == expected,
                "Archived app metadata mismatch: " + field)


def validate_app(app, settings):
    info = app / "Contents/Info.plist"
    require(info.is_file() and info.stat().st_size <= MAX_BYTES, "Missing or oversized app Info.plist")
    raw = info.read_bytes()
    validate_bundle_metadata(plistlib.loads(raw), settings)
    require((app / "Contents/MacOS/SonanceEQ").is_file(), "Archived executable is missing")
    return {"info_plist_sha256": hashlib.sha256(raw).hexdigest(), "metadata": "verified"}


@contextmanager
def request_deadline(seconds=12):
    # CLI runs on the main thread. This bounds headers and trickling bodies too,
    # whereas a socket timeout alone only bounds inactivity between reads.
    def expired(*_):
        # HTTP chunk parsers catch ValueError; use a distinct timeout type so a
        # deadline cannot be reclassified as a malformed chunk or swallowed.
        raise ConfigurationTimeout("RevenueCat configuration read exceeded its deadline")

    previous_handler = signal.signal(signal.SIGALRM, expired)
    previous_timer = signal.setitimer(signal.ITIMER_REAL, seconds)
    try:
        yield
    finally:
        signal.setitimer(signal.ITIMER_REAL, *previous_timer)
        signal.signal(signal.SIGALRM, previous_handler)


def read_provider(path, key, connection=None):
    # No caller-supplied origin, redirects, secret key, customer-info read or write.
    require(path == "/v1/product_entitlement_mapping" or
            re.fullmatch(r"/v1/subscribers/sonance-config-read-[0-9a-f-]{36}/offerings", path),
            "Unsupported configuration endpoint")
    connection = connection or http.client.HTTPSConnection("api.revenuecat.com", timeout=5)
    try:
        with request_deadline():
            connection.request("GET", path, headers={"Authorization": "Bearer " + key,
                "Accept": "application/json", "X-Platform": "macOS",
                "User-Agent": "SonanceReleaseConfiguration/1"})
            response = connection.getresponse()
            require(response.status == 200, "RevenueCat configuration HTTP " + str(response.status))
            content_type = response.getheader("Content-Type", "").split(";", 1)[0].strip().lower()
            require(content_type == "application/json", "RevenueCat returned a non-JSON response")
            length = response.getheader("Content-Length")
            if length is not None:
                require(length.isdecimal() and int(length) <= MAX_BYTES, "Invalid or oversized response length")
            raw = response.read(MAX_BYTES + 1)
            return decode_json(raw), hashlib.sha256(raw).hexdigest()
    finally:
        connection.close()


def validate_live_configuration(mapping, offerings):
    require(isinstance(mapping, dict), "Invalid entitlement mapping")
    products = mapping.get("product_entitlement_mapping")
    require(isinstance(products, dict), "Missing entitlement mapping")
    product = products.get(PRODUCT)
    require(isinstance(product, dict) and product.get("product_identifier") == PRODUCT,
            "Approved Pro product is missing from RevenueCat")
    entitlements = product.get("entitlements")
    require(isinstance(entitlements, list) and all(isinstance(item, str) for item in entitlements)
            and len(entitlements) == len(set(entitlements)) and "pro" in entitlements,
            "Approved Pro product does not grant pro")
    require(isinstance(offerings, dict), "Invalid offerings response")
    rows = offerings.get("offerings")
    require(isinstance(rows, list) and 0 < len(rows) <= 100, "Missing or excessive offerings")
    by_id = {}
    for row in rows:
        require(isinstance(row, dict), "Invalid offering")
        identifier = row.get("identifier")
        require(isinstance(identifier, str) and identifier and identifier not in by_id,
                "Missing or duplicate offering identity")
        packages = row.get("packages")
        require(isinstance(packages, list) and len(packages) <= 100, "Invalid packages")
        identities = set()
        for package in packages:
            require(isinstance(package, dict), "Invalid package")
            identity = package.get("identifier")
            require(isinstance(identity, str) and identity and identity not in identities,
                    "Missing or duplicate package identity")
            require(isinstance(package.get("platform_product_identifier"), str), "Missing package product")
            identities.add(identity)
        by_id[identifier] = row
    current = offerings.get("current_offering_id")
    require(current is None or isinstance(current, str) and current in by_id,
            "Current offering is not in the complete response")
    # Mirrors PurchaseManager's current, then named-default fallback.
    for identifier in dict.fromkeys([current, "default"]):
        offering = by_id.get(identifier)
        if not offering:
            continue
        matches = [item for item in offering["packages"] if item["platform_product_identifier"] == PRODUCT]
        require(len(matches) <= 1, "Ambiguous approved Pro packages")
        if matches:
            return {"offering": identifier, "package": matches[0]["identifier"],
                    "product": PRODUCT, "entitlement": "pro"}
    raise ConfigurationError("No eligible Pro package in current or default offering")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, help="Actual compiled or archived SonanceEQ.app")
    parser.add_argument("--metadata-only", action="store_true", help="Check app/build metadata without a provider read")
    args = parser.parse_args()
    if args.metadata_only and args.app is None:
        parser.error("--metadata-only requires --app")
    report = {"schema": "sonance_mas_purchase_configuration_v1",
              "observed_at": datetime.now(timezone.utc).isoformat(),
              "release_acceptance": "pending", "customer_payment_verified": False,
              "live_storekit_price_verified": False, "receipt_to_entitlement_verified": False,
              "campaign_attribution_verified": False, "signature_verified": False}
    try:
        settings = read_settings()
        key = validate_settings(settings)
        report["sdk_key_sha256"] = hashlib.sha256(key.encode()).hexdigest()
        report["build_configuration"] = "Release-MAS"
        if args.app:
            report["app"] = validate_app(args.app, settings)
        if not args.metadata_only:
            mapping, mapping_hash = read_provider("/v1/product_entitlement_mapping", key)
            probe = str(uuid.uuid4())
            offerings, offering_hash = read_provider("/v1/subscribers/sonance-config-read-" + probe + "/offerings", key)
            report["revenuecat_configuration"] = validate_live_configuration(mapping, offerings)
            report["provider_body_sha256"] = {"mapping": mapping_hash, "offerings": offering_hash}
            report["offering_scope"] = "configuration_probe; customer targeting unverified"
        report["status"] = "metadata_verified" if args.metadata_only else "configuration_verified"
    except (ConfigurationError, OSError, ValueError, KeyError, TypeError,
            subprocess.SubprocessError, http.client.HTTPException) as error:
        report["status"] = "blocked"
        # Never echo provider bodies, keys, Xcode output or arbitrary exception strings.
        report["reason"] = str(error) if isinstance(error, (ConfigurationError, ConfigurationTimeout)) else type(error).__name__
    print(json.dumps(report, sort_keys=True))
    return 2 if report["status"] == "blocked" else 0


if __name__ == "__main__":
    sys.exit(main())
