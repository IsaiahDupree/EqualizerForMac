#!/usr/bin/env python3
"""Assess recorded physical-device evidence; never operates or records hardware.

Usage: python3 iOS/Tools/assess_audio_device_run.py RUN.json [--format json]
       [--output report.json]
Exit codes: 0 pass, 1 fail, 2 incomplete/not_run/input error.
No file is written unless --output is supplied. All thresholds are project
targets, not Apple guarantees. A pass is limited to the declared scope and
recorded configuration; unavailable instrumentation cannot establish a pass.
"""

import argparse
import json
import math
from pathlib import Path
import re
import sys

TARGETS = {"steady_state_seconds": 1800, "recovery_seconds": 2.0,
           "allowed_recovery_trials": 10, "negative_observation_seconds": 2.0}
COUNTERS = ("unexplained_audible_dropouts", "short_fills", "render_errors",
            "nonfinite_samples")
IDENTIFIERS = ("iphone_model", "ios_version", "bluetooth_device_model",
               "host_app", "host_version", "sonance_version", "sonance_commit")


def mapping(value):
    return value if isinstance(value, dict) else {}


def number(value):
    try:
        return (isinstance(value, (int, float)) and not isinstance(value, bool)
                and math.isfinite(value) and value >= 0)
    except OverflowError:
        return False


def text_present(value):
    return (isinstance(value, str) and bool(value.strip())
            and value.strip().lower() not in {"unknown", "tbd", "n/a", "null", "none"}
            and not value.strip().startswith("<"))


def assess(run):
    """Return a JSON-serializable assessment without modifying input or files."""
    run = mapping(run)
    report = {"status": "incomplete", "scope": run.get("scope"),
              "targets": dict(TARGETS), "failures": [], "missing": [],
              "notes": ["Evidence assessment only; no hardware test was executed.",
                        "A pass covers only this configuration and selected scope.",
                        "Tonal response, clipping/true peak, and real-time render deadlines "
                        "require separate measurements; this assesses continuity/recovery only."]}
    fail, missing = report["failures"], report["missing"]
    if run.get("status") == "not_run":
        report["status"] = "not_run"
        report["notes"].append("Run is explicitly marked not_run; measurements were not assessed.")
        return report
    if run.get("schema_version") != 1 or isinstance(run.get("schema_version"), bool):
        missing.append("schema_version must be 1")
    if run.get("status") != "recorded":
        missing.append("status must be recorded after a physical-device run")
    scope = run.get("scope")
    if scope not in ("steady_state", "recovery", "combined"):
        missing.append("scope must be steady_state, recovery, or combined")
    ids = mapping(run.get("identifiers"))
    for key in IDENTIFIERS:
        if not text_present(ids.get(key)):
            missing.append("identifiers." + key)
    commit = ids.get("sonance_commit")
    if text_present(commit) and not re.fullmatch(r"[0-9a-fA-F]{7,40}", commit):
        missing.append("identifiers.sonance_commit must be a 7-40 character hex commit")
    config = mapping(run.get("configuration"))
    for key in ("source_fixture", "output_route", "processing_chain"):
        if not text_present(config.get(key)):
            missing.append("configuration." + key)
    for key in ("actual_sample_rate_hz", "actual_channels", "actual_io_buffer_frames"):
        value = config.get(key)
        if not number(value) or value <= 0:
            missing.append("configuration." + key + " must be a measured positive value")
        elif key != "actual_sample_rate_hz" and not isinstance(value, int):
            missing.append("configuration." + key + " must be an integer")
    if scope in ("steady_state", "combined"):
        steady = mapping(run.get("steady_state"))
        if steady.get("continuous_input") is not True:
            missing.append("steady_state.continuous_input must be verified true")
        duration = steady.get("duration_seconds")
        if not number(duration) or duration < TARGETS["steady_state_seconds"]:
            missing.append("steady_state requires at least 1800 measured continuous seconds")
        counters = mapping(steady.get("counters"))
        for key in COUNTERS:
            counter = mapping(counters.get(key))
            count = counter.get("count")
            valid = isinstance(count, int) and not isinstance(count, bool) and count >= 0
            if counter.get("observed") is not True or not valid:
                missing.append("steady_state.counters." + key + " needs an observed integer count")
            if valid and count > 0:
                fail.append(key + "=" + str(count) + " (target: zero)")
    if scope in ("recovery", "combined"):
        assess_recovery(mapping(run.get("recovery")), fail, missing)
    report["status"] = "fail" if fail else ("incomplete" if missing else "pass")
    return report


def assess_recovery(recovery, fail, missing):
    trials = recovery.get("trials")
    if not isinstance(trials, list):
        missing.append("recovery.trials must be a list of recorded trials")
        trials = []
    allowed_count = 0
    negative_coverage = {"user_paused": False, "resume_disallowed": False}
    for index, raw in enumerate(trials):
        trial = mapping(raw)
        label = "recovery.trials[" + str(index) + "]"
        if not text_present(trial.get("event")):
            missing.append(label + ".event")
        for key in ("expected_interruption", "user_paused", "resume_allowed"):
            if not isinstance(trial.get(key), bool):
                missing.append(label + "." + key + " must be explicit true/false")
        if trial.get("expected_interruption") is False:
            fail.append(label + " records an unexpected interruption")
        paused, allowed = trial.get("user_paused"), trial.get("resume_allowed")
        resumed = trial.get("audio_resumed_at_s")
        if "audio_resumed_at_s" not in trial:
            missing.append(label + ".audio_resumed_at_s must be recorded (null means none observed)")
            continue
        if paused is True or allowed is False:
            if resumed is not None or trial.get("stayed_paused") is False:
                fail.append(label + " resumed despite user pause or denied resumption")
            duration = trial.get("observation_duration_seconds")
            verified = (trial.get("stayed_paused") is True and resumed is None
                        and number(duration)
                        and duration >= TARGETS["negative_observation_seconds"])
            if not verified:
                missing.append(label + " needs at least 2 seconds of verified paused observation")
            elif paused is True and allowed is True:
                negative_coverage["user_paused"] = True
            if verified and paused is False and allowed is False:
                negative_coverage["resume_disallowed"] = True
            continue
        if paused is not False or allowed is not True:
            continue
        route = trial.get("route_usable_at_s")
        permission = trial.get("resume_allowed_at_s")
        finished = trial.get("observation_finished_at_s")
        if not all(number(value) for value in (route, permission, finished)):
            missing.append(label + " needs measured route/permission/observation timestamps")
            continue
        start = max(route, permission)
        if finished < start:
            missing.append(label + " observation ends before the route/resumption opportunity")
            continue
        if resumed is None:
            if finished - start >= TARGETS["recovery_seconds"]:
                fail.append(label + " did not resume within 2 seconds of the usable/allowed state")
            else:
                missing.append(label + " observation is too short to judge recovery")
            continue
        if not number(resumed) or resumed > finished:
            missing.append(label + " needs a valid measured audio-resumption timestamp")
            continue
        if resumed < start:
            fail.append(label + " resumed before the route was usable and resumption allowed")
        elif resumed - start > TARGETS["recovery_seconds"]:
            fail.append(label + " recovery took " + str(round(resumed - start, 6)) + " seconds")
        else:
            allowed_count += 1
    if allowed_count < TARGETS["allowed_recovery_trials"]:
        missing.append("recovery needs 10 successful allowed-resumption trials; got " + str(allowed_count))
    for name, covered in negative_coverage.items():
        if not covered:
            missing.append("recovery needs a verified " + name + " negative trial")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run", type=Path, help="Recorded JSON or unrun template")
    parser.add_argument("--format", choices=("human", "json"), default="human")
    parser.add_argument("--output", type=Path, help="Write assessment JSON only when supplied")
    args = parser.parse_args(argv)
    try:
        report = assess(json.loads(args.run.read_text(encoding="utf-8")))
    except (OSError, ValueError) as error:
        report = {"status": "incomplete", "scope": None, "targets": dict(TARGETS),
                  "failures": [], "missing": ["Could not read run JSON: " + str(error)], "notes": []}
    serialized = json.dumps(report, indent=2, allow_nan=False) + "\n"
    if args.output:
        try:
            args.output.write_text(serialized, encoding="utf-8")
        except OSError as error:
            print("Could not write assessment: " + str(error), file=sys.stderr)
            return 2
    if args.format == "json":
        print(serialized, end="")
    else:
        print("Audio device evidence: " + report["status"].upper())
        print("Scope: " + str(report["scope"]))
        for key in ("failures", "missing", "notes"):
            for message in report[key]:
                print(key + ": " + message)
    return {"pass": 0, "fail": 1, "incomplete": 2, "not_run": 2}[report["status"]]


if __name__ == "__main__":
    sys.exit(main())
