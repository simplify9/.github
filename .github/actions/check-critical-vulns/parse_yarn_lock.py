#!/usr/bin/env python3
"""Extracts every resolved version of a given package from a yarn.lock's
content (read on stdin), across all its version-spec blocks.

yarn.lock isn't JSON -- each block looks like:

    pbkdf2@^3.0.3:
      version "3.1.1"
      resolved "..."

or, for scoped/multi-spec packages:

    "@babel/core@^7.0.0", "@babel/core@^7.1.0":
      version "7.24.0"
      ...

The same package name can appear in multiple blocks at different resolved
versions (a real, confirmed case: the same package resolved differently
nested under another dependency vs. at the top level of the same lockfile),
so every block is checked -- callers must treat ANY still-vulnerable
occurrence as unresolved, not just the first one found.

Usage: python3 parse_yarn_lock.py <package-name> < path/to/yarn.lock
Prints one resolved version per line (possibly zero, possibly several).
"""
import sys
import re


def main() -> int:
    name = sys.argv[1]
    content = sys.stdin.read()
    blocks = re.split(r"\n(?=\S)", content)
    found = []
    for block in blocks:
        lines = block.split("\n")
        if not lines or not lines[0].rstrip().endswith(":"):
            continue
        header = lines[0].rstrip().rstrip(":")
        specs = [s.strip().strip('"') for s in header.split(",")]
        for spec in specs:
            if "@" not in spec:
                continue
            spec_name = spec.rsplit("@", 1)[0]
            if spec_name == name:
                for line in lines[1:]:
                    m = re.match(r'^\s+version\s+"([^"]+)"', line)
                    if m:
                        found.append(m.group(1))
                break
    print("\n".join(found))
    return 0


if __name__ == "__main__":
    sys.exit(main())
