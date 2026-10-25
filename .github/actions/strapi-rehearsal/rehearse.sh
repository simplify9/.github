#!/usr/bin/env bash
# Helpers for the strapi-rehearsal action. Sourced by action.yml and test_rehearse.sh.

# table_counts <psql-url> -> sorted "table count" lines for tables in schema public
table_counts() {
  local url="$1" t
  psql "${url}" -v ON_ERROR_STOP=1 -Atc "select table_name from information_schema.tables where table_schema='public' and table_type='BASE TABLE'" |
    while IFS= read -r t; do
      echo "${t} $(psql "${url}" -v ON_ERROR_STOP=1 -Atc "select count(*) from public.\"${t}\"")"
    done | LC_ALL=C sort
}

# compare_counts <before-file> <after-file>: exit 1 and print a line per content table whose count
# changed. Strapi bookkeeping tables change legitimately on upgrade and are ignored; tables
# present in only one file are ignored too (new tables are expected).
compare_counts() {
  awk '
    NR == FNR { before[$1] = $2; next }
    $1 ~ /^(strapi_|admin_|up_|i18n_locale)/ { next }
    ($1 in before) && before[$1] != $2 { printf "[VERIFY] rehearsal: %s %s -> %s\n", $1, before[$1], $2; bad = 1 }
    END { exit bad }
  ' "$1" "$2"
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
