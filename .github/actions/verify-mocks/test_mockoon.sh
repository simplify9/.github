#!/usr/bin/env bash
# Tests for mockoon.sh with the real pinned Mockoon CLI (needs npm and network to install it).
# Run: bash .github/actions/verify-mocks/test_mockoon.sh
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=mockoon.sh
source "${here}/mockoon.sh"
fails=0
RUNNER_TEMP="$(mktemp -d)"
export RUNNER_TEMP
trap '[ -z "${MOCKOON_PID:-}" ] || kill "${MOCKOON_PID}" 2>/dev/null; rm -rf "${RUNNER_TEMP}"' EXIT
eq() { # name expected actual
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: expected '$2' got '$3'"; fails=$((fails + 1)); fi
}
mockoon_install || { echo "FAIL install"; exit 1; }
test_mockoon_start_serves() {
  mockoon_start "${here}/testdata/mocks.json" >/dev/null
  eq "${FUNCNAME[0]}_rc" 0 $?
  eq "${FUNCNAME[0]}_body" '{"pong":true}' "$(curl -fsS "http://127.0.0.1:${MOCKOON_PORT}/ping")"
  kill "${MOCKOON_PID}" 2>/dev/null; wait "${MOCKOON_PID}" 2>/dev/null; MOCKOON_PID=""
}
test_mockoon_start_bad_file_fails_fast() {
  echo 'not json' > "${RUNNER_TEMP}/bad.json"
  local t0=${SECONDS}
  mockoon_start "${RUNNER_TEMP}/bad.json" >/dev/null 2>&1
  eq "${FUNCNAME[0]}_rc" 1 $?
  eq "${FUNCNAME[0]}_fast" 1 "$([ $((SECONDS - t0)) -lt 25 ] && echo 1 || echo 0)"
}
test_mockoon_start_serves
test_mockoon_start_bad_file_fails_fast
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "${fails} FAILED"; exit 1; fi
