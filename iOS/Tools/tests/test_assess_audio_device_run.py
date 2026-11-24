"""Synthetic in-memory evidence tests; these do not certify real audio hardware."""

import copy
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import unittest
from unittest import mock

MODULE = Path(__file__).resolve().parents[1] / "assess_audio_device_run.py"
SPEC = importlib.util.spec_from_file_location("assess_audio_device_run", MODULE)
ASSESSOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ASSESSOR)


def valid_steady():
    return {
        "schema_version": 2, "status": "recorded", "scope": "steady_state",
        "identifiers": {
            "iphone_model": "synthetic-test-device", "ios_version": "test-os",
            "bluetooth_device_model": "synthetic-headphones", "host_app": "test-host",
            "host_version": "test-version", "sonance_version": "test-build",
            "sonance_commit": "a" * 40,
        },
        "configuration": {
            "source_fixture": "synthetic-continuous-fixture", "output_route": "BluetoothA2DP",
            "actual_sample_rate_hz": 48000, "actual_channels": 2,
            "actual_io_buffer_frames": 1024, "processing_chain": "Sonance only",
        },
        "steady_state": {
            "continuous_input": True, "duration_seconds": 1800,
            "counters": {name: {"count": 0, "observed": True} for name in ASSESSOR.COUNTERS},
            "sonance_effect_timing": {
                "instrumented": True, "completed_blocks": 1000, "deadline_overruns": 0,
                "maximum_processing_microseconds": 1200,
                "last_buffer_deadline_microseconds": 5333,
            },
        },
    }


def recovery_trial():
    return {"event": "bluetooth_reconnect", "expected_interruption": True,
            "user_paused": False, "resume_allowed": True, "route_usable_at_s": 10.0,
            "resume_allowed_at_s": 11.0, "audio_resumed_at_s": 12.0,
            "observation_finished_at_s": 15.0, "stayed_paused": False}


def valid_recovery():
    run = valid_steady()
    run["scope"] = "recovery"
    trials = [recovery_trial() for _ in range(10)]
    for user_paused, resume_allowed in ((True, True), (False, False)):
        trials.append({"event": "interruption", "expected_interruption": True,
                       "user_paused": user_paused, "resume_allowed": resume_allowed,
                       "audio_resumed_at_s": None, "stayed_paused": True,
                       "observation_duration_seconds": 3.0})
    run["recovery"] = {"trials": trials}
    return run


class EvidenceAssessmentTests(unittest.TestCase):
    def status(self, run):
        return ASSESSOR.assess(run)["status"]

    def test_explicit_not_run_cannot_pass(self):
        self.assertEqual(self.status({"status": "not_run", "scope": "combined"}), "not_run")

    def test_complete_steady_evidence_passes_its_scope_only(self):
        self.assertEqual(self.status(valid_steady()), "pass")

    def test_legacy_schema_one_remains_supported_without_effect_timing(self):
        run = valid_steady()
        run["schema_version"] = 1
        del run["steady_state"]["sonance_effect_timing"]
        self.assertEqual(self.status(run), "pass")

    def test_effect_timing_is_required_and_overruns_fail(self):
        run = valid_steady()
        run["steady_state"]["sonance_effect_timing"]["instrumented"] = False
        self.assertEqual(self.status(run), "incomplete")
        run = valid_steady()
        run["steady_state"]["sonance_effect_timing"]["deadline_overruns"] = 1
        self.assertEqual(self.status(run), "fail")

    def test_invalid_effect_timing_cannot_pass(self):
        for field, value in (("completed_blocks", True), ("completed_blocks", 0),
                             ("deadline_overruns", -1),
                             ("maximum_processing_microseconds", float("inf")),
                             ("last_buffer_deadline_microseconds", 0)):
            with self.subTest(field=field, value=value):
                run = valid_steady()
                run["steady_state"]["sonance_effect_timing"][field] = value
                self.assertEqual(self.status(run), "incomplete")

    def test_null_and_uninstrumented_counters_are_incomplete(self):
        for observed, count in ((True, None), (False, None), (False, 0)):
            with self.subTest(observed=observed, count=count):
                run = valid_steady()
                run["steady_state"]["counters"]["short_fills"] = {"observed": observed, "count": count}
                self.assertEqual(self.status(run), "incomplete")

    def test_each_injected_counter_fault_fails(self):
        for counter in ASSESSOR.COUNTERS:
            with self.subTest(counter=counter):
                run = valid_steady()
                run["steady_state"]["counters"][counter]["count"] = 1
                self.assertEqual(self.status(run), "fail")

    def test_observed_failure_is_not_hidden_by_missing_evidence(self):
        run = valid_steady()
        run["identifiers"]["ios_version"] = None
        run["steady_state"]["counters"]["render_errors"]["count"] = 1
        self.assertEqual(self.status(run), "fail")

    def test_invalid_counter_types_cannot_be_zero(self):
        for count in (False, -1, "0", 0.0, float("nan")):
            with self.subTest(count=count):
                run = valid_steady()
                run["steady_state"]["counters"]["render_errors"]["count"] = count
                self.assertEqual(self.status(run), "incomplete")

    def test_missing_identifiers_are_incomplete_firmware_optional(self):
        for key in ASSESSOR.IDENTIFIERS:
            with self.subTest(identifier=key):
                run = valid_steady()
                del run["identifiers"][key]
                self.assertEqual(self.status(run), "incomplete")
        self.assertEqual(self.status(valid_steady()), "pass")

    def test_unknown_identifiers_cannot_pass(self):
        for value in (None, "", "unknown", "TBD", "<iphone>"):
            run = valid_steady()
            run["identifiers"]["iphone_model"] = value
            self.assertEqual(self.status(run), "incomplete")

    def test_short_or_unverified_continuous_run_is_incomplete(self):
        for duration in (None, 1799, False, float("inf"), float("nan"), 10 ** 1000):
            run = valid_steady()
            run["steady_state"]["duration_seconds"] = duration
            self.assertEqual(self.status(run), "incomplete")
        run = valid_steady()
        run["steady_state"]["continuous_input"] = False
        self.assertEqual(self.status(run), "incomplete")

    def test_valid_recovery_uses_later_route_or_permission_time(self):
        self.assertEqual(self.status(valid_recovery()), "pass")
        run = valid_recovery()
        for trial in run["recovery"]["trials"][:10]:
            trial["resume_allowed_at_s"] = 2
            trial["audio_resumed_at_s"] = 12
        self.assertEqual(self.status(run), "pass")

    def test_slow_or_missing_resumption_fails_after_observation(self):
        for resumed in (13.001, None):
            run = valid_recovery()
            run["recovery"]["trials"][0]["audio_resumed_at_s"] = resumed
            self.assertEqual(self.status(run), "fail")

    def test_short_observation_does_not_invent_a_timeout(self):
        run = valid_recovery()
        trial = run["recovery"]["trials"][0]
        trial["audio_resumed_at_s"] = None
        trial["observation_finished_at_s"] = 11.5
        self.assertEqual(self.status(run), "incomplete")

    def test_missing_resumption_measurement_is_not_inferred_as_timeout(self):
        run = valid_recovery()
        del run["recovery"]["trials"][0]["audio_resumed_at_s"]
        self.assertEqual(self.status(run), "incomplete")

    def test_unexpected_interruption_is_not_excused(self):
        run = valid_recovery()
        run["recovery"]["trials"][0]["expected_interruption"] = False
        self.assertEqual(self.status(run), "fail")
        del run["recovery"]["trials"][0]["expected_interruption"]
        self.assertEqual(self.status(run), "incomplete")

    def test_user_pause_and_denied_resume_are_respected(self):
        for index in (10, 11):
            run = valid_recovery()
            run["recovery"]["trials"][index]["audio_resumed_at_s"] = 1
            self.assertEqual(self.status(run), "fail")

    def test_negative_trial_needs_actual_paused_observation(self):
        run = valid_recovery()
        del run["recovery"]["trials"][10]["stayed_paused"]
        self.assertEqual(self.status(run), "incomplete")

    def test_ten_successes_and_both_negative_cases_are_required(self):
        for removed in (0, 10, 11):
            run = valid_recovery()
            del run["recovery"]["trials"][removed]
            self.assertEqual(self.status(run), "incomplete")

    def test_one_confounded_negative_case_does_not_cover_both(self):
        run = valid_recovery()
        run["recovery"]["trials"] = run["recovery"]["trials"][:11]
        run["recovery"]["trials"][10]["resume_allowed"] = False
        self.assertEqual(self.status(run), "incomplete")

    def test_early_resumption_is_a_failure(self):
        run = valid_recovery()
        run["recovery"]["trials"][0]["audio_resumed_at_s"] = 9
        self.assertEqual(self.status(run), "fail")

    def test_combined_requires_both_scopes(self):
        run = valid_steady()
        run["scope"] = "combined"
        self.assertEqual(self.status(run), "incomplete")
        run["recovery"] = valid_recovery()["recovery"]
        self.assertEqual(self.status(run), "pass")

    def test_malformed_structure_is_incomplete_not_exception(self):
        for value in (None, [], {}, {"status": "recorded", "scope": "wrong"},
                      {"status": "recorded", "scope": []}):
            self.assertEqual(self.status(value), "incomplete")

    def test_assessment_does_not_mutate_record(self):
        run = valid_recovery()
        before = copy.deepcopy(run)
        ASSESSOR.assess(run)
        self.assertEqual(run, before)

    def test_cli_exit_codes_json_and_no_implicit_file_writes(self):
        failure = valid_steady()
        failure["steady_state"]["counters"]["short_fills"]["count"] = 1
        cases = ((valid_steady(), 0, "pass"), (failure, 1, "fail"),
                 ({}, 2, "incomplete"), ({"status": "not_run"}, 2, "not_run"))
        for run, code, status in cases:
            with self.subTest(status=status), \
                    mock.patch.object(Path, "read_text", return_value=json.dumps(run)), \
                    mock.patch.object(Path, "write_text") as writer, \
                    contextlib.redirect_stdout(io.StringIO()) as output:
                self.assertEqual(ASSESSOR.main(["unused.json", "--format", "json"]), code)
                self.assertEqual(json.loads(output.getvalue())["status"], status)
                writer.assert_not_called()

    def test_cli_output_requires_explicit_option(self):
        with mock.patch.object(Path, "read_text", return_value=json.dumps(valid_steady())), \
                mock.patch.object(Path, "write_text") as writer, \
                contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(ASSESSOR.main(["unused.json", "--output", "result.json"]), 0)
            self.assertIn("PASS", output.getvalue())
            writer.assert_called_once()
            self.assertEqual(json.loads(writer.call_args.args[0])["status"], "pass")


if __name__ == "__main__":
    unittest.main()
