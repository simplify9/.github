#!/usr/bin/env bash
# Network block for verify's end-to-end steps (sourced; tested by test_netblock.sh and
# test_netblock_docker.sh). Blocks outbound traffic for ONE process tree, not the machine:
# commands started with netblock_run run with group verify-offline, and iptables/ip6tables
# send that group's packets (`-m owner --gid-owner`) to chain VERIFY_NETBLOCK, which accepts
# loopback and the allow-listed hosts and rejects the rest. The runner agent keeps its own
# connection to GitHub. Needs root network control (sudo + iptables): GitHub-hosted runners.
#
#   netblock_hosts FILE       validated hosts of an allowed-hosts file, one per line
#   netblock_on [FILE]        (re)build the rules; allowed hosts are resolved once and pinned in /etc/hosts
#   netblock_run CMD...       run CMD blocked (same uid and env, group verify-offline)
#   netblock_off              lift the block for the group (rules kept; netblock_on restores it)
#   netblock_count            packets rejected since the last netblock_on
#   netblock_blocked          rejected destinations as ip:port (best effort, from the kernel log)

NETBLOCK_GROUP=verify-offline
NETBLOCK_CHAIN=VERIFY_NETBLOCK

_nb_sudo() { if [ "$(id -u)" = 0 ]; then echo ""; else echo sudo; fi; }

# netblock_hosts <file>: host names and IP literals, comments (#), blank lines and CRLF ignored.
# A missing file is an empty list. A line with a scheme, port, path or wildcard fails, naming it.
netblock_hosts() {
  local file="$1" n=0 bad=0 line host
  [ -f "${file}" ] || return 0
  while IFS= read -r line || [ -n "${line}" ]; do
    n=$((n + 1))
    host="${line%%#*}"
    host="${host//$'\r'/}"
    host="${host#"${host%%[![:space:]]*}"}"
    host="${host%"${host##*[![:space:]]}"}"
    [ -n "${host}" ] || continue
    if [[ "${host}" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)*$ ]] \
      || [[ "${host}" =~ ^[0-9A-Fa-f]*:[0-9A-Fa-f]*:[0-9A-Fa-f:]*$ ]]; then
      echo "${host}"
    else
      echo "::error title=[VERIFY] network::${file}:${n}: \"${host}\" is not a host name or IP (no scheme, port, path or wildcard)" >&2
      bad=1
    fi
  done < "${file}"
  return "${bad}"
}

netblock_on() {
  local file="${1:-}" sudo hosts host ips ip ipt allowed=0
  sudo="$(_nb_sudo)"
  hosts="$(netblock_hosts "${file}")" || return 1
  for ipt in iptables ip6tables; do
    if ! ${sudo} "${ipt}" -w -L OUTPUT -n >/dev/null 2>&1; then
      echo "::error title=[VERIFY] network::the network block needs root network control (a GitHub-hosted runner); ${ipt} is not usable here"
      return 1
    fi
  done
  getent group "${NETBLOCK_GROUP}" >/dev/null || ${sudo} groupadd "${NETBLOCK_GROUP}" || return 1
  for ipt in iptables ip6tables; do
    ${sudo} "${ipt}" -w -N "${NETBLOCK_CHAIN}" 2>/dev/null || ${sudo} "${ipt}" -w -F "${NETBLOCK_CHAIN}" || return 1
    ${sudo} "${ipt}" -w -Z "${NETBLOCK_CHAIN}" || return 1
    ${sudo} "${ipt}" -w -C OUTPUT -m owner --gid-owner "${NETBLOCK_GROUP}" -j "${NETBLOCK_CHAIN}" 2>/dev/null \
      || ${sudo} "${ipt}" -w -I OUTPUT 1 -m owner --gid-owner "${NETBLOCK_GROUP}" -j "${NETBLOCK_CHAIN}" || return 1
    ${sudo} "${ipt}" -w -A "${NETBLOCK_CHAIN}" -o lo -j ACCEPT || return 1
  done
  for host in ${hosts}; do
    if [[ "${host}" =~ ^[0-9.]+$ || "${host}" == *:* ]]; then
      ips="${host}"
    else
      # Resolved once; pinned in /etc/hosts so the app connects to exactly the addresses allowed here.
      # `|| true`: getent exits 2 for an unknown host, which errexit callers would die on silently.
      ips="$(getent ahosts "${host}" | awk '{print $1}' | sort -u || true)"
      if [ -z "${ips}" ]; then
        echo "::error title=[VERIFY] network::cannot resolve allowed host ${host}"
        return 1
      fi
    fi
    for ip in ${ips}; do
      ipt=iptables
      [[ "${ip}" == *:* ]] && ipt=ip6tables
      ${sudo} "${ipt}" -w -A "${NETBLOCK_CHAIN}" -d "${ip}" -j ACCEPT || return 1
      if [ "${ip}" != "${host}" ] && ! grep -qE "^${ip//./\\.}[[:space:]]+${host//./\\.}\$" /etc/hosts; then
        echo "${ip} ${host}" | ${sudo} tee -a /etc/hosts >/dev/null
      fi
    done
    allowed=$((allowed + 1))
  done
  for ipt in iptables ip6tables; do
    ${sudo} "${ipt}" -w -A "${NETBLOCK_CHAIN}" -m limit --limit 10/second --limit-burst 20 \
      -j LOG --log-prefix "VERIFY-NETBLOCK " || return 1
    ${sudo} "${ipt}" -w -A "${NETBLOCK_CHAIN}" -p tcp -j REJECT --reject-with tcp-reset || return 1
    ${sudo} "${ipt}" -w -A "${NETBLOCK_CHAIN}" -j REJECT || return 1
  done
  echo "::notice title=[VERIFY] network::outbound network blocked except loopback and ${allowed} allowed host(s)"
}

netblock_run() {
  if [ "$(id -u)" = 0 ]; then
    setpriv --reuid 0 --regid "${NETBLOCK_GROUP}" --clear-groups -- "$@"
  else
    sudo -E env "PATH=${PATH}" setpriv --reuid "$(id -u)" --regid "${NETBLOCK_GROUP}" --clear-groups -- "$@"
  fi
}

netblock_off() {
  local sudo ipt
  sudo="$(_nb_sudo)"
  for ipt in iptables ip6tables; do
    ${sudo} "${ipt}" -w -D OUTPUT -m owner --gid-owner "${NETBLOCK_GROUP}" -j "${NETBLOCK_CHAIN}" 2>/dev/null || true
  done
}

netblock_count() {
  local sudo ipt n total=0
  sudo="$(_nb_sudo)"
  for ipt in iptables ip6tables; do
    n="$(${sudo} "${ipt}" -w -L "${NETBLOCK_CHAIN}" -n -v -x 2>/dev/null | awk '$3 == "REJECT" {s += $1} END {print s + 0}')"
    total=$((total + n))
  done
  echo "${total}"
}

netblock_blocked() {
  { $(_nb_sudo) dmesg 2>/dev/null || true; } | awk '/VERIFY-NETBLOCK / {
      dst = ""; dpt = ""
      for (i = 1; i <= NF; i++) { if ($i ~ /^DST=/) dst = substr($i, 5); if ($i ~ /^DPT=/) dpt = substr($i, 5) }
      if (dst != "" && dpt != "") print (index(dst, ":") ? "[" dst "]" : dst) ":" dpt
    }' | sort -u
}
