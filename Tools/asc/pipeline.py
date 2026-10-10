#!/usr/bin/env python3
"""Sonance's checkout-local entry to AppFleet. No arguments runs read-only doctor.

ship/all preview a source release; upload previews an explicitly named PKG and
build number. --yes delegates writes, VALID processing and attachment to AppFleet.
"""
import argparse
import hashlib
import http.client
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "Tools"))
import verify_mas_purchase_config as gate


def canonical_pipeline():
    configured = os.environ.get("APPFLEET_PIPELINE")
    path = Path(configured).expanduser() if configured else Path.home() / "Documents/Software/AppFleet/appstore_pipeline.py"
    gate.require(path.is_absolute() and path.is_file(), "Canonical AppFleet pipeline is unavailable")
    return path.resolve()


def appfleet_module(path):
    # Reuse the canonical generator; no local build/sign/upload implementation.
    sys.path.insert(0, str(path.parent))
    spec = importlib.util.spec_from_file_location("sonance_appfleet", path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def parser():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("command", nargs="?", choices=("doctor", "status", "ship", "all", "upload"), default="doctor")
    cli.add_argument("--artifact", type=Path, help="Explicit existing Sonance .pkg; no directory is guessed")
    cli.add_argument("--build-number", help="Exact numeric build in the existing package, or an explicit source build")
    cli.add_argument("--yes", action="store_true", help="Authorize AppFleet build/Apple writes, upload and attachment")
    cli.add_argument("--json", action="store_true", help="JSON doctor/status output")
    return cli


def plan(args, pipeline, repo=REPO):
    readonly = args.command in ("doctor", "status")
    gate.require(not readonly or not (args.yes or args.artifact or args.build_number),
                 "doctor/status accept no write or artifact options")
    if args.build_number is not None:
        gate.require(args.build_number.isdecimal() and 0 < int(args.build_number) < 2**31,
                     "An explicit positive numeric build number is required")
    if args.command == "upload":
        gate.require(args.artifact is not None and args.build_number is not None,
                     "upload requires --artifact and --build-number; no implicit package path is used")
    if args.artifact is not None:
        gate.require(not readonly and args.build_number is not None, "Existing packages require --build-number")
        artifact = args.artifact.expanduser().resolve()
        gate.require(artifact.is_file() and artifact.suffix.lower() == ".pkg", "Explicit installer package does not exist")
    else:
        artifact = None
    command = [sys.executable, str(pipeline), args.command if readonly else "ship", str(repo),
               "--scheme", "SonanceEQ", "--configuration", "Release-MAS", "--platform", "macos",
               "--bundle-id", gate.BUNDLE]
    if artifact:
        command += ["--artifact", str(artifact)]
    if args.build_number:
        command += ["--build-number", args.build_number]
    if args.yes:
        command.append("--yes")
    if args.json and readonly:
        command.append("--json")
    return command, artifact


def validate_package_purchase_metadata(artifact, settings, build_number):
    gate.require(0 < artifact.stat().st_size <= 256 * 1024 * 1024, "Installer package exceeds the Sonance size bound")
    digest = file_digest(artifact)
    with tempfile.TemporaryDirectory(prefix="sonance-pkg-read-") as directory:
        expanded = Path(directory) / "expanded"
        subprocess.run(["pkgutil", "--expand-full", str(artifact), str(expanded)],
                       capture_output=True, check=True, timeout=60)
        apps = [app for app in expanded.rglob("*.app")
                if not any(parent.suffix == ".app" for parent in app.relative_to(expanded).parents)]
        gate.require(len(apps) == 1, "Package must contain exactly one main app")
        app = apps[0]
        gate.require(app.resolve().is_relative_to(expanded.resolve())
                     and (app / "Contents/Info.plist").resolve().is_relative_to(expanded.resolve()),
                     "Package app metadata escapes the extracted payload")
        expected = dict(settings, CURRENT_PROJECT_VERSION=build_number)
        metadata = gate.validate_app(app, expected)
    gate.require(file_digest(artifact) == digest, "Package changed during inspection")
    return {"package_sha256": digest, **metadata, "distribution_signature_verified": False}


def file_digest(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(256 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main():
    args = parser().parse_args()
    try:
        pipeline = canonical_pipeline()
        command, artifact = plan(args, pipeline)
        if args.command in ("doctor", "status"):
            os.execv(sys.executable, command)
        if args.yes and artifact is None:
            config = gate.decode_json((REPO / "appstore.json").read_bytes())
            appfleet_module(pipeline).generate_project_for_authorized_ship(REPO, config, None)
        settings = gate.read_settings(repo=REPO)
        key = gate.validate_settings(settings, repo=REPO)
        metadata = validate_package_purchase_metadata(artifact, settings, args.build_number) if artifact else None
        if not args.yes:
            print(json.dumps({"schema": "sonance_appfleet_handoff_v1", "status": "preview", "dry_run": True,
                              "source_repo": str(REPO), "command": command, "package": metadata,
                              "native_distribution_verified": False, "release_acceptance": "pending"}, indent=2))
            return 0
        # Public app-specific configuration reads only; no customers or receipts.
        import uuid
        mapping, _ = gate.read_provider("/v1/product_entitlement_mapping", key)
        offerings, _ = gate.read_provider("/v1/subscribers/sonance-config-read-" + str(uuid.uuid4()) + "/offerings", key)
        gate.validate_live_configuration(mapping, offerings)
        # AppFleet revalidates repository/signatures/team/profiles/version/build
        # before Apple writes and owns the full upload -> VALID -> attachment flow.
        os.execv(sys.executable, command)
    except (gate.ConfigurationError, OSError, ValueError, TypeError, KeyError, RuntimeError,
            subprocess.SubprocessError, http.client.HTTPException) as error:
        reason = str(error) if isinstance(error, gate.ConfigurationError) else type(error).__name__
        print(json.dumps({"schema": "sonance_appfleet_handoff_v1", "status": "blocked", "reason": reason,
                          "release_acceptance": "pending"}))
        return 2


if __name__ == "__main__":
    sys.exit(main())
