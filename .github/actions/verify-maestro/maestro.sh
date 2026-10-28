#!/usr/bin/env bash
# The React Native `maestro` step (see action.yml). Run from the project directory with APK (a path
# or glob), ACTION_PATH and RUNNER_TEMP set, after `yarn install`. Sourced with MAESTRO_SH_LIB=1 by
# test_maestro.sh for the helpers only.

# maestro_flows <dir>: flow files directly in <dir>/.maestro (*.yaml, *.yml; not config.yaml/yml),
# relative to <dir>, smoke.yaml first, the rest sorted. One per line; spaces kept.
maestro_flows() {
  [ -d "$1/.maestro" ] || return 0
  (
    cd "$1" || exit 1
    [ -f .maestro/smoke.yaml ] && echo .maestro/smoke.yaml
    find .maestro -maxdepth 1 -type f \( -name '*.yaml' -o -name '*.yml' \) \
      ! -name config.yaml ! -name config.yml ! -name smoke.yaml | LC_ALL=C sort
  )
}

# maestro_verdict <first-rc> <rerun-rc|-> <blocked-count> [recheck: true|false, default true]:
# pass | flaky | network-check | blocked (network enforced: no unblocked re-run) | fail
maestro_verdict() {
  if [ "$1" -eq 0 ]; then echo pass
  elif [ "$2" != "-" ] && [ "$2" -eq 0 ]; then echo flaky
  elif [ "$3" -gt 0 ] && [ "${4:-true}" = true ]; then echo network-check
  elif [ "$3" -gt 0 ]; then echo blocked
  else echo fail
  fi
}

# maestro_app_env <has-mocks: true|false>: Metro's environment, one VAR=value per line. Metro passes
# it to the app only at bundle time; the EXPO_PUBLIC_ copies are for Expo apps.
maestro_app_env() {
  printf '%s\n' VERIFY_E2E=1 EXPO_PUBLIC_VERIFY_E2E=1
  [ "$1" = true ] && printf '%s\n' E2E_API_URL=http://localhost:3901 EXPO_PUBLIC_E2E_API_URL=http://localhost:3901
  return 0
}

[ "${MAESTRO_SH_LIB:-}" = 1 ] && return 0

set -euo pipefail
# shellcheck source=../verify-netblock/netblock.sh
source "${ACTION_PATH}/../verify-netblock/netblock.sh"
# shellcheck source=../verify-mocks/mockoon.sh
source "${ACTION_PATH}/../verify-mocks/mockoon.sh"
# shellcheck source=../verify-emulator/emulator.sh
source "${ACTION_PATH}/../verify-emulator/emulator.sh"
# Helpers only (its main is skipped). Not followed: its library-mode `return` reads as dead code here.
# shellcheck source=/dev/null
E2E_SH_LIB=1 source "${ACTION_PATH}/../verify-web-e2e/e2e.sh"

export MAESTRO_CLI_NO_ANALYTICS=1 MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED=true
out="${RUNNER_TEMP}/maestro-report"
mkdir -p "${out}"
# Metro and emulator logs are written straight into the evidence folder: a step timeout kills this
# script without running the exit trap.
export EMULATOR_LOG_DIR="${out}"
MOCKOON_PID=""
trap 'cp "${RUNNER_TEMP}"/mockoon.log "${out}/" 2>/dev/null || true
      [ -z "${MOCKOON_PID}" ] || kill "${MOCKOON_PID}" 2>/dev/null || true' EXIT

e2e_scan_committed "${ACTION_PATH}/../verify-secret-scan/scan.py" || exit 1
netblock_hosts e2e/allowed-hosts.txt >/dev/null
mapfile -t flows < <(maestro_flows .)
mapfile -t apks < <(compgen -G "${APK}" || true)
if [ "${#apks[@]}" -eq 0 ]; then
  echo "::error title=[VERIFY] maestro::no APK at ${APK}"
  exit 1
fi

# Everything that needs the internet happens before the block.
emulator_kvm
emulator_install || verify_infra_fail "the Android emulator image could not be installed"
curl -fsSL "https://get.maestro.mobile.dev" | MAESTRO_VERSION=2.11.0 bash >/dev/null \
  || verify_infra_fail "the Maestro CLI could not be installed"
export PATH="${HOME}/.maestro/bin:${PATH}"
has_mocks=false
[ -f e2e/mocks.json ] && has_mocks=true
[ "${has_mocks}" = true ] && mockoon_install

netblock_on e2e/allowed-hosts.txt
mapfile -t app_env < <(maestro_app_env "${has_mocks}")
if [ "${has_mocks}" = true ]; then
  mockoon_start e2e/mocks.json netblock_run || exit 1
  echo "::notice title=[VERIFY] maestro::Mockoon serves e2e/mocks.json; the app gets E2E_API_URL=http://localhost:${MOCKOON_PORT}"
fi
# Metro inlines the env at bundle time (the app's Babel env plugin), so no stale cache.
netblock_run env "${app_env[@]}" npx react-native start --port 8081 --reset-cache > "${out}/metro.log" 2>&1 &
emulator_boot netblock_run
adb install -r "${apks[0]}" >/dev/null || verify_infra_fail "the APK could not be installed on the emulator"
adb reverse tcp:8081 tcp:8081 >/dev/null
[ "${has_mocks}" = true ] && adb reverse "tcp:${MOCKOON_PORT}" "tcp:${MOCKOON_PORT}" >/dev/null
# Only what happens from here (the app and its flows) counts as blocked traffic.
sleep 5
netblock_reset
# TEMPORARY attribution probe (review I1): what the idle emulator still sends with no flow running.
if [ "${VERIFY_IDLE_PROBE_SECONDS:-0}" -gt 0 ]; then
  sleep "${VERIFY_IDLE_PROBE_SECONDS}"
  echo "[VERIFY] idle probe: $(netblock_count) packet(s) in ${VERIFY_IDLE_PROBE_SECONDS} s to: $(netblock_blocked | tr '\n' ' ')"
  sudo iptables -w -L VERIFY_NETBLOCK -n -v -x | sed 's/^/[VERIFY] idle v4: /'
  sudo ip6tables -w -L VERIFY_NETBLOCK -n -v -x | sed 's/^/[VERIFY] idle v6: /'
  sudo dmesg | grep 'VERIFY-NETBLOCK' | tail -n 8 | sed 's/^/[VERIFY] idle log: /'
  # Split TCP into SYN and non-SYN counters for a moment, and list every non-loopback TCP socket.
  sudo iptables -w -I VERIFY_NETBLOCK 2 -p tcp --syn -j RETURN
  sudo iptables -w -I VERIFY_NETBLOCK 2 -p tcp ! --syn -j RETURN
  netblock_reset
  sleep 20
  sudo iptables -w -L VERIFY_NETBLOCK -n -v -x | grep -E 'RETURN' | sed 's/^/[VERIFY] idle split: /'
  sudo ss -tanpH | grep -v -E '127\.0\.0\.1|\[::1\]|::ffff:127' | sed 's/^/[VERIFY] idle sock: /' | head -n 15
  sudo iptables -w -D VERIFY_NETBLOCK -p tcp ! --syn -j RETURN
  sudo iptables -w -D VERIFY_NETBLOCK -p tcp --syn -j RETURN
  netblock_reset
fi

# run_flow <flow> <attempt> [PREFIX...]: one Maestro run, JUnit and artifacts under ${out}. Maestro
# is the host-side driver, so it runs outside the block: the app's own traffic leaves through the
# emulator, which is blocked, and Maestro's own calls are not the app's.
run_flow() {
  local flow="$1" attempt="$2" name
  shift 2
  name="$(basename "${flow}")"
  name="${name%.*}-${attempt}"
  "$@" maestro test --format JUNIT --output "${out}/${name}.xml" --test-output-dir "${out}/${name}" "${flow}"
}

passed=() flaky=() network=() failed=() first_failed=()
for flow in "${flows[@]}"; do
  if run_flow "${flow}" 1; then passed+=("${flow}"); else first_failed+=("${flow}"); fi
done
blocked="$(netblock_count)"
dests="$(netblock_blocked | tr '\n' ' ')"
dests="${dests% }"
recheck=()
enforced=false
for flow in "${first_failed[@]+"${first_failed[@]}"}"; do
  rc=0
  run_flow "${flow}" 2 || rc=1
  case "$(maestro_verdict 1 "${rc}" "${blocked}" "${NETWORK_RECHECK:-true}")" in
    flaky) flaky+=("${flow}") ;;
    network-check) recheck+=("${flow}") ;;
    blocked) failed+=("${flow}"); enforced=true ;;
    *) failed+=("${flow}") ;;
  esac
done
[ "${enforced}" = false ] || e2e_network_enforced "${dests}"
if [ "${#recheck[@]}" -gt 0 ]; then
  echo "::notice title=[VERIFY] network::flows failed while the block rejected ${blocked} packet(s) to: ${dests:-unknown}; re-running them once with network access"
  netblock_off
  for flow in "${recheck[@]}"; do
    if run_flow "${flow}" 3; then network+=("${flow}"); else failed+=("${flow}"); fi
  done
fi

{
  echo "### Maestro"
  echo "Flows: ${#flows[@]}"
  for kind in passed flaky network failed; do
    declare -n list="${kind}"
    [ "${#list[@]}" -gt 0 ] || continue
    case "${kind}" in
      passed) echo; echo "**Passed**" ;;
      flaky) echo; echo "**Flaky (passed on re-run)**" ;;
      network) echo; echo "**Passed only with network access** (blocked: ${dests:-unknown})" ;;
      failed) echo; echo "**Failed**" ;;
    esac
    # shellcheck disable=SC2016 # Markdown code spans, not expansions
    printf -- '- `%s`\n' "${list[@]}"
    unset -n list
  done
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
for flow in "${flaky[@]+"${flaky[@]}"}"; do echo "::warning title=[VERIFY] maestro::flaky (passed on re-run): ${flow}"; done
for flow in "${failed[@]+"${failed[@]}"}"; do echo "::error title=[VERIFY] maestro::failed: ${flow}"; done
if [ "${#network[@]}" -gt 0 ]; then
  echo "::warning title=[VERIFY] network::${network[*]} passed only with network access; blocked: ${dests:-unknown} (Android's own background traffic may be listed too). Mock the app's calls, or list third-party SDK hosts in e2e/allowed-hosts.txt"
  echo "network=needed" >> "${GITHUB_OUTPUT}"
fi
[ "${#failed[@]}" -eq 0 ]
