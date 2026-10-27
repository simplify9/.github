#!/usr/bin/env bash
# Tests for cluster-dump.sh against a stub kubectl. Run: bash scripts/strapi-fixture/test_cluster_dump.sh
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fails=0
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
ok() { echo "PASS $1"; }
bad() { echo "FAIL $1: $2"; fails=$((fails + 1)); }

# Stub kubectl: logs each call (one arg per line, calls separated by ---), prints a fake dump on exec,
# and fails the exec when STUB_EXEC_FAIL is set.
mkdir -p "${tmp}/bin"
cat > "${tmp}/bin/kubectl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "${STUB_LOG}"; echo --- >> "${STUB_LOG}"
for a in "$@"; do
  if [ "${a}" = exec ]; then
    [ -n "${STUB_EXEC_FAIL:-}" ] && exit 3
    echo "dump body"
  fi
done
exit 0
EOF
chmod +x "${tmp}/bin/kubectl"
run() { # args... -> sets rc, out, log
  : > "${tmp}/log"
  out="$(PATH="${tmp}/bin:${PATH}" STUB_LOG="${tmp}/log" bash "${here}/cluster-dump.sh" "$@" 2>/dev/null)"; rc=$?
  log="$(cat "${tmp}/log")"
}

test_pod_reads_the_app_secret_read_only() {
  run ctx cms-ns cms-secret my-cms
  overrides="$(printf '%s\n' "${log}" | sed -n 's/^--overrides=//p')"
  if [ "${rc}" -eq 0 ] && [ "${out}" = "dump body" ] \
     && printf '%s' "${overrides}" | python3 -c '
import json, sys
spec = json.load(sys.stdin)["spec"]
c = spec["containers"][0]
assert spec["terminationGracePeriodSeconds"] == 0, spec
env = {e["name"]: e.get("value") or e["valueFrom"]["secretKeyRef"] for e in c["env"]}
assert env["PGPASSWORD"] == {"name": "cms-secret", "key": "DATABASE_PASSWORD"}, env
assert env["PGHOST"] == {"name": "cms-secret", "key": "DATABASE_HOST"}, env
assert env["PGOPTIONS"] == "-c default_transaction_read_only=on", env
assert env["PGSSLMODE"] == "require", env
assert c["securityContext"]["runAsNonRoot"] is True
'; then ok "$1"; else bad "$1" "rc=${rc} out=${out} log=${log}"; fi
}
test_named_schema_dumped_alone() {
  run ctx ns sec my-cms
  if printf '%s\n' "${log}" | grep -qx -- '--schema="my-cms"'; then ok "$1"; else bad "$1" "log=${log}"; fi
}
test_public_dumps_whole_database() {
  run ctx ns sec
  if printf '%s\n' "${log}" | grep -qx pg_dump && ! printf '%s\n' "${log}" | grep -q -- '--schema'; then ok "$1"; else bad "$1" "log=${log}"; fi
}
test_pod_deleted_even_when_dump_fails() {
  STUB_EXEC_FAIL=1 run ctx ns sec
  last="$(printf '%s\n' "${log}" | awk 'BEGIN{RS="---\n"} NF{c=$0} END{print c}')"
  if [ "${rc}" -ne 0 ] && printf '%s\n' "${last}" | grep -qx delete; then ok "$1"; else bad "$1" "rc=${rc} last=${last}"; fi
}
test_pg_image_matches_the_server() {
  PG_IMAGE=postgres:18 run ctx ns sec
  if printf '%s\n' "${log}" | grep -qx -- '--image=postgres:18' && printf '%s\n' "${log}" | grep -q '"image":"postgres:18"'; then ok "$1"; else bad "$1" "log=${log}"; fi
}
test_usage_without_secret() {
  run ctx ns
  if [ "${rc}" -eq 2 ] && [ ! -s "${tmp}/log" ]; then ok "$1"; else bad "$1" "rc=${rc} log=${log}"; fi
}

for t in $(declare -F | awk '{print $3}' | grep '^test_'); do "${t}" "${t}"; done
[ "${fails}" -eq 0 ] && echo "ALL PASS" || { echo "${fails} FAILED"; exit 1; }
