#!/usr/bin/env python3
"""Verification Contract checker: which required tests/scripts does a repo lack?

CLI: python3 contract.py --stack S --dir D --deadline YYYY-MM-DD
Prints {"mode": "warn"|"enforce", "missing": [ids], "levels": {id: "warning"|"error"}} (stdlib only).

Per-item deadlines: an item in SINCE becomes an error at the later of the repo deadline and its
since date + GRACE_DAYS; every other item at the repo deadline. No valid repo deadline: warnings forever.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from datetime import date, datetime, timedelta

LOCKFILES = {"yarn.lock", "package-lock.json", "pnpm-lock.yaml", "pubspec.lock",
             "packages.lock.json", "Directory.Packages.props"}
NODE = ("web", "react-native", "strapi")
SCRIPTS = {
    "web": ["lint", "typecheck", "test", "build", "test:e2e"],
    "react-native": ["lint", "typecheck", "test"],
    "strapi": ["build"],
}
SKIP_DIRS = {".git", "node_modules", "bin", "obj", "build", ".dart_tool", ".yarn", "Pods"}
STACKS = set(NODE) | {"dotnet-service", "dotnet-library", "flutter", "infra"}
# Items added after v1, with the day they shipped (spec 4.3). Their deadline is never before since + GRACE_DAYS.
SINCE = {"playwright": "2026-11-03", "maestro-journeys": "2026-11-03", "e2e-mocks": "2026-11-03"}
GRACE_DAYS = 56
PLAYWRIGHT_CONFIGS = {"playwright.config." + e for e in ("ts", "js", "mjs", "cjs")}


def missing_items(stack, files, package_json, csproj_count, has_health_mapping):
    if stack not in STACKS:
        raise ValueError("unknown stack: %s" % stack)
    if stack == "infra":  # infra repos have no contract items
        return []
    pkg = package_json or {}
    names = {f.rsplit("/", 1)[-1] for f in files}
    dotnet = stack.startswith("dotnet")
    out = []

    def need(ok, item):
        if not ok:
            out.append(item)

    need(names & LOCKFILES, "lockfile")  # for dotnet, CPM props is in LOCKFILES
    if stack in NODE:
        pin = ".nvmrc" in names or "node" in pkg.get("engines", {}) or "packageManager" in pkg
    elif dotnet:
        pin = "global.json" in names
    else:  # flutter: pubspec.lock pins the resolved toolchain-compatible deps
        pin = ".fvmrc" in names or "pubspec.lock" in names
    need(pin, "toolchain-pin")

    cpm = "Directory.Packages.props" in names
    tests = any(f.endswith(".csproj") and "Test" in f for f in files)
    if stack == "dotnet-service":
        if csproj_count > 1:
            need(cpm, "cpm")
        need(has_health_mapping, "health-endpoint")
        need(tests, "test-project")
        need("Dockerfile" in names, "dockerfile")
    elif stack == "dotnet-library":
        need(cpm, "cpm")
        need(tests, "test-project")

    scripts = pkg.get("scripts", {})
    for s in SCRIPTS.get(stack, []):
        need(s in scripts, "script:" + s)
    if stack == "web":
        need("@playwright/test" in pkg.get("devDependencies", {}) and files & PLAYWRIGHT_CONFIGS, "playwright")
    if stack == "react-native":
        need("@rnx-kit/align-deps" in pkg.get("devDependencies", {}), "align-deps")
        need(".maestro/smoke.yaml" in files, "maestro-smoke")
        flows = [f for f in files if re.fullmatch(r"\.maestro/[^/]+\.ya?ml", f) and f not in (".maestro/config.yaml", ".maestro/config.yml")]
        need(len(flows) >= 3, "maestro-journeys")
        need("e2e/mocks.json" in files, "e2e-mocks")
    elif stack == "flutter":
        need(any(f.startswith("test/") and f.endswith("_test.dart") for f in files), "widget-test")
    return out


def mode_for(deadline, today):
    try:
        return "enforce" if today >= datetime.strptime(deadline, "%Y-%m-%d").date() else "warn"
    except (ValueError, TypeError):
        print("::warning title=[VERIFY] Contract::contract-deadline missing or invalid; warn mode",
              file=sys.stderr)
        return "warn"


def _parse(day):
    try:
        return datetime.strptime(day, "%Y-%m-%d").date()
    except (ValueError, TypeError):
        return None


def item_deadline(item, repo_deadline):
    """-> the date `item` becomes an error, or None (never: no valid repo deadline)."""
    repo = _parse(repo_deadline)
    if repo is None or item not in SINCE:
        return repo
    return max(repo, _parse(SINCE[item]) + timedelta(days=GRACE_DAYS))


def item_levels(missing, repo_deadline, today):
    out = {}
    for item in missing:
        due = item_deadline(item, repo_deadline)
        out[item] = "error" if due is not None and today >= due else "warning"
    return out


def scan(root):
    files, health, csprojs = set(), False, 0
    for dp, dns, fns in os.walk(root):
        dns[:] = [d for d in dns if d not in SKIP_DIRS]
        for fn in fns:
            rel = os.path.relpath(os.path.join(dp, fn), root).replace(os.sep, "/")
            files.add(rel)
            csprojs += fn.endswith(".csproj")
            if fn.endswith(".cs") and not health:
                with open(os.path.join(dp, fn), encoding="utf-8", errors="ignore") as f:
                    txt = f.read()
                health = "MapHealthChecks(" in txt or '"/health"' in txt
    return files, csprojs, health


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stack", required=True)
    ap.add_argument("--dir", default=".")
    ap.add_argument("--deadline", default="")
    a = ap.parse_args()
    files, csprojs, health = scan(a.dir)
    pkg = None
    if "package.json" in files:
        with open(os.path.join(a.dir, "package.json"), encoding="utf-8") as f:
            pkg = json.load(f)
    missing = missing_items(a.stack, files, pkg, csprojs, health)
    print(json.dumps({"mode": mode_for(a.deadline, date.today()), "missing": missing,
                      "levels": item_levels(missing, a.deadline, date.today())}))


if __name__ == "__main__":
    main()
