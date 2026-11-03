#!/usr/bin/env python3
"""The verdict of verify's `result` job from its needed jobs (stdlib only; tested by test_evaluate.py).

CLI (the verify-result action): reads NEEDS (toJSON(needs)), FULL, BASE and KNOWN_FAILING from the
environment, writes verify-report.json and `status`/`summary` to GITHUB_OUTPUT.
"""
from __future__ import annotations

import json
import os

# Emulator jobs and the step id that tolerates them. Such a job can die with its runner (out of memory
# on a 2-vCPU hosted runner) before its collect step runs: then no step recorded a failure, and while
# the step id is still tolerated (known-failing) the lost job is a warning, not a red check.
TOLERATED_JOBS = {"flutter-e2e": "e2e", "maestro": "maestro"}


def evaluate(needs, full, base, known_failing):
    """-> (status, summary line, report dict)."""
    def out(job, key):
        return (needs.get(job, {}).get("outputs") or {}).get(key, "") or ""

    known = set(known_failing.split())
    bad = sorted(j for j, n in needs.items() if n.get("result") in ("failure", "cancelled"))
    lost = [j for j in bad if TOLERATED_JOBS.get(j) in known and not out(j, "failed").split()]
    problems = ["%s %s" % (j, needs[j]["result"]) for j in bad if j not in lost]
    if full and needs.get("plan", {}).get("result") != "success" and "plan" not in bad:
        problems.append("plan %s (expected success)" % needs.get("plan", {}).get("result"))

    ladder = [j for j in needs if j not in ("plan", "contract")]
    report = {
        "scope": "full" if full else "skipped-human-develop",
        "failed": sorted(w for j in ladder for w in out(j, "failed").split()),
        "warned": sorted({w for j in ladder for w in out(j, "warned").split()} | {TOLERATED_JOBS[j] for j in lost}),
        "missing": out("contract", "missing").split(),
        "lost_jobs": lost,
    }
    if problems:
        return "failure", "Verification failed: " + "; ".join(problems), report
    if not full:
        return ("success", "Human PR into %s: full verification runs on PRs into the default branch and on "
                "Renovate PRs." % base, report)
    line = "Verification passed."
    if lost:
        line += " Tolerated until its deadline: %s (the job ended without reporting its steps, e.g. its runner was lost)." % \
            ", ".join("%s (%s)" % (j, TOLERATED_JOBS[j]) for j in lost)
    return "success", line, report


def main():
    status, line, report = evaluate(json.loads(os.environ["NEEDS"]), os.environ["FULL"] == "true",
                                    os.environ.get("BASE", ""), os.environ.get("KNOWN_FAILING", ""))
    with open("verify-report.json", "w") as f:
        json.dump(report, f, indent=2)
    with open(os.environ["GITHUB_OUTPUT"], "a") as f:
        f.write("status=%s\nsummary=%s\n" % (status, line))
    print(line)
    if status != "success":
        print("::error title=[VERIFY] Result::" + line.split(": ", 1)[1])
    for job in report["lost_jobs"]:
        print("::warning title=[VERIFY] Result::%s ended without reporting its steps (runner lost?); tolerated "
              "while %s is in known-failing" % (job, TOLERATED_JOBS[job]))


if __name__ == "__main__":
    main()
