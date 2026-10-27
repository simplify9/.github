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
#                                 300 s; returns 2 with an "infrastructure" error when it never boots
#   emulator_stop
#   emulator_boot_verdict RC1 RC2|-   booted | retry | failed

EMULATOR_IMAGE="system-images;android-34;default;x86_64"
EMULATOR_BOOT_SECONDS=300
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

# _emulator_wait <seconds>: 0 once sys.boot_completed is 1.
_emulator_wait() {
  local end=$((SECONDS + $1))
  timeout "$1" adb wait-for-device >/dev/null 2>&1 || return 1
  while [ "${SECONDS}" -lt "${end}" ]; do
    [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] && return 0
    sleep 3
  done
  return 1
}

emulator_stop() {
  adb emu kill >/dev/null 2>&1 || true
  pkill -u "$(id -u)" -f 'qemu-system-x86_64' 2>/dev/null || true
  sleep 2
}

emulator_boot() {
  local attempt rc1=1 rc2=- rc
  for attempt in 1 2; do
    "$@" emulator -avd verify -no-window -no-audio -no-boot-anim -no-snapshot -gpu swiftshader_indirect \
      -camera-back none -camera-front none > "${RUNNER_TEMP}/emulator-${attempt}.log" 2>&1 &
    if _emulator_wait "${EMULATOR_BOOT_SECONDS}"; then rc=0; else rc=1; fi
    if [ "${attempt}" = 1 ]; then rc1=${rc}; else rc2=${rc}; fi
    case "$(emulator_boot_verdict "${rc1}" "${rc2}")" in
      booted)
        # Animations off, as emulator-runner does: fewer timing flakes in UI tests.
        for k in window_animation_scale transition_animation_scale animator_duration_scale; do
          adb shell settings put global "${k}" 0 >/dev/null 2>&1 || true
        done
        echo "[VERIFY] emulator: booted (attempt ${attempt})"
        return 0
        ;;
      retry)
        echo "::warning title=[VERIFY] emulator::the Android emulator did not boot within ${EMULATOR_BOOT_SECONDS} s; retrying once"
        tail -n 20 "${RUNNER_TEMP}/emulator-1.log"
        emulator_stop
        ;;
    esac
  done
  tail -n 40 "${RUNNER_TEMP}/emulator-2.log"
  echo "::error title=[VERIFY] emulator::the Android emulator did not boot after 2 attempts (infrastructure, not the app)"
  return 2
}
