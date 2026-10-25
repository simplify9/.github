#!/usr/bin/env bash
# Tests for sla_overdue.jq and sla_decide.sh. Run: bash test_sla_overdue.sh
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOW=1767225600 # 2026-01-01T00:00:00Z

# alert <severity> <days_before_now> [number]
alert() {
  local created
  created="$(date -u -r $((NOW - $2 * 86400)) +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$((NOW - $2 * 86400))" +%Y-%m-%dT%H:%M:%SZ)"
  jq -n --arg s "$1" --arg c "$created" --argjson n "${3:-1}" \
    '{number:$n, created_at:$c, html_url:"https://x/\($n)",
      security_advisory:{severity:$s}, dependency:{package:{name:"pkg\($n)", ecosystem:"npm"}}}'
}
run() { jq --argjson now "$NOW" --argjson high 30 --argjson medium 90 -f "$here/sla_overdue.jq"; }
check() { # name, jq -e expression, stdin = filter output
  local out; out="$(cat)"
  if printf '%s' "$out" | jq -e "$2" >/dev/null; then echo "ok $1"; else echo "FAIL $1: $out"; exit 1; fi
}

alert high 31 | jq -s . | run | check high_31d_overdue 'length==1 and .[0].age_days==31 and .[0].deadline_days==30 and .[0].package=="pkg1"'
alert high 30 | jq -s . | run | check high_30d_not_overdue 'length==0'
alert medium 91 | jq -s . | run | check medium_91d_overdue 'length==1 and .[0].deadline_days==90'
alert medium 89 | jq -s . | run | check medium_89d_ok 'length==0'
alert critical 400 | jq -s . | run | check critical_ignored 'length==0'
alert low 400 | jq -s . | run | check low_ignored 'length==0'
{ alert high 40 1; alert medium 200 2; } | jq -s . | run | check sorted_desc '[.[].number]==[2,1]'

# --- decision section: sla_decide <mode> <api_ok:0|1> <count> prints exit code
# shellcheck source=sla_decide.sh
source "$here/sla_decide.sh"
expect() { # name, expected, args...
  local name="$1" want="$2"; shift 2
  local got; got="$(sla_decide "$@")"
  if [[ "$got" == "$want" ]]; then echo "ok $name"; else echo "FAIL $name: got $got want $want"; exit 1; fi
}
expect sla_api_error_warn 0 warn 1 0
expect sla_api_error_enforce 1 enforce 1 0
expect sla_enforce_overdue 1 enforce 0 2
expect sla_warn_overdue 0 warn 0 2
expect sla_enforce_clean 0 enforce 0 0
