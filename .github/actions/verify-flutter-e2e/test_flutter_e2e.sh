#!/usr/bin/env bash
# shellcheck disable=SC2317,SC2329 # helpers are called by name from the test loop
# Unit tests for the helpers of flutter_e2e.sh (sourced with FLUTTER_E2E_SH_LIB=1, so main does not
# run). The emulator flow is proved on a hosted runner. Run: bash .github/actions/verify-flutter-e2e/test_flutter_e2e.sh
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=flutter_e2e.sh
FLUTTER_E2E_SH_LIB=1 source "${here}/flutter_e2e.sh"
fails=0
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
eq() { # name expected actual
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: expected '$2' got '$3'"; fails=$((fails + 1)); fi
}
test_defines_with_mocks() {
  eq "${FUNCNAME[0]}" $'--dart-define=VERIFY_E2E=true\n--dart-define=E2E_API_URL=http://localhost:3901' "$(flutter_e2e_defines true)"
}
test_defines_without_mocks() { eq "${FUNCNAME[0]}" "--dart-define=VERIFY_E2E=true" "$(flutter_e2e_defines false)"; }
test_failed_names() {
  printf '%s\n' \
    '00:05 +0: loading /w/integration_test/app_test.dart' \
    '00:41 +1: /w/integration_test/app_test.dart: app starts on the first step' \
    '00:52 +1 -1: /w/integration_test/app_test.dart: user signs in [E]' \
    '  Expected: at least one matching candidate' \
    '01:03 +2 -1: /w/integration_test/app_test.dart: signed-in user sees their items' \
    '01:10 +2 -2: /w/integration_test/partner_test.dart: partner reachable [E]' \
    '01:10 +2 -2: Some tests failed.' > "${tmp}/log"
  eq "${FUNCNAME[0]}" $'app_test.dart: user signs in\npartner_test.dart: partner reachable' "$(flutter_e2e_failed "${tmp}/log")"
}
test_failed_none() { printf '00:30 +3: All tests passed!\n' > "${tmp}/ok"; eq "${FUNCNAME[0]}" "" "$(flutter_e2e_failed "${tmp}/ok")"; }
test_verdict_pass() { eq "${FUNCNAME[0]}" pass "$(flutter_e2e_verdict 0 - 9)"; }
test_verdict_flaky() { eq "${FUNCNAME[0]}" flaky "$(flutter_e2e_verdict 1 0 9)"; }
test_verdict_network_check() { eq "${FUNCNAME[0]}" network-check "$(flutter_e2e_verdict 1 1 3)"; }
test_verdict_fail() { eq "${FUNCNAME[0]}" fail "$(flutter_e2e_verdict 1 1 0)"; }
for t in $(declare -F | awk '$3 ~ /^test_/ {print $3}'); do "$t"; done
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "${fails} FAILED"; exit 1; fi
