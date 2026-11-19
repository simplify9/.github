#!/usr/bin/env bash
# Scope helpers for verify.yml. Sourced by the verify-plan action and by test_scope.sh.
# All dates are ISO YYYY-MM-DD, compared as strings.

# verify_full <event> <base> <default-branch> <author> <bot-login> [tests-changed] -> true|false
# tests-changed is the tests-probe job's answer (tests_changed_from_list) for a human PR into develop.
verify_full() {
  if [ "$1" = "workflow_dispatch" ] || [ "$2" = "$3" ] || [ "$4" = "$5" ] || [ "${6:-false}" = "true" ]; then
    echo true
  else
    echo false
  fi
}

# known_failing_effective <list> <deadline> <today> -> the list before the deadline, else empty
known_failing_effective() {
  if [ -z "$2" ] || [[ "$3" < "$2" ]]; then echo "$1"; else echo ""; fi
}

# Step ids added after v1 (spec 4.4), as <stack>:<id>:<own deadline> (own deadline = ship date + 56
# days; stack `*` = every stack). Each is tolerated (as if listed in known-failing) until the later of
# its own deadline and the repo's contract-deadline; forever when the repo has no deadline.
# SCOPE BY STACK when the id already blocks elsewhere: tolerance is matched by step id, so a bare `*`
# entry would downgrade that existing blocking step everywhere.
#   network  web e2e network block, shipped 2026-11-03 (no other stack has a `network` step)
#   smoke    default-on docker smoke for dotnet-service, shipped 2026-11-03; verify.yml applies it only
#            when smoke-path is empty (an explicit opt-in uses repo_known_failing and keeps blocking)
#   e2e      Flutter's emulator journeys (flutter-e2e job), shipped 2026-11-03; scoped to flutter because
#            web's `e2e` already blocks
# `ios` (React Native iOS build, shipped 2026-11-04) is deliberately absent: it blocks from day one, because
# while tolerated the bot would still merge a lock refresh that breaks the iOS release build (it did once).
# `integration` is deliberately absent: its projects already ran, and blocked, inside `test`, so it
# follows `test`'s tolerance in verify.yml.
NEW_STEPS="*:network:2026-12-29 dotnet-service:smoke:2026-12-29 flutter:e2e:2026-12-29"

# new_steps_tolerated <repo-deadline> <today> [stack] -> the new step ids still tolerated for that stack
# (without a stack, only `*` entries)
new_steps_tolerated() {
  local out="" entry scope rest
  local -a entries=()
  read -ra entries <<< "${NEW_STEPS}"
  for entry in "${entries[@]}"; do
    scope="${entry%%:*}"; rest="${entry#*:}"
    [ "${scope}" = "*" ] || [ "${scope}" = "${3:-}" ] || continue
    if [ -z "$1" ] || [[ "$2" < "${rest#*:}" ]] || [[ "$2" < "$1" ]]; then out="${out} ${rest%%:*}"; fi
  done
  echo "${out# }"
}

# effective_known_failing <list> <repo-deadline> <today> [stack] -> known_failing_effective plus the
# tolerated new steps for that stack, without duplicates
effective_known_failing() {
  local out="" id
  for id in $(known_failing_effective "$1" "$2" "$3") $(new_steps_tolerated "$2" "$3" "${4:-}"); do
    case " ${out} " in *" ${id} "*) ;; *) out="${out} ${id}" ;; esac
  done
  echo "${out# }"
}

# effective_deadline <repo-deadline> <today> <head-ref> -> today on a strict branch, else the repo deadline.
# Strict branches (renovate/strict-*) carry Renovate's developer-tool majors (renovate/dev-tools.json), which
# merge by themselves. Judged as if the deadline were today, nothing in known-failing is tolerated and every
# contract item is enforced: a green check then means the tool ran and passed (ESLint 10 that cannot load the
# repo's config fails instead of being tolerated). Only the bot's prefix counts, and it can only tighten.
effective_deadline() {
  case "${3:-}" in renovate/strict-*) echo "$2" ;; *) echo "$1" ;; esac
}

# branch_known_failing <list> <head-ref> -> the list without `ios` on an iOS toolchain branch
# (renovate/ios-toolchain, renovate/lock-file-maintenance-ios-toolchain). On react-native those merge by
# themselves once verify's iOS build passes, so that build must block there even when the repo lists `ios`.
branch_known_failing() {
  case "${2:-}" in renovate/*ios-toolchain*) ;; *) echo "$1"; return ;; esac
  local out="" id
  for id in $1; do [ "${id}" = ios ] || out="${out} ${id}"; done
  echo "${out# }"
}

# contract_mode <deadline> <today> -> warn|enforce (mirrors verify-contract)
contract_mode() {
  if [ -z "$1" ] || [[ "$2" < "$1" ]]; then echo warn; else echo enforce; fi
}

# deps_changed_from_list <newline-separated file paths> -> true|false
# Here-string, not a pipe: `printf | grep -q` gets SIGPIPE under pipefail on big lists.
deps_changed_from_list() {
  local pattern='(^|/)(package\.json|yarn\.lock|package-lock\.json|pnpm-lock\.yaml|Directory\.Packages\.props|pubspec\..*|Gemfile.*|\.nvmrc|\.node-version)$|\.csproj$|(^|/)(android|ios)/'
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

# tests_changed_from_list <newline-separated file paths> [stack] -> true|false
# True when a PR changes critical-journey or integration test files: Maestro flows (.maestro/), e2e/
# (Playwright specs, Mockoon mocks, allowed hosts), Flutter integration_test/, a Playwright config, and for
# the .NET stacks an integration-test project: a directory named *Integration*Test(s) (SW.Api.IntegrationTests/)
# or an integration folder under tests/ (tests/integration/). A human PR into develop that changes them gets
# the full ladder, so new tests run before they reach develop instead of first failing a Renovate PR.
# Unit and contract test projects (*.UnitTests/, *.ContractTests/, tests/Unit/) and other stacks' unit-test
# folders (__tests__, *.test.ts) stay out: such a PR passes at once, like any other human develop PR.
# ponytail: by name, as the probe has only the file list; verify's integration job finds Testcontainers
# projects by content. Every enrolled one is named *IntegrationTests; one named otherwise first runs on
# the promotion PR into the default branch or a Renovate PR.
tests_changed_from_list() {
  local journeys='(^|/)(\.maestro|e2e|integration_test)/|(^|/)playwright\.config\.[cm]?[jt]s$'
  local dotnet='(^|/)[^/]*[Ii]ntegration[^/]*Tests?/|(^|/)[Tt]ests?/([^/]+/)*[Ii]ntegration[^/]*/'
  if grep -Eq "${journeys}" <<< "$1"; then echo true; return; fi
  case "${2:-}" in
    dotnet-service|dotnet-library) if grep -Eq "${dotnet}" <<< "$1"; then echo true; return; fi ;;
  esac
  echo false
}

# ios_changed_from_list <newline-separated file paths> -> true|false|packages
# What only verify's macOS ios job checks is pod install and the native iOS compile: the JS bundle is
# built and Hermes-compiled for iOS by the react-native job on Linux. true when the PR changes an iOS build
# input outright: ios/, Gemfile*, the Ruby, Xcode or Node version, patches/ (patch-package can patch native
# code), react-native.config.* (autolinking), a lock file the plan cannot compare (npm, pnpm), or
# package.json without yarn.lock. `packages` when yarn.lock changed: the plan then asks
# ios_relevant_packages whether a package with native iOS code moved. false otherwise (JS source, Android).
# ponytail: a package.json change beside yarn.lock is judged by the lock alone; a change to its
# `codegenConfig` or `react-native` fields in the same PR is not seen (rare; a PR into the default branch
# always builds iOS).
ios_changed_from_list() {
  local direct='(^|/)(ios/|patches/)|(^|/)(Gemfile(\.lock)?|\.ruby-version|\.xcode-version|\.nvmrc|\.node-version|package-lock\.json|pnpm-lock\.yaml|react-native\.config\.[cm]?[jt]s)$'
  if grep -Eq "${direct}" <<< "$1"; then echo true; return; fi
  if grep -Eq '(^|/)yarn\.lock$' <<< "$1"; then echo packages; return; fi
  if grep -Eq '(^|/)package\.json$' <<< "$1"; then echo true; return; fi
  echo false
}

# lock_versions <yarn.lock text> -> sorted unique "name version" lines (Yarn 1 and Berry lock files)
lock_versions() {
  awk '
    /^[^ ]/ { name = "" }
    /^[^ #_][^ ]*.*:$/ || /^"/ {
      key = $0; sub(/:$/, "", key); gsub(/"/, "", key); split(key, specs, ", "); s = specs[1]
      at = substr(s, 1, 1) == "@" ? index(substr(s, 2), "@") + 1 : index(s, "@")
      name = at > 1 ? substr(s, 1, at - 1) : s
      next
    }
    /^  version:? / && name != "" { v = $2; gsub(/"/, "", v); print name " " v }
  ' <<< "$1" | LC_ALL=C sort -u
}

# lock_changed_packages <base yarn.lock> <head yarn.lock> -> names whose resolved versions differ, one per line
lock_changed_packages() {
  LC_ALL=C comm -3 <(lock_versions "$1") <(lock_versions "$2") | awk '{print $1}' | LC_ALL=C sort -u
}

# podfile_lock_packages <ios/Podfile.lock text> -> the JS packages the iOS app builds native code from
# (every autolinked module appears as a ../node_modules/<package> path), one per line
podfile_lock_packages() {
  { grep -oE 'node_modules/(@[^/"`]+/)?[^/"`]+' <<< "$1" || true; } | sed 's#^node_modules/##' | LC_ALL=C sort -u
}

# ios_relevant_packages <changed names> <native names> -> true|false
# true when a changed package has native iOS code, or is React Native or Expo tooling: any React Native or
# Expo package counts, because one can gain native code in a new version before Podfile.lock lists it.
ios_relevant_packages() {
  local name
  while IFS= read -r name; do
    [ -n "${name}" ] || continue
    case "${name}" in *react-native* | expo | expo-* | @expo/*) echo true; return ;; esac
    if grep -qxF -- "${name}" <<< "$2"; then echo true; return; fi
  done <<< "$1"
  echo false
}
