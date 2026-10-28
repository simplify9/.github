#!/usr/bin/env bash
# shellcheck disable=SC2317,SC2329 # helpers are called by name from the test loop
# Unit tests for the helpers of maestro.sh (sourced with MAESTRO_SH_LIB=1, so main does not run).
# The emulator flow is proved on a hosted runner. Run: bash .github/actions/verify-maestro/test_maestro.sh
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=maestro.sh
MAESTRO_SH_LIB=1 source "${here}/maestro.sh"
fails=0
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
eq() { # name expected actual
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: expected '$2' got '$3'"; fails=$((fails + 1)); fi
}
test_flows_order_and_exclusions() {
  mkdir -p "${tmp}/a/.maestro/sub"
  touch "${tmp}/a/.maestro/"{zeta.yaml,smoke.yaml,alpha.yml,config.yaml,notes.md} "${tmp}/a/.maestro/sub/x.yaml"
  eq "${FUNCNAME[0]}" $'.maestro/smoke.yaml\n.maestro/alpha.yml\n.maestro/zeta.yaml' "$(maestro_flows "${tmp}/a")"
}
test_flows_spaces() {
  mkdir -p "${tmp}/b/.maestro"
  touch "${tmp}/b/.maestro/smoke.yaml" "${tmp}/b/.maestro/sign in.yaml"
  local -a got
  mapfile -t got < <(maestro_flows "${tmp}/b")
  eq "${FUNCNAME[0]}_count" 2 "${#got[@]}"
  eq "${FUNCNAME[0]}_name" ".maestro/sign in.yaml" "${got[1]}"
}
test_flows_none() { mkdir -p "${tmp}/c"; eq "${FUNCNAME[0]}" "" "$(maestro_flows "${tmp}/c")"; }
test_verdict_pass() { eq "${FUNCNAME[0]}" pass "$(maestro_verdict 0 - 0)"; }
test_verdict_flaky() { eq "${FUNCNAME[0]}" flaky "$(maestro_verdict 1 0 0)"; }
test_verdict_network_check() { eq "${FUNCNAME[0]}" network-check "$(maestro_verdict 1 1 3)"; }
test_verdict_fail() { eq "${FUNCNAME[0]}" fail "$(maestro_verdict 1 1 0)"; }
test_app_env_with_mocks() {
  eq "${FUNCNAME[0]}" $'VERIFY_E2E=1\nEXPO_PUBLIC_VERIFY_E2E=1\nE2E_API_URL=http://localhost:3901\nEXPO_PUBLIC_E2E_API_URL=http://localhost:3901' "$(maestro_app_env true)"
}
test_app_env_without_mocks() { eq "${FUNCNAME[0]}" $'VERIFY_E2E=1\nEXPO_PUBLIC_VERIFY_E2E=1' "$(maestro_app_env false)"; }
for t in $(declare -F | awk '$3 ~ /^test_/ {print $3}'); do "$t"; done
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "${fails} FAILED"; exit 1; fi
