#!/usr/bin/env python3
"""Pre-merge gate: will every org caller of a reusable workflow still start?

A called workflow can only downgrade the GITHUB_TOKEN it inherits. If any job in
it requests a scope above what the caller job grants, GitHub rejects the whole
run before a single job starts ("The nested job 'X' is requesting 'Y', but is
only allowed 'Z'"). So widening a reusable workflow's `permissions:` is a
breaking change for every caller that pins an explicit permissions block.

This script reads what each job of the LOCAL workflow file requests, finds every
caller across the org (code search on default branches + a direct scan of the
listed branches, since push-triggered callers run the file on the pushed
branch), computes each caller job's effective ceiling, and exits 1 if any caller
would fail to start.

Usage:
  scripts/fleet/audit_caller_permissions.py .github/workflows/vite-cloudflare-worker.yml
  scripts/fleet/audit_caller_permissions.py <workflow> --branches main,develop,staging
  # "what if every caller also granted packages: read":
  scripts/fleet/audit_caller_permissions.py <workflow> --assume-grant packages=read

Requires: gh (authenticated with repo read on the org), PyYAML.
"""
import argparse
import base64
import json
import pathlib
import subprocess
import sys

import yaml

RANK = {"none": 0, "read": 1, "write": 2}
SCOPES = ["actions", "attestations", "checks", "contents", "deployments",
          "discussions", "id-token", "issues", "models", "packages", "pages",
          "pull-requests", "repository-projects", "security-events", "statuses"]


def gh(*args):
    r = subprocess.run(["gh", *args], capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None


def expand(perm, default):
    """Normalise a `permissions:` value to {scope: level}."""
    if perm is None:
        return dict(default)
    if perm == "read-all":
        return {s: "read" for s in SCOPES}
    if perm == "write-all":
        return {s: "write" for s in SCOPES}
    return {s: str((perm or {}).get(s, "none")) for s in SCOPES}


def requested(workflow):
    """{job: {scope: level}} for jobs that request an explicit permission set.
    Jobs with no job- or workflow-level block inherit the caller as-is and can't fail."""
    doc = yaml.safe_load(pathlib.Path(workflow).read_text())
    top = doc.get("permissions")
    out = {}
    for name, job in doc["jobs"].items():
        perm = job.get("permissions", top)
        if perm is not None:
            out[name] = {s: lvl for s, lvl in expand(perm, {}).items() if lvl != "none"}
    return out


def org_default(org):
    lvl = json.loads(gh("api", f"/orgs/{org}/actions/permissions/workflow") or "{}").get(
        "default_workflow_permissions", "read")
    # restricted default = contents/packages read; permissive = everything write
    return {s: "write" for s in SCOPES} if lvl == "write" else \
        {s: ("read" if s in ("contents", "packages", "metadata") else "none") for s in SCOPES}


def callers(org, wf_name, branches):
    hits = gh("search", "code", wf_name, "--owner", org, "--limit", "200",
              "--json", "repository", "--jq", ".[].repository.nameWithOwner") or ""
    repos = sorted({r for r in hits.split() if r != f"{org}/.github"})
    for repo in repos:
        default = (gh("api", f"/repos/{repo}", "--jq", ".default_branch") or "main").strip()
        for br in sorted({default, *branches}):
            listing = gh("api", f"/repos/{repo}/contents/.github/workflows?ref={br}", "--jq", ".[].path")
            for path in (listing or "").split():
                raw = gh("api", f"/repos/{repo}/contents/{path}?ref={br}", "--jq", ".content")
                body = base64.b64decode(raw).decode() if raw else ""
                if wf_name in body:
                    yield repo, br, path, yaml.safe_load(body)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("workflow", help="local path of the reusable workflow")
    ap.add_argument("--org", default="simplify9")
    ap.add_argument("--branches", default="main,develop,staging")
    ap.add_argument("--assume-grant", action="append", default=[], metavar="SCOPE=LEVEL",
                    help="pretend every caller also grants this (models a caller-side rollout)")
    a = ap.parse_args()

    wf_name = pathlib.Path(a.workflow).name
    req = requested(a.workflow)
    grants = dict(g.split("=", 1) for g in a.assume_grant)
    default = org_default(a.org)
    print(f"{wf_name} requests: " + "; ".join(
        f"{j}: " + ", ".join(f"{s}={l}" for s, l in sorted(p.items())) for j, p in req.items()))
    if grants:
        print(f"assuming every caller also grants: {grants}")

    rows, failures = [], 0
    for repo, br, path, doc in callers(a.org, wf_name, a.branches.split(",")):
        for jname, job in (doc.get("jobs") or {}).items():
            if wf_name not in str(job.get("uses", "")):
                continue
            perm = job.get("permissions", doc.get("permissions"))
            ceil = expand(perm, default)
            for s, lvl in grants.items():
                if RANK[lvl] > RANK[ceil[s]]:
                    ceil[s] = lvl
            bad = [f"{j}:{s}={l}>{ceil[s]}" for j, p in req.items()
                   for s, l in p.items() if RANK[l] > RANK[ceil[s]]]
            failures += bool(bad)
            rows.append((repo.split("/")[1], br, jname, "FAIL " + ", ".join(bad) if bad else "ok"))

    w = max((len(r[0]) for r in rows), default=4)
    for r in sorted(rows):
        print(f"  {r[0]:<{w}}  {r[1]:<8} {r[2]:<12} {r[3]}")
    print(f"\n{len(rows)} caller jobs, {failures} would fail to start.")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
