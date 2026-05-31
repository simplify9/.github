#!/usr/bin/env bash
set -euo pipefail

# GitHub Actions passes inputs as env vars too:
# INPUT_SERVICE_ACCOUNT_JSON, INPUT_PACKAGE_NAME, INPUT_AAB_PATH, etc.

echo "::notice title=🤖 [ANDROID] Upload to Google Play::Package: ${INPUT_PACKAGE_NAME:-unknown}, track: ${INPUT_TRACK:-internal}, AAB: ${INPUT_AAB_PATH:-unknown}"
echo "::group::🤖 [CHECKPOINT 1/2] Validate Credentials"

if [[ -z "${INPUT_SERVICE_ACCOUNT_JSON:-}" ]]; then
  echo "ERROR: input 'service_account_json' is required."
  exit 1
fi

# Write creds to a file inside container
CREDS_DIR="/tmp/creds"
mkdir -p "$CREDS_DIR"
CREDS_PATH="$CREDS_DIR/play.json"

# Preserve JSON exactly
printf '%s' "$INPUT_SERVICE_ACCOUNT_JSON" > "$CREDS_PATH"

# Basic validation (won't print secrets)
python - <<PY
import json, sys
p="${CREDS_PATH}"
try:
    json.load(open(p, "r", encoding="utf-8"))
    print("Credentials JSON: OK")
except Exception as e:
    print("ERROR: credentials JSON is invalid:", e, file=sys.stderr)
    sys.exit(2)
PY

echo "::endgroup::"
echo "::notice title=✅ [ANDROID] Credentials validated::Service account JSON is valid, proceeding to upload"

export GOOGLE_APPLICATION_CREDENTIALS="$CREDS_PATH"

# Delegate to Python script (args come from action.yml runs.args)
exec python /app/play_upload.py "$@"
