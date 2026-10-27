#!/usr/bin/env bash
# Unit tests for the pure helpers of emulator.sh; the boot itself is proved on a hosted runner.
# Run: bash .github/actions/verify-emulator/test_emulator.sh
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=emulator.sh
source "${here}/emulator.sh"
fails=0
eq() { # name expected actual
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: expected '$2' got '$3'"; fails=$((fails + 1)); fi
}
eq boot_first_try booted "$(emulator_boot_verdict 0 -)"
eq boot_retry retry "$(emulator_boot_verdict 1 -)"
eq boot_second_try booted "$(emulator_boot_verdict 1 0)"
eq boot_failed failed "$(emulator_boot_verdict 1 1)"
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "${fails} FAILED"; exit 1; fi
