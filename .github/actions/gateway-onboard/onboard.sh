#!/usr/bin/env bash
# =============================================================================
# gateway-onboard / onboard.sh
# =============================================================================
# Ensures the Cilium Gateway has the HTTP/HTTPS listeners and cert-manager
# Certificates needed for each requested hostname, before the Helm deploy runs.
#
# This was previously ~380 lines of bash inlined in the workflow's
# "Auto-onboard gateway hostnames" step. Extracting it makes the logic
# reviewable/lintable and let us fix three correctness/robustness issues:
#
#   * TOCTOU race on the SHARED gateway (workflow review #1). The old code did
#     read-count -> capacity-check -> patch as three independent kubectl calls.
#     Two workflows onboarding to the same gateway concurrently could both read
#     62/64 and both append, overshooting the 64-listener hard limit; and the
#     HTTP-then-HTTPS two-patch sequence could leave a half-baked HTTP-only
#     listener. This version reads the gateway ONCE (capturing resourceVersion),
#     decides which listeners are missing, capacity-checks against that same
#     snapshot, and writes ALL needed listeners in a SINGLE `kubectl replace`.
#     `replace` enforces optimistic concurrency via resourceVersion, so a
#     competing writer causes a 409 Conflict and we retry with a fresh read.
#     The write is all-or-nothing, so no rollback bookkeeping is needed.
#
#   * Single JSON tool (review). Listener counting now uses `jq 'length'`
#     instead of shelling out to python3 — jq is already the JSON tool here.
#
#   * DNS tool portability (review). The cert pre-flight no longer assumes `dig`
#     exists; it falls back to getent/nslookup and skips the check gracefully
#     when no resolver tool is present (relevant on self-hosted runners).
#
# Behaviour is otherwise a faithful port: shared-listener mode (singular and
# per-host), namespace creation, the cert-manager Certificate, the failed-Order
# purge, and the optional cert-readiness wait are all unchanged.
#
# Inputs are read from the environment (set by action.yml).
# =============================================================================
set -euo pipefail

# ----- required inputs -------------------------------------------------------
: "${GATEWAY_NAME:?gateway-parent-name is required}"
: "${GATEWAY_NAMESPACE:?gateway-parent-namespace is required}"
DEPLOY_NAMESPACE="${DEPLOY_NAMESPACE:-}"
GATEWAY_CLASS_NAME="${GATEWAY_CLASS_NAME:-cilium}"
GATEWAY_CERT_ISSUER_NAME="${GATEWAY_CERT_ISSUER_NAME:-}"
GATEWAY_CERT_ISSUER_KIND="${GATEWAY_CERT_ISSUER_KIND:-ClusterIssuer}"
GATEWAY_CERT_WAIT="${GATEWAY_CERT_WAIT:-true}"
GATEWAY_CERT_WAIT_TIMEOUT="${GATEWAY_CERT_WAIT_TIMEOUT:-600}"
GATEWAY_SECTION_NAME="${GATEWAY_SECTION_NAME:-}"
HOST_LIST="${HOST_LIST:-}"
SECTION_NAMES_LIST="${SECTION_NAMES_LIST:-}"
MAX_LISTENERS="${MAX_LISTENERS:-64}"          # Gateway API hard limit (overridable for tests)
REPLACE_MAX_RETRIES="${REPLACE_MAX_RETRIES:-6}"

# ----- kubeconfig (decoded exactly once — review #5) -------------------------
if [ -z "${KUBECONFIG_DATA:-}" ]; then
  echo "kubeconfig secret is required for gateway auto-onboarding" >&2
  exit 1
fi
KCFG_PATH="$RUNNER_TEMP/kubeconfig"
# Remove the decoded kubeconfig when this script exits so the credential does
# not linger (matters on self-hosted/reused runners).
trap 'rm -f "$KCFG_PATH"' EXIT
if echo "$KUBECONFIG_DATA" | grep -q 'apiVersion:'; then
  printf "%s" "$KUBECONFIG_DATA" > "$KCFG_PATH"
elif printf "%s" "$KUBECONFIG_DATA" | base64 -d > "$KCFG_PATH" 2>/dev/null; then
  : # successfully decoded base64
else
  printf "%s" "$KUBECONFIG_DATA" > "$KCFG_PATH"
fi
chmod 600 "$KCFG_PATH"
export KUBECONFIG="$KCFG_PATH"

if [ -z "$(echo "$HOST_LIST" | tr -d '[:space:]\r\n')" ]; then
  echo "No gateway hosts were provided. Skipping gateway auto-onboarding."
  exit 0
fi

# ----- helpers ---------------------------------------------------------------
to_slug() { echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/-\+/-/g; s/^-//; s/-$//'; }
trim63()  { echo "$1" | cut -c1-63 | sed 's/-$//'; }

gateway_json() { kubectl -n "$GATEWAY_NAMESPACE" get gateway "$GATEWAY_NAME" -o json 2>/dev/null; }

listener_names() {
  kubectl -n "$GATEWAY_NAMESPACE" get gateway "$GATEWAY_NAME" \
    -o jsonpath='{range .spec.listeners[*]}{.name}{"\n"}{end}' 2>/dev/null || true
}

# Resolve a hostname to IPv4 addresses using whatever resolver tool exists.
# Prints addresses (one per line). Returns 2 when NO resolver tool is available.
resolve_ipv4() {
  local host="$1"
  if command -v dig >/dev/null 2>&1; then
    dig +short "$host" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -5
  elif command -v getent >/dev/null 2>&1; then
    getent ahostsv4 "$host" 2>/dev/null | awk '{print $1}' \
      | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort -u | head -5
  elif command -v nslookup >/dev/null 2>&1; then
    nslookup "$host" 2>/dev/null | awk '/^Address: /{print $2}' \
      | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -5
  else
    return 2
  fi
}

# ---------------------------------------------------------------------------
# Shared listener mode (singular): when gateway-section-name is explicitly set,
# the app attaches to a pre-existing shared/wildcard listener. Skip all per-host
# provisioning — just validate the named listener exists, then exit cleanly.
# ---------------------------------------------------------------------------
if [ -n "${GATEWAY_SECTION_NAME:-}" ]; then
  echo "Shared listener mode: gateway-section-name='${GATEWAY_SECTION_NAME}' is set."
  echo "Skipping per-host listener and cert provisioning."
  if ! listener_names | grep -Fxq "${GATEWAY_SECTION_NAME}"; then
    echo "❌ Shared listener '${GATEWAY_SECTION_NAME}' does not exist on gateway '${GATEWAY_NAME}' in '${GATEWAY_NAMESPACE}'." >&2
    echo "   Available listeners:" >&2
    listener_names | sed 's/^/     /' >&2
    exit 1
  fi
  echo "✅ Shared listener '${GATEWAY_SECTION_NAME}' confirmed present on gateway. Onboarding complete."
  exit 0
fi

kubectl create namespace "$GATEWAY_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
[ -n "$DEPLOY_NAMESPACE" ] && kubectl create namespace "$DEPLOY_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Create the Gateway with this host's listeners if it does not exist yet.
ensure_gateway_exists() {
  local host="$1" slug http_listener https_listener secret_name
  slug=$(to_slug "$host")
  http_listener=$(trim63 "http-${slug}")
  https_listener=$(trim63 "https-${slug}")
  secret_name="$slug"

  if kubectl -n "$GATEWAY_NAMESPACE" get gateway "$GATEWAY_NAME" >/dev/null 2>&1; then
    return 0
  fi

  kubectl apply -f <(printf '%s\n' \
    "apiVersion: gateway.networking.k8s.io/v1" \
    "kind: Gateway" \
    "metadata:" \
    "  name: ${GATEWAY_NAME}" \
    "  namespace: ${GATEWAY_NAMESPACE}" \
    "spec:" \
    "  gatewayClassName: ${GATEWAY_CLASS_NAME}" \
    "  listeners:" \
    "    - name: ${http_listener}" \
    "      protocol: HTTP" \
    "      port: 80" \
    "      hostname: ${host}" \
    "      allowedRoutes:" \
    "        namespaces:" \
    "          from: All" \
    "    - name: ${https_listener}" \
    "      protocol: HTTPS" \
    "      port: 443" \
    "      hostname: ${host}" \
    "      tls:" \
    "        mode: Terminate" \
    "        certificateRefs:" \
    "          - kind: Secret" \
    "            name: ${secret_name}" \
    "      allowedRoutes:" \
    "        namespaces:" \
    "          from: All")
}

# ---------------------------------------------------------------------------
# add_host_listeners: race-safe, atomic addition of a host's missing listeners.
#
# Reads the gateway ONCE per attempt (capturing resourceVersion), determines
# which of the HTTP/HTTPS listeners are missing (by name AND by the Gateway API
# hostname+port+protocol uniqueness triplet), capacity-checks against that same
# snapshot, appends all missing listeners with jq, and writes the result with a
# single `kubectl replace`. `replace` fails with a 409 Conflict if another
# writer changed the gateway since the read, so we retry with a fresh snapshot.
# All-or-nothing: HTTP+HTTPS land together or not at all.
# ---------------------------------------------------------------------------
add_host_listeners() {
  local host="$1" slug http_listener https_listener secret_name
  slug=$(to_slug "$host")
  http_listener=$(trim63 "http-${slug}")
  https_listener=$(trim63 "https-${slug}")
  secret_name="$slug"

  local attempt
  for (( attempt = 1; attempt <= REPLACE_MAX_RETRIES; attempt++ )); do
    local gw
    gw=$(gateway_json) || { echo "❌ Gateway '${GATEWAY_NAME}' not found in '${GATEWAY_NAMESPACE}'." >&2; return 1; }

    # Decide which listeners are missing, from THIS snapshot.
    local need_http=true need_https=true
    if jq -e --arg n "$http_listener" --arg h "$host" \
         '.spec.listeners[]? | select(.name==$n or (.hostname==$h and .protocol=="HTTP" and .port==80))' \
         >/dev/null <<<"$gw"; then
      need_http=false
    fi
    if jq -e --arg n "$https_listener" --arg h "$host" \
         '.spec.listeners[]? | select(.name==$n or (.hostname==$h and .protocol=="HTTPS" and .port==443))' \
         >/dev/null <<<"$gw"; then
      need_https=false
    fi

    local needed=0
    [ "$need_http" = true ] && needed=$((needed + 1))
    [ "$need_https" = true ] && needed=$((needed + 1))
    if [ "$needed" -eq 0 ]; then
      echo "Both listeners for '${host}' already present; nothing to add."
      return 0
    fi

    # Capacity pre-flight against the same snapshot (review #1: no separate read).
    local current
    current=$(jq '.spec.listeners | length' <<<"$gw")
    if (( current + needed > MAX_LISTENERS )); then
      echo "❌ GATEWAY CAPACITY ERROR: '${GATEWAY_NAME}' in '${GATEWAY_NAMESPACE}' currently has ${current}/${MAX_LISTENERS} listeners." >&2
      echo "   Adding ${needed} listener(s) for '${host}' would reach $((current + needed)) — exceeding the hard Gateway API limit of ${MAX_LISTENERS}." >&2
      echo "   ACTION REQUIRED: Prune stale listeners from the gateway before redeploying." >&2
      # shellcheck disable=SC2028  # the \n is intentional literal text in a copy-pasteable kubectl hint
      echo "   Run: kubectl get gateway ${GATEWAY_NAME} -n ${GATEWAY_NAMESPACE} -o jsonpath='{range .status.listeners[*]}{.name}: attachedRoutes={.attachedRoutes}{\"\\n\"}{end}'" >&2
      echo "   Remove any listener with attachedRoutes=0 that has no active HTTPRoute." >&2
      exit 1
    fi

    # Build the new object by appending the missing listeners.
    local new
    new=$(jq \
      --argjson need_http "$need_http" --argjson need_https "$need_https" \
      --arg http_name "$http_listener" --arg https_name "$https_listener" \
      --arg host "$host" --arg secret "$secret_name" '
      .spec.listeners += (
        (if $need_http then [{
          name: $http_name, protocol: "HTTP", port: 80, hostname: $host,
          allowedRoutes: { namespaces: { from: "All" } }
        }] else [] end)
        +
        (if $need_https then [{
          name: $https_name, protocol: "HTTPS", port: 443, hostname: $host,
          tls: { mode: "Terminate", certificateRefs: [{ kind: "Secret", name: $secret }] },
          allowedRoutes: { namespaces: { from: "All" } }
        }] else [] end)
      )' <<<"$gw")

    # `kubectl replace` requires the resourceVersion (present in $gw) and rejects
    # the write with a 409 Conflict if the gateway changed since we read it.
    local err
    if err=$(kubectl replace -f - <<<"$new" 2>&1); then
      echo "✅ Added ${needed} listener(s) for '${host}' (HTTP=${need_http}, HTTPS=${need_https}); ${current} -> $((current + needed))/${MAX_LISTENERS}."
      return 0
    fi
    if echo "$err" | grep -qiE 'conflict|please apply your changes to the latest version|object has been modified'; then
      echo "⚠️  Conflict adding listeners for '${host}' (attempt ${attempt}/${REPLACE_MAX_RETRIES}); another writer updated the gateway. Retrying with a fresh read..."
      sleep "$attempt"
      continue
    fi
    echo "❌ Failed to add listeners for '${host}': ${err}" >&2
    return 1
  done

  echo "❌ Exhausted ${REPLACE_MAX_RETRIES} retries adding listeners for '${host}' due to repeated conflicts." >&2
  return 1
}

# Parse per-hostname section names aligned with HOST_LIST.
# Empty array (legacy mode) means every host runs in dedicated mode.
mapfile -t _per_host_sections <<< "${SECTION_NAMES_LIST:-}"
_host_idx=0

while IFS= read -r host; do
  host=$(echo "$host" | xargs)
  [ -z "$host" ] && continue

  # Resolve the section name for this specific host position.
  _per_host_sn=""
  if [ "${#_per_host_sections[@]}" -gt 0 ] && [ "$_host_idx" -lt "${#_per_host_sections[@]}" ]; then
    _per_host_sn=$(echo "${_per_host_sections[$_host_idx]}" | xargs)
  fi
  _host_idx=$((_host_idx + 1))

  if [ -n "$_per_host_sn" ]; then
    # Shared listener mode for this host: validate the named listener exists.
    echo "Shared listener mode for '${host}': section-name='${_per_host_sn}'."
    if ! listener_names | grep -Fxq "${_per_host_sn}"; then
      echo "❌ Shared listener '${_per_host_sn}' does not exist on gateway '${GATEWAY_NAME}' in '${GATEWAY_NAMESPACE}' for host '${host}'." >&2
      echo "   Available listeners:" >&2
      listener_names | sed 's/^/     /' >&2
      exit 1
    fi
    echo "✅ Shared listener '${_per_host_sn}' confirmed for '${host}'."
    continue
  fi

  slug=$(to_slug "$host")
  cert_name="$slug"

  ensure_gateway_exists "$host"

  # Read cert readiness once — shared by the DNS pre-flight and the Order purge.
  cert_ready_now=$(kubectl get certificate "${cert_name}" -n "${GATEWAY_NAMESPACE}" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")

  # ---------------------------------------------------------------------------
  # DNS pre-flight: only runs when the cert is not already Ready. A valid cert
  # means no issuance is needed, so DNS reachability is irrelevant. When the cert
  # IS absent/stuck, a proxy or wrong A record makes cert-manager's HTTP-01
  # self-check hang for the full timeout; fail fast instead. Skips gracefully if
  # no resolver tool (dig/getent/nslookup) is available on the runner.
  # ---------------------------------------------------------------------------
  if [ "${cert_ready_now}" != "True" ]; then
    gateway_ip=$(kubectl -n "${GATEWAY_NAMESPACE}" get gateway "${GATEWAY_NAME}" \
      -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "")
    if [ -n "${gateway_ip}" ]; then
      resolve_rc=0
      resolved=$(resolve_ipv4 "$host") || resolve_rc=$?
      if [ "$resolve_rc" -eq 2 ]; then
        echo "⚠️  No DNS resolver tool (dig/getent/nslookup) on this runner — skipping DNS pre-flight for '${host}'."
      elif [ -z "${resolved}" ]; then
        echo "❌ DNS pre-flight failed: '${host}' has no A record." >&2
        echo "   Create an A record: ${host} → ${gateway_ip}" >&2
        exit 1
      elif ! echo "${resolved}" | grep -Fxq "${gateway_ip}"; then
        echo "❌ DNS pre-flight failed: '${host}' does not resolve to the gateway IP." >&2
        echo "   Resolved to: $(echo "${resolved}" | tr '\n' ' ')" >&2
        echo "   Gateway IP:  ${gateway_ip} (${GATEWAY_NAME} in ${GATEWAY_NAMESPACE})" >&2
        echo "   HTTP-01 ACME requires DNS to point directly to the gateway — not through a proxy." >&2
        echo "   If using Cloudflare: set the record to DNS-only mode (grey cloud) for this hostname." >&2
        exit 1
      else
        echo "✅ DNS pre-flight passed: '${host}' → ${gateway_ip}"
      fi
    fi
  fi

  kubectl apply -f <(printf '%s\n' \
    "apiVersion: cert-manager.io/v1" \
    "kind: Certificate" \
    "metadata:" \
    "  name: ${cert_name}" \
    "  namespace: ${GATEWAY_NAMESPACE}" \
    "spec:" \
    "  secretName: ${cert_name}" \
    "  issuerRef:" \
    "    name: ${GATEWAY_CERT_ISSUER_NAME}" \
    "    kind: ${GATEWAY_CERT_ISSUER_KIND}" \
    "  dnsNames:" \
    "    - ${host}")

  # Purge any failed ACME Orders so cert-manager retries immediately rather than
  # waiting out exponential backoff. Only errored/invalid Orders are removed.
  if [ "${cert_ready_now}" != "True" ]; then
    orders_output=$(kubectl get orders -n "${GATEWAY_NAMESPACE}" \
      -l "cert-manager.io/certificate-name=${cert_name}" \
      -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.state}{"\n"}{end}' \
      2>/dev/null || echo "")
    while IFS=$'\t' read -r order_name order_state; do
      [ -z "$order_name" ] && continue
      case "$order_state" in
        errored|invalid)
          echo "⚠️  Purging failed ACME Order '${order_name}' (state: ${order_state}) — cert-manager will retry immediately."
          kubectl delete order "${order_name}" -n "${GATEWAY_NAMESPACE}" --ignore-not-found
          ;;
      esac
    done <<< "${orders_output}"
  fi

  # Atomically add the host's missing HTTP/HTTPS listeners (race-safe).
  add_host_listeners "$host"

  if [ "$GATEWAY_CERT_WAIT" = "true" ]; then
    kubectl wait --for=condition=Ready=True "certificate/${cert_name}" \
      -n "$GATEWAY_NAMESPACE" --timeout="${GATEWAY_CERT_WAIT_TIMEOUT}s"
  fi
done < <(printf "%s" "$HOST_LIST")

echo "✅ Gateway hostnames onboarded — PASSED"
