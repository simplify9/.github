#!/usr/bin/env bash
# shellcheck disable=SC2317,SC2329 # helpers are called by name from the test loop
# Unit tests for the decision helpers of e2e.sh (sourced with E2E_SH_LIB=1, so main does not run).
# The full flow is proved on a hosted runner (sandbox). Run: bash .github/actions/verify-web-e2e/test_e2e.sh
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=e2e.sh
E2E_SH_LIB=1 source "${here}/e2e.sh"
fails=0
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
eq() { # name expected actual
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: expected '$2' got '$3'"; fails=$((fails + 1)); fi
}
test_scan_targets_none() {
  mkdir -p "${tmp}/none"
  eq "${FUNCNAME[0]}" "" "$(e2e_scan_targets "${tmp}/none")"
  eq "${FUNCNAME[0]}_rc" 0 "$(e2e_scan_targets "${tmp}/none" >/dev/null; echo $?)"
}
test_scan_targets_har_and_mocks() {
  mkdir -p "${tmp}/r/e2e/rec"
  touch "${tmp}/r/e2e/rec/b.har" "${tmp}/r/e2e/mocks.json" "${tmp}/r/e2e/x.json"
  eq "${FUNCNAME[0]}" $'e2e/mocks.json\ne2e/rec/b.har' "$(e2e_scan_targets "${tmp}/r")"
}
test_scan_targets_har_body_files() {
  # routeFromHAR(..., { update: true }) defaults to updateContent "attach": bodies sit next to the .har.
  mkdir -p "${tmp}/b/e2e/rec"
  touch "${tmp}/b/e2e/home.spec.ts" "${tmp}/b/e2e/rec/items.har" "${tmp}/b/e2e/rec/0a1b.json" \
    "${tmp}/b/e2e/rec/2c3d.txt" "${tmp}/b/e2e/rec/4e5f.png" "${tmp}/b/e2e/rec/helper.ts"
  eq "${FUNCNAME[0]}" $'e2e/rec/0a1b.json\ne2e/rec/2c3d.txt\ne2e/rec/items.har' "$(e2e_scan_targets "${tmp}/b")"
}
test_zip_recordings() {
  mkdir -p "${tmp}/z/e2e/rec"
  touch "${tmp}/z/e2e/rec/items.zip" "${tmp}/z/e2e/ok.har"
  eq "${FUNCNAME[0]}" "e2e/rec/items.zip" "$(e2e_zip_recordings "${tmp}/z")"
  eq "${FUNCNAME[0]}_none" "" "$(e2e_zip_recordings "${tmp}/r")"
}
test_verdict_pass_with_blocked() { eq "${FUNCNAME[0]}" pass "$(e2e_verdict 0 5)"; }
test_verdict_fail_nothing_blocked() { eq "${FUNCNAME[0]}" fail "$(e2e_verdict 1 0)"; }
test_verdict_retry() { eq "${FUNCNAME[0]}" retry "$(e2e_verdict 1 3)"; }
test_verdict_recheck_true_retries() { eq "${FUNCNAME[0]}" retry "$(e2e_verdict 1 3 true)"; }
test_verdict_recheck_false_no_rerun() {
  eq "${FUNCNAME[0]}" blocked "$(e2e_verdict 1 3 false)"
  eq "${FUNCNAME[0]}_nothing_blocked" fail "$(e2e_verdict 1 0 false)"
  eq "${FUNCNAME[0]}_pass" pass "$(e2e_verdict 0 3 false)"
}
test_network_enforced_message() {
  eq "${FUNCNAME[0]}" "::error title=[VERIFY] network::the journeys failed while the block rejected traffic; blocked: 203.0.113.5:443. From the network deadline verify no longer re-runs with network access: mock these calls, or list third-party SDK hosts in e2e/allowed-hosts.txt" "$(e2e_network_enforced "203.0.113.5:443")"
}
test_after_retry() {
  eq "${FUNCNAME[0]}_pass" network "$(e2e_after_retry 0)"
  eq "${FUNCNAME[0]}_fail" fail "$(e2e_after_retry 1)"
}
for t in $(declare -F | awk '$3 ~ /^test_/ {print $3}'); do "$t"; done
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "${fails} FAILED"; exit 1; fi
