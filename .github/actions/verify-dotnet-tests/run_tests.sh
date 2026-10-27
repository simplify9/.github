#!/usr/bin/env bash
# verify-dotnet-tests (see action.yml): run the unit or the integration test projects of an already
# built solution, as sorted by classify.py. Env: KIND (unit|integration), BUILD_TARGET, WORKDIR,
# RESULTS_DIR (empty: no TRX), GITHUB_OUTPUT. Sourced with RUN_TESTS_LIB=1 for the helpers
# (test_run_tests_docker.sh).
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# solution_projects <sln>: absolute paths of the projects in the solution (solution folders excluded).
solution_projects() {
  local dir p
  dir="$(cd "$(dirname "$1")" && pwd)"
  # shellcheck disable=SC1003 # tr maps Windows separators in the solution file to /
  dotnet sln "$1" list | sed -n '3,$p' | tr '\\' '/' | while IFS= read -r p; do
    [ -n "${p}" ] && realpath -m "${dir}/${p}"
  done
}

# filtered_solution <sln> <drop-file> <kind>: the solution to test. The original when none of the
# projects in <drop-file> is in it; otherwise a __verify_<kind> copy next to it without them.
filtered_solution() {
  local copy
  local -a drop=()
  mapfile -t drop < <(grep -Fxf <(solution_projects "$1") "$2" || true)
  if [ "${#drop[@]}" -eq 0 ]; then
    echo "$1"
    return 0
  fi
  copy="$(dirname "$1")/__verify_$3.${1##*.}"
  cp "$1" "${copy}"
  dotnet sln "${copy}" remove "${drop[@]}" >/dev/null
  echo "${copy}"
}

[ "${RUN_TESTS_LIB:-}" = 1 ] && return 0

set -euo pipefail
tmp="$(mktemp -d)"
cls() { python3 "${here}/classify.py" --dir "${WORKDIR}" "$@"; }
cls --kind integration > "${tmp}/integration"
cls --kind unit > "${tmp}/unit"
case "${KIND}" in
  unit)
    cls --kind refused --warn > "${tmp}/refused"
    cat "${tmp}/integration" "${tmp}/refused" > "${tmp}/drop"
    ;;
  integration)
    cls --kind refused > "${tmp}/refused"
    if ! grep -Fxqf <(solution_projects "${BUILD_TARGET}") "${tmp}/integration"; then
      echo "::notice title=[VERIFY] integration::no integration test projects (Testcontainers) in ${BUILD_TARGET}, skipped"
      echo "ran=false" >> "${GITHUB_OUTPUT}"
      exit 0
    fi
    cat "${tmp}/unit" "${tmp}/refused" > "${tmp}/drop"
    ;;
  *)
    echo "::error title=[VERIFY] tests::kind must be unit or integration, got '${KIND}'"
    exit 1
    ;;
esac
target="$(filtered_solution "${BUILD_TARGET}" "${tmp}/drop" "${KIND}")"
echo "[VERIFY] ${KIND} tests: dotnet test ${target}"
args=(test "${target}" --no-build -c Release)
[ -z "${RESULTS_DIR}" ] || args+=(--logger trx --results-directory "${RESULTS_DIR}")
echo "ran=true" >> "${GITHUB_OUTPUT}"
dotnet "${args[@]}"
