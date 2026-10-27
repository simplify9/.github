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

# flutter_e2e_failed <log>: "file: test name" of each failed test in `flutter test --reporter expanded`.
flutter_e2e_failed() {
  sed -n 's#^[0-9:]* +[0-9]* -[0-9]*: .*/\([^/]*\.dart\): \(.*\) \[E\]$#\1: \2#p' "$1" | LC_ALL=C sort -u
}

[ "${FLUTTER_E2E_SH_LIB:-}" = 1 ] && return 0

set -euo pipefail
# shellcheck source=../verify-netblock/netblock.sh
source "${ACTION_PATH}/../verify-netblock/netblock.sh"
# shellcheck source=../verify-mocks/mockoon.sh
source "${ACTION_PATH}/../verify-mocks/mockoon.sh"
# shellcheck source=../verify-emulator/emulator.sh
source "${ACTION_PATH}/../verify-emulator/emulator.sh"
# Helpers only (its main is skipped): e2e_scan_committed, e2e_verdict, e2e_after_retry.
# shellcheck source=/dev/null
E2E_SH_LIB=1 source "${ACTION_PATH}/../verify-web-e2e/e2e.sh"

out="${RUNNER_TEMP}/flutter-e2e-report"
log="${out}/flutter-test.log"
mkdir -p "${out}"
MOCKOON_PID=""
trap 'adb logcat -d > "${out}/logcat.txt" 2>/dev/null || true
      cp "${RUNNER_TEMP}"/emulator-*.log "${RUNNER_TEMP}"/mockoon.log "${out}/" 2>/dev/null || true
      [ -z "${MOCKOON_PID}" ] || kill "${MOCKOON_PID}" 2>/dev/null || true' EXIT

e2e_scan_committed "${ACTION_PATH}/../verify-secret-scan/scan.py" || exit 1
netblock_hosts e2e/allowed-hosts.txt >/dev/null
has_mocks=false
[ -f e2e/mocks.json ] && has_mocks=true
mapfile -t defines < <(flutter_e2e_defines "${has_mocks}")

# Everything that needs the internet happens before the block: the emulator image, packages, and a
# debug build so Gradle has its dependencies cached when the blocked test build runs.
export FLUTTER_SUPPRESS_ANALYTICS=true
flutter config --no-analytics >/dev/null 2>&1 || true
dart --disable-analytics >/dev/null 2>&1 || true
emulator_kvm
emulator_install
flutter pub get
flutter build apk --debug
[ "${has_mocks}" = true ] && mockoon_install

netblock_on e2e/allowed-hosts.txt
if [ "${has_mocks}" = true ]; then
  mockoon_start e2e/mocks.json netblock_run || exit 1
  echo "::notice title=[VERIFY] e2e::Mockoon serves e2e/mocks.json; the app gets E2E_API_URL=http://localhost:${MOCKOON_PORT}"
fi
emulator_boot netblock_run || exit 2
[ "${has_mocks}" = true ] && adb reverse "tcp:${MOCKOON_PORT}" "tcp:${MOCKOON_PORT}" >/dev/null
device="$(adb devices | awk 'NR > 1 && $2 == "device" {print $1; exit}')"
# Only what happens from here (the app and its tests) counts as blocked traffic.
sleep 5
netblock_reset

# flutter_run [PREFIX...]: the integration tests on the emulator; the log keeps the last run.
flutter_run() {
  set +e
  "$@" flutter test integration_test --no-pub --reporter expanded -d "${device}" "${defines[@]}" 2>&1 | tee "${log}"
  rc=${PIPESTATUS[0]}
  set -e
}
flutter_run netblock_run
blocked="$(netblock_count)"
dests="$(netblock_blocked | tr '\n' ' ')"
dests="${dests% }"
case "$(e2e_verdict "${rc}" "${blocked}")" in
  pass)
    if [ "${blocked}" -gt 0 ]; then
      echo "::notice title=[VERIFY] network::e2e passed; the block rejected ${blocked} packet(s) to: ${dests:-unknown}"
    fi
    ;;
  retry)
    echo "::notice title=[VERIFY] network::e2e failed while the block rejected ${blocked} packet(s) to: ${dests:-unknown}; re-running once with network access to tell the two apart"
    netblock_off
    flutter_run
    if [ "$(e2e_after_retry "${rc}")" = network ]; then
      echo "::warning title=[VERIFY] network::e2e passed only with network access; blocked: ${dests:-unknown}. Mock these calls, or list third-party SDK hosts in e2e/allowed-hosts.txt"
      echo "network=needed" >> "${GITHUB_OUTPUT}"
    else
      echo "::notice title=[VERIFY] network::e2e failed with network access too: a real failure"
    fi
    ;;
esac

mapfile -t failed < <(flutter_e2e_failed "${log}")
{
  echo "### Flutter integration tests"
  tail -n 1 "${log}"
  if [ "${#failed[@]}" -gt 0 ]; then
    echo
    echo "**Failed**"
    printf -- '- %s\n' "${failed[@]}"
  fi
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
for t in "${failed[@]+"${failed[@]}"}"; do echo "::error title=[VERIFY] e2e::failed: ${t}"; done
exit "${rc}"
