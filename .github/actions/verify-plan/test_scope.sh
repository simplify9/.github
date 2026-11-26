#!/usr/bin/env bash
# Truth table for the scope rules in scope.sh, plus a drift guard for the full-scope
# expression copied in verify.yml. Run: bash .github/actions/verify-plan/test_scope.sh
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scope.sh
source "${here}/scope.sh"
fails=0
eq() { # name expected actual
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: expected '$2' got '$3'"; fails=$((fails + 1)); fi
}
BOT='s9-deps-bot[bot]'
test_scope_main_human_full() { eq "${FUNCNAME[0]}" true "$(verify_full pull_request main main alice "$BOT")"; }
test_scope_develop_human_skipped() { eq "${FUNCNAME[0]}" false "$(verify_full pull_request develop main alice "$BOT")"; }
test_scope_bot_author_full() { eq "${FUNCNAME[0]}" true "$(verify_full pull_request develop main "$BOT" "$BOT")"; }
test_scope_dispatch_full() { eq "${FUNCNAME[0]}" true "$(verify_full workflow_dispatch '' main '' "$BOT")"; }
test_scope_nondefault_main_name() { eq "${FUNCNAME[0]}" true "$(verify_full pull_request releases/r8.0 releases/r8.0 alice "$BOT")"; }
test_scope_develop_human_tests_changed_full() { eq "${FUNCNAME[0]}" true "$(verify_full pull_request develop main alice "$BOT" true)"; }
test_scope_develop_human_tests_unchanged_skipped() { eq "${FUNCNAME[0]}" false "$(verify_full pull_request develop main alice "$BOT" false)"; }
# A Node version file is a dependency: React Native and web build on the Node it names, so a bump gets
# the full ladder, including the emulator journeys.
test_deps_changed_nvmrc() { eq "${FUNCNAME[0]}" true "$(deps_changed_from_list '.nvmrc')"; }
test_deps_changed_node_version_nested() { eq "${FUNCNAME[0]}" true "$(deps_changed_from_list $'README.md\napps/mobile/.node-version')"; }
test_deps_changed_nvmrc_lookalike() { eq "${FUNCNAME[0]}" false "$(deps_changed_from_list $'docs/nvmrc.md\n.nvmrc.bak')"; }
# tests_changed_from_list <files> [stack]: journey/integration test files send a human develop PR through the full ladder
test_tests_changed_maestro() { eq "${FUNCNAME[0]}" true "$(tests_changed_from_list $'src/App.tsx\n.maestro/login.yaml' react-native)"; }
test_tests_changed_e2e_nested() { eq "${FUNCNAME[0]}" true "$(tests_changed_from_list $'apps/web/e2e/login.spec.ts' web)"; }
test_tests_changed_e2e_mocks() { eq "${FUNCNAME[0]}" true "$(tests_changed_from_list $'e2e/mocks.json' flutter)"; }
test_tests_changed_flutter_integration() { eq "${FUNCNAME[0]}" true "$(tests_changed_from_list $'integration_test/app_test.dart' flutter)"; }
test_tests_changed_playwright_config() { eq "${FUNCNAME[0]}" true "$(tests_changed_from_list $'playwright.config.mjs' web)"; }
test_tests_changed_dotnet_test_project() { eq "${FUNCNAME[0]}" true "$(tests_changed_from_list $'SW.Api.IntegrationTests/HealthTests.cs' dotnet-service)"; }
test_tests_changed_dotnet_tests_integration_dir() { eq "${FUNCNAME[0]}" true "$(tests_changed_from_list $'tests/integration/CounterStoreTests.cs' dotnet-library)"; }
test_tests_changed_dotnet_nested_integration_project() { eq "${FUNCNAME[0]}" true "$(tests_changed_from_list $'tests/Sbx.IntegrationTests/DbTests.cs' dotnet-service)"; }
# Unit and contract test projects are not journey or integration tests: a human develop PR that changes
# them passes at once, like any other develop PR (gig-onlineselling-api #237 changed only a UnitTests file).
test_tests_changed_false_dotnet_unit_project() { eq "${FUNCNAME[0]}" false "$(tests_changed_from_list $'SW.GigOnlineSelling.UnitTests/MotorInspectionTests.cs\nSW.GigOnlineSelling.Web/Services/MotorInspection/MotorInspectionRules.cs\nSW.GigOnlineSelling.Web/BusConsumers/PolicySubmitedIntegrationHandler.cs' dotnet-service)"; }
test_tests_changed_false_dotnet_tests_unit_dir() { eq "${FUNCNAME[0]}" false "$(tests_changed_from_list $'tests/Unit/CounterTests.cs\ntests/Sbx.Tests/SbxTests.cs' dotnet-library)"; }
test_tests_changed_false_dotnet_contract_project() { eq "${FUNCNAME[0]}" false "$(tests_changed_from_list $'SW.TraxisShip.ContractTests/ShipmentContractTests.cs' dotnet-service)"; }
test_tests_changed_false_dotnet_app_integrations_dir() { eq "${FUNCNAME[0]}" false "$(tests_changed_from_list $'SW.Api/Integrations/PaymentGateway.cs' dotnet-service)"; }
test_tests_changed_dotnet_dir_only_for_dotnet() { eq "${FUNCNAME[0]}" false "$(tests_changed_from_list $'SW.Api.IntegrationTests/HealthTests.cs' web)"; }
test_tests_changed_false_unit_tests_mobile() { eq "${FUNCNAME[0]}" false "$(tests_changed_from_list $'__tests__/App.test.tsx\nsrc/screens/Login.tsx' react-native)"; }
test_tests_changed_false_lowercase_suffix() { eq "${FUNCNAME[0]}" false "$(tests_changed_from_list $'src/Latest/Feed.cs\nsrc/Contests/List.cs' dotnet-service)"; }
test_tests_changed_false_app_only() { eq "${FUNCNAME[0]}" false "$(tests_changed_from_list $'src/index.ts\nREADME.md' web)"; }
test_known_failing_before_deadline() { eq "${FUNCNAME[0]}" "lint test" "$(known_failing_effective "lint test" 2026-12-20 2026-12-19)"; }
test_known_failing_on_deadline() { eq "${FUNCNAME[0]}" "" "$(known_failing_effective "lint test" 2026-12-20 2026-12-20)"; }
test_known_failing_after_deadline() { eq "${FUNCNAME[0]}" "" "$(known_failing_effective "lint" 2026-12-20 2027-01-01)"; }
test_known_failing_no_deadline() { eq "${FUNCNAME[0]}" "lint" "$(known_failing_effective "lint" "" 2027-01-01)"; }
test_contract_mode() {
  eq "${FUNCNAME[0]}_warn" warn "$(contract_mode 2026-12-20 2026-12-19)"
  eq "${FUNCNAME[0]}_enforce" enforce "$(contract_mode 2026-12-20 2026-12-20)"
  eq "${FUNCNAME[0]}_none" warn "$(contract_mode '' 2027-01-01)"
}
test_new_step_tolerated_before_own_deadline() { eq "${FUNCNAME[0]}" network "$(new_steps_tolerated 2026-11-10 2026-12-01)"; }
test_new_step_enforced_on_own_deadline() { eq "${FUNCNAME[0]}" "" "$(new_steps_tolerated 2026-11-10 2026-12-29 dotnet-service)"; }
test_new_step_later_repo_deadline_wins() { eq "${FUNCNAME[0]}" network "$(new_steps_tolerated 2027-02-01 2027-01-15)"; }
test_new_step_no_repo_deadline_forever() { eq "${FUNCNAME[0]}" network "$(new_steps_tolerated '' 2030-01-01)"; }
test_effective_known_failing_merges() {
  eq "${FUNCNAME[0]}_before" "lint network" "$(effective_known_failing "lint network" 2026-11-10 2026-11-01)"
  eq "${FUNCNAME[0]}_repo_passed" "network" "$(effective_known_failing "lint network" 2026-11-10 2026-11-10)"
  eq "${FUNCNAME[0]}_all_passed" "" "$(effective_known_failing "lint" 2026-11-10 2027-01-01)"
}
test_smoke_scoped_to_dotnet_service() {
  eq "${FUNCNAME[0]}_service" "network smoke" "$(new_steps_tolerated 2026-11-20 2026-12-01 dotnet-service)"
  eq "${FUNCNAME[0]}_library" "network" "$(new_steps_tolerated 2026-11-20 2026-12-01 dotnet-library)"
  eq "${FUNCNAME[0]}_web" "network" "$(new_steps_tolerated 2026-11-20 2026-12-01 web)"
  eq "${FUNCNAME[0]}_on_deadline" "" "$(new_steps_tolerated 2026-11-20 2026-12-29 dotnet-service)"
  eq "${FUNCNAME[0]}_effective" "docker network smoke" "$(effective_known_failing docker 2026-12-21 2026-12-01 dotnet-service)"
}
test_stack_entry_does_not_leak_to_other_stacks() {
  # shellcheck disable=SC2034 # read by new_steps_tolerated through bash dynamic scope
  local NEW_STEPS="flutter:e2e:2026-12-29 *:network:2026-12-29"
  eq "${FUNCNAME[0]}_web" "network" "$(new_steps_tolerated '' 2026-12-01 web)"
  eq "${FUNCNAME[0]}_flutter" "e2e network" "$(new_steps_tolerated '' 2026-12-01 flutter)"
  eq "${FUNCNAME[0]}_no_stack" "network" "$(new_steps_tolerated '' 2026-12-01)"
}
test_flutter_e2e_tolerated_for_flutter() {
  eq "${FUNCNAME[0]}" "e2e" "$(new_steps_tolerated 2026-11-20 2026-12-01 flutter | tr ' ' '\n' | grep -x e2e)"
  eq "${FUNCNAME[0]}_on_deadline" "" "$(new_steps_tolerated 2026-11-20 2026-12-29 flutter | tr ' ' '\n' | grep -x e2e)"
}
test_flutter_e2e_not_tolerated_for_web() {
  eq "${FUNCNAME[0]}" "" "$(new_steps_tolerated '' 2026-12-01 web | tr ' ' '\n' | grep -x e2e)"
  eq "${FUNCNAME[0]}_effective" "lint network" "$(effective_known_failing "lint" '' 2026-12-01 web)"
}
test_repo_known_failing_excludes_new_steps() { eq "${FUNCNAME[0]}" "test" "$(known_failing_effective "test" 2027-02-01 2026-12-01)"; }
test_integration_is_not_a_new_step() {
  case " $(new_steps_tolerated '' 2026-12-01) " in *" integration "*) eq "${FUNCNAME[0]}" absent present ;; *) eq "${FUNCNAME[0]}" absent absent ;; esac
}
test_deps_changed_manifest() { eq "${FUNCNAME[0]}" true "$(deps_changed_from_list $'src/a.cs\nweb/package.json')"; }
test_deps_changed_none() { eq "${FUNCNAME[0]}" false "$(deps_changed_from_list $'src/a.cs\nREADME.md')"; }
test_deps_changed_empty() { eq "${FUNCNAME[0]}" false "$(deps_changed_from_list '')"; }
test_deps_changed_large_list() {
  # >100KB list with the match first: a pipe into `grep -q` would SIGPIPE under pipefail.
  big="$(printf 'package.json\n'; yes 'some/long/path/to/an/unrelated/source/file.txt' | head -n 4000)"
  [ "${#big}" -gt 100000 ] || echo "FAIL list too small"
  set -o pipefail
  eq "${FUNCNAME[0]}" true "$(deps_changed_from_list "$big")"
  set +o pipefail
}
test_strapi_changed_true() {
  eq "${FUNCNAME[0]}" true "$(strapi_changed_from_pr $'src/a.js\npackage.json')"
}
test_strapi_changed_lockfile_only() {
  eq "${FUNCNAME[0]}" true "$(strapi_changed_from_pr $'package-lock.json')"
}
test_strapi_changed_no_package_json() { eq "${FUNCNAME[0]}" false "$(strapi_changed_from_pr $'src/a.js\nREADME.md')"; }
test_strapi_changed_migration() { eq "${FUNCNAME[0]}" true "$(strapi_changed_from_pr $'database/migrations/2026-p10b.js')"; }
test_strapi_changed_content_type_schema() { eq "${FUNCNAME[0]}" true "$(strapi_changed_from_pr $'cms/src/api/article/content-types/article/schema.json')"; }
test_strapi_changed_component() { eq "${FUNCNAME[0]}" true "$(strapi_changed_from_pr $'src/components/shared/seo.json')"; }
test_strapi_changed_false_other_src() { eq "${FUNCNAME[0]}" false "$(strapi_changed_from_pr $'src/api/article/controllers/article.js\nsrc/index.js')"; }
test_scope_expression_copies_identical() {
  # base: the v1 full-scope rule. canon adds the probe's answer. The probe has NO if: it must never be
  # skipped, because a skipped ancestor skips every ladder below it (#225).
  local base="github.event_name == 'workflow_dispatch' || github.base_ref == github.event.repository.default_branch || github.event.pull_request.user.login == inputs.bot-login"
  local canon="${base} || needs.tests-probe.outputs.tests_changed == 'true'"
  local yml="${here}/../../workflows/verify.yml" probe plan res
  probe="$(awk '/^  tests-probe:/{f=1; next} f && /^  [a-z][a-z-]*:$/{exit} f && /^    if: /{sub(/^    if: /,""); print; exit}' "$yml")"
  plan="$(awk '/^  plan:/{f=1} f && /^    if: /{sub(/^    if: /,""); print; exit}' "$yml")"
  res="$(awk '/^  result:/{f=1} f && /FULL: /{sub(/.*FULL: \$\{\{ /,""); sub(/ \}\}$/,""); print; exit}' "$yml")"
  eq "${FUNCNAME[0]}_probe_has_no_if" "" "$probe"
  eq "${FUNCNAME[0]}_plan" "\${{ !cancelled() && (${canon}) }}" "$plan"
  eq "${FUNCNAME[0]}_result" "$canon" "$res"
}
# step_block <job> <step-id>: the lines of that step in verify.yml (empty when absent)
step_block() {
  awk -v job="  $1:" -v id="        id: $2" '
    $0 == job {j = 1; next}
    j && /^  [a-z][a-z-]*:$/ {exit}
    j && /^      - name:/ {if (hit) exit; buf = ""}
    j {buf = buf $0 "\n"}
    j && $0 == id {hit = 1}
    END {if (hit) printf "%s", buf}' "${here}/../../workflows/verify.yml"
}
test_integration_build_carries_build_tolerance() {
  local tol="contains(format(' {0} ', needs.plan.outputs.known_failing), ' build ')" step
  for step in "dotnet build" "integration build" "integration detect"; do
    # shellcheck disable=SC2086 # two words on purpose: job and step id
    case "$(step_block ${step})" in *"continue-on-error: \${{ ${tol} }}"*) eq "${FUNCNAME[0]}_${step// /_}" ok ok ;;
      *) eq "${FUNCNAME[0]}_${step// /_}" "build tolerance" "missing" ;; esac
  done
}
# job_if <job>: that job's if: expression in verify.yml
job_if() {
  awk -v job="  $1:" '$0 == job {f = 1; next} f && /^  [a-z][a-z-]*:$/ {exit} f && /^    if: / {sub(/^    if: /, ""); print; exit}' \
    "${here}/../../workflows/verify.yml"
}
test_emulator_journeys_run_when_tests_changed() {
  # A human develop PR that changes only Maestro flows or Flutter integration tests gets the full
  # ladder (tests-probe). The emulator jobs must then run those tests: before, they also required a
  # dependency change or a PR into the default branch, so the changed tests were skipped and result passed.
  local j
  for j in maestro flutter-e2e; do
    case "$(job_if "$j")" in *"needs.plan.outputs.tests_changed == 'true'"*) eq "${FUNCNAME[0]}_${j}" ok ok ;;
      *) eq "${FUNCNAME[0]}_${j}" "runs when tests_changed" "missing" ;; esac
  done
  case "$(awk '/^  plan:$/ {f = 1; next} f && /^  [a-z][a-z-]*:$/ {exit} f && /^      tests_changed: / {print; exit}' "${here}/../../workflows/verify.yml")" in
    *'steps.plan.outputs.tests_changed'*) eq "${FUNCNAME[0]}_plan_output" ok ok ;;
    *) eq "${FUNCNAME[0]}_plan_output" "plan exposes tests_changed" "missing" ;;
  esac
}
# iOS blocks from the day it shipped (2026-11-04), an exception to "new steps start tolerated": while
# tolerated, a lock refresh that breaks the iOS build would still be merged by the bot, which is how an
# enrolled app's iOS release builds broke in the first place. A repo can still list `ios` in known-failing.
test_ios_blocks_from_day_one() {
  case " $(new_steps_tolerated '' 2026-11-04 react-native) $(new_steps_tolerated 2026-12-21 2026-11-10 react-native) " in
    *" ios "*) eq "${FUNCNAME[0]}" "enforced" "tolerated" ;; *) eq "${FUNCNAME[0]}" ok ok ;; esac
}
test_ios_tolerated_only_when_listed() {
  case " $(effective_known_failing 'ios' 2026-12-21 2026-11-10 react-native) " in *" ios "*) eq "${FUNCNAME[0]}" ok ok ;; *) eq "${FUNCNAME[0]}" "listed ios tolerated" "missing" ;; esac
}
test_ios_job_scope_and_result_wiring() {
  # macOS minutes cost ~10x Linux: the iOS build runs when an iOS input changed (plan's ios_changed) or the PR
  # targets the default branch.
  case "$(job_if ios)" in
    *"inputs.stack == 'react-native'"*"needs.plan.outputs.ios_changed == 'true'"*"github.base_ref == github.event.repository.default_branch"*) eq "${FUNCNAME[0]}_if" ok ok ;;
    *) eq "${FUNCNAME[0]}_if" "react-native, iOS inputs changed or default branch" "$(job_if ios)" ;;
  esac
  case "$(awk '/^  result:$/ {f = 1} f && /^    needs:/ {print; exit}' "${here}/../../workflows/verify.yml")" in
    *" ios,"* | *" ios]"*) eq "${FUNCNAME[0]}_result_needs" ok ok ;; *) eq "${FUNCNAME[0]}_result_needs" "result needs ios" "missing" ;;
  esac
  case "$(awk '/^  plan:$/ {f = 1; next} f && /^  [a-z][a-z-]*:$/ {exit} f && /^      ios_changed: / {print; exit}' "${here}/../../workflows/verify.yml")" in
    *'steps.plan.outputs.ios_changed'*) eq "${FUNCNAME[0]}_plan_output" ok ok ;;
    *) eq "${FUNCNAME[0]}_plan_output" "plan exposes ios_changed" "missing" ;;
  esac
  case "$(step_block plan plan)" in *'working-directory: ${{ inputs.working-directory }}'*) eq "${FUNCNAME[0]}_working_directory" ok ok ;;
    *) eq "${FUNCNAME[0]}_working_directory" "plan gets working-directory (finds ios/Podfile.lock)" "missing" ;; esac
}
# ios_changed_from_list <files>: true when the PR changes an iOS build input outright, `packages` when only the
# JS packages changed (yarn.lock: the plan then compares the resolved versions with the app's native modules),
# else false. The JS bundle is built and Hermes-compiled for iOS by the react-native job on Linux; what only
# the macOS job checks is pod install and the native compile.
test_ios_changed_ios_dir() { eq "${FUNCNAME[0]}" true "$(ios_changed_from_list $'src/App.tsx\nios/Podfile.lock')"; }
test_ios_changed_nested_app() { eq "${FUNCNAME[0]}" true "$(ios_changed_from_list $'apps/mobile/ios/App/Info.plist')"; }
test_ios_changed_gemfile_lock() { eq "${FUNCNAME[0]}" true "$(ios_changed_from_list $'Gemfile.lock')"; }
test_ios_changed_ruby_version() { eq "${FUNCNAME[0]}" true "$(ios_changed_from_list $'.ruby-version')"; }
test_ios_changed_xcode_version() { eq "${FUNCNAME[0]}" true "$(ios_changed_from_list $'.xcode-version')"; }
test_ios_changed_node_version() { eq "${FUNCNAME[0]}" true "$(ios_changed_from_list $'.nvmrc')"; }
test_ios_changed_patches() { eq "${FUNCNAME[0]}" true "$(ios_changed_from_list $'patches/react-native-pdf+6.7.7.patch')"; }
test_ios_changed_rn_config() { eq "${FUNCNAME[0]}" true "$(ios_changed_from_list $'react-native.config.js')"; }
test_ios_changed_npm_lock_unreadable() { eq "${FUNCNAME[0]}" true "$(ios_changed_from_list $'package.json\npackage-lock.json')"; }
test_ios_changed_manifest_without_lock() { eq "${FUNCNAME[0]}" true "$(ios_changed_from_list $'package.json')"; }
test_ios_changed_yarn_lock_needs_packages() { eq "${FUNCNAME[0]}" packages "$(ios_changed_from_list $'package.json\nyarn.lock')"; }
test_ios_changed_false_android_only() { eq "${FUNCNAME[0]}" false "$(ios_changed_from_list $'android/build.gradle\nandroid/gradle/wrapper/gradle-wrapper.properties')"; }
test_ios_changed_false_js_source() { eq "${FUNCNAME[0]}" false "$(ios_changed_from_list $'src/screens/Login.tsx\nbabel.config.js\nREADME.md')"; }
test_ios_changed_false_lookalikes() { eq "${FUNCNAME[0]}" false "$(ios_changed_from_list $'docs/ios-setup.md\nsrc/iosHelpers.ts')"; }
# lock_changed_packages <base yarn.lock> <head yarn.lock>: names whose resolved versions differ (Yarn 1 and Berry)
YARN1_BASE='# THIS IS AN AUTOGENERATED FILE. DO NOT EDIT THIS FILE DIRECTLY.
# yarn lockfile v1


"@babel/core@^7.20.0", "@babel/core@^7.25.2":
  version "7.26.0"
  resolved "https://registry.yarnpkg.com/@babel/core/-/core-7.26.0.tgz"
  dependencies:
    "@babel/parser" "^7.26.0"

jest@^29.7.0:
  version "29.7.0"

react-native-gesture-handler@~2.20.0:
  version "2.20.2"

left-pad@^1.3.0:
  version "1.3.0"'
YARN1_HEAD='# yarn lockfile v1


"@babel/core@^7.20.0", "@babel/core@^7.25.2":
  version "7.26.0"
  dependencies:
    "@babel/parser" "^7.26.0"

jest@^30.0.0:
  version "30.0.5"

react-native-gesture-handler@~2.20.0:
  version "2.20.2"

ws@^8.18.0:
  version "8.18.3"'
test_lock_changed_packages_yarn1() {
  eq "${FUNCNAME[0]}" $'jest\nleft-pad\nws' "$(lock_changed_packages "$YARN1_BASE" "$YARN1_HEAD")"
}
test_lock_changed_packages_none() { eq "${FUNCNAME[0]}" "" "$(lock_changed_packages "$YARN1_BASE" "$YARN1_BASE")"; }
test_lock_changed_packages_scoped_and_berry() {
  local base='__metadata:
  version: 8

"@react-native/codegen@npm:0.79.1":
  version: 0.79.1
  dependencies:
    glob: "npm:^7.1.1"

"lodash@npm:^4.17.21, lodash@npm:^4.17.4":
  version: 4.17.21'
  local head="${base/version: 0.79.1/version: 0.79.2}"
  eq "${FUNCNAME[0]}" "@react-native/codegen" "$(lock_changed_packages "$base" "$head")"
}
# podfile_lock_packages <ios/Podfile.lock>: the JS packages whose native code the iOS app builds (autolinked)
PODFILE_LOCK='PODS:
  - boost (1.84.0)
  - RNGestureHandler (2.20.2):
    - React-Core

DEPENDENCIES:
  - RNGestureHandler (from `../node_modules/react-native-gesture-handler`)

EXTERNAL SOURCES:
  boost:
    :podspec: "../node_modules/react-native/third-party-podspecs/boost.podspec"
  RNCAsyncStorage:
    :path: "../node_modules/@react-native-async-storage/async-storage"
  RNGestureHandler:
    :path: "../node_modules/react-native-gesture-handler"
  card-sdk:
    :path: "../node_modules/card-sdk"

SPEC CHECKSUMS:
  boost: 1dca942403ed9342f98334bf4c3621f011aa7946'
test_podfile_lock_packages() {
  eq "${FUNCNAME[0]}" $'@react-native-async-storage/async-storage\ncard-sdk\nreact-native\nreact-native-gesture-handler' \
    "$(podfile_lock_packages "$PODFILE_LOCK")"
}
# ios_relevant_packages <changed names> <native names>: a changed native module, React Native itself, or any
# React Native or Expo package (one can gain native code in a new version, before Podfile.lock lists it)
test_ios_relevant_native_module() { eq "${FUNCNAME[0]}" true "$(ios_relevant_packages $'ws\ncard-sdk' $'card-sdk\nreact-native')"; }
test_ios_relevant_rn_named() { eq "${FUNCNAME[0]}" true "$(ios_relevant_packages $'react-native-country-picker-modal' $'react-native')"; }
test_ios_relevant_rn_scoped() { eq "${FUNCNAME[0]}" true "$(ios_relevant_packages $'@react-native-community/cli' '')"; }
test_ios_relevant_expo() { eq "${FUNCNAME[0]}" true "$(ios_relevant_packages $'expo-modules-core' '')"; }
test_ios_relevant_false_js_tools() { eq "${FUNCNAME[0]}" false "$(ios_relevant_packages $'jest\n@babel/core\nws\nprotobufjs' $'card-sdk\nreact-native')"; }
test_ios_relevant_false_none() { eq "${FUNCNAME[0]}" false "$(ios_relevant_packages '' $'react-native')"; }
test_ios_relevant_end_to_end() {
  eq "${FUNCNAME[0]}_js_only" false "$(ios_relevant_packages "$(lock_changed_packages "$YARN1_BASE" "$YARN1_HEAD")" "$(podfile_lock_packages "$PODFILE_LOCK")")"
  local head="${YARN1_HEAD/version \"2.20.2\"/version \"2.20.3\"}"
  eq "${FUNCNAME[0]}_native_bump" true "$(ios_relevant_packages "$(lock_changed_packages "$YARN1_BASE" "$head")" "$(podfile_lock_packages "$PODFILE_LOCK")")"
}
# Strict branches (renovate/strict-*): Renovate's developer-tool majors, which merge by themselves. They are
# judged as if the contract deadline were today: nothing in known-failing is tolerated and every contract item
# is enforced, so a tool that cannot run (ESLint 10 without eslint.config.*) turns the check red instead of
# "tolerated". Only a branch that starts with the prefix counts.
test_strict_branch_deadline_is_today() { eq "${FUNCNAME[0]}" 2026-11-17 "$(effective_deadline 2026-12-21 2026-11-17 renovate/strict-major-jest-monorepo)"; }
test_strict_branch_without_repo_deadline() { eq "${FUNCNAME[0]}" 2026-11-17 "$(effective_deadline '' 2026-11-17 renovate/strict-typescript-7.x)"; }
test_other_branch_keeps_deadline() { eq "${FUNCNAME[0]}" 2026-12-21 "$(effective_deadline 2026-12-21 2026-11-17 renovate/major-jest-monorepo)"; }
test_strict_prefix_must_lead() { eq "${FUNCNAME[0]}" 2026-12-21 "$(effective_deadline 2026-12-21 2026-11-17 feature/renovate/strict-x)"; }
test_no_branch_keeps_deadline() { eq "${FUNCNAME[0]}" '' "$(effective_deadline '' 2026-11-17 '')"; }
test_strict_branch_tolerates_no_listed_step() {
  local d; d="$(effective_deadline 2026-12-21 2026-11-17 renovate/strict-major-eslint-monorepo)"
  # `network` is a new step with its own deadline (2026-12-29): as for any repo past its deadline, it stays tolerated
  eq "${FUNCNAME[0]}" "network" "$(effective_known_failing "lint test typecheck" "$d" 2026-11-17 react-native)"
  eq "${FUNCNAME[0]}_mode" enforce "$(contract_mode "$d" 2026-11-17)"
}
# iOS toolchain branches (renovate/ios-toolchain, renovate/lock-file-maintenance-ios-toolchain) merge by themselves
# on react-native once verify's iOS build passes, so that build must block there even if the repo lists `ios`.
test_ios_toolchain_branch_drops_ios() { eq "${FUNCNAME[0]}" "lint test" "$(branch_known_failing "lint ios test" renovate/ios-toolchain)"; }
test_ios_toolchain_lock_refresh_drops_ios() { eq "${FUNCNAME[0]}" "" "$(branch_known_failing "ios" renovate/lock-file-maintenance-ios-toolchain)"; }
test_other_branch_keeps_ios() { eq "${FUNCNAME[0]}" "lint ios" "$(branch_known_failing "lint ios" renovate/non-major)"; }
test_no_branch_keeps_list() { eq "${FUNCNAME[0]}" "ios" "$(branch_known_failing "ios" '')"; }
test_plan_and_contract_use_the_branch_deadline() {
  # The contract job must read the plan's deadline (strict branches enforce the contract), and the plan must get
  # the branch name: the PR's head branch, or the dispatched branch.
  local yml="${here}/../../workflows/verify.yml"
  case "$(step_block contract contract)" in *'deadline: ${{ needs.plan.outputs.deadline }}'*) eq "${FUNCNAME[0]}_contract" ok ok ;;
    *) eq "${FUNCNAME[0]}_contract" "contract reads needs.plan.outputs.deadline" "missing" ;; esac
  case "$(step_block plan plan)" in *'head-ref: ${{ github.head_ref || github.ref_name }}'*) eq "${FUNCNAME[0]}_head_ref" ok ok ;;
    *) eq "${FUNCNAME[0]}_head_ref" "plan gets head-ref" "missing" ;; esac
  case "$(awk '/^  plan:$/ {f = 1; next} f && /^  [a-z][a-z-]*:$/ {exit} f && /^      deadline: / {print; exit}' "$yml")" in
    *'steps.plan.outputs.deadline'*) eq "${FUNCNAME[0]}_plan_output" ok ok ;;
    *) eq "${FUNCNAME[0]}_plan_output" "plan exposes deadline" "missing" ;; esac
}
# Every image verify builds gets the build args the deploy workflows give it (generic-*-helm-template.yml,
# "Assemble Docker build args"): NUGET_PACKAGE_PAT when the NuGet token is set, plus the caller's
# docker-build-args. Without them a Dockerfile that restores private NuGet packages, or that refuses to build
# without its VITE_*/NEXT_PUBLIC_* URLs, fails in verify although it ships fine, and `docker` gets tolerated.
test_docker_builds_get_the_deploy_build_args() {
  local site
  for site in "node docker" "dotnet docker"; do
    # shellcheck disable=SC2086 # two words on purpose: job and step id
    case "$(step_block ${site})" in
      *"build-args: |"*"secrets.nuget-restore-token"*"inputs.docker-build-args"*) eq "${FUNCNAME[0]}_${site// /_}" ok ok ;;
      *) eq "${FUNCNAME[0]}_${site// /_}" "build-args from the NuGet token and docker-build-args" "missing" ;;
    esac
  done
  for site in "node docker-more" "docker-smoke smoke"; do
    # shellcheck disable=SC2086
    case "$(step_block ${site})" in
      *"secrets.nuget-restore-token"*"inputs.docker-build-args"*"--build-arg"*) eq "${FUNCNAME[0]}_${site// /_}" ok ok ;;
      *) eq "${FUNCNAME[0]}_${site// /_}" "--build-arg from the NuGet token and docker-build-args" "missing" ;;
    esac
  done
  case "$(awk '/^      docker-build-args:$/ {f = 1; next} f && /^      [a-z]/ {exit} f' "${here}/../../workflows/verify.yml")" in
    *"type: string"*) eq "${FUNCNAME[0]}_input" ok ok ;; *) eq "${FUNCNAME[0]}_input" "docker-build-args input" "missing" ;;
  esac
}
test_android_gradle_cache_matches_deploy_build() {
  # actions/cache versions an entry by its path list: verify restores the deploy build's Gradle cache only
  # when both list the same Gradle User Home parts (it never did: verify lacked `wrapper`).
  local inc='/gradle-home-cache-includes:/ {f = 1; next} f && /^ +[a-z.-]+$/ {gsub(/ /, ""); printf "%s ", $0; next} f {exit}'
  eq "${FUNCNAME[0]}" "$(awk "${inc}" "${here}/../../workflows/android-build.yml")" \
    "$(awk '/^  android:$/ {j = 1} j' "${here}/../../workflows/verify.yml" | awk "${inc}")"
}
# gh_retry: a fake gh on PATH fails twice (printing a partial answer each time), then answers.
fake_gh() { # dir fails-before-success
  # shellcheck disable=SC2016 # the fake gh's own script: its $n expands when it runs, not here
  printf '#!/usr/bin/env bash\nn=$(cat "%s/n" 2>/dev/null || echo 0); echo $((n + 1)) > "%s/n"\n[ "$n" -ge %s ] || { echo partial; exit 1; }\necho ok\n' "$1" "$1" "$2" > "$1/gh"
  chmod +x "$1/gh"
}
test_gh_retry_recovers_without_partial_output() {
  local d; d="$(mktemp -d)"; fake_gh "$d" 2
  eq "${FUNCNAME[0]}" ok "$(PATH="$d:$PATH" GH_RETRY_DELAY=0 gh_retry api x)"; rm -rf "$d"
}
test_gh_retry_gives_up_after_three() {
  local d rc=0; d="$(mktemp -d)"; fake_gh "$d" 3
  PATH="$d:$PATH" GH_RETRY_DELAY=0 gh_retry api x > /dev/null || rc=$?
  eq "${FUNCNAME[0]}" "1 3" "${rc} $(cat "$d/n")"; rm -rf "$d"
}
for t in $(declare -F | awk '$3 ~ /^test_/ {print $3}'); do "$t"; done
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "${fails} FAILED"; exit 1; fi
