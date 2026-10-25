#!/usr/bin/env bash
# Run: bash .github/actions/verify-web-install/test_detect_pm.sh
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=detect_pm.sh
source "${here}/detect_pm.sh"
fails=0
eq() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: expected '$2' got '$3'"; fails=$((fails + 1)); fi; }
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
mk() { rm -rf "${t:?}"/*; for f in "$@"; do touch "${t}/${f}"; done; }
mk yarn.lock;                  eq yarn_classic yarn "$(detect_pm "$t")"
mk yarn.lock .yarnrc.yml;      eq yarn_berry yarn-berry "$(detect_pm "$t")"
mk package-lock.json;          eq npm npm "$(detect_pm "$t")"
mk pnpm-lock.yaml;             eq pnpm pnpm "$(detect_pm "$t")"
mk;                            out="$(detect_pm "$t")"; rc=$?
eq none_rc 1 "$rc"
case "$out" in "::error title=[VERIFY] Install::no lockfile"*) echo "PASS none_error";; *) echo "FAIL none_error: $out"; fails=$((fails + 1));; esac
[ "$fails" -eq 0 ] || exit 1
