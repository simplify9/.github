#!/usr/bin/env bash
# Tests for the pure functions in rehearse.sh. Run: bash .github/actions/strapi-rehearsal/test_rehearse.sh
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=rehearse.sh
source "${here}/rehearse.sh"
fails=0
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
ok() { echo "PASS $1"; }
bad() { echo "FAIL $1: $2"; fails=$((fails + 1)); }
cmp_run() { # before-content after-content -> sets rc and out
  printf '%b' "$1" > "${tmp}/b"; printf '%b' "$2" > "${tmp}/a"
  out="$(compare_counts "${tmp}/b" "${tmp}/a")"; rc=$?
}
test_compare_counts_equal_ok() {
  cmp_run 'articles 10\nusers 2\n' 'articles 10\nusers 2\n'
  if [ "${rc}" -eq 0 ]; then ok "$1"; else bad "$1" "rc=${rc} out=${out}"; fi
}
test_compare_counts_content_change_fails() {
  cmp_run 'articles 10\n' 'articles 20\n'
  if [ "${rc}" -eq 1 ] && [ "${out}" = "[VERIFY] rehearsal: articles 10 -> 20" ]; then ok "$1"; else bad "$1" "rc=${rc} out=${out}"; fi
}
test_compare_counts_bookkeeping_ignored() {
  cmp_run 'strapi_migrations 3\nadmin_users 1\nup_users 1\ni18n_locale 1\n' 'strapi_migrations 5\nadmin_users 2\nup_users 4\ni18n_locale 2\n'
  if [ "${rc}" -eq 0 ]; then ok "$1"; else bad "$1" "rc=${rc} out=${out}"; fi
}
test_compare_counts_new_table_ignored() {
  cmp_run 'articles 10\n' 'articles 10\ncomments 7\n'
  if [ "${rc}" -eq 0 ]; then ok "$1"; else bad "$1" "rc=${rc} out=${out}"; fi
}
test_compare_counts_dropped_table_fails() {
  cmp_run 'articles 10\nusers 2\n' 'users 2\n'
  if [ "${rc}" -eq 1 ] && [ "${out}" = "[VERIFY] rehearsal: articles 10 -> dropped" ]; then ok "$1"; else bad "$1" "rc=${rc} out=${out}"; fi
}
test_compare_counts_dropped_bookkeeping_ignored() {
  cmp_run 'strapi_x 3\narticles 1\n' 'articles 1\n'
  if [ "${rc}" -eq 0 ]; then ok "$1"; else bad "$1" "rc=${rc} out=${out}"; fi
}
test_compare_counts_empty_count_fails() {
  cmp_run 'articles \n' 'articles 10\n'
  if [ "${rc}" -ne 0 ]; then ok "$1"; else bad "$1" "rc=${rc} out=${out}"; fi
}
hct() { printf '%b' "$1" > "${tmp}/h"; has_content_tables "${tmp}/h" 2>/dev/null; }
test_has_content_tables_empty_fails() { if hct ''; then bad "$1" "passed"; else ok "$1"; fi; }
test_has_content_tables_only_bookkeeping_fails() { if hct 'strapi_x 1\nadmin_users 2\n'; then bad "$1" "passed"; else ok "$1"; fi; }
test_has_content_tables_ok() { if hct 'strapi_x 1\narticles 0\n'; then ok "$1"; else bad "$1" "failed"; fi; }
for t in $(declare -F | awk '$3 ~ /^test_/ {print $3}'); do "$t" "$t"; done
if [ "${fails}" -eq 0 ]; then echo "ALL PASS"; else echo "${fails} FAILED"; exit 1; fi
