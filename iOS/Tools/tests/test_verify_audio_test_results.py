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


if __name__ == "__main__":
    unittest.main()
