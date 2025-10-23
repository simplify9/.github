# Next.js Cloudflare Workers CI/CD Template

This reusable workflow template deploys Next.js applications to Cloudflare Workers, based on your proven working workflow. It's modular, configurable, and handles everything from dependency installation to custom domain setup.

## 🚀 Quick Start

### Basic Usage (NPM)
```yaml
name: Deploy to Workers

on:
  push:
    branches: [staging, main]

jobs:
  deploy-staging:
    if: github.ref == 'refs/heads/staging'
    uses: simplify9/.github/.github/workflows/nextjs-workers-ci.yml@main
    with:
      environment: 'staging'
      wrangler-environment: 'staging'
    secrets: inherit

  deploy-production:
    if: github.ref == 'refs/heads/main'
    uses: simplify9/.github/.github/workflows/nextjs-workers-ci.yml@main
    with:
      environment: 'production'
      wrangler-environment: 'production'
    secrets: inherit
```

### Enhanced Configuration Example
```yaml
name: Deploy Next.js to Cloudflare Workers

on:
  push:
    branches: [main, staging]
  workflow_dispatch:

jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/nextjs-workers-ci.yml@main
    with:
      environment: ${{ github.ref == 'refs/heads/main' && 'production' || 'staging' }}
      
      # Build Configuration
      node-version: '20'
      package-manager: 'yarn'
      install-command: 'yarn install --frozen-lockfile'
      build-command: 'yarn build'
      cloudflare-build-command: 'npx @cloudflare/next-on-pages@1'
      
      # Path Configuration (for custom project structures)
      wrangler-config-path: 'configs/wrangler.toml'
      next-build-output: 'dist'
      workers-output-dir: 'dist/worker'
      worker-script-path: 'dist/worker/_worker.js'
      assets-ignore-file: 'dist/worker/.assetsignore'
      assets-ignore-content: |
        _worker.js
        *.map
        *.LICENSE.txt
      
      # Custom Domain Setup
      setup-custom-domain: 'true'
      worker-name: 'my-nextjs-app'
      domain-pattern: 'app.example.com/*'
      zone-name: 'example.com'
      
      # Quality Gates
      run-lint: 'true'
      run-tests: 'true'
      lint-command: 'yarn lint'
      test-command: 'yarn test'
    secrets: inherit
```

### Your Exact Workflow (Yarn)
```yaml
name: Deploy Next.js to Cloudflare Workers

on:
  push:
    branches: [staging, master]
  workflow_dispatch:

jobs:
  deploy-staging:
    if: github.ref == 'refs/heads/staging'
    uses: simplify9/.github/.github/workflows/nextjs-workers-ci.yml@main
    with:
      environment: 'staging'
      target-branch: 'staging'
      node-version: '20'
      package-manager: 'yarn'
      package-manager-cache: 'yarn'
      install-command: 'yarn install --frozen-lockfile'
      lint-command: 'yarn lint'
      build-command: 'yarn build'
      wrangler-environment: 'staging'
      setup-custom-domain: true
      worker-name: 'jibli-www-stg'
      domain-pattern: 'www-stg.jibli.com/*'
      zone-name: 'jibli.com'
    secrets: inherit

  deploy-production:
    if: github.ref == 'refs/heads/master'
    uses: simplify9/.github/.github/workflows/nextjs-workers-ci.yml@main
    with:
      environment: 'production'
      target-branch: 'master'
      node-version: '20'
      package-manager: 'yarn'
      package-manager-cache: 'yarn'
      install-command: 'yarn install --frozen-lockfile'
      lint-command: 'yarn lint'
      build-command: 'yarn build'
      wrangler-environment: 'production'
      setup-custom-domain: true
      worker-name: 'jibli-www'
      domain-pattern: 'jibli.com/*'
      zone-name: 'jibli.com'
    secrets: inherit
```

## 📋 Configuration Options

### Required Inputs
| Input | Description | Example |
|-------|-------------|---------|
| `environment` | Deployment environment | `staging`, `production` |

### Build Configuration
| Input | Description | Default | Example |
|-------|-------------|---------|---------|
| `node-version` | Node.js version | `20` | `18`, `20` |
| `package-manager` | Package manager | `npm` | `npm`, `yarn`, `pnpm` |
| `package-manager-cache` | Cache key | `npm` | `npm`, `yarn`, `pnpm` |
| `install-command` | Install command | `npm ci` | `yarn install --frozen-lockfile` |
| `lint-command` | Lint command | `npm run lint` | `yarn lint` |
| `build-command` | Build command | `npm run build` | `yarn build` |
| `cloudflare-build-command` | Cloudflare build command | `npx @cloudflare/next-on-pages` | `npx @cloudflare/next-on-pages@1` |

### Path Configuration
| Input | Description | Default | Example |
|-------|-------------|---------|---------|
| `wrangler-config-path` | Path to wrangler.toml | `wrangler.toml` | `configs/wrangler.toml` |
| `next-build-output` | Next.js build output directory | `.next` | `dist`, `out` |
| `workers-output-dir` | Workers build output directory | `.vercel/output/static` | `dist/worker` |
| `worker-script-path` | Path to worker script file | `.vercel/output/static/_worker.js` | `dist/worker/_worker.js` |
| `assets-ignore-file` | Path to assets ignore file | `.vercel/output/static/.assetsignore` | `dist/worker/.assetsignore` |
| `assets-ignore-content` | Content for assets ignore file | `_worker.js` | `_worker.js\n*.map` |

### Optional Features
| Input | Description | Default | Type |
|-------|-------------|---------|------|
| `run-lint` | Run linting | `true` | boolean |
| `run-tests` | Run tests | `false` | boolean |
| `test-command` | Test command | `npm test` | string |

### Wrangler Configuration
| Input | Description | Default | Example |
|-------|-------------|---------|---------|
| `wrangler-environment` | Environment from wrangler.toml | `''` | `staging`, `production` |

### Custom Domain Setup
| Input | Description | Default | Example |
|-------|-------------|---------|---------|
| `setup-custom-domain` | Enable domain setup | `false` | `true` |
| `worker-name` | Worker name for routes | `''` | `my-app-staging` |
| `domain-pattern` | Domain pattern | `''` | `app.example.com/*` |
| `zone-name` | Cloudflare zone | `''` | `example.com` |
| `fail-on-domain-error` | Fail on domain error | `false` | `true` |

## 🔧 Required Project Setup

### 1. wrangler.toml Configuration
```toml
name = "my-app"
main = ".vercel/output/static/_worker.js"
compatibility_date = "2024-10-20"
compatibility_flags = ["nodejs_compat"]

[env.staging]
name = "my-app-staging"

[env.production] 
name = "my-app-production"
```

### 2. Next.js Configuration
```javascript
/** @type {import('next').NextConfig} */
const nextConfig = {
  images: {
    unoptimized: true, // Required for Cloudflare Workers
  },
}

module.exports = nextConfig
```

### 3. Package Dependencies
```json
{
  "devDependencies": {
    "@cloudflare/next-on-pages": "^1.0.0",
    "wrangler": "^3.0.0"
  }
}
```

### 4. Required Secrets
- `CLOUDFLARE_API_TOKEN`
- `CLOUDFLARE_ACCOUNT_ID`

## 🏗️ Architecture

The template uses three modular composite actions:

1. **setup-nextjs**: Handles Node.js setup, dependencies, linting, testing
2. **build-nextjs-workers**: Builds Next.js and converts for Workers
3. **deploy-nextjs-workers**: Deploys to Workers and sets up custom domains

## 🌟 Key Features

### ✅ **Modular Design**
- Reusable composite actions
- Configurable for any project
- No vendor lock-in

### ✅ **Your Proven Workflow**
- Based on your working implementation
- Uses existing wrangler.toml configuration
- Supports custom domain routes

### ✅ **Comprehensive Validation**
- Build output verification
- Deployment confirmation
- Error handling with fallbacks

### ✅ **Flexible Package Managers**
- NPM, Yarn, PNPM support
- Custom install commands
- Proper caching configuration

## 🔗 Related Templates

- [Vite CI/CD](./vite-ci.yml) - For Vite apps to Cloudflare Pages
- [API CI/CD](./api-cicd.yml) - For .NET APIs

## 🐛 Troubleshooting

### Common Issues

1. **Build fails**: Check Next.js configuration has `images: { unoptimized: true }`
2. **Deploy fails**: Verify wrangler.toml exists and is valid
3. **Domain setup fails**: Check worker name and zone configuration

### Debug Mode
Enable debug output by setting the `fail-on-domain-error: true` input to see detailed error messages.