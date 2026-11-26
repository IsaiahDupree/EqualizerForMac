import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("verify_audio_test_results", Path(__file__).parents[1] / "verify_audio_test_results.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class XcodeEvidenceTests(unittest.TestCase):
    source = "func testFidelity() async throws {}\nfunc testContinuity() throws {}\n"

    def evidence(self):
        return ({"result": "Passed", "totalTestCount": 2, "passedTests": 2,
                 "failedTests": 0, "skippedTests": 0, "testFailures": []},
                {"testNodes": [{"name": "AudioContinuityTests", "children": [
                    {"name": "testFidelity()", "result": "Passed"},
                    {"name": "testContinuity()", "result": "Passed"}]}]})

    def test_full_run_passes(self):
        summary, tree = self.evidence()
        self.assertEqual(module.verify(summary, tree, self.source), [])

    def test_zero_tests_cannot_pass(self):
        summary, tree = self.evidence()
        summary.update(totalTestCount=0, passedTests=0)
        self.assertTrue(module.verify(summary, tree, self.source))

    def test_skipped_or_partial_runs_cannot_pass(self):
        summary, tree = self.evidence()
        summary.update(passedTests=1, skippedTests=1)
        self.assertTrue(module.verify(summary, tree, self.source))

    def test_wrong_tests_with_same_count_cannot_pass(self):
        summary, tree = self.evidence()
        tree["testNodes"][0]["children"][0]["name"] = "testSomethingElse()"
        self.assertTrue(module.verify(summary, tree, self.source))

    def test_session_failure_cannot_hide_behind_passed_cases(self):
        summary, tree = self.evidence()
        summary.update(result="Failed", testFailures=[{"message": "Session failure"}])
        self.assertTrue(module.verify(summary, tree, self.source))

    def test_missing_or_unrecognized_schema_cannot_pass(self):
        self.assertTrue(module.verify({}, {}, self.source))
        self.assertTrue(module.verify([], {}, self.source))

    def test_no_expected_tests_cannot_pass(self):
        self.assertTrue(module.verify({"result": "Passed", "totalTestCount": 0,
                                       "passedTests": 0, "failedTests": 0,
                                       "skippedTests": 0}, {}, ""))

    def test_booleans_are_not_counts(self):
        summary, tree = self.evidence()
        summary["failedTests"] = False
        self.assertTrue(module.verify(summary, tree, self.source))


    def test_names_in_metadata_are_not_execution_evidence(self):
        summary, _ = self.evidence()
        tree = {"testNodes": [], "notes": "testFidelity testContinuity"}
        self.assertTrue(module.verify(summary, tree, self.source))

    def test_other_suite_cannot_satisfy_gate(self):
        summary, tree = self.evidence()
        tree["testNodes"][0]["name"] = "OtherTests"
        self.assertTrue(module.verify(summary, tree, self.source))

    def test_individual_failed_or_missing_result_cannot_pass(self):
        for result in ("Failed", "Skipped", None):
            with self.subTest(result=result):
                summary, tree = self.evidence()
                tree["testNodes"][0]["children"][0]["result"] = result
                self.assertTrue(module.verify(summary, tree, self.source))

    def test_duplicate_case_cannot_pass(self):
        summary, tree = self.evidence()
        children = tree["testNodes"][0]["children"]
        children.append(dict(children[0]))
        self.assertTrue(module.verify(summary, tree, self.source))

    def test_nested_xcresult_suite_passes(self):
        summary, tree = self.evidence()
        suite = tree["testNodes"][0]
        suite["nodeType"] = "Test Suite"
        for case in suite["children"]:
            case["nodeType"] = "Test Case"
        tree["testNodes"] = [{"name": "Test Plan", "children": [
            {"name": "SonanceEQiOSTests", "children": [suite]}]}]
        self.assertEqual(module.verify(summary, tree, self.source), [])

if __name__ == "__main__":
    unittest.main()
