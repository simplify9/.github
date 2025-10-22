# Next.js CI/CD Template Usage Guide

This guide shows how to use the `next-ci.yml` reusable workflow template for your Next.js projects deployed to **Cloudflare Workers**.

## ⚡ What is Cloudflare Workers?

Cloudflare Workers is a serverless platform that runs your code at the edge, closer to your users. Unlike Cloudflare Pages, Workers provides:

- **True SSR at the edge** - Server-side rendering happens globally
- **Better performance** - Lower latency and faster cold starts
- **Full Node.js compatibility** - Support for all Next.js features
- **Dynamic routing** - API routes, middleware, and dynamic pages work perfectly

## 🚀 Quick Start

### Basic Usage
```yaml
jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/next-ci.yml@main
    with:
      worker-name: 'my-nextjs-app'
    secrets: inherit
```

### Production Deployment with Custom Domain
```yaml
jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/next-ci.yml@main
    with:
      worker-name: 'my-nextjs-app'
      environment: 'production'
      worker-name-suffix: '-prod'
      custom-domain: 'app.example.com'
      fail-on-domain-error: true
      compatibility-flags: 'nodejs_compat'
    secrets: inherit
```

### Development with Environment Variables
```yaml
jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/next-ci.yml@main
    with:
      worker-name: 'my-nextjs-app'
      environment: 'development'
      worker-name-suffix: '-dev'
      environment-variables: '{"API_URL": "https://api-dev.example.com", "DEBUG": "true"}'
    secrets: inherit
```

## 🔧 Next.js Configuration for Workers

Your Next.js application should be configured for edge runtime compatibility:

### next.config.js
```javascript
/** @type {import('next').NextConfig} */
const nextConfig = {
  // Enable edge runtime for better Workers compatibility
  experimental: {
    runtime: 'edge',
  },
  
  // Optimize for Cloudflare Workers
  swcMinify: true,
  output: 'standalone',
  
  // Optional: Configure for better edge performance
  poweredByHeader: false,
  reactStrictMode: true,
  
  // Image optimization works with Cloudflare
  images: {
    domains: ['your-domain.com'],
  },
}

module.exports = nextConfig
```

### package.json
```json
{
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "lint": "next lint"
  },
  "dependencies": {
    "next": "^13.0.0",
    "react": "^18.0.0",
    "react-dom": "^18.0.0"
  },
  "devDependencies": {
    "@types/node": "^18.0.0"
  }
}
```

## 📋 Inputs

| Input | Description | Default | Required |
|-------|-------------|---------|----------|
| `worker-name` | Name of the Cloudflare Worker | - | ✅ |
| `environment` | Environment to deploy to | `development` | ❌ |
| `target-branch` | Target branch for deployment | `development` | ❌ |
| `node-version` | Node.js version | `18` | ❌ |
| `package-manager` | Package manager (npm/yarn/pnpm) | `npm` | ❌ |
| `build-command` | Build command | `npm run build` | ❌ |
| `output-directory` | Next.js build output directory | `.next` | ❌ |
| `worker-name-suffix` | Suffix for worker name | `` | ❌ |
| `compatibility-date` | Workers compatibility date | `2024-10-20` | ❌ |
| `compatibility-flags` | Workers compatibility flags | `nodejs_compat` | ❌ |
| `custom-routes` | Custom routes configuration | `` | ❌ |
| `environment-variables` | Environment variables (JSON) | `{}` | ❌ |
| `custom-domain` | Custom domain to configure | `` | ❌ |
| `fail-on-domain-error` | Fail on domain setup error | `false` | ❌ |
| `run-tests` | Run tests before deployment | `true` | ❌ |
| `test-command` | Test command | `npm test` | ❌ |
| `run-lint` | Run linting before deployment | `true` | ❌ |
| `lint-command` | Lint command | `npm run lint` | ❌ |

## 📤 Outputs

| Output | Description |
|--------|-------------|
| `deployment-url` | URL of the deployed worker |
| `worker-name` | Full worker name used for deployment |

## 🔐 Secrets

| Secret | Description | Required |
|--------|-------------|----------|
| `CLOUDFLARE_API_TOKEN` | Cloudflare API token | ❌* |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare account ID | ❌* |

*Uses organization secrets if not provided

## 📚 Examples

### Basic Deployment
```yaml
name: Deploy to Workers

on:
  push:
    branches: [main]

jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/next-ci.yml@main
    with:
      worker-name: 'my-nextjs-app'
    secrets: inherit
```

### Multi-Environment Setup
```yaml
name: Deploy Next.js App

on:
  push:
    branches: [main, develop]

jobs:
  deploy-dev:
    if: github.ref == 'refs/heads/develop'
    uses: simplify9/.github/.github/workflows/next-ci.yml@main
    with:
      worker-name: 'my-app'
      environment: 'development'
      worker-name-suffix: '-dev'
      environment-variables: '{"NODE_ENV": "development", "API_URL": "https://api-dev.example.com"}'
    secrets: inherit

  deploy-prod:
    if: github.ref == 'refs/heads/main'
    uses: simplify9/.github/.github/workflows/next-ci.yml@main
    with:
      worker-name: 'my-app'
      environment: 'production'
      worker-name-suffix: '-prod'
      custom-domain: 'app.example.com'
      environment-variables: '{"NODE_ENV": "production", "API_URL": "https://api.example.com"}'
    secrets: inherit
```

### Advanced Configuration
```yaml
jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/next-ci.yml@main
    with:
      worker-name: 'my-app'
      environment: 'production'
      package-manager: 'pnpm'
      compatibility-date: '2024-10-20'
      compatibility-flags: 'nodejs_compat'
      custom-domain: 'app.example.com'
      environment-variables: |
        {
          "DATABASE_URL": "${{ secrets.DATABASE_URL }}",
          "API_KEY": "${{ secrets.API_KEY }}",
          "NODE_ENV": "production"
        }
    secrets: inherit
```

## 🌟 Key Features

### ✅ **Full SSR Support**
- Server-side rendering at the edge
- Dynamic routes and API routes work perfectly
- Middleware support

### ✅ **Global Performance**
- Deployed to 200+ edge locations
- Ultra-low latency worldwide
- Fast cold starts

### ✅ **Environment Management**
- Support for multiple environments
- Secure environment variable handling
- Custom domain configuration

### ✅ **Developer Experience**
- Comprehensive logging and summaries
- Error handling and validation
- Test and lint integration

## 🔗 Related Documentation

- [Cloudflare Workers Deployment Guide](./CLOUDFLARE_DEPLOYMENT_GUIDE.md)
- [Next.js SSR Deployment Guide](./NEXT_SSR_DEPLOYMENT_GUIDE.md)
- [API CI/CD Usage](./API_CICD_USAGE.md)