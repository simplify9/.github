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

# Shared awk prelude for the compare_* helpers: bookkeeping tables, and declared changes read from
# the file in -v decl (lines `table` or `table.column`): a declared difference is printed with
# " (declared)" and does not fail.
AWK_DECLARED='
  function skip(t) { return t ~ /^(strapi_|admin_|up_|i18n_locale)/ }
  function report(t, c, msg) {
    if ((t in d) || (c != "" && (t "." c) in d)) printf "%s (declared)\n", msg
    else { print msg; bad = 1 }
  }
  BEGIN { while ((getline l < decl) > 0) d[l] = 1 }
'

# compare_counts <before-file> <after-file> [declared-file]: exit 1 and print a line per content table
# whose count changed or that disappeared, and for any malformed line (table without a numeric count).
# Strapi bookkeeping tables change legitimately and are ignored; new tables are ignored too.
compare_counts() {
  awk -v decl="${3:-/dev/null}" "${AWK_DECLARED}"'
    $2 !~ /^[0-9]+$/ { printf "[VERIFY] rehearsal: malformed count line: %s\n", $0; bad = 1; next }
    FILENAME == ARGV[1] { before[$1] = $2; next }
    { after[$1] = $2 }
    END {
      for (t in before) {
        if (skip(t)) continue
        if (!(t in after)) report(t, "", sprintf("[VERIFY] rehearsal: %s %s -> dropped", t, before[t]))
        else if (before[t] != after[t]) report(t, "", sprintf("[VERIFY] rehearsal: %s %s -> %s", t, before[t], after[t]))
      }
      exit bad
    }
  ' "$1" "$2" | LC_ALL=C sort
  return "${PIPESTATUS[0]}"
}

# declared_changes <base-file> <head-file>: the entries of ci/rehearsal-expected-changes.txt that this PR
# adds (in head, not in base), normalized (CRLF, # comments, whitespace, blank lines), sorted. Lines
# already on the base branch never count, so a merged file cannot loosen the check on later PRs.
# A missing file is empty.
declared_changes() {
  local norm='{ sub(/\r$/, ""); sub(/#.*/, ""); gsub(/^[ \t]+|[ \t]+$/, ""); if ($0 != "") print }'
  LC_ALL=C comm -13 <(awk "${norm}" "$1" 2>/dev/null | LC_ALL=C sort -u) \
                    <(awk "${norm}" "$2" 2>/dev/null | LC_ALL=C sort -u)
}

# table_columns <psql-url> -> sorted "table<TAB>column<TAB>data_type" lines for base tables in schema public.
table_columns() {
  local out
  out="$(psql "$1" -v ON_ERROR_STOP=1 -At -F $'\t' -c "select c.table_name, c.column_name, c.data_type
      from information_schema.columns c join information_schema.tables t
        on t.table_schema = c.table_schema and t.table_name = c.table_name
      where c.table_schema = 'public' and t.table_type = 'BASE TABLE'")" || {
    echo "::error title=[VERIFY] rehearsal::could not list columns"; return 1; }
  printf '%s\n' "${out}" | LC_ALL=C sort
}

# column_fingerprints <psql-url> <columns-file> -> sorted "table<TAB>column<TAB>md5" lines for content tables.
# Per column: md5 over each row's md5(value::text) (NULL as '<null>'), in "id" order when the table has
# an id column, else in sorted-hash order. An empty table hashes the empty string. Identifiers are quoted.
column_fingerprints() {
  local url="$1" t c qt qc ord h out=""
  while IFS=$'\t' read -r t c _; do
    [ -n "${t}" ] || continue
    [[ "${t}" =~ ^(strapi_|admin_|up_|i18n_locale) ]] && continue
    qt="\"${t//\"/\"\"}\""; qc="\"${c//\"/\"\"}\""
    ord="md5(coalesce(${qc}::text, '<null>'))"
    if awk -F'\t' -v t="${t}" '$1 == t && $2 == "id" { f = 1 } END { exit !f }' "$2"; then ord='"id"'; fi
    h="$(psql "${url}" -v ON_ERROR_STOP=1 -At -c \
      "select md5(coalesce(string_agg(md5(coalesce(${qc}::text, '<null>')), ',' order by ${ord}), '')) from public.${qt}")" || {
      echo "::error title=[VERIFY] rehearsal::fingerprint failed for ${t}.${c}"; return 1; }
    out+="${t}"$'\t'"${c}"$'\t'"${h}"$'\n'
  done < "$2"
  printf '%s' "${out}" | LC_ALL=C sort
}

# compare_columns <before> <after> [declared]: exit 1 per content-table column dropped or whose type
# changed (new columns are fine).
compare_columns() {
  awk -F'\t' -v decl="${3:-/dev/null}" "${AWK_DECLARED}"'
    FILENAME == ARGV[1] { before[$1 "\t" $2] = $3; next }
    { after[$1 "\t" $2] = $3 }
    END {
      for (k in before) {
        split(k, p, "\t"); if (skip(p[1])) continue
        if (!(k in after)) report(p[1], p[2], sprintf("[VERIFY] rehearsal: column %s.%s dropped", p[1], p[2]))
        else if (before[k] != after[k]) report(p[1], p[2], sprintf("[VERIFY] rehearsal: column %s.%s type %s -> %s", p[1], p[2], before[k], after[k]))
      }
      exit bad
    }
  ' "$1" "$2" | LC_ALL=C sort
  return "${PIPESTATUS[0]}"
}

# compare_fingerprints <before> <after> [declared]: exit 1 per content-table column (present in both)
# whose values changed.
compare_fingerprints() {
  awk -F'\t' -v decl="${3:-/dev/null}" "${AWK_DECLARED}"'
    FILENAME == ARGV[1] { before[$1 "\t" $2] = $3; next }
    { after[$1 "\t" $2] = $3 }
    END {
      for (k in before) {
        split(k, p, "\t"); if (skip(p[1]) || !(k in after)) continue
        if (before[k] != after[k]) report(p[1], p[2], sprintf("[VERIFY] rehearsal: %s.%s values changed", p[1], p[2]))
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
