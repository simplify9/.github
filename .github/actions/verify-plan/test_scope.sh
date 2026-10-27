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
test_new_step_enforced_on_own_deadline() { eq "${FUNCNAME[0]}" "" "$(new_steps_tolerated 2026-11-10 2026-12-29)"; }
test_new_step_later_repo_deadline_wins() { eq "${FUNCNAME[0]}" network "$(new_steps_tolerated 2027-02-01 2027-01-15)"; }
test_new_step_no_repo_deadline_forever() { eq "${FUNCNAME[0]}" network "$(new_steps_tolerated '' 2030-01-01)"; }
test_effective_known_failing_merges() {
  eq "${FUNCNAME[0]}_before" "lint network" "$(effective_known_failing "lint network" 2026-11-10 2026-11-01)"
  eq "${FUNCNAME[0]}_repo_passed" "network" "$(effective_known_failing "lint network" 2026-11-10 2026-11-10)"
  eq "${FUNCNAME[0]}_all_passed" "" "$(effective_known_failing "lint" 2026-11-10 2027-01-01)"
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
  canon="github.event_name == 'workflow_dispatch' || github.base_ref == github.event.repository.default_branch || github.event.pull_request.user.login == inputs.bot-login"
  yml="${here}/../../workflows/verify.yml"
  plan="$(awk '/^  plan:/{f=1} f && /^    if: /{sub(/^    if: /,""); print; exit}' "$yml")"
  res="$(awk '/^  result:/{f=1} f && /FULL: /{sub(/.*FULL: \$\{\{ /,""); sub(/ \}\}$/,""); print; exit}' "$yml")"
  eq "${FUNCNAME[0]}_plan" "$canon" "$plan"
  eq "${FUNCNAME[0]}_result" "$canon" "$res"
}
for t in $(declare -F | awk '$3 ~ /^test_/ {print $3}'); do "$t"; done
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; else echo "${fails} FAILED"; exit 1; fi
