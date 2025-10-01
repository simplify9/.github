#!/bin/bash

echo "🔬 COMPREHENSIVE TEST: Secret Passing in Reusable Workflows"
echo "==========================================================="

echo ""
echo "❓ QUESTION: Can we access calling workflow secrets in reusable workflow?"
echo ""

# Simulate what GitHub Actions does
echo "1. CALLING WORKFLOW (your workflow):"
echo "   secrets:"
echo "     DBCS_ESCAPED: \${{ secrets.DBCS_ESCAPED }}"
echo ""

echo "2. REUSABLE WORKFLOW receives:"
echo "   \${{ toJson(secrets) }} would contain:"
echo '   {"DBCS_ESCAPED":"connect;string;userId=23fv","kubeconfig":"base64-encoded-config",...}'
echo ""

echo "3. RAW VALUES input:"
RAW_VALUES='ingress.enabled=true,db="${DBCS_ESCAPED}"'
echo "   $RAW_VALUES"
echo ""

echo "4. NODE.JS PROCESSING:"
RESULT=$(SECRETS_JSON='{"DBCS_ESCAPED":"connect;string;userId=23fv"}' node -e '
const secrets = JSON.parse(process.env.SECRETS_JSON);
const rawValues = process.argv[1];
const result = rawValues.replace(/\$\{([^}]+)\}/g, (match, secretName) => {
  console.error(`  - Found variable: ${secretName}`);
  if (secrets[secretName]) {
    console.error(`  - Secret exists: ${secretName} = ${secrets[secretName]}`);
    return `"${secrets[secretName]}"`;
  } else {
    console.error(`  - Secret NOT found: ${secretName}`);
    return match;
  }
});
console.log(result);
' "$RAW_VALUES" 2>&1)

echo "$RESULT"
echo ""

echo "5. FINAL RESULT:"
FINAL=$(echo "$RESULT" | tail -1)
echo "   $FINAL"
echo ""

echo "🤔 POTENTIAL ISSUES:"
echo "- If secrets aren't properly passed to reusable workflow"
echo "- If \${{ toJson(secrets) }} doesn't include custom secrets"
echo "- If GitHub Actions has restrictions on secret access"
echo ""

echo "💡 LET'S TEST THE FUNDAMENTAL ASSUMPTION:"
echo "We need to verify that secrets passed to a reusable workflow"
echo "are available in the \${{ toJson(secrets) }} context."