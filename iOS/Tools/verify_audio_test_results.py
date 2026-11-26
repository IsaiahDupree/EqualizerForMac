#!/usr/bin/env python3
"""Reject zero/skipped/partial XCTest runs even if xcodebuild exits successfully."""
import argparse
import json
from pathlib import Path
import re


def nodes(value):
    """Traverse only xcresult node lists, never arbitrary metadata strings."""
    if isinstance(value, list):
        for node in value:
            if isinstance(node, dict):
                yield node
                yield from nodes(node.get("children"))


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
    roots = test_tree.get("testNodes") if isinstance(test_tree, dict) else None
    suites = [node for node in nodes(roots)
              if node.get("name") == "AudioContinuityTests"
              and node.get("nodeType", "Test Suite") == "Test Suite"]
    if len(suites) != 1:
        errors.append(f"Expected exactly one AudioContinuityTests suite, observed {len(suites)}")
        return errors
    children = suites[0].get("children")
    cases = children if isinstance(children, list) else []
    for name in sorted(expected):
        matches = [case for case in cases if isinstance(case, dict)
                   and case.get("name") in (name, name + "()")
                   and case.get("nodeType", "Test Case") == "Test Case"]
        if len(matches) != 1:
            errors.append(f"Expected exactly one result for {name}, observed {len(matches)}")
        elif matches[0].get("result") != "Passed":
            errors.append(f"{name}: expected Passed, observed {matches[0].get('result')!r}")
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
