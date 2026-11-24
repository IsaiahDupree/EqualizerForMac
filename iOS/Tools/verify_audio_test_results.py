#!/usr/bin/env python3
"""Reject zero/skipped/partial XCTest runs even if xcodebuild exits successfully."""
import argparse
import json
from pathlib import Path
import re


def strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for child in value.values():
            yield from strings(child)
    elif isinstance(value, list):
        for child in value:
            yield from strings(child)


def verify(summary, test_tree, source):
    expected = set(re.findall(r"^\s*func\s+(test\w+)\s*\(", source, re.MULTILINE))
    errors = []
    if not expected:
        errors.append("No AudioContinuityTests functions were found in the source")
    if not isinstance(summary, dict):
        return ["xcresult summary is not an object"]
    for key, desired in (("totalTestCount", len(expected)), ("passedTests", len(expected)),
                         ("failedTests", 0), ("skippedTests", 0)):
        value = summary.get(key)
        if not isinstance(value, int) or isinstance(value, bool) or value != desired:
            errors.append(f"{key}: expected {desired}, observed {value!r}")
    if summary.get("result") != "Passed":
        errors.append(f"Session result is not Passed: {summary.get('result')!r}")
    if summary.get("testFailures"):
        errors.append("xcresult includes test/session failures")
    identifiers = "\n".join(strings(test_tree))
    for name in sorted(expected):
        if not re.search(r"\b" + re.escape(name) + r"\b", identifiers):
            errors.append(f"Expected test is absent from the result tree: {name}")
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("summary", type=Path)
    parser.add_argument("test_tree", type=Path)
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    try:
        errors = verify(json.loads(args.summary.read_text()), json.loads(args.test_tree.read_text()),
                        args.source.read_text())
    except (OSError, ValueError) as error:
        errors = [str(error)]
    if errors:
        raise SystemExit("Audio suite execution is not verified:\n" + "\n".join(errors))
    print("All expected AudioContinuityTests executed and passed; zero skipped tests.")


if __name__ == "__main__":
    main()
