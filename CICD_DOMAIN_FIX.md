# 🔄 CI/CD Domain Fix - Custom Domain Route Handling

## 🎯 **Problem Solved**

Fixed custom domain setup failures in CI/CD environments where DNS routes already exist from previous deployments.

## 🐛 **Previous Issue**

**Symptom**: Custom domain setup would fail on subsequent deployments
```bash
❌ Failed to add custom domain route
Response: {"errors":[{"message":"Route already exists"}]}
```

**Root Cause**: Template always tried to create new routes without checking if they already existed.

## ✅ **Solution Applied**

### 1. **Smart Route Detection**
```bash
# Now checks for existing routes BEFORE creating new ones
🔍 Checking for existing routes...
✅ Route already exists for pattern: app.example.com/*
🔄 Skipping route creation (already configured)
```

### 2. **CI/CD-Friendly Parameters**
```yaml
# New parameter for robust CI/CD
skip-existing-routes: true  # Default: enabled for CI/CD
fail-on-domain-error: false # Default: don't fail entire deployment
```

### 3. **Enhanced Logic Flow**
1. ✅ **Check existing routes** via Cloudflare API
2. ✅ **Skip creation if exists** (CI/CD friendly)
3. ✅ **Create only if needed** (new deployments)
4. ✅ **Graceful error handling** (parse "already exists" errors)

## 🚀 **Template Usage**

### Zero Configuration (Recommended)
```yaml
uses: simplify9/.github/.github/workflows/nextjs-workers-ci.yml@main
with:
  environment: 'production'
  setup-custom-domain: true
  domain-pattern: 'app.example.com/*'
  zone-name: 'example.com'
  # skip-existing-routes: true (default)
  # fail-on-domain-error: false (default)
secrets: inherit
```

### Custom Control
```yaml
uses: simplify9/.github/.github/workflows/nextjs-workers-ci.yml@main
with:
  environment: 'production'
  setup-custom-domain: true
  domain-pattern: 'app.example.com/*'
  zone-name: 'example.com'
  skip-existing-routes: false    # Force route recreation
  fail-on-domain-error: true     # Fail on any domain error
secrets: inherit
```

## 🔍 **Behavior Matrix**

| Scenario | `skip-existing-routes` | `fail-on-domain-error` | Result |
|----------|----------------------|----------------------|---------|
| **First deployment** | `true` | `false` | ✅ Creates route |
| **Subsequent deployment** | `true` | `false` | ✅ Skips (route exists) |
| **Route creation fails** | `true` | `false` | ✅ Continues deployment |
| **Route creation fails** | `true` | `true` | ❌ Fails deployment |
| **Force recreation** | `false` | `false` | ⚠️ May get "exists" error, continues |

## 🎯 **CI/CD Benefits**

- ✅ **Idempotent deployments**: Same workflow can run multiple times
- ✅ **No manual cleanup**: Routes don't need manual deletion between deployments  
- ✅ **Robust error handling**: Graceful handling of edge cases
- ✅ **Zero configuration**: Works out-of-the-box for most CI/CD scenarios
- ✅ **Customizable**: Can be configured for specific needs

## 🔧 **Technical Details**

### Route Existence Check
```bash
# Query existing routes for the worker
EXISTING_ROUTES=$(curl -s -X GET \
  "https://api.cloudflare.com/client/v4/accounts/$ACCOUNT_ID/workers/scripts/$WORKER_NAME/routes")

# Check if our pattern already exists
ROUTE_EXISTS=$(echo "$EXISTING_ROUTES" | jq -r \
  ".result[]? | select(.pattern == \"$DOMAIN_PATTERN\") | .id")
```

### Smart Error Parsing
```bash
# Parse error messages for "already exists" scenarios
ERROR_MESSAGE=$(echo "$RESPONSE" | jq -r '.errors[]?.message // ""')
if echo "$ERROR_MESSAGE" | grep -q -i "already exists\|duplicate"; then
  echo "✅ Treating as success since route is configured"
fi
```

## ✨ **Result**

The template now supports **continuous deployment** with custom domains:

1. ✅ **First run**: Creates custom domain routes
2. ✅ **Subsequent runs**: Detects existing routes, skips creation  
3. ✅ **Error resilience**: Handles edge cases gracefully
4. ✅ **Zero maintenance**: No manual cleanup between deployments

**Perfect for CI/CD pipelines that deploy multiple times! 🚀**