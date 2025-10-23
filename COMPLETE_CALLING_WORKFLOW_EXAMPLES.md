# 🚀 Next.js Cloudflare Workers - Complete Calling Workflow Examples

## 📋 **Required Secrets**

Your calling workflow repository needs these secrets configured:

| Secret | Description | How to Get |
|--------|-------------|------------|
| `CLOUDFLARE_API_TOKEN` | API token with Workers and DNS permissions | [Cloudflare Dashboard](https://dash.cloudflare.com/profile/api-tokens) |
| `CLOUDFLARE_ACCOUNT_ID` | Your Cloudflare account ID | [Cloudflare Dashboard](https://dash.cloudflare.com/) → Right sidebar |

### 🔑 **API Token Permissions**

Create a **Custom Token** with these permissions:
- **Zone:Zone:Read** (for your domain)
- **Zone:DNS:Edit** (for custom domains)
- **Account:Cloudflare Workers:Edit** (for deployments)

## 📝 **Complete Calling Workflow Examples**

### 1. **Simple Deployment (Minimal Configuration)**

```yaml
name: Deploy to Cloudflare Workers

on:
  push:
    branches: [main, staging]
  workflow_dispatch:

jobs:
  deploy-staging:
    if: github.ref == 'refs/heads/staging'
    uses: simplify9/.github/.github/workflows/next-ci.yml@main
    with:
      environment: 'staging'
      package-manager: 'yarn'
      install-command: 'yarn install --frozen-lockfile'
    secrets:
      CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
      CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}

  deploy-production:
    if: github.ref == 'refs/heads/main'
    uses: simplify9/.github/.github/workflows/next-ci.yml@main
    with:
      environment: 'production'
      package-manager: 'yarn'
      install-command: 'yarn install --frozen-lockfile'
    secrets:
      CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
      CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
```

### 2. **Advanced Configuration (All Features)**

```yaml
name: Next.js Cloudflare Workers CI/CD

on:
  push:
    branches: [main, staging, develop]
  pull_request:
    branches: [main]
  workflow_dispatch:
    inputs:
      environment:
        description: 'Environment to deploy to'
        required: true
        default: 'staging'
        type: choice
        options:
          - staging
          - production

jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/next-ci.yml@main
    with:
      # Environment Configuration
      environment: ${{ github.event.inputs.environment || (github.ref == 'refs/heads/main' && 'production' || 'staging') }}
      target-branch: ${{ github.ref_name }}
      
      # Build Configuration
      node-version: '20'
      package-manager: 'yarn'
      package-manager-cache: 'yarn'
      install-command: 'yarn install --frozen-lockfile'
      build-command: 'yarn build'
      cloudflare-build-command: 'npx @cloudflare/next-on-pages@1'
      
      # Next.js 15 Auto-Detection (recommended)
      auto-detect-worker-path: true
      
      # Quality Gates
      run-lint: true
      run-tests: ${{ github.event_name != 'workflow_dispatch' }}
      lint-command: 'yarn lint'
      test-command: 'yarn test'
      
      # Wrangler Configuration
      wrangler-environment: ${{ github.ref == 'refs/heads/main' && 'production' || 'staging' }}
      
      # Custom Domain Setup
      setup-custom-domain: true
      worker-name: 'my-nextjs-app'
      domain-pattern: ${{ github.ref == 'refs/heads/main' && 'app.example.com/*' || 'staging.example.com/*' }}
      zone-name: 'example.com'
      fail-on-domain-error: false
      skip-existing-routes: true  # CI/CD friendly
      
    secrets:
      CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
      CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
```

### 3. **Multi-Environment with Manual Approval**

```yaml
name: Deploy Next.js App

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  deploy-staging:
    uses: simplify9/.github/.github/workflows/next-ci.yml@main
    with:
      environment: 'staging'
      package-manager: 'yarn'
      install-command: 'yarn install --frozen-lockfile'
      setup-custom-domain: true
      domain-pattern: 'staging.myapp.com/*'
      zone-name: 'myapp.com'
    secrets:
      CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
      CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}

  deploy-production:
    needs: deploy-staging
    if: github.ref == 'refs/heads/main'
    environment: production  # Requires manual approval
    uses: simplify9/.github/.github/workflows/next-ci.yml@main
    with:
      environment: 'production'
      package-manager: 'yarn'
      install-command: 'yarn install --frozen-lockfile'
      setup-custom-domain: true
      domain-pattern: 'app.myapp.com/*'
      zone-name: 'myapp.com'
      fail-on-domain-error: true  # Strict for production
    secrets:
      CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
      CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
```

### 4. **Custom Project Structure**

```yaml
name: Deploy Custom Structure

on:
  push:
    branches: [main]

jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/next-ci.yml@main
    with:
      environment: 'production'
      package-manager: 'pnpm'
      install-command: 'pnpm install --frozen-lockfile'
      
      # Custom paths for non-standard project structure
      auto-detect-worker-path: false  # Disable auto-detection
      wrangler-config-path: 'configs/wrangler.toml'
      workers-output-dir: 'dist/cloudflare'
      worker-script-path: 'dist/cloudflare/_worker.js'
      assets-ignore-file: 'dist/cloudflare/.assetsignore'
      assets-ignore-content: |
        _worker.js
        *.map
        *.LICENSE.txt
        
    secrets:
      CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
      CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
```

### 5. **Your Exact Working Configuration**

```yaml
name: Deploy Next.js to Cloudflare Workers

on:
  push:
    branches: [staging, master]
  workflow_dispatch:

jobs:
  deploy-staging:
    if: github.ref == 'refs/heads/staging'
    uses: simplify9/.github/.github/workflows/next-ci.yml@main
    with:
      environment: 'staging'
      target-branch: 'staging'
      node-version: '20'
      package-manager: 'yarn'
      package-manager-cache: 'yarn'
      install-command: 'yarn install --frozen-lockfile'
      build-command: 'yarn build'
      cloudflare-build-command: 'npx @cloudflare/next-on-pages'
      auto-detect-worker-path: true  # Next.js 15 compatible
    secrets:
      CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
      CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}

  deploy-production:
    if: github.ref == 'refs/heads/master'
    uses: simplify9/.github/.github/workflows/next-ci.yml@main
    with:
      environment: 'production'
      target-branch: 'master'
      node-version: '20'
      package-manager: 'yarn'
      package-manager-cache: 'yarn'
      install-command: 'yarn install --frozen-lockfile'
      build-command: 'yarn build'
      cloudflare-build-command: 'npx @cloudflare/next-on-pages'
      auto-detect-worker-path: true  # Next.js 15 compatible
    secrets:
      CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
      CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
```

## 🔧 **Repository Setup**

1. **Add the secrets** to your repository:
   - Go to your repo → Settings → Secrets and variables → Actions
   - Add `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`

2. **Create your workflow file**:
   - Create `.github/workflows/deploy.yml` in your project
   - Copy one of the examples above
   - Customize for your needs

3. **Ensure you have a `wrangler.toml`** in your project root:
   ```toml
   name = "my-nextjs-app"
   main = ".vercel/output/static/_worker.js"
   compatibility_date = "2024-09-25"
   compatibility_flags = ["nodejs_compat"]

   [env.staging]
   name = "my-nextjs-app-staging"

   [env.production]
   name = "my-nextjs-app-production"
   ```

## ✅ **Template Features Summary**

- ✅ **Next.js 15 Compatible** with auto-detection
- ✅ **CI/CD Friendly** domain handling
- ✅ **Flexible Package Managers** (npm, yarn, pnpm)
- ✅ **Custom Domain Setup** with existing route detection
- ✅ **Quality Gates** (linting, testing)
- ✅ **Multi-environment** support
- ✅ **Configurable Paths** for custom project structures

Choose the example that best fits your needs and customize as required! 🚀