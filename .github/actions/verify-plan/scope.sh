#!/usr/bin/env bash
# Scope helpers for verify.yml. Sourced by the verify-plan action and by test_scope.sh.
# All dates are ISO YYYY-MM-DD, compared as strings.

# verify_full <event> <base> <default-branch> <author> <bot-login> -> true|false
verify_full() {
  if [ "$1" = "workflow_dispatch" ] || [ "$2" = "$3" ] || [ "$4" = "$5" ]; then
    echo true
  else
    echo false
  fi
}

# known_failing_effective <list> <deadline> <today> -> the list before the deadline, else empty
known_failing_effective() {
  if [ -z "$2" ] || [[ "$3" < "$2" ]]; then echo "$1"; else echo ""; fi
}

# Step ids added after v1 (spec 4.4), as id:own-deadline where own deadline = ship date + 56 days.
# Each is tolerated (as if listed in known-failing) until the later of its own deadline and the
# repo's contract-deadline; forever when the repo has no deadline. network: shipped 2026-11-03.
# smoke: default-on docker smoke for dotnet-service, shipped 2026-11-16 (verify.yml applies it only
# when smoke-path is empty; an explicit opt-in uses repo_known_failing). `integration` is deliberately
# absent: its projects already ran (and blocked) inside `test`, so it follows `test`'s tolerance.
NEW_STEPS="network:2026-12-29 smoke:2027-01-11"

# new_steps_tolerated <repo-deadline> <today> -> the new step ids still tolerated
new_steps_tolerated() {
  local out="" entry
  for entry in ${NEW_STEPS}; do
    if [ -z "$1" ] || [[ "$2" < "${entry#*:}" ]] || [[ "$2" < "$1" ]]; then out="${out} ${entry%%:*}"; fi
  done
  echo "${out# }"
}

# effective_known_failing <list> <repo-deadline> <today> -> known_failing_effective plus the
# tolerated new steps, without duplicates
effective_known_failing() {
  local out="" id
  for id in $(known_failing_effective "$1" "$2" "$3") $(new_steps_tolerated "$2" "$3"); do
    case " ${out} " in *" ${id} "*) ;; *) out="${out} ${id}" ;; esac
  done
  echo "${out# }"
}

# contract_mode <deadline> <today> -> warn|enforce (mirrors verify-contract)
contract_mode() {
  if [ -z "$1" ] || [[ "$2" < "$1" ]]; then echo warn; else echo enforce; fi
}

# deps_changed_from_list <newline-separated file paths> -> true|false
# Here-string, not a pipe: `printf | grep -q` gets SIGPIPE under pipefail on big lists.
deps_changed_from_list() {
  local pattern='(^|/)(package\.json|yarn\.lock|package-lock\.json|pnpm-lock\.yaml|Directory\.Packages\.props|pubspec\..*|Gemfile.*)$|\.csproj$|(^|/)(android|ios)/'
  if grep -Eq "${pattern}" <<< "$1"; then echo true; else echo false; fi
}

# strapi_changed_from_pr <newline-separated file paths> -> true|false
# True when the PR can change what Strapi does to existing data on boot: any dependency
# change (an @strapi bump, but also a lock file refresh or a driver update moves Strapi's
# own dependencies), a database migration, a content-type schema or a component (Strapi
# alters tables to match those on boot). Only the strapi job reads it.
strapi_changed_from_pr() {
  local data='(^|/)(package\.json|package-lock\.json|yarn\.lock|pnpm-lock\.yaml)$|(^|/)database/migrations/|(^|/)src/(api/[^/]+/content-types/[^/]+/schema\.json|components/.+\.json)$'
  if grep -Eq "${data}" <<< "$1"; then echo true; else echo false; fi
}
