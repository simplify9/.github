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
eq nothing "24 default" "$(node_version "$(repo package.json '{}')")"

[ "${fails}" -eq 0 ] && echo "ALL PASS" || { echo "${fails} FAILED"; exit 1; }
