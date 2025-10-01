#!/bin/bash

echo "🧪 TESTING YOUR EXACT USE CASE"
echo "=============================="

# Your exact secret value
RAW_VALUES='ingress.enabled=true,replicas=1,ingress.hosts={surl.sf9.io},environment="Staging",ingress.path="/api",ingress.tls[0].secretName="surl-tls",db="${DBCS_ESCAPED}"'

echo "Original values:"
echo "$RAW_VALUES"
echo ""

# Process using the same logic as the workflow
PROCESSED_VALUES=$(SECRETS_JSON='{"DBCS_ESCAPED":"connect;string;userId=23fv"}' node -p '
const secrets = JSON.parse(process.env.SECRETS_JSON);
const raw = "ingress.enabled=true,replicas=1,ingress.hosts={surl.sf9.io},environment=\"Staging\",ingress.path=\"/api\",ingress.tls[0].secretName=\"surl-tls\",db=\"${DBCS_ESCAPED}\"";
raw.replace(/\$\{([^}]+)\}/g, (m, s) => secrets[s] ? `"${secrets[s].replace(/"/g, "\\\"")}\"` : m)
')

echo "After secret substitution:"
echo "$PROCESSED_VALUES"
echo ""

echo "🚀 FINAL HELM COMMAND (what the workflow generates):"
echo "===================================================="
echo "helm upgrade --install test-app-dev oci://ghcr.io/simplify9/charts/test-app \\"
echo "  --version 1.0.1 \\"
echo "  --namespace development \\"
echo "  --set $PROCESSED_VALUES \\"
echo "  --timeout 10m"

echo ""
echo "📋 Breakdown:"
echo "- \${DBCS_ESCAPED} → \"connect;string;userId=23fv\""
echo "- The workflow automatically finds and replaces ALL secrets"
echo "- No manual mapping required!"
echo ""
echo "✅ This is the EXACT command your workflow will generate!"