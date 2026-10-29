#!/usr/bin/env bash
# The Flutter `e2e` step (see action.yml). Run from the project directory with ACTION_PATH and
# RUNNER_TEMP set, after Flutter is set up. Sourced with FLUTTER_E2E_SH_LIB=1 by test_flutter_e2e.sh
# for the helpers only.

# flutter_e2e_defines <has-mocks: true|false>: the --dart-define arguments, one per line.
flutter_e2e_defines() {
  echo "--dart-define=VERIFY_E2E=true"
  [ "$1" = true ] && echo "--dart-define=E2E_API_URL=http://localhost:3901"
  return 0
}

# flutter_e2e_failed <log>: "file: test name" of each failed test, from the "Failing tests:" footer
# `flutter test` prints (the per-test "[E]" lines carry no path in a one-file run).
flutter_e2e_failed() {
  sed -n '/^Failing tests:$/,/^$/ s#^  .*/\([^/]*\.dart\): \(.*\)$#\1: \2#p' "$1" | LC_ALL=C sort -u
}

# flutter_e2e_result_line <log>: the last "+N [~S] [-F]: Some tests failed." / "All tests passed!" line.
flutter_e2e_result_line() {
  grep -E '^[0-9:]+ \+[0-9]+( ~[0-9]+)?( -[0-9]+)?: (Some tests failed\.|All tests passed!)$' "$1" | tail -n 1
}

# flutter_e2e_summary <verdict> <first-run-log> <last-run-log>: Markdown on stdout (the job summary),
# one annotation per flaky or failed test on stderr. Flaky tests are named from the first run's log.
flutter_e2e_summary() {
  local -a names
  local t
  echo "### Flutter integration tests"
  flutter_e2e_result_line "$3"
  if [ "$1" = flaky ]; then
    mapfile -t names < <(flutter_e2e_failed "$2")
    echo
    echo "**Flaky (failed, then passed on a re-run)**"
    printf -- '- %s\n' "${names[@]+"${names[@]}"}"
    for t in "${names[@]+"${names[@]}"}"; do echo "::warning title=[VERIFY] e2e::flaky (passed on re-run): ${t}" >&2; done
  fi
  mapfile -t names < <(flutter_e2e_failed "$3")
  if [ "${#names[@]}" -gt 0 ]; then
    echo
    echo "**Failed**"
    printf -- '- %s\n' "${names[@]}"
    for t in "${names[@]}"; do echo "::error title=[VERIFY] e2e::failed: ${t}" >&2; done
  fi
}

# flutter_e2e_timed_out <rc>: the attempt was stopped by its time cap: timeout's 124, or 137 when the
# child ignored TERM and was killed (an OOM kill is 137 too, and no more worth re-running).
flutter_e2e_timed_out() { [ "$1" = 124 ] || [ "$1" = 137 ]; }

# flutter_e2e_verdict <first-rc> <blocked-rerun-rc|-> <blocked-count> [recheck: true|false, default
# true]: pass | flaky | network-check | blocked (network enforced: no unblocked re-run) | fail.
# A failure is re-run once under the block first, so a flake is never taken for a network need;
# a timed-out attempt (first or re-run) makes it a plain fail with no further attempt.
flutter_e2e_verdict() {
  if [ "$1" -eq 0 ]; then echo pass
  elif flutter_e2e_timed_out "$1" || flutter_e2e_timed_out "$2"; then echo fail # a hanging run hangs again
  elif [ "$2" != "-" ] && [ "$2" -eq 0 ]; then echo flaky
  elif [ "$3" -gt 0 ] && [ "${4:-true}" = true ]; then echo network-check
  elif [ "$3" -gt 0 ]; then echo blocked
  else echo fail
  fi
}

# flutter_e2e_stop_gradle: after the warm build (run from the project directory), no Gradle or Kotlin
# daemon stays resident next to the emulator; a large app's daemons plus the emulator ran a 2-vCPU
# hosted runner out of memory. The blocked test build later starts a fresh, incremental one.
flutter_e2e_stop_gradle() {
  if [ -x android/gradlew ]; then (cd android && ./gradlew --stop) >/dev/null 2>&1 || true; fi
  pkill -u "$(id -u)" -f KotlinCompileDaemon 2>/dev/null || true
  pkill -u "$(id -u)" -f GradleDaemon 2>/dev/null || true
}

[ "${FLUTTER_E2E_SH_LIB:-}" = 1 ] && return 0

set -euo pipefail
# shellcheck source=../verify-netblock/netblock.sh
source "${ACTION_PATH}/../verify-netblock/netblock.sh"
# shellcheck source=../verify-mocks/mockoon.sh
source "${ACTION_PATH}/../verify-mocks/mockoon.sh"
# shellcheck source=../verify-emulator/emulator.sh
source "${ACTION_PATH}/../verify-emulator/emulator.sh"
# Helpers only (its main is skipped): e2e_scan_committed, e2e_after_retry, e2e_network_enforced.
# shellcheck source=/dev/null
E2E_SH_LIB=1 source "${ACTION_PATH}/../verify-web-e2e/e2e.sh"

out="${RUNNER_TEMP}/flutter-e2e-report"
log="${out}/flutter-test.log"
mkdir -p "${out}"
# Emulator logs straight into the evidence folder: a step timeout skips the exit trap.
export EMULATOR_LOG_DIR="${out}"
MOCKOON_PID=""
# logcat only when a device is online (adb would otherwise wait for one forever), and bounded.
trap '{ adb get-state >/dev/null 2>&1 && timeout 60 adb logcat -d > "${out}/logcat.txt"; } 2>/dev/null || true
      cp "${RUNNER_TEMP}"/emulator-*.log "${RUNNER_TEMP}"/mockoon.log "${out}/" 2>/dev/null || true
      [ -z "${MOCKOON_PID}" ] || kill "${MOCKOON_PID}" 2>/dev/null || true' EXIT

e2e_scan_committed "${ACTION_PATH}/../verify-secret-scan/scan.py" || exit 1
netblock_hosts e2e/allowed-hosts.txt >/dev/null
has_mocks=false
[ -f e2e/mocks.json ] && has_mocks=true
mapfile -t defines < <(flutter_e2e_defines "${has_mocks}")

# Before the block: the emulator image, packages, and a debug build that warms Gradle's caches so
# each test build is incremental.
export FLUTTER_SUPPRESS_ANALYTICS=true
flutter config --no-analytics >/dev/null 2>&1 || true
dart --disable-analytics >/dev/null 2>&1 || true
emulator_kvm
emulator_install
flutter pub get
flutter build apk --debug
verify_mem "after the debug build"
flutter_e2e_stop_gradle
sleep 3
verify_mem "Gradle stopped, before the emulator"
[ "${has_mocks}" = true ] && mockoon_install

# The block covers the emulator, where the app and its tests run, and Mockoon. The host-side
# `flutter test` (Gradle build, adb, result reader) stays outside it, as in the maestro job: blocked,
# Gradle could not resolve dynamic versions such as integration_test's androidx.test:runner:1.2+.
netblock_on e2e/allowed-hosts.txt
if [ "${has_mocks}" = true ]; then
  mockoon_start e2e/mocks.json netblock_run || exit 1
  echo "::notice title=[VERIFY] e2e::Mockoon serves e2e/mocks.json; the app gets E2E_API_URL=http://localhost:${MOCKOON_PORT}"
fi
emulator_boot netblock_run || exit 2
verify_mem "emulator booted"
[ "${has_mocks}" = true ] && adb reverse "tcp:${MOCKOON_PORT}" "tcp:${MOCKOON_PORT}" >/dev/null
device="$(adb devices | awk 'NR > 1 && $2 == "device" {print $1; exit}')"
# Without one, `flutter test -d ""` could pick a host device, which runs outside the block.
[ -n "${device}" ] || verify_infra_fail "adb lists no booted emulator"
# Only what happens from here (the app and its tests) counts as blocked traffic, and the emulator's own
# residual background traffic, recorded while nothing runs, is never blamed on the tests.
sleep 5
netblock_reset
netblock_idle 30

# flutter_run: the integration tests on the emulator, one attempt capped at 10 minutes so a hanging
# test cannot use up the job; the log keeps the last run.
flutter_run() {
  set +e
  timeout --kill-after=30 600 \
    flutter test integration_test --no-pub --reporter expanded -d "${device}" "${defines[@]}" 2>&1 | tee "${log}"
  rc=${PIPESTATUS[0]}
  flutter_e2e_timed_out "${rc}" && echo "::warning title=[VERIFY] e2e::an attempt ran past 10 minutes and was stopped"
  verify_mem "after a test attempt"
  set -e
}
flutter_run
first=${rc} rerun=-
if [ "${first}" -ne 0 ] && ! flutter_e2e_timed_out "${first}"; then
  cp "${log}" "${out}/flutter-test-run1.log"
  echo "[VERIFY] e2e: failed; re-running once with the block still on"
  flutter_run
  rerun=${rc}
fi
# Blocked traffic the tests are blamed for: destinations listed since the idle window, minus those seen
# while idle. Its count, not the raw packet counter, decides whether the block may be the cause.
attributable="$(netblock_subtract "${NETBLOCK_IDLE:-}" "$(netblock_blocked)")"
blocked="$(grep -c . <<< "${attributable}" || true)"
dests="$(tr '\n' ' ' <<< "${attributable}")"
dests="${dests% }"
verdict="$(flutter_e2e_verdict "${first}" "${rerun}" "${blocked}" "${NETWORK_RECHECK:-true}")"
# A timed-out run gets no network re-check, but the hosts it was refused still point at the cause.
if [ "${verdict}" = fail ] && [ "${blocked}" -gt 0 ]; then
  echo "::notice title=[VERIFY] network::the block rejected traffic to ${blocked} destination(s) during the e2e step: ${dests}"
fi
case "${verdict}" in
  blocked)
    e2e_network_enforced "${dests}"
    ;;
  network-check)
    echo "::notice title=[VERIFY] network::e2e failed twice while the block rejected traffic to ${blocked} destination(s): ${dests}; re-running once with network access to tell the two apart"
    netblock_off
    flutter_run
    if [ "$(e2e_after_retry "${rc}")" = network ]; then
      echo "::warning title=[VERIFY] network::e2e passed only with network access; blocked: ${dests:-unknown}. Mock the app's calls, or list third-party SDK hosts in e2e/allowed-hosts.txt"
      echo "network=needed" >> "${GITHUB_OUTPUT}"
    else
      echo "::notice title=[VERIFY] network::e2e failed with network access too: a real failure"
    fi
    ;;
esac

flutter_e2e_summary "${verdict}" "${out}/flutter-test-run1.log" "${log}" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
exit "${rc}"
