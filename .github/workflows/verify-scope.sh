#!/usr/bin/env bash
# Scope helpers for verify.yml. Sourced by the `plan` job and by test_verify_scope.sh.
# All dates are ISO YYYY-MM-DD, compared as strings.

# verify_full <event> <base> <default-branch> <author> <bot-login> -> true|false
verify_full() {
  if [ "$1" = "workflow_dispatch" ] || [ "$2" = "$3" ] || [ "$4" = "$5" ]; then
    echo true
  else
    echo false
  fi
}

# known_failing_effective <list> <deadline> <today> -> the list before the deadline, else empty
known_failing_effective() {
  if [ -z "$2" ] || [[ "$3" < "$2" ]]; then echo "$1"; else echo ""; fi
}

# contract_mode <deadline> <today> -> warn|enforce (mirrors verify-contract)
contract_mode() {
  if [ -z "$1" ] || [[ "$2" < "$1" ]]; then echo warn; else echo enforce; fi
}
