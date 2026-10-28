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
    '01:10 +2 -2: Some tests failed.' \
    '' \
    'Failing tests:' \
    '  /w/integration_test/app_test.dart: user signs in' \
    '  /w/integration_test/partner_test.dart: partner reachable' > "${tmp}/log"
  eq "${FUNCNAME[0]}" $'app_test.dart: user signs in\npartner_test.dart: partner reachable' "$(flutter_e2e_failed "${tmp}/log")"
}
test_failed_single_file_real_output() {
  # A real one-file run: its "[E]" line carries no path, only the "Failing tests:" footer does.
  eq "${FUNCNAME[0]}" "app_test.dart: user signs in" "$(flutter_e2e_failed "${here}/testdata/single_file_failed.txt")"
}
test_result_line() {
  eq "${FUNCNAME[0]}" "00:34 +2 -1: Some tests failed." "$(flutter_e2e_result_line "${here}/testdata/single_file_failed.txt")"
  printf '00:05 +3: All tests passed!\n\nsome trailing output\n' > "${tmp}/ok2"
  eq "${FUNCNAME[0]}_pass" "00:05 +3: All tests passed!" "$(flutter_e2e_result_line "${tmp}/ok2")"
}
test_summary_names_flaky_from_first_run() {
  printf '00:05 +3: All tests passed!\n' > "${tmp}/last"
  local out
  out="$(flutter_e2e_summary flaky "${here}/testdata/single_file_failed.txt" "${tmp}/last" 2>&1)"
  eq "${FUNCNAME[0]}_section" 1 "$(grep -c 'Flaky' <<< "${out}")"
  eq "${FUNCNAME[0]}_name" 1 "$(grep -c -- '- app_test.dart: user signs in' <<< "${out}")"
  eq "${FUNCNAME[0]}_annotation" 1 "$(grep -c '::warning title=\[VERIFY\] e2e::flaky (passed on re-run): app_test.dart: user signs in' <<< "${out}")"
}
test_trap_does_not_hang_without_device() {
  # An invalid allowed-hosts line fails the step before any emulator; the exit trap must not wait
  # for a device (adb logcat would block forever).
  mkdir -p "${tmp}/proj/e2e" "${tmp}/bin" "${tmp}/rt"
  echo 'https://bad.example.com/path' > "${tmp}/proj/e2e/allowed-hosts.txt"
  # shellcheck disable=SC2016 # $1 belongs to the stub script
  printf '#!/usr/bin/env bash\ncase "$1" in get-state) exit 1 ;; logcat) sleep 300 ;; esac\n' > "${tmp}/bin/adb"
  chmod +x "${tmp}/bin/adb"
  (cd "${tmp}/proj" && PATH="${tmp}/bin:${PATH}" ACTION_PATH="${here}" RUNNER_TEMP="${tmp}/rt" \
    GITHUB_OUTPUT="${tmp}/rt/out" bash "${here}/flutter_e2e.sh" > "${tmp}/rt/log" 2>&1) &
  local pid=$! t0=${SECONDS}
  while kill -0 "${pid}" 2>/dev/null && [ $((SECONDS - t0)) -lt 15 ]; do sleep 1; done
  if kill -0 "${pid}" 2>/dev/null; then
    pkill -P "${pid}" 2>/dev/null; kill "${pid}" 2>/dev/null
    eq "${FUNCNAME[0]}" "exited within 15 s" "still running after 15 s"
  else
    wait "${pid}"; eq "${FUNCNAME[0]}_rc" 1 $?
  fi
}
test_failed_none() { printf '00:30 +3: All tests passed!\n' > "${tmp}/ok"; eq "${FUNCNAME[0]}" "" "$(flutter_e2e_failed "${tmp}/ok")"; }
test_verdict_pass() { eq "${FUNCNAME[0]}" pass "$(flutter_e2e_verdict 0 - 9)"; }
test_verdict_flaky() { eq "${FUNCNAME[0]}" flaky "$(flutter_e2e_verdict 1 0 9)"; }
test_verdict_network_check() { eq "${FUNCNAME[0]}" network-check "$(flutter_e2e_verdict 1 1 3)"; }
test_verdict_recheck_false_no_rerun() {
  eq "${FUNCNAME[0]}" blocked "$(flutter_e2e_verdict 1 1 3 false)"
  eq "${FUNCNAME[0]}_true" network-check "$(flutter_e2e_verdict 1 1 3 true)"
  eq "${FUNCNAME[0]}_flaky_unaffected" flaky "$(flutter_e2e_verdict 1 0 3 false)"
}
test_verdict_fail() { eq "${FUNCNAME[0]}" fail "$(flutter_e2e_verdict 1 1 0)"; }
for t in $(declare -F | awk '$3 ~ /^test_/ {print $3}'); do "$t"; done
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "${fails} FAILED"; exit 1; fi
