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

# strapi_changed_from_pr <newline-separated file paths> <package.json patch text> -> true|false
# True when the PR can change what Strapi does to existing data on boot: a changed (+/-)
# package.json patch line names an "@strapi/ dependency, or it touches a database migration,
# a content-type schema or a component (Strapi alters tables to match those on boot).
strapi_changed_from_pr() {
  local data='(^|/)database/migrations/|(^|/)src/(api/[^/]+/content-types/[^/]+/schema\.json|components/.+\.json)$'
  if grep -Eq "${data}" <<< "$1" \
    || { grep -Eq '(^|/)package\.json$' <<< "$1" && grep -Eq '^[+-].*"@strapi/' <<< "$2"; }; then
    echo true
  else
    echo false
  fi
}
