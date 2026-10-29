#!/usr/bin/env bash
# Android emulator for verify's mobile end-to-end steps (sourced; helpers tested by
# test_emulator.sh, the boot proved on GitHub-hosted runners). Used by verify-maestro and the
# Flutter e2e step. Needs ANDROID_HOME (preinstalled on hosted runners) and RUNNER_TEMP.
#
#   emulator_kvm                  let the runner user open /dev/kvm (hosted Linux runners)
#   emulator_install              API 34 x86_64 image, emulator and platform-tools; AVD "verify"
#                                 (downloads: run before the network block)
#   emulator_boot [PREFIX...]     boot through PREFIX (e.g. netblock_run, so the emulator's own
#                                 sockets, which carry the app's traffic, are blocked); 2 attempts of
#                                 300 s; exits 2 through verify_infra_fail when it never boots
#   emulator_stop                 until adb lists no emulator (SIGKILL after a grace period)
#   emulator_boot_verdict RC1 RC2|-   booted | retry | failed
#   verify_mem LABEL              one line of `free -m` in the step log
#   verify_infra_fail MESSAGE     "MESSAGE (infrastructure, not the app)" as an error and in the job
#                                 summary, then exit 2 (not reported as a journey failure)

EMULATOR_IMAGE="system-images;android-34;default;x86_64"
EMULATOR_BOOT_SECONDS=300
# Guest RAM in MB, capped so the emulator fits next to the rest of the job on a 2-vCPU / ~8 GB hosted
# runner (private repositories): a large app's Gradle build plus an uncapped emulator ran it out of memory.
EMULATOR_MEMORY_MB="${EMULATOR_MEMORY_MB:-2048}"
# Where emulator-<attempt>.log go; a caller points it at its evidence folder so the logs survive a
# step timeout (no exit trap runs then).
EMULATOR_LOG_DIR="${EMULATOR_LOG_DIR:-${RUNNER_TEMP:-/tmp}}"
export PATH="${ANDROID_HOME:-}/platform-tools:${ANDROID_HOME:-}/emulator:${PATH}"

emulator_boot_verdict() {
  if [ "$1" -eq 0 ]; then echo booted
  elif [ "$2" = "-" ]; then echo retry
  elif [ "$2" -eq 0 ]; then echo booted
  else echo failed
  fi
}

emulator_kvm() {
  # udev rule from GitHub's 2024-04-02 changelog (KVM on hosted Linux runners).
  echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' | sudo tee /etc/udev/rules.d/99-kvm4all.rules >/dev/null
  sudo udevadm control --reload-rules
  sudo udevadm trigger --name-match=kvm
}

emulator_install() {
  local sdkmanager="${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager"
  yes | "${sdkmanager}" --licenses >/dev/null 2>&1 || true
  "${sdkmanager}" --install emulator platform-tools "${EMULATOR_IMAGE}" >/dev/null
  # Explicit, so the emulator finds the AVD whatever HOME the process that boots it sees.
  export ANDROID_AVD_HOME="${ANDROID_AVD_HOME:-${HOME}/.android/avd}"
  mkdir -p "${ANDROID_AVD_HOME}"
  echo no | "${ANDROID_HOME}/cmdline-tools/latest/bin/avdmanager" create avd --force -n verify -k "${EMULATOR_IMAGE}" >/dev/null
  test -f "${ANDROID_AVD_HOME}/verify.ini" || { echo "::error title=[VERIFY] emulator::AVD not created in ${ANDROID_AVD_HOME}"; return 1; }
  adb start-server >/dev/null 2>&1
}

# emulator_system_uids <`cmd package list packages -s -U` output>: system apps' UIDs >= 10000, unique.
emulator_system_uids() {
  printf '%s\n' "$1" | tr -d '\r' | sed -n 's/.* uid:\([0-9,]*\).*/\1/p' | tr ',' '\n' \
    | awk '$1 >= 10000' | sort -un
}

# Stops Android's own background traffic inside the guest, where it can be told apart from the app's
# (on the host every packet comes from the emulator process). Needs adb root (the default image
# allows it): loopback and DNS pass; system UIDs (below 10000, and each system app's) are rejected.
# Apps installed later (the app under test, a test build) are untouched, so their traffic still
# reaches the host's block and is counted.
emulator_guest_quiet() {
  local uids u ipt rule cmd=""
  local -a rules
  adb root >/dev/null 2>&1 || return 0
  timeout 60 adb wait-for-device >/dev/null 2>&1 || return 0
  uids="$(emulator_system_uids "$(adb shell cmd package list packages -s -U 2>/dev/null)")"
  rules=("-N verify_quiet" "-A verify_quiet -o lo -j ACCEPT" "-A verify_quiet -p udp --dport 53 -j ACCEPT"
    "-A verify_quiet -p tcp --dport 53 -j ACCEPT" "-A verify_quiet -m owner --uid-owner 0-9999 -j REJECT")
  for u in ${uids}; do rules+=("-A verify_quiet -m owner --uid-owner ${u} -j REJECT"); done
  rules+=("-I OUTPUT 1 -j verify_quiet")
  for ipt in iptables ip6tables; do
    for rule in "${rules[@]}"; do cmd="${cmd}${ipt} -w ${rule}; "; done
  done
  adb shell "${cmd}" >/dev/null 2>&1 || true
  echo "[VERIFY] emulator: Android's own traffic stopped in the guest ($(wc -w <<< "${uids}" | tr -d ' ') system app UIDs + UIDs below 10000)"
}

# verify_mem <label>: one line of `free -m` in the step log (memory is what runs a hosted runner out).
verify_mem() {
  free -m 2>/dev/null | awk -v l="$1" '/^Mem:/ {t = $2; u = $3; a = $7} /^Swap:/ {s = $3}
    END {if (t) printf "[VERIFY] memory (%s): total %s MB, used %s MB, available %s MB, swap used %s MB\n", l, t, u, a, s + 0}'
}

verify_infra_fail() {
  echo "::error title=[VERIFY] emulator::$1 (infrastructure, not the app)"
  echo "**$1 (infrastructure, not the app)**" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
  exit 2
}

# _emulator_wait <seconds>: 0 once sys.boot_completed is 1; 1 at the timeout, or at once when the
# emulator process (EMULATOR_PID) has exited, e.g. on "Unknown AVD name".
_emulator_wait() {
  local end=$((SECONDS + $1))
  while [ "${SECONDS}" -lt "${end}" ]; do
    if [ -n "${EMULATOR_PID:-}" ] && ! kill -0 "${EMULATOR_PID}" 2>/dev/null; then return 1; fi
    if [ "$(adb get-state 2>/dev/null)" = device ] \
      && [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; then
      return 0
    fi
    sleep 2
  done
  return 1
}

_emulator_listed() { adb devices 2>/dev/null | grep -q '^emulator-'; }

emulator_stop() {
  adb emu kill >/dev/null 2>&1 || true
  for _ in $(seq 1 15); do _emulator_listed || return 0; sleep 2; done
  pkill -9 -u "$(id -u)" -f 'qemu-system-x86_64' 2>/dev/null || true
  for _ in $(seq 1 10); do _emulator_listed || return 0; sleep 2; done
}

emulator_boot() {
  local attempt rc1=1 rc2=- rc
  for attempt in 1 2; do
    "$@" emulator -avd verify -no-window -no-audio -no-boot-anim -no-snapshot -no-metrics -memory "${EMULATOR_MEMORY_MB}" \
      -gpu swiftshader_indirect -camera-back none -camera-front none > "${EMULATOR_LOG_DIR}/emulator-${attempt}.log" 2>&1 &
    EMULATOR_PID=$!
    if _emulator_wait "${EMULATOR_BOOT_SECONDS}"; then rc=0; else rc=1; fi
    if [ "${attempt}" = 1 ]; then rc1=${rc}; else rc2=${rc}; fi
    case "$(emulator_boot_verdict "${rc1}" "${rc2}")" in
      booted)
        # Animations off, as emulator-runner does: fewer timing flakes in UI tests.
        for k in window_animation_scale transition_animation_scale animator_duration_scale; do
          adb shell settings put global "${k}" 0 >/dev/null 2>&1 || true
        done
        # Android's own background traffic (private DNS, captive-portal checks, network time) would
        # otherwise be blocked and counted as the app's. The caller resets the block's counters next.
        adb shell settings put global private_dns_mode off >/dev/null 2>&1 || true
        adb shell settings put global captive_portal_mode 0 >/dev/null 2>&1 || true
        adb shell settings put global captive_portal_detection_enabled 0 >/dev/null 2>&1 || true
        adb shell settings put global auto_time 0 >/dev/null 2>&1 || true
        # Network validation probes Google (generate_204) and keeps retrying while blocked: point the
        # probes at the emulator's own loopback, then reconnect so the network monitor reads them.
        for k in captive_portal_http_url captive_portal_https_url captive_portal_fallback_url \
          captive_portal_other_fallback_urls; do
          adb shell settings put global "${k}" http://127.0.0.1:9/generate_204 >/dev/null 2>&1 || true
        done
        adb shell cmd connectivity airplane-mode enable >/dev/null 2>&1 || true
        sleep 3
        adb shell cmd connectivity airplane-mode disable >/dev/null 2>&1 || true
        sleep 5
        emulator_guest_quiet
        echo "[VERIFY] emulator: booted (attempt ${attempt})"
        return 0
        ;;
      retry)
        echo "::warning title=[VERIFY] emulator::the Android emulator did not boot within ${EMULATOR_BOOT_SECONDS} s; retrying once"
        tail -n 20 "${EMULATOR_LOG_DIR}/emulator-1.log"
        emulator_stop
        ;;
    esac
  done
  tail -n 40 "${EMULATOR_LOG_DIR}/emulator-2.log"
  verify_infra_fail "the Android emulator did not boot after 2 attempts"
}
