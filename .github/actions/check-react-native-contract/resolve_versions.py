#!/usr/bin/env python3
"""Resolves the react/react-native version contract for a React Native repo.

WHY THIS EXISTS
---------------
react-native's package.json advertises a LOOSE peer range (e.g. ^19.2.3) while
its own bundled renderer hard-codes an EXACT version and throws at runtime:

    var isomorphicReactPackageVersion = React.version;
    if ("19.2.3" !== isomorphicReactPackageVersion)
      throw Error('Incompatible React versions: ...');

So `react: 19.2.8` + `react-native: 0.85.1` installs cleanly, type-checks
cleanly, bundles cleanly, and passes a react-test-renderer unit test -- then
throws the first time anything calls one of the six APIs that RendererImplementation
binds to the Paper renderer unconditionally (findNodeHandle, unstable_batchedUpdates,
sendAccessibilityEvent, findHostInstance_DEPRECATED,
unmountComponentAtNodeAndRemoveContainer, isChildPublicInstance) -- even on the
New Architecture, where rendering itself correctly uses Fabric.

This script determines what react-native actually demands, and what the repo
actually pins, so a CI gate can compare them BEFORE the merge.

RESOLUTION ORDER (most authoritative first)
-------------------------------------------
Versions come from the lockfile when present, because the lockfile -- not
package.json -- decides what gets installed. package.json is the fallback.

The expected react version comes from the shipped renderer bundle:
  1. Paper renderer's hard assertion   -> the literal that actually throws.
  2. Fabric renderer's reconcilerVersion -> fallback for RN >= 0.86, which
     dropped the Paper renderer entirely and therefore has no assertion.
Never falls back to "no opinion": a gate that silently passes when it cannot
determine the contract manufactures confidence, which is worse than no gate.

Usage:
    resolve_versions.py --dir <repo-root> [--offline]

Prints a single JSON object to stdout. Exit code is always 0 unless the repo
could not be inspected at all -- the CALLER decides what constitutes failure.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request

UNPKG = "https://unpkg.com/react-native@{ver}/Libraries/Renderer/implementations/{impl}.js"

# The literal comparison the Paper renderer performs against React.version.
PAPER_ASSERTION = re.compile(r'"(\d+\.\d+\.\d+)"\s*!==\s*isomorphicReactPackageVersion')
# Fabric keeps the reconciler's React version in its devtools-injection object.
FABRIC_RECONCILER = re.compile(r'reconcilerVersion:\s*"(\d+\.\d+\.\d+)"')


def read_json(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return None


def versions_from_yarn_lock(path, name):
    """Every resolved version of `name` in a yarn.lock v1 file.

    The same package can legitimately appear in several blocks at different
    versions (a nested copy plus a top-level one), and ANY vulnerable/mismatched
    occurrence matters -- so all of them are collected, not just the first.
    """
    try:
        with open(path, encoding="utf-8") as fh:
            content = fh.read()
    except OSError:
        return []
    found = []
    for block in re.split(r"\n(?=\S)", content):
        lines = block.split("\n")
        if not lines or not lines[0].rstrip().endswith(":"):
            continue
        header = lines[0].rstrip().rstrip(":")
        for spec in (s.strip().strip('"') for s in header.split(",")):
            if "@" not in spec:
                continue
            if spec.rsplit("@", 1)[0] == name:
                for line in lines[1:]:
                    m = re.match(r'^\s+version[:\s]+"?([^"\s]+)"?', line)
                    if m:
                        found.append(m.group(1))
                break
    return sorted(set(found))


def versions_from_npm_lock(path, name):
    """Every resolved version of `name` in a package-lock.json (v1, v2 or v3)."""
    data = read_json(path)
    if not data:
        return []
    found = set()
    # v2/v3: flat "packages" map keyed by install path.
    for pkg_path, meta in (data.get("packages") or {}).items():
        if not isinstance(meta, dict):
            continue
        if pkg_path.endswith("node_modules/" + name) and meta.get("version"):
            found.add(meta["version"])
    # v1: nested "dependencies" tree.

    def walk(node):
        for dep_name, meta in (node.get("dependencies") or {}).items():
            if not isinstance(meta, dict):
                continue
            if dep_name == name and meta.get("version"):
                found.add(meta["version"])
            walk(meta)

    walk(data)
    return sorted(found)


def resolve_installed(root, name, declared):
    """Resolved version(s) of `name`, preferring the lockfile over package.json."""
    for lockfile, parser in (
        ("yarn.lock", versions_from_yarn_lock),
        ("package-lock.json", versions_from_npm_lock),
    ):
        path = os.path.join(root, lockfile)
        if os.path.exists(path):
            found = parser(path, name)
            if found:
                return found, lockfile
    # No lockfile (or the package is absent from it): fall back to the manifest.
    # An exact pin is usable as-is; a range is not, and is reported verbatim so
    # the caller can decide rather than guessing.
    if declared and re.fullmatch(r"\d+\.\d+\.\d+", declared.strip()):
        return [declared.strip()], "package.json"
    return ([declared] if declared else []), "package.json (unresolved range)"


def fetch_renderer_expectation(rn_version, root, allow_network=True):
    """The react version react-native `rn_version` demands.

    Reads node_modules first when available (free, and exactly what will run),
    otherwise fetches just the two renderer files from the CDN -- never the
    ~32MB tarball.
    """
    sources = []
    for impl, pattern, label in (
        ("ReactNativeRenderer-prod", PAPER_ASSERTION, "paper-assertion"),
        ("ReactFabric-prod", FABRIC_RECONCILER, "fabric-reconciler"),
    ):
        text = None
        local = os.path.join(
            root, "node_modules", "react-native",
            "Libraries", "Renderer", "implementations", impl + ".js",
        )
        if os.path.exists(local):
            try:
                with open(local, encoding="utf-8", errors="replace") as fh:
                    text = fh.read()
            except OSError:
                text = None
        if text is None and allow_network:
            try:
                req = urllib.request.Request(
                    UNPKG.format(ver=rn_version, impl=impl),
                    headers={"User-Agent": "simplify9-rn-contract-gate"},
                )
                with urllib.request.urlopen(req, timeout=60) as resp:
                    text = resp.read().decode("utf-8", errors="replace")
            except (urllib.error.URLError, urllib.error.HTTPError, OSError):
                continue
        m = pattern.search(text)
        if m:
            sources.append((label, m.group(1)))
            # The Paper assertion is the one that actually throws -- stop there.
            if label == "paper-assertion":
                break
    return sources


def npm_resolve_range(spec):
    """Concrete version npm would install for a range like ^0.68.1."""
    try:
        out = subprocess.run(
            ["npm", "view", "react-native@" + spec, "version", "--json"],
            capture_output=True, text=True, timeout=120, check=False,
        ).stdout.strip()
        if not out:
            return None
        val = json.loads(out)
        return val[-1] if isinstance(val, list) else val
    except (OSError, ValueError, subprocess.SubprocessError):
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=".", help="repo root containing package.json")
    ap.add_argument("--offline", action="store_true",
                    help="only read node_modules; never reach the network")
    args = ap.parse_args()

    root = os.path.abspath(args.dir)
    pkg = read_json(os.path.join(root, "package.json"))
    if pkg is None:
        print(json.dumps({"status": "NO_PACKAGE_JSON", "dir": root}))
        return 0

    deps = {**(pkg.get("dependencies") or {}), **(pkg.get("devDependencies") or {})}
    if "react-native" not in deps:
        print(json.dumps({"status": "NOT_A_REACT_NATIVE_REPO"}))
        return 0

    rn_versions, rn_src = resolve_installed(root, "react-native", deps.get("react-native"))
    react_versions, react_src = resolve_installed(root, "react", deps.get("react"))

    result = {
        "declared": {"react-native": deps.get("react-native"), "react": deps.get("react")},
        "resolved": {"react-native": rn_versions, "react": react_versions},
        "resolvedFrom": {"react-native": rn_src, "react": react_src},
    }

    if not rn_versions or not react_versions:
        result["status"] = "UNRESOLVABLE"
        result["reason"] = "could not determine installed react and/or react-native version"
        print(json.dumps(result))
        return 0

    # More than one copy of react in the tree is its own crash vector: the
    # renderer captures one instance's internals while components use another.
    if len(react_versions) > 1:
        result["status"] = "DUPLICATE_REACT"
        result["reason"] = "multiple react versions resolved: " + ", ".join(react_versions)
        print(json.dumps(result))
        return 0

    rn_version = rn_versions[0]
    if not re.fullmatch(r"\d+\.\d+\.\d+.*", rn_version) and not args.offline:
        resolved = npm_resolve_range(rn_version)
        if resolved:
            rn_version = resolved
            result["resolved"]["react-native"] = [resolved]

    react_version = react_versions[0]
    result["reactVersion"] = react_version
    result["reactNativeVersion"] = rn_version

    sources = fetch_renderer_expectation(rn_version, root, allow_network=not args.offline)
    if not sources:
        result["status"] = "CONTRACT_UNKNOWN"
        result["reason"] = (
            "could not read react-native@%s's bundled renderer to learn which react "
            "version it expects" % rn_version
        )
        print(json.dumps(result))
        return 0

    source_label, expected = sources[0]
    result["expectedReact"] = expected
    result["expectationSource"] = source_label
    result["status"] = "OK" if expected == react_version else "DRIFT"
    if result["status"] == "DRIFT":
        result["reason"] = (
            "react-native@%s's %s requires react %s, but this repo resolves react %s"
            % (rn_version, source_label, expected, react_version)
        )
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
