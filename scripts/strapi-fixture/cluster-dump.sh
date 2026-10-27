#!/usr/bin/env bash
# Streams a read-only pg_dump of a Strapi database that only accepts connections from inside its cluster.
#
#   scripts/strapi-fixture/cluster-dump.sh CONTEXT NAMESPACE SECRET [SCHEMA] \
#     | python3 scripts/strapi-fixture/strapi_fixture.py --source-dump - [--schema SCHEMA] --repo ../some-cms
#
# Starts a temporary Postgres pod (PG_IMAGE, default postgres:17; use the server's major version) in NAMESPACE that logs in with the CMS's own secret (DATABASE_HOST, _PORT,
# _NAME, _USERNAME, _PASSWORD), in a read-only session, and deletes the pod on exit. Only the dump leaves the
# cluster, straight into strapi_fixture.py's throwaway container. SCHEMA is the CMS's DATABASE_SCHEMA (default
# public, which dumps the whole database).
set -euo pipefail
[ $# -ge 3 ] || { echo "usage: cluster-dump.sh CONTEXT NAMESPACE SECRET [SCHEMA]" >&2; exit 2; }
ctx="$1" ns="$2" secret="$3" schema="${4:-public}"
pod="strapi-fixture-dump-$$"
image="${PG_IMAGE:-postgres:17}"
k() { kubectl --context "${ctx}" -n "${ns}" "$@"; }
ref() { printf '{"name":"%s","valueFrom":{"secretKeyRef":{"name":"%s","key":"%s"}}}' "$1" "${secret}" "$2"; }
overrides="$(printf '{"spec":{"restartPolicy":"Never","terminationGracePeriodSeconds":0,"containers":[{"name":"dump","image":"%s","command":["sleep","1800"],
"env":[%s,%s,%s,%s,%s,{"name":"PGSSLMODE","value":"require"},{"name":"PGOPTIONS","value":"-c default_transaction_read_only=on"}],
"securityContext":{"runAsNonRoot":true,"runAsUser":999,"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"seccompProfile":{"type":"RuntimeDefault"}}}]}}' \
  "${image}" "$(ref PGHOST DATABASE_HOST)" "$(ref PGPORT DATABASE_PORT)" "$(ref PGDATABASE DATABASE_NAME)" \
  "$(ref PGUSER DATABASE_USERNAME)" "$(ref PGPASSWORD DATABASE_PASSWORD)" | tr -d '\n')"
trap 'k delete pod "${pod}" --wait=false > /dev/null 2>&1 || true' EXIT
k run "${pod}" --image="${image}" --restart=Never --overrides="${overrides}" > /dev/null
k wait --for=condition=Ready "pod/${pod}" --timeout=180s > /dev/null
args=(pg_dump --no-owner --no-privileges)
# pg_dump --schema=public emits CREATE SCHEMA public, which does not restore into a fresh database.
[ "${schema}" = public ] || args+=("--schema=\"${schema//\"/\"\"}\"")
k exec "${pod}" -- "${args[@]}"
