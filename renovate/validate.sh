#!/usr/bin/env bash
# Validates the org Renovate presets with the pinned renovate-config-validator.
# Stack presets extend github>simplify9/.github//renovate/default, which is
# fetched from GitHub by the validator, so this needs network access.
set -euo pipefail
cd "$(dirname "$0")/.."
npx --yes --package renovate@44.181.5 renovate-config-validator --strict renovate/*.json
