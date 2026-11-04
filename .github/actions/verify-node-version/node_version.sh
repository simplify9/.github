#!/usr/bin/env bash
# node_version <dir> [explicit]: the Node.js version verify sets up (web, strapi, react-native) and the
# React Native build workflows build with, and where it came from, as "<version> <source>". Test what ships: the repo's own version, not a fixed one.
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
  # By lowercased name: DockerFile too (Linux runners are case-sensitive). tr, not bash 4 case conversion: macOS
  # runners run this with /bin/bash 3.2.
  for f in "${dir}"/*; do
    name="$(basename "${f}")"
    case "$(printf '%s' "${name}" | tr '[:upper:]' '[:lower:]')" in dockerfile.dockerignore) continue ;; dockerfile | dockerfile.*) ;; *) continue ;; esac
    [ -f "${f}" ] || continue
    v="$(sed -n -E 's/^[[:space:]]*[Ff][Rr][Oo][Mm][[:space:]]+(--platform=[^[:space:]]+[[:space:]]+)?(docker\.io\/)?(library\/)?node:([0-9]+(\.[0-9]+)*).*/\4/p' "${f}" | head -n 1)"
    if [ -n "${v}" ]; then echo "${v} ${name}"; return; fi
  done
  echo "24 default"
}
# declared_mismatch <dir> <version>: "<file> <declared>" when the repo's .nvmrc or .node-version names
# a different major than <version>, the Node verify runs on; empty when it agrees, names no number
# (lts/*) or is absent. Only an explicit node-version input can disagree with the repo: then a PR that
# only bumps .nvmrc would be green without that Node ever running.
declared_mismatch() {
  local declared src want="${2#v}"
  read -r declared src < <(node_version "$1")
  case "${src}" in .nvmrc | .node-version) ;; *) return 0 ;; esac
  declared="${declared#v}"
  [[ "${declared%%.*}" =~ ^[0-9]+$ ]] || return 0
  [ "${declared%%.*}" = "${want%%.*}" ] || echo "${src} ${declared}"
}
if [ "${BASH_SOURCE[0]}" = "$0" ]; then node_version "$@"; fi
