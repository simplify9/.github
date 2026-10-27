#!/usr/bin/env python3
"""Name the failed and flaky Playwright tests of a test:e2e run (stdlib only).

CLI: python3 e2e_report.py LOG
Prints a Markdown summary on stdout (for $GITHUB_STEP_SUMMARY) and one annotation per failed or
flaky test on stderr. Reads the epilogue of Playwright's list/line/dot reporters; other reporters
print none, so nothing is named. Always exits 0.
"""
from __future__ import annotations

import re
import sys

ANSI = re.compile(r"\x1b\[[0-9;]*m")
HEADER = re.compile(r"^  (\d+) (failed|flaky|passed)\b")
# "    [chromium] › file:line › title ─────" (the trailing rule is padding)
TEST = re.compile(r"^    (\[.+?)\s*─*\s*$")


def parse(text):
    out = {"failed": [], "flaky": [], "passed": None}
    section = None
    for raw in text.splitlines():
        line = ANSI.sub("", raw)
        m = HEADER.match(line)
        if m:
            section = m.group(2)
            if section == "passed":
                out["passed"] = int(m.group(1))
                section = None
            continue
        m = TEST.match(line)
        if section and m:
            out[section].append(m.group(1))
        else:
            section = None
    return out


def markdown(result):
    lines = ["### Playwright"]
    if result["passed"] is None and not result["failed"] and not result["flaky"]:
        lines.append("No test summary found: use the `list` reporter in CI to have failed and flaky tests named here.")
        return "\n".join(lines) + "\n"
    if result["passed"] is not None:
        lines.append("%d passed" % result["passed"])
    for kind, label in (("failed", "Failed"), ("flaky", "Flaky (passed on retry)")):
        if result[kind]:
            lines.append("")
            lines.append("**%s**" % label)
            lines.extend("- `%s`" % t for t in result[kind])
    return "\n".join(lines) + "\n"


def main(argv):
    try:
        with open(argv[0], encoding="utf-8", errors="replace") as f:
            result = parse(f.read())
    except (IndexError, OSError) as e:
        print("::warning title=[VERIFY] e2e::no Playwright log to summarise (%s)" % e, file=sys.stderr)
        return 0
    sys.stdout.write(markdown(result))
    for t in result["failed"]:
        print("::error title=[VERIFY] e2e::failed: %s" % t.replace("%", "%25"), file=sys.stderr)
    for t in result["flaky"]:
        print("::warning title=[VERIFY] e2e::flaky (passed on retry): %s" % t.replace("%", "%25"), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
