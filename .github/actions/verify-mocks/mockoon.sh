#!/usr/bin/env bash
# Mockoon for verify's end-to-end steps (sourced; tested by test_mockoon.sh). Used by
# verify-web-e2e and verify-maestro. Needs RUNNER_TEMP.
#
#   mockoon_install                        install the pinned CLI (before the network block)
#   mockoon_start FILE [PREFIX...]         serve FILE on 127.0.0.1:$MOCKOON_PORT with proxying off,
#                                          run through PREFIX (e.g. netblock_run); sets MOCKOON_PID;
#                                          returns 1 and prints the log when it does not come up

MOCKOON_VERSION=9.9.0
MOCKOON_PORT=3901

mockoon_install() {
  npm i --no-save --no-audit --no-fund --prefix "${RUNNER_TEMP}/mockoon" "@mockoon/cli@${MOCKOON_VERSION}" >/dev/null
}

mockoon_start() {
  local file="$1" log="${RUNNER_TEMP}/mockoon.log"
  shift
  "$@" "${RUNNER_TEMP}/mockoon/node_modules/.bin/mockoon-cli" start -d "${file}" -p "${MOCKOON_PORT}" \
    -l 127.0.0.1 --proxy disabled --disable-admin-api -X -r > "${log}" 2>&1 &
  MOCKOON_PID=$!
  for _ in $(seq 1 30); do
    (echo > "/dev/tcp/127.0.0.1/${MOCKOON_PORT}") 2>/dev/null && return 0
    kill -0 "${MOCKOON_PID}" 2>/dev/null || break
    sleep 1
  done
  cat "${log}"
  echo "::error title=[VERIFY] e2e::Mockoon did not serve ${file} on port ${MOCKOON_PORT} (log above)"
  return 1
}
