#!/usr/bin/env bash
# detect_pm <dir>: print npm | yarn | yarn-berry | pnpm from the lockfile in <dir>.
# No lockfile: emit an ::error annotation and return 1.
detect_pm() {
  local dir="${1:-.}"
  if [ -f "${dir}/yarn.lock" ]; then
    if [ -f "${dir}/.yarnrc.yml" ]; then echo yarn-berry; else echo yarn; fi
  elif [ -f "${dir}/package-lock.json" ]; then echo npm
  elif [ -f "${dir}/pnpm-lock.yaml" ]; then echo pnpm
  else
    echo "::error title=[VERIFY] Install::no lockfile (yarn.lock, package-lock.json or pnpm-lock.yaml) in ${dir}; commit one so installs are reproducible"
    return 1
  fi
}
