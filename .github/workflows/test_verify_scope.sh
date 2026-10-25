#!/usr/bin/env bash
# Truth table for the scope rules in verify-scope.sh. verify.yml's `plan` job `if:`
# duplicates verify_full; keep them in sync. Run: bash .github/workflows/test_verify_scope.sh
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=verify-scope.sh
source "${here}/verify-scope.sh"
fails=0
eq() { # name expected actual
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: expected '$2' got '$3'"; fails=$((fails + 1)); fi
}
BOT='s9-deps-bot[bot]'
test_scope_main_human_full() { eq "${FUNCNAME[0]}" true "$(verify_full pull_request main main alice "$BOT")"; }
test_scope_develop_human_skipped() { eq "${FUNCNAME[0]}" false "$(verify_full pull_request develop main alice "$BOT")"; }
test_scope_bot_author_full() { eq "${FUNCNAME[0]}" true "$(verify_full pull_request develop main "$BOT" "$BOT")"; }
test_scope_dispatch_full() { eq "${FUNCNAME[0]}" true "$(verify_full workflow_dispatch '' main '' "$BOT")"; }
test_scope_nondefault_main_name() { eq "${FUNCNAME[0]}" true "$(verify_full pull_request releases/r8.0 releases/r8.0 alice "$BOT")"; }
test_known_failing_before_deadline() { eq "${FUNCNAME[0]}" "lint test" "$(known_failing_effective "lint test" 2026-12-20 2026-12-19)"; }
test_known_failing_on_deadline() { eq "${FUNCNAME[0]}" "" "$(known_failing_effective "lint test" 2026-12-20 2026-12-20)"; }
test_known_failing_after_deadline() { eq "${FUNCNAME[0]}" "" "$(known_failing_effective "lint" 2026-12-20 2027-01-01)"; }
test_known_failing_no_deadline() { eq "${FUNCNAME[0]}" "lint" "$(known_failing_effective "lint" "" 2027-01-01)"; }
test_contract_mode() {
  eq "${FUNCNAME[0]}_warn" warn "$(contract_mode 2026-12-20 2026-12-19)"
  eq "${FUNCNAME[0]}_enforce" enforce "$(contract_mode 2026-12-20 2026-12-20)"
  eq "${FUNCNAME[0]}_none" warn "$(contract_mode '' 2027-01-01)"
}
for t in $(declare -F | awk '$3 ~ /^test_/ {print $3}'); do "$t"; done
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "${fails} FAILED"; exit 1; fi
