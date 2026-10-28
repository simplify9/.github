#!/usr/bin/env bash
# Unit tests for the pure helpers of emulator.sh; the boot itself is proved on a hosted runner.
# Run: bash .github/actions/verify-emulator/test_emulator.sh
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=emulator.sh
source "${here}/emulator.sh"
fails=0
eq() { # name expected actual
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: expected '$2' got '$3'"; fails=$((fails + 1)); fi
}
eq boot_first_try booted "$(emulator_boot_verdict 0 -)"
eq boot_retry retry "$(emulator_boot_verdict 1 -)"
eq boot_second_try booted "$(emulator_boot_verdict 1 0)"
eq boot_failed failed "$(emulator_boot_verdict 1 1)"
# I1: system apps' UIDs from `cmd package list packages -s -U` (>= 10000; below is blocked as a range).
eq system_uids $'10023\n10031' "$(emulator_system_uids $'package:com.android.providers.downloads uid:10023\r\npackage:android uid:1000\npackage:com.android.webview uid:10031\npackage:com.android.shell uid:2000,10023\n')"
eq system_uids_empty "" "$(emulator_system_uids '')"

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
mkdir -p "${tmp}/bin"
# Stub adb: no device ever boots; `devices` lists an emulator for the first 2 calls, then none.
cat > "${tmp}/bin/adb" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  wait-for-device) sleep 30 ;;
  get-state) exit 1 ;;
  devices) n=$(cat "${STUB_DIR}/n" 2>/dev/null || echo 0); echo $((n + 1)) > "${STUB_DIR}/n"
           echo "List of devices attached"; [ "${n}" -lt 2 ] && printf 'emulator-5554\tdevice\n'; exit 0 ;;
  *) exit 0 ;;
esac
STUB
chmod +x "${tmp}/bin/adb"
export PATH="${tmp}/bin:${PATH}" STUB_DIR="${tmp}"

# M2: an emulator that already exited ("Unknown AVD name") is not waited on for the full timeout.
sh -c 'exit 0' & EMULATOR_PID=$!
wait "${EMULATOR_PID}" 2>/dev/null
t0=${SECONDS}
_emulator_wait 8
eq wait_dead_emulator_rc 1 $?
eq wait_dead_emulator_fast 1 "$([ $((SECONDS - t0)) -lt 5 ] && echo 1 || echo 0)"

# M2: emulator_stop returns only once adb lists no emulator.
rm -f "${tmp}/n"
emulator_stop
eq stop_waits_for_device_gone 1 "$([ "$(cat "${tmp}/n" 2>/dev/null || echo 0)" -ge 3 ] && echo 1 || echo 0)"

# M3: an infrastructure failure says so (annotation and summary) and exits 2.
out="$( (GITHUB_STEP_SUMMARY="${tmp}/summary" verify_infra_fail "the emulator image could not be installed") 2>&1)"
eq infra_fail_rc 2 "$( (GITHUB_STEP_SUMMARY="${tmp}/summary" verify_infra_fail "x") >/dev/null 2>&1; echo $?)"
eq infra_fail_annotation 1 "$(grep -c '::error title=\[VERIFY\] emulator::the emulator image could not be installed (infrastructure, not the app)' <<< "${out}")"
eq infra_fail_summary 1 "$(grep -c 'infrastructure, not the app' "${tmp}/summary" | awk '{print ($1 > 0)}')"

if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "${fails} FAILED"; exit 1; fi
