# 🚀 Cloudflare Pages Deployment - Cheat Sheet

## **Prerequisites (One-time setup)**
Ask DevOps to set these **Organization secrets**:
- `CLOUDFLARE_API_TOKEN`
- `CLOUDFLARE_ACCOUNT_ID`

## **Choose Your Template**

| App Type | Template | Use Case |
|----------|----------|----------|
| **Static Sites** (Vite/CRA) | `vite-ci.yml` | React, Vue, Svelte, vanilla JS |
| **Next.js Apps** | `next-ci.yml` | Next.js 15+ with SSR, API routes deployed to Cloudflare Workers |

---

## **Template 1: Static Sites (Most Common)**
Copy to your project: `.github/workflows/deploy.yml`

```yaml
name: Deploy to Cloudflare Pages
on:
  push:
    branches: [development, main]

jobs:
  deploy-dev:
    if: github.ref == 'refs/heads/development'
    uses: simplify9/.github/.github/workflows/vite-ci.yml@main
    with:
      project-name: YOUR_APP_NAME          # 👈 CHANGE THIS
      environment: development
      project-name-suffix: -dev
      build-directory: dist                # 👈 'dist' for Vite, 'build' for CRA

  deploy-prod:
    if: github.ref == 'refs/heads/main'
    uses: simplify9/.github/.github/workflows/vite-ci.yml@main
    with:
      project-name: YOUR_APP_NAME          # 👈 SAME NAME
      environment: production
      build-directory: dist
      run-tests: true
```

## **Required Changes**
1. **`project-name`**: Your app name (e.g., `customer-portal`, `admin-app`)
2. **`build-directory`**: 
   - Vite projects: `dist`
   - Create React App: `build`

## **Optional Additions**

**Custom domains:**
```yaml
custom-domain: yourapp.com               # Add this line
fail-on-domain-error: true              # Fail if domain setup fails
```

**Staging environment:**
```yaml
deploy-staging:
  if: github.ref == 'refs/heads/staging'
  uses: simplify9/.github/.github/workflows/vite-ci.yml@main
  with:
    project-name: YOUR_APP_NAME
    environment: staging
    project-name-suffix: -staging
    build-directory: dist
```

**Different package manager:**
```yaml
package-manager: yarn                    # or 'pnpm'
build-command: yarn build               # or 'pnpm build'
test-command: yarn test                 # or 'pnpm test'
```

## **What Gets Created**

| Branch Push | Creates Project | URL |
|-------------|----------------|-----|
| `development` | `your-app-dev` | Auto-generated + custom domain |
| `staging` | `your-app-staging` | Auto-generated + custom domain |
| `main` | `your-app` | Auto-generated + custom domain |

---

## **Quick Decision Guide**

### **Static Sites** → Use `vite-ci.yml`
- ✅ React, Vue, Svelte apps
- ✅ No server-side rendering needed
- ✅ Build output is just HTML/CSS/JS files
- ✅ Examples: Portfolio sites, dashboards, SPAs

### **Next.js Apps** → Use `next-ci.yml`
- ✅ **Next.js 15+ Compatible** with auto-detection
- ✅ Next.js with API routes
- ✅ Server-side rendering (SSR)
- ✅ Dynamic routes (`[id].js`)
- ✅ Middleware or authentication
- ✅ Static generation (SSG/ISR)
- ✅ Examples: E-commerce, blogs, web apps, static sites

📚 **Full Documentation**: See [NEXTJS_WORKERS_CI_USAGE.md](NEXTJS_WORKERS_CI_USAGE.md)

---

## **Template 2: Next.js Applications (Next.js 15+ Compatible)**

**Quick Setup - Zero Configuration:**
```yaml
name: Deploy Next.js to Cloudflare Workers

on:
  push:
    branches: [staging, main]

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

**Features:**
- ✅ **Auto-detects worker script paths** (Next.js 15 compatible)
- ✅ **Smart asset handling** (respects @cloudflare/next-on-pages)
- ✅ **CI/CD friendly domain setup** (no failures on existing routes)
- ✅ **Package manager flexibility** (npm, yarn, pnpm)

**Required Repository Secrets:**
- `CLOUDFLARE_API_TOKEN` - [Create here](https://dash.cloudflare.com/profile/api-tokens)
- `CLOUDFLARE_ACCOUNT_ID` - Found in Cloudflare Dashboard
```javascript
// next.config.js - Optimized for Cloudflare Workers
module.exports = {
  experimental: {
    runtime: 'edge',  // ✅ Enable edge runtime
  },
  output: 'standalone',
  swcMinify: true,
}
```

---

## **Common Issues**

❌ **"Build directory not found"**  
→ Fix: Use `build-directory: dist` for Vite projects

❌ **"Project creation failed"**  
→ Fix: Check project name isn't already taken

❌ **"Unauthorized"**  
→ Fix: Ask DevOps about organization secrets

## **Need More Examples?**
👉 [QUICK_START_README.md](./QUICK_START_README.md) - Complete guide with patterns