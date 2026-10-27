#!/usr/bin/env bash
# Unit tests for the parts of netblock.sh that need no root: the allowed-hosts parser.
# The firewall itself is tested by test_netblock_docker.sh. Run: bash .github/actions/verify-netblock/test_netblock.sh
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=netblock.sh
source "${here}/netblock.sh"
fails=0
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
eq() { # name expected actual
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: expected '$2' got '$3'"; fails=$((fails + 1)); fi
}
rejects() { # name line-content expected-line-number
  printf 'ok.example.com\n%s\n' "$2" > "${tmp}/h"
  local out rc
  out="$(netblock_hosts "${tmp}/h" 2>&1)"; rc=$?
  eq "$1_rc" 1 "${rc}"
  case "${out}" in *":$3: "*) eq "$1_names_line" ok ok ;; *) eq "$1_names_line" ":$3: in output" "${out}" ;; esac
}
test_hosts_comments_blank_crlf() {
  printf '# c\r\n\r\napi.example.com # maps\r\n203.0.113.5\r\n2001:db8::1\r\n' > "${tmp}/h"
  eq "${FUNCNAME[0]}" $'api.example.com\n203.0.113.5\n2001:db8::1' "$(netblock_hosts "${tmp}/h")"
}
test_hosts_missing_file_empty() {
  eq "${FUNCNAME[0]}" "" "$(netblock_hosts "${tmp}/absent")"
  eq "${FUNCNAME[0]}_rc" 0 "$(netblock_hosts "${tmp}/absent" >/dev/null; echo $?)"
}
test_hosts_rejects_url() { rejects "${FUNCNAME[0]}" 'https://x.example.com/p' 2; }
test_hosts_rejects_port() { rejects "${FUNCNAME[0]}" 'x.example.com:443' 2; }
test_hosts_rejects_wildcard() { rejects "${FUNCNAME[0]}" '*.example.com' 2; }
for t in $(declare -F | awk '$3 ~ /^test_/ {print $3}'); do "$t"; done
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "${fails} FAILED"; exit 1; fi
