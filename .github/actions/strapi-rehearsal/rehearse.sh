#!/usr/bin/env bash
# Helpers for the strapi-rehearsal action. Sourced by action.yml and test_rehearse.sh.

# table_counts <psql-url> -> sorted "table count" lines for tables in schema public.
# A failed count aborts with non-zero status: a blank count must never look like a snapshot.
table_counts() {
  local url="$1" tables t n out=""
  tables="$(psql "${url}" -v ON_ERROR_STOP=1 -Atc "select table_name from information_schema.tables where table_schema='public' and table_type='BASE TABLE'")" || {
    echo "::error title=[VERIFY] rehearsal::could not list tables"; return 1; }
  while IFS= read -r t; do
    [ -n "${t}" ] || continue
    n="$(psql "${url}" -v ON_ERROR_STOP=1 -Atc "select count(*) from public.\"${t}\"")" || {
      echo "::error title=[VERIFY] rehearsal::count failed for table ${t}"; return 1; }
    out+="${t} ${n}"$'\n'
  done <<< "${tables}"
  printf '%s' "${out}" | LC_ALL=C sort
}

# has_content_tables <counts-file>: fail unless at least one non-bookkeeping table exists.
has_content_tables() {
  if awk '$1 !~ /^(strapi_|admin_|up_|i18n_locale)/ { found = 1 } END { exit !found }' "$1"; then return 0; fi
  echo "::error title=[VERIFY] rehearsal::fixture produced no content tables (check ci/fixture.sql.gz)"
  return 1
}

# compare_counts <before-file> <after-file>: exit 1 and print a line per content table whose count
# changed or that disappeared, and for any malformed line (table without a numeric count).
# Strapi bookkeeping tables change legitimately and are ignored; new tables are ignored too.
compare_counts() {
  awk '
    function skip(t) { return t ~ /^(strapi_|admin_|up_|i18n_locale)/ }
    $2 !~ /^[0-9]+$/ { printf "[VERIFY] rehearsal: malformed count line: %s\n", $0; bad = 1; next }
    NR == FNR { before[$1] = $2; next }
    { after[$1] = $2 }
    END {
      for (t in before) {
        if (skip(t)) continue
        if (!(t in after)) { printf "[VERIFY] rehearsal: %s %s -> dropped\n", t, before[t]; bad = 1 }
        else if (before[t] != after[t]) { printf "[VERIFY] rehearsal: %s %s -> %s\n", t, before[t], after[t]; bad = 1 }
      }
      exit bad
    }
  ' "$1" "$2" | LC_ALL=C sort
  return "${PIPESTATUS[0]}"
}

# wait_health <base-url>: poll <base-url>/_health until it returns 204, up to 120 s.
wait_health() {
  local i code
  for ((i = 0; i < 60; i++)); do
    code="$(curl -s -o /dev/null -w '%{http_code}' "$1/_health" || true)"
    [ "${code}" = "204" ] && return 0
    sleep 2
  done
  echo "::error title=[VERIFY] Rehearsal::$1/_health did not return 204 within 120 s (last status ${code:-none})"
  return 1
}
