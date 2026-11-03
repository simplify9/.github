#!/usr/bin/env bash
# node_version <dir> [explicit]: the Node.js version verify sets up for a web/strapi repo, and where
# it came from, as "<version> <source>". Test what ships: the repo's own version, not a fixed one.
#   1. explicit (the caller's node-version input)
#   2. <dir>/.nvmrc or <dir>/.node-version (first line; anything setup-node accepts: 26, v26.1.0, lts/*)
#   3. the first `FROM node:<tag>` in <dir>/Dockerfile*: its leading version (node:26-alpine -> 26)
#   4. 24
node_version() {
  local dir="$1" explicit="${2:-}" f v
  if [ -n "${explicit}" ]; then echo "${explicit} input"; return; fi
  for f in .nvmrc .node-version; do
    if [ -f "${dir}/${f}" ]; then
      v="$(head -n 1 "${dir}/${f}" | tr -d '[:space:]')"
      if [ -n "${v}" ]; then echo "${v} ${f}"; return; fi
    fi
  done
  local name
  for f in "${dir}"/*; do  # by lowercased name: DockerFile too (Linux runners are case-sensitive)
    name="$(basename "${f}")"
    case "${name,,}" in dockerfile.dockerignore) continue ;; dockerfile | dockerfile.*) ;; *) continue ;; esac
    [ -f "${f}" ] || continue
    v="$(sed -n -E 's/^[[:space:]]*[Ff][Rr][Oo][Mm][[:space:]]+(--platform=[^[:space:]]+[[:space:]]+)?(docker\.io\/)?(library\/)?node:([0-9]+(\.[0-9]+)*).*/\4/p' "${f}" | head -n 1)"
    if [ -n "${v}" ]; then echo "${v} ${name}"; return; fi
  done
  echo "24 default"
}
if [ "${BASH_SOURCE[0]}" = "$0" ]; then node_version "$@"; fi
