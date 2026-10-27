#!/usr/bin/env bash
# The web `e2e` step (see action.yml). Run from the project directory with RUNNER (yarn/npm/pnpm),
# ACTION_PATH and RUNNER_TEMP set. Sourced with E2E_SH_LIB=1 by test_e2e.sh for the helpers only.

# e2e_scan_targets <dir>: committed recordings and mocks to scan, relative to <dir>, sorted: every
# e2e/**/*.har, e2e/mocks.json, and every other file next to a .har (Playwright's default
# updateContent "attach" writes response bodies there), except source code and binary media.
e2e_scan_targets() {
  [ -d "$1/e2e" ] || return 0
  (
    cd "$1" || exit 1
    {
      [ -f e2e/mocks.json ] && echo e2e/mocks.json
      find e2e -type f -name '*.har' -exec dirname {} \; | LC_ALL=C sort -u | while IFS= read -r dir; do
        find "${dir}" -maxdepth 1 -type f \
          | grep -Ev '\.(ts|tsx|mts|cts|js|jsx|mjs|cjs|png|jpe?g|gif|webp|ico|svg|woff2?|ttf|otf|pdf|mp4|webm|zip)$' || true
      done
    } | LC_ALL=C sort -u
  )
}

# e2e_zip_recordings <dir>: zipped HAR recordings, which the scanner cannot read.
e2e_zip_recordings() {
  [ -d "$1/e2e" ] || return 0
  (cd "$1" && find e2e -type f -name '*.zip' | LC_ALL=C sort)
}

# e2e_verdict <rc> <blocked-count>: pass | fail (a real failure) | retry (the block may be the cause)
e2e_verdict() {
  if [ "$1" -eq 0 ]; then echo pass; elif [ "$2" -eq 0 ]; then echo fail; else echo retry; fi
}

# e2e_after_retry <rc of the unblocked run>: network (passes only with network access) | fail
e2e_after_retry() {
  if [ "$1" -eq 0 ]; then echo network; else echo fail; fi
}

[ "${E2E_SH_LIB:-}" = 1 ] && return 0

set -euo pipefail
# shellcheck source=../verify-netblock/netblock.sh
source "${ACTION_PATH}/../verify-netblock/netblock.sh"
MOCK_PORT=3901
log="${RUNNER_TEMP}/e2e.log"
mock_pid=""
trap '[ -z "${mock_pid}" ] || kill "${mock_pid}" 2>/dev/null || true' EXIT

mapfile -t zips < <(e2e_zip_recordings .)
if [ "${#zips[@]}" -gt 0 ]; then
  echo "::error title=[VERIFY] e2e::${zips[*]}: zipped recordings cannot be scanned for personal data; record with routeFromHAR(..., { update: true, updateContent: 'embed' }) and commit the .har"
  exit 1
fi
mapfile -t targets < <(e2e_scan_targets .)
if [ "${#targets[@]}" -gt 0 ]; then
  echo "[VERIFY] e2e: scanning ${targets[*]}"
  if ! python3 "${ACTION_PATH}/../verify-secret-scan/scan.py" "${targets[@]}"; then
    echo "::error title=[VERIFY] e2e::e2e recordings or mocks hold personal data or secrets (see above); remove or scrub the recording"
    exit 1
  fi
fi
netblock_hosts e2e/allowed-hosts.txt >/dev/null

# Everything that needs the internet happens before the block.
npx playwright install --with-deps chromium
if [ -f e2e/mocks.json ]; then
  npm i --no-save --no-audit --no-fund --prefix "${RUNNER_TEMP}/mockoon" @mockoon/cli@9.9.0 >/dev/null
fi

netblock_on e2e/allowed-hosts.txt
if [ -f e2e/mocks.json ]; then
  netblock_run "${RUNNER_TEMP}/mockoon/node_modules/.bin/mockoon-cli" start -d e2e/mocks.json -p "${MOCK_PORT}" \
    -l 127.0.0.1 --proxy disabled --disable-admin-api -X -r > "${RUNNER_TEMP}/mockoon.log" 2>&1 &
  mock_pid=$!
  for _ in $(seq 1 30); do
    (echo > "/dev/tcp/127.0.0.1/${MOCK_PORT}") 2>/dev/null && break
    sleep 1
  done
  if ! (echo > "/dev/tcp/127.0.0.1/${MOCK_PORT}") 2>/dev/null; then
    cat "${RUNNER_TEMP}/mockoon.log"
    echo "::error title=[VERIFY] e2e::Mockoon did not serve e2e/mocks.json on port ${MOCK_PORT} within 30 s (log above)"
    exit 1
  fi
  export E2E_API_URL="http://127.0.0.1:${MOCK_PORT}"
  echo "::notice title=[VERIFY] e2e::Mockoon serves e2e/mocks.json at ${E2E_API_URL}"
fi

# e2e_run [netblock_run]: test:e2e, blocked when given netblock_run; the log keeps the last run.
e2e_run() {
  set +e
  "$@" env CI=true VERIFY_E2E=1 NEXT_TELEMETRY_DISABLED=1 "${RUNNER}" run test:e2e 2>&1 | tee "${log}"
  rc=${PIPESTATUS[0]}
  set -e
}
e2e_run netblock_run
blocked="$(netblock_count)"
dests="$(netblock_blocked | tr '\n' ' ')"
dests="${dests% }"

case "$(e2e_verdict "${rc}" "${blocked}")" in
  pass)
    if [ "${blocked}" -gt 0 ]; then
      echo "::notice title=[VERIFY] network::e2e passed; the block rejected ${blocked} packet(s) to: ${dests:-unknown (kernel log unreadable)}"
    fi
    ;;
  retry)
    echo "::notice title=[VERIFY] network::e2e failed while the block rejected ${blocked} packet(s) to: ${dests:-unknown}; re-running once with network access to tell the two apart"
    e2e_run
    if [ "$(e2e_after_retry "${rc}")" = network ]; then
      echo "::warning title=[VERIFY] network::e2e passed only with network access; blocked: ${dests:-unknown}. Mock these calls, or list third-party SDK hosts in e2e/allowed-hosts.txt"
      echo "network=needed" >> "${GITHUB_OUTPUT}"
    else
      echo "::notice title=[VERIFY] network::e2e failed with network access too: a real failure"
    fi
    ;;
esac
python3 "${ACTION_PATH}/e2e_report.py" "${log}" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
exit "${rc}"
