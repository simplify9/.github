import sys
import unittest

import yaml

sys.dont_write_bytecode = True
sys.path.insert(0, __file__.rsplit("/", 1)[0])
from audit_caller_permissions import required_check_gaps  # noqa: E402


def caller(pr="{types: [opened, synchronize, reopened, edited]}", job_if=""):
    doc = yaml.safe_load(f"""
on:
  pull_request: {pr}
  workflow_dispatch:
jobs:
  verify:
    {f"if: {job_if}" if job_if else ""}
    uses: simplify9/.github/.github/workflows/verify.yml@main
""")
    return doc, doc["jobs"]["verify"]


class T(unittest.TestCase):
    def test_caller_that_always_runs_passes(self):
        self.assertEqual(required_check_gaps(*caller()), [])

    def test_job_if_fails(self):
        # .github #226: a description edit started a run whose verify job was skipped, and that
        # newest run without `verify / result` kept the PR BLOCKED although an older run passed.
        doc, job = caller(job_if="github.event.action != 'edited' || github.event.changes.base")
        self.assertEqual(len(required_check_gaps(doc, job)), 1)

    def test_paths_filter_fails(self):
        doc, job = caller(pr="{paths-ignore: ['**.md']}")
        self.assertEqual(len(required_check_gaps(doc, job)), 1)

    def test_bare_pull_request_trigger_passes(self):
        doc = yaml.safe_load("on: [pull_request]\njobs:\n  verify:\n    uses: x/verify.yml@main\n")
        self.assertEqual(required_check_gaps(doc, doc["jobs"]["verify"]), [])


if __name__ == "__main__":
    unittest.main()
