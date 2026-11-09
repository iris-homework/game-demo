"""Exercise runner verdicts against real short-lived subprocess logs."""
from pathlib import Path
import os
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from run_core_qa import execute


class RunnerTests(unittest.TestCase):
    def run_process(self, code, timeout=5):
        with tempfile.TemporaryDirectory(prefix="midnight-runner-qa-") as temporary:
            return execute([sys.executable, "-c", code], Path(temporary) / "sample", os.environ.copy(), timeout)

    def test_both_existing_summary_formats_pass(self):
        for summary in ["COMBAT: 25 checks, 0 failures", "AUDIO checks=142 failures=0"]:
            with self.subTest(summary=summary):
                result = self.run_process("print(" + repr(summary) + ")")
                self.assertEqual(result["status"], "passed")
                self.assertGreater(result["checks"], 0)

    def test_exit_zero_without_summary_fails(self):
        self.assertEqual(self.run_process("print('unfinished')")["status"], "failed")

    def test_nonzero_exit_with_success_summary_fails(self):
        self.assertEqual(self.run_process("print('TEST: 2 checks, 0 failures'); raise SystemExit(1)")["status"], "failed")

    def test_script_error_with_exit_zero_fails(self):
        self.assertEqual(self.run_process("print('TEST: 2 checks, 0 failures'); print('SCRIPT ERROR: test')")["status"], "failed")

    def test_nonzero_failure_summary_is_not_hidden_by_success_marker(self):
        for summary in ["TEST: 2 checks, 1 failures", "TEST checks=2 failures=1"]:
            with self.subTest(summary=summary):
                self.assertEqual(self.run_process("print(" + repr(summary) + "); print('END checks=2 failures=0')")["status"], "failed")

    def test_timeout_fails(self):
        result = self.run_process("import time; time.sleep(10)", timeout=0.05)
        self.assertEqual(result["status"], "failed")
        self.assertTrue(result["timed_out"])


if __name__ == "__main__":
    unittest.main()
