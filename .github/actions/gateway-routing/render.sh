#!/usr/bin/env bash
# =============================================================================
# gateway-routing / render.sh
# =============================================================================
# Pure (no-cluster) renderer that turns the workflow's routing inputs into a
# Helm *values file* (gateway/ingress/config structure) plus two ancillary
# outputs consumed by the gateway-onboard step:
#
#   * gateway-host-list           — newline-separated, trimmed gateway hostnames.
#   * gateway-section-names-list  — newline-separated section names, ALIGNED BY
#                                   POSITION with the host list. A blank entry
#                                   means DEDICATED mode for that host; a
#                                   non-empty entry means SHARED listener mode.
#
# This was previously ~140 lines of bash inlined in the workflow's
# "Generate routing and config values" step. Extracting it makes the logic
# unit-testable (see scripts/render.bats-style golden tests) and lets the
# structured gateway/ingress values be emitted as a real YAML document instead
# of a fragile `\n`-escaped `--set` string (the chart receives `-f values.yaml`).
#
# Behaviour is a faithful 1:1 port of the original inline logic — the only
# change is the OUTPUT FORMAT (YAML file vs. `key=value` lines). The set of
# keys emitted, their values, their ordering, the parentRef de-duplication, the
# legacy single-parentRef fallback and the host/section alignment are identical.
#
# Inputs are read from the environment (set by action.yml). Outputs:
#   * a YAML values file written to $ROUTING_VALUES_FILE
#   * GitHub step outputs appended to $GITHUB_OUTPUT (skipped if unset, so the
#     script can be run directly in tests)
# =============================================================================
set -euo pipefail

# ----- helpers ---------------------------------------------------------------

# Lowercase a string.
lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Slugify a hostname into a DNS-1123-ish label fragment (same transform the
# onboarding step and chart use to derive per-host listener/secret names).
to_slug() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/-\+/-/g; s/^-//; s/-$//'
}

# Truncate to 63 chars (Gateway listener-name limit) and drop a trailing dash.
trim63() { printf '%s' "$1" | cut -c1-63 | sed 's/-$//'; }

# True when the argument is empty once all whitespace/commas/CR are stripped.
is_blank() { [ -z "$(printf '%s' "${1:-}" | tr -d '[:space:],\r\n')" ]; }

# YAML-quote a scalar as a double-quoted string (escaping \ and ").
yq_str() {
  local s="${1//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '"%s"' "$s"
}

# Emit a scalar the way `helm --set key=value` would have typed it: bare
# integers stay integers, bare true/false stay booleans, everything else is a
# quoted string. This preserves the exact chart-side typing of the old --set path.
yq_scalar() {
  local v="$1"
  if [ "$v" = "true" ] || [ "$v" = "false" ]; then
    printf '%s' "$v"
  elif printf '%s' "$v" | grep -Eq '^[0-9]+$'; then
    printf '%s' "$v"
  else
    yq_str "$v"
  fi
}

# ----- read inputs (env) -----------------------------------------------------

ROUTING_MODE="${ROUTING_MODE:-gateway}"
CONFIGMAP_ENABLED="${CONFIGMAP_ENABLED:-false}"
GATEWAY_PARENT_NAME="${GATEWAY_PARENT_NAME:-}"
GATEWAY_PARENT_NAMESPACE="${GATEWAY_PARENT_NAMESPACE:-}"
GATEWAY_SECTION_NAME="${GATEWAY_SECTION_NAME:-}"
GATEWAY_SECTION_NAMES_RAW="${GATEWAY_SECTION_NAMES_RAW:-}"
GATEWAY_HOSTNAMES_RAW="${GATEWAY_HOSTNAMES_RAW:-}"
GATEWAY_PATHS_RAW="${GATEWAY_PATHS_RAW:-}"
GATEWAY_PATH_TYPE="${GATEWAY_PATH_TYPE:-PathPrefix}"
GATEWAY_BACKEND_SERVICE_NAME="${GATEWAY_BACKEND_SERVICE_NAME:-}"
GATEWAY_BACKEND_PORT="${GATEWAY_BACKEND_PORT:-}"
INGRESS_HOSTS="${INGRESS_HOSTS:-}"
INGRESS_PATHS="${INGRESS_PATHS:-}"
INGRESS_TLS_SECRETS="${INGRESS_TLS_SECRETS:-}"
INGRESS_CLASS_NAME="${INGRESS_CLASS_NAME:-nginx}"
INGRESS_PATH_TYPE="${INGRESS_PATH_TYPE:-Prefix}"
INGRESS_TLS_ENABLED="${INGRESS_TLS_ENABLED:-true}"
INGRESS_CLUSTER_ISSUER="${INGRESS_CLUSTER_ISSUER:-}"
INGRESS_PROXY_BODY_SIZE="${INGRESS_PROXY_BODY_SIZE:-}"

: "${ROUTING_VALUES_FILE:?ROUTING_VALUES_FILE must point at the output values file}"

# ----- resolve routing mode --------------------------------------------------

mode=$(lc "$ROUTING_MODE")
gateway_enabled=false
ingress_enabled=false
case "$mode" in
  gateway) gateway_enabled=true ;;
  ingress) ingress_enabled=true ;;
  dual)    gateway_enabled=true; ingress_enabled=true ;;
  *)
    echo "Unknown routing-mode '$ROUTING_MODE'. Expected one of: gateway, ingress, dual." >&2
    exit 1
    ;;
esac

# Backward compatibility: when gateway host/path are omitted, fall back to ingress-style inputs.
gateway_hosts_input="$GATEWAY_HOSTNAMES_RAW"
gateway_paths_input="$GATEWAY_PATHS_RAW"
if is_blank "$gateway_hosts_input" && ! is_blank "$INGRESS_HOSTS"; then
  gateway_hosts_input="$INGRESS_HOSTS"
fi
if is_blank "$gateway_paths_input" && ! is_blank "$INGRESS_PATHS"; then
  gateway_paths_input="$INGRESS_PATHS"
fi
if is_blank "$gateway_paths_input"; then
  gateway_paths_input='/'
fi

# Build the trimmed host list (newline-separated) and count.
host_list=""
host_count=0
while IFS= read -r host; do
  host=$(echo "$host" | xargs)
  [ -z "$host" ] && continue
  host_list+="$host"$'\n'
  host_count=$((host_count + 1))
done < <(echo "$gateway_hosts_input" | sed 's/\r//g' | tr ',' '\n')

# ----- accumulate YAML fragments ---------------------------------------------
# Each block is emitted only when it has content, exactly mirroring the original
# (which emitted `gateway.hostnames[i]=...` etc. only per present element).

parentrefs_yaml=""
hostnames_yaml=""
routes_yaml=""
ingress_hosts_yaml=""
ingress_paths_yaml=""
ingress_annotations_yaml=""

# Per-hostname section names list — populated only when gateway-section-names
# (plural) is used; remains empty in legacy mode. Position-aligned with host_list.
section_names_list=""

if [ "$gateway_enabled" = "true" ]; then
  # The singular gateway-section-name and the plural gateway-section-names drive
  # mutually exclusive listener-selection paths (onboard.sh short-circuits on the
  # singular). If both are set, the rendered Helm values can reference per-host
  # listeners that onboarding never creates — fail loudly instead.
  if ! is_blank "${GATEWAY_SECTION_NAME:-}" && ! is_blank "${GATEWAY_SECTION_NAMES_RAW:-}"; then
    echo "gateway-section-name and gateway-section-names are mutually exclusive." >&2
    exit 1
  fi
  if ! is_blank "${GATEWAY_SECTION_NAMES_RAW:-}"; then
    # Per-hostname mode: one parentRef per host, section name resolved from
    # gateway-section-names by position (empty entry = auto-slug for dedicated).
    mapfile -t _raw_sections <<< "${GATEWAY_SECTION_NAMES_RAW//$'\r'/}"
    _sn_pos=0
    _emitted_sections=""
    while IFS= read -r _h; do
      _h=$(echo "$_h" | xargs)
      [ -z "$_h" ] && continue
      _sn=""
      if [ "$_sn_pos" -lt "${#_raw_sections[@]}" ]; then
        # Strip shell-style comments so callers can annotate lines.
        _sn=$(echo "${_raw_sections[$_sn_pos]}" | xargs | sed 's/#.*//' | xargs)
      fi
      _sn_pos=$((_sn_pos + 1))
      if [ -n "$_sn" ]; then
        # Shared mode — always record in section_names_list so onboarding can
        # validate the listener for every host. Emit one parentRef per UNIQUE
        # sectionName (the Gateway API forbids duplicate (name,ns,section) tuples).
        section_names_list+="${_sn}"$'\n'
        if ! echo "$_emitted_sections" | grep -Fxq "$_sn"; then
          _emitted_sections+="${_sn}"$'\n'
          parentrefs_yaml+="    - name: $(yq_str "$GATEWAY_PARENT_NAME")"$'\n'
          parentrefs_yaml+="      namespace: $(yq_str "$GATEWAY_PARENT_NAMESPACE")"$'\n'
          parentrefs_yaml+="      sectionName: $(yq_str "$_sn")"$'\n'
        fi
      else
        # Dedicated mode: each host gets its own unique auto-slugged parentRef.
        _slug=$(to_slug "$_h")
        _auto_sn=$(trim63 "https-${_slug}")
        parentrefs_yaml+="    - name: $(yq_str "$GATEWAY_PARENT_NAME")"$'\n'
        parentrefs_yaml+="      namespace: $(yq_str "$GATEWAY_PARENT_NAMESPACE")"$'\n'
        parentrefs_yaml+="      sectionName: $(yq_str "$_auto_sn")"$'\n'
        section_names_list+=''$'\n'
      fi
    done < <(echo "$gateway_hosts_input" | sed 's/\r//g' | tr ',' '\n')
  else
    # Legacy single-parentRef mode — fully backwards compatible.
    parentrefs_yaml+="    - name: $(yq_str "$GATEWAY_PARENT_NAME")"$'\n'
    parentrefs_yaml+="      namespace: $(yq_str "$GATEWAY_PARENT_NAMESPACE")"$'\n'
    effective_section="${GATEWAY_SECTION_NAME}"
    if [ -z "$effective_section" ] && [ "$host_count" -eq 1 ]; then
      first_host=$(echo "$host_list" | head -n1)
      effective_section=$(trim63 "https-$(to_slug "$first_host")")
    fi
    if [ -n "$effective_section" ]; then
      parentrefs_yaml+="      sectionName: $(yq_str "$effective_section")"$'\n'
    fi
  fi

  # hostnames
  while IFS= read -r host; do
    host=$(echo "$host" | xargs)
    [ -z "$host" ] && continue
    hostnames_yaml+="    - $(yq_str "$host")"$'\n'
  done < <(printf "%s" "$host_list")

  # routes
  while IFS= read -r path; do
    path=$(echo "$path" | xargs)
    [ -z "$path" ] && continue
    routes_yaml+="    - path: $(yq_str "$path")"$'\n'
    routes_yaml+="      pathType: $(yq_str "$GATEWAY_PATH_TYPE")"$'\n'
    if [ -n "$GATEWAY_BACKEND_SERVICE_NAME" ] || [ -n "$GATEWAY_BACKEND_PORT" ]; then
      routes_yaml+="      backendRef:"$'\n'
      [ -n "$GATEWAY_BACKEND_SERVICE_NAME" ] && \
        routes_yaml+="        name: $(yq_str "$GATEWAY_BACKEND_SERVICE_NAME")"$'\n'
      [ -n "$GATEWAY_BACKEND_PORT" ] && \
        routes_yaml+="        port: $(yq_scalar "$GATEWAY_BACKEND_PORT")"$'\n'
    fi
  done < <(echo "$gateway_paths_input" | sed 's/\r//g' | tr ',' '\n')
fi

if [ "$ingress_enabled" = "true" ]; then
  if [ -n "$INGRESS_CLUSTER_ISSUER" ]; then
    ingress_annotations_yaml+="    cert-manager.io/cluster-issuer: $(yq_str "$INGRESS_CLUSTER_ISSUER")"$'\n'
  fi
  if [ -n "$INGRESS_PROXY_BODY_SIZE" ]; then
    ingress_annotations_yaml+="    nginx.ingress.kubernetes.io/proxy-body-size: $(yq_str "$INGRESS_PROXY_BODY_SIZE")"$'\n'
  fi

  tls_input=$(echo "$INGRESS_TLS_SECRETS" | sed 's/\r//g' | tr ',' '\n')
  mapfile -t tls_list < <(echo "$tls_input" | grep -v '^[[:space:]]*$' || true)

  iidx=0
  while IFS= read -r host; do
    host=$(echo "$host" | xargs)
    [ -z "$host" ] && continue
    ingress_hosts_yaml+="    - host: $(yq_str "$host")"$'\n'
    tls_secret=""
    if [ ${#tls_list[@]} -gt $iidx ]; then
      tls_secret=$(echo "${tls_list[$iidx]}" | xargs)
    fi
    if [ -n "$tls_secret" ]; then
      ingress_hosts_yaml+="      tlsSecret: $(yq_str "$tls_secret")"$'\n'
    fi
    iidx=$((iidx + 1))
  done < <(echo "$INGRESS_HOSTS" | sed 's/\r//g' | tr ',' '\n')

  while IFS= read -r path; do
    path=$(echo "$path" | xargs)
    [ -z "$path" ] && continue
    ingress_paths_yaml+="    - $(yq_str "$path")"$'\n'
  done < <(echo "$INGRESS_PATHS" | sed 's/\r//g' | tr ',' '\n')
fi

# ----- assemble the values file ----------------------------------------------

{
  echo "# Rendered by gateway-routing/render.sh — do not edit by hand."
  echo "gateway:"
  echo "  enabled: ${gateway_enabled}"
  if [ "$gateway_enabled" = "true" ]; then
    if [ -n "$parentrefs_yaml" ]; then
      echo "  parentRefs:"
      printf '%s' "$parentrefs_yaml"
    fi
    if [ -n "$hostnames_yaml" ]; then
      echo "  hostnames:"
      printf '%s' "$hostnames_yaml"
    fi
    if [ -n "$routes_yaml" ]; then
      echo "  routes:"
      printf '%s' "$routes_yaml"
    fi
  fi
  echo "ingress:"
  echo "  enabled: ${ingress_enabled}"
  if [ "$ingress_enabled" = "true" ]; then
    echo "  ingressClassName: $(yq_str "$INGRESS_CLASS_NAME")"
    echo "  pathType: $(yq_str "$INGRESS_PATH_TYPE")"
    echo "  tlsEnabled: $(yq_scalar "$INGRESS_TLS_ENABLED")"
    if [ -n "$ingress_annotations_yaml" ]; then
      echo "  annotations:"
      printf '%s' "$ingress_annotations_yaml"
    fi
    if [ -n "$ingress_hosts_yaml" ]; then
      echo "  hosts:"
      printf '%s' "$ingress_hosts_yaml"
    fi
    if [ -n "$ingress_paths_yaml" ]; then
      echo "  paths:"
      printf '%s' "$ingress_paths_yaml"
    fi
  fi
  echo "config:"
  echo "  enabled: $(yq_scalar "$CONFIGMAP_ENABLED")"
} > "$ROUTING_VALUES_FILE"

# ----- emit step outputs -----------------------------------------------------

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  # Randomized heredoc delimiters so host/section values can never collide with a
  # literal "EOF" and truncate or inject step output (repo convention).
  host_delim=$(dd if=/dev/urandom bs=15 count=1 status=none | base64)
  section_delim=$(dd if=/dev/urandom bs=15 count=1 status=none | base64)
  {
    echo "values-file=${ROUTING_VALUES_FILE}"
    echo "gateway-host-list<<${host_delim}"
    printf "%s" "$host_list"
    echo
    echo "${host_delim}"
    echo "gateway-section-names-list<<${section_delim}"
    printf "%s" "$section_names_list"
    echo
    echo "${section_delim}"
  } >> "$GITHUB_OUTPUT"
fi

echo "✅ [CHECKPOINT 1/2] Routing values rendered — mode: ${mode} (${host_count} host(s))"
echo "--- rendered values file (${ROUTING_VALUES_FILE}) ---"
cat "$ROUTING_VALUES_FILE"
