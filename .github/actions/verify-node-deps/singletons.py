#!/usr/bin/env python3
"""Detect duplicate versions of singleton npm packages (react, next, ...) in node_modules."""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

PRUNE = {".bin", ".cache"}


def find_versions(root: Path, names: list[str]) -> dict[str, set[str]]:
    found: dict[str, set[str]] = {n: set() for n in names}
    # Symlinks are never followed (pnpm); its real packages live under
    # node_modules/.pnpm/<name>@<ver>/node_modules/<name>, which this walk visits.
    for dirpath, dirnames, filenames in os.walk(Path(root) / "node_modules"):
        dirnames[:] = [d for d in dirnames if d not in PRUNE]
        if "package.json" not in filenames:
            continue
        parts = Path(dirpath).parts
        for name in names:
            tail = tuple(name.split("/"))
            if len(parts) > len(tail) and parts[-len(tail):] == tail and parts[-len(tail) - 1] == "node_modules":
                try:
                    found[name].add(json.loads((Path(dirpath) / "package.json").read_text())["version"])
                except (OSError, ValueError, KeyError):
                    pass
    return found


def problems(found: dict[str, set[str]]) -> list[str]:
    return [f"{n} resolves to {', '.join(sorted(v))}" for n, v in sorted(found.items()) if len(v) > 1]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=".")
    ap.add_argument("--names", default="react,react-dom,react-native,next")
    a = ap.parse_args()
    root = Path(a.dir)
    if not (root / "node_modules").is_dir():
        if (root / ".pnp.cjs").exists():
            print("skipped (PnP): no node_modules to scan")
            return 0
        print(f"::error title=[VERIFY] Node deps::node_modules not found in {root} (install did not run?)")
        return 1
    found = find_versions(root, [n for n in a.names.split(",") if n])
    bad = problems(found)
    for p in bad:
        print(f"::error title=[VERIFY] Duplicate singleton::{p}")
    if not bad:
        print("no duplicate singletons: " + ", ".join(f"{n}={'/'.join(sorted(v)) or 'absent'}" for n, v in found.items()))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
