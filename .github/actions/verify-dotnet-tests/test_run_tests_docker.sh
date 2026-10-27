#!/usr/bin/env bash
# run_tests.sh against the real .NET 10 SDK: re-runs itself in mcr.microsoft.com/dotnet/sdk:10.0.
# Builds a solution with a unit, a Testcontainers, a refused and an orphan test project (the
# Testcontainers project never starts a container) and checks which ones each kind runs, for .sln
# and .slnx. Needs network for NuGet. Skips without Docker.
# Run: bash .github/actions/verify-dotnet-tests/test_run_tests_docker.sh
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fails=0
eq() { # name expected actual
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: expected '$2' got '$3'"; fails=$((fails + 1)); fi
}

make_repo() { # dir format
  mkdir -p "$1" && cd "$1" || exit 1
  dotnet new classlib -n Lib -o src/Lib >/dev/null
  for t in Unit Db Real Orphan; do dotnet new xunit -n "$t.Tests" -o "tests/$t.Tests" --no-restore >/dev/null; done
  for t in Db Real Orphan; do
    cat > "tests/$t.Tests/UnitTest1.cs" <<CS
namespace $t.Tests;
public class UnitTest1 { [Fact] public void MustNotRunInUnit() => Assert.Fail("$t.Tests ran"); }
CS
  done
  sed -i 's#</Project>#<ItemGroup><PackageReference Include="Testcontainers.PostgreSql" Version="4.16.0" /></ItemGroup></Project>#' tests/Db.Tests/Db.Tests.csproj
  printf '{\n  "ConnectionStrings": { "Default": "Host=db.example.co;Database=app;Password=n0tlocal-pw" }\n}\n' > tests/Real.Tests/appsettings.json
  dotnet new sln -n App --format "$2" >/dev/null
  dotnet sln "App.$2" add src/Lib/Lib.csproj tests/Unit.Tests/Unit.Tests.csproj tests/Db.Tests/Db.Tests.csproj tests/Real.Tests/Real.Tests.csproj >/dev/null
  dotnet build "App.$2" -c Release >/dev/null 2>&1 || { echo "FAIL build $2"; exit 1; }
}

names() { sed 's#.*/##; s#\.csproj$##' | sort | tr '\n' ' ' | sed 's/ $//'; }

inner() {
  for fmt in sln slnx; do
    make_repo "/tmp/repo-$fmt" "$fmt"
    # shellcheck source=run_tests.sh
    RUN_TESTS_LIB=1 source "${here}/run_tests.sh"
    eq "${fmt}_solution_projects" "Db.Tests Lib Real.Tests Unit.Tests" "$(solution_projects "App.$fmt" | names)"
    out="$(KIND=unit BUILD_TARGET="App.$fmt" WORKDIR=. RESULTS_DIR="" GITHUB_OUTPUT=/tmp/out-u-$fmt bash "${here}/run_tests.sh" 2>&1)"
    eq "${fmt}_unit_rc" 0 $?
    eq "${fmt}_unit_runs_only_unit" 1 "$(grep -c 'Passed!.*Unit.Tests.dll' <<< "${out}")"
    eq "${fmt}_unit_names_refused" 1 "$(grep -c 'tests/Real.Tests/Real.Tests.csproj is not run' <<< "${out}")"
    eq "${fmt}_unit_ran" "ran=true" "$(cat /tmp/out-u-$fmt)"
    out="$(KIND=integration BUILD_TARGET="App.$fmt" WORKDIR=. RESULTS_DIR=/tmp/trx-$fmt GITHUB_OUTPUT=/tmp/out-i-$fmt bash "${here}/run_tests.sh" 2>&1)"
    eq "${fmt}_integration_fails_on_db_only" "1 0 0" "$(grep -c 'Db.Tests ran' <<< "${out}") $(grep -c 'Real.Tests ran' <<< "${out}") $(grep -c 'Unit.Tests.dll' <<< "${out}")"
    eq "${fmt}_trx_written" 1 "$(find /tmp/trx-$fmt -name '*.trx' | wc -l | tr -d ' ')"
    eq "${fmt}_no_copy_left_dirty" "App.$fmt" "$(filtered_solution "App.$fmt" /dev/null unit)"
    KIND=integration BUILD_TARGET="" WORKDIR=. RESULTS_DIR="" GITHUB_OUTPUT=/tmp/out-d-$fmt bash "${here}/run_tests.sh" >/dev/null 2>&1
    eq "${fmt}_detect_has" "has=true" "$(cat /tmp/out-d-$fmt)"
    cd / || exit 1
  done
  mkdir -p /tmp/none && cd /tmp/none && dotnet new classlib -n Only -o src/Only >/dev/null && dotnet new sln -n N --format sln >/dev/null \
    && dotnet sln N.sln add src/Only/Only.csproj >/dev/null && dotnet build N.sln -c Release >/dev/null 2>&1
  out="$(KIND=integration BUILD_TARGET=N.sln WORKDIR=. RESULTS_DIR="" GITHUB_OUTPUT=/tmp/out-n bash "${here}/run_tests.sh" 2>&1)"
  eq none_integration_rc 0 $?
  eq none_integration_ran "ran=false" "$(cat /tmp/out-n)"
  eq none_integration_notice 1 "$(grep -c 'no integration test projects' <<< "${out}")"
  KIND=integration BUILD_TARGET="" WORKDIR=. RESULTS_DIR="" GITHUB_OUTPUT=/tmp/out-nd bash "${here}/run_tests.sh" >/dev/null 2>&1
  eq none_detect_has "has=false" "$(cat /tmp/out-nd)"
}

case "${1:-}" in
  --inner) inner ;;
  *)
    if ! docker info >/dev/null 2>&1; then echo "::notice::Docker not available; skipping"; exit 0; fi
    docker run --rm -v "${here}/..:/actions:ro" -e DOTNET_CLI_TELEMETRY_OPTOUT=1 -e DOTNET_NOLOGO=1 \
      mcr.microsoft.com/dotnet/sdk:10.0 bash -c 'apt-get update -qq >/dev/null 2>&1; apt-get install -y -qq python3 >/dev/null 2>&1; bash /actions/verify-dotnet-tests/test_run_tests_docker.sh --inner'
    exit $?
    ;;
esac
if [ "${fails}" -eq 0 ]; then echo "ALL PASS"; else echo "${fails} FAILED"; exit 1; fi
