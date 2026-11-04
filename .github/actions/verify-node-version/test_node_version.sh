#!/usr/bin/env bash
# Truth table for node_version.sh. Run: bash test_node_version.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "${here}/node_version.sh"
fails=0
eq() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: want [$2] got [$3]"; fails=$((fails + 1)); fi; }
repo() { local d; d="$(mktemp -d)"; while [ $# -gt 0 ]; do printf '%b' "$2" > "${d}/$1"; shift 2; done; echo "${d}"; }

eq explicit_wins "20 input" "$(node_version "$(repo .nvmrc '26\n')" 20)"
eq nvmrc "26 .nvmrc" "$(node_version "$(repo .nvmrc '26\n' Dockerfile 'FROM node:24-alpine\n')")"
eq nvmrc_full_version "v22.11.0 .nvmrc" "$(node_version "$(repo .nvmrc ' v22.11.0 \n')")"
eq nvmrc_alias "lts/* .nvmrc" "$(node_version "$(repo .nvmrc 'lts/*\n')")"
eq node_version_file "26 .node-version" "$(node_version "$(repo .node-version '26\n')")"
eq empty_nvmrc_falls_through "26 Dockerfile" "$(node_version "$(repo .nvmrc '\n' Dockerfile 'FROM node:26-alpine AS build\n')")"
eq dockerfile_tag "26 Dockerfile" "$(node_version "$(repo Dockerfile '# build\nFROM node:26-alpine AS build\nFROM nginx:stable-alpine\n')")"
eq dockerfile_lowercase_as_platform "20.11 Dockerfile" "$(node_version "$(repo Dockerfile 'from --platform=linux/amd64 docker.io/library/node:20.11-bullseye as b\n')")"
eq dockerfile_variant_only "22 Dockerfile.staging" "$(node_version "$(repo Dockerfile.staging 'FROM node:22-alpine\n')")"
eq dockerfile_non_numeric_tag "24 default" "$(node_version "$(repo Dockerfile 'FROM node:lts-alpine\n')")"
eq dockerfile_other_base "24 default" "$(node_version "$(repo Dockerfile 'FROM nginx:1.27\n')")"
eq dockerfile_any_case "20 DockerFile" "$(node_version "$(repo DockerFile 'FROM node:20-alpine\n')")"
eq nothing "24 default" "$(node_version "$(repo package.json '{}')")"
# macOS runners (verify's ios job, ios-build.yml) run this with /bin/bash 3.2: no bash 4 syntax.
# The whole file also passes there: /bin/bash test_node_version.sh on a Mac.
eq bash32_safe "" "$(grep -nE '\$\{[A-Za-z_]+(,,?|\^\^?)\}|mapfile|readarray|declare -A|local -A' "${here}/node_version.sh")"


# declared_mismatch <dir> <version>: "<file> <declared>" when the repo's .nvmrc/.node-version names a
# different major than the Node verify runs on; empty when it agrees, names no number, or is absent.
eq mismatch_nvmrc ".nvmrc 26" "$(declared_mismatch "$(repo .nvmrc '26\n')" 24)"
eq mismatch_node_version_file ".node-version 22" "$(declared_mismatch "$(repo .node-version '22\n')" 24.11)"
eq same_major_full_version "" "$(declared_mismatch "$(repo .nvmrc ' v24.11.0 \n')" 24)"
eq same_major_v_prefixed_input "" "$(declared_mismatch "$(repo .nvmrc '24\n')" v24.1.0)"
eq alias_not_compared "" "$(declared_mismatch "$(repo .nvmrc 'lts/*\n')" 24)"
eq dockerfile_not_a_declaration "" "$(declared_mismatch "$(repo Dockerfile 'FROM node:26-alpine\n')" 24)"
eq no_file "" "$(declared_mismatch "$(repo package.json '{}')" 24)"

# React Native: the build workflows (android-build.yml, ios-build.yml) and verify resolve Node the same
# way, through this action (the node-version input, else .nvmrc / .node-version, else 24). So a Node bump
# in the app is built AND tested on the new Node, and what verify tests is what ships.
wf="${here}/../../workflows"
build_default() { awk '/^      node-version:$/ {f = 1} f && /^        default:/ {gsub(/[" ]/, ""); sub(/default:/, ""); print; exit}' "$1"; }
setup_node_versions() { awk '/uses: actions\/setup-node/ {n = NR} n && NR <= n + 3 && /node-version:/ {sub(/.*node-version: /, ""); print; n = 0}' "$1" | sort -u; }
for f in android-build.yml ios-build.yml; do
  eq "${f}_node_input_default_empty" "" "$(build_default "${wf}/${f}")"
done
for f in android-build.yml ios-build.yml verify.yml; do
  eq "${f}_every_setup_node_reads_the_resolver" "\${{ steps.node.outputs.version }}" "$(setup_node_versions "${wf}/${f}")"
  case "$(grep -c 'uses: simplify9/.github/.github/actions/verify-node-version@main' "${wf}/${f}")" in
    0) eq "${f}_uses_the_resolver" "verify-node-version" "missing" ;; *) eq "${f}_uses_the_resolver" ok ok ;;
  esac
done
eq no_fixed_node_fallback_left "" "$(grep -ho "inputs.node-version || '[^']*'" "${wf}/android-build.yml" "${wf}/ios-build.yml" "${wf}/verify.yml")"

[ "${fails}" -eq 0 ] && echo "ALL PASS" || { echo "${fails} FAILED"; exit 1; }
