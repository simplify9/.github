#!/usr/bin/env python3
"""Offline check: does every workflow-template grant what its reusable workflow requests?

A template's `permissions:` becomes the ceiling for the reusable workflow it
calls. If any job in that workflow requests more, a repo created from the
template fails to start on its first run. Run from the repo root; no network.

Usage:
  scripts/fleet/audit_template_permissions.py
"""
import pathlib
import re
import sys

import yaml

sys.dont_write_bytecode = True  # importing the sibling must not leave __pycache__ in the repo
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from audit_caller_permissions import RANK, SCOPES, expand, requested  # noqa: E402

# Templates are copied into new repos, which get the org default ('write' today);
# only an explicit block can under-grant, so treat "no block" as permissive.
PERMISSIVE = {s: "write" for s in SCOPES}


def main():
    failures = 0
    for tpl in sorted(pathlib.Path("workflow-templates").glob("*.yml")):
        doc = yaml.safe_load(tpl.read_text())
        for jname, job in (doc.get("jobs") or {}).items():
            m = re.search(r"\.github/workflows/([\w.-]+)@", str(job.get("uses", "")))
            if not m:
                continue
            ceil = expand(job.get("permissions", doc.get("permissions")), PERMISSIVE)
            bad = sorted({f"{j}:{s}={lvl}>{ceil[s]}"
                          for j, p in requested(f".github/workflows/{m.group(1)}").items()
                          for s, lvl in p.items() if RANK[lvl] > RANK[ceil[s]]})
            failures += bool(bad)
            print(f"  {tpl.name:34} {jname:14} -> {m.group(1):32} "
                  + ("FAIL " + ", ".join(bad) if bad else "ok"))
    print(f"\n{failures} template job(s) would fail to start.")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
