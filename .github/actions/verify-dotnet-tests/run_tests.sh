#!/usr/bin/env bash
# verify-dotnet-tests (see action.yml): run the unit or the integration test projects of an already
# built solution, as sorted by classify.py. Env: KIND (unit|integration), BUILD_TARGET (empty: only
# report has=true|false for KIND, before any build), WORKDIR,
# RESULTS_DIR (empty: no TRX), GITHUB_OUTPUT. Sourced with RUN_TESTS_LIB=1 for the helpers
# (test_run_tests_docker.sh).
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# solution_projects <sln>: absolute paths of the projects in the solution (solution folders excluded).
# Returns 1 when `dotnet sln list` cannot read the solution.
solution_projects() {
  local dir p listed
  dir="$(cd "$(dirname "$1")" && pwd)"
  listed="$(dotnet sln "$1" list)" || return 1
  # shellcheck disable=SC1003 # tr maps Windows separators in the solution file to /
  sed -n '3,$p' <<< "${listed}" | tr '\\' '/' | while IFS= read -r p; do
    [ -n "${p}" ] && realpath -m "${dir}/${p}"
  done
  return 0
}

# filtered_solution <sln> <drop-file> <kind>: the solution to test. The original when none of the
# projects in <drop-file> is in it; otherwise a __verify_<kind> copy next to it without them.
filtered_solution() {
  local copy list
  local -a drop=()
  list="$(mktemp)"
  # Fail closed: a solution we cannot list is never tested unfiltered.
  if ! solution_projects "$1" > "${list}"; then
    echo "::error title=[VERIFY] tests::cannot list the projects of $1 (dotnet sln list failed); not running its tests unfiltered" >&2
    return 1
  fi
  mapfile -t drop < <(grep -Fxf "${list}" "$2" || true)
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
# Detection only (no build yet): does the working directory hold projects of this kind?
if [ -z "${BUILD_TARGET}" ]; then
  if [ -s "${tmp}/${KIND}" ]; then echo "has=true"; else echo "has=false"; fi >> "${GITHUB_OUTPUT}"
  exit 0
fi
case "${KIND}" in
  unit)
    cls --kind refused --warn > "${tmp}/refused"
    cat "${tmp}/integration" "${tmp}/refused" > "${tmp}/drop"
    ;;
  integration)
    cls --kind refused > "${tmp}/refused"
    if ! solution_projects "${BUILD_TARGET}" > "${tmp}/solution"; then
      echo "::error title=[VERIFY] tests::cannot list the projects of ${BUILD_TARGET} (dotnet sln list failed); not running its tests unfiltered"
      exit 1
    fi
    if ! grep -Fxqf "${tmp}/solution" "${tmp}/integration"; then
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
set +e
dotnet "${args[@]}"
rc=$?
set -e
# Two solution files in one folder break a Dockerfile's `COPY *.sln . && dotnet restore` (MSB1011).
[ "${target}" = "${BUILD_TARGET}" ] || rm -f "${target}"
exit "${rc}"
