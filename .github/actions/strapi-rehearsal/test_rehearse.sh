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
  if [ "${rc}" -ne 0 ] && [[ "${out}" == *"malformed count line"* ]]; then ok "$1"; else bad "$1" "rc=${rc} out=${out}"; fi
}
hct() { printf '%b' "$1" > "${tmp}/h"; hout="$(has_content_tables "${tmp}/h" 2>&1)"; hrc=$?; }
hct_fails() { hct "$2"; if [ "${hrc}" -ne 0 ] && [[ "${hout}" == *"fixture produced no content tables"* ]]; then ok "$1"; else bad "$1" "rc=${hrc} out=${hout}"; fi; }
test_has_content_tables_empty_fails() { hct_fails "$1" ''; }
test_has_content_tables_only_bookkeeping_fails() { hct_fails "$1" 'strapi_x 1\nadmin_users 2\n'; }
test_has_content_tables_ok() { hct 'strapi_x 1\narticles 0\n'; if [ "${hrc}" -eq 0 ]; then ok "$1"; else bad "$1" "failed"; fi; }
# --- v2: declared changes, column structure, value fingerprints ---
dc_run() { printf '%b' "$1" > "${tmp}/db"; printf '%b' "$2" > "${tmp}/dh"; dout="$(declared_changes "${tmp}/db" "${tmp}/dh")"; drc=$?; }
test_declared_changes_only_added_lines() {
  dc_run 'a\n' 'a\nb.c\n'
  if [ "${drc}" -eq 0 ] && [ "${dout}" = "b.c" ]; then ok "$1"; else bad "$1" "rc=${drc} out=${dout}"; fi
}
test_declared_changes_crlf_comments_whitespace() {
  dc_run '' '# x\r\n  t.c  \r\n\r\nu # note\r\n'
  if [ "${dout}" = $'t.c\nu' ]; then ok "$1"; else bad "$1" "out=${dout}"; fi
}
test_declared_changes_missing_files() {
  dout="$(declared_changes "${tmp}/nope1" "${tmp}/nope2" 2>&1)"; drc=$?
  if [ "${drc}" -eq 0 ] && [ -z "${dout}" ]; then ok "$1"; else bad "$1" "rc=${drc} out=${dout}"; fi
}
v2_run() { # fn before after declared
  printf '%b' "$2" > "${tmp}/b"; printf '%b' "$3" > "${tmp}/a"; printf '%b' "$4" > "${tmp}/d"
  out="$("$1" "${tmp}/b" "${tmp}/a" "${tmp}/d")"; rc=$?
}
COLS='articles\tbody\ttext\narticles\ttitle\tcharacter varying\n'
test_compare_columns_drop_fails() {
  v2_run compare_columns "${COLS}" 'articles\ttitle\tcharacter varying\n' ''
  if [ "${rc}" -eq 1 ] && [ "${out}" = "[VERIFY] rehearsal: column articles.body dropped" ]; then ok "$1"; else bad "$1" "rc=${rc} out=${out}"; fi
}
test_compare_columns_type_change_fails() {
  v2_run compare_columns "${COLS}" 'articles\tbody\ttext\narticles\ttitle\ttext\n' ''
  if [ "${rc}" -eq 1 ] && [ "${out}" = "[VERIFY] rehearsal: column articles.title type character varying -> text" ]; then ok "$1"; else bad "$1" "rc=${rc} out=${out}"; fi
}
test_compare_columns_new_ignored() {
  v2_run compare_columns "${COLS}" "${COLS}"'articles\tslug\ttext\n' ''
  if [ "${rc}" -eq 0 ] && [ -z "${out}" ]; then ok "$1"; else bad "$1" "rc=${rc} out=${out}"; fi
}
test_compare_columns_declared_reported() {
  v2_run compare_columns "${COLS}" 'articles\ttitle\tcharacter varying\n' 'articles.body\n'
  if [ "${rc}" -eq 0 ] && [ "${out}" = "[VERIFY] rehearsal: column articles.body dropped (declared)" ]; then ok "$1"; else bad "$1" "rc=${rc} out=${out}"; fi
}
test_compare_columns_bookkeeping_skipped() {
  v2_run compare_columns 'strapi_x\ta\ttext\nadmin_users\tb\ttext\narticles\tt\ttext\n' 'articles\tt\ttext\n' ''
  if [ "${rc}" -eq 0 ] && [ -z "${out}" ]; then ok "$1"; else bad "$1" "rc=${rc} out=${out}"; fi
}
FPS='articles\tbody\taaa\narticles\ttitle\tbbb\n'
test_compare_fingerprints_change_fails() {
  v2_run compare_fingerprints "${FPS}" 'articles\tbody\taaa\narticles\ttitle\tccc\n' ''
  if [ "${rc}" -eq 1 ] && [ "${out}" = "[VERIFY] rehearsal: articles.title values changed" ]; then ok "$1"; else bad "$1" "rc=${rc} out=${out}"; fi
}
test_compare_fingerprints_only_common_columns() {
  v2_run compare_fingerprints "${FPS}" 'articles\ttitle\tbbb\narticles\tslug\tzzz\n' ''
  if [ "${rc}" -eq 0 ] && [ -z "${out}" ]; then ok "$1"; else bad "$1" "rc=${rc} out=${out}"; fi
}
test_compare_fingerprints_declared_table_reported() {
  v2_run compare_fingerprints "${FPS}" 'articles\tbody\tx\narticles\ttitle\ty\n' 'articles\n'
  if [ "${rc}" -eq 0 ] && [ "${out}" = $'[VERIFY] rehearsal: articles.body values changed (declared)\n[VERIFY] rehearsal: articles.title values changed (declared)' ]; then ok "$1"; else bad "$1" "rc=${rc} out=${out}"; fi
}
test_compare_counts_declared_reported() {
  v2_run compare_counts 'articles 10\n' 'articles 20\n' 'articles\n'
  if [ "${rc}" -eq 0 ] && [ "${out}" = "[VERIFY] rehearsal: articles 10 -> 20 (declared)" ]; then ok "$1"; else bad "$1" "rc=${rc} out=${out}"; fi
}
test_rehearsal_base_prefers_merge_first_parent() {
  local r="${tmp}/git" a c out
  git init -q -b main "${r}" && cd "${r}" || { bad "$1" "git init"; return; }
  git -c user.email=t@example.invalid -c user.name=t commit -q --allow-empty -m A; a="$(git rev-parse HEAD)"
  git checkout -q -b pr && git -c user.email=t@example.invalid -c user.name=t commit -q --allow-empty -m B
  git checkout -q main && git -c user.email=t@example.invalid -c user.name=t commit -q --allow-empty -m C; c="$(git rev-parse HEAD)"
  git -c user.email=t@example.invalid -c user.name=t merge -q --no-ff -m M pr
  out="$(rehearsal_base "${r}" "${a}")"
  local plain; git checkout -q pr; plain="$(rehearsal_base "${r}" "${a}")"
  cd - > /dev/null || true
  if [ "${out}" = "${c}" ] && [ "${plain}" = "${a}" ]; then ok "$1"; else bad "$1" "merge=${out} want ${c}; plain=${plain} want ${a}"; fi
}
fixed_run() { # <config-file-content> -> sets rc and out for fixed_db_config on an app dir holding it
  rm -rf "${tmp}/app"; mkdir -p "${tmp}/app/config"
  printf '%s\n' "$1" > "${tmp}/app/config/database.ts"
  out="$(fixed_db_config "${tmp}/app")"; rc=$?
}
test_fixed_db_config_literals_flagged_values_hidden() {
  fixed_run 'export default ({ env }) => ({
  connection: {
    client: "postgres",
    connection: {
      host: "db.example.co",
      port: 25060,
      database: '"'"'cms-stg'"'"',
      user: "cms",
      password: `S3cretPass`,
      schema: "cms",
    },
  },
});'
  want=$'config/database.ts:5 host\nconfig/database.ts:7 database\nconfig/database.ts:8 user\nconfig/database.ts:9 password\nconfig/database.ts:10 schema'
  if [ "${rc}" -eq 1 ] && [ "${out}" = "${want}" ] && ! printf '%s' "${out}" | grep -q S3cret; then ok "$1"; else bad "$1" "rc=${rc} out=${out}"; fi
}
test_fixed_db_config_env_localhost_public_ok() {
  fixed_run 'export default ({ env }) => ({
  connection: {
    client: env("DATABASE_CLIENT", "sqlite"),
    connection: {
      host: env("DATABASE_HOST", "db.example.co"),
      password: process.env.DATABASE_PASSWORD,
      schema: env("DATABASE_SCHEMA", "public"),
    },
    sqlite: { filename: path.join(__dirname, "..", ".tmp/data.db") },
  },
});
const local = { host: "localhost", other: { host: '"'"'127.0.0.1'"'"', schema: "public" } };'
  if [ "${rc}" -eq 0 ] && [ -z "${out}" ]; then ok "$1"; else bad "$1" "rc=${rc} out=${out}"; fi
}
test_fixed_db_config_no_file_ok() {
  rm -rf "${tmp}/app"; mkdir -p "${tmp}/app"
  out="$(fixed_db_config "${tmp}/app")"; rc=$?
  if [ "${rc}" -eq 0 ] && [ -z "${out}" ]; then ok "$1"; else bad "$1" "rc=${rc} out=${out}"; fi
}
# Needs a Postgres: PG_TEST_URL=postgres://postgres:postgres@localhost:5432/postgres bash test_rehearse.sh
test_fingerprints_quoting_no_id_and_empty() {
  if [ -z "${PG_TEST_URL:-}" ]; then echo "SKIP $1 (PG_TEST_URL unset)"; return; fi
  psql "${PG_TEST_URL}" -q -v ON_ERROR_STOP=1 -c 'drop table if exists "Orders", no_id, e; create table "Orders"(id int, "order" text); insert into "Orders" values (2, $$b$$), (1, null); create table no_id(v text); insert into no_id values ($$y$$), ($$x$$); create table e(id int, x text);' || { bad "$1" "setup failed"; return; }
  printf '%b' 'Orders\tid\tinteger\nOrders\torder\ttext\nno_id\tv\ttext\ne\tid\tinteger\ne\tx\ttext\n' > "${tmp}/cols"
  local one two
  one="$(column_fingerprints "${PG_TEST_URL}" "${tmp}/cols")" && two="$(column_fingerprints "${PG_TEST_URL}" "${tmp}/cols")"
  if [ "${one}" = "${two}" ] && [ "$(printf '%s\n' "${one}" | grep -cE $'^[^\t]+\t[^\t]+\t[0-9a-f]{32}$')" -eq 5 ] \
     && printf '%s\n' "${one}" | grep -q $'^e\tx\td41d8cd98f00b204e9800998ecf8427e$'; then ok "$1"; else bad "$1" "out=${one}"; fi
  psql "${PG_TEST_URL}" -q -c 'drop table "Orders", no_id, e;'
}
for t in $(declare -F | awk '$3 ~ /^test_/ {print $3}'); do "$t" "$t"; done
if [ "${fails}" -eq 0 ]; then echo "ALL PASS"; else echo "${fails} FAILED"; exit 1; fi
