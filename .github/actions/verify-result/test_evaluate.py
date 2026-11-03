import unittest

import evaluate as e


def needs(**jobs):
    """job=result or job=(result, failed-output)."""
    out = {"plan": {"result": "success", "outputs": {}}}
    for job, v in jobs.items():
        result, failed = v if isinstance(v, tuple) else (v, "")
        out[job.replace("_", "-")] = {"result": result, "outputs": {"failed": failed} if failed else {}}
    return out


class Verdict(unittest.TestCase):
    def test_all_green(self):
        status, line, report = e.evaluate(needs(flutter="success", flutter_e2e="success"), True, "main", "")
        self.assertEqual((status, line), ("success", "Verification passed."))

    def test_crashed_tolerated_job_is_warned(self):
        # The runner died mid-step (no collect output) while e2e is still tolerated for this repo.
        status, line, report = e.evaluate(needs(flutter_e2e="failure"), True, "main", "e2e network")
        self.assertEqual(status, "success")
        self.assertIn("e2e", report["warned"])
        self.assertEqual(report["lost_jobs"], ["flutter-e2e"])
        self.assertIn("flutter-e2e", line)

    def test_cancelled_tolerated_job_is_warned(self):
        status, _, report = e.evaluate(needs(maestro="cancelled"), True, "main", "maestro")
        self.assertEqual(status, "success")
        self.assertIn("maestro", report["warned"])

    def test_crashed_job_not_tolerated_fails(self):
        status, line, _ = e.evaluate(needs(flutter_e2e="failure"), True, "main", "network")
        self.assertEqual(status, "failure")
        self.assertIn("flutter-e2e failure", line)

    def test_job_failed_by_an_enforced_step_still_fails(self):
        # e2e tolerated, but the job's own collect step recorded `network` as failed: not a crash.
        status, _, report = e.evaluate(needs(flutter_e2e=("failure", "network")), True, "main", "e2e")
        self.assertEqual(status, "failure")
        self.assertIn("network", report["failed"])

    def test_other_jobs_never_tolerated(self):
        status, _, _ = e.evaluate(needs(node="failure"), True, "main", "e2e maestro")
        self.assertEqual(status, "failure")

    def test_plan_must_succeed_in_full_scope(self):
        n = needs()
        n["plan"]["result"] = "skipped"
        status, line, _ = e.evaluate(n, True, "main", "")
        self.assertEqual(status, "failure")
        self.assertIn("plan skipped (expected success)", line)

    def test_human_develop_passes(self):
        n = {"plan": {"result": "skipped", "outputs": {}}}
        status, line, report = e.evaluate(n, False, "develop", "")
        self.assertEqual(status, "success")
        self.assertTrue(line.startswith("Human PR into develop"))
        self.assertEqual(report["scope"], "skipped-human-develop")


if __name__ == "__main__":
    unittest.main()
