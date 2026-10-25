#!/usr/bin/env bash
# Validates the org Renovate presets with the pinned renovate-config-validator.
# Stack presets extend github>simplify9/.github//renovate/default, which is
# fetched from GitHub by the validator, so this needs network access.
# A full resolution check needs that file on the default branch, i.e. it only
# passes completely after merge.
# The validator checks schema and keys, not rule semantics; behaviour is proven
# by a Renovate dry run against real repos.
set -euo pipefail
cd "$(dirname "$0")/.."
npx --yes --package renovate@44.181.5 renovate-config-validator --strict renovate/*.json
