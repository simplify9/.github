#!/usr/bin/env bash
# Sourced by the SLA step in action.yml and by test_sla_overdue.sh.
# sla_decide <mode:warn|enforce> <api_ok:0|1> <overdue_count>
#   api_ok is an exit-code style flag: 0 = alerts fetched fine, 1 = API error.
# Prints the exit code the step should use. Enforce fails closed on an API
# error or any overdue alert; warn never fails.
sla_decide() {
  local mode="$1" api_err="$2" count="$3"
  if [[ "$mode" != "enforce" ]]; then echo 0; return; fi
  if [[ "$api_err" -ne 0 || "$count" -gt 0 ]]; then echo 1; else echo 0; fi
}
