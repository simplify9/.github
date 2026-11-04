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

    def test_lost_ios_runner_is_warned_while_tolerated(self):
        # The hosted macOS job can lose its runner like maestro; while `ios` is still a tolerated new
        # step (scope.sh NEW_STEPS) that is a warning, not a red check.
        status, _, report = e.evaluate(needs(react_native="success", ios="cancelled"), True, "main", "ios", "react-native")
        self.assertEqual(status, "success")
        self.assertIn("ios", report["warned"])

    def test_ios_failure_blocks_once_enforced(self):
        status, _, _ = e.evaluate(needs(react_native="success", ios=("failure", "ios")), True, "main", "", "react-native")
        self.assertEqual(status, "failure")

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
        self.assertIn("journey or integration test files", line)

    def test_human_develop_probe_failure_fails(self):
        # fail closed: a probe that could not list the PR files must not turn into a pass
        n = {"tests-probe": {"result": "failure", "outputs": {}}, "plan": {"result": "skipped", "outputs": {}}}
        status, line, _ = e.evaluate(n, False, "develop", "")
        self.assertEqual(status, "failure")
        self.assertIn("tests-probe failure", line)

    def test_probe_is_not_a_ladder_job(self):
        n = needs(node="success")
        n["tests-probe"] = {"result": "success", "outputs": {"tests_changed": "true", "failed": "x"}}
        status, _, report = e.evaluate(n, True, "develop", "")
        self.assertEqual(status, "success")
        self.assertEqual(report["failed"], [])


class LadderMustRun(unittest.TestCase):
    """A full run whose stack ladder was skipped tested nothing: red (#225 passed Renovate PRs that way)."""

    def test_225_shape_fails(self):
        # tests-probe skipped, plan ran, every ladder skipped behind the skipped probe
        n = needs(node="skipped", contract="skipped", dotnet="skipped")
        n["tests-probe"] = {"result": "skipped", "outputs": {}}
        status, line, _ = e.evaluate(n, True, "develop", "", "web")
        self.assertEqual(status, "failure")
        self.assertIn("node did not run (skipped)", line)

    def test_dotnet_skipped_fails(self):
        status, line, _ = e.evaluate(needs(dotnet="skipped", integration="success"), True, "develop", "", "dotnet-service")
        self.assertEqual(status, "failure")
        self.assertIn("dotnet did not run", line)

    def test_strapi_needs_both_jobs(self):
        status, line, _ = e.evaluate(needs(node="success", strapi="skipped"), True, "main", "", "strapi")
        self.assertEqual(status, "failure")
        self.assertIn("strapi did not run", line)
        status, _, _ = e.evaluate(needs(node="success", strapi="success"), True, "main", "", "strapi")
        self.assertEqual(status, "success")

    def test_absent_ladder_fails(self):
        status, line, _ = e.evaluate(needs(), True, "main", "", "flutter")
        self.assertIn("flutter did not run (absent)", line)

    def test_ran_ladder_passes(self):
        for stack, job in (("web", "node"), ("dotnet-library", "dotnet"), ("react-native", "react_native"), ("flutter", "flutter")):
            status, _, _ = e.evaluate(needs(**{job: "success"}), True, "develop", "", stack)
            self.assertEqual(status, "success", stack)

    def test_unknown_stack_needs_some_ladder(self):
        status, line, _ = e.evaluate(needs(contract="success"), True, "main", "", "")
        self.assertIn("no ladder job ran", line)
        status, _, _ = e.evaluate(needs(node="success"), True, "main", "", "")
        self.assertEqual(status, "success")

    def test_human_develop_skips_ladders_legitimately(self):
        n = {"tests-probe": {"result": "success", "outputs": {"tests_changed": "false"}}, "plan": {"result": "skipped", "outputs": {}},
             "node": {"result": "skipped", "outputs": {}}}
        status, _, _ = e.evaluate(n, False, "develop", "", "web")
        self.assertEqual(status, "success")


if __name__ == "__main__":
    unittest.main()
