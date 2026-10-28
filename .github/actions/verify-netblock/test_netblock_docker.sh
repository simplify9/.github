#!/usr/bin/env bash
# Real-firewall test of netblock.sh: re-runs itself in ubuntu:24.04 with NET_ADMIN, as root and as a
# sudo-capable non-root user like the GitHub-hosted "runner". Needs internet (example.com, example.org).
# Skips when Docker is absent. Run: bash .github/actions/verify-netblock/test_netblock_docker.sh
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fails=0
eq() { # name expected actual
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: expected '$2' got '$3'"; fails=$((fails + 1)); fi
}
failed() { "$@" >/dev/null 2>&1 && echo 0 || echo 1; }

as_runner() {
  # shellcheck source=netblock.sh
  source "${here}/netblock.sh"
  # shellcheck disable=SC2016 # expanded by the inner sh, on purpose
  eq nonroot_keeps_env_uid_and_path "bar runner verify-offline ${PATH}" \
    "$(FOO=bar netblock_run sh -c 'echo "${FOO} $(id -un) $(id -gn) ${PATH}"')"
  # HOME and USER as the caller sees them: tools find their per-user files (e.g. ~/.android/avd).
  # shellcheck disable=SC2016 # expanded by the inner sh, on purpose
  eq nonroot_keeps_home_and_user "${HOME} runner" "$(netblock_run sh -c 'echo "${HOME} ${USER}"')"
  eq nonroot_blocked 1 "$(failed netblock_run curl -sS -m 5 https://example.org)"
  eq nonroot_count 1 "$([ "$(netblock_count)" -gt 0 ] && echo 1 || echo 0)"
}

inner() {
  if ! { apt-get update -qq && apt-get install -y -qq iptables curl python3 sudo; } >/dev/null 2>&1; then
    echo "FAIL apt"; exit 1
  fi
  # shellcheck source=netblock.sh
  source "${here}/netblock.sh"
  python3 -m http.server 8765 --bind 127.0.0.1 >/dev/null 2>&1 &
  sleep 1

  netblock_on >/dev/null || { echo "FAIL netblock_on"; exit 1; }
  eq blocked_host_fails 1 "$(failed netblock_run curl -sS -m 5 https://example.org)"
  eq count_after_block 1 "$([ "$(netblock_count)" -gt 0 ] && echo 1 || echo 0)"
  eq unblocked_process_reaches_internet 0 "$(failed curl -sS -m 10 https://example.org)"
  eq loopback_allowed 0 "$(failed netblock_run curl -sS -m 5 http://127.0.0.1:8765/)"
  eq runs_as_group verify-offline "$(netblock_run id -gn)"
  eq blocked_list_best_effort 0 "$(failed netblock_blocked)"

  printf '# docs\nexample.com\n' > /tmp/allowed
  netblock_on /tmp/allowed >/dev/null || { echo "FAIL netblock_on allowed"; exit 1; }
  eq counter_zeroed 0 "$(netblock_count)"
  eq allowed_host_reachable 0 "$(failed netblock_run curl -sS -m 10 https://example.com)"
  eq hosts_pinned 1 "$(grep -qE '[[:space:]]example\.com$' /etc/hosts && echo 1 || echo 0)"
  eq other_host_still_blocked 1 "$(failed netblock_run curl -sS -m 5 https://example.org)"
  eq single_output_jump 1 "$(iptables -S OUTPUT | grep -c VERIFY_NETBLOCK)"
  eq single_output_jump_v6 1 "$(ip6tables -S OUTPUT | grep -c VERIFY_NETBLOCK)"

  # Under errexit + pipefail, as e2e.sh runs it: an unresolvable allowed host must say so, not exit silently.
  printf 'no-such-host.invalid\n' > /tmp/bad
  out="$(bash -c "set -euo pipefail; source ${here}/netblock.sh; netblock_on /tmp/bad" 2>&1)"; rc=$?
  eq unresolvable_host_rc 1 "${rc}"
  eq unresolvable_host_named 1 "$(grep -c 'cannot resolve allowed host no-such-host.invalid' <<< "${out}")"

  # Multicast (mDNS) and NTP are dropped silently: an emulator's own chatter, never the app's journey.
  netblock_on >/dev/null
  netblock_run python3 -c 'import socket; s=socket.socket(socket.AF_INET, socket.SOCK_DGRAM); [s.sendto(b"x", a) for a in (("224.0.0.251", 5353), ("203.0.113.9", 123))]' 2>/dev/null
  eq multicast_and_ntp_not_counted 0 "$(netblock_count)"
  netblock_run curl -sS -m 5 https://example.org >/dev/null 2>&1
  eq tcp_still_counted 1 "$([ "$(netblock_count)" -gt 0 ] && echo 1 || echo 0)"

  # netblock_reset forgets traffic rejected so far (an emulator's own boot chatter), keeping the block.
  netblock_on >/dev/null
  netblock_run curl -sS -m 5 https://example.org >/dev/null 2>&1
  eq before_reset_counted 1 "$([ "$(netblock_count)" -gt 0 ] && echo 1 || echo 0)"
  netblock_reset
  eq after_reset_zero 0 "$(netblock_count)"
  eq after_reset_still_blocked 1 "$(failed netblock_run curl -sS -m 5 https://example.org)"

  # netblock_off lifts the block for the group without restarting anything (mobile network check).
  netblock_on >/dev/null
  eq before_off_blocked 1 "$(failed netblock_run curl -sS -m 5 https://example.org)"
  netblock_off
  eq after_off_reachable 0 "$(failed netblock_run curl -sS -m 10 https://example.org)"
  eq after_off_no_jump 0 "$(iptables -S OUTPUT | grep -c VERIFY_NETBLOCK)"
  eq after_off_no_jump_v6 0 "$(ip6tables -S OUTPUT | grep -c VERIFY_NETBLOCK)"

  useradd -m -s /bin/bash runner && echo 'runner ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/runner
  netblock_on >/dev/null
  su runner -c "bash ${here}/test_netblock_docker.sh --as-runner" > /tmp/runner.out
  cat /tmp/runner.out
  fails=$((fails + $(grep -c '^FAIL' /tmp/runner.out)))
}

case "${1:-}" in
  --as-runner) as_runner; exit 0 ;;
  --inner) inner ;;
  *)
    if ! docker info >/dev/null 2>&1; then
      echo "::notice::Docker not available; skipping the netblock firewall test"
      exit 0
    fi
    docker run --rm --cap-add NET_ADMIN -v "${here}:/nb:ro" ubuntu:24.04 bash /nb/test_netblock_docker.sh --inner
    exit $?
    ;;
esac
if [ "${fails}" -eq 0 ]; then echo "ALL PASS"; else echo "${fails} FAILED"; exit 1; fi
