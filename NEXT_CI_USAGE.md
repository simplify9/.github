# Next.js CI/CD Template Usage Guide

This guide shows how to use the `next-ci.yml` reusable workflow template for your Next.js projects deployed to Cloudflare Pages.

## 🚀 Quick Start

### Basic Usage
```yaml
jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/next-ci.yml@main
    with:
      project-name: 'my-nextjs-app'
    secrets: inherit
```

### Production Deployment with Custom Domain
```yaml
jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/next-ci.yml@main
    with:
      project-name: 'my-nextjs-app'
      environment: 'production'
      target-branch: 'main'
      custom-domain: 'app.example.com'
      fail-on-domain-error: true
    secrets: inherit
```

## Key Differences from Vite CI

1. **Build Directory**: Default is `out` (Next.js static export default)
2. **Static Export**: Added support for `next export` command
3. **Linting**: Added optional lint step (common in Next.js projects)
4. **Build Process**: Separated build and export steps for better control

## Next.js Configuration

For Cloudflare Pages deployment, your Next.js application should be configured for static export:

### next.config.js
```javascript
/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'export',
  trailingSlash: true,
  images: {
    unoptimized: true
  }
}

module.exports = nextConfig
```

### package.json
```json
{
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "export": "next export",
    "start": "next start",
    "lint": "next lint"
  }
}
```

## Inputs

| Input | Description | Default | Required |
|-------|-------------|---------|----------|
| `project-name` | Base Cloudflare project name | - | ✅ |
| `environment` | Environment to deploy to | `development` | ❌ |
| `target-branch` | Target branch for deployment | `development` | ❌ |
| `node-version` | Node.js version | `18` | ❌ |
| `package-manager` | Package manager (npm/yarn/pnpm) | `npm` | ❌ |
| `build-command` | Build command | `npm run build` | ❌ |
| `build-directory` | Build output directory | `out` | ❌ |
| `static-export` | Use Next.js static export | `true` | ❌ |
| `export-command` | Export command | `npx next export` | ❌ |
| `project-name-suffix` | Suffix for project name | `` | ❌ |
| `custom-domain` | Custom domain to configure | `` | ❌ |
| `fail-on-domain-error` | Fail on domain setup error | `false` | ❌ |
| `run-tests` | Run tests before deployment | `true` | ❌ |
| `test-command` | Test command | `npm test` | ❌ |
| `run-lint` | Run linting before deployment | `true` | ❌ |
| `lint-command` | Lint command | `npm run lint` | ❌ |

## Outputs

| Output | Description |
|--------|-------------|
| `deployment-url` | URL of the deployed application |
| `project-name` | Full project name used for deployment |

## Secrets

| Secret | Description | Required |
|--------|-------------|----------|
| `CLOUDFLARE_API_TOKEN` | Cloudflare API token | ❌* |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare account ID | ❌* |

*Uses organization secrets if not provided

## Examples

### Basic Deployment
```yaml
jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/next-ci.yml@main
    with:
      project-name: 'my-app'
    secrets: inherit
```

### Production with Custom Domain
```yaml
jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/next-ci.yml@main
    with:
      project-name: 'my-app'
      environment: 'production'
      target-branch: 'main'
      custom-domain: 'app.example.com'
      fail-on-domain-error: true
    secrets: inherit
```

### Development with Different Build Setup
```yaml
jobs:
  deploy:
    uses: simplify9/.github/.github/workflows/next-ci.yml@main
    with:
      project-name: 'my-app'
      environment: 'development'
      project-name-suffix: '-dev'
      build-directory: 'dist'
      static-export: false
      package-manager: 'pnpm'
    secrets: inherit
```