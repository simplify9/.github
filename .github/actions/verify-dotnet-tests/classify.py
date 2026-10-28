#!/usr/bin/env python3
"""Sort .NET projects by what they reference, for verify's test steps and contract (stdlib only).

A test project (Microsoft.NET.Test.Sdk, <IsTestProject>true or an MSTest.Sdk project) is:
  refused      a config file next to it holds a real-environment connection string: never run
  integration  it references Testcontainers: the hosted `integration` job runs it
  unit         everything else: the `test` step runs it, as before

CLI: classify.py --dir D [--kind unit|integration|refused] [--warn]
  --kind  absolute csproj paths of that kind, one per line (else JSON for every project)
  --warn  one ::warning per refused project on stderr, naming file:line (never the value)
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "verify-secret-scan"))
import scan  # noqa: E402

SKIP_DIRS = {"bin", "obj", ".git", "node_modules"}
CONFIG_EXT = (".json", ".config", ".runsettings", ".env", ".yml", ".yaml")
# Include anywhere among the attributes, single or double quotes (Update= modifies, never adds).
PACKAGE_REF = re.compile(r"""<PackageReference\b[^>]*?\bInclude\s*=\s*["']([^"']+)["']""", re.I)
# MSBuild imports these into every project below them: what they reference counts for the project.
INHERITED = ("Directory.Build.props", "Directory.Build.targets")
# Outside-system clients: a library using one needs Testcontainers tests (contract item integration-tests).
CLIENTS = {"stackexchange.redis", "microsoft.data.sqlclient", "system.data.sqlclient", "mongodb.driver",
           "rabbitmq.client", "confluent.kafka"}
CLIENT_PREFIXES = ("npgsql", "masstransit", "azure.storage.")


def references(text):
    return set(PACKAGE_REF.findall(text))


def project_info(text):
    refs = references(text)
    low = {r.lower() for r in refs}
    test = ("microsoft.net.test.sdk" in low or re.search(r"<IsTestProject>\s*true\s*</IsTestProject>", text, re.I)
            or re.search(r'Sdk="MSTest\.Sdk', text, re.I))
    return {
        "test": bool(test),
        "testcontainers": any(r == "testcontainers" or r.startswith("testcontainers.") for r in low),
        "mvc_testing": "microsoft.aspnetcore.mvc.testing" in low,
        "clients": sorted(r for r in refs if r.lower() in CLIENTS or r.lower().startswith(CLIENT_PREFIXES)),
    }


def _walk(top):
    for dp, dns, fns in os.walk(top):
        dns[:] = sorted(d for d in dns if d not in SKIP_DIRS)
        for fn in sorted(fns):
            yield dp, fn


def refusals(project_dir):
    """Config files under project_dir with a non-local connection string, as "<relpath>:<line> connection-string"."""
    out = []
    for dp, fn in _walk(project_dir):
        if fn.endswith(CONFIG_EXT):
            path = os.path.join(dp, fn)
            for f in scan.scan_path(path, (set(), set()), False):
                if f.kind == "connection-string":
                    out.append("%s:%d connection-string" % (os.path.relpath(path, project_dir).replace(os.sep, "/"), f.line))
    return out


def _read(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


def inherited_text(project_dir, root):
    """Every Directory.Build.props/.targets from project_dir up to root. MSBuild imports only the nearest
    unless it chains upward; folding all of them in can only add references, never hide one."""
    texts, d, top = [], os.path.realpath(project_dir), os.path.realpath(root)
    while True:
        texts += [_read(os.path.join(d, n)) for n in INHERITED if os.path.isfile(os.path.join(d, n))]
        if d == top or os.path.dirname(d) == d:
            return "\n".join(texts)
        d = os.path.dirname(d)


def classify(root):
    projects = []
    for dp, fn in _walk(root):
        if not fn.endswith(".csproj"):
            continue
        path = os.path.join(dp, fn)
        info = project_info(_read(path) + "\n" + inherited_text(dp, root))
        info["path"] = os.path.relpath(path, root).replace(os.sep, "/")
        info["refused"] = refusals(dp) if info["test"] else []
        info["kind"] = None if not info["test"] else (
            "refused" if info["refused"] else "integration" if info["testcontainers"] else "unit")
        projects.append(info)
    return projects


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--dir", default=".")
    ap.add_argument("--kind", choices=("unit", "integration", "refused"))
    ap.add_argument("--warn", action="store_true")
    a = ap.parse_args(argv)
    projects = classify(a.dir)
    if a.warn:
        for p in projects:
            if p["kind"] == "refused":
                print("::warning title=[VERIFY] tests::%s is not run: its config holds a real-environment connection "
                      "string (%s). Use Testcontainers or local values" % (p["path"], "; ".join(p["refused"])),
                      file=sys.stderr)
    if a.kind:
        for p in projects:
            if p["kind"] == a.kind:
                print(os.path.realpath(os.path.join(a.dir, p["path"])))
    else:
        print(json.dumps(projects, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
