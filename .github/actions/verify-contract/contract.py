#!/usr/bin/env python3
"""Verification Contract checker: which required tests/scripts does a repo lack?

CLI: python3 contract.py --stack S --dir D --deadline YYYY-MM-DD
Prints {"mode": "warn"|"enforce", "missing": [ids]} (stdlib only).
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import date, datetime

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
    if stack == "react-native":
        need("@rnx-kit/align-deps" in pkg.get("devDependencies", {}), "align-deps")
        need(".maestro/smoke.yaml" in files, "maestro-smoke")
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
    print(json.dumps({"mode": mode_for(a.deadline, date.today()),
                      "missing": missing_items(a.stack, files, pkg, csprojs, health)}))


if __name__ == "__main__":
    main()
